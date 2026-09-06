"""Test the patched spawn path without constructing agents or calling providers."""

from __future__ import annotations

import json
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from tools import delegate_tool


class DelegationProfileSpawnTests(unittest.TestCase):
    def setUp(self):
        self.config = {
            "provider": "fixture-provider",
            "model": "fixture-default",
            "default_profile": "operator",
            "profiles": {
                "operator": {"model": "fixture-operator", "reasoning_effort": "high"},
                "researcher": {"model": "fixture-researcher", "reasoning_effort": False},
            },
        }
        self.parent = SimpleNamespace(_delegate_depth=0, session_id="fixture-parent")
        for name, value in {
            "_load_config": self.config,
            "is_spawn_paused": False,
            "_get_max_spawn_depth": 2,
            "_get_max_concurrent_children": 4,
            "_get_max_async_children": 4,
            "_capture_gateway_steer_authority": (None, None),
        }.items():
            self.enterContext(patch.object(delegate_tool, name, return_value=value))
        self.enterContext(patch("tools.async_delegation._current_origin_session_id", return_value=""))
        self.enterContext(patch("gateway.session_context.get_session_env", return_value=""))
        self.enterContext(patch("gateway.session_context.async_delivery_supported", return_value=True))
        self.enterContext(patch("tools.approval.get_current_session_key", return_value="fixture-session"))
        self.resolve = self.enterContext(patch.object(
            delegate_tool, "_resolve_delegation_credentials", side_effect=self.resolve_fixture
        ))
        self.build = self.enterContext(patch.object(
            delegate_tool, "_build_child_preserving_parent_tools",
            side_effect=lambda **kwargs: SimpleNamespace(),
        ))
        self.enterContext(patch.object(
            delegate_tool, "_run_single_child", side_effect=AssertionError("Must not run a child")
        ))
        self.transcripts = self.enterContext(patch(
            "tools.delegation_live_log.create_live_transcripts", return_value=(None, [], [])
        ))
        self.dispatch = self.enterContext(patch(
            "tools.async_delegation.dispatch_async_delegation_batch",
            return_value={"status": "dispatched", "delegation_id": "fixture-delegation"},
        ))

    @staticmethod
    def resolve_fixture(config, parent):
        return {
            "model": config.get("model"),
            "provider": config.get("provider"),
            "base_url": None,
            "api_key": None,
            "api_mode": None,
        }

    def spawn(self, **kwargs):
        result = json.loads(delegate_tool.delegate_task(
            parent_agent=self.parent, background=True, **kwargs
        ))
        self.assertEqual(result.get("status"), "dispatched", result)
        return result

    def assert_metadata(self, model, provider):
        self.assertEqual(self.transcripts.call_args.kwargs["model"], model)
        self.assertEqual(self.transcripts.call_args.kwargs["provider"], provider)
        self.assertEqual(self.dispatch.call_args.kwargs["model"], model)

    def test_default_profile_reaches_dispatch(self):
        self.spawn(goal="Inspect fixture alpha for syntax errors")
        self.assert_metadata("fixture-operator", "fixture-provider")
        self.assertEqual(self.build.call_args.kwargs["model"], "fixture-operator")
        self.assertEqual(self.build.call_args.kwargs["override_reasoning_effort"], "high")

    def test_explicit_profile_reaches_dispatch(self):
        self.spawn(goal="Inspect fixture alpha for syntax errors", profile="researcher")
        self.assert_metadata("fixture-researcher", "fixture-provider")
        self.assertIs(self.build.call_args.kwargs["override_reasoning_effort"], False)

    def test_uniform_batch_retains_concrete_metadata(self):
        self.spawn(tasks=[
            {"goal": "Inspect fixture alpha for syntax errors"},
            {"goal": "Inspect fixture beta for naming errors"},
        ])
        self.assert_metadata("fixture-operator", "fixture-provider")
        self.assertEqual(self.build.call_count, 2)

    def test_mixed_models_keep_per_task_routes(self):
        self.spawn(profile="operator", tasks=[
            {"goal": "Inspect fixture alpha for syntax errors"},
            {"goal": "Inspect fixture beta for naming errors", "profile": "researcher"},
        ])
        self.assert_metadata("mixed-profiles", "fixture-provider")
        self.assertEqual(
            [call.kwargs["model"] for call in self.build.call_args_list],
            ["fixture-operator", "fixture-researcher"],
        )

    def test_mixed_providers_do_not_label_the_batch_as_one_provider(self):
        self.config["profiles"]["researcher"]["provider"] = "fixture-other-provider"
        self.spawn(tasks=[
            {"goal": "Inspect fixture alpha for syntax errors"},
            {"goal": "Inspect fixture beta for naming errors", "profile": "researcher"},
        ])
        self.assert_metadata("mixed-profiles", "mixed-profiles")
        self.assertEqual(
            [call.kwargs["override_provider"] for call in self.build.call_args_list],
            ["fixture-provider", "fixture-other-provider"],
        )

    def test_legacy_config_preserves_parent_inheritance(self):
        self.config.clear()
        self.spawn(goal="Inspect fixture alpha for syntax errors")
        self.assert_metadata(None, None)
        self.assertIsNone(self.build.call_args.kwargs["model"])

    def test_invalid_profile_fails_before_transcripts_or_children(self):
        result = delegate_tool.delegate_task(parent_agent=self.parent, tasks=[
            {"goal": "Inspect fixture alpha for syntax errors"},
            {"goal": "Inspect fixture beta for naming errors", "profile": "unknown"},
        ])
        self.assertIn("Unknown delegation profile", result)
        self.transcripts.assert_not_called()
        self.build.assert_not_called()
        self.dispatch.assert_not_called()


if __name__ == "__main__":
    unittest.main()
