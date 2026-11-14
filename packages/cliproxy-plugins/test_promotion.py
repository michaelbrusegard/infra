import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).with_name("update-manifest.py").resolve()
MANIFESTS = [line.split('"')[1] for line in SCRIPT.read_text().splitlines() if line.startswith("    Path(")]


class PromotionTests(unittest.TestCase):
    def test_promotes_only_plugin_installers_and_supports_repeat_updates(self):
        self.assertEqual(len(MANIFESTS), 3)
        with tempfile.TemporaryDirectory() as directory:
            previous = {}
            for manifest in MANIFESTS:
                target = Path(directory) / manifest
                target.parent.mkdir(parents=True, exist_ok=True)
                previous[manifest] = (ROOT / manifest).read_text()
                target.write_text(previous[manifest])
            for digit in ("a", "b"):
                image = f"ghcr.io/michaelbrusegard/cliproxy-plugins:sha-{digit * 40}@sha256:{digit * 64}"
                subprocess.run([sys.executable, str(SCRIPT), image], cwd=directory, check=True)
                for manifest in MANIFESTS:
                    result = (Path(directory) / manifest).read_text()
                    changed = [(old, new) for old, new in zip(previous[manifest].splitlines(), result.splitlines())
                               if old != new]
                    self.assertEqual(len(changed), 1, manifest)
                    self.assertEqual(changed[0][1].strip(), "image: " + image)
                    self.assertEqual(len(previous[manifest].splitlines()), len(result.splitlines()))
                    previous[manifest] = result

    def test_mutable_or_unrelated_reference_is_rejected(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "other/image:latest"],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("immutable", result.stderr)
