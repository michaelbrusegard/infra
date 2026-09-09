"""Disposable native mail acceptance; run only inside integration's verified namespace.

Helpers deliberately retain ports, TLS files and credentials in the caller-owned
fixture so recovery tests can restart the same database without reconfiguration.
"""

from __future__ import annotations

import base64
import imaplib
import json
import os
import secrets
import smtplib
import socket
import ssl
import subprocess
import time
from contextlib import contextmanager
from email import policy
from email.message import EmailMessage
from email.parser import BytesParser
from pathlib import Path

from integration import (
    ROOT,
    Client,
    Redactor,
    Server,
    check_namespace,
    namespace_id,
    patch,
    require,
    seeded_user_defaults,
)

MAIL_PERMISSIONS = [
    "authenticate",
    "emailSend",
    "emailReceive",
    "imapAuthenticate",
    "imapList",
    "imapSelect",
    "imapSearch",
    "imapFetch",
    "imapCreate",
    "imapAppend",
    "imapStore",
    "imapCopy",
    "imapMove",
    "imapExpunge",
    "imapStatus",
]


def port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def isolated():
    # The launcher checks namespace ancestry; helpers additionally reject a host
    # network even when accidentally called outside that launcher.
    require(
        os.geteuid() == 0 and [n for _, n in socket.if_nameindex()] == ["lo"],
        "Mail fixture requires integration's verified unshare -Urn namespace",
    )
    require(
        Path("/proc/self/uid_map").read_text().split()[2:] == ["1"],
        "Mail fixture requires single-user root mapping",
    )


def update(client, kind, values):
    return client.jmap(f"x:{kind}/set", {"update": {"singleton": values}})


def create(client, kind, value):
    return client.jmap(f"x:{kind}/set", {"create": {"fixture": value}})["created"][
        "fixture"
    ]["id"]


def reload(client):
    client.jmap("x:Action/set", {"create": {"reload": {"@type": "ReloadSettings"}}})


def certificate(root):
    cert, key = root / "mail.crt", root / "mail.key"
    subprocess.run(
        [
            "openssl",
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-keyout",
            str(key),
            "-out",
            str(cert),
            "-days",
            "2",
            "-subj",
            "/CN=localhost",
            "-addext",
            "subjectAltName=IP:127.0.0.1,DNS:localhost",
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=30,
    )
    key.chmod(0o600)
    context = ssl.create_default_context(cafile=str(cert))
    return cert, key, context


def start_mail(server):
    """Start the same Server in normal mode; recovery mode disables mail listeners."""
    isolated()
    server.stop()
    server.log = (server.root / "server.log").open("ab")
    env = {
        "PATH": os.environ.get("PATH", ""),
        "HOME": str(server.root),
        "TMPDIR": str(server.root),
        "LANG": "C.UTF-8",
    }
    server.process = subprocess.Popen(
        [str(server.binary), "--config", str(server.config)],
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=server.log,
        stderr=server.log,
        start_new_session=True,
    )
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        require(server.process.poll() is None, "Normal-mode Stalwart exited")
        try:
            if (
                server.client.request("GET", "/api/account", auth="recovery").status
                == 200
            ):
                return
        except OSError:
            pass
        time.sleep(0.2)
    raise AssertionError("Normal-mode management listener not ready")


def management_account(server, client, domain_id):
    permissions = [
        "authenticate",
        "impersonate",
        "scimAccess",
        "actionReloadSettings",
    ]
    for kind, verbs in {
        "Account": ("Get", "Query", "Create", "Update", "Destroy"),
        "Domain": ("Get", "Query"),
        "MailingList": ("Get", "Query"),
        "Authentication": ("Get", "Update"),
        "Role": ("Get", "Destroy"),
        "Certificate": ("Get", "Update"),
        "DkimSignature": ("Get", "Create"),
        "Action": ("Create",),
        "ApiKey": ("Create",),
        "MtaRoute": ("Create",),
        "MtaOutboundStrategy": ("Update",),
    }.items():
        permissions.extend("sys" + kind + verb for verb in verbs)
    uid = create(
        client,
        "Account",
        {
            "@type": "User",
            "name": "mail-admin",
            "domainId": domain_id,
            "roles": {"@type": "Admin"},
            "encryptionAtRest": {"@type": "Disabled"},
            "credentials": {"0": {"@type": "Password", "secret": server.password}},
            "permissions": {
                "@type": "Merge",
                "enabledPermissions": dict.fromkeys(permissions, True),
            },
        },
    )
    email = client.jmap("x:Account/get", {"ids": [uid]})["list"][0]["emailAddress"]
    auth = client.redactor.add(
        "Basic " + base64.b64encode((email + ":" + server.password).encode()).decode()
    )
    return uid, auth, email


def configure_backend(server, client, domain="mail.test"):
    """Configure a fresh native Server; caller starts/stops it and owns its root.

    Return dict: server/client/domain, ports (smtp/lmtp/imap), context,
    certificate/private_key, users {alice,bob: {id,email,password}}.
    Listener configuration survives Server.restart() and offline DB restores.
    """
    isolated()
    update(client, "SpamPyzor", {"enable": False, "host": "pyzor-fixture.invalid"})
    create(
        client,
        "Tracer",
        {
            "@type": "Stdout",
            "level": "info",
            "ansi": False,
            "events": {"auth.success": True},
        },
    )
    cert, key, context = certificate(server.root)
    cert_id = create(
        client,
        "Certificate",
        {
            "certificate": {"@type": "File", "filePath": str(cert)},
            "privateKey": {"@type": "File", "filePath": str(key)},
        },
    )
    domain_id = create(
        client,
        "Domain",
        {
            "name": domain,
            "allowScimProvisioning": True,
            "certificateManagement": {"@type": "Manual"},
            "dkimManagement": {"@type": "Manual"},
            "dnsManagement": {"@type": "Manual"},
        },
    )
    update(
        client,
        "SystemSettings",
        {
            "defaultHostname": "mail.fixture.test",
            "defaultDomainId": domain_id,
            "defaultCertificateId": cert_id,
        },
    )
    ports = {name: port() for name in ("smtp", "lmtp", "imap")}
    for name, number in ports.items():
        create(
            client,
            "NetworkListener",
            {
                "name": "fixture-" + name,
                "protocol": name,
                "bind": {f"127.0.0.1:{number}": True},
                "useTls": True,
                "tlsImplicit": True,
            },
        )
    update(
        client,
        "MtaStageAuth",
        {
            "require": {"else": "false"},
            "saslMechanisms": {"else": "[plain, login]"},
            "waitOnFail": {"else": "1ms"},
        },
    )
    # Zero durations evaluate as unset and fall back to the 30-second tarpit.
    update(client, "MtaStageRcpt", {"waitOnFail": {"else": "1ms"}})
    update(client, "MtaStageData", {"enableSpamFilter": {"else": "false"}})
    users = {}
    for name in ("alice", "bob"):
        password = client.redactor.add(secrets.token_urlsafe(32))
        uid = create(
            client,
            "Account",
            {
                "@type": "User",
                "name": name,
                "domainId": domain_id,
                "credentials": {"0": {"@type": "Password", "secret": password}},
                "roles": {"@type": "User"},
                "permissions": {
                    "@type": "Merge",
                    "enabledPermissions": {
                        p: True for p in MAIL_PERMISSIONS if p != "authenticate"
                    },
                },
                "encryptionAtRest": {"@type": "Disabled"},
                "aliases": {
                    "0": {
                        "name": "alias-" + name,
                        "domainId": domain_id,
                        "enabled": True,
                    }
                },
            },
        )
        users[name] = {"id": uid, "email": f"{name}@{domain}", "password": password}
    shared_id = create(
        client,
        "Account",
        {
            "@type": "Group",
            "name": "shared",
            "domainId": domain_id,
            # A migration-only fixture entitlement. The migration acceptance
            # restores Inherit after copying and verifies master login closes.
            "permissions": {
                "@type": "Merge",
                "enabledPermissions": dict.fromkeys(MAIL_PERMISSIONS, True),
            },
        },
    )
    create(
        client,
        "MailingList",
        {
            "name": "team",
            "domainId": domain_id,
            "recipients": {u["email"]: True for u in users.values()},
        },
    )
    management_port = int(client.origin.rsplit(":", 1)[1])
    create(
        client,
        "NetworkListener",
        {
            "name": "fixture-http",
            "protocol": "http",
            "bind": {f"127.0.0.1:{management_port}": True},
            "useTls": False,
        },
    )
    admin_id, auth, admin_email = management_account(server, client, domain_id)
    reload(client)
    client.recovery = auth
    start_mail(server)
    return dict(
        admin_id=admin_id,
        admin_email=admin_email,
        admin_password=server.password,
        server=server,
        client=client,
        domain=domain,
        domain_id=domain_id,
        ports=ports,
        context=context,
        certificate=cert,
        private_key=key,
        users=users,
        shared={"id": shared_id, "address": f"shared@{domain}"},
    )


class TLSLMTP(smtplib.LMTP):
    def __init__(self, host, number, context):
        self.context = context
        super().__init__(host, number, local_hostname="localhost", timeout=15)

    def _get_socket(self, host, number, timeout):
        return self.context.wrap_socket(
            socket.create_connection((host, number), timeout), server_hostname=host
        )


def smtp_connection(fixture, protocol="smtp"):
    isolated()
    # Stay below the native default of five SMTP connections per second.
    time.sleep(0.25)
    if protocol == "lmtp":
        return TLSLMTP("127.0.0.1", fixture["ports"][protocol], fixture["context"])
    return smtplib.SMTP_SSL(
        "127.0.0.1",
        fixture["ports"][protocol],
        timeout=15,
        context=fixture["context"],
        local_hostname="localhost",
    )


def known_message(tag):
    message = EmailMessage(policy=policy.SMTP)
    message["From"] = "sender@outside.test"
    message["To"] = "alice@mail.test"
    message["Subject"] = "Disposable mail " + tag
    message["Message-ID"] = f"<{tag}@fixture.test>"
    message["Date"] = "Tue, 08 Sep 2026 12:00:00 +0000"
    message.set_content("Known body: " + tag + "\n")
    message.add_attachment(
        b"\x00\x01\xffattachment:" + tag.encode(),
        maintype="application",
        subtype="octet-stream",
        filename="fixture.bin",
    )
    return message


def smtp_send(fixture, recipient, message, protocol="smtp", user=None):
    with smtp_connection(fixture, protocol) as smtp:
        sender = "sender@outside.test"
        if user:
            account = fixture["users"][user]
            smtp.login(account["email"], account["password"])
            sender = account["email"]
        refused = smtp.sendmail(
            sender,
            [recipient],
            message.as_bytes() if hasattr(message, "as_bytes") else message,
        )
        require(not refused, f"Recipient refused: {refused}")


@contextmanager
def mailbox(fixture, user="alice"):
    isolated()
    account = fixture["users"][user]
    connection = imaplib.IMAP4_SSL(
        "127.0.0.1",
        fixture["ports"]["imap"],
        ssl_context=fixture["context"],
        timeout=15,
    )
    try:
        connection.login(account["email"], account["password"])
        yield connection
    finally:
        try:
            connection.logout()
        except (OSError, imaplib.IMAP4.error):
            pass


def fetch_message(fixture, tag, user="alice", folder="INBOX", timeout=25):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        with mailbox(fixture, user) as imap:
            require(imap.select(folder)[0] == "OK", "Cannot select mailbox")
            # Delivery smoke checks should not depend on asynchronous FTS indexing.
            status, rows = imap.search(None, "ALL")
            require(status == "OK", "IMAP search failed")
            matches = []
            for message_id in rows[0].split():
                status, data = imap.fetch(message_id, "(RFC822 FLAGS)")
                require(status == "OK", "IMAP fetch failed")
                raw = next(row[1] for row in data if isinstance(row, tuple))
                parsed = BytesParser(policy=policy.default).parsebytes(raw)
                if parsed["Message-ID"] != f"<{tag}@fixture.test>":
                    continue
                require(
                    next(parsed.iter_attachments()).get_payload(decode=True)
                    == b"\x00\x01\xffattachment:" + tag.encode(),
                    "Attachment corruption",
                )
                require(
                    parsed.get_body(preferencelist=("plain",)).get_content().strip()
                    == "Known body: " + tag,
                    "Body corruption",
                )
                matches.append(raw)
            require(len(matches) <= 1, "Duplicate message delivery")
            if matches:
                return matches[0]
        time.sleep(0.2)
    raise AssertionError(f"Message {tag} not delivered to {user}/{folder}")


def backend_tests(fixture):
    for protocol in ("smtp", "lmtp"):
        smtp_send(
            fixture,
            fixture["users"]["alice"]["email"],
            known_message(protocol),
            protocol,
        )
        fetch_message(fixture, protocol)
    with mailbox(fixture) as imap:
        require(imap.create("Rehearsal")[0] == "OK", "IMAP CREATE failed")
        require(
            imap.append(
                "Rehearsal",
                "(\\Seen \\Flagged)",
                None,
                known_message("folder").as_bytes(),
            )[0]
            == "OK",
            "IMAP APPEND failed",
        )
    fetch_message(fixture, "folder", folder="Rehearsal")
    for recipient, tag in [("alias-alice", "alias"), ("team", "team")]:
        smtp_send(fixture, f"{recipient}@{fixture['domain']}", known_message(tag))
        fetch_message(fixture, tag)
    fetch_message(fixture, "team", user="bob")
    for address in [f"nobody@{fixture['domain']}", "relay@outside.test"]:
        with smtp_connection(fixture) as smtp:
            smtp.ehlo()
            require(
                smtp.mail("sender@outside.test")[0] == 250,
                "MAIL rejected before RCPT test",
            )
            code, text = smtp.rcpt(address)
            require(
                500 <= code < 600,
                f"Unsafe recipient acceptance: {address}: {code} {text}",
            )
    return {
        "smtp_lmtp_delivery": "pass",
        "mime_attachments": "pass",
        "imap_folders": "pass",
        "aliases_mailing_list": "pass",
        "unknown_recipient": "pass",
        "unauthorized_relay": "pass",
    }


def suspension_test(fixture):
    client = fixture["client"]
    old_token = client.token
    client.token = client.redactor.add(
        client.jmap(
            "x:ApiKey/set",
            {
                "accountId": fixture["admin_id"],
                "create": {
                    "fixture": {
                        "description": "Disposable mail SCIM smoke",
                        "permissions": {"@type": "Inherit"},
                    }
                },
            },
        )["created"]["fixture"]["secret"]
    )
    path = ROOT + "/Users/" + fixture["users"]["alice"]["id"]
    try:
        client.expect(
            "PATCH",
            path,
            200,
            patch({"op": "replace", "path": "active", "value": False}),
        )
        require(
            client.expect("GET", path, 200).document()["active"] is False,
            "SCIM active=false not persisted",
        )
        try:
            with mailbox(fixture):
                pass
        except imaplib.IMAP4.error:
            pass
        else:
            raise AssertionError("Suspended user authenticated over IMAP")
        with smtp_connection(fixture) as smtp:
            account = fixture["users"]["alice"]
            try:
                smtp.login(account["email"], account["password"])
            except smtplib.SMTPAuthenticationError:
                pass
            else:
                raise AssertionError("Suspended user authenticated over SMTP")
        smtp_send(
            fixture, fixture["users"]["alice"]["email"], known_message("suspended")
        )
    finally:
        try:
            client.expect(
                "PATCH",
                path,
                200,
                patch({"op": "replace", "path": "active", "value": True}),
            )
        finally:
            client.token = old_token
    fetch_message(fixture, "suspended")
    fetch_message(fixture, "smtp")
    with smtp_connection(fixture) as smtp:
        account = fixture["users"]["alice"]
        require(
            smtp.login(account["email"], account["password"])[0] == 235,
            "Restored SMTP login failed",
        )
    return {"suspended_credentials_denied_incoming_preserved_restored": "pass"}


def run(server, client):
    isolated()
    update(client, "SpamPyzor", {"enable": False, "host": "pyzor-fixture.invalid"})
    with seeded_user_defaults(client):
        fixture = configure_backend(server, client)
        results = backend_tests(fixture)
        print(
            "PASS native SMTP/LMTP, IMAP MIME/folders, aliases/list, recipient/relay rejection",
            flush=True,
        )
        results.update(suspension_test(fixture))
        print(
            "PASS native SCIM suspension preserves incoming mail and restores authentication",
            flush=True,
        )
        return results


def main():
    import sys
    import tempfile

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
    require(len(sys.argv) == 4, "Usage: mail.py /approved/native/binary")
    check_namespace(int(sys.argv[2]), int(sys.argv[3]))
    with tempfile.TemporaryDirectory(prefix="stalwart-native-mail-") as directory:
        client = Client(port(), Redactor())
        server = Server(Path(sys.argv[1]), Path(directory), client)
        try:
            server.start()
            print(json.dumps(run(server, client), indent=2), flush=True)
        except Exception:
            print(server.diagnostics(), flush=True)
            raise
        finally:
            server.stop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
