"""Disposable cold-RocksDB Restic backup and restore smoke test.

Run inside integration.py's verified namespace via run(server, client), or use
this file's standalone launcher. No Kubernetes/CSI/VolSync controller is run:
stopping the source before Restic models a stronger consistency boundary than
an unquiesced volume snapshot. No storage fault injection is performed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
from types import SimpleNamespace

from integration import (
    Acceptance,
    Client,
    Server,
    Redactor,
    ROOT,
    CORE,
    check_namespace,
    namespace_id,
    isolated_environment,
    seeded_user_defaults,
    require,
    user_body,
)


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def clone_server(source, root):
    root.mkdir(mode=0o700)
    client = Client(int(source.client.origin.rsplit(":", 1)[1]), source.client.redactor)
    server = Server(source.binary, root, client)
    client.token = source.client.token
    client.recovery = source.client.recovery
    return server, client


def inventory(path):
    return {
        str(file.relative_to(path)): hashlib.sha256(file.read_bytes()).hexdigest()
        for file in sorted(path.rglob("*"))
        if file.is_file()
    }


def restic_restore(server, restic, start):
    """Backup only after graceful stop, restore into an empty different data dir."""
    root = server.root / "recovery-restic"
    root.mkdir(mode=0o700)
    password = root / "password"
    password.write_text(server.client.redactor.add(secrets.token_urlsafe(40)))
    password.chmod(0o600)
    environment = isolated_environment()
    environment.update(
        {
            "HOME": str(root),
            "TMPDIR": str(root),
            "RESTIC_REPOSITORY": str(root / "repository"),
            "RESTIC_PASSWORD_FILE": str(password),
            "RESTIC_CACHE_DIR": str(root / "cache"),
        }
    )

    def execute(*args):
        process = subprocess.run(
            [restic, *args],
            env=environment,
            cwd=server.root,
            capture_output=True,
            timeout=180,
        )
        require(
            process.returncode == 0,
            server.client.redactor(
                f"Restic {args[0]} failed: {process.stderr.decode(errors='replace')}"
            ),
        )
        return process.stdout

    restored, client = clone_server(server, root / "restored")
    require(not (restored.root / "data").exists(), "Restore destination not empty")
    server.stop()
    try:
        before = inventory(server.root / "data")
        require(before, "Source RocksDB is empty")
        execute("init")
        execute("backup", "--json", "--tag", "stopped-disposable-rocksdb", "data")
        snapshots = json.loads(execute("snapshots", "--json"))
        require(len(snapshots) == 1, "Expected exactly one local backup snapshot")
        execute("check", "--read-data")
        execute("restore", snapshots[0]["id"], "--target", str(restored.root))
        require(
            inventory(restored.root / "data") == before,
            "Restored RocksDB bytes differ from stopped source",
        )
        start(restored)
    except BaseException:
        restored.stop()
        start(server)
        raise
    return (
        restored,
        client,
        {
            "snapshotCount": 1,
            "filesVerified": len(before),
            "consistency": "gracefully stopped RocksDB",
        },
    )


def native_snapshot(client):
    result = {}
    for kind in (
        "Account",
        "Domain",
        "Role",
        "Authentication",
        "DkimSignature",
        "Certificate",
    ):
        rows = client.jmap(f"x:{kind}/get", {})
        result[kind] = sorted(rows.get("list", []), key=lambda row: row["id"])
    return result


def run(server, client):
    require(
        [name for _, name in socket.if_nameindex()] == ["lo"] and os.geteuid() == 0,
        "Recovery requires integration verified isolated namespace",
    )
    restic = os.environ.get("STALWART_TEST_RESTIC") or shutil.which("restic")
    require(restic and Path(restic).is_file(), "Local Restic executable unavailable")
    results = {}
    client.jmap(
        "x:SpamPyzor/set",
        {"update": {"singleton": {"enable": False, "host": "pyzor-fixture.invalid"}}},
    )
    with seeded_user_defaults(client):
        acceptance = Acceptance(client, server, SimpleNamespace())
        if client.token is None:
            acceptance.bootstrap()
        active = client.expect(
            "POST", ROOT + "/Users", 201, user_body("recovery-active")
        ).document()
        inactive = client.expect(
            "POST", ROOT + "/Users", 201, user_body("recovery-inactive", active=False)
        ).document()
        active_key = acceptance.api_key(active["id"])
        inactive_key = acceptance.api_key(inactive["id"])
        client.expect("GET", "/api/account", 200, auth="Bearer " + active_key)
        client.expect("GET", "/api/account", 403, auth="Bearer " + inactive_key)
        group = client.expect(
            "POST",
            ROOT + "/Groups",
            201,
            {
                "schemas": [CORE + "Group"],
                "displayName": "recovery-group@example.test",
                "members": [{"value": active["id"]}, {"value": inactive["id"]}],
            },
        ).document()
        from mail import (
            configure_backend,
            fetch_message,
            known_message,
            mailbox,
            smtp_send,
            start_mail,
        )

        fixture = configure_backend(server, client, domain="recovery-mail.test")
        # Embed only disposable TLS/DKIM material in the backed-up registry so
        # restored listeners do not depend on files in the original instance.
        private_key = client.redactor.add(fixture["private_key"].read_text())
        certificates = client.jmap("x:Certificate/get", {})["list"]
        require(len(certificates) == 1, "Expected one disposable TLS certificate")
        client.jmap(
            "x:Certificate/set",
            {
                "update": {
                    certificates[0]["id"]: {
                        "certificate": {
                            "@type": "Text",
                            "value": fixture["certificate"].read_text(),
                        },
                        "privateKey": {"@type": "Text", "secret": private_key},
                    }
                }
            },
        )
        client.jmap(
            "x:DkimSignature/set",
            {
                "create": {
                    "fixture": {
                        "@type": "Dkim1RsaSha256",
                        "domainId": fixture["domain_id"],
                        "selector": "disposable-recovery",
                        "privateKey": {"@type": "Text", "secret": private_key},
                    }
                }
            },
        )
        client.jmap("x:Action/set", {"create": {"reload": {"@type": "ReloadSettings"}}})
        tag = "recovery-known"
        smtp_send(fixture, fixture["users"]["alice"]["email"], known_message(tag))
        inbox_bytes = fetch_message(fixture, tag)
        with mailbox(fixture) as imap:
            require(
                imap.create("RecoveryArchive")[0] == "OK",
                "Create recovery folder failed",
            )
            require(
                imap.append("RecoveryArchive", "(\\Seen \\Flagged)", None, inbox_bytes)[
                    0
                ]
                == "OK",
                "Append recovery folder failed",
            )
        archived_bytes = fetch_message(fixture, tag, folder="RecoveryArchive")
        before = native_snapshot(client)
        snapshots = {
            path: client.expect("GET", path, 200).document()
            for path in (
                ROOT + "/Users/" + active["id"],
                ROOT + "/Users/" + inactive["id"],
                ROOT + "/Groups/" + group["id"],
            )
        }
        restored, recovered, backup = restic_restore(server, restic, start_mail)
        try:
            require(
                native_snapshot(recovered) == before,
                "Native users/groups/roles/permissions/config not restored",
            )
            for path, expected in snapshots.items():
                actual = recovered.expect("GET", path, 200).document()
                # Location is the new instance origin, not persisted identity.
                actual.get("meta", {}).pop("location", None)
                expected.get("meta", {}).pop("location", None)
                require(actual == expected, "SCIM restored snapshot differs")
            recovered.expect("GET", "/api/account", 200, auth="Bearer " + active_key)
            recovered.expect("GET", "/api/account", 403, auth="Bearer " + inactive_key)
            restored_fixture = {**fixture, "server": restored, "client": recovered}
            require(
                fetch_message(restored_fixture, tag) == inbox_bytes,
                "Restored INBOX bytes changed",
            )
            require(
                fetch_message(restored_fixture, tag, folder="RecoveryArchive")
                == archived_bytes,
                "Restored folder bytes/attachment changed",
            )
            with mailbox(restored_fixture) as imap:
                require(
                    imap.select("RecoveryArchive")[0] == "OK", "Restored folder missing"
                )
                status, flags = imap.fetch("1", "(FLAGS)")
                require(
                    status == "OK"
                    and b"\\Seen" in b" ".join(flags)
                    and b"\\Flagged" in b" ".join(flags),
                    "Restored flags changed",
                )
            results["backupRestore"] = {
                **backup,
                "nativeAndScimSnapshots": "pass",
                "testTokensAndInactiveAuth": "pass",
                "knownMailAttachmentFolderFlags": "pass",
                "testTlsAndDkimRegistry": "pass",
            }
        finally:
            restored.stop()
            start_mail(server)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary")
    parser.add_argument("--restic", required=True)
    parser.add_argument("--scratch", required=True)
    parser.add_argument("--namespace-child", action="store_true")
    parser.add_argument("--parent-netns", type=int)
    parser.add_argument("--parent-userns", type=int)
    args = parser.parse_args()
    if not args.namespace_child:
        environment = isolated_environment()
        argv = [
            shutil.which("unshare"),
            "-Urn",
            "--",
            sys.executable,
            str(Path(__file__).resolve()),
            str(Path(args.binary).resolve(strict=True)),
            "--restic",
            str(Path(args.restic).resolve(strict=True)),
            "--scratch",
            str(Path(args.scratch).resolve(strict=True)),
            "--namespace-child",
            "--parent-netns",
            str(namespace_id("net")),
            "--parent-userns",
            str(namespace_id("user")),
        ]
        process = subprocess.Popen(argv, env=environment, start_new_session=True)
        try:
            return process.wait()
        finally:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    check_namespace(args.parent_netns, args.parent_userns)
    os.environ["STALWART_TEST_RESTIC"] = args.restic
    with tempfile.TemporaryDirectory(
        prefix="stalwart-recovery-", dir=args.scratch
    ) as directory:
        root = Path(directory)
        root.chmod(0o700)
        os.environ.update(
            {
                "HOME": directory,
                "TMPDIR": directory,
                "XDG_CACHE_HOME": directory + "/cache",
            }
        )
        redactor = Redactor()
        client = Client(free_port(), redactor)
        server = Server(Path(args.binary), root, client)
        try:
            server.start()
            print(json.dumps(run(server, client), indent=2), flush=True)
            return 0
        except Exception as error:
            print(
                redactor(f"FAIL recovery: {type(error).__name__}: {error}"), flush=True
            )
            print(server.diagnostics(), flush=True)
            return 1
        finally:
            server.stop()


if __name__ == "__main__":
    sys.exit(main())
