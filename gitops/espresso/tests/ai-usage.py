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
import re
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "gitops/espresso"
PLUGINS = ROOT / "packages/cliproxy-plugins"


def run(*args, input=None, check=True, **kwargs):
    return subprocess.run(
        args, input=input, text=True, capture_output=True, check=check, **kwargs
    )


def manifest(path):
    return json.loads(run("yq", "-o=json", str(BASE / path)).stdout)


def expand(sql, provider=None, model=None, origin=None):
    for name, value in (("origin", origin), ("provider", provider), ("model", model)):
        condition = f"$__conditionalAll({name} IN (${{{name}:singlequote}}), ${name})"
        sql = sql.replace(
            condition, "1=1" if value is None else f"{name} IN ('{value}')"
        )
    sql = sql.replace(
        "$__timeFilter_ms(requested_at)",
        "requested_at BETWEEN now() - INTERVAL 1 DAY AND now()",
    )
    sql = sql.replace(
        "$__timeInterval_ms(requested_at)",
        "toStartOfInterval(requested_at, INTERVAL 300 SECOND)",
    )
    assert "$" not in sql, sql
    return sql


def same_json(a, b):
    """Compare JSON by value, keeping numerals as written and duplicate keys."""

    def load(text):
        return json.loads(
            text,
            parse_float=lambda n: ("number", n),
            parse_int=lambda n: ("number", n),
            object_pairs_hook=lambda pairs: sorted(pairs, key=repr),
        )

    return load(a) == load(b)


def check_request_items(query, temp):
    """Plugin rows and the view agree on the real schema."""
    fixtures = json.loads((PLUGINS / "requestitems/testdata/bodies.json").read_text())
    dump = temp / "dump"
    dump.mkdir()
    run(
        "go",
        "test",
        "-count=1",
        "./clickhouse-archive",
        "-run",
        "TestRequestRowsMatchTheSplit",
        "-args",
        "-dump",
        str(dump),
        cwd=PLUGINS,
    )
    items = (dump / "llm.request_items.jsonl").read_text()
    requests = (dump / "llm.requests.jsonl").read_text()

    # The plugin's rows, inserted with its own grants.
    query("INSERT INTO llm.request_items FORMAT JSONEachRow\n" + items, "cliproxy")
    query("INSERT INTO llm.requests FORMAT JSONEachRow\n" + requests, "cliproxy")
    for table in ("llm.request_items", "llm.requests", "llm.request_bodies"):
        result = query(f"SELECT * FROM {table}", "cliproxy", check=False)
        assert result.returncode != 0, f"Writer unexpectedly read {table}"

    # Go's hashes are ClickHouse's SHA256 prefix of the stored bytes.
    assert (
        query(
            "SELECT count() FROM llm.request_items "
            "WHERE hash != reinterpretAsUInt128(substring(SHA256(item), 1, 16))"
        ).stdout.strip()
        == "0"
    )
    stored_items = len(items.splitlines())
    assert (
        int(query("SELECT uniqExact(hash) FROM llm.request_items").stdout)
        == stored_items
    )

    rows = query(
        "SELECT request_id, request_body FROM llm.request_bodies FORMAT JSONEachRow"
    ).stdout
    found = {
        r["request_id"]: r["request_body"] for r in map(json.loads, rows.splitlines())
    }
    for f in fixtures:
        body = found[f["name"]]
        try:
            json.loads(f["body"])
            valid = f["body"].lstrip().startswith("{")
        except ValueError:
            valid = False
        assert same_json(body, f["body"]) if valid else body == f["body"], (
            f["name"],
            body,
        )

    # A plugin writing a column the table lacks must fail, not lose the value.
    unknown = json.dumps({"request_id": "unknown-column", "request_body": "{}"})
    rejected = query(
        "INSERT INTO llm.requests FORMAT JSONEachRow\n" + unknown,
        "cliproxy",
        check=False,
    )
    assert rejected.returncode != 0 and "request_body" in rejected.stderr, (
        rejected.stderr
    )
    return len(fixtures)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true")
    args = parser.parse_args()
    config = manifest("apps/clickhouse/configmap.yaml")["data"]
    statefulset = manifest("apps/clickhouse/statefulset.yaml")
    image = statefulset["spec"]["template"]["spec"]["containers"][0]["image"]
    dashboard = json.loads(
        (BASE / "infrastructure/configs/grafana/ai-usage.json").read_text()
    )
    queries = [
        (p["title"], t["rawSql"])
        for p in dashboard["panels"]
        for t in p.get("targets", [])
    ]
    queries += [(v["name"], v["query"]) for v in dashboard["templating"]["list"]]
    container = f"infra-ai-usage-test-{os.getpid()}"
    with tempfile.TemporaryDirectory(prefix="infra-ai-usage-") as directory:
        temp = Path(directory)
        temp.chmod(0o755)
        for name in ("config.xml", "users.xml", "schema.sql"):
            (temp / name).write_text(config[name])
        try:
            run(
                "docker",
                "run",
                "--detach",
                "--name",
                container,
                "--network",
                "none",
                "--memory",
                "2g",
                "--cpus",
                "2",
                "-e",
                "CLICKHOUSE_SKIP_USER_SETUP=1",
                "-v",
                f"{temp}/config.xml:/etc/clickhouse-server/config.d/archive.xml:ro",
                "-v",
                f"{temp}/users.xml:/etc/clickhouse-server/users.d/archive.xml:ro",
                "-v",
                f"{temp}/schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro",
                image,
            )

            def query(sql, user="default", check=True):
                return run(
                    "docker",
                    "exec",
                    "-i",
                    container,
                    "clickhouse-client",
                    "--user",
                    user,
                    "--query",
                    sql,
                    check=check,
                )

            for _ in range(120):
                ready = query("EXISTS TABLE llm.usage_metrics", check=False)
                if ready.returncode == 0 and ready.stdout.strip() == "1":
                    break
                time.sleep(0.5)
            else:
                raise RuntimeError(run("docker", "logs", container).stdout)

            stamp = datetime.datetime.now(datetime.UTC).strftime(
                "%Y-%m-%d %H:%M:%S.000"
            )

            def row(id, model="gpt-6.1-sol", provider="codex", **tokens):
                return {
                    "request_id": id,
                    "trace_id": id,
                    "model": model,
                    "provider": provider,
                    "requested_at": stamp,
                    "auth_type": "oauth",
                    **tokens,
                }

            rows = [
                row(
                    "cached",
                    input_tokens=1000,
                    output_tokens=100,
                    reasoning_tokens=50,
                    cached_tokens=500,
                    cache_read_tokens=500,
                ),
                row(
                    "long",
                    input_tokens=272001,
                    output_tokens=1000,
                    cache_read_tokens=200000,
                ),
                row("threshold", input_tokens=272000),
                row(
                    "claude",
                    "claude-opus-5-5",
                    "claude",
                    input_tokens=100,
                    cache_read_tokens=2000,
                    output_tokens=25,
                ),
                row(
                    "cache-write",
                    "claude-opus-5-5",
                    "claude",
                    input_tokens=100,
                    cached_tokens=1000,
                    cache_creation_tokens=1000,
                    output_tokens=25,
                ),
                row(
                    "unknown",
                    "future-model",
                    "codex",
                    input_tokens=1000,
                    output_tokens=100,
                ),
                row("limited", failed=True, failure_status=429),
                row("astra", "gpt-6-astra", input_tokens=1000, output_tokens=100),
                row("luna", "gpt-6-luna", input_tokens=1000, output_tokens=100),
            ]
            query(
                "INSERT INTO llm.usage FORMAT JSONEachRow\n"
                + "\n".join(map(json.dumps, rows))
            )
            old_stamp = (
                datetime.datetime.now(datetime.UTC) - datetime.timedelta(days=90)
            ).strftime("%Y-%m-%d %H:%M:%S.000")

            # History before the proxy is the transcript calls with usage, as
            # llm.call_history reads them; proxy calls and empty ones are not.
            def call(
                id, client, model, started_at=old_stamp, origin="transcript", **tokens
            ):
                return {
                    "call_id": id,
                    "session_id": f"{client}:s",
                    "started_at": started_at,
                    "origin": origin,
                    "client": client,
                    "model": model,
                    **tokens,
                }

            calls = [
                call(
                    "history-claude",
                    "claude-code",
                    "claude-opus-5-5",
                    uncached_input_tokens=100,
                    cache_read_tokens=200,
                    cache_write_tokens=100,
                    cache_write_5m_tokens=60,
                    cache_write_1h_tokens=40,
                    output_tokens=25,
                ),
                call(
                    "history-gpt",
                    "codex",
                    "gpt-5.5",
                    uncached_input_tokens=500,
                    cache_read_tokens=500,
                    output_tokens=100,
                ),
                call(
                    "history-unknown",
                    "pi",
                    "future-model",
                    uncached_input_tokens=100,
                    output_tokens=10,
                ),
                call(
                    "overlap",
                    "pi",
                    "gpt-6.1-sol",
                    stamp,
                    uncached_input_tokens=999999999,
                ),
                call("transcript-empty", "pi", "kimi-k3.1-pro"),
                call(
                    "proxy-call",
                    "claude-code",
                    "claude-opus-5-5",
                    origin="proxy",
                    output_tokens=1,
                ),
            ]
            # Reruns may add physical rows, but must never increase dashboard totals.
            for _ in range(2):
                query(
                    "INSERT INTO llm.calls FORMAT JSONEachRow\n"
                    + "\n".join(map(json.dumps, calls))
                )
            values = [
                json.loads(line)
                for line in query(
                    "SELECT * FROM llm.usage_metrics FORMAT JSONEachRow", "grafana"
                ).stdout.splitlines()
            ]
            data = {r["trace_id"]: r for r in values}
            for id, expected in (
                ("cached", 0.00205),
                ("long", 0.343004),
                ("threshold", 0.544),
                ("claude", 0.0013),
                ("astra", 0.015),
                ("luna", 0.00015),
            ):
                assert math.isclose(
                    data[id]["estimated_cost_usd"], expected, rel_tol=1e-9
                ), data[id]
            assert data["cached"]["total_tokens"] == 1100  # reasoning is a subset
            assert (
                data["cached"]["uncached_input_tokens"] == 500
            )  # cache fields are aliases
            assert data["claude"]["input_tokens"] == 2100  # Claude cache is independent
            assert (
                data["cache-write"]["cache_read_tokens"] == 0
            )  # cached_tokens may mean writes
            assert data["cache-write"]["estimated_cost_usd"] is None
            assert data["unknown"]["estimated_cost_usd"] is None
            assert math.isclose(
                data["history-claude"]["estimated_cost_usd"], 0.00156, rel_tol=1e-9
            )
            assert math.isclose(
                data["history-gpt"]["estimated_cost_usd"], 0.00575, rel_tol=1e-9
            )
            assert data["history-unknown"]["estimated_cost_usd"] is None
            assert data["history-claude"]["input_tokens"] == 400
            assert data["history-claude"]["origin"] == "history:claude-code"
            assert data["history-claude"]["latency_ms"] is None
            assert data["history-claude"]["failed"] is None
            assert "overlap" not in data
            assert len(data) == len(rows) + 3
            day_cost = float(
                query(
                    "SELECT sumOrNull(estimated_cost_usd) FROM llm.usage_metrics WHERE requested_at >= now() - INTERVAL 1 DAY",
                    "grafana",
                ).stdout
            )
            year_cost = float(
                query(
                    "SELECT sumOrNull(estimated_cost_usd) FROM llm.usage_metrics WHERE requested_at >= now() - INTERVAL 1 YEAR",
                    "grafana",
                ).stdout
            )
            assert math.isclose(year_cost - day_cost, 0.00731, rel_tol=1e-8)

            query(
                "SELECT count() FROM llm.usage_metrics SETTINGS max_execution_time=10",
                "grafana",
            )
            # The HTTP driver's connection health check uses a 60-second timeout.
            query("SELECT 1 SETTINGS max_execution_time=60", "grafana")
            denied = [
                "SELECT * FROM llm.usage",
                "SELECT * FROM llm.requests",
                "SELECT * FROM llm.request_items",
                "SELECT * FROM llm.request_bodies",
                "SELECT * FROM llm.calls",
                "SELECT * FROM llm.messages",
                "SELECT * FROM llm.call_history",
                "SELECT failure_body FROM llm.usage_metrics",
                "INSERT INTO llm.usage (request_id) VALUES ('forbidden')",
                "DROP VIEW llm.usage_metrics",
                "SET readonly=0",
                "SELECT 1 SETTINGS max_execution_time=61",
            ]
            for sql in denied:
                result = query(sql, "grafana", check=False)
                assert result.returncode != 0, f"Reader unexpectedly allowed {sql}"

            for title, sql in queries:
                for provider, model, origin in (
                    (None, None, None),
                    ("codex", "gpt-6.1-sol", "live"),
                    (None, None, "history:claude-code"),
                    ("missing", "missing", None),
                ):
                    try:
                        query(expand(sql, provider, model, origin), "grafana")
                    except subprocess.CalledProcessError as error:
                        raise RuntimeError(f"{title}: {error.stderr}") from error
            print(
                f"PASS: pricing fixtures, token accounting, {len(denied)} permission checks, "
                f"{len(queries)} dashboard queries with all/specific/empty filters"
            )
            bodies = check_request_items(query, temp)
            print(
                f"PASS: {bodies} request body fixtures through the plugin and the view"
            )

            if args.live:
                # Inline the uninstalled view so production queries remain strictly read-only.
                view = re.search(
                    r"CREATE OR REPLACE VIEW llm\.usage_metrics\s+"
                    r"DEFINER = default SQL SECURITY DEFINER AS\s+(.*?);",
                    config["schema.sql"],
                    re.DOTALL,
                ).group(1)
                for title, sql in queries:
                    live = expand(sql).replace(
                        "FROM llm.usage_metrics", f"FROM ({view}) AS metrics"
                    )
                    result = run(
                        "kubectl",
                        "exec",
                        "-i",
                        "-n",
                        "clickhouse",
                        "clickhouse-0",
                        "--",
                        "clickhouse-client",
                        "--query",
                        live,
                        check=False,
                    )
                    assert result.returncode == 0, f"{title}: {result.stderr}"
                print(
                    f"PASS: {len(queries)} queries against the live archive (read-only)"
                )
        finally:
            run("docker", "rm", "--force", container, check=False)


if __name__ == "__main__":
    main()
