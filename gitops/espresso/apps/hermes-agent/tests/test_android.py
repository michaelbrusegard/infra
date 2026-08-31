from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import subprocess
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest import mock


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "android.py"
APP_ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("hermes_android", SCRIPT_PATH)
assert SPEC and SPEC.loader
android = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(android)

COMPANION_PATH = APP_ROOT / "scripts" / "android-companion.py"
COMPANION_SPEC = importlib.util.spec_from_file_location("hermes_android_companion", COMPANION_PATH)
assert COMPANION_SPEC and COMPANION_SPEC.loader
companion = importlib.util.module_from_spec(COMPANION_SPEC)
COMPANION_SPEC.loader.exec_module(companion)

MANIFEST_UPDATER_PATH = (
    APP_ROOT.parents[3] / "packages" / "hermes-android-image" / "update-manifest.py"
)
MANIFEST_UPDATER_SPEC = importlib.util.spec_from_file_location(
    "hermes_android_manifest_updater",
    MANIFEST_UPDATER_PATH,
)
assert MANIFEST_UPDATER_SPEC and MANIFEST_UPDATER_SPEC.loader
manifest_updater = importlib.util.module_from_spec(MANIFEST_UPDATER_SPEC)
MANIFEST_UPDATER_SPEC.loader.exec_module(manifest_updater)


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
            "ANDROID_COMPANION_URL": os.environ.get("ANDROID_COMPANION_URL"),
            "ANDROID_EMULATOR_GRPC_TOKEN_FILE": os.environ.get(
                "ANDROID_EMULATOR_GRPC_TOKEN_FILE"
            ),
            "ANDROID_COMPANION_TOKEN_FILE": os.environ.get("ANDROID_COMPANION_TOKEN_FILE"),
            "ANDROID_SERIAL": os.environ.get("ANDROID_SERIAL"),
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

    def test_global_serial_survives_subcommand_compatibility_option(self) -> None:
        before = android.parser().parse_args(["--serial", "device-a", "health"])
        after = android.parser().parse_args(["health", "--serial", "device-b"])

        self.assertEqual(before.serial, "device-a")
        self.assertEqual(after.serial, "device-b")

    def test_http_companion_requires_authentication_for_semantic_tree(self) -> None:
        token_file = Path(self.tempdir.name) / "http-companion-token"
        token_file.write_text("http-companion-secret\n", encoding="utf-8")
        os.environ["ANDROID_COMPANION_TOKEN_FILE"] = str(token_file)
        os.environ["ANDROID_SERIAL"] = "device-a"
        server = companion.Server(("127.0.0.1", 0), companion.Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        endpoint = f"http://127.0.0.1:{server.server_port}/v1/ui-tree"
        try:
            with self.assertRaises(urllib.error.HTTPError) as rejected:
                urllib.request.urlopen(endpoint, timeout=2)
            self.assertEqual(rejected.exception.code, 401)
            rejected.exception.close()

            request = urllib.request.Request(
                endpoint,
                headers={"Authorization": "Bearer http-companion-secret"},
            )
            with mock.patch.object(
                companion.android,
                "current_ui_tree",
                return_value={"backend": "accessibility-service", "nodes": []},
            ):
                with urllib.request.urlopen(request, timeout=2) as response:
                    payload = json.load(response)
            self.assertTrue(payload["ok"])
            self.assertEqual(payload["backend"], "accessibility-service")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_http_companion_exports_unauthenticated_degraded_metrics(self) -> None:
        server = companion.Server(("127.0.0.1", 0), companion.Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        endpoint = f"http://127.0.0.1:{server.server_port}/metrics"
        try:
            with (
                mock.patch.object(companion, "launcher_status", return_value={"state": "disabled"}),
                mock.patch.object(
                    companion,
                    "accessibility_status",
                    return_value={"state": "stopped"},
                ),
                urllib.request.urlopen(endpoint, timeout=2) as response,
            ):
                payload = response.read().decode("utf-8")
                self.assertEqual(response.headers.get_content_type(), "text/plain")
            self.assertIn("hermes_android_companion_up 1", payload)
            self.assertIn("hermes_android_available 0", payload)
            self.assertIn("hermes_android_disabled 1", payload)
            self.assertIn('hermes_android_launcher_state{state="disabled"} 1', payload)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

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
        os.environ["ANDROID_COMPANION_URL"] = "http://127.0.0.1:8777"
        self.assertEqual(
            android.live_view("127.0.0.1:5555"),
            {
                "serial": "127.0.0.1:5555",
                "adb_endpoint": "127.0.0.1:5555",
                "grpc_url": "http://127.0.0.1:8554",
                "viewer_url": "http://127.0.0.1:6080/vnc.html",
                "companion_url": "http://127.0.0.1:8777",
            },
        )

    @mock.patch.object(android.subprocess, "run")
    def test_run_grpc_requires_and_injects_persisted_token(self, run: mock.Mock) -> None:
        token_file = Path(self.tempdir.name) / "grpc-token"
        token_file.write_text("secret-token\n", encoding="utf-8")
        os.environ["ANDROID_EMULATOR_GRPC_TOKEN_FILE"] = str(token_file)
        run.return_value = subprocess.CompletedProcess([], 0, stdout='{"state":"RUNNING"}\n', stderr="")

        response = android.run_grpc(
            "http://127.0.0.1:8554",
            "android.emulation.control.EmulatorController/getVmState",
        )

        command = run.call_args.args[0]
        self.assertIn("authorization: Bearer secret-token", command)
        self.assertEqual(command[-2], "127.0.0.1:8554")
        self.assertEqual(response, '{"state":"RUNNING"}')

    @mock.patch.object(android, "run_adb")
    @mock.patch.object(android, "grpc_json")
    @mock.patch.object(android, "require_connected_serial", return_value="127.0.0.1:5555")
    def test_screenshot_prefers_emulator_framebuffer(
        self,
        _require_serial: mock.Mock,
        grpc_json: mock.Mock,
        run_adb: mock.Mock,
    ) -> None:
        os.environ["ANDROID_EMULATOR_GRPC_URL"] = "http://127.0.0.1:8554"
        grpc_json.return_value = {"image": "c2VjdXJlLXBuZw=="}
        destination = Path(self.tempdir.name) / "secure.png"

        result = android.handle_screenshot(argparse.Namespace(path=str(destination)))

        self.assertEqual(destination.read_bytes(), b"secure-png")
        self.assertEqual(result["source"], "emulator-grpc")
        self.assertTrue(result["secure_windows_visible"])
        grpc_json.assert_called_once_with(
            "127.0.0.1:5555",
            "android.emulation.control.EmulatorController/getScreenshot",
            {"format": "PNG", "display": 0},
            timeout=120,
        )
        run_adb.assert_not_called()

    @mock.patch.object(android, "run_adb", return_value=b"adb-png")
    @mock.patch.object(android, "grpc_json", side_effect=RuntimeError("gRPC unavailable"))
    @mock.patch.object(android, "require_connected_serial", return_value="127.0.0.1:5555")
    def test_screenshot_falls_back_to_adb(
        self,
        _require_serial: mock.Mock,
        _grpc_json: mock.Mock,
        run_adb: mock.Mock,
    ) -> None:
        os.environ["ANDROID_EMULATOR_GRPC_URL"] = "http://127.0.0.1:8554"
        destination = Path(self.tempdir.name) / "fallback.png"

        result = android.handle_screenshot(argparse.Namespace(path=str(destination)))

        self.assertEqual(destination.read_bytes(), b"adb-png")
        self.assertEqual(result["source"], "adb-screencap")
        self.assertFalse(result["secure_windows_visible"])
        self.assertIn("gRPC unavailable", result["grpc_error"])
        run_adb.assert_called_once_with(
            "127.0.0.1:5555",
            "exec-out",
            "screencap",
            "-p",
            text=False,
            timeout=120,
        )

    @mock.patch.object(android, "accessibility_snapshot")
    def test_current_ui_tree_prefers_on_device_accessibility(
        self,
        accessibility_snapshot: mock.Mock,
    ) -> None:
        accessibility_snapshot.return_value = {
            "backend": "accessibility-service",
            "tree_id": "tree-1",
            "nodes": [],
        }

        tree = android.current_ui_tree("serial")

        self.assertEqual(tree["backend"], "accessibility-service")
        accessibility_snapshot.assert_called_once_with("serial")

    @mock.patch.object(android, "run_adb")
    def test_accessibility_request_authenticates_over_adb_shell(self, run_adb: mock.Mock) -> None:
        token_file = Path(self.tempdir.name) / "companion-token"
        token_file.write_text("companion-secret\n", encoding="utf-8")
        os.environ["ANDROID_COMPANION_TOKEN_FILE"] = str(token_file)
        sent: list[bytes] = []

        def adb_side_effect(_: str, *args: str, **__: object) -> str | bytes:
            if args[0] == "push":
                sent.append(Path(args[1]).read_bytes())
                return ""
            if args[0] == "shell" and len(args) == 2:
                return b'{"ok":true,"connected":true}\n'
            return ""

        run_adb.side_effect = adb_side_effect
        response = android.accessibility_request("serial", {"op": "health"})

        self.assertEqual(run_adb.call_count, 3)
        push_call, request_call, cleanup_call = run_adb.call_args_list
        self.assertEqual(push_call.args[1], "push")
        self.assertIn("nc -w 20 127.0.0.1 8765", request_call.args[2])
        self.assertEqual(cleanup_call.args[1:4], ("shell", "rm", "-f"))
        payload = json.loads(sent[0])
        self.assertEqual(payload, {"op": "health", "token": "companion-secret"})
        self.assertTrue(response["connected"])

    def test_stamp_tree_adds_short_lived_ref_metadata(self) -> None:
        tree = android.stamp_tree({"tree_id": "abc", "nodes": []}, ttl_seconds=12.0)

        self.assertEqual(tree["tree_id"], "abc")
        self.assertEqual(tree["ref_ttl_seconds"], 12.0)
        self.assertLess(
            android.parse_iso8601(tree["captured_at"]),
            android.parse_iso8601(tree["expires_at"]),
        )

    def test_compact_ui_tree_nodes_keeps_only_labeled_clickable_nodes(self) -> None:
        tree = {
            "tree_id": "tree-1",
            "expires_at": "2099-01-01T00:00:00Z",
            "nodes": [
                {"ref": "r1", "clickable": True, "text": " Buy "},
                {
                    "ref": "r2",
                    "clickable": True,
                    "description": "Checkout",
                },
                {"ref": "r3", "clickable": True, "text": ""},
                {"ref": "r4", "clickable": False, "text": "Ignored"},
            ],
        }

        self.assertEqual(
            android.compact_ui_tree_nodes(tree),
            [
                {
                    "ref": "r1",
                    "text": "Buy",
                    "content_description": "",
                    "tree_id": "tree-1",
                    "expires_at": "2099-01-01T00:00:00Z",
                },
                {
                    "ref": "r2",
                    "text": "",
                    "content_description": "Checkout",
                    "tree_id": "tree-1",
                    "expires_at": "2099-01-01T00:00:00Z",
                },
            ],
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

    @mock.patch.object(android, "accessibility_action")
    @mock.patch.object(android, "require_connected_serial")
    def test_tap_ref_uses_accessibility_action_and_verification(
        self,
        require_connected_serial: mock.Mock,
        accessibility_action: mock.Mock,
    ) -> None:
        require_connected_serial.return_value = "serial"
        accessibility_action.return_value = {"accepted": True, "changed": True}

        result = android.handle_tap_ref(
            argparse.Namespace(
                serial="serial",
                ref="r7",
                tree_id="abc123",
                expires_at="2099-01-01T00:00:00Z",
                verify_timeout=3.0,
                fallback_screenshot=None,
                require_change=False,
            )
        )

        accessibility_action.assert_called_once_with(
            "serial",
            "abc123",
            "r7",
            "click",
            verify_timeout=3.0,
            require_change=False,
        )
        self.assertEqual(result["mode"], "accessibility-action")
        self.assertTrue(result["verification"]["changed"])

    @mock.patch.object(android, "accessibility_action")
    @mock.patch.object(android, "require_connected_serial")
    def test_tap_ref_rejects_stale_tree(
        self,
        require_connected_serial: mock.Mock,
        accessibility_action: mock.Mock,
    ) -> None:
        require_connected_serial.return_value = "serial"
        accessibility_action.side_effect = RuntimeError(
            "accessibility companion rejected request: stale tree_id"
        )

        with self.assertRaisesRegex(RuntimeError, "stale tree_id"):
            android.handle_tap_ref(
                argparse.Namespace(
                    serial="serial",
                    ref="r1",
                    tree_id="old",
                    expires_at=None,
                    verify_timeout=3.0,
                    fallback_screenshot=None,
                    require_change=False,
                )
            )

    @mock.patch.object(android, "current_ui_tree")
    @mock.patch.object(android, "require_connected_serial")
    def test_tap_ref_rejects_expired_ref(
        self,
        require_connected_serial: mock.Mock,
        current_ui_tree: mock.Mock,
    ) -> None:
        require_connected_serial.return_value = "serial"
        current_ui_tree.return_value = {
            "tree_id": "same",
            "nodes": [{"ref": "r1", "bounds": {"center": [1, 2]}}],
        }

        with self.assertRaisesRegex(RuntimeError, "expired"):
            android.handle_tap_ref(
                argparse.Namespace(
                    serial="serial",
                    ref="r1",
                    tree_id="same",
                    expires_at="2000-01-01T00:00:00Z",
                    verify_timeout=3.0,
                    fallback_screenshot=None,
                    require_change=False,
                )
            )

    def test_parser_does_not_impose_recording_or_gesture_caps(self) -> None:
        record = android.parser().parse_args(["record", "--seconds", "7200"])
        swipe = android.parser().parse_args(
            ["swipe", "0", "0", "10", "10", "--duration-ms", "120000"]
        )
        ui_tree = android.parser().parse_args(["ui-tree", "--compact"])

        self.assertEqual(record.seconds, 7200)
        self.assertEqual(swipe.duration_ms, 120000)
        self.assertTrue(ui_tree.compact)

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

    @mock.patch.object(android, "accessibility_action")
    @mock.patch.object(android, "accessibility_snapshot")
    @mock.patch.object(android, "require_connected_serial", return_value="serial")
    def test_text_uses_accessibility_set_text_for_unicode(
        self,
        require_connected_serial: mock.Mock,
        accessibility_snapshot: mock.Mock,
        accessibility_action: mock.Mock,
    ) -> None:
        del require_connected_serial
        accessibility_snapshot.return_value = {
            "tree_id": "tree-1",
            "nodes": [{"ref": "r4", "editable": True, "focused": True}],
        }
        accessibility_action.return_value = {"accepted": True, "changed": True}
        result = android.handle_text(
            argparse.Namespace(
                serial="serial",
                text="Grüße ☕",
                ref=None,
                tree_id=None,
                verify_timeout=1.0,
                fallback_screenshot=None,
            )
        )

        accessibility_action.assert_called_once_with(
            "serial",
            "tree-1",
            "r4",
            "set_text",
            value="Grüße ☕",
            verify_timeout=1.0,
            require_change=False,
        )
        self.assertEqual(result["mode"], "accessibility-set-text")

    @mock.patch.object(android, "set_clipboard_text", side_effect=RuntimeError("gRPC unavailable"))
    @mock.patch.object(android, "accessibility_snapshot", side_effect=RuntimeError("service unavailable"))
    @mock.patch.object(android, "run_adb")
    @mock.patch.object(android, "require_connected_serial", return_value="serial")
    def test_text_keeps_adb_as_final_ascii_fallback(
        self,
        require_connected_serial: mock.Mock,
        run_adb: mock.Mock,
        accessibility_snapshot: mock.Mock,
        set_clipboard_text: mock.Mock,
    ) -> None:
        del require_connected_serial
        del accessibility_snapshot
        del set_clipboard_text

        result = android.handle_text(
            argparse.Namespace(
                serial="serial",
                text="hello world",
                verify_timeout=1.0,
                fallback_screenshot=None,
            )
        )

        run_adb.assert_called_once_with("serial", "shell", "input", "text", "hello%sworld")
        self.assertEqual(result["mode"], "adb-input-fallback")

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

    @mock.patch.object(android, "grpc_json")
    def test_get_emulator_status_collects_status_and_vm_state(self, grpc_json: mock.Mock) -> None:
        grpc_json.side_effect = [
            {"uptime": "1s"},
            {"state": "RUNNING"},
        ]

        with mock.patch.dict(
            os.environ,
            {"ANDROID_EMULATOR_GRPC_URL": "http://127.0.0.1:8554"},
            clear=False,
        ):
            status = android.get_emulator_status("127.0.0.1:5555")

        self.assertEqual(status["grpc_url"], "http://127.0.0.1:8554")
        self.assertEqual(status["status"], {"uptime": "1s"})
        self.assertEqual(status["vm_state"], {"state": "RUNNING"})

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
        self.assertIn('required_sdk="${ANDROID_REQUIRED_SDK:-}"', launcher)
        self.assertIn('required_release="${ANDROID_REQUIRED_RELEASE:-}"', launcher)
        self.assertIn('"state":"disabled","reason":"wrong-platform"', launcher)
        self.assertIn('write_status "running"', launcher)
        self.assertIn("trap cleanup EXIT", launcher)
        self.assertIn("adb_device emu kill", launcher)
        self.assertIn("-grpc-use-token", launcher)
        self.assertIn('-grpc-allowlist "$GRPC_ALLOWLIST_FILE"', launcher)
        self.assertIn('"/android.emulation.control.v2.Rtc/.*",', launcher)
        self.assertIn("enable_accessibility_companion", launcher)
        self.assertIn("nc -w 2 127.0.0.1 8765", launcher)
        self.assertIn("/root/.android/avd/running/pid_*.ini", launcher)
        self.assertIn('write_accessibility_status "starting" "waiting-for-boot"', launcher)
        self.assertIn('rm -f "$GRPC_TOKEN_FILE"', launcher)
        self.assertIn('mv "$AVD_HOME" "$migration_dir"', launcher)
        self.assertLess(
            launcher.index("rm -rf /tmp/android-unknown"),
            launcher.index("mkdir -p /root/.android"),
        )

    def test_chromium_uses_its_internal_sandbox(self) -> None:
        statefulset = (APP_ROOT / "statefulset.yaml").read_text(encoding="utf-8")
        browser_image = (
            APP_ROOT.parents[3] / "packages" / "hermes-browser-image" / "default.nix"
        ).read_text(encoding="utf-8")
        seccomp_generator = (
            APP_ROOT.parents[3]
            / "packages"
            / "chromium-seccomp-profile"
            / "generate.go"
        ).read_text(encoding="utf-8")
        seccomp_install = (
            APP_ROOT.parents[3] / "hosts" / "espresso" / "seccomp-profiles.nix"
        ).read_text(encoding="utf-8")
        k3s_module = (
            APP_ROOT.parents[3] / "modules" / "nixos" / "k3s.nix"
        ).read_text(encoding="utf-8")
        image_workflow = (
            APP_ROOT.parents[3] / ".github" / "workflows" / "hermes-agent-image.yaml"
        ).read_text(encoding="utf-8")
        agent_browser_package = (
            APP_ROOT.parents[3]
            / "packages"
            / "hermes-agent-image"
            / "agent-browser.nix"
        ).read_text(encoding="utf-8")
        hermes_patch = (
            APP_ROOT.parents[3]
            / "packages"
            / "hermes-agent-image"
            / "hermes-v2026.8.19.patch"
        ).read_text(encoding="utf-8")
        browser = statefulset.split("        - name: browser\n", 1)[1].split(
            "        - name: android-emulator\n", 1
        )[0]
        android_viewer = statefulset.split("        - name: android-viewer\n", 1)[1].split(
            "        - name: android-viewer-auth\n", 1
        )[0]

        self.assertNotIn("--no-sandbox", browser_image)
        self.assertEqual(browser_image.count("--disable-setuid-sandbox"), 2)
        self.assertNotIn("--no-sandbox", browser)
        self.assertIn("allowPrivilegeEscalation: false", browser)
        self.assertIn("allowPrivilegeEscalation: false", android_viewer)
        self.assertIn(
            'Names:  []string{"chroot", "clone", "unshare"}', seccomp_generator
        )
        self.assertIn("chromium-seccomp-profile", seccomp_install)
        self.assertNotIn("chromium", k3s_module)
        self.assertIn(
            "nix build --out-link result-chromium-seccomp ", image_workflow
        )
        self.assertIn(
            '--security-opt "seccomp=$chromium_seccomp_profile"', image_workflow
        )
        self.assertIn(
            "kernel.apparmor_restrict_unprivileged_userns=0", image_workflow
        )
        self.assertNotIn("seccomp=unconfined", image_workflow)
        self.assertIn('version = "0.35.0";', agent_browser_package)
        self.assertNotIn("agent-browser-target-id.patch", image_workflow)
        self.assertIn('                "--pin-tab",', hermes_patch)
        seccomp_profile = (
            "seccompProfile:\n"
            "              type: Localhost\n"
            "              localhostProfile: hermes/chromium.json"
        )
        self.assertIn(seccomp_profile, browser)
        self.assertIn(seccomp_profile, android_viewer)

    def test_android_manifest_updater_atomically_releases_pending_rollout(self) -> None:
        manifest = (APP_ROOT / "statefulset.yaml").read_text(encoding="utf-8")
        manifest = manifest.replace(
            manifest_updater.READY_ANNOTATION,
            manifest_updater.PENDING_ANNOTATION,
            1,
        ).replace(
            manifest_updater.READY_STRATEGY,
            manifest_updater.PENDING_STRATEGY,
            1,
        )
        image = f"ghcr.io/example/hermes-android:sha-test@sha256:{'a' * 64}"

        updated = manifest_updater.update_content(manifest, image)

        self.assertEqual(updated.count(f"image: {image}"), 2)
        self.assertNotIn(manifest_updater.PENDING_ANNOTATION, updated)
        self.assertIn(manifest_updater.READY_ANNOTATION, updated)
        self.assertIn(manifest_updater.READY_STRATEGY, updated)
        self.assertNotIn(manifest_updater.PENDING_STRATEGY, updated)

    def test_android_manifest_updater_rejects_mutable_or_inconsistent_rollouts(self) -> None:
        manifest = (APP_ROOT / "statefulset.yaml").read_text(encoding="utf-8")
        manifest = manifest.replace(
            manifest_updater.READY_ANNOTATION,
            manifest_updater.PENDING_ANNOTATION,
            1,
        ).replace(
            manifest_updater.READY_STRATEGY,
            manifest_updater.PENDING_STRATEGY,
            1,
        )
        with self.assertRaisesRegex(ValueError, "immutable GHCR digest"):
            manifest_updater.update_content(manifest, "ghcr.io/example/hermes-android:latest")

        inconsistent = manifest.replace(
            manifest_updater.PENDING_STRATEGY,
            manifest_updater.READY_STRATEGY,
            1,
        )
        image = f"ghcr.io/example/hermes-android:sha-test@sha256:{'b' * 64}"
        with self.assertRaisesRegex(ValueError, "missing its partition hold"):
            manifest_updater.update_content(inconsistent, image)

    def test_android_workload_is_pinned_and_has_live_viewer(self) -> None:
        statefulset = (APP_ROOT / "statefulset.yaml").read_text(encoding="utf-8")
        services = (APP_ROOT / "services.yaml").read_text(encoding="utf-8")
        httproute = (APP_ROOT / "httproute.yaml").read_text(encoding="utf-8")
        network_policy = (APP_ROOT / "network-policy.yaml").read_text(encoding="utf-8")
        netbird_egress = (APP_ROOT / "netbird-egress.yaml").read_text(encoding="utf-8")
        monitoring = (APP_ROOT / "monitoring.yaml").read_text(encoding="utf-8")
        kustomization = (APP_ROOT / "kustomization.yaml").read_text(encoding="utf-8")
        viewer_app = (
            APP_ROOT.parents[3]
            / "packages"
            / "hermes-browser-image"
            / "android-viewer-app.tsx"
        ).read_text(encoding="utf-8")
        viewer_auth_tofu = (
            APP_ROOT.parents[3]
            / "gitops"
            / "espresso"
            / "tofu"
            / "hermes-auth"
            / "main.tf"
        ).read_text(encoding="utf-8")
        netbird_tofu = (
            APP_ROOT.parents[3]
            / "gitops"
            / "espresso"
            / "tofu"
            / "netbird"
            / "main.tf"
        ).read_text(encoding="utf-8")
        companion_wrapper = (APP_ROOT / "scripts" / "android-companion").read_text(
            encoding="utf-8"
        )
        self.assertIn('mkdir -p "$HOME"', companion_wrapper)
        workflow = (APP_ROOT.parents[3] / ".github" / "workflows" / "hermes-android-image.yaml").read_text(
            encoding="utf-8"
        )
        manifest_updater_source = MANIFEST_UPDATER_PATH.read_text(encoding="utf-8")
        agent_workflow = (
            APP_ROOT.parents[3] / ".github" / "workflows" / "hermes-agent-image.yaml"
        ).read_text(encoding="utf-8")
        kvm_device_plugin = (
            APP_ROOT.parents[3]
            / "gitops"
            / "espresso"
            / "infrastructure"
            / "controllers"
            / "generic-device-plugin"
            / "daemonset.yaml"
        ).read_text(encoding="utf-8")
        versions = (APP_ROOT.parents[3] / "packages" / "hermes-android-image" / "versions.env").read_text(
            encoding="utf-8"
        )
        accessibility_source = (
            APP_ROOT.parents[3]
            / "packages"
            / "hermes-android-companion"
            / "src"
            / "com"
            / "hermes"
            / "agent"
            / "accessibility"
            / "HermesAccessibilityService.java"
        ).read_text(encoding="utf-8")
        accessibility_manifest = (
            APP_ROOT.parents[3] / "packages" / "hermes-android-companion" / "AndroidManifest.xml"
        ).read_text(encoding="utf-8")
        config_receiver_source = (
            APP_ROOT.parents[3]
            / "packages"
            / "hermes-android-companion"
            / "src"
            / "com"
            / "hermes"
            / "agent"
            / "accessibility"
            / "ConfigReceiver.java"
        ).read_text(encoding="utf-8")

        emulator_image = re.search(
            r"(?m)^        - name: android-emulator\n          image: (.+)$",
            statefulset,
        )
        self.assertIsNotNone(emulator_image)
        assert emulator_image
        self.assertIn("@sha256:", emulator_image.group(1))
        self.assertIn('- name: ANDROID_REQUIRED_SDK\n              value: "37"', statefulset)
        self.assertIn('- name: ANDROID_REQUIRED_RELEASE\n              value: "17"', statefulset)
        self.assertIn("- name: android-companion\n", statefulset)
        self.assertIn("- /opt/data/scripts/android-companion", statefulset)
        self.assertIn(
            "- name: data\n              mountPath: /opt/data\n              readOnly: true",
            statefulset,
        )
        self.assertNotIn("name: android-grpc", statefulset)
        self.assertIn("value: 0.0.0.0:8777", statefulset)
        self.assertIn("/opt/android/companion/auth-token", statefulset)
        self.assertIn("/opt/android/companion/emulator-grpc-token", statefulset)
        self.assertNotIn("ANDROID_ACCESSIBILITY_PORT", statefulset)
        self.assertIn("HermesAccessibility-1.0.0.apk", statefulset)
        self.assertIn(
            "[ ! -s /opt/android/apks/AuroraStore-4.8.4.apk ]",
            statefulset,
        )
        self.assertIn(
            "[ ! -s /opt/android/apks/HermesAccessibility-1.0.0.apk ]",
            statefulset,
        )
        self.assertIn("- name: android-viewer\n", statefulset)
        self.assertIn("value: 127.0.0.1:6081", statefulset)
        self.assertIn("chown 10000:0 /opt/android/adb/adbkey", statefulset)
        self.assertIn("chown 10000:0 /opt/android/companion/auth-token", statefulset)
        self.assertIn("chmod 640 /opt/android/adb/adbkey", statefulset)
        self.assertIn("chmod 640 /opt/android/companion/auth-token", statefulset)
        self.assertIn(
            "securityContext:\n            runAsUser: 0\n            runAsGroup: 0\n            allowPrivilegeEscalation: false",
            statefulset,
        )
        self.assertIn("- name: android-tmp\n              mountPath: /tmp", statefulset)
        self.assertIn(
            "value: -gpu swiftshader_indirect -timezone America/Los_Angeles -prop persist.sys.locale=en-US",
            statefulset,
        )
        self.assertNotIn("- name: netbird-egress", statefulset)
        self.assertIn("kind: SidecarProfile", netbird_egress)
        self.assertIn("kind: SetupKey", netbird_egress)
        self.assertIn("name: Hermes Egress", netbird_egress)
        self.assertIn("injectionMode: Sidecar", netbird_egress)
        self.assertNotIn("containerOverride:", netbird_egress)
        self.assertIn("value: America/Los_Angeles", statefulset)
        self.assertIn("settings put system time_12_24 24", (APP_ROOT / "scripts" / "android-emulator-launch.sh").read_text(encoding="utf-8"))
        self.assertIn("hermes.michaelbrusegard.com/kvm: \"1\"", statefulset)
        self.assertNotIn("kubernetes.io/hostname", statefulset)
        self.assertNotIn("mountPath: /dev/kvm", statefulset)
        rollout_pending = 'hermes.michaelbrusegard.com/android-image-rollout: "pending"' in statefulset
        rollout_ready = 'hermes.michaelbrusegard.com/android-image-rollout: "ready"' in statefulset
        self.assertNotEqual(rollout_pending, rollout_ready)
        if rollout_pending:
            self.assertIn(manifest_updater.PENDING_STRATEGY, statefulset)
        else:
            self.assertIn(manifest_updater.READY_STRATEGY, statefulset)
        self.assertIn("/android/sdk/platform-tools/adb connect", statefulset)
        self.assertNotIn("pgrep -x scrcpy", statefulset)
        self.assertIn("emulator-webrtc", statefulset)
        self.assertIn("kill -0 \"$viewer_pid\"", statefulset)
        self.assertIn("kill -0 \"$gateway_pid\"", statefulset)
        self.assertIn("kill -0 \"$scrcpy_pid\"", statefulset)
        self.assertIn("http://127.0.0.1:8080/api/v1/emulator/status", statefulset)
        self.assertIn("port: 8777\n      targetPort: android-api", services)
        self.assertNotIn("targetPort: android-grpc", services)
        self.assertIn("port: 6080\n      targetPort: viewer-auth", services)
        self.assertIn("name: hermes-browser", services)
        self.assertIn("port: 6080\n      targetPort: browser-auth", services)
        self.assertIn("android.asgard.michaelbrusegard.com", httproute)
        self.assertIn("browser.asgard.michaelbrusegard.com", httproute)
        self.assertIn("type: Exact\n            value: /", httproute)
        self.assertIn("replaceFullPath: /vnc.html", httproute)
        self.assertIn("name: hermes-android\n          port: 6080", httproute)
        self.assertIn("name: hermes-browser\n          port: 6080", httproute)
        self.assertIn("- httproute.yaml", kustomization)
        self.assertIn("- name: ANDROID_VIEW_URL", statefulset)
        self.assertIn(
            "value: https://android.asgard.michaelbrusegard.com/vnc.html?autoconnect=true&resize=scale&view_only=false&reconnect=true",
            statefulset,
        )
        self.assertIn("- name: BROWSER_VIEW_URL", statefulset)
        self.assertIn(
            "value: https://browser.asgard.michaelbrusegard.com/vnc.html?autoconnect=true&resize=scale&view_only=false&reconnect=true",
            statefulset,
        )
        self.assertIn("- name: android-viewer-auth", statefulset)
        self.assertIn("- name: browser-viewer-auth", statefulset)
        self.assertIn("oauth2-proxy:v7.15.4@sha256:", statefulset)
        self.assertIn("--upstream=http://127.0.0.1:6081", statefulset)
        self.assertIn("--upstream=http://127.0.0.1:6080", statefulset)
        self.assertIn("--http-address=0.0.0.0:4181", statefulset)
        self.assertIn("--code-challenge-method=S256", statefulset)
        self.assertIn("name: hermes-viewer-auth", statefulset)
        self.assertIn('className="input-overlay"', viewer_app)
        self.assertIn("inputQueue = inputQueue", viewer_app)
        self.assertIn('type: "mouse"', viewer_app)
        self.assertIn('type: "keyboard"', viewer_app)
        self.assertIn('data "pocketid_group" "admin"', viewer_auth_tofu)
        self.assertIn("data.pocketid_group.admin.id", viewer_auth_tofu)
        self.assertIn('"https://browser.${local.domain}/oauth2/callback"', viewer_auth_tofu)
        self.assertIn("hermes_browser = {", netbird_tofu)
        self.assertIn('address = "browser.${local.domain}"', netbird_tofu)
        self.assertIn('network               = "0.0.0.0/0"', netbird_tofu)
        self.assertIn("netbird_group.hermes_egress.id", netbird_tofu)
        self.assertIn('port: "8777"', network_policy)
        self.assertIn("Fail closed", network_policy)
        self.assertIn("forces the tunnel through the HTTPS relay", network_policy)
        self.assertNotIn('port: "51820"', network_policy)
        self.assertIn('- fromEntities:\n        - ingress', network_policy)
        self.assertIn('port: "4180"', network_policy)
        self.assertIn('port: "4181"', network_policy)
        self.assertNotIn('port: "6080"', network_policy)
        self.assertNotIn('port: "6081"', network_policy)
        self.assertNotIn('port: "9222"', network_policy)
        self.assertIn("kind: PodMonitor", monitoring)
        self.assertIn("path: /metrics", monitoring)
        self.assertIn("alert: HermesAndroidUnavailable", monitoring)
        self.assertIn("alert: HermesAndroidMetricsMissing", monitoring)
        self.assertIn("android-companion=scripts/android-companion", kustomization)
        self.assertIn("android-companion.py=scripts/android-companion.py", kustomization)
        self.assertIn("- netbird-egress.yaml", kustomization)
        self.assertIn("HERMES_PYTHON", companion_wrapper)
        self.assertNotIn("/opt/hermes/.venv", companion_wrapper)
        self.assertIn("Android 17 Play Store image", workflow)
        self.assertIn("x86_64-37.0_r06.zip", versions)
        self.assertIn("ANDROID_PLATFORM_TOOLS_VERSION=37.0.1", versions)
        self.assertIn("ANDROID_BUILD_TOOLS_VERSION=37.0.0", versions)
        self.assertIn("ANDROID_PLATFORM_VERSION=37.0_r02", versions)
        self.assertIn("AOSP_BUILD_COMMIT=", versions)
        self.assertIn("HERMES_ACCESSIBILITY_VERSION=1.0.0", versions)
        self.assertIn(f"AURORA_STORE_VERSION={android._AURORA_STORE_VERSION}", versions)
        self.assertIn(f"AURORA_STORE_SHA256={android._AURORA_STORE_SHA256}", versions)
        self.assertIn("AURORA_STORE_SHA256", workflow)
        self.assertIn("Build accessibility companion", workflow)
        self.assertIn("packages/hermes-android-companion/build.sh", workflow)
        self.assertIn("com.android.settings:id/search_action_bar", workflow)
        self.assertIn("Grüße ☕", workflow)
        self.assertIn("AOSP_TESTKEY_PK8_SHA256", workflow)
        self.assertIn("HERMES_ANDROID_SIGNING_KEY_PK8_B64", workflow)
        self.assertIn("HERMES_ANDROID_SIGNING_CERT_X509_PEM_B64", workflow)
        self.assertIn("HERMES_ACCESSIBILITY_SIGNING_CERT_SHA256", workflow)
        self.assertIn("update-manifest.py", workflow)
        self.assertIn("workflow_dispatch", workflow)
        self.assertIn("fcbd1076a93841fa88855acce810e342a5b78101 # v2026.8.19", agent_workflow)
        self.assertIn("agent-browser 0.35.0", agent_workflow)
        self.assertIn("hermes-v2026.8.19.patch", agent_workflow)
        self.assertIn("--domain=hermes.michaelbrusegard.com", kvm_device_plugin)
        self.assertIn("path: /dev/kvm", kvm_device_plugin)
        self.assertIn("2cc50b0@sha256:", kvm_device_plugin)
        self.assertIn("class HermesAccessibilityService", accessibility_source)
        self.assertIn('InetAddress.getByName("127.0.0.1")', accessibility_source)
        self.assertIn("LISTEN_PORT = 8765", accessibility_source)
        self.assertIn("MAX_LIVE_SNAPSHOTS = 32", accessibility_source)
        self.assertIn("snapshots.get(treeId)", accessibility_source)
        self.assertIn("ACTION_SET_TEXT", accessibility_source)
        self.assertIn("dispatchGesture", accessibility_source)
        self.assertIn("requireAuthentication", accessibility_source)
        self.assertIn('android:permission="android.permission.DUMP"', accessibility_manifest)
        self.assertIn("class ConfigReceiver", config_receiver_source)
        self.assertIn(
            "HOME=/tmp /android/sdk/platform-tools/adb keygen /opt/android/adb/adbkey",
            statefulset,
        )
        self.assertIn("chown 10000:0 /opt/android/adb/adbkey", statefulset)
        self.assertIn("chmod 640 /opt/android/adb/adbkey", statefulset)
        self.assertIn(
            "securityContext:\n            runAsUser: 0\n            runAsGroup: 0\n            allowPrivilegeEscalation: false",
            statefulset,
        )
        self.assertIn("name: prepare-android", manifest_updater_source)
        self.assertIn(
            r"(?m)^(\s*- name: (?:gateway|android-companion)\n\s*image:)\s*.*$",
            agent_workflow,
        )
        self.assertIn("if agent_replacements != 2:", agent_workflow)


if __name__ == "__main__":
    unittest.main()
