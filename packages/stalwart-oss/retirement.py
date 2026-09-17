"""Isolated legacy-mail cleanup rehearsal; never accepts a live endpoint."""

import imaplib
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from contextlib import ExitStack

from integration import Client, Redactor, Server, check_namespace, namespace_id, require
from mail import (
    configure_backend,
    known_message,
    mailbox,
    port,
    smtp_connection,
    smtp_send,
    start_mail,
)


def mail_call(client, method, arguments):
    response = client.expect(
        "POST",
        "/jmap",
        200,
        {
            "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
            "methodCalls": [[method, arguments, "retirement"]],
        },
        auth="recovery",
    )
    result = response.document()["methodResponses"][0]
    require(result[0] == method, f"{method} failed: {result[0]}")
    return result[1]


def ids(client, account_id):
    return mail_call(client, "Email/query", {"accountId": account_id})["ids"]


def wait_count(client, account_id, count):
    for _ in range(100):
        if len(ids(client, account_id)) == count:
            return
        time.sleep(0.2)
    raise AssertionError("Unexpected account-scoped email count")


def run(binary):
    with (
        tempfile.TemporaryDirectory(prefix="stalwart-retirement-") as directory,
        ExitStack() as clients,
    ):
        client = Client(port(), Redactor())
        # Explicit legacy source fixture; no change to the binary or licensing.
        server = Server(binary, Path(directory), client, expected_edition=None)
        try:
            server.start()
            fixture = configure_backend(server, client, native_scim=False)
            alice = fixture["users"]["alice"]
            bob = fixture["users"]["bob"]
            shared = fixture["shared"]
            client.jmap(
                "x:Account/set",
                {
                    "update": {
                        shared["id"]: {
                            "aliases": {
                                "0": {
                                    "name": "postmaster",
                                    "domainId": fixture["domain_id"],
                                    "enabled": True,
                                },
                            }
                        }
                    }
                },
            )
            for address, tag in (
                (alice["email"], "old-user-copy"),
                (shared["address"], "old-shared-copy"),
                (bob["email"], "unrelated-mail"),
            ):
                smtp_send(fixture, address, known_message(tag))
            for account_id in (alice["id"], shared["id"], bob["id"]):
                wait_count(client, account_id, 1)
            control_ids = ids(client, bob["id"])
            old_connection = clients.enter_context(mailbox(fixture))
            client.jmap(
                "x:Account/set",
                {
                    "update": {
                        alice["id"]: {
                            "credentials": {},
                            "permissions": {
                                "@type": "Merge",
                                "disabledPermissions": {"authenticate": True},
                            },
                        }
                    }
                },
            )
            account = client.jmap(
                "x:Account/get",
                {"ids": [alice["id"]], "properties": ["credentials"]},
            )["list"][0]
            require(not account["credentials"], "Legacy credentials remain")
            try:
                with mailbox(fixture):
                    pass
            except (imaplib.IMAP4.error, imaplib.IMAP4.abort):
                pass
            else:
                raise AssertionError("Old password login still works")
            smtp_send(fixture, alice["email"], known_message("receive-after-disable"))
            wait_count(client, alice["id"], 2)
            for account_id in (alice["id"], shared["id"]):
                selected = ids(client, account_id)
                result = mail_call(
                    client, "Email/set", {"accountId": account_id, "destroy": selected}
                )
                require(not result.get("notDestroyed"), "Email destruction failed")
                require(set(result["destroyed"]) == set(selected), "Partial deletion")
                wait_count(client, account_id, 0)
            start_mail(server)
            try:
                old_connection.noop()
            except imaplib.IMAP4.error:
                pass
            else:
                raise AssertionError("Old IMAP session survived process restart")
            for account_id in (alice["id"], shared["id"]):
                wait_count(client, account_id, 0)
            require(ids(client, bob["id"]) == control_ids, "Unrelated mail changed")
            with mailbox(fixture, "bob") as connection:
                require(connection.select("INBOX")[0] == "OK", "Unrelated login failed")
            try:
                with mailbox(fixture):
                    pass
            except imaplib.IMAP4.error:
                pass
            else:
                raise AssertionError("Old password login returned after restart")
            with smtp_connection(fixture) as smtp:
                require(smtp.ehlo()[0] == 250, "EHLO rejected")
                for address in (
                    alice["email"],
                    shared["address"],
                    "alias-alice@" + fixture["domain"],
                    "alice+retired@" + fixture["domain"],
                    "postmaster@" + fixture["domain"],
                ):
                    require(smtp.mail("")[0] == 250, "MAIL rejected")
                    require(smtp.rcpt(address)[0] == 250, "Recipient principal damaged")
                    smtp.rset()
                for address in ("unknown@" + fixture["domain"], "relay@outside.test"):
                    require(smtp.mail("")[0] == 250, "MAIL rejected")
                    require(smtp.rcpt(address)[0] == 550, "Unsafe recipient accepted")
                    smtp.rset()
            return {
                "legacyPasswordLoginDenied": "pass",
                "receivePermissionPreserved": "pass",
                "userAndSharedEmailDeletion": "pass",
                "unrelatedAccountUntouched": "pass",
                "recipientPrincipalsRetained": "pass",
                "existingSessionRevocationAfterRestart": "pass",
                "unrelatedLoginPreserved": "pass",
                "taggedAndPostmasterRecipients": "pass",
                "unknownAndRelayRecipientsRejected": "pass",
            }
        except Exception:
            print(server.diagnostics(), flush=True)
            raise
        finally:
            server.stop()


def main():
    if len(sys.argv) == 2:
        return subprocess.call(
            [
                "unshare",
                "-Urn",
                sys.executable,
                __file__,
                str(Path(sys.argv[1]).resolve()),
                str(namespace_id("net")),
                str(namespace_id("user")),
            ]
        )
    require(len(sys.argv) == 4, "Usage: retirement.py /approved/legacy/binary")
    check_namespace(int(sys.argv[2]), int(sys.argv[3]))
    print(json.dumps(run(Path(sys.argv[1])), indent=2), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
