"""Independent native SCIM blackbox acceptance fixture (stdlib unless --ui-checks).

    python3 integration.py /approved/path/to/stalwart
    python3 integration.py --self-test

The launcher ALWAYS creates a fresh `unshare -Urn` user/network namespace. The
child verifies different namespace identities and an interface/address set
containing only loopback before starting anything. HTTP is pinned to 127.0.0.1,
proxies and redirects are disabled, and only a new temporary RocksDB is used.
No production configuration, credential, adapter module, or external URL is used.
Upstream recovery mode binds [::], not a configurable literal loopback address;
inside this mandatory namespace it is reachable only over loopback. A literal
127.0.0.1 kernel bind requires a separate server recovery-listener change.

Expectations come from RFC 7643/7644 and public Stalwart SCIM docs, not proprietary
SCIM source/tests. The default suite asserts the documented target profile,
including Bulk, cursor pagination, and conditional writes. Unfinished features
FAIL; advertised support=false does not silently skip their tests. This is a
single-server blackbox fixture. Barrier-synchronized concurrent requests check
lost-update and conditional-write invariants, but cannot force overlap at a
particular storage instruction; they are not a linearizability proof. OIDC/JIT
and delivery behavior remain separate acceptance boundaries. The fake-IdP phase
exercises the native OIDC directory's opaque-token/userinfo JIT path, not JWT
signature validation, OAuth authorization-code exchange, or an actual Pocket ID.

Optional --ui-checks imports our sibling ui.py and requires Playwright/Chromium.
Optional --admin-assets checks the supplied pinned asset directory over HTTP.
Neither optional check replaces any native SCIM assertion.
"""

from __future__ import annotations

import argparse
import base64
import gzip
import hashlib
import ipaddress
import json
import os
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from dataclasses import dataclass
from functools import partial
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock

CORE = "urn:ietf:params:scim:schemas:core:2.0:"
MESSAGE = "urn:ietf:params:scim:api:messages:2.0:"
ROOT = "/scim/v2"
DOMAIN = "example.test"
SCIM_PERMISSIONS = (
    "authenticate",
    "scimAccess",
    "sysAccountGet",
    "sysAccountCreate",
    "sysAccountUpdate",
    "sysAccountDestroy",
)
# Only the rights exercised by the optional native UI workflow. An Admin role
# label alone has no built-in grants in a recovery-only database.
UI_PERMISSIONS = (
    "authenticate",
    "scimAccess",
    "sysDomainGet",
    "sysDomainQuery",
    "sysDomainUpdate",
    "sysAccountGet",
    "sysAccountQuery",
    "sysAccountUpdate",
    "sysApiKeyCreate",
    "sysApiKeyGet",
)
SCIM_FIELDS = {
    ("x:Domain", "allowScimProvisioning"),
    ("x:UserAccount", "externalId"),
    ("x:GroupAccount", "externalId"),
}
MAX_RESPONSE = 16 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def encoded(value):
    return json.dumps(value, separators=(",", ":")).encode()


def isolated_environment():
    # Keep tool/package lookup, not the caller's credentials or Stalwart config.
    environment = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "LANG": "C.UTF-8",
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    if os.environ.get("PYTHONPATH"):
        environment["PYTHONPATH"] = os.environ["PYTHONPATH"]
    return environment


def patch(*operations):
    return {"schemas": [MESSAGE + "PatchOp"], "Operations": list(operations)}


def user_body(local_part, /, **extra):
    return {"schemas": [CORE + "User"], "userName": f"{local_part}@{DOMAIN}", **extra}


def query(path, **parameters):
    return path + "?" + urllib.parse.urlencode(parameters)


def safe_path(path):
    parsed = urllib.parse.urlsplit(path)
    require(
        isinstance(path, str)
        and path.startswith("/")
        and not path.startswith("//")
        and not parsed.scheme
        and not parsed.netloc
        and not parsed.fragment
        and not any(c in path for c in "\r\n\\"),
        "Refusing an off-origin or malformed fixture request path",
    )
    return path


def same_origin_path(location, origin):
    parsed = urllib.parse.urlsplit(location)
    if parsed.scheme or parsed.netloc:
        require(f"{parsed.scheme}://{parsed.netloc}" == origin, "Off-origin Location")
        location = urllib.parse.urlunsplit(
            ("", "", parsed.path, parsed.query, parsed.fragment)
        )
    return safe_path(location)


def enterprise_flags(schema):
    return {
        (kind, name): field.get("enterprise")
        for kind, definition in schema["fields"].items()
        for name, field in definition.get("properties", {}).items()
        if "enterprise" in field
    }


def check_schema(archive, fingerprint, reference=None):
    expected = (
        base64.urlsafe_b64encode(hashlib.sha256(archive).digest()).decode().rstrip("=")
    )
    require(
        fingerprint == expected, "Schema redirect hash does not match served gzip bytes"
    )
    schema = json.loads(gzip.decompress(archive))
    flags = enterprise_flags(schema)
    for field in SCIM_FIELDS:
        require(
            flags.get(field) is False,
            f"Native SCIM schema field is still gated: {field}",
        )
    for field in (
        ("x:Authentication", "defaultTenantRoleIds"),
        ("x:DataRetention", "archiveDeletedAccountsFor"),
        ("x:DataRetention", "holdMetricsFor"),
    ):
        require(
            flags.get(field) is True,
            f"Unrelated Enterprise annotation changed: {field}",
        )
    if reference is not None:
        previous = enterprise_flags(reference)
        require(set(previous) == set(flags), "Enterprise annotation keys changed")
        changed = {field for field in flags if flags[field] != previous[field]}
        require(changed == SCIM_FIELDS, f"Unexpected schema annotation diff: {changed}")
    return schema


class Redactor:
    def __init__(self):
        self.values = []

    def add(self, value):
        if value:
            self.values.append(value)
        return value

    def __call__(self, value):
        value = str(value)
        for secret in sorted(self.values, key=len, reverse=True):
            value = value.replace(secret, "<disposable-credential-redacted>")
        return value


class FakeIdP:
    """Loopback opaque-token IdP; HTTP starts only in the live namespace fixture.

    Empty JWKS is intentional: the supported opaque bearer path authenticates at
    userinfo. No unsigned JWT or fake cryptographic-validation claim is involved.
    """

    def __init__(self, redactor):
        self.redactor = redactor
        self.origin = None
        self.tokens = {}
        self.userinfo_hits = {}
        self.paths = []
        self.lock = threading.Lock()
        self.server = None
        self.thread = None

    def issue(self, email, name, groups):
        token = self.redactor.add("fixture-opaque-" + secrets.token_urlsafe(32))
        with self.lock:
            self.tokens[token] = {
                "sub": email,
                "email": email,
                "name": name,
                "groups": list(groups),
            }
        return token

    def wait_discovered(self, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            with self.lock:
                if {"/.well-known/openid-configuration", "/jwks"}.issubset(self.paths):
                    return
            time.sleep(0.05)
        raise AssertionError(
            "ReloadSettings completed but native OIDC discovery/JWKS readiness was not observed"
        )

    def hit_count(self, token):
        with self.lock:
            return self.userinfo_hits.get(token, 0)

    def response(self, path, authorization):
        require(self.origin is not None, "Fake IdP has no configured loopback origin")
        with self.lock:
            self.paths.append(path)
            if path == "/.well-known/openid-configuration":
                return 200, {
                    "issuer": self.origin,
                    "jwks_uri": self.origin + "/jwks",
                    "userinfo_endpoint": self.origin + "/userinfo",
                    "authorization_endpoint": self.origin + "/authorize",
                    "token_endpoint": self.origin + "/token",
                    "scopes_supported": ["openid", "profile", "email"],
                    "claims_supported": ["sub", "email", "name", "groups"],
                }
            if path == "/jwks":
                return 200, {"keys": []}
            if path == "/userinfo":
                token = (
                    authorization.removeprefix("Bearer ")
                    if authorization.startswith("Bearer ")
                    else None
                )
                if token not in self.tokens:
                    return 401, {"error": "invalid_token"}
                self.userinfo_hits[token] = self.userinfo_hits.get(token, 0) + 1
                return 200, json.loads(json.dumps(self.tokens[token]))
            return 404, {"error": "unsupported_fixture_endpoint"}

    def __enter__(self):
        require(
            [name for _, name in socket.if_nameindex()] == ["lo"],
            "Fake IdP may only start in the loopback-only fixture namespace",
        )
        provider = self

        class Handler(BaseHTTPRequestHandler):
            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def do_GET(self):
                status, document = provider.response(
                    self.path, self.headers.get("Authorization", "")
                )
                body = encoded(document)
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_):
                # Neither bearer credentials nor disposable profile data is logged.
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.origin = f"http://127.0.0.1:{self.server.server_port}"
        self.thread = threading.Thread(
            target=self.server.serve_forever, name="fixture-idp", daemon=True
        )
        try:
            self.thread.start()
        except BaseException:
            self.server.server_close()
            raise
        return self

    def __exit__(self, *_):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=10)
        require(not self.thread.is_alive(), "Fake IdP thread did not stop")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


@dataclass
class Response:
    status: int
    headers: object
    raw: bytes

    def document(self):
        raw = (
            gzip.decompress(self.raw)
            if self.headers.get("Content-Encoding") == "gzip"
            else self.raw
        )
        return json.loads(raw)


class Client:
    def __init__(self, port, redactor):
        require(isinstance(port, int) and 1 <= port <= 65535, "Invalid fixture port")
        self.origin = f"http://127.0.0.1:{port}"
        self.http = urllib.request.build_opener(
            urllib.request.ProxyHandler({}), NoRedirect()
        )
        self.redactor = redactor
        self.token = None
        self.recovery = None

    def request(
        self, method, path, body=None, *, auth="bearer", headers=None, raw=None
    ):
        path = safe_path(path)
        require(not (body is not None and raw is not None), "Ambiguous request body")
        request_headers = {
            "Accept": "application/scim+json",
            "Accept-Encoding": "identity",
        }
        if auth == "bearer":
            require(self.token is not None, "SCIM API key not bootstrapped")
            request_headers["Authorization"] = "Bearer " + self.token
        elif auth == "recovery":
            require(self.recovery is not None, "Recovery auth not bootstrapped")
            request_headers["Authorization"] = self.recovery
        elif auth is not None:
            request_headers["Authorization"] = auth
        if body is not None:
            raw = encoded(body)
        if raw is not None:
            request_headers["Content-Type"] = (
                "application/scim+json" if path.startswith(ROOT) else "application/json"
            )
        request_headers.update(headers or {})
        request = urllib.request.Request(
            self.origin + path, method=method, data=raw, headers=request_headers
        )
        try:
            response = self.http.open(request, timeout=30)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            data = response.read(MAX_RESPONSE + 1)
            require(len(data) <= MAX_RESPONSE, "Fixture response exceeds safety bound")
            return Response(response.code, response.headers, data)

    def expect(self, method, path, status, body=None, *, scim_type=None, **kwargs):
        response = self.request(method, path, body, **kwargs)
        require(
            response.status == status,
            self.redactor(
                f"{method} {path}: expected HTTP {status}, got {response.status}: {response.raw[:3000]!r}"
            ),
        )
        if path.startswith(ROOT) and status != 204:
            require(
                response.headers.get("Content-Type", "").split(";")[0]
                == "application/scim+json",
                f"{path}: missing SCIM media type",
            )
            document = response.document()
            if status >= 400:
                require(
                    MESSAGE + "Error" in document.get("schemas", []),
                    f"{path}: missing SCIM Error schema",
                )
                require(
                    document.get("status") == str(status),
                    f"{path}: error status must be a string",
                )
                require(
                    isinstance(document.get("detail"), str) and document["detail"],
                    f"{path}: missing error detail",
                )
                if scim_type:
                    require(
                        document.get("scimType") == scim_type,
                        f"{path}: expected scimType {scim_type}: {document}",
                    )
        if status == 204:
            require(not response.raw, f"{path}: 204 response must have an empty body")
        return response

    def jmap(self, method, arguments, *, auth="recovery", allow_failure=False):
        response = self.expect(
            "POST",
            "/jmap",
            200,
            {
                "using": ["urn:ietf:params:jmap:core", "urn:stalwart:jmap"],
                "methodCalls": [[method, arguments, "fixture"]],
            },
            auth=auth,
        )
        calls = response.document().get("methodResponses", [])
        require(
            len(calls) == 1 and calls[0][2] == "fixture",
            "Unexpected JMAP response envelope",
        )
        if allow_failure:
            return calls[0]
        require(calls[0][0] == method, self.redactor(f"{method}: {calls[0]}"))
        result = calls[0][1]
        require(
            not any(
                result.get(k) for k in ("notCreated", "notUpdated", "notDestroyed")
            ),
            self.redactor(f"{method} failed: {result}"),
        )
        return result


class Server:
    def __init__(self, binary, root, client):
        self.binary, self.root, self.client = binary, root, client
        self.process = None
        self.log = None
        self.password = client.redactor.add(secrets.token_urlsafe(40))
        client.recovery = client.redactor.add(
            "Basic " + base64.b64encode(("fixture:" + self.password).encode()).decode()
        )
        self.config = root / "config.json"
        self.config.write_bytes(
            encoded({"@type": "RocksDb", "path": str(root / "data")})
        )
        self.config.chmod(0o600)

    def start(self):
        require(self.process is None, "Server already started")
        self.log = (self.root / "server.log").open("ab")
        env = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "LANG": "C.UTF-8",
            "HOME": str(self.root),
            "TMPDIR": str(self.root),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_CACHE_HOME": str(self.root / "cache"),
            "STALWART_RECOVERY_MODE": "true",
            "STALWART_RECOVERY_ADMIN": "fixture:" + self.password,
            "STALWART_OIDC_ADMIN_GROUP": "admin",
            "STALWART_RECOVERY_MODE_PORT": str(
                urllib.parse.urlsplit(self.client.origin).port
            ),
        }
        try:
            self.process = subprocess.Popen(
                [str(self.binary), "--config", str(self.config)],
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=self.log,
                stderr=self.log,
                start_new_session=True,
            )
            deadline = time.monotonic() + 60
            while time.monotonic() < deadline:
                require(self.process.poll() is None, "Stalwart exited before startup")
                try:
                    response = self.client.request(
                        "GET", "/api/account", auth="recovery"
                    )
                    if response.status == 200:
                        require(
                            response.document().get("edition") == "oss",
                            "Fixture binary is not OSS edition",
                        )
                        return
                except (OSError, ValueError):
                    pass
                time.sleep(0.2)
            raise AssertionError("Stalwart did not become ready within 60 seconds")
        except BaseException:
            self.stop()
            raise

    def stop(self):
        process, self.process = self.process, None
        if process is not None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=10)
            # Terminate any child that outlived the main server process.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        if self.log:
            self.log.close()
            self.log = None

    def restart(self):
        self.stop()
        self.start()

    def diagnostics(self):
        path = self.root / "server.log"
        if not path.exists():
            return "No server log"
        with path.open("rb") as log:
            log.seek(max(0, path.stat().st_size - 12000))
            return self.client.redactor(log.read().decode(errors="replace"))


class Acceptance:
    def __init__(self, client, server, args):
        self.c, self.server, self.args = client, server, args
        self.user = None
        self.group = None
        self.bulk_ids = []
        self.failures = []

    def stage(self, name, operation):
        try:
            operation()
        except Exception as error:  # noqa: BLE001 - collect test failures, never skip them
            self.failures.append(name)
            print(
                self.c.redactor(f"FAIL {name}: {type(error).__name__}: {error}"),
                flush=True,
            )
        else:
            print(f"PASS {name}", flush=True)

    def create_native_user(self, name, domain_id, *, permissions=None, admin=False):
        user = {
            "@type": "User",
            "name": name,
            "domainId": domain_id,
            "roles": {"@type": "Admin" if admin else "User"},
            "credentials": {},
            "encryptionAtRest": {"@type": "Disabled"},
        }
        if permissions is not None:
            user["permissions"] = {
                "@type": "Replace",
                "enabledPermissions": permissions,
            }
        result = self.c.jmap("x:Account/set", {"create": {"fixture": user}})
        return result["created"]["fixture"]["id"]

    def api_key(self, account_id, permissions=None):
        settings = (
            {"@type": "Inherit"}
            if permissions is None
            else {"@type": "Replace", "permissions": permissions}
        )
        result = self.c.jmap(
            "x:ApiKey/set",
            {
                "accountId": account_id,
                "create": {
                    "fixture": {
                        "description": "Disposable isolated native SCIM fixture",
                        "permissions": settings,
                    },
                },
            },
        )
        return self.c.redactor.add(result["created"]["fixture"]["secret"])

    def bootstrap(self):
        domains = {}
        for name, enabled in ((DOMAIN, True), ("closed.test", False)):
            domains[name] = {
                "name": name,
                "isEnabled": True,
                "allowScimProvisioning": enabled,
                "certificateManagement": {"@type": "Manual"},
                "dkimManagement": {"@type": "Manual"},
                "dnsManagement": {"@type": "Manual"},
            }
        result = self.c.jmap("x:Domain/set", {"create": domains})
        self.domain_id = result["created"][DOMAIN]["id"]
        self.closed_domain_id = result["created"]["closed.test"]["id"]
        self.bootstrap_domain_state()
        permissions = dict.fromkeys(SCIM_PERMISSIONS, True)
        self.service_id = self.create_native_user(
            "scim-fixture", self.domain_id, permissions=permissions
        )
        self.c.token = self.api_key(self.service_id, permissions)
        self.no_scim_key = self.api_key(self.service_id, {"authenticate": True})
        self.hidden_id = self.create_native_user("hidden", self.closed_domain_id)
        account = self.native(self.service_id)
        require(
            account.get("roles", {}).get("@type") == "User",
            "SCIM principal must be an ordinary user, not administrator",
        )
        require(
            account.get("permissions", {}).get("enabledPermissions") == permissions,
            "SCIM principal permission scope changed",
        )
        require(
            self.c.expect("GET", "/api/account", 200).document()["edition"] == "oss",
            "Ordinary API-key session does not report OSS edition",
        )
        self.bootstrap_service_visibility()
        for method in ("x:Domain/query", "x:Domain/get", "x:Account/query"):
            result = self.c.jmap(method, {}, auth="bearer", allow_failure=True)
            require(
                result[0] == "error" and result[1].get("type") == "forbidden",
                f"Restricted key unexpectedly allowed {method}: {result}",
            )

    def bootstrap_domain_state(self):
        # Recovery-only raw native readback distinguishes persisted opt-in from
        # a broken SCIM snapshot/listing. No Query permission is added to the key.
        ids = [self.domain_id, self.closed_domain_id]
        result = self.c.jmap("x:Domain/get", {"ids": ids})
        rows = {row["id"]: row for row in result.get("list", [])}
        require(
            len(set(ids)) == 2 and set(rows) == set(ids) and not result.get("notFound"),
            "Bootstrap native Domain/get did not return both distinct domain IDs",
        )
        for domain_id, name, enabled in (
            (self.domain_id, DOMAIN, True),
            (self.closed_domain_id, "closed.test", False),
        ):
            row = rows[domain_id]
            require(
                row.get("name") == name and row.get("allowScimProvisioning") is enabled,
                f"Bootstrap Domain/get failed persisted policy readback for {name}: id={domain_id}, name={row.get('name')}, allowScimProvisioning={row.get('allowScimProvisioning')!r}",
            )

    def bootstrap_service_visibility(self):
        account = self.native(self.service_id)
        require(
            account.get("id") == self.service_id
            and account.get("name") == "scim-fixture"
            and account.get("domainId") == self.domain_id,
            "Bootstrap native Account/get returned the wrong service account or domain",
        )
        scoped = self.c.expect(
            "GET", ROOT + "/Users/" + self.service_id, 200
        ).document()
        require(
            scoped.get("id") == self.service_id
            and scoped.get("userName") == "scim-fixture@" + DOMAIN
            and CORE + "User" in scoped.get("schemas", []),
            "Native service account exists but authenticated SCIM lookup does not expose the expected scoped User",
        )
        print(
            "Bootstrap native Account/get and six-permission SCIM service lookup PASS",
            flush=True,
        )

    def native(self, account_id):
        result = self.c.jmap("x:Account/get", {"ids": [account_id]})
        require(
            len(result.get("list", [])) == 1, f"Native account missing: {account_id}"
        )
        return result["list"][0]

    def needed_user(self):
        require(self.user is not None, "Blocked: user creation failed (not skipped)")
        return ROOT + "/Users/" + self.user["id"]

    def management_schema(self):
        require(
            self.c.expect("GET", "/api/account", 200, auth="recovery").document()[
                "edition"
            ]
            == "oss",
            "Edition changed",
        )
        response = self.c.expect("GET", "/api/schema", 302, auth="recovery")
        location = same_origin_path(response.headers["Location"], self.c.origin)
        require(location.startswith("/api/schema/"), "Unexpected schema redirect")
        archive = self.c.expect("GET", location, 200, auth="recovery")
        require(
            archive.headers.get("Content-Encoding") == "gzip",
            "Schema is not served as gzip",
        )
        reference = None
        if self.args.reference_schema:
            reference = json.loads(
                gzip.decompress(Path(self.args.reference_schema).read_bytes())
            )
        check_schema(archive.raw, location.rsplit("/", 1)[1], reference)

    def auth_and_discovery(self):
        for endpoint in ("ServiceProviderConfig", "ResourceTypes", "Schemas"):
            path = ROOT + "/" + endpoint
            self.c.expect("GET", path, 200, auth=None)
            self.c.expect("GET", path, 401, auth="recovery")
            self.c.expect("GET", path, 401, auth="Bearer invalid-fixture-token")
            self.c.expect("GET", path, 403, auth="Bearer " + self.no_scim_key)
            self.c.expect("GET", query(path, filter='id eq "User"'), 403)
            self.c.expect("OPTIONS", path, 204)
        config = self.c.expect("GET", ROOT + "/ServiceProviderConfig", 200).document()
        for name in ("patch", "filter", "bulk", "sort", "etag"):
            require(
                config[name]["supported"] is True,
                f"Documented target capability unavailable: {name}",
            )
        require(
            config["bulk"]["maxOperations"] == 1000, "Bulk maxOperations must be 1000"
        )
        require(
            config["bulk"]["maxPayloadSize"] == 1024 * 1024,
            "Bulk payload cap must be 1 MiB",
        )
        require(config["filter"]["maxResults"] == 200, "Filter cap must be 200")
        require(
            config["changePassword"]["supported"] is False,
            "Password changes must not be advertised",
        )
        require(
            config.get("interopProfileConformant") is False,
            "Interop profile must disclose discarded known fields",
        )
        require(
            {a["type"] for a in config["authenticationSchemes"]}
            == {"oauthbearertoken"},
            "Only Bearer authentication may be advertised",
        )
        resources = self.c.expect("GET", ROOT + "/ResourceTypes", 200).document()[
            "Resources"
        ]
        require(
            {r["id"] for r in resources} == {"User", "Group"},
            "Unexpected resource types",
        )
        for kind in ("User", "Group"):
            self.c.expect("GET", ROOT + "/ResourceTypes/" + kind, 200)
            schema = self.c.expect(
                "GET", ROOT + "/Schemas/" + CORE + kind, 200
            ).document()
            attrs = {a["name"]: a for a in schema["attributes"]}
            require(
                "externalId" in attrs and "displayName" in attrs,
                "Discovery has placeholder attribute definitions",
            )
            multi = attrs["emails" if kind == "User" else "members"]
            require(
                multi["multiValued"] is True and multi.get("subAttributes"),
                "Missing complex schema attributes",
            )
            require(
                "password" not in attrs and "roles" not in attrs,
                "Discarded attributes leaked into schema",
            )

    def endpoint_errors(self):
        self.c.expect("GET", ROOT + "/Me", 501)
        self.c.expect("GET", ROOT + "/Missing", 404)
        response = self.c.expect("DELETE", ROOT + "/Users", 405)
        require("GET" in response.headers.get("Allow", ""), "405 must advertise Allow")
        self.c.expect("OPTIONS", ROOT + "/Users", 204)
        for expression in (
            'userName co "x"',
            'userName ne "x"',
            "active pr",
            'userName eq "x" or active eq true',
            "not (active eq true)",
            'emails[value eq "x"]',
            'timezone eq "UTC"',
            'name.givenName eq "Alice"',
        ):
            self.c.expect(
                "GET",
                query(ROOT + "/Users", filter=expression),
                400,
                scim_type="invalidFilter",
            )
        self.c.expect(
            "GET",
            query(ROOT + "/Groups", filter='userName eq "x"'),
            400,
            scim_type="invalidFilter",
        )
        self.c.expect(
            "POST",
            ROOT + "/Users",
            400,
            {"userName": "missing-schema@example.test"},
            scim_type="invalidSyntax",
        )
        self.c.expect(
            "POST",
            ROOT + "/Users",
            400,
            user_body("typo", dispalyName="typo"),
            scim_type="invalidSyntax",
        )
        duplicate = (
            '{"schemas":["'
            + CORE
            + 'User"],"userName":"one@example.test","userName":"two@example.test"}'
        ).encode()
        self.c.expect(
            "POST", ROOT + "/Users", 400, raw=duplicate, scim_type="invalidSyntax"
        )
        self.c.expect(
            "POST",
            ROOT + "/Users",
            400,
            user_body("bad", userName="bare-login"),
            scim_type="invalidValue",
        )
        self.c.expect(
            "POST", ROOT + "/Users", 400, raw=b'{"schemas":', scim_type="invalidSyntax"
        )

    def create_user(self):
        body = user_body(
            "alice",
            externalId="native-fixture-user",
            name={"givenName": "Alice", "familyName": "Fixture"},
            emails=[{"value": "alias@example.test"}],
            locale="EN-us",
            timezone="Europe/Lisbon",
            password="discarded-fixture-not-a-credential",
            roles=[{"value": "admin"}],
        )
        response = self.c.expect("POST", ROOT + "/Users", 201, body)
        self.user = response.document()
        path = self.needed_user()
        require(
            same_origin_path(response.headers["Location"], self.c.origin) == path,
            "Wrong User Location",
        )
        user = self.c.expect("GET", path, 200).document()
        require(
            user["id"] == self.user["id"]
            and user["externalId"] == "native-fixture-user",
            "Created identity not readable",
        )
        require(
            user["displayName"] == user["name"]["formatted"] == "Alice Fixture",
            "Structured-name fallback missing",
        )
        require(
            user["locale"] == user["preferredLanguage"] == "en-US"
            and user["timezone"] == "Europe/Lisbon",
            "Locale/timezone mapping failed",
        )
        require(
            {e["value"] for e in user["emails"]}
            == {"alice@example.test", "alias@example.test"},
            "Native aliases missing",
        )
        require(
            sum(e.get("primary") is True for e in user["emails"]) == 1,
            "Exactly one primary address required",
        )
        require(
            "password" not in user and "roles" not in user,
            "Ignored credentials/roles returned",
        )
        native = self.native(user["id"])
        require(
            not native.get("credentials"),
            "SCIM password was persisted as a native credential",
        )
        require(
            native.get("externalId") == user["externalId"],
            "externalId is not stored natively",
        )
        self.c.expect("POST", ROOT + "/Users", 409, body, scim_type="uniqueness")

    def put_and_patch(self):
        path = self.needed_user()
        body = user_body(
            "alice-renamed",
            externalId="native-fixture-user",
            displayName="Renamed User",
            emails=[{"value": "replacement@example.test"}],
            locale="fr-FR",
            timezone="Europe/Paris",
        )
        result = self.c.expect("PUT", path, 200, body).document()
        require(
            {e["value"] for e in result["emails"]}
            == {"alice-renamed@example.test", "replacement@example.test"},
            "PUT did not replace aliases/primary",
        )
        require(
            result["locale"] == "fr-FR" and result["timezone"] == "Europe/Paris",
            "PUT locale/timezone lost",
        )
        result = self.c.expect(
            "PATCH",
            path,
            200,
            patch(
                {
                    "op": "add",
                    "path": "emails",
                    "value": [{"value": "patched@example.test"}],
                },
                {"op": "remove", "path": 'emails[value eq "replacement@example.test"]'},
                {"op": "replace", "path": "name.formatted", "value": "Patched User"},
            ),
        ).document()
        require(
            {e["value"] for e in result["emails"]}
            == {"alice-renamed@example.test", "patched@example.test"},
            "Filtered alias PATCH failed",
        )
        require(
            result["displayName"] == "Patched User",
            "name.formatted did not update shared display field",
        )
        self.c.expect(
            "PATCH",
            path,
            400,
            patch({"op": "remove", "path": "emails[primary eq true]"}),
            scim_type="mutability",
        )
        self.c.expect(
            "PATCH",
            path,
            400,
            patch({"op": "replace", "path": "id", "value": "1"}),
            scim_type="mutability",
        )
        self.c.expect(
            "PATCH",
            path,
            400,
            patch({"op": "replace", "path": "unknown", "value": "x"}),
            scim_type="invalidPath",
        )
        self.c.expect(
            "PUT",
            path,
            400,
            {**body, "timezone": "Not/AZone"},
            scim_type="invalidValue",
        )
        self.c.expect(
            "PUT",
            path,
            400,
            {**body, "locale": "not-a-locale"},
            scim_type="invalidValue",
        )
        before = self.c.expect("GET", path, 200).document()
        self.c.expect(
            "PATCH",
            path,
            400,
            patch(
                {"op": "replace", "path": "displayName", "value": "must roll back"},
                {"op": "replace", "path": "id", "value": "invalid"},
            ),
            scim_type="mutability",
        )
        require(
            self.c.expect("GET", path, 200).document() == before,
            "Failed PATCH partially committed",
        )

    def unconfigured_user_defaults(self):
        """A valid native key cannot invent an absent Authenticate entitlement."""
        with restored_configuration(self.c, [self.domain_id, self.closed_domain_id]):
            self.c.jmap(
                "x:Authentication/set",
                {"update": {"singleton": {"defaultUserRoleIds": {}}}},
            )
            self.c.jmap(
                "x:Action/set", {"create": {"reload": {"@type": "ReloadSettings"}}}
            )
            account_id = self.create_native_user("defaults-disabled", self.domain_id)
            try:
                token = self.api_key(account_id, {"authenticate": True})
                path = ROOT + "/Users/" + account_id
                before = self.native(account_id)["permissions"]
                require(
                    self.c.expect("GET", path, 200).document()["active"] is False,
                    "Account with empty native default roles unexpectedly authenticates",
                )
                for endpoint in ("/api/account", "/jmap/session"):
                    self.c.expect("GET", endpoint, 403, auth="Bearer " + token)
                disabled = self.c.expect(
                    "PATCH",
                    path,
                    200,
                    patch({"op": "replace", "path": "active", "value": False}),
                ).document()
                require(
                    disabled["active"] is False,
                    "Redundant deactivation granted authentication",
                )
                self.c.expect(
                    "PATCH",
                    path,
                    409,
                    patch({"op": "replace", "path": "active", "value": True}),
                )
                require(
                    self.native(account_id)["permissions"] == before,
                    "SCIM fabricated pre-existing permissions for a natively disabled account",
                )
                require(
                    self.c.expect("GET", path, 200).document()["active"] is False,
                    "Failed restore enabled an account without native entitlement",
                )
                for endpoint in ("/api/account", "/jmap/session"):
                    self.c.expect("GET", endpoint, 403, auth="Bearer " + token)
            finally:
                self.c.jmap("x:Account/set", {"destroy": [account_id]})

    def permissions_roundtrip(self):
        path = self.needed_user()
        custom = {
            "@type": "Replace",
            "enabledPermissions": {"authenticate": True, "sysAccountGet": True},
            "disabledPermissions": {"sysAccountCreate": True},
        }
        self.c.jmap(
            "x:Account/set", {"update": {self.user["id"]: {"permissions": custom}}}
        )
        # This is a real native credential, created through x:ApiKey/set, not a
        # SCIM flag assertion. Warm the credential/auth caches before disabling.
        user_key = self.api_key(self.user["id"], {"authenticate": True})
        before = self.native(self.user["id"])["permissions"]

        def authentication(status):
            for endpoint in ("/api/account", "/jmap/session"):
                self.c.expect("GET", endpoint, status, auth="Bearer " + user_key)

        authentication(200)
        disabled_response = self.c.expect(
            "PATCH",
            path,
            200,
            patch({"op": "replace", "path": "active", "value": "false"}),
        )
        require(
            disabled_response.document()["active"] is False,
            "Deactivation did not affect effective permission",
        )
        # No polling allowance: successful deactivation must invalidate a warmed
        # native credential before acknowledging the completed SCIM mutation.
        # Native authenticate() preserves Security::Unauthorized when the valid
        # credential lacks Authenticate; the JMAP/management mapper returns 403,
        # not the 401 used for invalid credentials. This is a strict denial.
        authentication(403)
        disabled_native = self.native(self.user["id"])
        require(
            disabled_native["id"] == self.user["id"],
            "Deactivation deleted account/mailbox identity",
        )
        disabled_permissions = disabled_native["permissions"]
        disabled_etag = disabled_response.headers.get("ETag")
        require(disabled_etag, "Inactive resource has no ETag")
        again = self.c.expect(
            "PATCH",
            path,
            200,
            patch({"op": "replace", "path": "active", "value": False}),
        )
        require(
            again.document()["active"] is False
            and again.headers.get("ETag") == disabled_etag,
            "Repeated active=false is not an idempotent no-op",
        )
        require(
            self.native(self.user["id"])["permissions"] == disabled_permissions,
            "Repeated active=false overwrote the original permission backup",
        )
        authentication(403)

        self.server.restart()
        inactive = self.c.expect("GET", path, 200)
        require(
            inactive.document()["active"] is False
            and inactive.headers.get("ETag") == disabled_etag,
            "Inactive state/ETag did not survive restart",
        )
        require(
            self.native(self.user["id"])["permissions"] == disabled_permissions,
            "Inactive native permission override changed across restart",
        )
        authentication(403)
        enabled = self.c.expect(
            "PATCH",
            path,
            200,
            patch({"op": "replace", "path": "active", "value": "true"}),
        ).document()
        require(enabled["active"] is True, "Reactivation failed")
        require(
            self.native(self.user["id"])["permissions"] == before,
            "Deactivate/restart/reactivate lost exact original native permissions",
        )
        authentication(200)
        self.server.restart()
        require(
            self.c.expect("GET", path, 200).document()["active"] is True,
            "Reactivated state did not survive restart",
        )
        require(
            self.native(self.user["id"])["permissions"] == before,
            "Restored native permissions changed across restart",
        )
        authentication(200)
        own = ROOT + "/Users/" + self.service_id
        self.c.expect(
            "PATCH",
            own,
            403,
            patch({"op": "replace", "path": "active", "value": False}),
        )
        self.c.expect("DELETE", own, 403)
        self.c.expect("GET", own, 200)

    def groups(self):
        self.needed_user()
        response = self.c.expect(
            "POST",
            ROOT + "/Groups",
            201,
            {
                "schemas": [CORE + "Group"],
                "displayName": "Native Fixture Group",
                "externalId": "native-fixture-group",
                "members": [{"value": self.user["id"], "type": "User"}],
            },
        )
        self.group = response.document()
        path = ROOT + "/Groups/" + self.group["id"]
        require(
            {m["value"] for m in self.group["members"]} == {self.user["id"]},
            "Group creation lost members",
        )
        user = self.c.expect("GET", self.needed_user(), 200).document()
        require(
            self.group["id"] in {g["value"] for g in user.get("groups", [])},
            "User reverse membership missing",
        )
        before_membership = self.c.expect("GET", path, 200).headers.get("ETag")
        removed = self.c.expect(
            "PATCH",
            path,
            200,
            patch(
                {"op": "remove", "path": 'members[value eq "' + self.user["id"] + '"]'}
            ),
        )
        group = removed.document()
        require(
            before_membership
            and removed.headers.get("ETag")
            and removed.headers["ETag"] != before_membership,
            "Group ETag does not cover membership",
        )
        require(not group.get("members"), "Filtered member removal failed")
        require(
            not self.c.expect("GET", self.needed_user(), 200).document().get("groups"),
            "Reverse membership survived removal",
        )
        self.c.expect(
            "PATCH",
            path,
            200,
            patch(
                {"op": "add", "path": "members", "value": [{"value": self.user["id"]}]}
            ),
        )
        self.c.expect(
            "POST",
            ROOT + "/Groups",
            409,
            {"schemas": [CORE + "Group"], "displayName": "Native Fixture Group"},
            scim_type="uniqueness",
        )
        self.c.expect(
            "PATCH",
            path,
            400,
            patch(
                {
                    "op": "add",
                    "path": "members",
                    "value": [{"value": self.group["id"], "type": "Group"}],
                }
            ),
            scim_type="invalidValue",
        )

    def closed_domain(self):
        self.c.expect("GET", ROOT + "/Users/" + self.hidden_id, 404)
        result = self.c.expect(
            "GET",
            query(ROOT + "/Users", filter='userName eq "hidden@closed.test"'),
            200,
        ).document()
        require(result["totalResults"] == 0, "Opt-out domain account visible in search")
        self.c.expect(
            "POST",
            ROOT + "/Users",
            400,
            user_body("closed", userName="new@closed.test"),
            scim_type="invalidValue",
        )
        self.c.expect(
            "POST",
            ROOT + "/Users",
            400,
            user_body("closed-alias", emails=[{"value": "alias@closed.test"}]),
            scim_type="invalidValue",
        )

    def etags(self):
        path = self.needed_user()
        response = self.c.expect("GET", path, 200)
        old = response.headers.get("ETag")
        require(
            old and old == response.document()["meta"].get("version"),
            "ETag missing or inconsistent with meta.version",
        )
        again = self.c.expect("GET", path, 200)
        require(again.headers.get("ETag") == old, "ETag changed without mutation")
        updated = self.c.expect(
            "PATCH",
            path,
            200,
            patch({"op": "replace", "path": "displayName", "value": "ETag mutation"}),
            headers={"If-Match": old},
        )
        new = updated.headers.get("ETag")
        require(new and new != old, "ETag did not change on mutation")
        no_op = self.c.expect(
            "PATCH",
            path,
            200,
            patch({"op": "replace", "path": "displayName", "value": "ETag mutation"}),
            headers={"If-Match": new},
        )
        require(
            no_op.headers.get("ETag") == new,
            "Content-derived ETag changed on a no-op mutation",
        )
        self.c.expect(
            "PATCH",
            path,
            412,
            patch({"op": "replace", "path": "displayName", "value": "stale"}),
            headers={"If-Match": old},
        )
        self.c.expect("DELETE", path, 412, headers={"If-Match": old})
        require(
            self.c.expect("GET", path, 200).document()["displayName"]
            == "ETag mutation",
            "Stale write changed resource",
        )

    def fake_idp_jit_authority(self):
        """Restore global settings/base domains even if the live JIT phase fails."""
        with restored_configuration(
            self.c, [self.domain_id, self.closed_domain_id]
        ) as authentication:
            self._fake_idp_jit_authority(authentication)

    def _fake_idp_jit_authority(self, authentication):
        """Real opaque OIDC auth/JIT; no actual Pocket ID or JWT-signing claim."""
        domain_names = ("jit-switch.test", "jit-unmanaged.test")
        domains = self.c.jmap(
            "x:Domain/set",
            {
                "create": {
                    name: {
                        "name": name,
                        "isEnabled": True,
                        "allowScimProvisioning": False,
                        "certificateManagement": {"@type": "Manual"},
                        "dkimManagement": {"@type": "Manual"},
                        "dnsManagement": {"@type": "Manual"},
                    }
                    for name in domain_names
                }
            },
        )["created"]
        switch_id = domains["jit-switch.test"]["id"]
        unmanaged_id = domains["jit-unmanaged.test"]["id"]
        require(
            len({switch_id, unmanaged_id, self.domain_id, self.closed_domain_id}) == 4,
            "Native domain creation reused an existing fixture domain ID",
        )

        def find_native(name, domain_id):
            # Recovery administration, never a new permission on the SCIM key.
            accounts = self.c.jmap("x:Account/get", {})["list"]
            found = [
                account
                for account in accounts
                if account.get("name") == name and account.get("domainId") == domain_id
            ]
            require(len(found) <= 1, "JIT created duplicate native identities")
            return found[0] if found else None

        def semantics(account):
            return {
                key: account.get(key)
                for key in (
                    "name",
                    "domainId",
                    "description",
                    "aliases",
                    "externalId",
                    "permissions",
                    "memberGroupIds",
                    "roles",
                    "locale",
                    "timeZone",
                    "credentials",
                )
            }

        # The global directory setting is OSS. Per-domain directoryId remains an
        # unrelated Enterprise feature and is deliberately not enabled here.
        # A recovery-only database may have no default role grants. Create
        # narrow temporary User and Admin roles so the OIDC authorization test
        # proves only the configured group adds the management permission.
        jit_role = self.c.jmap(
            "x:Role/set",
            {
                "create": {
                    "fixture": {
                        "description": "Disposable JIT authentication only",
                        "enabledPermissions": {"authenticate": True},
                    }
                }
            },
        )["created"]["fixture"]["id"]
        jit_admin_role = self.c.jmap(
            "x:Role/set",
            {
                "create": {
                    "admin": {
                        "description": "Disposable OIDC JIT administrator",
                        "enabledPermissions": {"sysNetworkListenerQuery": True},
                    }
                }
            },
        )["created"]["admin"]["id"]
        with FakeIdP(self.c.redactor) as provider:
            directory = self.c.jmap(
                "x:Directory/set",
                {
                    "create": {
                        "fixture": {
                            "@type": "Oidc",
                            "description": "Disposable loopback opaque-token IdP",
                            "issuerUrl": provider.origin,
                            "claimUsername": "email",
                            "claimName": "name",
                            "claimGroups": "groups",
                            "requireScopes": {},
                        }
                    }
                },
            )["created"]["fixture"]["id"]
            try:
                self.c.jmap(
                    "x:Authentication/set",
                    {
                        "update": {
                            "singleton": {
                                "directoryId": directory,
                                "defaultUserRoleIds": {jit_role: True},
                                "defaultAdminRoleIds": {jit_admin_role: True},
                            }
                        }
                    },
                )
                # The pinned native API has an explicit ReloadSettings action;
                # saving Authentication/Directory alone does NOT activate Core.
                self.c.jmap(
                    "x:Action/set", {"create": {"reload": {"@type": "ReloadSettings"}}}
                )
                provider.wait_discovered(timeout=15)

                def login(email, name, groups, status=200):
                    # A fresh opaque token forces real userinfo/JIT instead of a
                    # previously cached HTTP credential. Each probe proves a hit.
                    token = provider.issue(email, name, groups)
                    self.c.expect("GET", "/api/account", status, auth="Bearer " + token)
                    require(
                        provider.hit_count(token) >= 1,
                        "Authentication bypassed the fixture IdP userinfo/JIT path",
                    )
                    return token

                def expect_admin_query(token, allowed):
                    response = self.c.request(
                        "POST",
                        "/jmap",
                        {
                            "using": ["urn:ietf:params:jmap:core", "urn:stalwart:jmap"],
                            "methodCalls": [["x:NetworkListener/query", {}, "admin"]],
                        },
                        auth="Bearer " + token,
                    )
                    require(response.status == 200, "Admin permission probe failed")
                    method, result, _ = response.document()["methodResponses"][0]
                    if allowed:
                        require(
                            method == "x:NetworkListener/query",
                            f"Configured OIDC admin group was not elevated: {method} {result}",
                        )
                    else:
                        require(
                            method == "error" and result.get("type") == "forbidden",
                            "Non-admin OIDC group received management permission",
                        )

                nonadmin_token = login(
                    "nonadmin@jit-switch.test",
                    "Non-admin OIDC profile",
                    ["administrator"],
                )
                expect_admin_query(nonadmin_token, False)
                admin_token = login(
                    "oidc-admin@jit-switch.test",
                    "OIDC admin profile",
                    ["mail-support", "admin"],
                )
                expect_admin_query(admin_token, True)
                oidc_admin = find_native("oidc-admin", switch_id)
                require(
                    oidc_admin is not None
                    and oidc_admin.get("roles", {}).get("@type") == "User"
                    and not oidc_admin.get("memberGroupIds"),
                    "OIDC administration persisted a native role or group membership",
                )
                require(
                    find_native("mail-support", switch_id) is None,
                    "OIDC authorization groups created a native mailbox group",
                )

                require(
                    find_native("warm", switch_id) is None,
                    "Warm identity existed before real JIT",
                )
                login("warm@jit-switch.test", "Warm unmanaged profile", [])
                warm = find_native("warm", switch_id)
                require(
                    warm is not None
                    and warm.get("description") == "Warm unmanaged profile",
                    "Real OIDC userinfo did not JIT-create the warm identity",
                )
                require(
                    "/.well-known/openid-configuration" in provider.paths
                    and "/jwks" in provider.paths,
                    "Native OIDC directory did not fetch discovery and JWKS",
                )
                warm_semantics = semantics(warm)

                # No restart and NO intervening SCIM/account mutation: the next
                # request must observe the domain toggle despite the warm cache.
                self.c.jmap(
                    "x:Domain/set",
                    {"update": {switch_id: {"allowScimProvisioning": True}}},
                )
                login("warm@jit-switch.test", "Must not overwrite after toggle", [])
                require(
                    semantics(self.native(warm["id"])) == warm_semantics,
                    "Warm pre-toggle domain cache allowed IdP profile overwrite",
                )
                login("absent@jit-switch.test", "Must not JIT-create", [], status=401)
                require(
                    find_native("absent", switch_id) is None,
                    "Opted-in domain JIT created a missing identity despite denial",
                )

                # Also prove preservation of values actually written via native
                # SCIM, especially aliases that OIDC's empty alias list could erase.
                warm_path = ROOT + "/Users/" + warm["id"]
                provisioned = self.c.expect(
                    "PUT",
                    warm_path,
                    200,
                    {
                        "schemas": [CORE + "User"],
                        "userName": "warm@jit-switch.test",
                        "externalId": "fixture-jit-authoritative",
                        "displayName": "SCIM authoritative profile",
                        "emails": [{"value": "retained-alias@jit-switch.test"}],
                        "active": True,
                        "locale": "en-US",
                        "timezone": "Europe/Lisbon",
                    },
                ).document()
                native_provisioned = semantics(self.native(warm["id"]))
                login(
                    "warm@jit-switch.test",
                    "IdP replacement must be ignored",
                    ["injected@jit-switch.test"],
                )
                require(
                    self.c.expect("GET", warm_path, 200).document() == provisioned,
                    "Real JIT changed a SCIM-provisioned representation",
                )
                require(
                    semantics(self.native(warm["id"])) == native_provisioned,
                    "Real JIT altered native SCIM-authoritative state",
                )
                require(
                    find_native("injected", switch_id) is None,
                    "JIT created an injected group in an opted-in domain",
                )

                # A user's domain alone is not the membership authority boundary.
                # The outsider stays unmanaged, while BOTH groups are protected by
                # their opted-in domain (the normal SCIM fixture domain).
                protected = []
                for suffix in ("remove", "add"):
                    group = self.c.expect(
                        "POST",
                        ROOT + "/Groups",
                        201,
                        {
                            "schemas": [CORE + "Group"],
                            "displayName": "JIT protected " + suffix,
                        },
                    ).document()
                    native_group = self.native(group["id"])
                    address = native_group.get("emailAddress")
                    require(
                        isinstance(address, str) and address.endswith("@" + DOMAIN),
                        "Protected fixture group has no native email identity",
                    )
                    protected.append((group["id"], address))
                remove_group, add_group = protected
                login("outsider@jit-unmanaged.test", "Initial unmanaged profile", [])
                outsider = find_native("outsider", unmanaged_id)
                require(
                    outsider is not None,
                    "Unmanaged outsider was not created by real JIT",
                )
                self.c.jmap(
                    "x:Account/set",
                    {
                        "update": {
                            outsider["id"]: {"memberGroupIds": {remove_group[0]: True}}
                        }
                    },
                )
                membership_before = self.native(outsider["id"])["memberGroupIds"]
                login(
                    "outsider@jit-unmanaged.test",
                    "Changed unmanaged profile",
                    [add_group[1]],
                )
                changed = self.native(outsider["id"])
                require(
                    changed.get("description") == "Changed unmanaged profile",
                    "Outsider login did not exercise ordinary JIT profile synchronization",
                )
                require(
                    changed.get("memberGroupIds") == membership_before,
                    "Unmanaged JIT gained or removed a protected-group membership",
                )
                require(
                    remove_group[0] in changed["memberGroupIds"]
                    and add_group[0] not in changed["memberGroupIds"],
                    "Protected membership add/remove boundary failed",
                )
                # Empty groups tests omission/removal separately from a rejected
                # addition. Again the user's ordinary profile must still change.
                login("outsider@jit-unmanaged.test", "Empty group claims profile", [])
                changed = self.native(outsider["id"])
                require(
                    changed.get("description") == "Empty group claims profile"
                    and changed.get("memberGroupIds") == membership_before,
                    "Empty IdP groups removed protected native membership",
                )
                print(
                    "Real opaque-token OIDC/JIT exercised with loopback discovery/JWKS/userinfo; JWT signatures and authorization-code flow remain untested",
                    flush=True,
                )
            finally:
                # Restore native authentication while the provider is still alive,
                # then remove its directory before stopping the HTTP thread.
                self.c.jmap(
                    "x:Authentication/set", {"update": {"singleton": authentication}}
                )
                self.c.jmap(
                    "x:Domain/set",
                    {
                        "update": {
                            switch_id: {"allowScimProvisioning": False},
                            unmanaged_id: {"allowScimProvisioning": False},
                        }
                    },
                )
                self.c.jmap(
                    "x:Action/set", {"create": {"reload": {"@type": "ReloadSettings"}}}
                )
                self.c.jmap("x:Directory/set", {"destroy": [directory]})
                self.c.jmap(
                    "x:Role/set", {"destroy": [jit_role, jit_admin_role]}
                )

    def native_jmap_invalidation(self):
        """Ordinary registry writes must invalidate SCIM snapshots/preconditions."""
        path = self.needed_user()
        require(self.group is not None, "Blocked: group creation failed (not skipped)")
        original = self.c.expect("GET", path, 200)
        old = original.headers.get("ETag")
        require(old, "User ETag missing before native mutation")
        self.c.jmap(
            "x:Account/set",
            {"update": {self.hidden_id: {"description": "Unrelated native B change"}}},
        )
        unrelated = self.c.expect("GET", path, 200)
        require(
            unrelated.headers.get("ETag") == old
            and unrelated.document() == original.document(),
            "Unrelated native B mutation invalidated content-derived ETag/resource A",
        )
        self.c.expect(
            "PATCH",
            path,
            200,
            patch(
                {
                    "op": "replace",
                    "path": "displayName",
                    "value": original.document()["displayName"],
                }
            ),
            headers={"If-Match": old},
        )
        self.c.jmap(
            "x:Account/set",
            {"update": {self.user["id"]: {"description": "Ordinary JMAP update"}}},
        )
        current = self.c.expect("GET", path, 200)
        require(
            current.document()["displayName"] == "Ordinary JMAP update",
            "Native JMAP account update left stale SCIM snapshot",
        )
        require(
            current.headers.get("ETag") and current.headers["ETag"] != old,
            "Native JMAP update did not invalidate SCIM ETag",
        )
        self.c.expect(
            "PATCH",
            path,
            412,
            patch(
                {
                    "op": "replace",
                    "path": "displayName",
                    "value": "must not overwrite native update",
                }
            ),
            headers={"If-Match": old},
        )
        self.c.expect("DELETE", path, 412, headers={"If-Match": old})
        require(
            self.native(self.user["id"])["description"] == "Ordinary JMAP update",
            "Stale SCIM write destroyed native update",
        )

        group_path = ROOT + "/Groups/" + self.group["id"]
        group_before = self.c.expect("GET", group_path, 200)
        group_etag = group_before.headers.get("ETag")
        require(group_etag, "Group ETag missing before native membership mutation")
        original_memberships = self.native(self.user["id"]).get("memberGroupIds", {})
        require(
            original_memberships.get(self.group["id"]) is True,
            "Fixture user is not a native group member",
        )
        removed_memberships = {
            key: value
            for key, value in original_memberships.items()
            if key != self.group["id"]
        }
        self.c.jmap(
            "x:Account/set",
            {"update": {self.user["id"]: {"memberGroupIds": removed_memberships}}},
        )
        removed = self.c.expect("GET", group_path, 200)
        require(
            self.user["id"]
            not in {
                member["value"] for member in removed.document().get("members", [])
            },
            "Native membership removal left stale SCIM group members",
        )
        require(
            removed.headers.get("ETag") and removed.headers["ETag"] != group_etag,
            "Group ETag ignores ordinary native membership writes",
        )
        require(
            self.group["id"]
            not in {
                group["value"]
                for group in self.c.expect("GET", path, 200)
                .document()
                .get("groups", [])
            },
            "Native membership removal left stale SCIM reverse membership",
        )
        self.c.expect(
            "PATCH",
            group_path,
            412,
            patch(
                {"op": "add", "path": "members", "value": [{"value": self.user["id"]}]}
            ),
            headers={"If-Match": group_etag},
        )
        require(
            self.native(self.user["id"]).get("memberGroupIds", {})
            == removed_memberships,
            "Stale group PATCH resurrected a natively removed membership",
        )
        self.c.jmap(
            "x:Account/set",
            {"update": {self.user["id"]: {"memberGroupIds": original_memberships}}},
        )
        restored = self.c.expect("GET", group_path, 200)
        require(
            self.user["id"]
            in {member["value"] for member in restored.document().get("members", [])},
            "Native membership restoration did not reach SCIM group",
        )
        require(
            restored.headers.get("ETag") != removed.headers.get("ETag"),
            "Restored native membership did not invalidate group ETag",
        )
        require(
            self.group["id"]
            in {
                group["value"]
                for group in self.c.expect("GET", path, 200)
                .document()
                .get("groups", [])
            },
            "Restored native membership did not reach SCIM user",
        )

    def parallel_registry_writes(self):
        """Exercise possible overlapping writes; this is not a scheduling proof."""
        response = self.c.expect(
            "POST",
            ROOT + "/Users",
            201,
            user_body(
                "parallel-fixture",
                externalId="race-initial",
                displayName="Race initial",
            ),
        )
        race_id = response.document()["id"]
        path = ROOT + "/Users/" + race_id
        port = urllib.parse.urlsplit(self.c.origin).port

        def client():
            # urllib openers are deliberately not shared across worker threads.
            instance = Client(port, self.c.redactor)
            instance.token, instance.recovery = self.c.token, self.c.recovery
            return instance

        try:
            for iteration in range(4):
                before = self.c.expect("GET", path, 200)
                etag = before.headers.get("ETag")
                require(etag, "Concurrent conditional-write fixture has no ETag")
                left, right = client(), client()
                a, b = f"Conditional A {iteration}", f"Conditional B {iteration}"
                outcomes = parallel_pair(
                    partial(
                        left.request,
                        "PATCH",
                        path,
                        patch({"op": "replace", "path": "displayName", "value": a}),
                        headers={"If-Match": etag},
                    ),
                    partial(
                        right.request,
                        "PATCH",
                        path,
                        patch({"op": "replace", "path": "displayName", "value": b}),
                        headers={"If-Match": etag},
                    ),
                )
                require(
                    sorted(result.status for result in outcomes) == [200, 412],
                    f"Two concurrent writes with one ETag must have one winner and one 412, got {[result.status for result in outcomes]}",
                )
                winner = a if outcomes[0].status == 200 else b
                require(
                    self.c.expect("GET", path, 200).document()["displayName"] == winner,
                    "Losing conditional write overwrote the winner",
                )
                loser = next(
                    result for result in outcomes if result.status == 412
                ).document()
                require(
                    loser.get("status") == "412"
                    and MESSAGE + "Error" in loser.get("schemas", []),
                    "Concurrent stale-write response is not a SCIM 412 error",
                )

            for iteration in range(12):
                before_response = self.c.expect("GET", path, 200)
                before = before_response.document()
                etag = before_response.headers.get("ETag")
                require(etag, "Native/SCIM race fixture has no ETag")
                native_marker, scim_marker = (
                    f"native-race-{iteration}",
                    f"SCIM race {iteration}",
                )
                native_client, scim_client = client(), client()
                # Full replacement intentionally carries the old externalId. A
                # broken stale-snapshot write can erase the concurrent JMAP value;
                # a PATCH of disjoint fields alone would miss that regression.
                replacement = user_body(
                    "parallel-fixture",
                    externalId=before["externalId"],
                    displayName=scim_marker,
                )
                _, outcome = parallel_pair(
                    partial(
                        native_client.jmap,
                        "x:Account/set",
                        {"update": {race_id: {"externalId": native_marker}}},
                    ),
                    partial(
                        scim_client.request,
                        "PUT",
                        path,
                        replacement,
                        headers={"If-Match": etag},
                    ),
                )
                after = self.c.expect("GET", path, 200).document()
                check_native_race(
                    before, after, native_marker, scim_marker, outcome.status
                )
                require(
                    self.native(race_id)["externalId"] == native_marker,
                    "Native registry lost acknowledged JMAP race update",
                )
                if outcome.status == 412:
                    error = outcome.document()
                    require(
                        error.get("status") == "412"
                        and MESSAGE + "Error" in error.get("schemas", []),
                        "Native/SCIM race rejection is not a SCIM 412 error",
                    )
            print(
                "Parallel requests checked: 4 same-ETag pairs, 12 native-JMAP/SCIM pairs; transaction overlap is not instrumented",
                flush=True,
            )
        finally:
            # Native recovery cleanup is independent of SCIM success. The whole
            # database is temporary even if this explicit cleanup itself fails.
            self.c.jmap("x:Account/set", {"destroy": [race_id]})

    def search_projection(self):
        path = self.needed_user()
        result = self.c.expect(
            "GET",
            query(ROOT + "/Users", filter='externalId eq "native-fixture-user"'),
            200,
        ).document()
        require(
            result["totalResults"] == 1
            and result["Resources"][0]["id"] == self.user["id"],
            "externalId filter failed",
        )
        self.c.expect(
            "GET",
            query(
                ROOT + "/Users",
                filter='emails eq "alice-renamed@example.test" and active eq true',
            ),
            200,
        )
        projected = self.c.expect(
            "GET", query(path, attributes="userName,emails.value"), 200
        ).document()
        require(
            set(projected) == {"schemas", "id", "userName", "emails"},
            "Projection leaked default fields or omitted always-returned fields",
        )
        require(
            all(set(e) == {"value"} for e in projected["emails"]),
            "Complex sub-attribute projection failed",
        )
        excluded = self.c.expect(
            "GET", query(path, excludedAttributes="id,schemas,emails"), 200
        ).document()
        require(
            "id" in excluded and "schemas" in excluded and "emails" not in excluded,
            "Always-returned/exclusion semantics failed",
        )
        result = self.c.expect(
            "POST",
            ROOT + "/Users/.search",
            200,
            {
                "schemas": [MESSAGE + "SearchRequest"],
                "filter": 'externalId eq "native-fixture-user"',
            },
        ).document()
        require(result["totalResults"] == 1, "POST search differs from GET")
        result = self.c.expect(
            "POST",
            ROOT + "/.search",
            200,
            {
                "schemas": [MESSAGE + "SearchRequest"],
                "filter": 'externalId eq "native-fixture-group"',
            },
        ).document()
        require(
            result["totalResults"] == 1
            and result["Resources"][0]["id"] == self.group["id"],
            "Root POST search did not include Groups",
        )

    def bulk(self):
        request = {
            "schemas": [MESSAGE + "BulkRequest"],
            "failOnErrors": 1,
            "Operations": [
                {
                    "method": "POST",
                    "bulkId": "bulk-group",
                    "path": "/Groups",
                    "data": {
                        "schemas": [CORE + "Group"],
                        "displayName": "Bulk Forward Group",
                        "members": [{"value": "bulkId:bulk-user"}],
                    },
                },
                {
                    "method": "POST",
                    "bulkId": "bulk-user",
                    "path": "/Users",
                    "data": user_body("bulk-user", externalId="native-bulk-user"),
                },
            ],
        }
        result = self.c.expect("POST", ROOT + "/Bulk", 200, request).document()
        require(
            MESSAGE + "BulkResponse" in result.get("schemas", []),
            "Missing BulkResponse schema",
        )
        ops = {op.get("bulkId"): op for op in result["Operations"]}
        require(
            {"bulk-group", "bulk-user"}.issubset(ops),
            f"Bulk omitted requested operation identities: {result}",
        )
        for bulk_id in ("bulk-group", "bulk-user"):
            require(
                ops[bulk_id]["status"] == "201", f"Bulk forward reference failed: {ops}"
            )
            location = same_origin_path(ops[bulk_id]["location"], self.c.origin)
            self.bulk_ids.append(location)
        group = self.c.expect(
            "GET", same_origin_path(ops["bulk-group"]["location"], self.c.origin), 200
        ).document()
        user_id = same_origin_path(ops["bulk-user"]["location"], self.c.origin).rsplit(
            "/", 1
        )[1]
        require(
            {m["value"] for m in group["members"]} == {user_id},
            "Bulk forward member was not resolved",
        )
        partial = self.c.expect(
            "POST",
            ROOT + "/Bulk",
            200,
            {
                "schemas": [MESSAGE + "BulkRequest"],
                "Operations": [
                    {
                        "method": "POST",
                        "bulkId": "partial-good",
                        "path": "/Users",
                        "data": user_body("partial-good"),
                    },
                    {
                        "method": "POST",
                        "bulkId": "partial-bad",
                        "path": "/Users",
                        "data": {"userName": "missing-schema@example.test"},
                    },
                ],
            },
        ).document()["Operations"]
        partial = {op["bulkId"]: op for op in partial}
        require(
            partial["partial-good"]["status"] == "201"
            and partial["partial-bad"]["status"] == "400",
            "Bulk partial failure rolled back success or hid failure",
        )
        self.bulk_ids.append(
            same_origin_path(partial["partial-good"]["location"], self.c.origin)
        )
        self.c.expect("GET", self.bulk_ids[-1], 200)
        boundary = {
            "schemas": [MESSAGE + "BulkRequest"],
            "Operations": [{"method": "DELETE", "path": "/Users/0"}] * 1000,
        }
        accepted = self.c.expect("POST", ROOT + "/Bulk", 200, boundary).document()[
            "Operations"
        ]
        require(
            len(accepted) == 1000 and all(op["status"] == "404" for op in accepted),
            "Bulk 1000-operation boundary was not processed",
        )
        oversize = {
            "schemas": [MESSAGE + "BulkRequest"],
            "Operations": [{"method": "DELETE", "path": "/Users/0"}] * 1001,
        }
        self.c.expect("POST", ROOT + "/Bulk", 413, oversize)
        self.c.expect("POST", ROOT + "/Bulk", 413, raw=b" " * (1024 * 1024 + 1))

    def pagination_limits(self):
        # More than 200 real candidates proves caps and the non-indexed guard;
        # a tiny fixture cannot distinguish an ignored count from a valid cap.
        creations = {
            f"page{i:03d}": {
                "@type": "User",
                "name": f"page{i:03d}",
                "domainId": self.domain_id,
                "roles": {"@type": "User"},
                "credentials": {},
                "encryptionAtRest": {"@type": "Disabled"},
            }
            for i in range(205)
        }
        for start in range(0, 205, 40):
            selected = dict(list(creations.items())[start : start + 40])
            self.c.jmap("x:Account/set", {"create": selected})
        default = self.c.expect("GET", ROOT + "/Users", 200).document()
        require(
            default["itemsPerPage"] == len(default["Resources"]) == 100,
            f"Default page size must be 100; totalResults={default.get('totalResults')}, itemsPerPage={default.get('itemsPerPage')}, actual={len(default.get('Resources', []))}",
        )
        capped = self.c.expect(
            "GET", query(ROOT + "/Users", count=1000), 200
        ).document()
        require(
            capped["itemsPerPage"] == len(capped["Resources"]) == 200,
            "Page cap must be 200",
        )
        zero = self.c.expect("GET", query(ROOT + "/Users", count=0), 200).document()
        require(
            zero["totalResults"] > 200
            and zero["itemsPerPage"] == 0
            and not zero["Resources"],
            "count=0 must preserve totalResults only",
        )
        first = self.c.expect(
            "GET",
            query(
                ROOT + "/Users",
                sortBy="userName",
                sortOrder="ascending",
                startIndex=1,
                count=3,
            ),
            200,
        ).document()
        second = self.c.expect(
            "GET",
            query(
                ROOT + "/Users",
                sortBy="userName",
                sortOrder="ascending",
                startIndex=4,
                count=3,
            ),
            200,
        ).document()
        names = [r["userName"] for r in first["Resources"] + second["Resources"]]
        require(
            names == sorted(names) and len(set(names)) == 6,
            "Indexed sorted pages overlap or are unordered",
        )
        descending = self.c.expect(
            "GET",
            query(ROOT + "/Users", sortBy="userName", sortOrder="descending", count=5),
            200,
        ).document()
        names = [r["userName"] for r in descending["Resources"]]
        require(names == sorted(names, reverse=True), "Descending sort ignored")
        self.c.expect(
            "GET",
            query(ROOT + "/Users", sortBy="displayName"),
            400,
            scim_type="invalidValue",
        )
        self.c.expect(
            "GET",
            query(ROOT + "/Groups", sortBy="userName"),
            400,
            scim_type="invalidValue",
        )
        self.c.expect(
            "GET",
            query(ROOT + "/Users", filter="active eq true"),
            400,
            scim_type="tooMany",
        )
        narrowed = self.c.expect(
            "GET",
            query(
                ROOT + "/Users",
                filter='userName eq "page001@example.test" and active eq true',
            ),
            200,
        ).document()
        require(
            narrowed["totalResults"] == 1,
            "Indexed conjunction did not narrow non-indexed evaluation",
        )
        cursor_page = self.c.expect(
            "GET", query(ROOT + "/Users", cursor="", count=3, sortBy="id"), 200
        ).document()
        cursor = cursor_page.get("nextCursor")
        require(
            isinstance(cursor, str) and cursor,
            "Cursor pagination must return nextCursor",
        )
        next_page = self.c.expect(
            "GET", query(ROOT + "/Users", cursor=cursor, count=3, sortBy="id"), 200
        ).document()
        require(
            not (
                {r["id"] for r in cursor_page["Resources"]}
                & {r["id"] for r in next_page["Resources"]}
            ),
            "Cursor page repeated resources",
        )
        self.c.expect(
            "GET",
            query(ROOT + "/Users", cursor=cursor, count=3, sortBy="userName"),
            400,
        )

    def persistence(self):
        path = self.needed_user()
        require(self.group is not None, "Blocked: group creation failed (not skipped)")
        group_path = ROOT + "/Groups/" + self.group["id"]
        before = self.c.expect("GET", path, 200).document()
        before_group = self.c.expect("GET", group_path, 200).document()
        self.server.restart()
        after = self.c.expect("GET", path, 200).document()
        after_group = self.c.expect("GET", group_path, 200).document()
        require(
            after == before and after_group == before_group,
            "SCIM state or metadata changed across process restart",
        )
        require(
            after["externalId"] == "native-fixture-user"
            and after_group["externalId"] == "native-fixture-group",
            "externalId persistence missing",
        )
        require(
            self.native(after["id"])["externalId"] == after["externalId"],
            "Restart loaded adapter-only externalId",
        )

    def cleanup_resources(self):
        path = self.needed_user()
        require(self.group is not None, "Blocked: group creation failed (not skipped)")
        # Deleting a member must also clean native reverse membership.
        self.c.expect("DELETE", path, 204)
        self.c.expect("GET", path, 404)
        group_path = ROOT + "/Groups/" + self.group["id"]
        group = self.c.expect("GET", group_path, 200).document()
        require(not group.get("members"), "Deleted user remains a native group member")
        self.c.expect("DELETE", group_path, 204)
        self.c.expect("GET", group_path, 404)
        for location in self.bulk_ids:
            self.c.expect("DELETE", location, 204)
        ids = [self.user["id"], self.group["id"]] + [
            p.rsplit("/", 1)[1] for p in self.bulk_ids
        ]
        result = self.c.jmap("x:Account/get", {"ids": ids})
        require(
            not result.get("list") and set(result.get("notFound", [])) == set(ids),
            "SCIM deletion did not destroy native account objects",
        )
        for external in (
            "native-fixture-user",
            "native-fixture-group",
            "native-bulk-user",
        ):
            result = self.c.expect(
                "POST",
                ROOT + "/.search",
                200,
                {
                    "schemas": [MESSAGE + "SearchRequest"],
                    "filter": f'externalId eq "{external}"',
                },
            ).document()
            require(result["totalResults"] == 0, "Deleted externalId still resolves")
        replacement = self.c.expect(
            "POST",
            ROOT + "/Users",
            201,
            user_body(
                "alice-renamed",
                externalId="native-fixture-user",
                emails=[{"value": "patched@example.test"}],
            ),
        ).document()
        self.c.expect("DELETE", ROOT + "/Users/" + replacement["id"], 204)

    def admin_assets(self):
        root = Path(self.args.admin_assets)
        require(
            root.is_dir(), "--admin-assets must name a pinned extracted asset directory"
        )
        index = root / "index.html"
        require(index.is_file(), "Pinned asset fixture has no index.html")
        candidates = sorted(root.rglob("*.js"))
        require(candidates, "Pinned asset fixture has no JavaScript bundle")
        for source, path in (
            (index, "/"),
            (candidates[0], "/" + candidates[0].relative_to(root).as_posix()),
        ):
            response = self.c.expect("GET", path, 200, auth=None)
            data = (
                gzip.decompress(response.raw)
                if response.headers.get("Content-Encoding") == "gzip"
                else response.raw
            )
            require(
                hashlib.sha256(data).digest()
                == hashlib.sha256(source.read_bytes()).digest(),
                f"Served admin asset differs from pinned bytes: {path}",
            )

    def ui_checks(self):
        from ui import run_ui_checks

        # Admin resolves only configured defaultAdminRoleIds; recovery fixtures
        # can legitimately have none. Use explicit, bounded workflow permissions
        # on this disposable account, not a global Admin-role grant or all rights.
        permissions = dict.fromkeys(UI_PERMISSIONS, True)
        admin = self.create_native_user(
            "ui-admin", self.domain_id, admin=True, permissions=permissions
        )
        token = self.api_key(admin, permissions)
        info = self.c.expect(
            "GET", "/api/account", 200, auth="Bearer " + token
        ).document()
        require(
            info.get("edition") == "oss"
            and set(UI_PERMISSIONS).issubset(info.get("permissions", [])),
            "UI credential lacks explicitly provisioned workflow permissions",
        )
        target = self.create_native_user("ui-target", self.domain_id)
        result = run_ui_checks(
            self.c.origin,
            token,
            DOMAIN,
            domain_id=self.domain_id,
            account_id=target,
            external_id="ui-native-scim-acceptance",
            screenshot_path=self.args.screenshot,
            chromium_executable=self.args.chromium or shutil.which("chromium"),
        )
        require(isinstance(result, dict), "UI checks did not return their result")

    def run(self):
        # Pyzor is outside this SCIM fixture. An unresolvable host also makes
        # subsequent ReloadSettings calls detect any accidental re-enabling.
        self.c.jmap(
            "x:SpamPyzor/set",
            {
                "update": {
                    "singleton": {"enable": False, "host": "pyzor-fixture.invalid"}
                }
            },
        )
        with seeded_user_defaults(self.c):
            self._run_seeded()

    def _run_seeded(self):
        self.bootstrap()
        for name, method in (
            ("OSS management schema/hash", self.management_schema),
            ("Bearer-only discovery and target capabilities", self.auth_and_discovery),
            ("public endpoint/profile rejection", self.endpoint_errors),
            (
                "native empty-default entitlement remains failclosed",
                self.unconfigured_user_defaults,
            ),
            ("native user creation", self.create_user),
            ("PUT and atomic complex PATCH", self.put_and_patch),
            ("permission roundtrip and self-protection", self.permissions_roundtrip),
            ("native group membership", self.groups),
            ("opt-out domain isolation", self.closed_domain),
            (
                "real fake-IdP JIT authority and warmed domain cache",
                self.fake_idp_jit_authority,
            ),
            ("conditional ETag writes", self.etags),
            (
                "ordinary JMAP invalidates SCIM state and ETags",
                self.native_jmap_invalidation,
            ),
            ("parallel native/SCIM conditional writes", self.parallel_registry_writes),
            ("filter/search and projection", self.search_projection),
            ("Bulk forward references and limits", self.bulk),
            (
                "page limits, index/cursor sorting, candidate guard",
                self.pagination_limits,
            ),
            ("restart persistence", self.persistence),
            ("DELETE and native cleanup", self.cleanup_resources),
        ):
            self.stage(name, method)
        if self.args.admin_assets:
            self.stage("pinned HTTP admin assets", self.admin_assets)
        if self.args.ui_checks:
            self.stage("real native admin UI", self.ui_checks)
        require(not self.failures, "Acceptance failures: " + ", ".join(self.failures))


@contextmanager
def seeded_user_defaults(client):
    """Model an active-by-default deployment using native, minimal role policy.

    The SCIM implementation still inherits server policy; no grant is inserted by
    SCIM. Every original Authentication/default-role property is restored even
    when bootstrap or a later live phase fails.
    """
    rows = client.jmap("x:Authentication/get", {"ids": ["singleton"]}).get("list", [])
    require(
        len(rows) == 1, "Default User-role fixture cannot read Authentication singleton"
    )
    original = {key: value for key, value in rows[0].items() if key != "id"}
    role_id = client.jmap(
        "x:Role/set",
        {
            "create": {
                "fixture": {
                    "description": "Disposable active-by-default User: Authenticate only",
                    "enabledPermissions": {"authenticate": True},
                }
            }
        },
    )["created"]["fixture"]["id"]
    try:
        client.jmap(
            "x:Authentication/set",
            {"update": {"singleton": {"defaultUserRoleIds": {role_id: True}}}},
        )
        client.jmap("x:Action/set", {"create": {"reload": {"@type": "ReloadSettings"}}})
        roles = client.jmap("x:Role/get", {"ids": [role_id]}).get("list", [])
        require(
            len(roles) == 1
            and roles[0].get("enabledPermissions") == {"authenticate": True}
            and not roles[0].get("disabledPermissions")
            and not roles[0].get("roleIds"),
            "Fixture default User role is not strictly Authenticate-only",
        )
        configured = client.jmap("x:Authentication/get", {"ids": ["singleton"]})["list"]
        expected = {**original, "defaultUserRoleIds": {role_id: True}}
        require(
            len(configured) == 1
            and {key: value for key, value in configured[0].items() if key != "id"}
            == expected,
            "Seeding User default changed unrelated Authentication policy",
        )
        yield role_id
    finally:
        client.jmap("x:Authentication/set", {"update": {"singleton": original}})
        client.jmap("x:Action/set", {"create": {"reload": {"@type": "ReloadSettings"}}})
        restored = client.jmap("x:Authentication/get", {"ids": ["singleton"]})["list"]
        require(
            len(restored) == 1
            and {key: value for key, value in restored[0].items() if key != "id"}
            == original,
            "Default User-role fixture did not restore original Authentication policy",
        )
        client.jmap("x:Role/set", {"destroy": [role_id]})


@contextmanager
def restored_configuration(client, domain_ids):
    """Keep a failed JIT setup from changing subsequent fixture stage policy."""
    auth = client.jmap("x:Authentication/get", {"ids": ["singleton"]})["list"]
    require(len(auth) == 1, "Native Authentication singleton unavailable")
    authentication = {key: value for key, value in auth[0].items() if key != "id"}
    domains = client.jmap("x:Domain/get", {"ids": domain_ids})["list"]
    require(
        {domain["id"] for domain in domains} == set(domain_ids),
        "Fixture base domain snapshot incomplete",
    )
    body_failed = False
    try:
        yield authentication
    except BaseException:
        body_failed = True
        raise
    finally:
        current_domains = {
            domain["id"]: domain
            for domain in client.jmap("x:Domain/get", {"ids": domain_ids})["list"]
        }
        changed_base_policy = any(
            current_domains.get(domain["id"], {}).get("allowScimProvisioning", False)
            != domain.get("allowScimProvisioning", False)
            for domain in domains
        )
        if changed_base_policy:
            print(
                "JIT cleanup: restoring an unexpected change to a base domain provisioning flag",
                flush=True,
            )
        # Restore ALL Authentication properties, including every default role
        # map, not just directoryId. These are disposable local settings only.
        client.jmap("x:Authentication/set", {"update": {"singleton": authentication}})
        client.jmap(
            "x:Domain/set",
            {
                "update": {
                    domain["id"]: {
                        "allowScimProvisioning": domain.get(
                            "allowScimProvisioning", False
                        )
                    }
                    for domain in domains
                }
            },
        )
        client.jmap("x:Action/set", {"create": {"reload": {"@type": "ReloadSettings"}}})
        restored = client.jmap("x:Authentication/get", {"ids": ["singleton"]})["list"]
        require(
            len(restored) == 1
            and {key: value for key, value in restored[0].items() if key != "id"}
            == authentication,
            "JIT cleanup did not restore complete Authentication/default-role settings",
        )
        restored_domains = {
            domain["id"]: domain
            for domain in client.jmap("x:Domain/get", {"ids": domain_ids})["list"]
        }
        for domain in domains:
            current = restored_domains.get(domain["id"], {})
            require(
                current.get("name") == domain.get("name")
                and current.get("allowScimProvisioning", False)
                == domain.get("allowScimProvisioning", False),
                "JIT cleanup did not restore base domain identity/provisioning policy",
            )
        require(
            body_failed or not changed_base_policy,
            "JIT changed an unrelated base domain provisioning flag; restored, but not accepted",
        )


def parallel_pair(first, second):
    """Release two independent HTTP clients together, with bounded completion."""
    barrier = threading.Barrier(3)

    def run(operation):
        barrier.wait(timeout=10)
        return operation()

    with ThreadPoolExecutor(max_workers=2, thread_name_prefix="scim-race") as pool:
        futures = [pool.submit(run, operation) for operation in (first, second)]
        barrier.wait(timeout=10)
        return tuple(future.result(timeout=40) for future in futures)


def check_native_race(before, after, native_marker, scim_marker, scim_status):
    # These are the only successful serializations of an unconditional native
    # externalId write versus a full SCIM PUT guarded by the pre-race ETag.
    require(
        scim_status in (200, 412),
        f"Concurrent conditional PUT returned {scim_status}, expected 200 or 412",
    )
    require(
        after["externalId"] == native_marker,
        "Concurrent SCIM PUT lost the acknowledged native externalId update",
    )
    expected_display = scim_marker if scim_status == 200 else before["displayName"]
    require(
        after["displayName"] == expected_display,
        "Concurrent native update lost a successful SCIM write, or stale SCIM write committed",
    )


def namespace_id(kind):
    return os.stat(f"/proc/self/ns/{kind}").st_ino


def check_namespace(parent_net, parent_user):
    require(sys.platform == "linux", "Fixture requires Linux network/user namespaces")
    require(
        namespace_id("net") != parent_net and namespace_id("user") != parent_user,
        "Refusing to start without fresh user AND network namespaces",
    )
    require(os.geteuid() == 0, "Fixture requires unshare -Urn root mapping")
    mapping = Path("/proc/self/uid_map").read_text().split()
    require(
        len(mapping) == 3 and mapping[0] == "0" and mapping[2] == "1",
        "Expected a single-user unshare -Ur mapping",
    )
    require(
        [name for _, name in socket.if_nameindex()] == ["lo"],
        "Refusing a namespace with non-loopback interfaces",
    )
    ip = shutil.which("ip")
    require(ip is not None, "iproute2 is required to enable isolated loopback")
    subprocess.run([ip, "link", "set", "lo", "up"], check=True, timeout=10)
    interfaces = json.loads(
        subprocess.check_output([ip, "-j", "address", "show"], timeout=10)
    )
    require(
        len(interfaces) == 1 and interfaces[0]["ifname"] == "lo",
        "Namespace acquired a non-loopback interface",
    )
    for interface in interfaces:
        for address in interface.get("addr_info", []):
            require(
                ipaddress.ip_address(address["local"]).is_loopback,
                "Refusing a non-loopback address",
            )


def child_run(args):
    check_namespace(args.parent_netns, args.parent_userns)
    binary = Path(args.binary).resolve(strict=True)
    require(
        binary.is_file() and os.access(binary, os.X_OK),
        "Supplied binary is not executable",
    )
    redactor = Redactor()

    def interrupted(signum, frame):
        raise KeyboardInterrupt(f"Fixture interrupted by signal {signum}")

    previous = signal.signal(signal.SIGTERM, interrupted)
    try:
        with tempfile.TemporaryDirectory(prefix="stalwart-native-scim-") as directory:
            root = Path(directory)
            root.chmod(0o700)
            os.environ.update(
                {
                    "HOME": str(root),
                    "TMPDIR": str(root),
                    "XDG_CONFIG_HOME": str(root / "config"),
                    "XDG_CACHE_HOME": str(root / "cache"),
                }
            )
            with socket.socket() as reserved:
                reserved.bind(("127.0.0.1", 0))
                port = reserved.getsockname()[1]
            client = Client(port, redactor)
            server = Server(binary, root, client)
            try:
                server.start()
                Acceptance(client, server, args).run()
                print("Native SCIM isolated blackbox acceptance passed", flush=True)
            except BaseException:
                print(server.diagnostics(), file=sys.stderr, flush=True)
                raise
            finally:
                server.stop()
    finally:
        signal.signal(signal.SIGTERM, previous)


def launch(args):
    require(args.binary, "A parent-approved binary path is required")
    require(
        not (args.screenshot and not args.ui_checks),
        "--screenshot requires --ui-checks",
    )
    unshare = shutil.which("unshare")
    require(
        unshare is not None and sys.platform == "linux",
        "Linux util-linux unshare is required",
    )
    script = str(Path(__file__).resolve())
    argv = [
        unshare,
        "-Urn",
        "--",
        sys.executable,
        script,
        str(Path(args.binary).resolve(strict=True)),
        "--namespace-child",
        "--parent-netns",
        str(namespace_id("net")),
        "--parent-userns",
        str(namespace_id("user")),
    ]
    for flag in ("reference_schema", "admin_assets", "chromium", "screenshot"):
        if getattr(args, flag):
            argv.extend(
                [
                    "--" + flag.replace("_", "-"),
                    str(Path(getattr(args, flag)).resolve()),
                ]
            )
    if args.ui_checks:
        argv.append("--ui-checks")
    process = subprocess.Popen(argv, start_new_session=True, env=isolated_environment())

    def interrupted(signum, frame):
        raise KeyboardInterrupt(f"Fixture launcher interrupted by signal {signum}")

    previous = signal.signal(signal.SIGTERM, interrupted)
    try:
        return process.wait()
    except BaseException:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=40)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
        raise
    finally:
        signal.signal(signal.SIGTERM, previous)


class HelperTests(unittest.TestCase):
    def test_ui_field_label_matches_pinned_optional_marker(self):
        from ui import _label_pattern

        pattern = _label_pattern("External Identifier")
        for text in (
            "External Identifier",
            "External Identifier(optional)",
            "External Identifier (optional)",
            "External Identifier*",
            "External Identifier *",
            "External Identifier  (optional)  ",
        ):
            with self.subTest(text=text):
                self.assertIsNotNone(pattern.search(text))
        for text in (
            "External Identifier Other",
            "Other External Identifier",
            "External Identifier(optional) Other",
        ):
            with self.subTest(text=text):
                self.assertIsNone(pattern.search(text))

    def test_origin_guards(self):
        for path in (
            "https://production.test/x",
            "//production.test/x",
            "/x\r\nHost: other",
            "/\\other",
            "/x#fragment",
        ):
            with self.assertRaises(AssertionError):
                safe_path(path)
        self.assertEqual(
            same_origin_path("http://127.0.0.1:9/x", "http://127.0.0.1:9"), "/x"
        )
        with self.assertRaises(AssertionError):
            same_origin_path("http://127.0.0.1:10/x", "http://127.0.0.1:9")

    def test_schema_hash_and_gating(self):
        fields = {}
        for kind, name in SCIM_FIELDS | {
            ("x:Authentication", "defaultTenantRoleIds"),
            ("x:DataRetention", "archiveDeletedAccountsFor"),
            ("x:DataRetention", "holdMetricsFor"),
        }:
            fields.setdefault(kind, {"properties": {}})["properties"][name] = {
                "enterprise": (kind, name) not in SCIM_FIELDS
            }
        schema = {"fields": fields}
        raw = gzip.compress(encoded(schema), mtime=0)
        fingerprint = (
            base64.urlsafe_b64encode(hashlib.sha256(raw).digest()).decode().rstrip("=")
        )
        self.assertEqual(check_schema(raw, fingerprint), schema)
        with self.assertRaises(AssertionError):
            check_schema(raw, "wrong")
        reference = json.loads(json.dumps(schema))
        for kind, name in SCIM_FIELDS:
            reference["fields"][kind]["properties"][name]["enterprise"] = True
        check_schema(raw, fingerprint, reference)
        reference["fields"]["x:Authentication"]["properties"]["defaultTenantRoleIds"][
            "enterprise"
        ] = False
        with self.assertRaises(AssertionError):
            check_schema(raw, fingerprint, reference)

    def test_key_scope_and_redaction(self):
        self.assertEqual(len(SCIM_PERMISSIONS), 6)
        self.assertFalse(
            any(
                p.startswith("sysDomain") or p == "sysAccountQuery"
                for p in SCIM_PERMISSIONS
            )
        )
        redactor = Redactor()
        redactor.add("secret-key")
        self.assertNotIn("secret-key", redactor("authorization secret-key"))

    def test_host_namespace_is_rejected_before_commands(self):
        with (
            mock.patch(__name__ + ".namespace_id", return_value=123),
            mock.patch.object(subprocess, "run") as run,
        ):
            with self.assertRaises(AssertionError):
                check_namespace(123, 456)
            run.assert_not_called()

    def test_server_environment_and_teardown_without_processes(self):
        with tempfile.TemporaryDirectory(prefix="native-scim-helper-") as directory:
            root = Path(directory)
            client = Client(12345, Redactor())
            process = mock.Mock(pid=98765)
            process.poll.return_value = None
            process.wait.return_value = 0
            with (
                mock.patch.object(subprocess, "Popen", return_value=process) as spawn,
                mock.patch.object(os, "killpg") as kill,
                mock.patch.object(
                    client,
                    "request",
                    return_value=Response(200, {}, b'{"edition":"oss"}'),
                ),
                mock.patch.dict(
                    os.environ,
                    {
                        "PRODUCTION_API_KEY": "must-not-inherit",
                        "STALWART_CONFIG": "must-not-inherit",
                    },
                ),
            ):
                server = Server(Path("/not/executed/stalwart"), root, client)
                server.start()
                environment = spawn.call_args.kwargs["env"]
                self.assertNotIn("PRODUCTION_API_KEY", isolated_environment())
                self.assertNotIn("STALWART_CONFIG", isolated_environment())
                self.assertNotIn("PRODUCTION_API_KEY", environment)
                self.assertNotIn("STALWART_CONFIG", environment)
                self.assertEqual(
                    json.loads(server.config.read_bytes())["path"], str(root / "data")
                )
                server.stop()
                self.assertIsNone(server.process)
                self.assertIsNone(server.log)
                kill.assert_has_calls(
                    [mock.call(98765, signal.SIGTERM), mock.call(98765, signal.SIGKILL)]
                )
                process.wait.assert_called_once_with(timeout=20)

    def test_user_body_accepts_structured_name_without_argument_collision(self):
        body = user_body("alice", name={"formatted": "Alice"})
        self.assertEqual(body["userName"], "alice@example.test")
        self.assertEqual(body["name"], {"formatted": "Alice"})
        self.assertEqual(
            user_body("alice", userName="override@example.test")["userName"],
            "override@example.test",
        )

    def test_seeded_default_role_is_minimal_and_restored_on_failure(self):
        baseline = {
            "id": "singleton",
            "directoryId": None,
            "defaultUserRoleIds": {},
            "defaultAdminRoleIds": {"original-admin": True},
        }
        auth = json.loads(json.dumps(baseline))
        role = {}
        reloads = []

        def jmap(method, arguments):
            if method == "x:Authentication/get":
                return {"list": [json.loads(json.dumps(auth))]}
            if method == "x:Authentication/set":
                auth.update(arguments["update"]["singleton"])
                return {"updated": {"singleton": None}}
            if method == "x:Role/set" and "create" in arguments:
                self.assertEqual(
                    arguments["create"]["fixture"]["enabledPermissions"],
                    {"authenticate": True},
                )
                role.update({"id": "temporary-user", **arguments["create"]["fixture"]})
                return {"created": {"fixture": {"id": "temporary-user"}}}
            if method == "x:Role/get":
                self.assertEqual(arguments["ids"], ["temporary-user"])
                return {"list": [dict(role)]}
            if method == "x:Role/set" and "destroy" in arguments:
                self.assertEqual(arguments["destroy"], ["temporary-user"])
                role.clear()
                return {"destroyed": ["temporary-user"]}
            if method == "x:Action/set":
                reloads.append(arguments["create"]["reload"]["@type"])
                return {"created": {"reload": {"id": "done"}}}
            raise AssertionError("Unexpected default-role fixture method: " + method)

        client = mock.Mock()
        client.jmap.side_effect = jmap
        with (
            self.assertRaisesRegex(RuntimeError, "live phase failed"),
            seeded_user_defaults(client),
        ):
            self.assertEqual(auth["defaultUserRoleIds"], {"temporary-user": True})
            self.assertEqual(
                auth["defaultAdminRoleIds"], baseline["defaultAdminRoleIds"]
            )
            raise RuntimeError("live phase failed")
        self.assertEqual(auth, baseline)
        self.assertFalse(role)
        self.assertEqual(reloads, ["ReloadSettings", "ReloadSettings"])

    def test_failed_jit_restores_complete_configuration(self):
        baseline_auth = {
            "id": "singleton",
            "directoryId": None,
            "defaultUserRoleIds": {"user-role": True},
            "defaultAdminRoleIds": {"admin-role": True},
        }
        baseline_domains = {
            "b": {"id": "b", "name": DOMAIN, "allowScimProvisioning": True},
            "c": {"id": "c", "name": "closed.test", "allowScimProvisioning": False},
        }
        auth = json.loads(json.dumps(baseline_auth))
        domains = json.loads(json.dumps(baseline_domains))
        calls = []

        def jmap(method, arguments):
            calls.append(method)
            if method == "x:Authentication/get":
                return {"list": [json.loads(json.dumps(auth))]}
            if method == "x:Domain/get":
                return {"list": json.loads(json.dumps(list(domains.values())))}
            if method == "x:Authentication/set":
                auth.update(arguments["update"]["singleton"])
                return {"updated": {"singleton": None}}
            if method == "x:Domain/set":
                for key, value in arguments["update"].items():
                    domains[key].update(value)
                return {"updated": {key: None for key in arguments["update"]}}
            if method == "x:Action/set":
                self.assertEqual(
                    arguments["create"]["reload"]["@type"], "ReloadSettings"
                )
                return {"created": {"reload": {"id": "done"}}}
            raise AssertionError("Unexpected fixture helper method: " + method)

        fake = mock.Mock()
        fake.jmap.side_effect = jmap
        with (
            self.assertRaisesRegex(RuntimeError, "simulated JIT setup failure"),
            restored_configuration(fake, ["b", "c"]),
        ):
            auth.update(
                {
                    "directoryId": "temporary",
                    "defaultUserRoleIds": {},
                    "defaultAdminRoleIds": {},
                }
            )
            domains["b"]["allowScimProvisioning"] = False
            raise RuntimeError("simulated JIT setup failure")
        self.assertEqual(auth, baseline_auth)
        self.assertEqual(domains, baseline_domains)
        self.assertIn("x:Action/set", calls)
        self.assertEqual(
            set(UI_PERMISSIONS),
            {
                "authenticate",
                "scimAccess",
                "sysDomainGet",
                "sysDomainQuery",
                "sysDomainUpdate",
                "sysAccountGet",
                "sysAccountQuery",
                "sysAccountUpdate",
                "sysApiKeyCreate",
                "sysApiKeyGet",
            },
        )

    def test_native_race_linearization_invariants(self):
        before = {"displayName": "old", "externalId": "old-id"}
        check_native_race(
            before,
            {"displayName": "new", "externalId": "native-id"},
            "native-id",
            "new",
            200,
        )
        check_native_race(
            before,
            {"displayName": "old", "externalId": "native-id"},
            "native-id",
            "new",
            412,
        )
        for after, status in (
            ({"displayName": "new", "externalId": "old-id"}, 200),
            ({"displayName": "old", "externalId": "native-id"}, 200),
            ({"displayName": "new", "externalId": "native-id"}, 412),
            ({"displayName": "old", "externalId": "native-id"}, 500),
        ):
            with self.assertRaises(AssertionError):
                check_native_race(before, after, "native-id", "new", status)


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "binary", nargs="?", help="Explicitly approved native Stalwart executable"
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Pure helper tests only; no namespace or server",
    )
    parser.add_argument(
        "--reference-schema",
        help="Public upstream schema.json.gz, for exact annotation-diff assertion",
    )
    parser.add_argument(
        "--admin-assets",
        help="Pinned extracted WebUI asset directory for extra HTTP byte checks",
    )
    parser.add_argument(
        "--ui-checks",
        action="store_true",
        help="Run optional sibling Playwright UI acceptance helper",
    )
    parser.add_argument(
        "--chromium", help="Explicit Chromium executable for optional UI checks"
    )
    parser.add_argument(
        "--screenshot",
        help="Optional successful UI screenshot in an existing /tmp directory",
    )
    parser.add_argument(
        "--namespace-child", action="store_true", help=argparse.SUPPRESS
    )
    parser.add_argument("--parent-netns", type=int, help=argparse.SUPPRESS)
    parser.add_argument("--parent-userns", type=int, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(
            unittest.defaultTestLoader.loadTestsFromTestCase(HelperTests)
        )
        return 0 if result.wasSuccessful() else 1
    if args.namespace_child:
        require(
            args.parent_netns is not None and args.parent_userns is not None,
            "Missing parent namespace identity",
        )
        child_run(args)
        return 0
    return launch(args)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, OSError, ValueError) as error:
        print(f"Fixture failed: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("Fixture interrupted; temporary server stopped", file=sys.stderr)
        sys.exit(130)
