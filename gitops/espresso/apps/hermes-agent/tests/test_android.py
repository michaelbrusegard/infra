from __future__ import annotations

import argparse
import base64
import importlib.util
import json
import os
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
COMPANION_SPEC = importlib.util.spec_from_file_location(
    "hermes_android_companion", COMPANION_PATH
)
assert COMPANION_SPEC and COMPANION_SPEC.loader
companion = importlib.util.module_from_spec(COMPANION_SPEC)
COMPANION_SPEC.loader.exec_module(companion)


def image_pipeline(name):
    """Return an image's workflow together with the smoke test it runs."""
    root = APP_ROOT.parents[3]
    workflow = (root / ".github" / "workflows" / f"{name}.yaml").read_text(
        encoding="utf-8"
    )
    smoke_test = root / "packages" / name / "smoke-test.sh"
    assert f"run: packages/{name}/smoke-test.sh" in workflow
    return workflow + smoke_test.read_text(encoding="utf-8")


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
            "ANDROID_COMPANION_TOKEN_FILE": os.environ.get(
                "ANDROID_COMPANION_TOKEN_FILE"
            ),
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
            with (
                mock.patch.object(
                    companion.android,
                    "current_ui_tree",
                    return_value={"backend": "accessibility-service", "nodes": []},
                ),
                urllib.request.urlopen(request, timeout=2) as response,
            ):
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
                mock.patch.object(
                    companion, "launcher_status", return_value={"state": "disabled"}
                ),
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
        self.assertEqual(
            android.encode_input_text("  hello  android world "),
            "hello%sandroid%sworld",
        )
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
        destination = android.resolve_output_path(
            None, "192.168.1.4:5555", "screenshots", ".png"
        )

        self.assertTrue(destination.is_relative_to(self.browser_files))
        self.assertEqual(destination.suffix, ".png")
        self.assertIn("192.168.1.4_5555", str(destination))

    def test_resolve_output_path_creates_any_visible_parent(self) -> None:
        destination = Path(self.tempdir.name) / "outside" / "captures" / "screen.png"

        resolved = android.resolve_output_path(
            str(destination), "serial", "screenshots", ".png"
        )

        self.assertEqual(resolved, destination.resolve())
        self.assertTrue(destination.parent.is_dir())

    def test_parse_wm_size_extracts_dimensions(self) -> None:
        self.assertEqual(
            android.parse_wm_size("Physical size: 1080x2400"),
            {"width": 1080, "height": 2400},
        )
        self.assertIsNone(android.parse_wm_size("garbage"))

    def test_live_view_uses_env_overrides(self) -> None:
        os.environ["ANDROID_VIEW_URL"] = "http://127.0.0.1:6080/vnc.html"
        os.environ["ANDROID_COMPANION_URL"] = "http://127.0.0.1:8777"
        self.assertEqual(
            android.live_view("127.0.0.1:5555"),
            {
                "serial": "127.0.0.1:5555",
                "adb_endpoint": "127.0.0.1:5555",
                "viewer_url": "http://127.0.0.1:6080/vnc.html",
                "companion_url": "http://127.0.0.1:8777",
            },
        )

    @mock.patch.object(android, "run_adb", return_value=b"adb-png")
    @mock.patch.object(
        android, "require_connected_serial", return_value="127.0.0.1:5555"
    )
    def test_screenshot_uses_adb(
        self,
        _require_serial: mock.Mock,
        run_adb: mock.Mock,
    ) -> None:
        destination = Path(self.tempdir.name) / "fallback.png"

        result = android.handle_screenshot(argparse.Namespace(path=str(destination)))

        self.assertEqual(destination.read_bytes(), b"adb-png")
        self.assertEqual(result["source"], "adb-screencap")
        self.assertFalse(result["secure_windows_visible"])
        run_adb.assert_called_once_with(
            "127.0.0.1:5555",
            "exec-out",
            "screencap",
            "-p",
            text=False,
            timeout=120,
        )

    @mock.patch.object(android, "run_adb")
    def test_clipboard_round_trips_unicode_through_the_device_helper(
        self, run_adb: mock.Mock
    ) -> None:
        text = "hei på deg ✓"
        encoded = base64.b64encode(text.encode("utf-8")).decode("ascii")
        run_adb.side_effect = ["", encoded + "\n"]

        self.assertEqual(
            android.set_clipboard_text("127.0.0.1:5555", text), {"text": text}
        )

        self.assertEqual(run_adb.call_args_list[0].args[-2:], ("set", encoded))
        self.assertEqual(run_adb.call_args_list[1].args[-1], "get")

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
    def test_accessibility_request_authenticates_over_adb_shell(
        self, run_adb: mock.Mock
    ) -> None:
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

    @mock.patch.object(
        android, "set_clipboard_text", side_effect=RuntimeError("gRPC unavailable")
    )
    @mock.patch.object(
        android,
        "accessibility_snapshot",
        side_effect=RuntimeError("service unavailable"),
    )
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

        run_adb.assert_called_once_with(
            "serial", "shell", "input", "text", "hello%sworld"
        )
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

    @mock.patch.object(
        android, "shell_text", return_value="package:/data/app/aurora/base.apk"
    )
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
    def test_ensure_device_connection_connects_missing_tcp_endpoints(
        self, run_adb: mock.Mock
    ) -> None:
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
        screenshot = (
            self.browser_files
            / "android"
            / "127.0.0.1_5555"
            / "snapshots"
            / "checkout.png"
        )
        ui_dump = (
            self.browser_files
            / "android"
            / "127.0.0.1_5555"
            / "snapshots"
            / "checkout.xml"
        )
        screenshot.parent.mkdir(parents=True, exist_ok=True)
        screenshot.write_bytes(b"png")
        ui_dump.write_text("<hierarchy/>", encoding="utf-8")
        handle_screenshot.return_value = {"path": str(screenshot)}
        handle_ui_dump.return_value = {"path": str(ui_dump)}
        health_report.return_value = {"boot_completed": True}

        result = android.handle_snapshot(
            argparse.Namespace(serial=serial, name="checkout")
        )

        metadata = Path(result["metadata_path"])
        self.assertTrue(metadata.is_file())
        payload = json.loads(metadata.read_text(encoding="utf-8"))
        self.assertEqual(payload["serial"], serial)
        self.assertEqual(payload["screenshot"], str(screenshot))
        self.assertEqual(payload["ui_dump"], str(ui_dump))
        self.assertEqual(payload["health"], {"boot_completed": True})

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
            APP_ROOT.parents[3]
            / "modules"
            / "hosts"
            / "espresso"
            / "seccomp-profiles.nix"
        ).read_text(encoding="utf-8")
        k3s_module = (
            APP_ROOT.parents[3] / "modules" / "features" / "k3s.nix"
        ).read_text(encoding="utf-8")
        image_workflow = image_pipeline("hermes-agent-image")
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
            "        - name: android\n", 1
        )[0]

        self.assertNotIn("--no-sandbox", browser_image)
        self.assertEqual(browser_image.count("--disable-setuid-sandbox"), 1)
        self.assertNotIn("--no-sandbox", browser)
        self.assertIn("allowPrivilegeEscalation: false", browser)
        self.assertIn(
            'Names:  []string{"chroot", "clone", "unshare"}', seccomp_generator
        )
        self.assertIn("chromium-seccomp-profile", seccomp_install)
        self.assertNotIn("chromium", k3s_module)
        self.assertIn("nix build --out-link result-chromium-seccomp ", image_workflow)
        self.assertIn(
            '--security-opt "seccomp=$chromium_seccomp_profile"', image_workflow
        )
        self.assertIn("kernel.apparmor_restrict_unprivileged_userns=0", image_workflow)
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


if __name__ == "__main__":
    unittest.main()
