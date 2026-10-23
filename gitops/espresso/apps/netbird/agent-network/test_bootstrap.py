"""Exercise bootstrap against a fake management API; never contact live NetBird."""

import copy
import json
import stat
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError

from bootstrap import NetBird, reconcile


class FakeAPI:
    def __init__(self):
        self.calls = []
        self.groups = [
            {"id": "admins", "name": "Admins"}, {"id": "ai", "name": "AI"},
            {"id": "hermes", "name": "Hermes Egress"},
        ]
        self.settings = {"endpoint": "", "proxy_address": ""}
        self.providers = []
        self.policies = []
        self.tokens = []

    def __call__(self, method, path, body=None):
        self.calls.append((method, path, copy.deepcopy(body)))
        if path == "/groups" and method == "GET":
            return copy.deepcopy(self.groups)
        if path == "/agent-network/settings":
            if method == "POST":
                self.settings = {**body, "proxy_address": body["endpoint"]}
            return copy.deepcopy(self.settings)
        for resource, rows in [
            ("providers", self.providers), ("policies", self.policies),
        ]:
            base = "/agent-network/" + resource
            if path == base and method == "GET":
                return copy.deepcopy(rows)
            if path == base and method == "POST":
                row = {**body, "id": resource + str(len(rows))}
                rows.append(row)
                return copy.deepcopy(row)
            if path.startswith(base + "/") and method == "PUT":
                row = next(row for row in rows if row["id"] == path.rsplit("/", 1)[1])
                row.update(body)
                return copy.deepcopy(row)
        if path == "/reverse-proxies/proxy-tokens":
            if method == "POST":
                self.tokens.append({
                    **body, "id": "token" + str(len(self.tokens)),
                    "plain_token": "test-proxy-secret", "revoked": False,
                })
            return copy.deepcopy(self.tokens[-1] if method == "POST" else self.tokens)
        raise AssertionError(f"Unexpected API call: {method} {path}")


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.token = Path(self.directory.name) / "proxy-token"
        self.config = json.loads(Path(__file__).with_name("config.json").read_text())
        self.api = FakeAPI()

    def run_bootstrap(self):
        reconcile(self.api, self.config, "test-upstream-secret", self.token)

    def assert_no_mutation(self):
        self.assertTrue(all(method == "GET" for method, _, _ in self.api.calls))

    def test_first_boot_and_restart_reuse_resources_without_writes(self):
        self.run_bootstrap()
        self.assertEqual(self.api.settings["endpoint"], self.config["endpoint"])
        self.assertFalse(self.api.settings["enable_prompt_collection"])
        provider = self.api.providers[0]
        self.assertEqual(provider["api_key"], "test-upstream-secret")
        self.assertEqual(provider["models"], [])
        self.assertEqual(self.api.policies[0]["source_groups"], ["ai"])
        self.assertEqual(self.api.policies[1]["name"], "Hermes AI Access")
        self.assertEqual(self.api.policies[1]["source_groups"], ["hermes"])
        self.assertEqual(
            self.api.policies[1]["destination_provider_ids"], [provider["id"]],
        )
        self.assertNotIn("limits", self.api.policies[0])
        self.assertEqual(self.api.policies[2]["name"], "Admin AI Access")
        self.assertEqual(self.api.policies[2]["source_groups"], ["admins"])
        self.assertNotIn("limits", self.api.policies[2])
        self.assertEqual(self.api.policies[2]["guardrail_ids"], [])
        self.assertEqual(stat.S_IMODE(self.token.stat().st_mode), 0o600)
        self.assertNotIn("test-upstream-secret", self.token.read_text())
        self.api.calls.clear()
        self.run_bootstrap()
        self.assertEqual(len(self.api.providers), 1)
        self.assertEqual(len(self.api.policies), 3)
        self.assertEqual(len(self.api.tokens), 1)
        self.assert_no_mutation()

    def test_missing_group_waits_without_changing_account(self):
        self.api.groups.pop()
        with self.assertRaisesRegex(RuntimeError, "Waiting for OpenTofu"):
            self.run_bootstrap()
        self.assert_no_mutation()

    def test_dashboard_controls_and_disabled_access_survive_restart(self):
        self.run_bootstrap()
        self.api.providers[0].update({
            "models": [{"id": "restricted-model", "input_per_1k": 0, "output_per_1k": 0}],
            "enabled": False,
        })
        self.api.policies[0].update({
            "enabled": False,
            "guardrail_ids": ["guardrail1"],
            "limits": {"token_limit": {"enabled": True, "user_cap": 1000}},
        })
        self.api.policies[1].update({
            "enabled": False,
            "guardrail_ids": ["hermes-guardrail"],
            "limits": {"token_limit": {"enabled": True, "group_cap": 2000}},
        })
        before = copy.deepcopy((self.api.providers, self.api.policies))
        self.api.calls.clear()
        self.run_bootstrap()
        self.assertEqual((self.api.providers, self.api.policies), before)
        self.assert_no_mutation()

    def test_add_missing_policies_without_resetting_existing_human_policy(self):
        self.config["policies"] = self.config["policies"][:1]
        self.run_bootstrap()
        self.api.policies[0].update({"enabled": False, "guardrail_ids": ["human-only"]})
        human_policy = copy.deepcopy(self.api.policies[0])
        self.config = json.loads(Path(__file__).with_name("config.json").read_text())
        self.api.calls.clear()
        self.run_bootstrap()
        self.assertEqual(self.api.policies[0], human_policy)
        self.assertEqual(self.api.policies[1]["source_groups"], ["hermes"])
        self.assertEqual(self.api.policies[2]["source_groups"], ["admins"])
        self.assertEqual(
            [(method, path) for method, path, _ in self.api.calls if method != "GET"],
            [("POST", "/agent-network/policies"), ("POST", "/agent-network/policies")],
        )

    def test_key_rotation_preserves_provider_settings_and_policy(self):
        self.run_bootstrap()
        self.api.providers[0].update({
            "enabled": False, "models": [{"id": "restricted-model"}],
            "extra_values": {"config_id": "gateway-config"},
            "identity_header_user_id": "x-user",
        })
        before = copy.deepcopy((self.api.providers[0], self.api.policies))
        self.api.calls.clear()
        reconcile(self.api, self.config, "rotated-upstream-secret", self.token)
        expected = {**before[0], "api_key": "rotated-upstream-secret"}
        self.assertEqual(self.api.providers[0], expected)
        self.assertEqual(self.api.policies, before[1])
        self.assertEqual(
            [(method, path) for method, path, _ in self.api.calls if method != "GET"],
            [("PUT", "/agent-network/providers/providers0")],
        )

    def test_changed_upstream_never_receives_credentials(self):
        self.run_bootstrap()
        self.api.providers[0]["upstream_url"] = "https://other.example.test"
        self.api.calls.clear()
        with self.assertRaisesRegex(RuntimeError, "refusing to send credentials"):
            self.run_bootstrap()
        self.assert_no_mutation()

    def test_existing_endpoint_is_never_replaced(self):
        self.api.settings = {"endpoint": "other.example.test", "proxy_address": "other.example.test"}
        with self.assertRaisesRegex(RuntimeError, "refusing to replace"):
            self.run_bootstrap()
        self.assert_no_mutation()

    def test_management_errors_do_not_expose_credential_payloads(self):
        api = NetBird("http://management.test/api", "test-management-secret")
        with patch("bootstrap.urlopen", side_effect=HTTPError(
            "http://management.test/api/agent-network/providers", 400,
            "test-upstream-secret", {}, None,
        )):
            with self.assertRaises(RuntimeError) as caught:
                api("POST", "/agent-network/providers", {"api_key": "test-upstream-secret"})
        self.assertEqual(str(caught.exception), "NetBird POST /agent-network/providers: HTTP 400")

    def test_revoked_and_expired_registrations_are_recreated(self):
        self.run_bootstrap()
        self.api.tokens[-1]["revoked"] = True
        self.run_bootstrap()
        self.assertEqual(len(self.api.tokens), 2)
        self.api.tokens[-1]["expires_at"] = "2000-01-01T00:00:00Z"
        self.run_bootstrap()
        self.assertEqual(len(self.api.tokens), 3)
        self.assertEqual(self.token.read_text().splitlines()[1], "token2")

    def test_truncated_registration_is_recreated_without_resetting_controls(self):
        self.run_bootstrap()
        self.api.policies[0]["enabled"] = False
        self.token.write_text("truncated-registration\n")
        self.api.calls.clear()
        self.run_bootstrap()
        self.assertEqual(len(self.api.tokens), 2)
        self.assertEqual(self.token.read_text().splitlines()[1], "token1")
        self.assertEqual(stat.S_IMODE(self.token.stat().st_mode), 0o600)
        self.assertFalse(self.api.policies[0]["enabled"])
        self.assertEqual(
            [(method, path) for method, path, _ in self.api.calls if method != "GET"],
            [("POST", "/reverse-proxies/proxy-tokens")],
        )


if __name__ == "__main__":
    unittest.main()
