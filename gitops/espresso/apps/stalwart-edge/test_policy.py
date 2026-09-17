"""Offline tests, NOT native qualification. No backend contacted or DATA sent.

PYTHONDONTWRITEBYTECODE=1 python -m unittest discover \
  -s gitops/espresso/apps/stalwart-edge -p test_policy.py -v
"""
import copy
from concurrent.futures import ThreadPoolExecutor
import http.client
import io
import json
from pathlib import Path
import sqlite3
import ssl
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import policy as p

DOMAIN = "manafishrov.com"
ALICE = "alice@" + DOMAIN
SOURCE = p.Source("manafishrov", "https://backend.manafishrov.com", "TEST_TOKEN",
                  (DOMAIN,), "127.0.0.1", 24, "localhost")


def hook(recipient=ALICE, sender="sender@example.net"):
    return {"context": {"stage": "rcpt", "protocol": {"version": 1},
                        "client": {"ip": "192.0.2.1", "port": 1234, "activeConnections": 1},
                        "server": {"ip": "127.0.0.1", "port": 25}},
            "envelope": {"from": {"address": sender}, "to": [{"address": recipient}]}}


def fixtures():
    return {"Domain": [{"id": "d", "name": DOMAIN}, {"id": "m", "name": "system." + DOMAIN}],
            "Account": [{"id": "a", "active": False, "emailAddress": "ALICE@" + DOMAIN,
                         "aliases": {"yes": {"enabled": True, "name": "alias", "domainId": "d"},
                                     "no": {"enabled": False, "name": "disabled", "domainId": "d"}}},
                        {"id": "b", "emailAddress": "literal+tag@" + DOMAIN, "aliases": {}},
                        {"id": "m", "emailAddress": "robot@system." + DOMAIN, "aliases": {}}],
            "MailingList": [{"id": "list", "emailAddress": "postmaster@" + DOMAIN, "aliases": {}}]}


class Discovery(p.Reader):
    """Models pinned native constant queryState and absent Get state."""
    def __init__(self, source=SOURCE, data=None):
        self.source = source
        self.data = fixtures() if data is None else data
        self.calls = []
        self.change = None

    def call(self, kind, operation, args, deadline):
        self.calls.append((kind, operation, copy.deepcopy(args)))
        rows = self.data[kind]
        if operation == "query":
            pos = args["position"]
            result = {"ids": [r["id"] for r in rows[pos:pos + args["limit"]]],
                      "position": pos, "total": len(rows), "queryState": "n"}
        else:
            result = {"notFound": [], "list": [copy.deepcopy(r) for r in rows if r["id"] in args["ids"]]}
        if self.change:
            self.change(kind, operation, args, result)
        return result


class ProbeState:
    def __init__(self, default=p.Outcome.POSITIVE):
        self.default = default
        self.outcomes = {}
        self.calls = []

    def factory(self, source):
        state = self
        class Probe:
            def probe(self, recipient):
                state.calls.append((source.name, recipient))
                return state.outcomes.get(recipient, state.default)
        return Probe()


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "recipients.sqlite3"
        self.inventory = {SOURCE.name: [ALICE]}
        self.index = p.Index(self.path, [SOURCE], self.inventory)
        self.index.initialize()
        self.state = ProbeState()
        self.workers = []

    def tearDown(self):
        for worker in self.workers:
            worker.close()
        self.temp.cleanup()

    def refresher(self, **kwargs):
        defaults = {"reader_factory": Discovery, "probe_factory": self.state.factory,
                    "source_rate": 1000, "global_rate": 1000}
        defaults.update(kwargs)
        worker = p.Refresher(self.index, [SOURCE], **defaults)
        self.workers.append(worker)
        return worker

    def seed_one(self):
        self.assertTrue(self.index.record(SOURCE.name, ALICE, p.Outcome.POSITIVE))
        self.index.complete_seed(SOURCE.name)

    def service(self, **kwargs):
        return p.Policy(self.index, self.refresher(**kwargs), [SOURCE])

    @staticmethod
    def status(result):
        return 250 if result["action"] == "accept" else result["response"]["status"]

    def test_sql_source_scalar_integer_exact_full_address(self):
        self.seed_one()
        self.assertEqual(p.RECIPIENT_SQL, Path(p.__file__).with_name("policy.sql").read_text().strip())
        self.assertTrue(p.RECIPIENT_SQL.startswith("SELECT"))
        with self.index.connect() as db:
            for recipient, expected in [(ALICE, 1), (ALICE.upper(), 1), ("alice+tag@" + DOMAIN, 0),
                                        ("unknown@" + DOMAIN, 0), ("alice@system." + DOMAIN, 0),
                                        ("' OR 1=1 --@" + DOMAIN, 0), ("alice@@" + DOMAIN, 0)]:
                rows = db.execute(p.RECIPIENT_SQL, [recipient]).fetchall()
                self.assertEqual(rows, [(expected,)])
                self.assertIs(type(rows[0][0]), int)

    def test_no_plus_or_alias_normalization(self):
        self.seed_one()
        self.assertIsNone(self.index.lookup("alice+tag@" + DOMAIN))
        self.assertIsNone(self.index.lookup("alias@" + DOMAIN))
        self.index.record(SOURCE.name, "literal+tag@" + DOMAIN, p.Outcome.POSITIVE)
        self.assertIsNotNone(self.index.lookup("literal+tag@" + DOMAIN))
        self.assertIsNone(self.index.lookup("literal@" + DOMAIN))
        self.assertIsNone(self.index.lookup("literal+tag+more@" + DOMAIN))

    def test_explicit_served_domain_and_no_alias_expansion(self):
        self.seed_one()
        with self.assertRaises(p.Unavailable):
            self.index.record(SOURCE.name, "alice@alias.example", p.Outcome.POSITIVE)
        self.assertEqual(self.status(self.service().hook(hook("alice@alias.example"))), 550)
        self.assertEqual(self.status(self.service().hook(hook("robot@system." + DOMAIN))), 550)

    def test_positive_committed_before_hook_accept_and_no_rewrites(self):
        self.seed_one()
        request = hook("new+tag@" + DOMAIN)
        original = copy.deepcopy(request)
        result = self.service().hook(request)
        self.assertEqual(self.status(result), 250)
        self.assertIsNotNone(self.index.lookup("new+tag@" + DOMAIN))
        self.assertEqual(result["modifications"], [])
        self.assertEqual(request, original)

    def test_fresh_positive_skips_probe(self):
        self.seed_one()
        self.state.default = p.Outcome.ABSENT
        self.assertEqual(self.status(self.service().hook(hook())), 250)
        self.assertEqual(self.state.calls, [])

    def test_no_expiry_and_unseen_tag_outage_451(self):
        self.seed_one()
        with self.index.connect(write=True) as db:
            db.execute("UPDATE policy_recipients SET verified_at=1")
        self.state.default = p.Outcome.UNKNOWN
        service = self.service()
        self.assertEqual(self.status(service.hook(hook())), 250)
        self.assertEqual(self.status(service.hook(hook("alice+new@" + DOMAIN))), 451)
        self.assertIsNotNone(self.index.lookup(ALICE))
        self.assertTrue(self.index.healthy())

    def test_cached_outage_positive_bypasses_exhausted_client_budget(self):
        self.seed_one()
        with self.index.connect(write=True) as db:
            db.execute("UPDATE policy_recipients SET verified_at=1")
        self.state.default = p.Outcome.UNKNOWN
        service = self.service()
        service.client_budget = p.ClientProbeBudget(clock=lambda: 1)
        for _ in range(p.CLIENT_PROBE_BURST):
            service.client_budget.admit("192.0.2.1")
        self.assertEqual(self.status(service.hook(hook())), 250)
        self.assertIsNotNone(self.index.lookup(ALICE))
        self.assertEqual(len(self.state.calls), 1)
        self.assertEqual(self.status(service.hook(hook("new@" + DOMAIN))), 451)
        self.assertEqual(len(self.state.calls), 1)

    def test_qualified_absence_revokes_then_returns_550(self):
        self.seed_one()
        self.state.default = p.Outcome.ABSENT
        self.assertEqual(self.status(self.service(fresh_seconds=0).hook(hook())), 550)
        self.assertIsNone(self.index.lookup(ALICE))
        # Seed is historical completion, not a requirement never to delete inventory addresses.
        self.assertTrue(self.index.healthy())

    def test_new_unknown_temporary_failure_451(self):
        self.seed_one()
        self.state.default = p.Outcome.UNKNOWN
        self.assertEqual(self.status(self.service().hook(hook("new@" + DOMAIN))), 451)
        self.assertIsNone(self.index.lookup("new@" + DOMAIN))

    def test_commit_failure_is_451_even_for_previous_positive(self):
        self.seed_one()
        service = self.service(fresh_seconds=0)
        with patch.object(self.index, "record", side_effect=sqlite3.OperationalError("disk full")):
            self.assertEqual(self.status(service.hook(hook())), 451)
            self.assertEqual(self.status(service.hook(hook("new@" + DOMAIN))), 451)
        self.assertIsNotNone(self.index.lookup(ALICE))
        self.assertIsNone(self.index.lookup("new@" + DOMAIN))

    def test_revoke_commit_failure_does_not_claim_absence(self):
        self.seed_one()
        self.state.default = p.Outcome.ABSENT
        with patch.object(self.index, "record", side_effect=sqlite3.OperationalError()):
            self.assertEqual(self.status(self.service(fresh_seconds=0).hook(hook())), 451)
        self.assertIsNotNone(self.index.lookup(ALICE))

    def test_capacity_rejects_new_never_evicts_existing(self):
        self.index.capacity = self.index.source_capacity = 1
        self.seed_one()
        self.assertFalse(self.index.record(SOURCE.name, "new@" + DOMAIN, p.Outcome.POSITIVE))
        self.assertEqual(self.status(self.service().hook(hook("new@" + DOMAIN))), 451)
        self.assertEqual(self.state.calls, [])
        self.assertIsNotNone(self.index.lookup(ALICE))
        self.assertTrue(self.index.record(SOURCE.name, ALICE, p.Outcome.POSITIVE))

    def test_per_source_capacity_independent(self):
        source2 = p.Source("second", "https://second.example", "TOKEN", ("second.example",),
                           "127.0.0.1", 24, "localhost")
        index = p.Index(Path(self.temp.name) / "two.sqlite3", [SOURCE, source2],
                        {SOURCE.name: [ALICE], "second": ["a@second.example"]}, capacity=3, source_capacity=1)
        index.initialize()
        self.assertTrue(index.record(SOURCE.name, ALICE, p.Outcome.POSITIVE))
        self.assertFalse(index.record(SOURCE.name, "new@" + DOMAIN, p.Outcome.POSITIVE))
        self.assertTrue(index.record("second", "a@second.example", p.Outcome.POSITIVE))

    def test_rate_and_circuit_bounds_keep_existing_positive(self):
        self.seed_one()
        self.state.default = p.Outcome.UNKNOWN
        worker = self.refresher(source_rate=0.001, circuit_failures=1, circuit_seconds=60)
        self.assertEqual(worker.observe("first@" + DOMAIN), p.Outcome.UNKNOWN)
        self.assertEqual(worker.observe("second@" + DOMAIN), p.Outcome.UNKNOWN)
        self.assertEqual(worker.observe(ALICE, force=True), p.Outcome.POSITIVE)
        self.assertEqual(len(self.state.calls), 1)
        self.assertIsNotNone(self.index.lookup(ALICE))

    def test_rate_saturation_independent_of_circuit(self):
        worker = self.refresher(source_rate=0.0001, global_rate=0.0001, per_source=1)
        self.assertEqual(worker.observe(ALICE), p.Outcome.POSITIVE)
        self.assertEqual(worker.observe("second@" + DOMAIN), p.Outcome.UNKNOWN)
        self.assertEqual(len(self.state.calls), 1)

    def test_same_address_coalesced_old_positive_cannot_overwrite_revocation(self):
        started, release = threading.Event(), threading.Event()
        calls = []
        class Slow:
            def __init__(self, source):
                pass
            def probe(self, recipient):
                calls.append(recipient)
                if len(calls) == 1:
                    started.set()
                    release.wait(2)
                    return p.Outcome.POSITIVE
                return p.Outcome.ABSENT
        worker = self.refresher(probe_factory=Slow, wait=0.02)
        try:
            self.assertEqual(worker.observe(ALICE), p.Outcome.UNKNOWN)
            self.assertTrue(started.wait(1))
            self.assertEqual(worker.observe(ALICE, force=True), p.Outcome.UNKNOWN)
            self.assertEqual(len(calls), 1)
        finally:
            release.set()
        end = time.monotonic() + 2
        while worker.pending and time.monotonic() < end:
            time.sleep(0.005)
        self.assertIsNotNone(self.index.lookup(ALICE))
        self.assertEqual(worker.observe(ALICE, force=True), p.Outcome.ABSENT)
        self.assertEqual(len(calls), 2)
        self.assertIsNone(self.index.lookup(ALICE))

    def test_concurrent_probe_count_and_wait_bounded(self):
        started, release = threading.Event(), threading.Event()
        calls = []
        class Slow:
            def __init__(self, source):
                pass
            def probe(self, recipient):
                calls.append(recipient)
                started.set()
                release.wait(2)
                return p.Outcome.UNKNOWN
        worker = self.refresher(probe_factory=Slow, workers=1, per_source=1, wait=0.02)
        try:
            start = time.monotonic()
            self.assertEqual(worker.observe(ALICE), p.Outcome.UNKNOWN)
            self.assertLess(time.monotonic() - start, 0.5)
            self.assertTrue(started.wait(1))
            self.assertEqual(worker.observe("second@" + DOMAIN), p.Outcome.UNKNOWN)
            self.assertEqual(len(calls), 1)
        finally:
            release.set()

    def test_operator_inventory_seed_required_and_restart_outage_ready(self):
        self.assertFalse(self.index.healthy())
        self.assertEqual(self.status(self.service().hook(hook())), 451)
        worker = self.refresher()
        self.assertTrue(worker.seed(budget=3))
        self.assertTrue(self.index.healthy())
        restarted = p.Index(self.path, [SOURCE], self.inventory)
        restarted.initialize()
        self.assertTrue(restarted.healthy())
        self.assertIsNotNone(restarted.lookup(ALICE))
        self.state.default = p.Outcome.UNKNOWN
        self.assertEqual(worker.observe(ALICE, force=True), p.Outcome.POSITIVE)
        self.assertTrue(restarted.healthy())

    def test_changed_inventory_requires_new_seed(self):
        self.seed_one()
        changed = p.Index(self.path, [SOURCE], {SOURCE.name: [ALICE, "new@" + DOMAIN]})
        changed.initialize()
        self.assertFalse(changed.healthy())
        with self.assertRaises(p.Unavailable):
            changed.complete_seed(SOURCE.name)
        self.assertIsNotNone(changed.lookup(ALICE))

    def test_partial_seed_preserves_positives_but_no_ready_marker(self):
        self.state.default = p.Outcome.UNKNOWN
        self.state.outcomes[ALICE] = p.Outcome.POSITIVE
        self.assertFalse(self.refresher().seed(budget=0.05))
        self.assertIsNotNone(self.index.lookup(ALICE))
        self.assertFalse(self.index.healthy())
        with self.index.connect() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM policy_seed").fetchone(), (0,))

    def test_seed_missing_operator_expected_positive_fails(self):
        self.state.outcomes[ALICE] = p.Outcome.ABSENT
        self.assertFalse(self.refresher().seed(budget=1))
        self.assertFalse(self.index.healthy())

    def test_discovery_omission_never_revokes_or_depopulates(self):
        self.seed_one()
        class Empty:
            def __init__(self, source):
                pass
            def discover(self, deadline):
                return set()
        self.assertTrue(self.refresher(reader_factory=Empty).seed(budget=1))
        self.assertIsNotNone(self.index.lookup(ALICE))
        self.assertTrue(self.index.healthy())

    def test_partial_enumeration_failure_no_marker_or_depopulation(self):
        self.seed_one()
        class Broken(Discovery):
            def discover(self, deadline):
                raise p.Unavailable()
        self.assertFalse(self.refresher(reader_factory=Broken).seed(budget=1))
        self.assertTrue(self.index.healthy())
        self.assertIsNotNone(self.index.lookup(ALICE))

    def test_seed_completion_marker_transaction_rolls_back(self):
        self.index.record(SOURCE.name, ALICE, p.Outcome.POSITIVE)
        with self.index.connect(write=True) as db:
            db.execute("CREATE TRIGGER fail_seed BEFORE INSERT ON policy_seed "
                       "BEGIN SELECT RAISE(ABORT, 'test'); END")
        with self.assertRaises(sqlite3.IntegrityError):
            self.index.complete_seed(SOURCE.name)
        self.assertFalse(self.index.healthy())
        self.assertIsNotNone(self.index.lookup(ALICE))

    def test_pooled_native_connection_sees_commit_and_revoke(self):
        with self.index.connect() as db:
            self.assertEqual(db.execute(p.RECIPIENT_SQL, [ALICE]).fetchone(), (0,))
            self.index.record(SOURCE.name, ALICE, p.Outcome.POSITIVE)
            self.assertEqual(db.execute(p.RECIPIENT_SQL, [ALICE]).fetchone(), (1,))
            self.index.record(SOURCE.name, ALICE, p.Outcome.ABSENT)
            self.assertEqual(db.execute(p.RECIPIENT_SQL, [ALICE]).fetchone(), (0,))

    def test_corrupt_missing_and_configuration_mismatch_fail_closed(self):
        for filename in ("missing.sqlite3", "corrupt.sqlite3"):
            path = Path(self.temp.name) / filename
            if filename.startswith("corrupt"):
                path.write_bytes(b"not sqlite")
            index = p.Index(path, [SOURCE], self.inventory)
            self.assertFalse(index.healthy())
            self.assertEqual(self.status(p.Policy(index, None, [SOURCE]).hook(hook())), 451)
        self.assertFalse((Path(self.temp.name) / "missing.sqlite3").exists())
        self.seed_one()
        with self.index.connect(write=True) as db:
            db.execute("UPDATE policy_meta SET config_hash='wrong'")
        self.assertEqual(self.status(self.service().hook(hook())), 451)

    def test_hook_schema_wrong_stage_address_bounds_and_candidate(self):
        self.seed_one()
        service = self.service()
        for payload in (None, {}, [], {"context": {"stage": "data"}}):
            self.assertEqual(self.status(service.hook(payload)), 451)
        for recipient in ("bad\r\nDATA@" + DOMAIN, "x" * 65 + "@" + DOMAIN,
                          '"quoted"@' + DOMAIN, "ü@" + DOMAIN, "alice@@" + DOMAIN):
            self.assertEqual(self.status(service.hook(hook(recipient))), 451)
        request = hook()
        request["envelope"]["to"].insert(0, {"address": "previous@example.net"})
        self.assertEqual(self.status(service.hook(request)), 250)
        request["context"]["protocol"]["version"] = True
        self.assertEqual(self.status(service.hook(request)), 451)
        self.assertIn("enhanced_status", p.rejection()["response"])
        self.assertNotIn("enhancedStatus", p.rejection()["response"])

    def test_http_health_body_and_wrong_path(self):
        self.seed_one()
        server = p.Server(self.service(), ("127.0.0.1", 0))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for method, path, body in [("GET", "/healthz", None), ("POST", "/rcpt", json.dumps(hook())),
                                       ("POST", "/wrong", "{}"), ("POST", "/rcpt", "not json"),
                                       ("POST", "/rcpt", "x" * (p.MAX_BODY + 1))]:
                client = http.client.HTTPConnection(*server.server_address, timeout=2)
                client.request(method, path, body)
                response = client.getresponse()
                self.assertEqual(response.status, 200)
                result = json.loads(response.read())
                if method == "POST" and body != json.dumps(hook()):
                    self.assertEqual(result["response"]["status"], 451)
                client.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


class DiscoveryTests(unittest.TestCase):
    def test_pagination_native_states_and_six_methods_only(self):
        reader = Discovery()
        with patch.object(p, "PAGE_SIZE", 1):
            result = reader.discover(time.monotonic() + 10)
        self.assertEqual(result, {ALICE, "alias@" + DOMAIN, "literal+tag@" + DOMAIN, "postmaster@" + DOMAIN})
        self.assertEqual({(k, op) for k, op, args in reader.calls},
                         {(k, op) for k in p.PROPERTIES for op in ("query", "get")})
        self.assertTrue(any(args.get("position") == 1 for _, _, args in reader.calls))

    def test_truncation_duplicate_total_change_and_notfound_fail(self):
        def truncated(k, op, args, result):
            if k == "Account" and op == "query" and args["position"]:
                result["ids"] = []
        def duplicate(k, op, args, result):
            if k == "Account" and op == "query" and args["position"]:
                result["ids"] = ["a"]
        def total_changed(k, op, args, result):
            if k == "Account" and op == "query" and args["position"]:
                result["total"] += 1
        def notfound(k, op, args, result):
            if k == "Account" and op == "get":
                result["notFound"] = ["a"]
        for mutate in (truncated, duplicate, total_changed, notfound):
            with self.subTest(mutate=mutate.__name__), patch.object(p, "PAGE_SIZE", 1):
                reader = Discovery()
                reader.change = mutate
                with self.assertRaises(p.Unavailable):
                    reader.discover(time.monotonic() + 10)

    def test_missing_metadata_not_silently_empty(self):
        data = fixtures()
        del data["Account"][0]["aliases"]
        with self.assertRaises(p.Unavailable):
            Discovery(data=data).discover(time.monotonic() + 10)

    def test_https_redirect_and_configuration(self):
        reader = p.Reader(SOURCE)
        https = next(h for h in reader.opener.handlers if isinstance(h, p.urllib.request.HTTPSHandler))
        self.assertEqual(https._context.verify_mode, ssl.CERT_REQUIRED)
        self.assertTrue(https._context.check_hostname)
        with self.assertRaises(p.Unavailable):
            p.NoRedirect().redirect_request(None, None, 302, None, {}, "https://evil.test")
        with patch.dict(p.os.environ, {}, clear=True):
            source = p.configured_sources()[0]
            self.assertEqual(source.domains, (DOMAIN,))
            self.assertEqual(source.lmtp_port, 24)
            self.assertEqual(source.lmtp_servername, "backend.manafishrov.com")
        bad = dict(p.DEFAULT_SOURCES[0], url="http://evil.test")
        with patch.dict(p.os.environ, {"STALWART_EDGE_POLICY_SOURCES": json.dumps([bad])}):
            with self.assertRaises(p.Unavailable):
                p.configured_sources()


class ClientBudgetTests(unittest.TestCase):
    def setUp(self):
        self.now = 100.0
        self.budget = p.ClientProbeBudget(clock=lambda: self.now)

    def test_rate_refill_and_clients_are_independent(self):
        for _ in range(p.CLIENT_PROBE_BURST):
            self.assertTrue(self.budget.admit("192.0.2.1"))
        self.assertFalse(self.budget.admit("192.0.2.1"))
        for _ in range(p.CLIENT_PROBE_BURST):
            self.assertTrue(self.budget.admit("192.0.2.2"))
        self.assertFalse(self.budget.admit("192.0.2.2"))
        self.now += 1 / p.CLIENT_PROBE_RATE
        self.assertTrue(self.budget.admit("192.0.2.1"))
        self.assertFalse(self.budget.admit("192.0.2.1"))

    def test_ipv4_mapped_and_ipv6_spellings_share_canonical_key(self):
        for _ in range(p.CLIENT_PROBE_BURST):
            self.assertTrue(self.budget.admit("::ffff:192.0.2.1"))
        self.assertFalse(self.budget.admit("192.0.2.1"))
        self.assertFalse(self.budget.admit("0:0:0:0:0:ffff:c000:201"))
        for _ in range(p.CLIENT_PROBE_BURST):
            self.assertTrue(self.budget.admit("2001:0DB8:0000:0:0:0:0:1"))
        self.assertFalse(self.budget.admit("2001:db8::1"))
        self.assertEqual(set(self.budget.clients), {"192.0.2.1", "2001:db8::1"})

    def test_bounded_ipv6_cardinality_no_live_eviction_and_bounded_expiry(self):
        for i in range(p.CLIENT_PROBE_MAX_IPS):
            self.assertTrue(self.budget.admit(f"2001:db8::{i:x}"))
        self.assertFalse(self.budget.admit("2001:db8:1::1"))
        self.assertEqual(len(self.budget.clients), p.CLIENT_PROBE_MAX_IPS)
        # Existing clients retain their remaining tokens even when full.
        self.assertTrue(self.budget.admit("2001:db8::1"))
        self.now += p.CLIENT_PROBE_IDLE_TTL
        self.assertTrue(self.budget.admit("2001:db8:1::1"))
        self.assertEqual(len(self.budget.clients), p.CLIENT_PROBE_MAX_IPS - p.CLIENT_PROBE_CLEANUP + 1)
        self.assertIn("2001:db8:1::1", self.budget.clients)

    def test_idle_expiry_does_not_reset_continuous_abuser(self):
        for _ in range(p.CLIENT_PROBE_BURST):
            self.assertTrue(self.budget.admit("192.0.2.1"))
        # Denied calls still update idle order, with no rate reset.
        self.now += 0.1
        self.assertFalse(self.budget.admit("192.0.2.1"))
        self.now += 0.1
        self.assertFalse(self.budget.admit("192.0.2.1"))
        self.assertAlmostEqual(self.budget.clients["192.0.2.1"][0], 0.1)
        self.now += p.CLIENT_PROBE_IDLE_TTL
        for _ in range(p.CLIENT_PROBE_BURST):
            self.assertTrue(self.budget.admit("192.0.2.1"))
        self.assertFalse(self.budget.admit("192.0.2.1"))

    def test_concurrent_admission_cannot_overspend(self):
        with ThreadPoolExecutor(max_workers=16) as pool:
            results = list(pool.map(lambda _: self.budget.admit("192.0.2.1"), range(128)))
        self.assertEqual(sum(results), p.CLIENT_PROBE_BURST)
        self.assertEqual(len(self.budget.clients), 1)

    def test_malformed_addresses_do_not_allocate(self):
        for value in (None, True, 123, {}, [], "", " 192.0.2.1", "192.0.2.1:25",
                      "192.0.2.1,192.0.2.2", "[2001:db8::1]", "fe80::1%eth0", "x" * 1000,
                      "192.0.2.1\r\nX-Forwarded-For: 192.0.2.2"):
            with self.subTest(value=value), self.assertRaises((p.Unavailable, ValueError)):
                self.budget.admit(value)
        self.assertEqual(len(self.budget.clients), 0)


class ClientHookTests(unittest.TestCase):
    """Isolate client budget from independent global/source probe throttles."""
    def setUp(self):
        class Index:
            def healthy(self):
                return True
            def lookup(self, recipient):
                return 1 if recipient == ALICE else None
        class Refresher:
            def __init__(self):
                self.calls = []
            def observe(self, recipient):
                self.calls.append(recipient)
                return p.Outcome.POSITIVE if recipient == ALICE else p.Outcome.ABSENT
        self.refresher = Refresher()
        self.policy = p.Policy(Index(), self.refresher, [SOURCE])
        self.policy.client_budget = p.ClientProbeBudget(clock=lambda: 1)

    def send(self, ip="192.0.2.1", recipient="unknown@" + DOMAIN):
        payload = hook(recipient)
        payload["context"]["client"]["ip"] = ip
        return CacheTests.status(self.policy.hook(payload))

    def test_abusive_ip_451_without_probe_other_ip_unaffected(self):
        for _ in range(p.CLIENT_PROBE_BURST):
            self.assertEqual(self.send(), 550)
        self.assertEqual(self.send(), 451)
        self.assertEqual(len(self.refresher.calls), p.CLIENT_PROBE_BURST)
        self.assertEqual(self.send("192.0.2.2"), 550)
        self.assertEqual(len(self.refresher.calls), p.CLIENT_PROBE_BURST + 1)

    def test_concurrent_hook_requests_bound_probe_attempts(self):
        with ThreadPoolExecutor(max_workers=16) as pool:
            results = list(pool.map(lambda _: self.send(), range(64)))
        self.assertEqual(results.count(550), p.CLIENT_PROBE_BURST)
        self.assertEqual(results.count(451), 64 - p.CLIENT_PROBE_BURST)
        self.assertEqual(len(self.refresher.calls), p.CLIENT_PROBE_BURST)

    def test_known_positive_bypasses_exhausted_or_full_budget(self):
        for _ in range(p.CLIENT_PROBE_BURST):
            self.send()
        self.assertEqual(self.send(recipient=ALICE), 250)
        for i in range(p.CLIENT_PROBE_MAX_IPS - 1):
            self.policy.client_budget.admit(f"2001:db8::{i:x}")
        size = len(self.policy.client_budget.clients)
        self.assertEqual(size, p.CLIENT_PROBE_MAX_IPS)
        count = len(self.refresher.calls)
        self.assertEqual(self.send("198.51.100.1"), 451)
        self.assertEqual(len(self.refresher.calls), count)
        self.assertEqual(self.send("198.51.100.1", ALICE), 250)
        self.assertEqual(len(self.policy.client_budget.clients), size)

    def test_missing_malformed_and_spoofed_context_fail_closed(self):
        for value in (None, {}, {"ipAddress": "192.0.2.1"}, {"ip": "bad"}, {"ip": True},
                      {"ip": "fe80::1%lo"}, {"ip": "192.0.2.1, 192.0.2.2"}):
            payload = hook()
            if value is None:
                del payload["context"]["client"]
            else:
                payload["context"]["client"] = value
            payload["headers"] = {"X-Forwarded-For": "192.0.2.1"}
            payload["context"]["ip"] = "192.0.2.1"
            self.assertEqual(CacheTests.status(self.policy.hook(payload)), 451)
        self.assertEqual(self.refresher.calls, [])
        self.assertEqual(len(self.policy.client_budget.clients), 0)

    def test_alternate_forwarded_fields_cannot_reset_native_ip_budget(self):
        for i in range(p.CLIENT_PROBE_BURST + 1):
            payload = hook("unknown@" + DOMAIN)
            payload["context"]["client"]["forwardedFor"] = f"192.0.2.{i + 2}"
            payload["headers"] = {"X-Forwarded-For": f"192.0.2.{i + 2}"}
            result = CacheTests.status(self.policy.hook(payload))
            self.assertEqual(result, 550 if i < p.CLIENT_PROBE_BURST else 451)
        self.assertEqual(len(self.refresher.calls), p.CLIENT_PROBE_BURST)
        self.assertEqual(len(self.policy.client_budget.clients), 1)


class FakeSocket:
    def __init__(self, responses):
        self.stream = io.BytesIO(responses)
        self.sent = []
        self.timeouts = []
    def __enter__(self):
        return self
    def __exit__(self, *args):
        pass
    def settimeout(self, value):
        self.timeouts.append(value)
    def sendall(self, value):
        self.sent.append(value)
    def recv(self, size):
        return self.stream.read(size)


class FakeContext:
    """Test transport only: production has no injectable-context CLI flag."""
    verify_mode = ssl.CERT_REQUIRED
    check_hostname = True
    def __init__(self, sock):
        self.sock = sock
        self.servername = None
    def wrap_socket(self, raw, server_hostname):
        self.servername = server_hostname
        return self.sock


class ProbeTests(unittest.TestCase):
    def run_probe(self, rcpt=b"250 2.1.5 OK\r\n", mail=b"250 2.1.0 OK\r\n", recipient=ALICE):
        replies = b"220 fixture LMTP\r\n250-fixture\r\n250 PIPELINING\r\n" + mail
        if mail.startswith(b"250"):
            replies += rcpt
        replies += b"250 reset\r\n221 bye\r\n"
        sock = FakeSocket(replies)
        context = FakeContext(sock)
        with patch.object(p.socket, "create_connection", return_value=sock):
            outcome = p.LMTPProbe(SOURCE, context=context).probe(recipient)
        self.assertEqual(context.servername, "localhost")
        self.assertNotIn(b"DATA\r\n", sock.sent)
        self.assertTrue(all(0 < n <= 3 for n in sock.timeouts))
        return outcome, sock.sent

    def test_positive_exact_envelope_cleanup_no_data(self):
        result, commands = self.run_probe(recipient="ALICE+TAG@" + DOMAIN)
        self.assertEqual(result, p.Outcome.POSITIVE)
        self.assertEqual(commands, [b"LHLO edge-policy.invalid\r\n",
                                   b"MAIL FROM:<policy-probe@system.edge.asgard.michaelbrusegard.com>\r\n",
                                   b"RCPT TO:<alice+tag@manafishrov.com>\r\n", b"RSET\r\n", b"QUIT\r\n"])

    def test_only_source_exact_rcpt_negative_is_absence(self):
        for response, expected in [
            (b"550 5.1.2 Mailbox does not exist.\r\n", p.Outcome.ABSENT),
            (b"550 5.1.2 Relay not allowed.\r\n", p.Outcome.UNKNOWN),
            (b"550 5.1.1 User unknown\r\n", p.Outcome.UNKNOWN),
            (b"550 Authentication required\r\n", p.Outcome.UNKNOWN),
            (b"550 5.7.1 Sender not allowed\r\n", p.Outcome.UNKNOWN),
            (b"451 4.3.0 backend unavailable\r\n", p.Outcome.UNKNOWN),
            (b"252 Cannot verify\r\n", p.Outcome.UNKNOWN),
            (b"550-5.1.2 Mailbox does not exist.\r\n550 detail\r\n", p.Outcome.UNKNOWN),
            (b"550 5.1.2 Mailbox does not exist. extra\r\n", p.Outcome.UNKNOWN),
        ]:
            with self.subTest(response=response):
                outcome, commands = self.run_probe(response)
                self.assertEqual(outcome, expected)
                self.assertEqual(commands[-2:], [b"RSET\r\n", b"QUIT\r\n"])

    def test_mail_rejection_never_recipient_absence(self):
        outcome, commands = self.run_probe(mail=b"550 5.1.2 Mailbox does not exist.\r\n")
        self.assertEqual(outcome, p.Outcome.UNKNOWN)
        self.assertFalse(any(c.startswith(b"RCPT") for c in commands))
        self.assertEqual(commands[-2:], [b"RSET\r\n", b"QUIT\r\n"])

    def test_malformed_and_unbounded_reply_unknown(self):
        for response in (b"not SMTP\r\n", b"250 " + b"x" * 1024 + b"\r\n",
                         b"550-one\r\n250 mismatch\r\n", b"550-more\r\n" * 17):
            with self.subTest(response=response[:40]):
                outcome, _ = self.run_probe(response)
                self.assertEqual(outcome, p.Outcome.UNKNOWN)

    def test_tls_failures_and_insecure_context_refused(self):
        context = ssl.create_default_context()
        with patch.object(p.socket, "create_connection", side_effect=ssl.SSLCertVerificationError()):
            self.assertEqual(p.LMTPProbe(SOURCE, context=context).probe(ALICE), p.Outcome.UNKNOWN)
        insecure = ssl._create_unverified_context()
        with self.assertRaises(p.Unavailable):
            p.LMTPProbe(SOURCE, context=insecure)
        probe = p.LMTPProbe(SOURCE)
        self.assertEqual(probe.context.verify_mode, ssl.CERT_REQUIRED)
        self.assertTrue(probe.context.check_hostname)

    def test_drip_feed_obeys_total_deadline(self):
        class Drip(FakeSocket):
            def recv(self, size):
                return self.stream.read(1)
        sock = Drip(b"220 fixture LMTP\r\n")
        clock = iter([0, 0, 0, 0, 1, 2, 3, 4, 6, 6, 6, 6])
        with patch.object(p.time, "monotonic", side_effect=lambda: next(clock, 7)):
            with patch.object(p.socket, "create_connection", return_value=sock):
                result = p.LMTPProbe(SOURCE, context=FakeContext(sock)).probe(ALICE)
        self.assertEqual(result, p.Outcome.UNKNOWN)
        self.assertNotIn(b"DATA\r\n", sock.sent)

    def test_command_injection_rejected_without_connect(self):
        with patch.object(p.socket, "create_connection") as connect:
            self.assertEqual(p.LMTPProbe(SOURCE).probe("x\r\nDATA@" + DOMAIN), p.Outcome.UNKNOWN)
            connect.assert_not_called()


if __name__ == "__main__":
    unittest.main()
