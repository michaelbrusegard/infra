"""Offline bootstrap boundaries; no cluster or credential access."""

import unittest

from edge_bootstrap import Client, bootstrap


class FakeClient:
    def __init__(self, occupied=False):
        self.occupied = occupied
        self.created = []
        self.calls = []

    def call(self, kind, operation, arguments):
        self.calls.append((kind, operation, arguments))
        if operation == "query":
            return {"ids": ["existing"] if self.occupied else []}
        return {}

    def create(self, kind, value):
        self.created.append((kind, value))
        return str(len(self.created))

    def key(self, account):
        return "fixture-only-key-" + account


class BootstrapTests(unittest.TestCase):
    def test_rejects_non_loopback_and_ambiguous_endpoints(self):
        for url in ("http://example.com:80", "https://127.0.0.1:443",
                    "http://127.0.0.1", "http://user@127.0.0.1:8080",
                    "http://127.0.0.1:8080/jmap", "http://127.0.0.1:8080?x=1"):
            with self.subTest(url=url), self.assertRaises(RuntimeError):
                Client(url, "edge-bootstrap:{PLAIN}fixture")
        Client("http://127.0.0.1:18088", "edge-bootstrap:{PLAIN}fixture")

    def test_refuses_existing_identity_store(self):
        client = FakeClient(occupied=True)
        with self.assertRaises(RuntimeError):
            bootstrap(client, ["authenticate"], ["authenticate"], self.fail, self.fail)
        self.assertEqual(client.created, [])

    def test_machine_only_bootstrap_and_no_smtp_activation(self):
        client = FakeClient()
        config, readiness = [], []
        bootstrap(client, ["authenticate", "sysDomainGet"], ["authenticate"],
                  config.append, readiness.append)
        users = [value for kind, value in client.created if kind == "Account"]
        self.assertEqual([user["name"] for user in users], ["tofu", "readiness"])
        for user in users:
            self.assertEqual(user["roles"], {"@type": "User"})
            self.assertEqual(user["credentials"], {})
            self.assertEqual(user["permissions"]["@type"], "Replace")
        listeners = [value for kind, value in client.created if kind == "NetworkListener"]
        self.assertEqual(len(listeners), 1)
        self.assertEqual(listeners[0]["bind"], {"[::]:443": True})
        self.assertEqual(config[0]["metadata"]["namespace"], "flux-system")
        self.assertEqual(readiness[0]["metadata"]["namespace"], "stalwart-edge")
        self.assertNotIn("STALWART_TOKEN", readiness[0]["stringData"])

    def test_persistence_failure_stops_before_second_principal(self):
        client = FakeClient()

        def fail_save(_):
            raise RuntimeError("fixture encryption failure")

        with self.assertRaises(RuntimeError):
            bootstrap(client, ["authenticate"], ["authenticate"], fail_save, self.fail)
        users = [value["name"] for kind, value in client.created if kind == "Account"]
        self.assertEqual(users, ["tofu"])


if __name__ == "__main__":
    unittest.main()
