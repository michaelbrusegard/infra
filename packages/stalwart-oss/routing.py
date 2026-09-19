"""Rehearse domain forwarding without contacting production or external SMTP.

Both backends retain the same domain and mailbox names, as during rollback.
An optional second binary tests the actual legacy server's route semantics.
Fixture-only self-signed relay certificates are accepted; production TLS must
be verified separately with certificate validation enabled.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from integration import Client, Redactor, Server, check_namespace, namespace_id, require
from mail import (
    MAIL_PERMISSIONS,
    configure_backend,
    create,
    fetch_message,
    isolated,
    known_message,
    port,
    reload,
    smtp_connection,
    smtp_send,
    update,
)
from migration import inventory


def message_ids(fixture, user="alice"):
    account = fixture["users"][user]
    return {
        row["messageId"]
        for messages in inventory(
            fixture, account["email"], account["password"]
        ).values()
        for row in messages
    }


def run(destination_binary, source_binary):
    isolated()
    # Legacy SMTP refuses loopback next hops. This address exists only on lo
    # inside the verified network namespace; no external interface is added.
    relay_address = "10.200.0.2"
    subprocess.run(
        [shutil.which("ip"), "address", "add", f"{relay_address}/32", "dev", "lo"],
        check=True,
        timeout=10,
    )
    with tempfile.TemporaryDirectory(prefix="stalwart-routing-") as directory:
        root = Path(directory)
        (root / "source").mkdir()
        (root / "destination").mkdir()
        source_client = Client(port(), Redactor())
        destination_client = Client(port(), Redactor())
        source_server = Server(
            source_binary,
            root / "source",
            source_client,
            # An explicitly supplied legacy binary keeps its own metadata and
            # licensing behavior. The destination must always identify as OSS.
            expected_edition="oss" if source_binary == destination_binary else None,
        )
        destination_server = Server(
            destination_binary, root / "destination", destination_client
        )
        try:
            source_server.start()
            destination_server.start()
            source = configure_backend(
                source_server,
                source_client,
                native_scim=source_binary == destination_binary,
            )
            destination = configure_backend(
                destination_server, destination_client, lmtp_address=relay_address
            )
            personal_domain = create(
                source_client,
                "Domain",
                {
                    "name": "personal.test",
                    "certificateManagement": {"@type": "Manual"},
                    "dkimManagement": {"@type": "Manual"},
                    "dnsManagement": {"@type": "Manual"},
                },
            )
            password = source["users"]["alice"]["password"]
            create(
                source_client,
                "Account",
                {
                    "@type": "User",
                    "name": "personal",
                    "domainId": personal_domain,
                    "credentials": {"0": {"@type": "Password", "secret": password}},
                    "roles": {"@type": "User"},
                    "permissions": {
                        "@type": "Merge",
                        "enabledPermissions": dict.fromkeys(MAIL_PERMISSIONS, True),
                    },
                    "encryptionAtRest": {"@type": "Disabled"},
                },
            )
            source["users"]["personal"] = {
                "email": "personal@personal.test",
                "password": password,
            }
            for fixture in (source, destination):
                fixture["client"].jmap(
                    "x:Domain/set",
                    {
                        "update": {
                            fixture["domain_id"]: {
                                "subAddressing": {"@type": "Enabled"}
                            }
                        }
                    },
                )
                create(
                    fixture["client"],
                    "MailingList",
                    {
                        "name": "postmaster",
                        "domainId": fixture["domain_id"],
                        "recipients": {"alice@mail.test": True},
                    },
                )
            original = source_client.jmap(
                "x:MtaOutboundStrategy/get",
                {"ids": ["singleton"], "properties": ["route"]},
            )["list"][0]["route"]
            smtp_send(source, "alice@mail.test", known_message("before-switch"))
            fetch_message(source, "before-switch")
            require(not message_ids(destination), "Destination was not initially empty")

            create(
                source_client,
                "MtaRoute",
                {
                    "@type": "Relay",
                    "name": "migrated-domain",
                    "address": relay_address,
                    "port": destination["ports"]["lmtp"],
                    "protocol": "lmtp",
                    "implicitTls": True,
                    # Only in this loopback-only, self-signed test fixture.
                    "allowInvalidCerts": True,
                    "authSecret": {"@type": "None"},
                },
            )
            update(
                source_client,
                "MtaOutboundStrategy",
                {
                    "route": {
                        "match": {
                            "0": {
                                "if": "rcpt_domain == 'mail.test'",
                                "then": "'migrated-domain'",
                            },
                            "1": {
                                "if": "is_local_domain(rcpt_domain)",
                                "then": "'local'",
                            },
                        },
                        "else": original["else"],
                    }
                },
            )
            reload(source_client)
            for address, tag, user in (
                ("alice@mail.test", "inbound-forwarded", None),
                ("alice@mail.test", "personal-submission", "personal"),
                ("alias-alice@mail.test", "alias-forwarded", None),
                ("alice+tag@mail.test", "tag-forwarded", None),
                ("postmaster@mail.test", "postmaster-forwarded", None),
            ):
                smtp_send(source, address, known_message(tag), user=user)
                fetch_message(destination, tag)

            with smtp_connection(source) as smtp:
                require(
                    not smtp.sendmail(
                        "sender@outside.test",
                        ["alice@mail.test", "personal@personal.test"],
                        known_message("mixed-domains").as_bytes(),
                    ),
                    "Mixed-domain recipients refused",
                )
            fetch_message(destination, "mixed-domains")
            fetch_message(source, "mixed-domains", user="personal")
            require(
                message_ids(source) == {"<before-switch@fixture.test>"},
                "Migrated-domain mail still reached the source mailbox",
            )
            require(
                message_ids(source, "personal") == {"<mixed-domains@fixture.test>"},
                "Personal delivery changed",
            )
            require(
                len(message_ids(destination)) == 6,
                "Forwarded delivery lost or duplicated messages",
            )
            with smtp_connection(source) as smtp:
                smtp.ehlo()
                for address in ("unknown@mail.test", "recipient@outside.test"):
                    require(smtp.mail("sender@outside.test")[0] == 250, "MAIL rejected")
                    require(smtp.rcpt(address)[0] == 550, "Invalid recipient accepted")
                    smtp.rset()

            # Route rollback is not data rollback. Keep newly delivered mail
            # on the destination and require reverse reconciliation separately.
            update(source_client, "MtaOutboundStrategy", {"route": original})
            reload(source_client)
            smtp_send(source, "alice@mail.test", known_message("route-rollback"))
            fetch_message(source, "route-rollback")
            require(len(message_ids(destination)) == 6, "Rollback changed new mail")
            return {
                "domainOverrideBeforeLocalDelivery": "pass",
                "authenticatedPersonalSubmission": "pass",
                "aliasesAndMixedDomainDelivery": "pass",
                "noSplitDelivery": "pass",
                "unknownRecipientAndUnauthenticatedRelayRejected": "pass",
                "routeRollbackRetainsDestinationMail": "pass",
                "sourceBinary": str(source_binary),
                "destinationBinary": str(destination_binary),
                "productionCertificateValidation": "not tested by this fixture",
            }
        except Exception:
            print("SOURCE\n" + source_server.diagnostics(), flush=True)
            print("DESTINATION\n" + destination_server.diagnostics(), flush=True)
            raise
        finally:
            destination_server.stop()
            source_server.stop()


def main():
    if len(sys.argv) in (2, 3):
        destination = str(Path(sys.argv[1]).resolve())
        source = str(Path(sys.argv[2]).resolve()) if len(sys.argv) == 3 else destination
        return subprocess.call(
            [
                "unshare",
                "-Urn",
                sys.executable,
                __file__,
                destination,
                source,
                str(namespace_id("net")),
                str(namespace_id("user")),
            ]
        )
    require(
        len(sys.argv) == 5,
        "Usage: routing.py /approved/destination/binary [/approved/legacy/binary]",
    )
    check_namespace(int(sys.argv[3]), int(sys.argv[4]))
    print(json.dumps(run(Path(sys.argv[1]), Path(sys.argv[2])), indent=2), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
