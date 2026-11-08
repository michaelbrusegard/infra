"""Verify a built provider against a disposable, bootstrapped local server."""

import argparse
import base64
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import Request, urlopen
from urllib.parse import urlparse


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--provider", required=True, type=Path)
parser.add_argument("--work-dir", required=True, type=Path)
parser.add_argument("--endpoint", default="http://127.0.0.1:18081")
args = parser.parse_args()
assert urlparse(args.endpoint).hostname in {"127.0.0.1", "localhost"}, "local test server required"
args.work_dir.mkdir(parents=True, exist_ok=False)
auth = base64.b64encode(b"admin:acctest123").decode()


def jmap(method, **params):
    body = {"using": ["urn:ietf:params:jmap:core"], "methodCalls": [
        [method, {"accountId": "d333333", **params}, "0"]
    ]}
    req = Request(args.endpoint + "/jmap", json.dumps(body).encode(), {
        "Authorization": "Basic " + auth, "Content-Type": "application/json"
    })
    with urlopen(req, timeout=90) as response:
        name, result, _ = json.load(response)["methodResponses"][0]
    assert name == method, (name, result)
    assert not any(result.get(key) for key in ("notCreated", "notUpdated", "notDestroyed")), result
    return result


def create(kind, **obj):
    return jmap("x:" + kind + "/set", create={"seed": obj})["created"]["seed"]["id"]


def get(kind, obj_id):
    return jmap("x:" + kind + "/get", ids=[obj_id])["list"][0]


def inventory():
    return {kind: sorted(jmap("x:" + kind + "/query")["ids"])
            for kind in ("Domain", "NetworkListener", "Directory", "Application", "MtaRoute")}


class Metadata(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/jwks":
            document = {"keys": []}
        else:
            document = {"issuer": issuer, "jwks_uri": issuer + "/jwks",
                        "token_endpoint": issuer + "/token",
                        "authorization_endpoint": issuer + "/authorize",
                        "userinfo_endpoint": issuer + "/userinfo",
                        "end_session_endpoint": issuer + "/logout"}
        data = json.dumps(document).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        pass


# Colima resolves this name to the macOS host. The fixture only serves metadata;
# this verifies settings reload, not token authentication.
metadata = ThreadingHTTPServer(("0.0.0.0", 0), Metadata)
issuer = f"http://host.docker.internal:{metadata.server_port}"
threading.Thread(target=metadata.serve_forever, daemon=True).start()

try:
    domain_id = create("Domain", name="manafishrov.test", dkimManagement={"@type": "Manual"})
    listener_id = create("NetworkListener", name="provider-smoke", bind={"127.0.0.1:12526": True}, protocol="smtp")
    directory_id = create("Directory", **{"@type": "Oidc", "description": "seed", "issuerUrl": issuer})
    application_id = create("Application", description="seed", resourceUrl="https://example.com/provider-smoke.zip",
                            urlPrefix={"/provider-smoke": True}, enable=False)
    relay_id = create("MtaRoute", **{"@type": "Relay", "name": "provider-smoke", "host": "smtp.example.com",
                                  "authSecret": {"@type": "Value", "secret": "smoke-secret-do-not-use"}})
    before = inventory()
    arch = {"arm64": "arm64", "aarch64": "arm64", "x86_64": "amd64"}[platform.machine()]
    target = platform.system().lower() + "_" + arch
    mirror = args.work_dir / "mirror"
    binary = mirror / "registry.opentofu.org/michaelbrusegard/stalwart/1.0.3" / target / "terraform-provider-stalwart_v1.0.3"
    binary.parent.mkdir(parents=True)
    shutil.copy2(args.provider.resolve(), binary)
    tofurc = args.work_dir / "tofurc"
    tofurc.write_text('provider_installation {\n  filesystem_mirror {\n'
                      f'    path = "{mirror.resolve()}"\n'
                      '    include = ["registry.opentofu.org/michaelbrusegard/stalwart"]\n'
                      '  }\n  direct {\n'
                      '    exclude = ["registry.opentofu.org/michaelbrusegard/stalwart"]\n  }\n}\n')
    env = {**os.environ, "TF_CLI_CONFIG_FILE": str(tofurc.resolve()),
           "STALWART_URL": args.endpoint, "STALWART_USER": "admin", "STALWART_PASSWORD": "acctest123",
           "TF_VAR_issuer_url": issuer, "TF_VAR_directory_id": directory_id,
           "TF_VAR_application_id": application_id, "TF_VAR_relay_id": relay_id}

    def tofu(folder, *command):
        result = subprocess.run(["tofu", f"-chdir={folder}", *command], env=env, text=True, capture_output=True)
        (folder / (command[0] + ".log")).write_text(result.stdout + result.stderr)
        assert result.returncode == 0, result.stdout + result.stderr
        return result.stdout

    states = []
    for name in ("smoke", "adoption"):
        folder = args.work_dir / name
        folder.mkdir()
        shutil.copy2(Path(__file__).with_name("smoke.tf"), folder / "main.tf")
        assert not (folder / "terraform.tfstate").exists()
        tofu(folder, "init", "-input=false", "-no-color")
        plan = tofu(folder, "plan", "-input=false", "-no-color", "-out=apply.tfplan")
        (folder / "plan-apply.log").write_text(plan)
        assert "3 to import" in plan, plan
        applied = tofu(folder, "apply", "-input=false", "-no-color", "apply.tfplan")
        for kind in ("domain", "network_listener"):
            assert "Adopted existing " + kind in applied, applied
        tofu(folder, "plan", "-input=false", "-no-color", "-detailed-exitcode", "-out=empty.tfplan")
        state = json.loads(tofu(folder, "show", "-json"))
        ids = {r["address"]: r["values"]["id"] for r in state["values"]["root_module"]["resources"]}
        assert ids["stalwart_domain.mail"] == domain_id
        assert ids["stalwart_network_listener.edge"] == listener_id
        assert ids["stalwart_directory_oidc.pocket_id"] == directory_id
        assert ids["stalwart_application.webui"] == application_id
        assert inventory() == before, "server objects duplicated"
        assert get("Domain", domain_id)["description"] == "managed by provider smoke"
        http = get("Http", "singleton")
        assert http["clientIpSource"] == "xForwardedFor" and http["forwardedHops"] == 1
        with urlopen(args.endpoint + "/healthz/live") as response:
            assert response.headers["X-Provider-Smoke"] == "applied", "settings reload did not take effect"
        assert "Unable to reload" not in applied, applied
        states.append(ids)
        print(f"{name}: 10 resources, existing IDs preserved, no duplicates, second plan empty", flush=True)
    assert states[0] == states[1], "fresh-state apply changed object IDs"

    jmap("x:SystemSettings/set", update={"singleton": {"includeSecrets": True}})
    try:
        jmap("x:Action/set", create={"reload": {"@type": "ReloadSettings"}})
        assert get("MtaRoute", relay_id)["authSecret"]["secret"] == "smoke-secret-do-not-use", "masked secret written back"
    finally:
        jmap("x:SystemSettings/set", update={"singleton": {"includeSecrets": False}})
        jmap("x:Action/set", create={"reload": {"@type": "ReloadSettings"}})
    print("Imported relay secret preserved across both applies", flush=True)
    schema = tofu(args.work_dir / "smoke", "providers", "schema", "-json")
    (args.work_dir / "provider-v1-schema.json").write_text(schema)
    (args.work_dir / "evidence.json").write_text(json.dumps({"resource_ids": states[0], "inventory": before}, indent=2) + "\n")
finally:
    metadata.shutdown()
    metadata.server_close()
