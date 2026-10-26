import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).with_name("update-manifest.py").resolve()
MANIFEST = Path("gitops/espresso/apps/netbird/agent-network.yaml")


class PromotionTests(unittest.TestCase):
    def test_promotes_only_proxy_and_supports_repeat_updates(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / MANIFEST
            target.parent.mkdir(parents=True)
            original = (ROOT / MANIFEST).read_text()
            target.write_text(original)
            previous = original
            for digit in ("a", "b"):
                image = f"ghcr.io/michaelbrusegard/netbird-proxy:sha-{digit * 40}@sha256:{digit * 64}"
                subprocess.run([sys.executable, str(SCRIPT), image], cwd=directory, check=True)
                result = target.read_text()
                changed = [(old, new) for old, new in zip(previous.splitlines(), result.splitlines()) if old != new]
                self.assertEqual(len(changed), 1)
                self.assertEqual(changed[0][1], "          image: " + image)
                self.assertEqual(len(previous.splitlines()), len(result.splitlines()))
                previous = result

    def test_mutable_or_unrelated_reference_is_rejected(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "other/image:latest"],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("immutable", result.stderr)
