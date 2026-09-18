"""Offline transport contracts; native qualification separately proves delivery."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


class DeliveryTests(unittest.TestCase):
    def invoke(self, *, ip="192.0.2.10", helo="sender.example", sender="sender@example.com",
               recipient="alice@manafishrov.com", status=0, reply="250"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            capture = root / "capture.json"
            fake = root / "curl"
            fake.write_text(f"#!{sys.executable}\n" + """import json, os, sys
with open(os.environ['CAPTURE'], 'w') as stream:
    json.dump({'args': sys.argv[1:], 'body': sys.stdin.buffer.read().hex()}, stream)
sys.stdout.write(os.environ['REPLY'])
sys.exit(int(os.environ['STATUS']))
""")
            fake.chmod(0o700)
            body = b"Subject: synthetic\r\n\r\n.leading\r\n--mail-rcpt evil.invalid\r\n"
            result = subprocess.run(
                ["bash", str(HERE / "deliver.sh"), "backend.example", "25", "26", "/trusted/ca",
                 ip, helo, sender, recipient], input=body, capture_output=True,
                env={"PATH": str(root) + ":" + os.environ["PATH"], "CAPTURE": str(capture),
                     "STATUS": str(status), "REPLY": reply}, timeout=5)
            record = json.loads(capture.read_text()) if capture.exists() else None
            if record is not None:
                self.assertEqual(record["body"], body.hex())
            return result, record

    def test_forward_native_context_without_reading_or_rewriting_message(self):
        result, record = self.invoke()
        self.assertEqual(result.returncode, 0)
        args = record["args"]
        self.assertEqual(args[0], "--disable")
        for key, value in [("--haproxy-clientip", "192.0.2.10"), ("--cacert", "/trusted/ca"),
                           ("--mail-from", "sender@example.com"), ("--upload-file", "-"),
                           ("--url", "smtp://backend.example:25/sender.example"),
                           ("--proxy", ""), ("--noproxy", "*")]:
            self.assertEqual(args[args.index(key) + 1], value)
        self.assertIn("--ssl-reqd", args)
        self.assertNotIn("--insecure", args)
        self.assertNotIn("--crlf", args)

    def test_internet_null_sender_keeps_original_context(self):
        result, record = self.invoke(sender="")
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("--mail-from", record["args"])
        self.assertIn("--haproxy-clientip", record["args"])
        self.assertIn("smtp://backend.example:25/sender.example", record["args"])

    def test_only_local_queue_records_use_separate_listener(self):
        result, record = self.invoke(ip="", helo="", sender="")
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("--haproxy-clientip", record["args"])
        self.assertIn("smtp://backend.example:26/smtp-edge", record["args"])

    def test_ipv6_and_ehlo_are_preserved_without_url_interpretation(self):
        result, record = self.invoke(ip="2001:db8::10", helo="[IPv6:2001:db8::10]")
        self.assertEqual(result.returncode, 0)
        self.assertIn("2001:db8::10", record["args"])
        self.assertIn("smtp://backend.example:25/%5BIPv6%3A2001%3Adb8%3A%3A10%5D", record["args"])
        result, record = self.invoke(helo="a/%2f?x#y;$(false)")
        self.assertEqual(result.returncode, 0)
        self.assertIn("smtp://backend.example:25/a%2F%252f%3Fx%23y%3B%24%28false%29", record["args"])

    def test_postfix_ipv6_log_prefix_is_normalized(self):
        result, record = self.invoke(ip="IPv6:2001:db8::10")
        self.assertEqual(result.returncode, 0)
        args = record["args"]
        self.assertEqual(args[args.index("--haproxy-clientip") + 1], "2001:db8::10")

    def test_temporary_and_tls_failures_defer_instead_of_bouncing(self):
        for status, reply in [(7, "000"), (28, "250"), (60, "220"), (55, "451")]:
            with self.subTest(status=status, reply=reply):
                result, _ = self.invoke(status=status, reply=reply)
                self.assertEqual(result.returncode, 75)
                self.assertTrue(result.stdout.startswith(b"4.3.0 "))

    def test_backend_permanent_rejection_uses_sysexits_not_curl_exit(self):
        result, _ = self.invoke(status=55, reply="550")
        self.assertEqual(result.returncode, 69)
        self.assertTrue(result.stdout.startswith(b"5.0.0 "))

    def test_invalid_protected_metadata_fails_closed(self):
        for changes in [dict(ip="unknown"), dict(ip="IPv6:"), dict(ip="192.0.2.1\r\nHELO evil"),
                        dict(helo=""), dict(helo="ok\nMAIL FROM:<evil>"), dict(recipient="")]:
            with self.subTest(changes=changes):
                result, record = self.invoke(**changes)
                self.assertEqual(result.returncode, 75)
                self.assertIsNone(record)


if __name__ == "__main__":
    unittest.main()
