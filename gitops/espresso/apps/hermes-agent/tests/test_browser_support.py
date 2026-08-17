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


if __name__ == "__main__":
    unittest.main()
