"""Offline contracts for the shared helpers; native delivery has its own proof."""

import unittest
from unittest.mock import Mock, call

import smtp_fixture as fixture


class SharedFixtureTests(unittest.TestCase):
    def test_registry_queries_and_updates_preserve_ids(self):
        client = Mock()
        client.jmap.side_effect = [
            {"ids": ["a"]},
            {"list": [{"id": "a"}]},
            {"updated": ["a"]},
        ]
        self.assertEqual(fixture.objects(client, "Account"), [{"id": "a"}])
        self.assertEqual(
            fixture.change(client, "Account", "a", {"name": "alice"}),
            {"updated": ["a"]},
        )
        self.assertEqual(
            client.jmap.call_args_list,
            [
                call("x:Account/query", {}),
                call("x:Account/get", {"ids": ["a"]}),
                call("x:Account/set", {"update": {"a": {"name": "alice"}}}),
            ],
        )

    def test_email_ids_uses_mail_capability_and_account_scoped_query(self):
        client = Mock()
        client.expect.return_value.document.return_value = {
            "methodResponses": [["Email/query", {"ids": ["message"]}, "mail-fixture"]]
        }
        self.assertEqual(fixture.email_ids(client, "account"), ["message"])
        client.expect.assert_called_once_with(
            "POST",
            "/jmap",
            200,
            {
                "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
                "methodCalls": [
                    ["Email/query", {"accountId": "account"}, "mail-fixture"]
                ],
            },
            auth="recovery",
        )

    def test_email_ids_rejects_failed_or_uncorrelated_responses(self):
        for calls in (
            [],
            [["error", {}, "mail-fixture"]],
            [["Email/query", {}, "wrong-id"]],
        ):
            with self.subTest(calls=calls):
                client = Mock()
                client.expect.return_value.document.return_value = {
                    "methodResponses": calls
                }
                with self.assertRaisesRegex(
                    AssertionError, "Unexpected Email/query response"
                ):
                    fixture.email_ids(client, "account")


if __name__ == "__main__":
    unittest.main()
