#!/usr/bin/env python3
"""Apply independent SCIM patches to the pinned, OSS-stripped Stalwart source.

Patches are preflighted together without fuzz before any files are changed.
Only the native module and feature-specific schema are generated here; upstream
Rust changes live in patches/ so their context and feature guards are reviewable.
"""
# SPDX-License-Identifier: AGPL-3.0-only

import base64
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

PATCH_DIRECTORY = Path(__file__).with_name("patches") / "server"
SCIM_FIELDS = (
    ("x:Domain", "allowScimProvisioning"),
    ("x:UserAccount", "externalId"),
    ("x:GroupAccount", "externalId"),
)


def validate_source(root, native):
    destination = root / "crates/http/src/independent_scim"
    if (
        destination.exists()
        or "pub mod independent_scim;" in (root / "crates/http/src/lib.rs").read_text()
    ):
        raise RuntimeError("Native integration already applied")
    for path in root.rglob("*.rs"):
        if "SPDX-License-Identifier: LicenseRef-SEL" in path.read_text():
            raise RuntimeError(f"SEL source remains after ossify: {path}")
    for crate in ("scim", "scim-proto"):
        source = (root / f"crates/{crate}/src/lib.rs").read_text()
        if "LicenseRef-SEL" in source or "pub mod" in source:
            raise RuntimeError("Run upstream ossify.py before applying native SCIM")
    if not (native / "mod.rs").is_file():
        raise RuntimeError("Native SCIM implementation is missing")


def schema_archive(root):
    schema = json.loads(
        gzip.decompress((root / "resources/schema/schema.json.gz").read_bytes())
    )
    for kind, name in SCIM_FIELDS:
        field = schema["fields"][kind]["properties"][name]
        if field.get("enterprise") is not True:
            raise RuntimeError(f"Unexpected upstream schema: {kind}.{name}")
        field["enterprise"] = False
    return gzip.compress(json.dumps(schema, separators=(",", ":")).encode(), mtime=0)


def apply_patches(root):
    patches = sorted(PATCH_DIRECTORY.glob("*.patch"))
    if not patches:
        raise RuntimeError("Native integration patches are missing")
    content = "".join(path.read_text() for path in patches)
    command = [
        "patch",
        "--directory",
        str(root.resolve()),
        "--strip=1",
        "--fuzz=0",
        "--forward",
        "--batch",
        "--no-backup-if-mismatch",
    ]
    for flags in (["--dry-run"], []):
        result = subprocess.run(
            command + flags,
            input=content,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        if result.returncode:
            raise RuntimeError(f"Pinned-source integration mismatch:\n{result.stdout}")


def apply(root, native):
    validate_source(root, native)
    archive = schema_archive(root)
    apply_patches(root)
    shutil.copytree(native, root / "crates/http/src/independent_scim")
    schema = root / "resources/schema"
    (schema / "schema.independent-scim.json.gz").write_bytes(archive)
    fingerprint = base64.urlsafe_b64encode(hashlib.sha256(archive).digest())
    (schema / "schema.independent-scim.json.sha256").write_text(
        fingerprint.decode().rstrip("=")
    )


if __name__ == "__main__":
    apply(Path(sys.argv[1]), Path(sys.argv[2]))
