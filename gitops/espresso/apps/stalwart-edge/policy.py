#!/usr/bin/env python3
"""Exact-address, native-LMTP-verified positive cache (stdlib, schema v2).

CLI: python policy.py serve | once | sql
  serve: 127.0.0.1:8090 POST /rcpt, GET /healthz; background discovery/rechecks.
  once: initialize and attempt seed, exit 0 only if ready; no SMTP listener.
  sql: print policy.sql verbatim, bind [rcpt] in native sql_query(store,sql,[rcpt]).
  STALWART_EDGE_POLICY_DB defaults /var/lib/stalwart/routing/recipients.sqlite3.
  STALWART_EDGE_POLICY_SOURCES: JSON list matching Source below. Default is the
    sole manafishrov source. TLS is implicit, certificate/hostname verified.
  STALWART_MANAFISH_SYNC_TOKEN: JMAP Bearer API key; never persisted/logged.
  STALWART_EDGE_POLICY_INVENTORY: REQUIRED path to operator-reviewed JSON map
    {source_name: [expected_valid_full_address,...]}; one per served domain at
    minimum. Include required aliases, plus variants, lists and postmaster.
  STALWART_EDGE_POLICY_QUALIFIED=1: REQUIRED operator attestation that the exact
    backend's RCPT existence result is sender-independent, including null,
    local, outside, and configured fixed probe sender. Set ONLY after native
    qualification; the flag is not itself evidence. No insecure TLS flag.

Policy caches complete lowercased ASCII SMTP addresses, not local-part rules.
There is NO plus stripping, alias expansion, TTL eviction, domain-wide grant,
recipient rewrite, or JMAP state/equal-scan consistency claim. Unseen +tags
return 451 during outage even when their base address is cached. JMAP is only
bounded/paginated discovery; SCIM active=false is login disable, not reception
policy. Omission, rename or deletion from discovery NEVER revokes a positive.
Each discovered address needs native LMTP verification. The operator inventory
is a separate expected-positive seed gate, not an assertion of atomic discovery.

Probe: implicit TLS greeting, LHLO, fixed MAIL FROM, exact RCPT TO, RSET, QUIT.
NEVER DATA or delivery. Only RCPT 250 is positive. Only the exact single-line
RCPT '550 5.1.2 Mailbox does not exist.' revokes (pinned smtp/inbound/rcpt.rs).
All other failures, including MAIL rejection, relay/auth errors and generic
5xx, are inconclusive. Production needs qualification of that exact response
and sender independence. Probe SSLContext is injectable for tests; even injected
contexts must verify certificates and hostnames.

A positive commits before hook accept; commit/read errors =>451. A due cached
positive survives inconclusive probes indefinitely. Fresh positives (5s) skip
probes. No positive silently evicted at capacity. One in-flight probe per exact
address, bounded executor/no pending queue; an older result cannot overwrite a
newer revocation. One process owns this DB (CLI enforces flock); native SQL
connections may remain open, because transactions never replace the file inode.

Defaults: 8 global/2 per-source concurrent probes, 8/s global and 2/s/source
with bursts 8/2; 5 inconclusive probes open a source circuit for 10s. Request
wait <=6s; probe I/O deadline 5s; TLS/connect <=3s per operation; DNS resolution
can exceed that OS timeout but occupies only a bounded worker, never an HTTP
wait. At most 16 HTTP workers, 64KiB bodies, 254-byte ASCII addresses, 16-line /
16KiB SMTP replies, 100k total /50k per-source cache. Saturation =>451 for new
addresses, retained acceptance for already committed ones. Background rechecks
are round-robin and rate-limited: 5s freshness is NOT a global deletion SLA.

Uncommitted RCPT lookups also consume a per-SMTP-client budget: 30/minute,
burst 10, at most 4096 IP keys, 600s idle expiry, <=64 expired removals per
admission (CLIENT_PROBE_* constants below). Active keys are never evicted to
admit new IPs. Exhaustion/full table =>451 without a probe; committed positives
bypass this budget, including during outage. This in-memory budget resets on
restart and is additional to global/source limits, not a distributed quota.
Only native context.client.ip is trusted; forwarded headers/alternate fields
are ignored. IPv4-mapped IPv6 shares its IPv4 budget. Missing/malformed IPs,
including scoped IPv6, fail closed even for known positives. The loopback hook
must remain accessible only to trusted native Stalwart/local components; JSON
cannot authenticate an IP supplied by an arbitrary local caller.

Readiness proves valid DB/schema/config AND completed seed for each configured
source/inventory. Marker commits in the same DB transaction as the final seed
validation; partial seeds keep their individually verified rows but are unready.
A valid persisted seed remains ready across restart/outage. Changed inventory
requires a new seed. Missing/corrupt DB =>451/unready. Both native readiness and
HTTP readiness are mandatory. Native SQLite failure AFTER hook success still
can yield native 550. This does not promise perfect end-to-end 451 behavior.
"""

import argparse
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
from contextlib import contextmanager
from dataclasses import asdict, dataclass
from enum import Enum
import fcntl
import hashlib
import http.server
import ipaddress
import json
import os
from pathlib import Path
import re
import socket
import sqlite3
import ssl
import threading
import time
import urllib.parse
import urllib.request

RECIPIENT_SQL = Path(__file__).with_name("policy.sql").read_text().strip()
SCHEMA_VERSION = 2
SCHEMA = """
CREATE TABLE policy_meta (version INTEGER NOT NULL, config_hash TEXT NOT NULL);
CREATE TABLE policy_sources (name TEXT PRIMARY KEY);
CREATE TABLE policy_domains (
 name TEXT PRIMARY KEY, source TEXT NOT NULL REFERENCES policy_sources(name),
 UNIQUE(name, source));
CREATE TABLE policy_recipients (
 address TEXT PRIMARY KEY, domain TEXT NOT NULL, source TEXT NOT NULL,
 verified_at REAL NOT NULL,
 FOREIGN KEY(domain, source) REFERENCES policy_domains(name, source));
CREATE INDEX policy_recipients_source ON policy_recipients(source, address);
CREATE TABLE policy_seed (
 source TEXT PRIMARY KEY REFERENCES policy_sources(name),
 inventory_hash TEXT NOT NULL, completed_at REAL NOT NULL);
"""
UNKNOWN_RECIPIENT = (550, (b"5.1.2 Mailbox does not exist.",))
MAX_BODY = 65536
MAX_RESPONSE = 4 * 1024 * 1024
MAX_OBJECTS = 100000
PAGE_SIZE = 128
# Per native SMTP client, in addition to existing global/source probe limits.
CLIENT_PROBE_RATE = 30 / 60  # tokens/second
CLIENT_PROBE_BURST = 10
CLIENT_PROBE_MAX_IPS = 4096
CLIENT_PROBE_IDLE_TTL = 600  # seconds; much longer than a full bucket refill
CLIENT_PROBE_CLEANUP = 64  # maximum expired removals per admission
PROPERTIES = {
    "Domain": ["id", "name"],
    "Account": ["id", "emailAddress", "aliases"],
    "MailingList": ["id", "emailAddress", "aliases"],
}


class Unavailable(Exception):
    """Inconclusive read/probe; never evidence of recipient absence."""


class Outcome(Enum):
    POSITIVE = "positive"
    ABSENT = "absent"
    UNKNOWN = "unknown"
    ERROR = "error"  # persistence/integrity failure: even cached positives fail closed


def require(condition):
    if not condition:
        raise Unavailable("invalid policy input")


def domain_name(value):
    require(isinstance(value, str) and value.isascii() and 0 < len(value) <= 253)
    value = value.lower()
    require(all(re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", p)
                for p in value.split(".")))
    return value


def address(value):
    """ASCII dot-atom subset only; unsupported SMTPUTF8/quoted locals =>451."""
    require(isinstance(value, str) and value.isascii() and len(value) <= 254)
    require(value.count("@") == 1)
    local, domain = value.lower().split("@")
    require(0 < len(local) <= 64 and re.fullmatch(r"[a-z0-9!#$%&'*+/=?^_`{|}~.\-]+", local))
    require(not local.startswith(".") and not local.endswith(".") and ".." not in local)
    return local + "@" + domain_name(domain)


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


@dataclass(frozen=True)
class Source:
    name: str
    url: str
    token_env: str
    domains: tuple
    lmtp_host: str
    lmtp_port: int = 24
    lmtp_servername: str = "backend.manafishrov.com"
    probe_sender: str = "policy-probe@system.edge.asgard.michaelbrusegard.com"


DEFAULT_SOURCES = [{
    "name": "manafishrov", "url": "https://backend.manafishrov.com",
    "token_env": "STALWART_MANAFISH_SYNC_TOKEN", "domains": ["manafishrov.com"],
    "lmtp_host": "backend.manafishrov.com", "lmtp_port": 24,
    "lmtp_servername": "backend.manafishrov.com",
    "probe_sender": "policy-probe@system.edge.asgard.michaelbrusegard.com",
}]


def configured_sources():
    raw = json.loads(os.environ.get("STALWART_EDGE_POLICY_SOURCES", json.dumps(DEFAULT_SOURCES)))
    require(isinstance(raw, list) and 0 < len(raw) <= 16)
    sources, names, domains = [], set(), set()
    for item in raw:
        source = Source(**item)
        parsed = urllib.parse.urlsplit(source.url)
        require(parsed.scheme == "https" and parsed.hostname and not parsed.username
                and not parsed.password and parsed.path in ("", "/")
                and not parsed.query and not parsed.fragment)
        require(re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", source.name) and source.name not in names)
        require(re.fullmatch(r"[A-Z][A-Z0-9_]*", source.token_env))
        require(isinstance(source.domains, (list, tuple)) and 0 < len(source.domains) <= 64)
        served = tuple(domain_name(d) for d in source.domains)
        require(len(set(served)) == len(served) and not domains.intersection(served))
        require(isinstance(source.lmtp_host, str) and 0 < len(source.lmtp_host) <= 253
                and not any(c.isspace() for c in source.lmtp_host))
        require(type(source.lmtp_port) is int and 0 < source.lmtp_port <= 65535)
        require(isinstance(source.lmtp_servername, str) and source.lmtp_servername)
        # Empty string deliberately selects MAIL FROM:<> for qualified deployments.
        if source.probe_sender:
            require(address(source.probe_sender) == source.probe_sender.lower())
        require(isinstance(source.probe_sender, str))
        sources.append(Source(source.name, source.url.rstrip("/"), source.token_env,
                              served, source.lmtp_host, source.lmtp_port,
                              source.lmtp_servername, source.probe_sender))
        names.add(source.name)
        domains.update(served)
    return sources


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise Unavailable("redirect refused")


class Reader:
    """Paginated candidate discovery, NOT authoritative recipient membership."""
    def __init__(self, source):
        self.source = source
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}), NoRedirect(),
            urllib.request.HTTPSHandler(context=ssl.create_default_context()))

    def call(self, kind, operation, arguments, deadline):
        remaining = deadline - time.monotonic()
        require(remaining > 0)
        method = f"x:{kind}/{operation}"
        request = urllib.request.Request(
            self.source.url + "/jmap",
            data=json.dumps({"using": ["urn:ietf:params:jmap:core", "urn:stalwart:jmap"],
                             "methodCalls": [[method, arguments, "p"]]}).encode(),
            headers={"Authorization": "Bearer " + os.environ[self.source.token_env],
                     "Content-Type": "application/json"})
        with self.opener.open(request, timeout=min(3, remaining)) as response:
            require(response.status == 200)
            chunks, size = [], 0
            while True:
                require(time.monotonic() < deadline)
                chunk = response.read1(min(65536, MAX_RESPONSE + 1 - size))
                if not chunk:
                    break
                chunks.append(chunk)
                size += len(chunk)
                require(size <= MAX_RESPONSE)
        responses = json.loads(b"".join(chunks)).get("methodResponses")
        require(isinstance(responses, list) and len(responses) == 1)
        row = responses[0]
        require(len(row) == 3 and row[0] == method and row[2] == "p" and isinstance(row[1], dict))
        return row[1]

    def collection(self, kind, deadline):
        objects, seen, position, total = [], set(), 0, None
        while True:
            page = self.call(kind, "query", {"position": position, "limit": PAGE_SIZE,
                                             "calculateTotal": True}, deadline)
            if total is None:
                total = page.get("total")
            ids = page.get("ids")
            require(type(total) is int and 0 <= total <= MAX_OBJECTS)
            require(page.get("total") == total and page.get("position") == position)
            require(isinstance(ids, list) and len(ids) <= PAGE_SIZE
                    and all(isinstance(i, str) for i in ids))
            require(len(set(ids)) == len(ids) and not seen.intersection(ids)
                    and position + len(ids) <= total and (ids or position == total))
            result = self.call(kind, "get", {"ids": ids, "properties": PROPERTIES[kind]}, deadline)
            rows = result.get("list")
            require(result.get("notFound") == [] and isinstance(rows, list) and len(rows) == len(ids))
            require(all(isinstance(r, dict) for r in rows) and {r.get("id") for r in rows} == set(ids))
            objects.extend(rows)
            seen.update(ids)
            position += len(ids)
            if position == total:
                return objects

    def discover(self, deadline):
        collections = {kind: self.collection(kind, deadline) for kind in PROPERTIES}
        by_id = {}
        for item in collections["Domain"]:
            require(item["id"] not in by_id)
            by_id[item["id"]] = domain_name(item["name"])
        result = set()
        for kind in ("Account", "MailingList"):
            for item in collections[kind]:
                require("emailAddress" in item and isinstance(item.get("aliases"), dict))
                candidates = [item["emailAddress"]] if item["emailAddress"] else []
                for alias in item["aliases"].values():
                    require(isinstance(alias, dict) and type(alias.get("enabled")) is bool)
                    if alias["enabled"]:
                        require(alias.get("domainId") in by_id and isinstance(alias.get("name"), str))
                        candidates.append(alias["name"] + "@" + by_id[alias["domainId"]])
                for candidate in candidates:
                    require(isinstance(candidate, str) and "@" in candidate)
                    if candidate.rsplit("@", 1)[1].lower() in self.source.domains:
                        result.add(address(candidate))
                        require(len(result) <= MAX_OBJECTS)
        # No domain-alias expansion, subaddressing rules, active filter or omission deletion.
        return result


class ReplyStream:
    """Read bounded SMTP lines with a wall-clock deadline, including drip feeds."""
    def __init__(self, sock, deadline):
        self.sock, self.deadline, self.buffer = sock, deadline, b""

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass  # Caller owns the TLS socket.

    def readline(self, limit):
        while b"\n" not in self.buffer and len(self.buffer) < limit:
            remaining = self.deadline - time.monotonic()
            require(remaining > 0)
            self.sock.settimeout(min(3, remaining))
            chunk = self.sock.recv(limit - len(self.buffer))
            require(chunk)
            self.buffer += chunk
        end = self.buffer.find(b"\n") + 1
        if end == 0:
            end = limit
        line, self.buffer = self.buffer[:end], self.buffer[end:]
        return line


class LMTPProbe:
    def __init__(self, source, *, context=None):
        self.source = source
        self.context = context if context is not None else ssl.create_default_context()
        require(self.context.verify_mode == ssl.CERT_REQUIRED and self.context.check_hostname)

    def probe(self, recipient):
        try:
            recipient = address(recipient)
            require(recipient.rsplit("@", 1)[1] in self.source.domains)
            sender = address(self.source.probe_sender) if self.source.probe_sender else ""
            deadline = time.monotonic() + 5
            with socket.create_connection((self.source.lmtp_host, self.source.lmtp_port), timeout=3) as raw:
                raw.settimeout(max(0.01, min(3, deadline - time.monotonic())))
                with self.context.wrap_socket(raw, server_hostname=self.source.lmtp_servername) as sock:
                    with ReplyStream(sock, deadline) as stream:
                        def budget():
                            remaining = deadline - time.monotonic()
                            require(remaining > 0)
                            sock.settimeout(min(3, remaining))

                        def reply():
                            code, lines, size = None, [], 0
                            for _ in range(16):
                                budget()
                                line = stream.readline(1025)
                                size += len(line)
                                require(len(line) <= 1024 and line.endswith(b"\r\n") and size <= 16384)
                                require(len(line) >= 6 and line[:3].isdigit() and line[3:4] in (b"-", b" "))
                                current = int(line[:3])
                                require(code is None or current == code)
                                code = current
                                lines.append(line[4:-2])
                                if line[3:4] == b" ":
                                    return code, tuple(lines)
                            raise Unavailable("reply limit")

                        def command(value):
                            budget()
                            sock.sendall(value + b"\r\n")
                            return reply()

                        outcome = Outcome.UNKNOWN
                        try:
                            if reply()[0] != 220:
                                return outcome
                            if command(b"LHLO edge-policy.invalid")[0] != 250:
                                return outcome
                            if command(("MAIL FROM:<" + sender + ">").encode("ascii"))[0] != 250:
                                return outcome
                            response = command(("RCPT TO:<" + recipient + ">").encode("ascii"))
                            if response[0] == 250:
                                outcome = Outcome.POSITIVE
                            elif response == UNKNOWN_RECIPIENT:
                                outcome = Outcome.ABSENT
                        finally:
                            # Cleanup failure does not invalidate an already definite RCPT.
                            # On broken sessions close is the final reset; never send DATA.
                            try:
                                command(b"RSET")
                            except Exception:
                                pass
                            try:
                                command(b"QUIT")
                            except Exception:
                                pass
                        return outcome
        except Exception:
            return Outcome.UNKNOWN


class Index:
    def __init__(self, path, sources, inventory, *, capacity=100000, source_capacity=50000):
        self.path = Path(path)
        self.sources = {s.name: s for s in sources}
        self.domains = {d: s.name for s in sources for d in s.domains}
        require(len(self.domains) == sum(len(s.domains) for s in sources))
        require(set(inventory) == set(self.sources))
        require(type(capacity) is int and 0 < capacity <= 100000)
        require(type(source_capacity) is int and 0 < source_capacity <= capacity)
        self.capacity, self.source_capacity = capacity, source_capacity
        self.inventory = {}
        for source in sources:
            items = inventory[source.name]
            require(isinstance(items, (list, tuple, set)) and 0 < len(items) <= source_capacity)
            expected = {address(a) for a in items}
            require({a.rsplit("@", 1)[1] for a in expected} == set(source.domains))
            self.inventory[source.name] = expected
        self.inventory_hash = {name: digest(sorted(items)) for name, items in self.inventory.items()}
        self.config_hash = digest([asdict(s) for s in sources])

    @contextmanager
    def connect(self, write=False):
        mode = "rw" if write else "ro"
        db = sqlite3.connect(self.path.resolve().as_uri() + "?mode=" + mode, uri=True, timeout=0.25)
        try:
            db.execute("PRAGMA foreign_keys=ON")
            db.execute("PRAGMA synchronous=FULL")
            with db:
                yield db
        finally:
            db.close()

    def initialize(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        db = sqlite3.connect(self.path, timeout=0.25)
        try:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("PRAGMA synchronous=FULL")
            db.execute("PRAGMA foreign_keys=ON")
            with db:
                db.execute("BEGIN IMMEDIATE")
                if db.execute("SELECT 1 FROM sqlite_master WHERE name='policy_meta'").fetchone():
                    self.validate(db)
                    return
                for statement in SCHEMA.split(";"):
                    if statement.strip():
                        db.execute(statement)
                db.execute("INSERT INTO policy_meta VALUES (?, ?)", [SCHEMA_VERSION, self.config_hash])
                db.executemany("INSERT INTO policy_sources VALUES (?)", [(s,) for s in self.sources])
                db.executemany("INSERT INTO policy_domains VALUES (?, ?)", self.domains.items())
        finally:
            db.close()

    def validate(self, db):
        if db.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
            raise Unavailable("corrupt database")
        require(db.execute("SELECT version, config_hash FROM policy_meta").fetchall()
                == [(SCHEMA_VERSION, self.config_hash)])
        require({r[0] for r in db.execute("SELECT name FROM policy_sources")} == set(self.sources))
        require(dict(db.execute("SELECT name,source FROM policy_domains")) == self.domains)
        require(not db.execute("PRAGMA foreign_key_check").fetchall())
        db.execute(RECIPIENT_SQL, ["probe@invalid"]).fetchone()

    def seeded(self, source, db):
        row = db.execute("SELECT inventory_hash,completed_at FROM policy_seed WHERE source=?", [source]).fetchone()
        return bool(row and row[0] == self.inventory_hash[source] and row[1] > 0)

    def healthy(self):
        try:
            with self.connect() as db:
                db.execute("BEGIN")
                self.validate(db)
                return all(self.seeded(s, db) for s in self.sources)
        except Exception:
            return False

    def lookup(self, recipient):
        recipient = address(recipient)
        with self.connect() as db:
            db.execute("BEGIN")
            self.validate(db)
            allowed = db.execute(RECIPIENT_SQL, [recipient]).fetchone()[0]
            if not allowed:
                return None
            return db.execute("SELECT verified_at FROM policy_recipients WHERE address=?",
                              [recipient]).fetchone()[0]

    def has_capacity(self, source, db=None):
        if db is None:
            with self.connect() as connection:
                self.validate(connection)
                return self.has_capacity(source, connection)
        return (db.execute("SELECT count(*) FROM policy_recipients").fetchone()[0] < self.capacity
                and db.execute("SELECT count(*) FROM policy_recipients WHERE source=?", [source]).fetchone()[0]
                < self.source_capacity)

    def record(self, source, recipient, outcome):
        require(outcome in (Outcome.POSITIVE, Outcome.ABSENT))
        recipient = address(recipient)
        domain = recipient.rsplit("@", 1)[1]
        require(self.domains.get(domain) == source)
        with self.connect(write=True) as db:
            db.execute("BEGIN IMMEDIATE")
            self.validate(db)
            if outcome is Outcome.ABSENT:
                db.execute("DELETE FROM policy_recipients WHERE address=? AND source=?", [recipient, source])
            else:
                existing = db.execute("SELECT 1 FROM policy_recipients WHERE address=?", [recipient]).fetchone()
                if not existing and not self.has_capacity(source, db):
                    return False
                db.execute("INSERT INTO policy_recipients VALUES (?, ?, ?, ?) "
                           "ON CONFLICT(address) DO UPDATE SET verified_at=excluded.verified_at",
                           [recipient, domain, source, time.time()])
        return True

    def complete_seed(self, source):
        with self.connect(write=True) as db:
            db.execute("BEGIN IMMEDIATE")
            self.validate(db)
            # Discovery can be non-atomic, but every inventory positive must be
            # committed in this transaction's view. Revocations during seed fail it.
            for recipient in self.inventory[source]:
                require(db.execute(RECIPIENT_SQL, [recipient]).fetchone() == (1,))
            db.execute("INSERT INTO policy_seed VALUES (?, ?, ?) ON CONFLICT(source) DO UPDATE SET "
                       "inventory_hash=excluded.inventory_hash,completed_at=excluded.completed_at",
                       [source, self.inventory_hash[source], time.time()])

    def batch(self, source, after="", limit=8):
        with self.connect() as db:
            self.validate(db)
            return [r[0] for r in db.execute(
                "SELECT address FROM policy_recipients WHERE source=? AND address>? ORDER BY address LIMIT ?",
                [source, after, limit])]


class Bucket:
    def __init__(self, rate, burst):
        self.rate, self.burst, self.tokens = rate, burst, float(burst)
        self.updated = time.monotonic()

    def available(self, now):
        self.tokens = min(self.burst, self.tokens + (now - self.updated) * self.rate)
        self.updated = now
        return self.tokens >= 1


class Refresher:
    """Single owner of bounded, same-address-serialized native probes."""
    def __init__(self, index, sources, reader_factory=Reader, probe_factory=LMTPProbe,
                 *, fresh_seconds=5, wait=6, workers=8, per_source=2,
                 global_rate=8, source_rate=2, circuit_failures=5, circuit_seconds=10):
        require(0 < workers <= 8 and 0 < per_source <= workers and 0 < wait <= 6)
        self.index, self.sources = index, {s.name: s for s in sources}
        self.reader_factory, self.probe_factory = reader_factory, probe_factory
        self.fresh_seconds, self.wait = fresh_seconds, wait
        self.workers, self.per_source = workers, per_source
        self.circuit_failures, self.circuit_seconds = circuit_failures, circuit_seconds
        self.lock = threading.Lock()
        self.seed_lock = threading.Lock()
        self.executor = ThreadPoolExecutor(max_workers=workers, thread_name_prefix="lmtp-policy")
        self.pending = {}
        self.counts = {s.name: 0 for s in sources}
        self.global_bucket = Bucket(global_rate, workers)
        self.buckets = {s.name: Bucket(source_rate, per_source) for s in sources}
        self.failures = {s.name: 0 for s in sources}
        self.open_until = {s.name: 0 for s in sources}
        self.stop = threading.Event()

    def close(self):
        self.stop.set()
        self.executor.shutdown(wait=True)

    def _probe(self, source, recipient):
        try:
            outcome = self.probe_factory(source).probe(recipient)
            if outcome not in (Outcome.POSITIVE, Outcome.ABSENT, Outcome.UNKNOWN):
                outcome = Outcome.UNKNOWN
        except Exception:
            outcome = Outcome.UNKNOWN
        with self.lock:
            if outcome is Outcome.UNKNOWN:
                self.failures[source.name] += 1
                if self.failures[source.name] >= self.circuit_failures:
                    self.open_until[source.name] = time.monotonic() + self.circuit_seconds
            else:
                self.failures[source.name] = 0
                self.open_until[source.name] = 0
        if outcome in (Outcome.POSITIVE, Outcome.ABSENT):
            try:
                if not self.index.record(source.name, recipient, outcome):
                    return Outcome.UNKNOWN  # Capacity race: never silently evict.
            except Exception:
                return Outcome.ERROR
        return outcome

    def _finished(self, source, recipient, future):
        with self.lock:
            if self.pending.get(recipient) is future:
                del self.pending[recipient]
                self.counts[source] -= 1

    def observe(self, recipient, *, force=False):
        try:
            recipient = address(recipient)
            source = self.sources[self.index.domains[recipient.rsplit("@", 1)[1]]]
            # In-flight ownership spans the probe AND its commit. A second
            # request shares that future, never starts a competing older probe.
            with self.lock:
                verified = self.index.lookup(recipient)
                future = self.pending.get(recipient)
                if future is None:
                    if verified is not None and not force and 0 <= time.time() - verified < self.fresh_seconds:
                        return Outcome.POSITIVE
                    now = time.monotonic()
                    blocked = (len(self.pending) >= self.workers or self.counts[source.name] >= self.per_source
                               or now < self.open_until[source.name]
                               or not self.global_bucket.available(now)
                               or not self.buckets[source.name].available(now))
                    if verified is None and not self.index.has_capacity(source.name):
                        blocked = True
                    if blocked:
                        return Outcome.POSITIVE if verified is not None else Outcome.UNKNOWN
                    self.global_bucket.tokens -= 1
                    self.buckets[source.name].tokens -= 1
                    self.counts[source.name] += 1
                    future = self.executor.submit(self._probe, source, recipient)
                    self.pending[recipient] = future
                    # Do NOT register callback while holding lock: an already
                    # finished future can run it synchronously.
                    created = True
                else:
                    created = False
            if created:
                future.add_done_callback(lambda f: self._finished(source.name, recipient, f))
            try:
                outcome = future.result(timeout=self.wait)
            except FutureTimeout:
                outcome = Outcome.UNKNOWN
            if outcome is Outcome.UNKNOWN:
                return Outcome.POSITIVE if self.index.lookup(recipient) is not None else Outcome.UNKNOWN
            return outcome
        except Exception:
            return Outcome.ERROR

    def seed(self, *, budget=60):
        """Complete discovery + individually verified expected operator inventory.

        Partial progress keeps committed positives, never sets a completion
        marker. No state tokens/equal scans are used. Reattempts can reuse
        already verified positives; this is deliberately not a snapshot claim.
        """
        if not self.seed_lock.acquire(blocking=False):
            return False
        try:
            deadline = time.monotonic() + budget
            for source in self.sources.values():
                candidates = self.reader_factory(source).discover(min(deadline, time.monotonic() + 20))
                require(isinstance(candidates, set) and len(candidates) <= MAX_OBJECTS)
                for candidate in candidates:
                    require(address(candidate) == candidate
                            and candidate.rsplit("@", 1)[1] in source.domains)
                expected = self.index.inventory[source.name]
                for recipient in sorted(expected) + sorted(candidates - expected):
                    # Previously committed positives remain native-verified
                    # during outage; background refresh handles their lifecycle.
                    if self.index.lookup(recipient) is not None:
                        continue
                    while True:
                        require(time.monotonic() < deadline and not self.stop.is_set())
                        outcome = self.observe(recipient)
                        if outcome is Outcome.POSITIVE:
                            break
                        if outcome is Outcome.ABSENT:
                            require(recipient not in expected)
                            break
                        if outcome is Outcome.ERROR:
                            raise Unavailable("seed storage failure")
                        if self.stop.wait(0.25):
                            raise Unavailable("stopped")
                self.index.complete_seed(source.name)
            return self.index.healthy()
        except Exception:
            return False
        finally:
            self.seed_lock.release()

    def background(self):
        cursors = {s: "" for s in self.sources}
        next_discovery = 0
        while not self.stop.is_set():
            try:
                self.index.initialize()
                if not self.index.healthy() or time.monotonic() >= next_discovery:
                    self.seed()
                    next_discovery = time.monotonic() + 300
                for source in self.sources:
                    rows = self.index.batch(source, cursors[source])
                    if not rows:
                        cursors[source] = ""
                        rows = self.index.batch(source)
                    for recipient in rows:
                        if self.stop.is_set():
                            return
                        self.observe(recipient)
                        cursors[source] = recipient
            except Exception:
                pass  # Never print exception strings, backend payloads or tokens.
            self.stop.wait(5)


def rejection(status=451):
    return {"action": "reject", "response": {
        "status": status, "enhanced_status": "4.3.0" if status == 451 else "5.1.1",
        "message": "Recipient policy unavailable" if status == 451 else "Unknown recipient",
        "disconnect": False}, "modifications": []}


def client_ip(value):
    require(isinstance(value, str) and 0 < len(value) <= 45 and "%" not in value)
    parsed = ipaddress.ip_address(value)
    if isinstance(parsed, ipaddress.IPv6Address) and parsed.ipv4_mapped is not None:
        parsed = parsed.ipv4_mapped
    return str(parsed)


class ClientProbeBudget:
    """Bounded idle-ordered token buckets; never evict a live client's budget."""
    def __init__(self, *, clock=time.monotonic):
        self.clock = clock
        self.lock = threading.Lock()
        self.clients = OrderedDict()

    def admit(self, ip):
        ip = client_ip(ip)
        with self.lock:
            now = self.clock()
            # Access order is last-seen order, including denied attempts, so a
            # continuously abusive client cannot reset its budget by churning.
            for _ in range(CLIENT_PROBE_CLEANUP):
                if not self.clients:
                    break
                oldest, (_, last_seen) = next(iter(self.clients.items()))
                if now - last_seen < CLIENT_PROBE_IDLE_TTL:
                    break
                del self.clients[oldest]
            previous = self.clients.get(ip)
            if previous is None:
                if len(self.clients) >= CLIENT_PROBE_MAX_IPS:
                    return False
                tokens = float(CLIENT_PROBE_BURST)
            else:
                tokens, last_seen = previous
                tokens = min(CLIENT_PROBE_BURST, tokens + max(0, now - last_seen) * CLIENT_PROBE_RATE)
            admitted = tokens >= 1
            self.clients[ip] = (tokens - 1 if admitted else tokens, now)
            self.clients.move_to_end(ip)
            return admitted


class Policy:
    def __init__(self, index, refresher, sources):
        self.index, self.refresher = index, refresher
        self.domains = {d for s in sources for d in s.domains}
        self.client_budget = ClientProbeBudget()

    def hook(self, payload):
        try:
            require(payload["context"]["stage"] == "rcpt")
            require(type(payload["context"]["protocol"]["version"]) is int
                    and payload["context"]["protocol"]["version"] == 1)
            ip = client_ip(payload["context"]["client"]["ip"])
            envelope = payload["envelope"]
            require(isinstance(envelope["from"]["address"], str))
            recipients = envelope["to"]
            require(isinstance(recipients, list) and 0 < len(recipients) <= 1000)
            rcpt = address(recipients[-1]["address"])
            if rcpt.rsplit("@", 1)[1] not in self.domains:
                return rejection(550)
            require(self.index.healthy())
            if self.index.lookup(rcpt) is None and not self.client_budget.admit(ip):
                # A concurrent successful probe may have committed since the
                # first lookup. Never deny that now-known positive on budget.
                if self.index.lookup(rcpt) is None:
                    return rejection()
            outcome = self.refresher.observe(rcpt)
            if outcome is Outcome.POSITIVE:
                return {"action": "accept", "modifications": []}
            return rejection(550 if outcome is Outcome.ABSENT else 451)
        except Exception:
            return rejection()


class Handler(http.server.BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(3)

    def log_message(self, *args):
        pass

    def respond(self, value, status=200):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def do_GET(self):
        healthy = self.path == "/healthz" and self.server.policy.index.healthy()
        self.respond({"healthy": healthy}, 200 if healthy else 503)

    def do_POST(self):
        try:
            lengths = self.headers.get_all("Content-Length", [])
            require(self.path == "/rcpt" and len(lengths) == 1 and not self.headers.get("Transfer-Encoding"))
            length = int(lengths[0])
            require(0 < length <= MAX_BODY)
            deadline = time.monotonic() + 3
            chunks = []
            remaining = length
            while remaining:
                timeout = deadline - time.monotonic()
                require(timeout > 0)
                self.connection.settimeout(timeout)
                chunk = self.rfile.read1(remaining)
                require(chunk)
                chunks.append(chunk)
                remaining -= len(chunk)
            result = self.server.policy.hook(json.loads(b"".join(chunks)))
        except Exception:
            result = rejection()
        self.respond(result)


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 16

    def __init__(self, policy, bind=("127.0.0.1", 8090)):
        self.policy = policy
        self.slots = threading.BoundedSemaphore(16)
        super().__init__(bind, Handler)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)  # Native tempFailOnError MUST be true.
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("serve", "once", "sql"))
    args = parser.parse_args()
    if args.command == "sql":
        print(RECIPIENT_SQL)
        return 0
    try:
        require(os.environ.get("STALWART_EDGE_POLICY_QUALIFIED") == "1")
        sources = configured_sources()
        inventory_path = Path(os.environ["STALWART_EDGE_POLICY_INVENTORY"])
        require(inventory_path.stat().st_size <= MAX_RESPONSE)
        inventory = json.loads(inventory_path.read_text())
        index = Index(os.environ.get("STALWART_EDGE_POLICY_DB",
                                    "/var/lib/stalwart/routing/recipients.sqlite3"), sources, inventory)
        index.path.parent.mkdir(parents=True, exist_ok=True)
        # Only one cache writer process is supported. Lock persists for process lifetime.
        with index.path.with_suffix(index.path.suffix + ".lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            refresher = Refresher(index, sources)
            if args.command == "once":
                try:
                    index.initialize()
                    return 0 if refresher.seed() else 1
                finally:
                    refresher.close()
            threading.Thread(target=refresher.background, daemon=True).start()
            try:
                Server(Policy(index, refresher, sources)).serve_forever()
            finally:
                refresher.close()
    except Exception:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
