from __future__ import annotations

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[5] / "packages" / "hermes-agent-image" / "browser_session_router.py"
SPEC = importlib.util.spec_from_file_location("hermes_browser_session_router", SCRIPT_PATH)
assert SPEC and SPEC.loader
browser_session_router = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(browser_session_router)


class BrowserSessionRouterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.browser_files = Path(self.tempdir.name) / "opt" / "browser-files"
        self.browser_files.mkdir(parents=True)
        self.previous = {
            "BROWSER_FILES_ROOT": os.environ.get("BROWSER_FILES_ROOT"),
        }
        os.environ["BROWSER_FILES_ROOT"] = str(self.browser_files)

    def tearDown(self) -> None:
        for key, value in self.previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        self.tempdir.cleanup()

    def test_persist_session_writes_atomic_metadata(self) -> None:
        session = {
            "shared_profile_session": True,
            "cdp_url": "http://127.0.0.1:9222",
            "root_target_id": "root-target",
            "active_target_id": "active-target",
            "owned_target_ids": ["root-target", "active-target"],
        }

        browser_session_router.persist_session("task/with spaces", session)

        metadata = self.browser_files / "browser-sessions" / "task_with_spaces.json"
        self.assertTrue(metadata.is_file())
        payload = json.loads(metadata.read_text(encoding="utf-8"))
        self.assertEqual(payload["task_id"], "task/with spaces")
        self.assertEqual(payload["active_target_id"], "active-target")
        self.assertEqual(payload["owned_target_ids"], ["root-target", "active-target"])
        self.assertIn("updated_at", payload)

    def test_remove_persisted_session_deletes_metadata(self) -> None:
        metadata = self.browser_files / "browser-sessions" / "task.json"
        metadata.parent.mkdir(parents=True, exist_ok=True)
        metadata.write_text("{}", encoding="utf-8")

        browser_session_router.remove_persisted_session("task")

        self.assertFalse(metadata.exists())


if __name__ == "__main__":
    unittest.main()
