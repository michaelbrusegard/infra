from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock


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

    def test_parse_wm_size_extracts_dimensions(self) -> None:
        self.assertEqual(
            android.parse_wm_size("Physical size: 1080x2400"),
            {"width": 1080, "height": 2400},
        )
        self.assertIsNone(android.parse_wm_size("garbage"))

    def test_live_view_uses_env_overrides(self) -> None:
        os.environ["ANDROID_EMULATOR_GRPC_URL"] = "http://127.0.0.1:8554"
        self.assertEqual(
            android.live_view("127.0.0.1:5555"),
            {
                "serial": "127.0.0.1:5555",
                "adb_endpoint": "127.0.0.1:5555",
                "grpc_url": "http://127.0.0.1:8554",
                "webrtc_url": "http://127.0.0.1:8554",
            },
        )

    @mock.patch.object(android, "run_adb")
    def test_ensure_device_connection_connects_missing_tcp_endpoints(self, run_adb: mock.Mock) -> None:
        run_adb.side_effect = [
            "List of devices attached\n",
            "connected to 127.0.0.1:5555\n",
        ]

        android.ensure_device_connection("127.0.0.1:5555")

        self.assertEqual(
            run_adb.call_args_list,
            [
                mock.call(None, "devices", "-l"),
                mock.call(None, "connect", "127.0.0.1:5555", check=False),
            ],
        )

    @mock.patch.object(android, "device_entry")
    @mock.patch.object(android, "shell_text")
    @mock.patch.object(android, "ensure_device_connection")
    def test_health_report_collects_focus_and_display(
        self,
        ensure_device_connection: mock.Mock,
        shell_text: mock.Mock,
        device_entry: mock.Mock,
    ) -> None:
        del ensure_device_connection
        device_entry.return_value = {"serial": "127.0.0.1:5555", "state": "device"}
        shell_text.side_effect = [
            "1",
            "stopped",
            "Physical size: 1080x2400",
            "Physical density: 420",
            "mCurrentFocus=Window{123 u0 com.android.chrome/com.google.android.apps.chrome.Main}",
        ]

        with mock.patch.dict(
            os.environ,
            {"ANDROID_EMULATOR_GRPC_URL": "http://127.0.0.1:8554"},
            clear=False,
        ):
            health = android.health_report("127.0.0.1:5555")

        self.assertTrue(health["boot_completed"])
        self.assertEqual(health["display"], {"width": 1080, "height": 2400})
        self.assertIn("mCurrentFocus", health["focus"])
        self.assertEqual(health["live_view"]["grpc_url"], "http://127.0.0.1:8554")


if __name__ == "__main__":
    unittest.main()
