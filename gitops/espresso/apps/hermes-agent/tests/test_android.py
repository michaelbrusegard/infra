from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "android.py"
APP_ROOT = Path(__file__).resolve().parents[1]
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
            "ANDROID_EMULATOR_GRPC_URL": os.environ.get("ANDROID_EMULATOR_GRPC_URL"),
            "ANDROID_VIEW_URL": os.environ.get("ANDROID_VIEW_URL"),
            "AURORA_STORE_APK": os.environ.get("AURORA_STORE_APK"),
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

    def test_resolve_local_source_allows_any_visible_regular_file(self) -> None:
        allowed = self.workspace / "note.txt"
        allowed.write_text("hello", encoding="utf-8")
        self.assertEqual(android.resolve_local_source(str(allowed)), allowed.resolve())

        outside = Path(self.tempdir.name) / "outside.txt"
        outside.write_text("available", encoding="utf-8")
        self.assertEqual(android.resolve_local_source(str(outside)), outside.resolve())

    def test_resolve_output_path_defaults_under_browser_files(self) -> None:
        destination = android.resolve_output_path(None, "192.168.1.4:5555", "screenshots", ".png")

        self.assertTrue(destination.is_relative_to(self.browser_files))
        self.assertEqual(destination.suffix, ".png")
        self.assertIn("192.168.1.4_5555", str(destination))

    def test_resolve_output_path_creates_any_visible_parent(self) -> None:
        destination = Path(self.tempdir.name) / "outside" / "captures" / "screen.png"

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
        os.environ["ANDROID_VIEW_URL"] = "http://127.0.0.1:6080/vnc.html"
        self.assertEqual(
            android.live_view("127.0.0.1:5555"),
            {
                "serial": "127.0.0.1:5555",
                "adb_endpoint": "127.0.0.1:5555",
                "grpc_url": "http://127.0.0.1:8554",
                "viewer_url": "http://127.0.0.1:6080/vnc.html",
            },
        )

    def test_parse_ui_tree_assigns_refs_and_centers(self) -> None:
        tree = android.parse_ui_tree(
            '<hierarchy><node text="Buy" content-desc="Checkout" '
            'resource-id="shop:id/buy" class="android.widget.Button" '
            'clickable="true" enabled="true" bounds="[10,20][110,80]"/>'
            '<node text="ignored" bounds="invalid"/></hierarchy>'
        )

        self.assertEqual(len(tree["tree_id"]), 16)
        self.assertEqual(
            tree["nodes"],
            [
                {
                    "ref": "r1",
                    "bounds": {
                        "left": 10,
                        "top": 20,
                        "right": 110,
                        "bottom": 80,
                        "center": [60, 50],
                    },
                    "text": "Buy",
                    "description": "Checkout",
                    "resource_id": "shop:id/buy",
                    "class": "android.widget.Button",
                    "clickable": True,
                    "enabled": True,
                }
            ],
        )

    @mock.patch.object(android, "run_adb")
    @mock.patch.object(android, "current_ui_tree")
    @mock.patch.object(android, "require_connected_serial")
    def test_tap_ref_verifies_tree_and_taps_center(
        self,
        require_connected_serial: mock.Mock,
        current_ui_tree: mock.Mock,
        run_adb: mock.Mock,
    ) -> None:
        require_connected_serial.return_value = "serial"
        current_ui_tree.return_value = {
            "tree_id": "abc123",
            "nodes": [{"ref": "r7", "bounds": {"center": [90, 120]}}],
        }

        result = android.handle_tap_ref(
            argparse.Namespace(serial="serial", ref="r7", tree_id="abc123")
        )

        run_adb.assert_called_once_with("serial", "shell", "input", "tap", "90", "120")
        self.assertEqual(result["tap"], {"x": 90, "y": 120})

    @mock.patch.object(android, "current_ui_tree")
    @mock.patch.object(android, "require_connected_serial")
    def test_tap_ref_rejects_stale_tree(
        self,
        require_connected_serial: mock.Mock,
        current_ui_tree: mock.Mock,
    ) -> None:
        require_connected_serial.return_value = "serial"
        current_ui_tree.return_value = {"tree_id": "new", "nodes": []}

        with self.assertRaisesRegex(RuntimeError, "UI changed"):
            android.handle_tap_ref(
                argparse.Namespace(serial="serial", ref="r1", tree_id="old")
            )

    def test_parser_does_not_impose_recording_or_gesture_caps(self) -> None:
        record = android.parser().parse_args(["record", "--seconds", "7200"])
        swipe = android.parser().parse_args(
            ["swipe", "0", "0", "10", "10", "--duration-ms", "120000"]
        )

        self.assertEqual(record.seconds, 7200)
        self.assertEqual(swipe.duration_ms, 120000)

    @mock.patch.object(android.subprocess, "call", return_value=17)
    def test_adb_passthrough_preserves_arguments_and_exit_status(
        self, call: mock.Mock
    ) -> None:
        with mock.patch.object(
            android.sys,
            "argv",
            ["android", "--serial", "device-1", "adb", "shell", "dumpsys", "window"],
        ):
            result = android.main()

        call.assert_called_once_with(
            ["adb", "-s", "device-1", "shell", "dumpsys", "window"]
        )
        self.assertEqual(result, 17)

    @mock.patch.object(android.subprocess, "call", return_value=0)
    def test_adb_passthrough_can_skip_default_serial(self, call: mock.Mock) -> None:
        with (
            mock.patch.dict(android.os.environ, {"ANDROID_SERIAL": "device-1"}),
            mock.patch.object(
                android.sys,
                "argv",
                ["android", "adb", "--no-serial", "devices", "-l"],
            ),
        ):
            result = android.main()

        call.assert_called_once_with(["adb", "devices", "-l"])
        self.assertEqual(result, 0)

    @mock.patch.object(android, "run_adb", return_value="Success\n")
    @mock.patch.object(android, "resolve_local_source")
    @mock.patch.object(android, "require_connected_serial", return_value="serial")
    def test_install_exposes_adb_install_controls(
        self,
        require_connected_serial: mock.Mock,
        resolve_local_source: mock.Mock,
        run_adb: mock.Mock,
    ) -> None:
        del require_connected_serial
        apk = self.workspace / "shop.apk"
        resolve_local_source.return_value = apk

        result = android.handle_install(
            argparse.Namespace(
                serial="serial",
                path=str(apk),
                replace=True,
                grant_all=True,
                downgrade=True,
                test_only=True,
                timeout=900,
            )
        )

        run_adb.assert_called_once_with(
            "serial", "install", "-r", "-g", "-d", "-t", str(apk), timeout=900
        )
        self.assertEqual(result["response"], "Success")

    @mock.patch.object(android, "shell_text", return_value="package:/data/app/aurora/base.apk")
    @mock.patch.object(android, "run_adb", return_value="Success\n")
    @mock.patch.object(android, "require_connected_serial", return_value="serial")
    def test_install_aurora_verifies_bundled_apk_and_package(
        self,
        require_connected_serial: mock.Mock,
        run_adb: mock.Mock,
        shell_text: mock.Mock,
    ) -> None:
        del require_connected_serial
        apk = Path(self.tempdir.name) / "AuroraStore.apk"
        apk.write_bytes(b"official apk")
        digest = android.hashlib.sha256(b"official apk").hexdigest()
        with (
            mock.patch.object(android, "_AURORA_STORE_SHA256", digest),
            mock.patch.dict(os.environ, {"AURORA_STORE_APK": str(apk)}),
        ):
            result = android.handle_install_aurora(
                argparse.Namespace(serial="serial", timeout=900)
            )

        run_adb.assert_called_once_with(
            "serial", "install", "-r", "-g", str(apk), timeout=900
        )
        shell_text.assert_called_once_with(
            "serial", "pm", "path", "com.aurora.store", timeout=900
        )
        self.assertEqual(result["package"], "com.aurora.store")
        self.assertEqual(result["sha256"], digest)

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

    @mock.patch.object(android, "health_report")
    @mock.patch.object(android, "handle_ui_dump")
    @mock.patch.object(android, "handle_screenshot")
    @mock.patch.object(android, "require_connected_serial")
    def test_snapshot_writes_metadata_bundle(
        self,
        require_connected_serial: mock.Mock,
        handle_screenshot: mock.Mock,
        handle_ui_dump: mock.Mock,
        health_report: mock.Mock,
    ) -> None:
        serial = "127.0.0.1:5555"
        require_connected_serial.return_value = serial
        screenshot = self.browser_files / "android" / "127.0.0.1_5555" / "snapshots" / "checkout.png"
        ui_dump = self.browser_files / "android" / "127.0.0.1_5555" / "snapshots" / "checkout.xml"
        screenshot.parent.mkdir(parents=True, exist_ok=True)
        screenshot.write_bytes(b"png")
        ui_dump.write_text("<hierarchy/>", encoding="utf-8")
        handle_screenshot.return_value = {"path": str(screenshot)}
        handle_ui_dump.return_value = {"path": str(ui_dump)}
        health_report.return_value = {"boot_completed": True}

        result = android.handle_snapshot(argparse.Namespace(serial=serial, name="checkout"))

        metadata = Path(result["metadata_path"])
        self.assertTrue(metadata.is_file())
        payload = json.loads(metadata.read_text(encoding="utf-8"))
        self.assertEqual(payload["serial"], serial)
        self.assertEqual(payload["screenshot"], str(screenshot))
        self.assertEqual(payload["ui_dump"], str(ui_dump))
        self.assertEqual(payload["health"], {"boot_completed": True})

    def test_android_launcher_preserves_required_runtime_directories(self) -> None:
        launcher = (APP_ROOT / "scripts" / "android-emulator-launch.sh").read_text(
            encoding="utf-8"
        )

        self.assertNotIn("rm -rf /tmp/*", launcher)
        self.assertNotIn("MediumPhone", launcher)
        self.assertIn("-name '*.ini'", launcher)
        self.assertIn('export ANDROID_AVD_HOME="$AVD_HOME"', launcher)
        self.assertIn(".hermes-system-image-sha256", launcher)
        self.assertIn("android-home-migrations", launcher)
        self.assertIn('mv "$AVD_HOME" "$migration_dir"', launcher)
        self.assertLess(
            launcher.index("rm -rf /tmp/android-unknown"),
            launcher.index("mkdir -p /root/.android"),
        )

    def test_android_workload_is_pinned_and_has_live_viewer(self) -> None:
        statefulset = (APP_ROOT / "statefulset.yaml").read_text(encoding="utf-8")
        services = (APP_ROOT / "services.yaml").read_text(encoding="utf-8")
        workflow = (APP_ROOT.parents[3] / ".github" / "workflows" / "hermes-android-image.yaml").read_text(
            encoding="utf-8"
        )
        versions = (APP_ROOT.parents[3] / "packages" / "hermes-android-image" / "versions.env").read_text(
            encoding="utf-8"
        )

        emulator_image = re.search(
            r"(?m)^        - name: android-emulator\n          image: (.+)$",
            statefulset,
        )
        self.assertIsNotNone(emulator_image)
        assert emulator_image
        self.assertIn("@sha256:", emulator_image.group(1))
        self.assertTrue(
            emulator_image.group(1).startswith(
                "us-docker.pkg.dev/android-emulator-268719/images/30-google-x64-no-metrics:"
            )
            or emulator_image.group(1).startswith(
                "ghcr.io/michaelbrusegard/hermes-android:sha-"
            )
        )
        self.assertIn("- name: android-viewer\n", statefulset)
        self.assertIn("value: 0.0.0.0:6081", statefulset)
        self.assertIn("chown 10000:10000 /opt/android/adb/adbkey", statefulset)
        self.assertIn("- name: android-tmp\n              mountPath: /tmp", statefulset)
        self.assertIn("value: -gpu swiftshader_indirect -timezone Europe/Oslo", statefulset)
        self.assertIn("/android/sdk/platform-tools/adb connect", statefulset)
        self.assertNotIn("pgrep -x scrcpy", statefulset)
        self.assertIn("kill -0 \"$scrcpy_pid\"", statefulset)
        self.assertIn("port: 6080\n      targetPort: android-viewer", services)
        self.assertIn("Android 17 Play Store image", workflow)
        self.assertIn("x86_64-37.0_r06.zip", versions)
        self.assertIn("ANDROID_PLATFORM_TOOLS_VERSION=37.0.1", versions)
        self.assertIn(f"AURORA_STORE_SHA256={android._AURORA_STORE_SHA256}", versions)
        self.assertIn("AURORA_STORE_SHA256", workflow)
        self.assertIn("- name: prepare-android", workflow)


if __name__ == "__main__":
    unittest.main()
