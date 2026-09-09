"""Real Pocket ID v2.12.0 disposable identity acceptance; no dependency downloads."""

from __future__ import annotations

import argparse
import base64
import hashlib
import http.cookiejar
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.parse

from integration import (
    Acceptance,
    Client,
    Server,
    Redactor,
    NoRedirect,
    ROOT,
    check_namespace,
    namespace_id,
    isolated_environment,
    seeded_user_defaults,
    patch,
    require,
)

POCKET_SHA256 = "0f27f55f6597986f9998ba0594c9eb4ef73fab01521d2795edf2ebce06c8448e"


def port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class Pocket(Client):
    def __init__(self, number, redactor):
        super().__init__(number, redactor)
        # WebAuthn requires a domain RP ID, not a numeric IP address.
        self.origin = f"http://localhost:{number}"
        self.cookies = http.cookiejar.CookieJar()
        self.http = urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            NoRedirect(),
            urllib.request.HTTPCookieProcessor(self.cookies),
        )

    def api(self, method, path, body=None, status=200):
        response = self.expect(
            method,
            path,
            status,
            body,
            auth=None,
            headers={"Cookie": "; ".join(c.name + "=" + c.value for c in self.cookies)},
        )
        for cookie in self.cookies:
            self.redactor.add(cookie.value)
        return response.document() if response.raw else None


def run(server, client, *, pocket_binary, chromium):
    """Caller must already have verified a fresh loopback-only namespace."""
    require([name for _, name in socket.if_nameindex()] == ["lo"], "Not isolated")
    require(
        hashlib.sha256(Path(pocket_binary).read_bytes()).hexdigest() == POCKET_SHA256,
        "Pocket ID release checksum mismatch",
    )
    root = server.root / "pocket"
    root.mkdir(mode=0o700)
    pocket = Pocket(port(), client.redactor)
    env = isolated_environment()
    env.update(
        HOME=str(root),
        TMPDIR=str(root),
        APP_URL=pocket.origin,
        HOST="127.0.0.1",
        PORT=str(urllib.parse.urlsplit(pocket.origin).port),
        ACTORS_HOST="127.0.0.1",
        ACTORS_PORT=str(port()),
        ENCRYPTION_KEY=client.redactor.add(secrets.token_hex(32)),
        DB_CONNECTION_STRING="file:" + str(root / "pocket.db"),
        UPLOAD_PATH=str(root / "uploads"),
        KEYS_PATH=str(root / "keys"),
        ANALYTICS_DISABLED="true",
    )
    result = {"pocketId": "2.12.0", "checks": {}}
    with (root / "log").open("wb") as log:
        process = subprocess.Popen(
            [str(pocket_binary)],
            cwd=root,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=log,
        )
        try:
            for _ in range(150):
                require(
                    process.poll() is None,
                    "Pocket exited: "
                    + client.redactor((root / "log").read_text()[-5000:]),
                )
                try:
                    discovery = pocket.api("GET", "/.well-known/openid-configuration")
                    break
                except OSError:
                    time.sleep(0.2)
            else:
                raise AssertionError("Pocket readiness timeout")
            require(discovery["issuer"] == pocket.origin, "Wrong issuer")
            jwks = pocket.api("GET", urllib.parse.urlsplit(discovery["jwks_uri"]).path)
            require(bool(jwks["keys"]), "No real issuer signing keys")
            result["checks"]["discoveryJwks"] = "PASS"
            admin = pocket.api(
                "POST",
                "/api/signup/setup",
                {
                    "username": "admin@example.test",
                    "email": "admin@example.test",
                    "firstName": "Identity",
                    "lastName": "Fixture",
                },
            )
            result["checks"]["realSetup"] = "PASS"
            oidc = pocket.api(
                "POST",
                "/api/oidc/clients",
                {
                    "id": "stalwart-fixture",
                    "name": "Isolated fixture",
                    "callbackURLs": [
                        pocket.origin + "/callback",
                        client.origin + "/account/oauth/callback",
                    ],
                    "isPublic": True,
                    "pkceEnabled": True,
                    "skipConsent": True,
                },
                status=201,
            )
            acceptance = Acceptance(client, server, argparse.Namespace())
            acceptance.bootstrap()
            client.jmap(
                "x:Account/set",
                {
                    "update": {
                        acceptance.service_id: {"domainId": acceptance.closed_domain_id}
                    }
                },
            )
            # Adopt existing mailbox identities before allowing Pocket ID to sync.
            adopted_user = acceptance.create_native_user("admin", acceptance.domain_id)
            group = pocket.api(
                "POST",
                "/api/user-groups",
                {
                    "name": "support",
                    "friendlyName": "Support",
                },
                status=201,
            )
            pocket.api(
                "PUT",
                "/api/user-groups/" + group["id"] + "/users",
                {"userIds": [admin["id"]]},
            )
            client.jmap(
                "x:Account/set",
                {
                    "update": {
                        adopted_user: {"externalId": admin["id"]},
                    }
                },
            )
            adopted_group = client.jmap(
                "x:Account/set",
                {
                    "create": {
                        "support": {
                            "@type": "Group",
                            "name": "support",
                            "domainId": acceptance.domain_id,
                            "externalId": group["id"],
                        }
                    }
                },
            )["created"]["support"]["id"]
            postmaster = client.jmap(
                "x:MailingList/set",
                {
                    "create": {
                        "postmaster": {
                            "name": "postmaster",
                            "domainId": acceptance.domain_id,
                            "recipients": {"support@example.test": True},
                        }
                    }
                },
            )["created"]["postmaster"]["id"]
            provider = pocket.api(
                "POST",
                "/api/scim/service-provider",
                {
                    "endpoint": client.origin + ROOT,
                    "token": client.token,
                    "oidcClientId": oidc["id"],
                },
                status=201,
            )
            syncpath = "/api/scim/service-provider/" + provider["id"] + "/sync"
            pocket.api("POST", syncpath)
            users = client.expect("GET", ROOT + "/Users", 200).document()["Resources"]
            require(
                any(
                    u["userName"] == "admin@example.test"
                    and u.get("externalId") == admin["id"]
                    for u in users
                ),
                "Real SCIM full-email sync missing",
            )
            result["checks"]["fullEmailScim"] = "PASS"
            target = pocket.api(
                "POST",
                "/api/users",
                {
                    "username": "offboard@example.test",
                    "email": "offboard@example.test",
                    "firstName": "Offboard",
                },
                status=201,
            )
            pocket.api("POST", syncpath)
            synced = client.expect("GET", ROOT + "/Users", 200).document()["Resources"]
            target_id = next(
                u["id"] for u in synced if u.get("externalId") == target["id"]
            )
            pocket.api("DELETE", "/api/users/" + target["id"], status=204)
            pocket.api("POST", syncpath)
            client.expect("GET", ROOT + "/Users/" + target_id, 404)
            result["checks"]["realDeleteOffboarding"] = "PASS"
            adopted = client.expect(
                "GET", ROOT + "/Users/" + adopted_user, 200
            ).document()
            require(adopted.get("externalId") == admin["id"], "Existing user replaced")
            shared = client.expect(
                "GET", ROOT + "/Groups/" + adopted_group, 200
            ).document()
            require(
                {m["value"] for m in shared.get("members", [])} == {adopted_user},
                "Shared mailbox membership not adopted",
            )
            require(
                acceptance.native(adopted_group)["emailAddress"]
                == "support@example.test",
                "Existing shared mailbox address changed",
            )
            require(
                acceptance.native(acceptance.service_id)["domainId"]
                == acceptance.closed_domain_id,
                "Unmanaged bootstrap identity changed",
            )
            require(
                client.jmap(
                    "x:MailingList/get", {"ids": [postmaster], "properties": ["id"]}
                )["list"],
                "Postmaster list removed by SCIM",
            )
            result["checks"]["existingMailboxIdsAndSystemIsolation"] = "PASS"
            result["checks"]["browserPkce"] = browser_login(
                pocket,
                oidc,
                discovery,
                chromium,
                client,
                adopted_user,
                adopted_group,
                lambda tokens, ui_check: stalwart_oidc_login(
                    client,
                    server,
                    pocket,
                    oidc,
                    tokens,
                    adopted_user,
                    adopted_group,
                    ui_check,
                ),
            )
            print(json.dumps(result), flush=True)
            return result
        except Exception:
            print(client.redactor((root / "log").read_text()[-8000:]), file=sys.stderr)
            raise
        finally:
            process.terminate()
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def stalwart_oidc_login(
    client, server, pocket, oidc, tokens, user_id, group_id, ui_check
):
    """Exercise the real native OIDC directory with a real issuer access JWT."""
    token = tokens["access_token"]
    require(token.count(".") == 2, "Pocket ID did not issue a JWT access token")
    original_directory = client.jmap("x:Authentication/get", {"ids": ["singleton"]})[
        "list"
    ][0].get("directoryId")
    application_ids = client.jmap("x:Application/query", {})["ids"]
    require(len(application_ids) == 1, "Expected one disposable WebUI application")
    application_id = application_ids[0]
    application = client.jmap("x:Application/get", {"ids": [application_id]})["list"][0]
    original_oauth_client_id = application.get("oauthClientId")
    directory = client.jmap(
        "x:Directory/set",
        {
            "create": {
                "pocket": {
                    "@type": "Oidc",
                    "description": "Disposable real Pocket ID authentication",
                    "issuerUrl": pocket.origin,
                    "claimUsername": "email",
                    "requireAudience": "wrong-fixture-audience",
                    "requireScopes": {},
                }
            }
        },
    )["created"]["pocket"]["id"]

    def reload():
        client.jmap("x:Action/set", {"create": {"reload": {"@type": "ReloadSettings"}}})

    try:
        client.jmap(
            "x:Application/set",
            {"update": {application_id: {"oauthClientId": oidc["id"]}}},
        )
        client.jmap(
            "x:Authentication/set",
            {"update": {"singleton": {"directoryId": directory}}},
        )
        # Application oauthClientId is part of an in-memory route bundle and is
        # not refreshed by ReloadSettings.
        server.restart()
        for _ in range(60):
            discovery = client.expect(
                "GET", "/api/discover/admin@example.test", 200, auth=None
            ).document()
            if discovery.get("token_endpoint", "").startswith(pocket.origin + "/"):
                break
            time.sleep(0.2)
        else:
            raise AssertionError("Native discovery did not select Pocket ID")
        client.expect("GET", "/api/account", 401, auth="Bearer " + token)
        client.jmap(
            "x:Directory/set",
            {"update": {directory: {"requireAudience": oidc["id"]}}},
        )
        reload()
        for _ in range(40):
            response = client.request("GET", "/api/account", auth="Bearer " + token)
            if response.status == 200:
                break
            time.sleep(0.25)
        else:
            raise AssertionError("Real Pocket ID access token did not authenticate")
        session = client.expect(
            "GET", "/jmap/session", 200, auth="Bearer " + token
        ).document()
        require(session["accounts"][user_id]["isPersonal"], "OIDC replaced the mailbox")
        require(group_id in session["accounts"], "OIDC lost shared-mailbox membership")
        header, payload, signature = token.split(".")
        invalid = client.redactor.add(
            ".".join(
                (header, payload, ("A" if signature[0] != "A" else "B") + signature[1:])
            )
        )
        client.expect("GET", "/api/account", 401, auth="Bearer " + invalid)
        for active, status in ((False, 403), (True, 200)):
            client.expect(
                "PATCH",
                ROOT + "/Users/" + user_id,
                200,
                patch({"op": "replace", "path": "active", "value": active}),
            )
            client.expect("GET", "/api/account", status, auth="Bearer " + token)
        ui_check()
        return "PASS (native JWT signature/audience validation, adopted mailbox, shared access, suspension, WebUI callback)"
    finally:
        client.jmap(
            "x:Application/set",
            {"update": {application_id: {"oauthClientId": original_oauth_client_id}}},
        )
        client.jmap(
            "x:Authentication/set",
            {"update": {"singleton": {"directoryId": original_directory}}},
        )
        client.jmap("x:Directory/set", {"destroy": [directory]})
        server.restart()


def webui_login(page, context, pocket, client, user_id, group_id):
    context.clear_cookies()
    page.goto(client.origin + "/account/login")
    page.get_by_label("Enter your account name to continue").fill("admin@example.test")
    page.get_by_role("button", name="Continue", exact=True).click()
    page.wait_for_url(pocket.origin + "/**", timeout=20000)
    page.get_by_role("button", name="Sign in", exact=False).first.click(timeout=15000)
    page.wait_for_url(client.origin + "/**", timeout=20000)
    page.wait_for_function(
        """() => {
          const raw = sessionStorage.getItem('stalwart-auth');
          if (!raw) return false;
          const parsed = JSON.parse(raw);
          return Boolean(parsed?.state?.accessToken);
        }""",
        timeout=20000,
    )
    require("/login" not in page.url, "WebUI returned to login after OIDC callback")
    stored = json.loads(page.evaluate("sessionStorage.getItem('stalwart-auth')"))
    token = client.redactor.add(stored["state"]["accessToken"])
    client.expect("GET", "/api/account", 200, auth="Bearer " + token)
    session = client.expect(
        "GET", "/jmap/session", 200, auth="Bearer " + token
    ).document()
    require(session["accounts"][user_id]["isPersonal"], "WebUI lost personal mailbox")
    require(group_id in session["accounts"], "WebUI lost shared mailbox")


def browser_login(
    pocket, oidc, discovery, chromium, client, user_id, group_id, verify_stalwart
):
    from playwright.sync_api import sync_playwright

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            executable_path=str(chromium),
            headless=True,
            args=["--no-sandbox", "--disable-dev-shm-usage"],
        )
        try:
            context = browser.new_context()
            context.add_cookies(
                [
                    {
                        "name": c.name,
                        "value": c.value,
                        "url": pocket.origin,
                        "secure": True,
                        "httpOnly": True,
                    }
                    for c in pocket.cookies
                ]
            )
            page = context.new_page()
            cdp = context.new_cdp_session(page)
            cdp.send("WebAuthn.enable")
            cdp.send(
                "WebAuthn.addVirtualAuthenticator",
                {
                    "options": {
                        "protocol": "ctap2",
                        "transport": "internal",
                        "hasResidentKey": True,
                        "hasUserVerification": True,
                        "isUserVerified": True,
                        "automaticPresenceSimulation": True,
                    }
                },
            )
            page.goto(pocket.origin + "/settings/account")
            page.get_by_role("button", name="Add Passkey", exact=True).first.click(
                timeout=15000
            )
            page.wait_for_timeout(1500)
            require(
                pocket.api("GET", "/api/webauthn/credentials"), "No passkey registered"
            )
            context.clear_cookies()
            verifier = secrets.token_urlsafe(48)
            challenge = (
                base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest())
                .decode()
                .rstrip("=")
            )
            state = secrets.token_urlsafe(24)
            callback = pocket.origin + "/callback"
            authorization = (
                discovery["authorization_endpoint"]
                + "?"
                + urllib.parse.urlencode(
                    {
                        "client_id": oidc["id"],
                        "redirect_uri": callback,
                        "response_type": "code",
                        "scope": "openid email profile",
                        "state": state,
                        "code_challenge": challenge,
                        "code_challenge_method": "S256",
                    }
                )
            )
            page.goto(authorization)
            page.get_by_role("button", name="Sign in", exact=False).first.click(
                timeout=15000
            )
            page.wait_for_url(pocket.origin + "/callback?**", timeout=20000)
            values = urllib.parse.parse_qs(urllib.parse.urlsplit(page.url).query)
            require(values.get("state") == [state], "OAuth state mismatch")
            code = pocket.redactor.add(values["code"][0])
            response = pocket.request(
                "POST",
                urllib.parse.urlsplit(discovery["token_endpoint"]).path,
                auth=None,
                raw=urllib.parse.urlencode(
                    {
                        "grant_type": "authorization_code",
                        "client_id": oidc["id"],
                        "code": code,
                        "redirect_uri": callback,
                        "code_verifier": verifier,
                    }
                ).encode(),
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
            require(response.status == 200, "Real PKCE token exchange failed")
            tokens = response.document()
            for key in ("access_token", "id_token", "refresh_token"):
                pocket.redactor.add(tokens.get(key))
            require(
                tokens.get("id_token", "").count(".") == 2, "No signed issuer ID token"
            )
            return {
                "passkeyPkce": "PASS",
                "stalwartAccountLogin": verify_stalwart(
                    tokens,
                    lambda: webui_login(
                        page, context, pocket, client, user_id, group_id
                    ),
                ),
            }
        finally:
            browser.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--pocket-binary", type=Path, required=True)
    parser.add_argument("--chromium", type=Path, required=True)
    parser.add_argument("--parent-net", type=int)
    parser.add_argument("--parent-user", type=int)
    args = parser.parse_args()
    if args.parent_net is None:
        return subprocess.call(
            [
                shutil.which("unshare"),
                "-Urn",
                "--",
                sys.executable,
                str(Path(__file__).resolve()),
                str(args.binary.resolve()),
                "--pocket-binary",
                str(args.pocket_binary.resolve()),
                "--chromium",
                str(args.chromium.resolve()),
                "--parent-net",
                str(namespace_id("net")),
                "--parent-user",
                str(namespace_id("user")),
            ],
            env=isolated_environment(),
        )
    check_namespace(args.parent_net, args.parent_user)
    with tempfile.TemporaryDirectory(prefix="identity-real-") as directory:
        root = Path(directory)
        os.environ.update(
            HOME=directory,
            TMPDIR=directory,
            XDG_CACHE_HOME=str(root / "cache"),
            XDG_CONFIG_HOME=str(root / "config"),
        )
        client = Client(port(), Redactor())
        server = Server(args.binary, root, client)
        try:
            server.start()
            client.jmap(
                "x:SpamPyzor/set",
                {
                    "update": {
                        "singleton": {"enable": False, "host": "pyzor-fixture.invalid"}
                    }
                },
            )
            with seeded_user_defaults(client):
                run(
                    server,
                    client,
                    pocket_binary=args.pocket_binary,
                    chromium=args.chromium,
                )
        except Exception as error:
            print(client.redactor(str(error)), file=sys.stderr)
            return 1
        finally:
            server.stop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
