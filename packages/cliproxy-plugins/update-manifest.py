"""Pin the plugin image's installers only after the image passes CI.

CLIProxyAPI's plugin installer and the LLM normalizer's installer in its
CronJob both copy from the same image.
"""

import re
import sys
from pathlib import Path


MANIFESTS = {
    Path("gitops/espresso/apps/cliproxy/statefulset.yaml"): "install-plugins",
    Path("gitops/espresso/apps/clickhouse/llm-normalizer.yaml"): "install-normalizer",
}

image = sys.argv[1]
if not re.fullmatch(r"ghcr\.io/michaelbrusegard/cliproxy-plugins:sha-[0-9a-f]{40}@sha256:[0-9a-f]{64}", image):
    raise SystemExit("Expected an immutable plugin image reference")
for path, container in MANIFESTS.items():
    text, count = re.subn(
        rf"(?m)^( +- name: {container}\n(?: +#[^\n]*\n)* +image: )(?:busybox|ghcr\.io/michaelbrusegard/cliproxy-plugins):[^\n]+$",
        lambda match: match[1] + image,
        path.read_text(),
    )
    if count != 1:
        raise SystemExit(f"Expected exactly one {container} image in {path}")
    path.write_text(text)
