from __future__ import annotations

import argparse
import base64
import importlib.util
import json
import os
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "browser-support.py"
SPEC = importlib.util.spec_from_file_location("hermes_browser_support", SCRIPT_PATH)
assert SPEC and SPEC.loader
browser_support = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(browser_support)


class BrowserSupportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        root = Path(self.tempdir.name)
        self.hermes_home = root / "opt" / "data"
        self.browser_files = root / "opt" / "browser-files"
        self.browser_profile = root / "opt" / "browser"
        (self.hermes_home / "workspace").mkdir(parents=True)
        (self.hermes_home / "cache").mkdir(parents=True)
        (self.browser_files / "browser-checkpoints").mkdir(parents=True)
        (self.browser_profile / "profile").mkdir(parents=True)
        (self.browser_profile / "profile" / "Preferences").write_text("{}", encoding="utf-8")
        self.previous = {
            "HERMES_HOME": os.environ.get("HERMES_HOME"),
            "BROWSER_FILES_ROOT": os.environ.get("BROWSER_FILES_ROOT"),
            "BROWSER_PROFILE_ROOT": os.environ.get("BROWSER_PROFILE_ROOT"),
        }
        os.environ["HERMES_HOME"] = str(self.hermes_home)
        os.environ["BROWSER_FILES_ROOT"] = str(self.browser_files)
        os.environ["BROWSER_PROFILE_ROOT"] = str(self.browser_profile)

    def tearDown(self) -> None:
        for key, value in self.previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        self.tempdir.cleanup()

    def test_build_challenge_summary_flags_verification_without_guarantees(self) -> None:
        summary = browser_support.build_challenge_summary(
            {
                "title": "Just a moment...",
                "url": "https://example.com/login",
                "body_text": "Checking your browser before accessing example.com",
                "frames": [{"src": "https://challenges.cloudflare.com/turnstile"}],
            }
        )

        self.assertTrue(summary["challenge_detected"])
        self.assertIn("checking_browser", summary["signals"])
        self.assertIn("Do not claim the challenge is solved", " ".join(summary["recommended_actions"]))

    def test_resolve_output_path_defaults_under_browser_files(self) -> None:
        destination = browser_support.resolve_output_path(None, "browser-checkpoints", ".json")

        self.assertTrue(destination.is_relative_to(self.browser_files))
        self.assertEqual(destination.suffix, ".json")

    def test_resolve_target_id_uses_persisted_task_session(self) -> None:
        payload = {
            "task_id": "shopping-task",
            "active_target_id": "target-123",
            "owned_target_ids": ["target-123"],
        }
        metadata = self.browser_files / "browser-sessions" / "shopping-task.json"
        metadata.parent.mkdir(parents=True, exist_ok=True)
        metadata.write_text(json.dumps(payload), encoding="utf-8")

        resolved = browser_support.resolve_target_id(None, "shopping-task")

        self.assertEqual(resolved, "target-123")

    def test_challenge_progress_reports_possible_recovery_without_guarantees(self) -> None:
        progress = browser_support.challenge_progress(
            {
                "title": "Just a moment...",
                "url": "https://example.com/login",
                "body_text": "Checking your browser before accessing example.com",
                "frames": [{"src": "https://challenges.cloudflare.com/turnstile"}],
            },
            {
                "title": "Example Login",
                "url": "https://example.com/login",
                "body_text": "Welcome back",
                "frames": [],
            },
        )

        self.assertTrue(progress["possible_progress"])
        self.assertIn("Challenge markers dropped", " ".join(progress["notes"]))

    def test_verify_page_state_matches_checkpoint_without_false_guarantees(self) -> None:
        verification = browser_support.verify_page_state(
            {
                "title": "Example Checkout",
                "url": "https://shop.example/checkout?step=shipping",
                "body_text": "Shipping address\nDelivery options\nPlace order",
                "frames": [],
            },
            expected_page={
                "title": "Example Checkout",
                "url": "https://shop.example/checkout?step=shipping",
                "body_text": "Shipping address\nDelivery options\nPlace order",
                "frames": [],
            },
            forbidden_signals=["captcha", "verification"],
        )

        self.assertTrue(verification["matched"])
        self.assertEqual(verification["confidence"], "high")
        self.assertFalse(verification["warnings"])
        self.assertIn("signal 'captcha' is absent", verification["evidence"])

    def test_verify_page_state_stays_conservative_when_challenge_remains(self) -> None:
        verification = browser_support.verify_page_state(
            {
                "title": "Example Checkout",
                "url": "https://shop.example/checkout",
                "body_text": "Verify you are human before continuing",
                "frames": [{"src": "https://challenges.cloudflare.com/turnstile"}],
            },
            expected_page={
                "title": "Example Checkout",
                "url": "https://shop.example/checkout",
                "body_text": "Shipping address\nDelivery options\nPlace order",
                "frames": [],
            },
            forbidden_signals=["verification"],
        )

        self.assertFalse(verification["matched"])
        self.assertEqual(verification["confidence"], "low")
        self.assertTrue(verification["challenge"]["challenge_detected"])
        self.assertIn("Challenge markers are still present", " ".join(verification["warnings"]))

    def test_profile_backup_writes_tarball(self) -> None:
        result = browser_support.handle_profile_backup(argparse.Namespace(name=None))

        archive = Path(result["path"])
        self.assertTrue(archive.is_file())
        with tarfile.open(archive, "r:gz") as bundle:
            self.assertIn("profile/Preferences", bundle.getnames())

    def test_checkpoint_list_reads_saved_metadata(self) -> None:
        payload = {"name": "cart-ready", "page": {"url": "https://shop.example"}}
        metadata = self.browser_files / "browser-checkpoints" / "cart-ready.json"
        metadata.write_text(json.dumps(payload), encoding="utf-8")

        result = browser_support.handle_checkpoint_list(mock.Mock())

        self.assertEqual(result["checkpoints"], [payload])

    @mock.patch.object(browser_support, "collect_page_state")
    @mock.patch.object(browser_support, "CDPClient")
    def test_verify_page_uses_checkpoint_expectations(
        self,
        client_cls: mock.Mock,
        collect_page_state: mock.Mock,
    ) -> None:
        del client_cls
        payload = {
            "name": "cart-ready",
            "page": {
                "title": "Example Cart",
                "url": "https://shop.example/cart",
                "body_text": "Cart summary\nSubtotal",
                "frames": [],
            },
        }
        metadata = self.browser_files / "browser-checkpoints" / "cart-ready.json"
        metadata.write_text(json.dumps(payload), encoding="utf-8")
        collect_page_state.return_value = payload["page"]

        result = browser_support.handle_verify_page(
            argparse.Namespace(
                cdp_url="http://127.0.0.1:9222",
                target_id="target-1",
                task_id=None,
                expected="cart-ready",
                url_substring=None,
                title_substring=None,
                body_substring=None,
                without_signal=["captcha"],
            )
        )

        self.assertTrue(result["verification"]["matched"])
        self.assertEqual(result["expected_page"]["title"], "Example Cart")

    def test_session_events_reads_task_history(self) -> None:
        events = self.browser_files / "browser-session-events" / "shopping-task.jsonl"
        events.parent.mkdir(parents=True, exist_ok=True)
        events.write_text(
            "\n".join(
                [
                    json.dumps({"event": "command.started", "task_id": "shopping-task"}),
                    json.dumps({"event": "command.completed", "task_id": "shopping-task"}),
                ]
            )
            + "\n",
            encoding="utf-8",
        )

        result = browser_support.handle_session_events(
            argparse.Namespace(task_id="shopping-task", limit=10)
        )

        self.assertEqual(
            [item["event"] for item in result["events"]],
            ["command.started", "command.completed"],
        )

    def test_cleanup_prunes_old_files(self) -> None:
        target = self.browser_files / "browser-checkpoints" / "old.json"
        target.write_text("{}", encoding="utf-8")
        old_mtime = 1_600_000_000
        os.utime(target, (old_mtime, old_mtime))

        result = browser_support.handle_cleanup(
            argparse.Namespace(bucket="browser-checkpoints", older_than_hours=1.0)
        )

        self.assertIn(str(target), result["removed"])
        self.assertFalse(target.exists())

    def test_cleanup_prunes_task_artifacts_and_session_metadata(self) -> None:
        session = self.browser_files / "browser-sessions" / "task.json"
        artifact = self.browser_files / "task" / "downloads" / "old.txt"
        session.parent.mkdir(parents=True, exist_ok=True)
        artifact.parent.mkdir(parents=True, exist_ok=True)
        session.write_text("{}", encoding="utf-8")
        artifact.write_text("old", encoding="utf-8")
        old_mtime = 1_600_000_000
        os.utime(session, (old_mtime, old_mtime))
        os.utime(artifact, (old_mtime, old_mtime))

        result = browser_support.handle_cleanup(
            argparse.Namespace(bucket="all", older_than_hours=1.0)
        )

        self.assertIn(str(session), result["removed"])
        self.assertIn(str(artifact), result["removed"])

    @mock.patch.object(browser_support, "resolve_target")
    @mock.patch.object(browser_support, "CDPClient")
    def test_click_dispatches_atomic_mouse_sequence(
        self,
        client_cls: mock.Mock,
        resolve_target: mock.Mock,
    ) -> None:
        fake_client = mock.Mock()
        client_cls.return_value = fake_client
        fake_target = browser_support.Target("target-1", "Title", "https://example.com", "page", "ws://target")
        resolve_target.return_value = ("target-1", fake_target)

        result = browser_support.handle_click(
            argparse.Namespace(
                cdp_url="http://127.0.0.1:9222",
                target_id="target-1",
                task_id=None,
                x=120,
                y=340,
                button="left",
                click_count=1,
            )
        )

        self.assertEqual(result["click"], {"x": 120, "y": 340, "button": "left", "click_count": 1})
        self.assertEqual(
            [call.args[1] for call in fake_client.call.call_args_list],
            ["Input.dispatchMouseEvent", "Input.dispatchMouseEvent", "Input.dispatchMouseEvent"],
        )

    @mock.patch.object(browser_support, "resolve_target")
    @mock.patch.object(browser_support, "CDPClient")
    def test_touch_swipe_dispatches_interpolated_events(
        self,
        client_cls: mock.Mock,
        resolve_target: mock.Mock,
    ) -> None:
        fake_client = mock.Mock()
        client_cls.return_value = fake_client
        fake_target = browser_support.Target("target-1", "Title", "https://example.com", "page", "ws://target")
        resolve_target.return_value = ("target-1", fake_target)

        result = browser_support.handle_touch_swipe(
            argparse.Namespace(
                cdp_url="http://127.0.0.1:9222",
                target_id="target-1",
                task_id=None,
                x1=10,
                y1=20,
                x2=110,
                y2=220,
                steps=4,
            )
        )

        self.assertEqual(result["swipe"]["steps"], 4)
        self.assertEqual(len(fake_client.call.call_args_list), 6)

    @mock.patch.object(browser_support, "resolve_target")
    @mock.patch.object(browser_support, "CDPClient")
    def test_drag_dispatches_press_move_release_sequence(
        self,
        client_cls: mock.Mock,
        resolve_target: mock.Mock,
    ) -> None:
        fake_client = mock.Mock()
        client_cls.return_value = fake_client
        fake_target = browser_support.Target("target-1", "Title", "https://example.com", "page", "ws://target")
        resolve_target.return_value = ("target-1", fake_target)

        result = browser_support.handle_drag(
            argparse.Namespace(
                cdp_url="http://127.0.0.1:9222",
                target_id="target-1",
                task_id=None,
                x1=1,
                y1=2,
                x2=51,
                y2=62,
                steps=3,
            )
        )

        self.assertEqual(result["drag"]["steps"], 3)
        self.assertEqual(len(fake_client.call.call_args_list), 6)

    @mock.patch.object(browser_support.time, "sleep")
    @mock.patch.object(browser_support.subprocess, "run")
    @mock.patch.object(browser_support, "resolve_target")
    @mock.patch.object(browser_support, "CDPClient")
    def test_record_page_captures_frames_and_writes_video(
        self,
        client_cls: mock.Mock,
        resolve_target: mock.Mock,
        run: mock.Mock,
        sleep: mock.Mock,
    ) -> None:
        del sleep
        destination = self.browser_files / "browser-recordings" / "clip.webm"
        destination.parent.mkdir(parents=True, exist_ok=True)
        fake_client = mock.Mock()
        fake_client.call.return_value = {"data": base64.b64encode(b"fake-png").decode("ascii")}
        client_cls.return_value = fake_client
        fake_target = browser_support.Target("target-1", "Title", "https://example.com", "page", "ws://target")
        resolve_target.return_value = ("target-1", fake_target)

        def write_destination(*_args: object, **_kwargs: object) -> mock.Mock:
            destination.write_bytes(b"webm")
            return mock.Mock()

        run.side_effect = write_destination

        with mock.patch.object(browser_support, "resolve_output_path", return_value=destination):
            result = browser_support.handle_record_page(
                argparse.Namespace(
                    cdp_url="http://127.0.0.1:9222",
                    target_id="target-1",
                    task_id=None,
                    seconds=1.0,
                    fps=2,
                    path=str(destination),
                )
            )

        self.assertEqual(result["path"], str(destination))
        self.assertEqual(result["frames"], 2)
        self.assertEqual(result["fps"], 2)
        self.assertEqual(fake_client.call.call_count, 2)

    @mock.patch.object(browser_support, "CDPClient")
    def test_diagnostics_reads_supervisor_status(self, client_cls: mock.Mock) -> None:
        fake_client = mock.Mock()
        fake_client.version.return_value = {"Browser": "Chromium"}
        fake_client.targets.return_value = []
        client_cls.return_value = fake_client
        supervisor = self.browser_files / "browser-supervisor" / "status.json"
        supervisor.parent.mkdir(parents=True, exist_ok=True)
        supervisor.write_text(json.dumps({"state": "running", "restart_count": 1}), encoding="utf-8")

        result = browser_support.handle_diagnostics(
            argparse.Namespace(cdp_url="http://127.0.0.1:9222")
        )

        self.assertEqual(result["supervisor"], {"state": "running", "restart_count": 1})


if __name__ == "__main__":
    unittest.main()
