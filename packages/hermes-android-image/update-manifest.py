#!/usr/bin/env python3
"""Pin a validated Android image and release the initial StatefulSet hold."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


PENDING_ANNOTATION = 'hermes.michaelbrusegard.com/android-image-rollout: "pending"'
READY_ANNOTATION = 'hermes.michaelbrusegard.com/android-image-rollout: "ready"'
IMAGE_PATTERNS = (
    r"(?m)^(\s*- name: prepare-android\n\s*image:)\s*.*$",
    r"(?m)^(\s*- name: android-emulator\n\s*image:)\s*.*$",
)


def update_content(content: str, image: str) -> str:
    if not re.fullmatch(r"ghcr\.io/[^\s]+@sha256:[0-9a-f]{64}", image):
        raise ValueError("Android image must be an immutable GHCR digest reference")

    for pattern in IMAGE_PATTERNS:
        content, replacements = re.subn(
            pattern,
            lambda match: f"{match.group(1)} {image}",
            content,
        )
        if replacements != 1:
            raise ValueError(f"expected exactly one Android image for {pattern}")

    if PENDING_ANNOTATION in content:
        content = content.replace(PENDING_ANNOTATION, READY_ANNOTATION, 1)
        content, replacements = re.subn(
            r"(?m)^(  updateStrategy:\n    type:) OnDelete\n    rollingUpdate: null$",
            r"\1 RollingUpdate",
            content,
        )
        if replacements != 1:
            raise ValueError("pending rollout is missing its OnDelete update strategy")
    elif READY_ANNOTATION not in content:
        raise ValueError("manifest is missing the Android rollout state annotation")
    elif "  updateStrategy:\n    type: RollingUpdate\n" not in content:
        raise ValueError("ready rollout is missing its RollingUpdate strategy")

    return content


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--image", required=True)
    args = parser.parse_args()

    original = args.manifest.read_text(encoding="utf-8")
    updated = update_content(original, args.image)
    args.manifest.write_text(updated, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
