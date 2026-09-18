"""Offline readiness checks; native execution is qualified separately."""

import unittest
from unittest.mock import MagicMock, patch

import readiness


class ReadinessTests(unittest.TestCase):
    def test_expression_preserves_sql_and_rejects_changed_match(self):
        readiness.expression({"else": "false", "match": {"0": {
            "if": "domain", "then": "SELECT\n1"}}}, "false", [("domain", "SELECT\n1")])
        with self.assertRaises(RuntimeError):
            readiness.expression({"else": "true"}, "false")
        with self.assertRaises(RuntimeError):
            readiness.expression({"else": "false", "match": [{"if": "x", "then": "true"}]}, "false")

    def test_empty_match_representations(self):
        for value in (None, {}, []):
            readiness.expression({"else": "false", "match": value}, "false")

    def test_readiness_permissions_are_read_only(self):
        self.assertEqual(len(readiness.READINESS_PERMISSIONS), len(set(readiness.READINESS_PERMISSIONS)))
        for permission in readiness.READINESS_PERMISSIONS:
            self.assertTrue(permission == "authenticate" or permission.endswith(("Get", "Query")))

    def test_native_key_sets_do_not_include_disabled_entries(self):
        self.assertEqual(readiness.enabled_keys({"rcpt": True, "data": False}), {"rcpt"})

    def test_smtp_probe_never_submits_data(self):
        for reply in (550, 250):
            with self.subTest(reply=reply), patch.object(readiness.smtplib, "SMTP") as smtp:
                conn = MagicMock()
                smtp.return_value.__enter__.return_value = conn
                conn.ehlo.return_value = (250, b"ok")
                conn.has_extn.side_effect = lambda extension: extension == "starttls"
                conn.starttls.return_value = (220, b"ready")
                conn.mail.return_value = (250, b"ok")
                conn.rcpt.return_value = (reply, b"response")
                if reply == 550:
                    readiness.check_smtp()
                    self.assertEqual(conn.rcpt.call_count, 3)
                else:
                    with self.assertRaises(RuntimeError):
                        readiness.check_smtp()
                conn.data.assert_not_called()
                conn.sendmail.assert_not_called()
                self.assertEqual(conn._host, readiness.HOST)


if __name__ == "__main__":
    unittest.main()
