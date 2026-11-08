"""Pin only CLIProxyAPI's plugin installer after the plugin image passes CI."""

import re
import sys
from pathlib import Path


image = sys.argv[1]
if not re.fullmatch(r"ghcr\.io/michaelbrusegard/cliproxy-plugins:sha-[0-9a-f]{40}@sha256:[0-9a-f]{64}", image):
    raise SystemExit("Expected an immutable plugin image reference")
path = Path("gitops/espresso/apps/cliproxy/statefulset.yaml")
text, count = re.subn(
    r"(?m)^(        - name: install-plugins\n(?:          #[^\n]*\n)*          image: )(?:busybox|ghcr\.io/michaelbrusegard/cliproxy-plugins):[^\n]+$",
    lambda match: match[1] + image,
    path.read_text(),
)
if count != 1:
    raise SystemExit("Expected exactly one plugin installer image")
path.write_text(text)
