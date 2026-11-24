#!/usr/bin/env python3
"""Native Stalwart backend side of the Postfix edge qualification.

qualify_postfix.py runs this in a single-UID user namespace that shares an
offline, loopback-only network with the Postfix container. Handshake: write
ROOT/ready.json, wait for ROOT/continue, then send mail through Postfix on
--postfix-port and ask the orchestrator for Postfix actions via
ROOT/request.json and ROOT/response.json.

Only behaviour the edge owns is checked. The backend's own spam filtering and
sender authentication are configured in gitops/espresso/tofu/stalwart and are
disabled here, since a copy of that configuration would not test production.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import smtplib
import socket
import subprocess
import sys
import time
import traceback
from email.parser import BytesParser
from email.policy import SMTP, SMTPUTF8
from email.policy import default as email_policy
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "stalwart-oss"))

from integration import Client, Redactor, Server, require  # noqa: E402
from mail import (  # noqa: E402
    certificate,
    configure_backend,
    create,
    fetch_message,
    known_message,
    mailbox,
    port,
    reload,
    start_mail,
    update,
)
from smtp_fixture import change, email_ids, objects  # noqa: E402

DELIVER = HERE / "deliver.sh"
DOMAIN = "manafishrov.com"
RELAY = "127.0.0.1"  # curl peer address; the only peer trusted to send PROXY
BACKEND_HOST = "localhost"  # deliver.sh backend name, matching the fixture certificate
CLIENT_IP = "192.0.2.10"
CLIENT_IP6 = "2001:db8::10"
HELO = "client.example.com"
SENDER = "sender@client.example.com"
SENDER_AUTH = (
    "spfEhloVerify",
    "spfFromVerify",
    "dkimVerify",
    "dmarcVerify",
    "arcVerify",
    "reverseIpVerify",
)


def listener(client, name, number, *, proxy):
    body = {
        "name": name,
        "protocol": "smtp",
        "bind": {f"{RELAY}:{number}": True},
        "useTls": True,
        "implicitTls": False,
    }
    if proxy:
        body["overrideProxyTrustedNetworks"] = {RELAY + "/32": True}
    return create(client, "NetworkListener", body)


def configure_edge_listeners(fixture, ports):
    """The two backend listeners deliver.sh uses: PROXY on edge, plain on local."""
    client = fixture["client"]
    # Exact recipient verification: an unknown plus address must not resolve
    # to its base mailbox. Explicit plus aliases remain supported.
    change(
        client, "Domain", fixture["domain_id"], {"subAddressing": {"@type": "Disabled"}}
    )
    listener(client, "smtp-edge", ports["edge"], proxy=True)
    listener(client, "smtp-edge-local", ports["local"], proxy=False)
    # The local path greets as "smtp-edge", which is not a FQDN.
    update(client, "MtaStageEhlo", {"rejectNonFqdn": {"else": "false", "match": {}}})
    # The fixture is offline; sender authentication would only time out on DNS.
    update(
        client,
        "SenderAuth",
        {key: {"else": "disable", "match": {}} for key in SENDER_AUTH},
    )
    update(
        client,
        "MtaStageData",
        {
            key: {"else": "true", "match": {}}
            for key in ("addReceivedHeader", "addReturnPathHeader")
        },
    )


def postfix_connection(fixture, number, client_ip=CLIENT_IP):
    class LoopbackSMTP(smtplib.SMTP):
        def _get_socket(self, host, port, timeout):
            # Keep the certificate name while selecting the source family.
            address = "::1" if ":" in client_ip else "127.0.0.1"
            return socket.create_connection(
                (address, port), timeout, self.source_address
            )

    smtp = LoopbackSMTP(
        "localhost",
        number,
        local_hostname=HELO,
        source_address=(client_ip, 0),
        timeout=45,
    )
    try:
        require(
            smtp.ehlo()[0] == 250
            and smtp.has_extn("smtputf8")
            and not smtp.has_extn("auth"),
            "Unexpected Postfix EHLO capabilities",
        )
        smtp.starttls(context=fixture["context"])
        require(
            smtp.ehlo()[0] == 250 and not smtp.has_extn("auth"),
            "Unexpected post-TLS capabilities",
        )
        return smtp
    except BaseException:
        smtp.close()
        raise


def message(tag, recipient=f"alice@{DOMAIN}"):
    body = known_message(tag)
    body.replace_header("To", recipient)
    return body.as_bytes(policy=SMTP)


def parse(raw):
    parsed = BytesParser(policy=email_policy).parsebytes(raw)
    return {
        "received": [str(v) for v in parsed.get_all("Received", [])],
        "returnPath": str(parsed.get("Return-Path", "")),
    }


def direct(fixture, ports, *, client_ip, sender, recipient, raw, ca=None):
    """Invoke deliver.sh as pipe(8) would, without Postfix."""
    time.sleep(0.3)  # Respect the native 5/second connection throttle.
    command = [
        "bash",
        str(DELIVER),
        BACKEND_HOST,
        str(ports["edge"]),
        str(ports["local"]),
        str(ca or fixture["certificate"]),
        client_ip,
        HELO,
        sender,
        recipient,
    ]
    result = subprocess.run(
        command,
        input=raw,
        capture_output=True,
        timeout=120,
        env={"PATH": os.environ["PATH"], "HOME": "/nonexistent", "LC_ALL": "C"},
        check=False,
    )
    return {
        "path": "direct-adapter",
        "exit": result.returncode,
        "stdout": result.stdout.decode(errors="replace").strip(),
        "stderr": result.stderr.decode(errors="replace").strip()[-500:],
    }


def run(root, report, binary, postfix_port):
    def save():
        (root / "report.json").write_text(json.dumps(report, indent=2) + "\n")

    def stage(name, function):
        print("START " + name, flush=True)

        def deadline(signum, frame):
            raise TimeoutError(f"{name} exceeded its 180-second deadline")

        previous = signal.signal(signal.SIGALRM, deadline)
        signal.alarm(180)
        started = time.monotonic()
        try:
            function()
        except Exception as error:
            report["tests"][name] = {"status": "FAIL", "error": str(error)}
            save()
            print(f"FAIL {name}: {error}", flush=True)
            raise
        finally:
            signal.alarm(0)
            signal.signal(signal.SIGALRM, previous)
        report["tests"][name] = {
            "status": "PASS",
            "seconds": round(time.monotonic() - started, 3),
        }
        save()
        print("PASS " + name, flush=True)

    directory = root / "backend"
    directory.mkdir()
    client = Client(port(), Redactor())
    server = Server(binary, directory, client)
    server.start()
    try:
        fixture = configure_backend(server, client, domain=DOMAIN)
        ports = {"edge": port(), "local": port()}
        configure_edge_listeners(fixture, ports)
        alice_id = fixture["users"]["alice"]["id"]
        change(
            client,
            "Account",
            alice_id,
            {
                "aliases": {
                    "0": {
                        "name": "alias-alice",
                        "domainId": fixture["domain_id"],
                        "enable": True,
                    },
                    "1": {
                        "name": "álïce",
                        "domainId": fixture["domain_id"],
                        "enable": True,
                    },
                    "2": {
                        "name": "alice+explicit",
                        "domainId": fixture["domain_id"],
                        "enable": True,
                    },
                }
            },
        )
        reload(client)
        # Listeners are bound at startup.
        start_mail(server)
        wrong_ca = certificate(root)[0]
        alice = fixture["users"]["alice"]["email"]
        report["messages"] = {}

        ready = {
            "backendHost": RELAY,
            "lmtpPort": fixture["ports"]["lmtp"],
            "smtpPort": ports["edge"],
            "localSmtpPort": ports["local"],
            "caFile": str(fixture["certificate"]),
            "certFile": str(fixture["certificate"]),
            "keyFile": str(fixture["private_key"]),
        }
        (root / "ready.json").write_text(json.dumps(ready))
        deadline = time.monotonic() + 180
        while not (root / "continue").exists():
            require(
                time.monotonic() < deadline, "Postfix readiness handshake timed out"
            )
            time.sleep(0.25)

        control_id = 0

        def control(action):
            nonlocal control_id
            control_id += 1
            request = root / "request.json"
            request.with_suffix(".tmp").write_text(
                json.dumps({"id": control_id, "action": action})
            )
            request.with_suffix(".tmp").replace(request)
            deadline = time.monotonic() + 60
            while time.monotonic() < deadline:
                response = root / "response.json"
                if response.exists():
                    result = json.loads(response.read_text())
                    if result["id"] == control_id:
                        return result
                time.sleep(0.2)
            raise TimeoutError("Postfix control timed out: " + action)

        def send(tag, *, client_ip=CLIENT_IP, sender=SENDER, recipient=alice, raw=None):
            raw = raw or message(tag, recipient)
            time.sleep(0.3)  # Respect the native 5/second connection throttle.
            with postfix_connection(fixture, postfix_port, client_ip) as smtp:
                refused = smtp.sendmail(
                    sender, [recipient], raw, mail_options=["SMTPUTF8", "BODY=8BITMIME"]
                )
                require(not refused, "Postfix refused the recipient")

        def record(tag, delivered, **extra):
            (root / (tag + ".eml")).write_bytes(delivered)
            result = {"delivered": True, **parse(delivered), **extra}
            report["messages"][tag] = result
            save()
            return result

        def recipient_probe(address):
            time.sleep(0.3)
            with postfix_connection(fixture, postfix_port) as smtp:
                require(smtp.mail(SENDER)[0] == 250, "Probe MAIL failed")
                return smtp.rcpt(address)[0]

        def require_original_client(result, client_ip):
            # The backend prepends its own Received header above Postfix's.
            backend, edge = result["received"][:2]
            require(
                "mail.fixture.test" in backend
                and client_ip in backend
                and HELO in backend
                and f"[{RELAY}]" not in backend,
                f"Backend did not see the original client: {backend}",
            )
            require(
                "by edge.fixture.test (Postfix)" in edge,
                f"Message did not pass through Postfix: {edge}",
            )

        def proxy_ipv4():
            send("proxy-ipv4")
            require_original_client(
                record("proxy-ipv4", fetch_message(fixture, "proxy-ipv4")), CLIENT_IP
            )

        stage("proxyPreservesClientIpv4AndEhlo", proxy_ipv4)

        def proxy_ipv6():
            send("proxy-ipv6", client_ip=CLIENT_IP6)
            require_original_client(
                record("proxy-ipv6", fetch_message(fixture, "proxy-ipv6")), CLIENT_IP6
            )

        stage("proxyPreservesClientIpv6AndEhlo", proxy_ipv6)

        def null_sender():
            # An Internet bounce has an empty sender but must keep the PROXY path.
            send("proxy-null-sender", sender="")
            result = record(
                "proxy-null-sender", fetch_message(fixture, "proxy-null-sender")
            )
            require_original_client(result, CLIENT_IP)
            require(result["returnPath"] == "<>", result)

        stage("internetNullSenderKeepsProxyPath", null_sender)

        def proxy_required():
            probe = subprocess.run(
                [
                    "curl",
                    "-sS",
                    "--max-time",
                    "5",
                    f"smtp://{BACKEND_HOST}:{ports['edge']}/x",
                    "--mail-rcpt",
                    alice,
                    "-T",
                    "/dev/null",
                ],
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )
            require(
                probe.returncode != 0,
                "PROXY listener accepted a connection without a PROXY header",
            )

        stage("proxyListenerRefusesConnectionsWithoutProxyHeader", proxy_required)

        def recipients():
            for address in (
                alice,
                f"alias-alice@{DOMAIN}",
                f"alice+explicit@{DOMAIN}",
                f"team@{DOMAIN}",
            ):
                require(
                    recipient_probe(address) == 250,
                    "Known recipient refused: " + address,
                )
            for address in (
                f"not-a-mailbox@{DOMAIN}",
                f"alice+not-configured@{DOMAIN}",
                f"alice@sub.{DOMAIN}",
                "relay@outside.test",
            ):
                require(
                    500 <= recipient_probe(address) < 600,
                    "Invalid recipient accepted: " + address,
                )

        stage("exactRecipientsNoPlusCatchallSubdomainOrRelay", recipients)

        def utf8():
            tag, recipient = "smtputf8-dot-transparency", f"álïce@{DOMAIN}"
            body = known_message(tag)
            body.replace_header("From", "séndér@client.example.com")
            body.replace_header("To", recipient)
            body.replace_header("Subject", "Grüße æøå " + tag)
            text = "Grüße æøå ☕\n.leading\n..double\n"
            body.get_payload()[0].set_content(text, cte="8bit")
            send(
                tag,
                sender="séndér@client.example.com",
                recipient=recipient,
                raw=body.as_bytes(policy=SMTPUTF8),
            )
            # fetch_message expects the ASCII known body, so look this one up here.
            delivered = None
            deadline = time.monotonic() + 30
            while delivered is None and time.monotonic() < deadline:
                with mailbox(fixture) as imap:
                    require(imap.select("INBOX")[0] == "OK", "Cannot select INBOX")
                    status, rows = imap.search(None, "ALL")
                    require(status == "OK", "IMAP search failed")
                    for ident in rows[0].split():
                        status, rows = imap.fetch(ident, "(RFC822)")
                        require(status == "OK", "IMAP fetch failed")
                        candidate = next(
                            row[1] for row in rows if isinstance(row, tuple)
                        )
                        if (
                            BytesParser(policy=email_policy).parsebytes(candidate)[
                                "Message-ID"
                            ]
                            == f"<{tag}@fixture.test>"
                        ):
                            require(delivered is None, "Duplicate SMTPUTF8 delivery")
                            delivered = candidate
                if delivered is None:
                    time.sleep(0.2)
            require(delivered is not None, "SMTPUTF8 message did not reach INBOX")
            parsed = BytesParser(policy=email_policy).parsebytes(delivered)
            require(
                str(parsed["Subject"]) == str(body["Subject"]), "UTF-8 header changed"
            )
            require(
                parsed.get_payload()[0].get_payload(decode=True)
                == text.replace("\n", "\r\n").encode(),
                "UTF-8 body or SMTP dot transparency changed",
            )
            record(tag, delivered)

        stage("smtpUtf8EnvelopeHeadersBodyAndDotTransparency", utf8)

        def local_generated():
            tag = "local-generated"
            result = direct(
                fixture,
                ports,
                client_ip="",
                sender=f"postmaster@{DOMAIN}",
                recipient=alice,
                raw=message(tag),
            )
            require(result["exit"] == 0, f"Local delivery failed: {result}")
            record(tag, fetch_message(fixture, tag), path="direct-adapter")
            log = (server.root / "server.log").read_text()
            require(
                'listenerId = "smtp-edge-local"' in log,
                "Local mail did not use the local listener",
            )

        stage("localGeneratedMailUsesPort26WithoutProxy", local_generated)

        def wrong_backend_ca():
            result = direct(
                fixture,
                ports,
                client_ip=CLIENT_IP,
                sender=SENDER,
                recipient=alice,
                raw=message("wrong-ca"),
                ca=wrong_ca,
            )
            require(
                result["exit"] == 75 and result["stdout"].startswith("4.3.0 "), result
            )
            # deliver.sh runs curl --silent; show the failure is the certificate.
            probe = subprocess.run(
                [
                    "curl",
                    "--disable",
                    "-sS",
                    "--max-time",
                    "5",
                    "--proxy",
                    "",
                    "--ssl-reqd",
                    "--cacert",
                    str(wrong_ca),
                    "--haproxy-protocol",
                    "--haproxy-clientip",
                    CLIENT_IP,
                    f"smtp://{BACKEND_HOST}:{ports['edge']}/{HELO}",
                ],
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            require(
                probe.returncode == 60,
                f"Expected a TLS certificate failure, got curl exit {probe.returncode}",
            )
            require(
                len(objects(client, "QueuedMessage")) == 0,
                "Wrong-CA delivery reached the backend",
            )
            report["messages"]["wrong-ca"] = result

        stage("wrongBackendCaDefers430", wrong_backend_ca)

        def local_dsn():
            alias = "retired-after-acceptance"
            current = client.jmap("x:Account/get", {"ids": [alice_id]})["list"][0][
                "aliases"
            ]
            change(
                client,
                "Account",
                alice_id,
                {
                    "aliases": {
                        **current,
                        "99": {
                            "name": alias,
                            "domainId": fixture["domain_id"],
                            "enable": True,
                        },
                    }
                },
            )
            reload(client)
            tag = "revoked-after-postfix-rcpt"
            time.sleep(0.3)
            with postfix_connection(fixture, postfix_port) as smtp:
                require(smtp.mail(alice)[0] == 250, "DSN fixture MAIL failed")
                require(
                    smtp.rcpt(f"{alias}@{DOMAIN}")[0] == 250,
                    "Cannot verify the disposable alias",
                )
                change(client, "Account", alice_id, {"aliases": current})
                reload(client)
                require(
                    smtp.data(message(tag, f"{alias}@{DOMAIN}"))[0] == 250,
                    "Postfix did not accept DATA",
                )
            # A Postfix-generated DSN has no client address, so deliver.sh can
            # only reach the backend through the local listener.
            delivered = None
            deadline = time.monotonic() + 45
            while delivered is None and time.monotonic() < deadline:
                with mailbox(fixture) as imap:
                    require(imap.select("INBOX")[0] == "OK", "Cannot select INBOX")
                    status, rows = imap.search(None, "ALL")
                    require(status == "OK", "IMAP search failed")
                    for ident in rows[0].split():
                        status, rows = imap.fetch(ident, "(RFC822)")
                        require(status == "OK", "IMAP fetch failed")
                        raw = next(row[1] for row in rows if isinstance(row, tuple))
                        parsed = BytesParser(policy=email_policy).parsebytes(raw)
                        if (
                            parsed.get_content_type() == "multipart/report"
                            and tag.encode() in raw
                        ):
                            require(delivered is None, "Duplicate local DSN")
                            delivered = raw
                if delivered is None:
                    time.sleep(0.2)
            require(
                delivered is not None, "Postfix-generated DSN did not reach the backend"
            )
            record("postfix-generated-dsn", delivered, path="postfix-generated")
            # Accelerate refresh only, not positive expiration: an observed
            # authoritative negative must not revoke the unexpired positive.
            control("refresh-cache")
            require(
                recipient_probe(f"{alias}@{DOMAIN}") == 250,
                "Finite positive-cache behavior changed",
            )
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                log = (server.root / "server.log").read_text()
                if any(
                    "smtp.mailbox-does-not-exist" in line
                    and 'listenerId = "fixture-lmtp"' in line
                    and f'to = "{alias}@{DOMAIN}"' in line
                    for line in log.splitlines()
                ):
                    break
                time.sleep(0.2)
            else:
                raise AssertionError("No authoritative negative refresh observed")
            require(
                recipient_probe(f"{alias}@{DOMAIN}") == 250,
                "Negative refresh revoked unexpired positive",
            )
            control("normal-cache")

        stage("postfixGeneratedDsnUsesLocalPathAfterRecipientRevocation", local_dsn)

        def queue_survives_restarts():
            server.stop()
            tag = "queued-across-restarts"
            send(tag)
            require(
                len(control("queue")["after"]) == 1,
                "Accepted message is not in the Postfix queue",
            )
            restarted = control("restart")
            require(
                len(restarted["after"]) == 1
                and [r["queue_id"] for r in restarted["before"]]
                == [r["queue_id"] for r in restarted["after"]],
                "Queued message changed across the Postfix restart",
            )
            start_mail(server)
            control("flush")
            require_original_client(record(tag, fetch_message(fixture, tag)), CLIENT_IP)

        stage("queueSurvivesPostfixAndBackendRestarts", queue_survives_restarts)

        def unseen_and_expired():
            control("short-cache")
            bob = fixture["users"]["bob"]["email"]
            require(recipient_probe(bob) == 250, "Cannot create a short-lived positive")
            server.stop()
            # Start a failed refresh while the old positive is still unexpired.
            control("refresh-cache")
            time.sleep(2)
            require(
                recipient_probe(alice) == 250,
                "Cannot initiate refresh of an unexpired positive",
            )
            control("short-cache")
            # The failed refresh keeps its probe timestamp, so Postfix's
            # 1000-second pending-probe grace covers the shortened expiry.
            require(
                recipient_probe(alice) == 250, "Pending-probe grace behaviour changed"
            )
            require(
                recipient_probe(f"unseen-during-outage@{DOMAIN}") == 451,
                "Unseen recipient did not defer during the outage",
            )
            time.sleep(6)
            require(
                recipient_probe(bob) == 451,
                "Expired positive did not defer during the outage",
            )
            start_mail(server)
            control("normal-cache")
            require(
                recipient_probe(alice) == 250,
                "Recipient did not recover after the outage",
            )

        stage("unseenAndExpiredRecipientsDeferDuringOutage", unseen_and_expired)

        def no_loss_after_acceptance():
            queue = client.jmap(
                "x:QueuedMessage/query", {"limit": 1, "calculateTotal": True}
            )
            require(
                queue["ids"] == [] and queue.get("total") == 0,
                "Backend queue is not empty",
            )
            log = (server.root / "server.log").read_text()
            # dsn-success is logged for ordinary successful deliveries too.
            require(
                not any(
                    "delivery.dsn-" in line and "dsn-success" not in line
                    for line in log.splitlines()
                ),
                "Backend generated a failure DSN",
            )
            delivered = sum(
                1 for m in report["messages"].values() if m.get("delivered")
            )
            require(
                log.count("(queue.message-queued)") == delivered,
                "Unexpected additional queued message",
            )
            require(
                len(email_ids(client, alice_id)) == delivered,
                "Delivery, discard or duplicate mismatch",
            )

        stage("noRejectDiscardOrDsnAfterAcceptance", no_loss_after_acceptance)
        report["passed"] = True
    finally:
        server.stop()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--binary", type=Path, required=True, help="Native Stalwart binary"
    )
    parser.add_argument(
        "--root",
        type=Path,
        required=True,
        help="Empty fixture directory shared with the orchestrator",
    )
    parser.add_argument("--postfix-port", type=int, required=True)
    args = parser.parse_args()
    report = {"passed": False, "tests": {}}

    def interrupted(signum, frame):
        raise KeyboardInterrupt("Fixture interrupted")

    signal.signal(signal.SIGTERM, interrupted)
    try:
        run(args.root, report, args.binary.resolve(), args.postfix_port)
    except (Exception, KeyboardInterrupt) as error:
        report["error"] = str(error)
        traceback.print_exc()
    finally:
        (args.root / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
