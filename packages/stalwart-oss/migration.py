"""Disposable two-backend mailbox-copy acceptance.

This proves the migration mechanism without production credentials or data. It
runs only in the same isolated network namespace used by the native mail tests.
"""

from __future__ import annotations

import imaplib
import json
import ssl
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from email import policy
from email.parser import BytesParser
from pathlib import Path

from integration import Client, Redactor, Server, check_namespace, namespace_id, require
from mail import configure_backend, isolated, known_message, mailbox, port, smtp_send


def append_fixture(fixture, folder, tag, flags="(\\Seen \\Flagged)"):
    with mailbox(fixture) as imap:
        parent = folder.split("/", 1)[0]
        if parent != folder:
            imap.create(parent)
        imap.create(folder)
        require(
            imap.append(
                folder,
                flags,
                '"08-Sep-2026 12:34:56 +0000"',
                known_message(tag).as_bytes(),
            )[0]
            == "OK",
            "Source IMAP APPEND failed",
        )


@contextmanager
def authenticated_mailbox(fixture, username, password):
    connection = imaplib.IMAP4_SSL(
        "localhost",
        fixture["ports"]["imap"],
        ssl_context=ssl.create_default_context(cafile=str(fixture["certificate"])),
        timeout=15,
    )
    try:
        connection.login(username, password)
        yield connection
    finally:
        try:
            connection.logout()
        except (OSError, imaplib.IMAP4.error):
            pass


def inventory(fixture, username=None, password=None):
    result = {}
    account = fixture["users"]["alice"]
    username = username or account["email"]
    password = password or account["password"]
    with authenticated_mailbox(fixture, username, password) as imap:
        status, rows = imap.list()
        require(status == "OK", "IMAP LIST failed")
        folders = []
        for row in rows:
            # Fixture folder names are printable ASCII. Production relies on
            # imapsync itself for modified UTF-7 handling.
            folders.append(row.rsplit(b' "/" ', 1)[-1].strip(b'"').decode())
        for folder in folders:
            require(
                imap.select(f'"{folder}"', readonly=True)[0] == "OK",
                "IMAP SELECT failed",
            )
            status, ids = imap.search(None, "ALL")
            require(status == "OK", "IMAP SEARCH failed")
            messages = []
            for message_id in ids[0].split():
                status, data = imap.fetch(message_id, "(RFC822 FLAGS INTERNALDATE)")
                require(status == "OK", "IMAP FETCH failed")
                metadata, raw = next(row for row in data if isinstance(row, tuple))
                parsed = BytesParser(policy=policy.default).parsebytes(raw)
                messages.append(
                    {
                        "messageId": parsed["Message-ID"],
                        "bytes": raw,
                        "seen": b"\\Seen" in metadata,
                        "flagged": b"\\Flagged" in metadata,
                        "internalDate": imaplib.Internaldate2tuple(metadata),
                    }
                )
            result[folder] = messages
    return result


def run_imapsync(
    executable,
    source,
    destination,
    *,
    source_user=None,
    source_password=None,
    destination_user=None,
    destination_password=None,
    scratch_name="personal",
):
    isolated()
    source_account = source["users"]["alice"]
    destination_account = destination["users"]["alice"]
    source_user = source_user or source_account["email"]
    source_password = source_password or source_account["password"]
    destination_user = destination_user or destination_account["email"]
    destination_password = destination_password or destination_account["password"]
    scratch = destination["server"].root / ("imapsync-" + scratch_name)
    scratch.mkdir(exist_ok=True)
    pass1 = scratch / "source-password"
    pass2 = scratch / "destination-password"
    pass1.write_text(source_password + "\n")
    pass2.write_text(destination_password + "\n")
    pass1.chmod(0o600)
    pass2.chmod(0o600)
    command = [
        str(executable),
        "--host1",
        "localhost",
        "--port1",
        str(source["ports"]["imap"]),
        "--user1",
        source_user,
        "--passfile1",
        str(pass1),
        "--ssl1",
        "--sslargs1",
        "SSL_verify_mode=1",
        "--sslargs1",
        "SSL_ca_file=" + str(source["certificate"]),
        "--host2",
        "localhost",
        "--port2",
        str(destination["ports"]["imap"]),
        "--user2",
        destination_user,
        "--passfile2",
        str(pass2),
        "--ssl2",
        "--sslargs2",
        "SSL_verify_mode=1",
        "--sslargs2",
        "SSL_ca_file=" + str(destination["certificate"]),
        "--automap",
        "--syncinternaldates",
        "--nofoldersizes",
        "--nofoldersizesatend",
        "--tmpdir",
        str(scratch),
        "--nolog",
    ]
    completed = subprocess.run(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=90,
    )
    require(completed.returncode == 0, "imapsync failed:\n" + completed.stdout[-4000:])


def verify_copy(source, destination, *, source_auth=None, destination_auth=None):
    expected = inventory(source, *(source_auth or (None, None)))
    actual = inventory(destination, *(destination_auth or (None, None)))
    require(set(actual) == set(expected), "Folder set changed during migration")
    for folder, messages in expected.items():
        copied = actual[folder]
        require(len(copied) == len(messages), "Message count changed in " + folder)
        by_id = {row["messageId"]: row for row in copied}
        require(len(by_id) == len(copied), "Destination contains duplicate Message-IDs")
        for message in messages:
            row = by_id.get(message["messageId"])
            require(row is not None, "Message missing after migration")
            require(row["bytes"] == message["bytes"], "RFC822 bytes changed")
            require(row["seen"] == message["seen"], "Seen flag changed")
            require(row["flagged"] == message["flagged"], "Flagged flag changed")
            require(
                row["internalDate"] == message["internalDate"],
                "Internal date changed",
            )
    return sum(map(len, actual.values()))


def shared_mailbox(fixture):
    return {
        "id": fixture["shared"]["id"],
        "address": fixture["shared"]["address"],
        "masterLogin": fixture["shared"]["address"] + "%" + fixture["admin_email"],
        "masterPassword": fixture["admin_password"],
    }


def run(binary, imapsync):
    isolated()
    with tempfile.TemporaryDirectory(prefix="stalwart-migration-") as directory:
        root = Path(directory)
        (root / "source").mkdir()
        (root / "destination").mkdir()
        source_client = Client(port(), Redactor())
        destination_client = Client(port(), Redactor())
        source_server = Server(binary, root / "source", source_client)
        destination_server = Server(binary, root / "destination", destination_client)
        try:
            source_server.start()
            destination_server.start()
            source = configure_backend(source_server, source_client)
            destination = configure_backend(destination_server, destination_client)

            append_fixture(source, "Projects/2026", "migration-first")
            run_imapsync(imapsync, source, destination)
            first_count = verify_copy(source, destination)
            run_imapsync(imapsync, source, destination)
            require(
                verify_copy(source, destination) == first_count,
                "Repeated sync duplicated mail",
            )
            append_fixture(source, "Archive", "migration-delta", flags="(\\Seen)")
            run_imapsync(imapsync, source, destination)
            require(
                verify_copy(source, destination) == first_count + 1,
                "Delta sync failed",
            )

            source_shared = shared_mailbox(source)
            destination_shared = shared_mailbox(destination)
            smtp_send(source, source_shared["address"], known_message("shared-copy"))
            source_auth = (
                source_shared["masterLogin"],
                source_shared["masterPassword"],
            )
            destination_auth = (
                destination_shared["masterLogin"],
                destination_shared["masterPassword"],
            )
            for _ in range(50):
                if sum(map(len, inventory(source, *source_auth).values())):
                    break
                time.sleep(0.2)
            else:
                raise AssertionError("Shared source mailbox did not receive mail")
            run_imapsync(
                imapsync,
                source,
                destination,
                source_user=source_shared["masterLogin"],
                source_password=source_shared["masterPassword"],
                destination_user=destination_shared["masterLogin"],
                destination_password=destination_shared["masterPassword"],
                scratch_name="shared",
            )
            require(
                verify_copy(
                    source,
                    destination,
                    source_auth=source_auth,
                    destination_auth=destination_auth,
                )
                == 1,
                "Shared mailbox copy failed",
            )
            for fixture, shared, auth in (
                (source, source_shared, source_auth),
                (destination, destination_shared, destination_auth),
            ):
                fixture["client"].jmap(
                    "x:Account/set",
                    {"update": {shared["id"]: {"permissions": {"@type": "Inherit"}}}},
                )
                try:
                    with authenticated_mailbox(fixture, *auth):
                        pass
                except (imaplib.IMAP4.error, imaplib.IMAP4.abort):
                    pass
                else:
                    raise AssertionError("Migration-only shared login remained enabled")
            return {
                "verifiedTls": "pass",
                "foldersFlagsInternalDatesRfc822": "pass",
                "repeatIsIdempotent": "pass",
                "deltaSync": "pass",
                "sharedMailboxViaScopedMasterLogin": "pass",
                "sharedPermissionsRestored": "pass",
            }
        except Exception:
            print("SOURCE\n" + source_server.diagnostics(), flush=True)
            print("DESTINATION\n" + destination_server.diagnostics(), flush=True)
            raise
        finally:
            destination_server.stop()
            source_server.stop()


def main():
    if len(sys.argv) == 3:
        return subprocess.call(
            [
                "unshare",
                "-Urn",
                sys.executable,
                __file__,
                sys.argv[1],
                sys.argv[2],
                str(namespace_id("net")),
                str(namespace_id("user")),
            ]
        )
    require(
        len(sys.argv) == 5,
        "Usage: migration.py /approved/native/binary /path/to/imapsync",
    )
    check_namespace(int(sys.argv[3]), int(sys.argv[4]))
    print(json.dumps(run(Path(sys.argv[1]), Path(sys.argv[2])), indent=2), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
