#!/usr/bin/env python3
"""Test the actual ClickHouse schema and dashboard, without changing the cluster.

Run with `nix develop --command python3 gitops/espresso/tests/ai-usage.py`.
Requires Docker and Go; --live also runs read-only dashboard queries against the archive.
"""

import argparse
import datetime
import json
import math
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "gitops/espresso"
PLUGINS = ROOT / "packages/cliproxy-plugins"

# llm.requests as it was before request_items, to migrate from.
LEGACY_REQUESTS = """
CREATE TABLE llm.requests
(
    request_id String, trace_id String, session_id String,
    started_at DateTime64(3, 'UTC'), completed_at DateTime64(3, 'UTC'),
    source_format LowCardinality(String), model LowCardinality(String),
    requested_model LowCardinality(String), stream Bool, outcome LowCardinality(String),
    status_code UInt16, error String, user_agent LowCardinality(String), truncated Bool,
    request_body String CODEC(ZSTD(3)), response_body String CODEC(ZSTD(3))
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(started_at)
ORDER BY (session_id, started_at, request_id)
"""


def run(*args, input=None, check=True, **kwargs):
    return subprocess.run(args, input=input, text=True, capture_output=True, check=check, **kwargs)


def manifest(path):
    return json.loads(run("yq", "-o=json", str(BASE / path)).stdout)


def expand(sql, provider=None, model=None, origin=None):
    for name, value in (("origin", origin), ("provider", provider), ("model", model)):
        condition = f"$__conditionalAll({name} IN (${{{name}:singlequote}}), ${name})"
        sql = sql.replace(condition, "1=1" if value is None else f"{name} IN ('{value}')")
    sql = sql.replace("$__timeFilter_ms(requested_at)",
                      "requested_at BETWEEN now() - INTERVAL 1 DAY AND now()")
    sql = sql.replace("$__timeInterval_ms(requested_at)",
                      "toStartOfInterval(requested_at, INTERVAL 300 SECOND)")
    assert "$" not in sql, sql
    return sql


def same_json(a, b):
    """Compare JSON by value, keeping numerals as written and duplicate keys."""
    def load(text):
        return json.loads(text, parse_float=lambda n: ("number", n), parse_int=lambda n: ("number", n),
                          object_pairs_hook=lambda pairs: sorted(pairs, key=repr))
    return load(a) == load(b)


def check_request_items(query, container, schema, temp):
    """Plugin rows, the backfill, and the view agree on the real schema."""
    fresh = query("SHOW CREATE TABLE llm.requests").stdout
    assert "request_body" not in fresh, fresh
    fixtures = json.loads((PLUGINS / "requestitems/testdata/bodies.json").read_text())
    dump = temp / "dump"
    dump.mkdir()
    run("go", "test", "-count=1", "./clickhouse-archive", "-run", "TestRequestRowsMatchTheBackfill",
        "-args", "-dump", str(dump), cwd=PLUGINS)
    items = (dump / "llm.request_items.jsonl").read_text()
    requests = (dump / "llm.requests.jsonl").read_text()

    # The plugin's rows, inserted with its own grants.
    query("INSERT INTO llm.request_items FORMAT JSONEachRow\n" + items, "cliproxy")
    query("INSERT INTO llm.requests FORMAT JSONEachRow\n" + requests, "cliproxy")
    for table in ("llm.request_items", "llm.requests", "llm.request_bodies"):
        result = query(f"SELECT * FROM {table}", "cliproxy", check=False)
        assert result.returncode != 0, f"Writer unexpectedly read {table}"

    # Go's hashes are ClickHouse's SHA256 prefix of the stored bytes.
    assert query("SELECT count() FROM llm.request_items "
                 "WHERE hash != reinterpretAsUInt128(substring(SHA256(item), 1, 16))").stdout.strip() == "0"
    stored_items = len(items.splitlines())
    assert int(query("SELECT uniqExact(hash) FROM llm.request_items").stdout) == stored_items

    # ClickHouse's own JSON extraction rewrites the bytes, so it cannot split
    # the same items; the backfill runs the plugin's Go code instead.
    lossy = query("SELECT JSONExtractArrayRaw('[1.0, -0, 1E+2]')").stdout.strip()
    assert lossy == "['1','0','100']", lossy

    def bodies(prefix=""):
        rows = query("SELECT request_id, request_body FROM llm.request_bodies FORMAT JSONEachRow").stdout
        found = {r["request_id"]: r["request_body"] for r in map(json.loads, rows.splitlines())}
        for f in fixtures:
            body = found[prefix + f["name"]]
            try:
                json.loads(f["body"])
                valid = f["body"].lstrip().startswith("{")
            except ValueError:
                valid = False
            assert same_json(body, f["body"]) if valid else body == f["body"], (f["name"], body)

    bodies()

    # An existing install: the old table, upgraded by schema.sql on restart.
    query("DROP TABLE llm.requests SYNC")
    query(LEGACY_REQUESTS)
    old = datetime.datetime(2026, 11, 10, 12)
    legacy = [json.dumps({"request_id": "legacy-" + f["name"], "session_id": f"s{i % 3}",
                          "started_at": (old + datetime.timedelta(minutes=i)).strftime("%Y-%m-%d %H:%M:%S.000"),
                          "request_body": f["body"], "response_body": "response " + f["name"]})
              for i, f in enumerate(fixtures)]
    query("INSERT INTO llm.requests FORMAT JSONEachRow\n" + "\n".join(legacy))
    run("docker", "exec", "-i", container, "clickhouse-client", "--multiquery", input=schema)

    migrate = BASE / "apps/clickhouse/migrate-request-items.sh"
    env = {**os.environ, "CLICKHOUSE_EXEC": f"docker exec -i {container}", "CHUNK_BYTES": "3000"}
    refused = run(migrate, "copy", env=env, check=False)
    assert refused.returncode != 0 and "roll out the new archive plugin first" in refused.stderr, refused.stderr
    # The new plugin's rows land in the old table until the swap.
    query("INSERT INTO llm.requests FORMAT JSONEachRow\n" + requests, "cliproxy")
    copied = run(migrate, "copy", env=env)
    assert copied.stdout.count("chunk ") > 1, copied.stdout
    # Lone surrogate escapes are valid JSON to Go but not to ClickHouse.
    assert "'legacy-tricky'" in copied.stdout, copied.stdout
    assert "chunk " not in run(migrate, "copy", env=env).stdout  # resumable: nothing left
    run(migrate, "drop", env=env)

    assert query("SHOW CREATE TABLE llm.requests").stdout == fresh
    tables = query("SHOW TABLES FROM llm").stdout.split()
    assert not [t for t in tables if t.startswith(("requests_", "request_backfill"))], tables
    # Both paths produce the same items, so the backfill added none.
    assert int(query("SELECT uniqExact(hash) FROM llm.request_items").stdout) == stored_items
    assert query("SELECT count() FROM llm.requests AS a JOIN llm.requests AS b "
                 "ON a.request_id = concat('legacy-', b.request_id) "
                 "WHERE a.request_envelope = b.request_envelope AND a.request_parts = b.request_parts"
                 ).stdout.strip() == str(len(fixtures))
    assert query("SELECT response_body FROM llm.requests WHERE request_id = 'legacy-claude'").stdout == "response claude\n"
    bodies("legacy-")
    return len(fixtures)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true")
    args = parser.parse_args()
    config = manifest("apps/clickhouse/configmap.yaml")["data"]
    statefulset = manifest("apps/clickhouse/statefulset.yaml")
    image = statefulset["spec"]["template"]["spec"]["containers"][0]["image"]
    dashboard = json.loads((BASE / "infrastructure/configs/grafana/ai-usage.json").read_text())
    queries = [(p["title"], t["rawSql"]) for p in dashboard["panels"] for t in p.get("targets", [])]
    queries += [(v["name"], v["query"]) for v in dashboard["templating"]["list"]]
    container = f"infra-ai-usage-test-{os.getpid()}"
    with tempfile.TemporaryDirectory(prefix="infra-ai-usage-") as directory:
        temp = Path(directory)
        temp.chmod(0o755)
        for name in ("config.xml", "users.xml", "schema.sql"):
            (temp / name).write_text(config[name])
        try:
            run("docker", "run", "--detach", "--name", container, "--network", "none",
                "--memory", "2g", "--cpus", "2",
                "-e", "CLICKHOUSE_SKIP_USER_SETUP=1",
                "-v", f"{temp}/config.xml:/etc/clickhouse-server/config.d/archive.xml:ro",
                "-v", f"{temp}/users.xml:/etc/clickhouse-server/users.d/archive.xml:ro",
                "-v", f"{temp}/schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro", image)

            def query(sql, user="default", check=True):
                return run("docker", "exec", "-i", container, "clickhouse-client", "--user", user,
                           "--query", sql, check=check)

            for _ in range(120):
                ready = query("EXISTS TABLE llm.usage_metrics", check=False)
                if ready.returncode == 0 and ready.stdout.strip() == "1":
                    break
                time.sleep(0.5)
            else:
                raise RuntimeError(run("docker", "logs", container).stdout)

            stamp = datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%d %H:%M:%S.000")

            def row(id, model="gpt-6.1-sol", provider="codex", **tokens):
                return {"request_id": id, "trace_id": id, "model": model, "provider": provider,
                        "requested_at": stamp, "auth_type": "oauth", **tokens}

            rows = [
                row("cached", input_tokens=1000, output_tokens=100, reasoning_tokens=50,
                    cached_tokens=500, cache_read_tokens=500),
                row("long", input_tokens=272001, output_tokens=1000, cache_read_tokens=200000),
                row("threshold", input_tokens=272000),
                row("claude", "claude-opus-5-5", "claude", input_tokens=100,
                    cache_read_tokens=2000, output_tokens=25),
                row("cache-write", "claude-opus-5-5", "claude", input_tokens=100,
                    cached_tokens=1000, cache_creation_tokens=1000, output_tokens=25),
                row("unknown", "future-model", "codex", input_tokens=1000, output_tokens=100),
                row("limited", failed=True, failure_status=429),
                row("astra", "gpt-6-astra", input_tokens=1000, output_tokens=100),
                row("luna", "gpt-6-luna", input_tokens=1000, output_tokens=100),
            ]
            query("INSERT INTO llm.usage FORMAT JSONEachRow\n" + "\n".join(map(json.dumps, rows)))
            old_stamp = (datetime.datetime.now(datetime.UTC) - datetime.timedelta(days=90)).strftime("%Y-%m-%d %H:%M:%S.000")
            history = [
                dict(event_id='history-claude', source='claude-code', requested_at=old_stamp,
                     provider='claude', model='claude-opus-5-5', uncached_input_tokens=100,
                     cache_read_tokens=200, cache_creation_tokens=100,
                     cache_write_5m_tokens=60, cache_write_1h_tokens=40, output_tokens=25),
                dict(event_id='history-gpt', source='codex', requested_at=old_stamp,
                     provider='codex', model='gpt-5.5', uncached_input_tokens=500,
                     cache_read_tokens=500, output_tokens=100),
                dict(event_id='history-unknown', source='pi', requested_at=old_stamp,
                     provider='kimi', model='future-model', uncached_input_tokens=100, output_tokens=10),
                dict(event_id='overlap', source='pi', requested_at=stamp,
                     provider='codex', model='gpt-6.1-sol', uncached_input_tokens=999999999),
            ]
            # Reruns may add physical rows, but must never increase dashboard totals.
            for _ in range(2):
                query("INSERT INTO llm.historical_usage FORMAT JSONEachRow\n" + "\n".join(map(json.dumps, history)))
            values = [json.loads(line) for line in query(
                "SELECT * FROM llm.usage_metrics FORMAT JSONEachRow", "grafana").stdout.splitlines()]
            data = {r["trace_id"]: r for r in values}
            for id, expected in (("cached", 0.00205), ("long", 0.343004), ("threshold", 0.544), ("claude", 0.0013),
                                 ("astra", 0.015), ("luna", 0.00015)):
                assert math.isclose(data[id]["estimated_cost_usd"], expected, rel_tol=1e-9), data[id]
            assert data["cached"]["total_tokens"] == 1100  # reasoning is a subset
            assert data["cached"]["uncached_input_tokens"] == 500  # cache fields are aliases
            assert data["claude"]["input_tokens"] == 2100  # Claude cache is independent
            assert data["cache-write"]["cache_read_tokens"] == 0  # cached_tokens may mean writes
            assert data["cache-write"]["estimated_cost_usd"] is None
            assert data["unknown"]["estimated_cost_usd"] is None
            assert math.isclose(data['history-claude']['estimated_cost_usd'], 0.00156, rel_tol=1e-9)
            assert math.isclose(data['history-gpt']['estimated_cost_usd'], 0.00575, rel_tol=1e-9)
            assert data['history-unknown']['estimated_cost_usd'] is None
            assert data['history-claude']['input_tokens'] == 400
            assert data['history-claude']['latency_ms'] is None
            assert data['history-claude']['failed'] is None
            assert 'overlap' not in data
            assert len(data) == len(rows) + 3
            day_cost = float(query("SELECT sumOrNull(estimated_cost_usd) FROM llm.usage_metrics WHERE requested_at >= now() - INTERVAL 1 DAY", 'grafana').stdout)
            year_cost = float(query("SELECT sumOrNull(estimated_cost_usd) FROM llm.usage_metrics WHERE requested_at >= now() - INTERVAL 1 YEAR", 'grafana').stdout)
            assert math.isclose(year_cost - day_cost, 0.00731, rel_tol=1e-8)

            query("SELECT count() FROM llm.usage_metrics SETTINGS max_execution_time=10", "grafana")
            # The HTTP driver's connection health check uses a 60-second timeout.
            query("SELECT 1 SETTINGS max_execution_time=60", "grafana")
            denied = ["SELECT * FROM llm.usage", "SELECT * FROM llm.requests",
                      "SELECT * FROM llm.request_items", "SELECT * FROM llm.request_bodies",
                      "SELECT * FROM llm.transcripts", "SELECT * FROM llm.historical_usage",
                      "SELECT failure_body FROM llm.usage_metrics",
                      "INSERT INTO llm.usage (request_id) VALUES ('forbidden')",
                      "DROP VIEW llm.usage_metrics", "SET readonly=0",
                      "SELECT 1 SETTINGS max_execution_time=61"]
            for sql in denied:
                result = query(sql, "grafana", check=False)
                assert result.returncode != 0, f"Reader unexpectedly allowed {sql}"

            for title, sql in queries:
                for provider, model, origin in ((None, None, None), ("codex", "gpt-6.1-sol", 'live'),
                                                (None, None, 'history:claude-code'), ("missing", "missing", None)):
                    try:
                        query(expand(sql, provider, model, origin), "grafana")
                    except subprocess.CalledProcessError as error:
                        raise RuntimeError(f"{title}: {error.stderr}") from error
            print(f"PASS: pricing fixtures, token accounting, {len(denied)} permission checks, "
                  f"{len(queries)} dashboard queries with all/specific/empty filters")
            bodies = check_request_items(query, container, config["schema.sql"], temp)
            print(f"PASS: {bodies} request body fixtures through the plugin, the backfill, and the view")

            if args.live:
                # Inline the uninstalled view so production queries remain strictly read-only.
                view = re.search(r"CREATE OR REPLACE VIEW llm\.usage_metrics\s+"
                                 r"DEFINER = default SQL SECURITY DEFINER AS\s+(.*?);",
                                 config["schema.sql"], re.S).group(1)
                for title, sql in queries:
                    live = expand(sql).replace("FROM llm.usage_metrics", f"FROM ({view}) AS metrics")
                    result = run("kubectl", "exec", "-i", "-n", "clickhouse", "clickhouse-0", "--",
                                 "clickhouse-client", "--query", live, check=False)
                    assert result.returncode == 0, f"{title}: {result.stderr}"
                print(f"PASS: {len(queries)} queries against the live archive (read-only)")
        finally:
            run("docker", "rm", "--force", container, check=False)


if __name__ == "__main__":
    main()
