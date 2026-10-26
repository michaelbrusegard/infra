"""Pin only the Agent Network proxy container after its image passes tests."""

import re
import sys
from pathlib import Path


image = sys.argv[1]
if not re.fullmatch(r"ghcr\.io/michaelbrusegard/netbird-proxy:sha-[0-9a-f]{40}@sha256:[0-9a-f]{64}", image):
    raise SystemExit("Expected an immutable NetBird proxy image reference")
path = Path("gitops/espresso/apps/netbird/agent-network.yaml")
text, count = re.subn(
    r"(?m)^(        - name: proxy\n(?:          #[^\n]*\n)*          image: )(?:docker\.io/netbirdio/reverse-proxy|ghcr\.io/michaelbrusegard/netbird-proxy):[^\n]+$",
    lambda match: match[1] + image,
    path.read_text(),
)
if count != 1:
    raise SystemExit("Expected exactly one Agent Network proxy image")
path.write_text(text)
