"""One-time edge bootstrap through a Kubernetes port-forward.

Creates only the private certificate/listener and two API-key-only machine
principals. Credentials go directly from memory to SOPS. This intentionally
refuses a nonempty identity store or existing output files; a partial failure
requires inspection rather than silently replacing existing credentials.
It does not activate SMTP, mark the server bootstrapped, or deploy anything.
"""

from __future__ import annotations

import argparse
import base64
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
IMAGE_DIGEST = "sha256:ee91efd83fd1c4ab51d1462e7b0188546449093e7960ead09f4917c068dbbd2d"
DOMAIN = "system.edge.asgard.michaelbrusegard.com"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def kubectl(*args):
    return json.loads(subprocess.check_output([
        "kubectl", "--context=espresso", "--request-timeout=15s", *args, "-o", "json",
    ]))


class Client:
    def __init__(self, url, credential):
        parsed = urllib.parse.urlsplit(url)
        require(parsed.scheme == "http" and parsed.hostname == "127.0.0.1"
                and parsed.port is not None and not parsed.username
                and parsed.path in ("", "/") and not parsed.query and not parsed.fragment,
                "bootstrap requires an explicit loopback HTTP port-forward")
        self.url = url.rstrip("/") + "/jmap"
        user, password = credential.split(":", 1)
        require(user == "edge-bootstrap" and password.startswith("{PLAIN}"),
                "unexpected ephemeral recovery credential format")
        self.auth = "Basic " + base64.b64encode((user + ":" + password[7:]).encode()).decode()

    def call(self, kind, operation, arguments):
        method = f"x:{kind}/{operation}"
        body = json.dumps({"using": ["urn:ietf:params:jmap:core", "urn:stalwart:jmap"],
                           "methodCalls": [[method, arguments, "bootstrap"]]}).encode()
        request = urllib.request.Request(self.url, data=body, headers={
            "Authorization": self.auth, "Content-Type": "application/json",
        })
        with urllib.request.urlopen(request, timeout=15) as response:
            raw = response.read(1024 * 1024 + 1)
        require(len(raw) <= 1024 * 1024, "oversized bootstrap response")
        result = json.loads(raw)["methodResponses"]
        require(len(result) == 1 and result[0][0] == method, "bootstrap method failed")
        value = result[0][1]
        require(not any(value.get(key) for key in ("notCreated", "notUpdated", "notFound")),
                "bootstrap object operation failed")
        return value

    def create(self, kind, value):
        return self.call(kind, "set", {"create": {"bootstrap": value}})["created"]["bootstrap"]["id"]

    def key(self, account):
        result = self.call("ApiKey", "set", {"accountId": account, "create": {
            "bootstrap": {"description": "Declarative edge machine credential",
                          "permissions": {"@type": "Inherit"}},
        }})
        return result["created"]["bootstrap"]["secret"]


def encrypt(repo, target, document):
    result = subprocess.run([
        "sops", "--encrypt", "--input-type", "json", "--output-type", "yaml",
        "--encrypted-regex", "^(data|stringData)$", "--filename-override", str(target),
        "/dev/stdin",
    ], input=json.dumps(document).encode(), capture_output=True, cwd=repo, timeout=30)
    require(result.returncode == 0 and b"ENC[AES256_GCM" in result.stdout,
            "SOPS encryption failed; plaintext was not saved")
    return result.stdout


def save(repo, target, document):
    require(not target.exists(), "refusing to overwrite an existing encrypted secret")
    encrypted = encrypt(repo, target, document)
    target.parent.mkdir(parents=True, exist_ok=True)
    # Only ciphertext enters this temporary file.
    fd, path = tempfile.mkstemp(prefix=".bootstrap-encrypted-", dir=target.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(encrypted)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(path, target)  # Refuse races with an existing destination.
    finally:
        os.unlink(path)


def secret(name, namespace, values):
    return {"apiVersion": "v1", "kind": "Secret",
            "metadata": {"name": name, "namespace": namespace},
            "type": "Opaque", "stringData": values}


def machine(client, name, domain, permissions):
    require(permissions and len(permissions) == len(set(permissions)), "invalid permission inventory")
    return client.create("Account", {
        "@type": "User", "name": name, "domainId": domain, "credentials": {},
        "roles": {"@type": "User"}, "memberGroupIds": {}, "aliases": {},
        "permissions": {"@type": "Replace", "enabledPermissions": dict.fromkeys(permissions, True),
                        "disabledPermissions": {}},
        "encryptionAtRest": {"@type": "Disabled"},
    })


def bootstrap(client, config_permissions, readiness_permissions, save_config, save_readiness):
    for kind in ("Domain", "Account", "Directory", "NetworkListener"):
        require(not client.call(kind, "query", {"limit": 1})["ids"],
                "bootstrap requires an empty identity and listener store")
    # Fresh stores include factory local/MX routes. This ingress-only instance
    # must not retain them as potential fallback targets.
    route_ids = client.call("MtaRoute", "query", {})["ids"]
    if route_ids:
        routes = client.call("MtaRoute", "get", {"ids": route_ids})["list"]
        require(len(routes) == len(route_ids) and all(
            (row["name"], row["@type"]) in (("local", "Local"), ("mx", "Mx"))
            for row in routes), "unexpected routes in bootstrap store")
        result = client.call("MtaRoute", "set", {"destroy": route_ids})
        require(set(result.get("destroyed", [])) == set(route_ids), "factory route removal failed")
    applications = client.call("Application", "query", {})["ids"]
    require(len(applications) == 1, "expected one bundled Application for import")
    domain = client.create("Domain", {
        "name": DOMAIN, "aliases": {}, "isEnabled": False, "allowRelaying": False,
        "directoryId": None, "catchAllAddress": None,
        "subAddressing": {"@type": "Disabled"},
        "certificateManagement": {"@type": "Manual"},
        "dkimManagement": {"@type": "Manual"}, "dnsManagement": {"@type": "Manual"},
    })
    certificate = client.create("Certificate", {
        "certificate": {"@type": "File", "filePath": "/var/lib/stalwart/private/tls/tls.crt"},
        "privateKey": {"@type": "File", "filePath": "/var/lib/stalwart/private/tls/tls.key"},
    })
    listener = client.create("NetworkListener", {
        "name": "https", "protocol": "http", "bind": {"[::]:443": True},
        "useTls": True, "tlsImplicit": True,
    })
    client.call("SystemSettings", "set", {"update": {"singleton": {
        "defaultHostname": "mail.asgard.michaelbrusegard.com", "defaultDomainId": domain,
        "defaultCertificateId": certificate,
    }}})
    client.call("Authentication", "set", {"update": {"singleton": {"directoryId": None}}})
    owner = machine(client, "tofu", domain, config_permissions)
    save_config(secret("stalwart-edge-tofu", "flux-system", {
        "STALWART_TOKEN": client.key(owner),
        "bootstrap_internal_domain_id": domain,
        "bootstrap_certificate_id": certificate,
        "bootstrap_https_listener_id": listener,
        "bootstrap_webui_id": applications[0],
    }))
    reader = machine(client, "readiness", domain, readiness_permissions)
    save_readiness(secret("stalwart-edge-readiness", "stalwart-edge", {"token": client.key(reader)}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True)
    parser.add_argument("--secrets-repo", required=True, type=Path)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    require(args.execute, "explicit --execute is required")
    repo = args.secrets_repo.resolve()
    require((repo / ".sops.yaml").is_file(), "missing secrets repository SOPS rules")
    config_path = repo / "gitops/espresso/infrastructure/stalwart-edge-tofu/secrets.yaml"
    readiness_path = repo / "gitops/espresso/apps/stalwart-edge/readiness/secrets.yaml"
    for path in (config_path, readiness_path):
        require(not path.exists(), "encrypted destination already exists; inspect before retrying")
        encrypt(repo, path, secret("preflight", "stalwart-edge", {"token": "encryption-preflight"}))
    pod = kubectl("-n", "stalwart-edge", "get", "pod", "stalwart-edge-0")
    container = next(row for row in pod["status"]["containerStatuses"] if row["name"] == "stalwart")
    require(container["imageID"].endswith("@" + IMAGE_DIGEST), "unapproved edge image")
    value = kubectl("-n", "stalwart-edge", "get", "secret", "stalwart-edge-bootstrap")
    credential = base64.b64decode(value["data"]["STALWART_RECOVERY_ADMIN"]).decode()
    client = Client(args.url, credential)
    config_permissions = json.loads((ROOT / "gitops/espresso/tofu/stalwart-edge/bootstrap-permissions.json").read_text())
    spec = importlib.util.spec_from_file_location("edge_readiness", ROOT / "gitops/espresso/apps/stalwart-edge/readiness.py")
    readiness = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(readiness)
    bootstrap(client, config_permissions, readiness.READINESS_PERMISSIONS,
              lambda value: save(repo, config_path, value),
              lambda value: save(repo, readiness_path, value))
    print("Machine credentials encrypted. SMTP remains inactive; no marker or deployment was changed.")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Fail without printing response bodies or credential-bearing requests.
        raise SystemExit("Edge bootstrap failed. Inspect partial state before retrying; credentials were not logged.")
