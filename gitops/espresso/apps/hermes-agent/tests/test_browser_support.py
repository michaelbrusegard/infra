from __future__ import annotations

import argparse
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


if __name__ == "__main__":
    unittest.main()
