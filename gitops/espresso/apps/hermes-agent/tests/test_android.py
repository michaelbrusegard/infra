from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "android.py"
SPEC = importlib.util.spec_from_file_location("hermes_android", SCRIPT_PATH)
assert SPEC and SPEC.loader
android = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(android)


class AndroidScriptTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        root = Path(self.tempdir.name)
        self.hermes_home = root / "opt" / "data"
        self.workspace = self.hermes_home / "workspace"
        self.cache = self.hermes_home / "cache"
        self.browser_files = root / "opt" / "browser-files"
        self.workspace.mkdir(parents=True)
        self.cache.mkdir(parents=True)
        self.browser_files.mkdir(parents=True)
        self.previous = {
            "HERMES_HOME": os.environ.get("HERMES_HOME"),
            "BROWSER_FILES_ROOT": os.environ.get("BROWSER_FILES_ROOT"),
        }
        os.environ["HERMES_HOME"] = str(self.hermes_home)
        os.environ["BROWSER_FILES_ROOT"] = str(self.browser_files)

    def tearDown(self) -> None:
        for key, value in self.previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        self.tempdir.cleanup()

    def test_parse_devices_reads_states_and_metadata(self) -> None:
        devices = android.parse_devices(
            "List of devices attached\n"
            "emulator-5554 device product:sdk_gphone64 model:Pixel_8 transport_id:1\n"
            "192.168.1.4:5555 offline transport_id:2\n"
        )

        self.assertEqual(
            devices,
            [
                {
                    "serial": "emulator-5554",
                    "state": "device",
                    "product": "sdk_gphone64",
                    "model": "Pixel_8",
                    "transport_id": "1",
                },
                {
                    "serial": "192.168.1.4:5555",
                    "state": "offline",
                    "transport_id": "2",
                },
            ],
        )

    def test_encode_input_text_normalizes_whitespace(self) -> None:
        self.assertEqual(android.encode_input_text("  hello  android world "), "hello%sandroid%sworld")
        with self.assertRaises(ValueError):
            android.encode_input_text("   ")

    def test_resolve_local_source_rejects_outside_paths(self) -> None:
        allowed = self.workspace / "note.txt"
        allowed.write_text("hello", encoding="utf-8")
        self.assertEqual(android.resolve_local_source(str(allowed)), allowed.resolve())

        outside = Path(self.tempdir.name) / "outside.txt"
        outside.write_text("nope", encoding="utf-8")
        with self.assertRaises(ValueError):
            android.resolve_local_source(str(outside))

    def test_resolve_output_path_defaults_under_browser_files(self) -> None:
        destination = android.resolve_output_path(None, "192.168.1.4:5555", "screenshots", ".png")

        self.assertTrue(destination.is_relative_to(self.browser_files))
        self.assertEqual(destination.suffix, ".png")
        self.assertIn("192.168.1.4_5555", str(destination))

    def test_resolve_output_path_creates_allowed_parent(self) -> None:
        destination = self.workspace / "captures" / "screen.png"

        resolved = android.resolve_output_path(str(destination), "serial", "screenshots", ".png")

        self.assertEqual(resolved, destination.resolve())
        self.assertTrue(destination.parent.is_dir())


if __name__ == "__main__":
    unittest.main()
