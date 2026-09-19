"""Normal-mode OIDC limiter regression; disposable loopback-only namespace.

Recovery mode disables HTTP limits, so this must run a configured normal server.
Forwarded addresses are trusted ONLY in this isolated fixture to give each probe
an independent documentation-address bucket. No production IdP or mail is used.
"""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from integration import (
    Acceptance,
    Client,
    FakeIdP,
    Redactor,
    Server,
    check_namespace,
    namespace_id,
    require,
)
from mail import create, port, reload, start_mail, update


RATE_PERIOD_MS = 3_600_000


def run(server, client):
    # The store uses wall-clock-aligned buckets. Do not straddle a boundary
    # during the short burst assertions, even when CI starts near the hour.
    remaining = RATE_PERIOD_MS / 1000 - time.time() % (RATE_PERIOD_MS / 1000)
    if remaining < 30:
        time.sleep(remaining + 0.1)
    domain = create(
        client,
        "Domain",
        {
            "name": "limit.test",
            "allowScimProvisioning": True,
            "certificateManagement": {"@type": "Manual"},
            "dkimManagement": {"@type": "Manual"},
            "dnsManagement": {"@type": "Manual"},
        },
    )
    update(client, "SpamPyzor", {"enable": False, "host": "unused.invalid"})
    create(
        client,
        "NetworkListener",
        {
            "name": "fixture-http",
            "protocol": "http",
            "useTls": False,
            "bind": {"127.0.0.1:" + client.origin.rsplit(":", 1)[1]: True},
        },
    )
    helper = Acceptance(client, server, None)
    management = helper.create_native_user(
        "operator",
        domain,
        permissions={
            key: True
            for key in (
                "authenticate",
                "sysHttpGet",
                "sysHttpUpdate",
                "sysAccountGet",
                "sysAccountUpdate",
                "sysActionCreate",
                "actionReloadSettings",
                "sysAuthenticationGet",
                "sysAuthenticationUpdate",
                "sysOidcProviderUpdate",
            )
        },
    )
    key = helper.api_key(management)
    alice = helper.create_native_user(
        "alice", domain, permissions={"authenticate": True}
    )
    helper.create_native_user("bob", domain, permissions={"authenticate": True})
    update(
        client,
        "Http",
        {
            "useXForwarded": True,
            "rateLimitAnonymous": {"count": 2, "period": RATE_PERIOD_MS},
            "rateLimitAuthenticated": {"count": 100, "period": RATE_PERIOD_MS},
        },
    )
    with FakeIdP(client.redactor) as provider:
        directory = create(
            client,
            "Directory",
            {
                "@type": "Oidc",
                "issuerUrl": provider.origin,
                "description": "Disposable OIDC limiter fixture",
                "claimUsername": "email",
                "claimGroups": "groups",
                "requireScopes": {},
            },
        )
        admin_role = create(
            client,
            "Role",
            {
                "description": "Disposable session admin probe",
                "enabledPermissions": {"sysHttpGet": True},
            },
        )
        update(
            client,
            "Authentication",
            {
                "directoryId": directory,
                "defaultAdminRoleIds": {admin_role: True},
            },
        )
        client.recovery = client.redactor.add("Bearer " + key)
        start_mail(server, oidc_admin_group="admin")
        provider.wait_discovered(timeout=15)

        def request(token, ip, status=200):
            return client.expect(
                "GET",
                "/api/account",
                status,
                auth="Bearer " + token,
                headers={"X-Forwarded-For": ip},
            )

        token = provider.issue("alice@limit.test", "Alice", [])
        for _ in range(8):
            request(token, "192.0.2.10")
        require(
            provider.hit_count(token) == 8,
            "Known OIDC tokens must still revalidate with their issuer",
        )
        print("PASS repeated valid OIDC requests exceed anonymous budget", flush=True)

        # Authorization changes must remain visible on the SAME opaque token.
        def admin_query(allowed):
            result = client.expect(
                "POST",
                "/jmap",
                200,
                {
                    "using": ["urn:ietf:params:jmap:core", "urn:stalwart:jmap"],
                    "methodCalls": [["x:Http/get", {"ids": ["singleton"]}, "admin"]],
                },
                auth="Bearer " + token,
                headers={"X-Forwarded-For": "192.0.2.10"},
            )
            method, data, _ = result.document()["methodResponses"][0]
            require(
                (method == "x:Http/get")
                if allowed
                else (method == "error" and data.get("type") == "forbidden"),
                "Warm OIDC authorization did not track current groups",
            )

        admin_query(False)
        with provider.lock:
            provider.tokens[token]["groups"] = ["admin"]
        admin_query(True)
        with provider.lock:
            provider.tokens[token]["groups"] = []
        admin_query(False)
        print(
            "PASS current group grants and removals survive rate admission", flush=True
        )

        # Fresh credentials still consume the pre-authentication budget.
        for index in range(3):
            fresh = provider.issue("alice@limit.test", "Alice", [])
            request(fresh, "192.0.2.11", 200 if index < 2 else 429)
        # Exhausting a shared gateway's anonymous bucket must not block a
        # previously verified token (but still revalidate it).
        request(token, "192.0.2.11")
        print("PASS unknown-token budget enforced; known token unaffected", flush=True)

        client.jmap(
            "x:Account/set",
            {
                "update": {
                    alice: {
                        "permissions": {
                            "@type": "Replace",
                            "enabledPermissions": {},
                        }
                    }
                }
            },
        )
        request(token, "192.0.2.12", 403)
        client.jmap(
            "x:Account/set",
            {
                "update": {
                    alice: {
                        "permissions": {
                            "@type": "Replace",
                            "enabledPermissions": {"authenticate": True},
                        }
                    }
                }
            },
        )
        request(token, "192.0.2.13")
        with provider.lock:
            del provider.tokens[token]
        request(token, "192.0.2.14", 401)
        request(token, "192.0.2.14", 401)
        request(token, "192.0.2.14", 401)
        request(token, "192.0.2.14", 429)
        print("PASS suspension/revocation denied; failed admission evicted", flush=True)

        switch_token = provider.issue("alice@limit.test", "Alice", [])
        request(switch_token, "192.0.2.16")
        update(client, "Authentication", {"directoryId": None})
        reload(client)
        request(switch_token, "192.0.2.16", 401)
        update(client, "Authentication", {"directoryId": directory})
        reload(client)
        provider.wait_discovered(timeout=15)
        request(switch_token, "192.0.2.17")
        print(
            "PASS OIDC admission cannot become native auth after directory switch",
            flush=True,
        )

        update(
            client,
            "Http",
            {"rateLimitAuthenticated": {"count": 5, "period": RATE_PERIOD_MS}},
        )
        reload(client)
        bob = provider.issue("bob@limit.test", "Bob", [])
        for _ in range(5):
            request(bob, "192.0.2.15")
        request(bob, "192.0.2.15", 429)
        require(
            provider.hit_count(bob) == 5,
            "Exhausted account budget still contacted the IdP",
        )
        client.expect("GET", "/api/account", 200, auth="recovery")
        print("PASS authenticated account budget and native machine key", flush=True)

        # Rate admission itself expires; it must not become an immortal bypass.
        update(
            client,
            "Http",
            {"rateLimitAuthenticated": {"count": 100, "period": RATE_PERIOD_MS}},
        )
        update(client, "OidcProvider", {"accessTokenExpiry": 1000})
        reload(client)
        expires = provider.issue("alice@limit.test", "Alice", [])
        request(expires, "192.0.2.18")
        request(provider.issue("alice@limit.test", "Alice", []), "192.0.2.18")
        time.sleep(1.2)
        request(expires, "192.0.2.18", 429)
        print("PASS expired rate admission consumes anonymous budget again", flush=True)


def main():
    if len(sys.argv) == 2:
        return subprocess.call(
            [
                "unshare",
                "-Urn",
                sys.executable,
                __file__,
                sys.argv[1],
                str(namespace_id("net")),
                str(namespace_id("user")),
            ]
        )
    require(len(sys.argv) == 4, "Usage: rate_limit.py /approved/native/binary")
    check_namespace(int(sys.argv[2]), int(sys.argv[3]))
    with tempfile.TemporaryDirectory(prefix="stalwart-oidc-limit-") as directory:
        client = Client(port(), Redactor())
        server = Server(Path(sys.argv[1]), Path(directory), client)
        try:
            server.start()
            run(server, client)
            print(json.dumps({"normal_mode_oidc_limits": "pass"}))
        except Exception:
            print(server.diagnostics(), flush=True)
            raise
        finally:
            server.stop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
