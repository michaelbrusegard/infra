#!/usr/bin/env python3
"""Test the canonical conversation prototype against a real ClickHouse.

Inserts the fixtures as source rows, normalizes them from there the way the
normalizer job would, and runs the example queries from
docs/llm-conversations.md. Nothing touches the cluster.

Run with `nix develop --command python3 gitops/espresso/tests/llm-conversations.py`.
Requires Docker and Go.
"""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "gitops/espresso"
PLUGINS = ROOT / "packages/cliproxy-plugins"
NORMALIZER = PLUGINS / "normalize-conversations"
DOC = ROOT / "docs/llm-conversations.md"
# The fixtures are from November 2026; pin "now" so the examples stay stable.
NOW = "toDateTime64('2026-11-14 00:00:00', 3, 'UTC')"


def run(*args, input=None, check=True, **kwargs):
    return subprocess.run(args, input=input, text=True, capture_output=True, check=check, **kwargs)


def examples():
    """The ```sql blocks of the design doc that start with `-- example: <name>`."""
    found = {}
    for block in re.findall(r"```sql\n(.*?)```", DOC.read_text(), re.S):
        match = re.match(r"-- example: (\S+)", block)
        if match:
            found[match.group(1)] = block.replace("now()", NOW)
    return found


def main():
    config = json.loads(run("yq", "-o=json", str(BASE / "apps/clickhouse/configmap.yaml")).stdout)["data"]
    statefulset = json.loads(run("yq", "-o=json", str(BASE / "apps/clickhouse/statefulset.yaml")).stdout)
    image = statefulset["spec"]["template"]["spec"]["containers"][0]["image"]
    schema = config["schema.sql"] + "\n" + (NORMALIZER / "schema.sql").read_text()
    container = f"infra-llm-conversations-test-{os.getpid()}"
    with tempfile.TemporaryDirectory(prefix="infra-llm-conversations-") as directory:
        temp = Path(directory)
        temp.chmod(0o755)
        for name, text in (("config.xml", config["config.xml"]), ("users.xml", config["users.xml"]),
                           ("schema.sql", schema)):
            (temp / name).write_text(text)
        try:
            run("docker", "run", "--detach", "--name", container, "--network", "none",
                "--memory", "2g", "--cpus", "2", "-e", "CLICKHOUSE_SKIP_USER_SETUP=1",
                "-v", f"{temp}/config.xml:/etc/clickhouse-server/config.d/archive.xml:ro",
                "-v", f"{temp}/users.xml:/etc/clickhouse-server/users.d/archive.xml:ro",
                "-v", f"{temp}/schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro", image)

            def query(sql, user="default", check=True, params=()):
                args = ["docker", "exec", "-i", container, "clickhouse-client", "--user", user]
                for name, value in params:
                    args.append(f"--param_{name}={value}")
                return run(*args, input=sql, check=check)

            def insert(table, path, user="default"):
                data = path.read_text() if path.exists() else ""
                if data:
                    query(f"INSERT INTO {table} FORMAT JSONEachRow\n" + data, user)

            for _ in range(120):
                ready = query("EXISTS TABLE llm.events", check=False)
                if ready.returncode == 0 and ready.stdout.strip() == "1":
                    break
                time.sleep(0.5)
            else:
                raise RuntimeError(run("docker", "logs", container).stdout)

            # Source rows: the plugin's, with its grants, and the backfill's.
            sources = temp / "sources"
            sources.mkdir()
            run("go", "test", "-count=1", "./conversations", "-run", "TestDumpSources",
                "-args", "-dump", str(sources), cwd=PLUGINS)
            for table in ("llm.request_items", "llm.requests", "llm.usage"):
                insert(table, sources / f"{table}.jsonl", "cliproxy")
            insert("llm.transcripts", sources / "llm.transcripts.jsonl")

            # Normalize requests first, so transcripts know the proxy's sessions.
            def normalize(sql, out, *flags, params=()):
                out.mkdir()
                rows = query(sql, params=params).stdout
                run("go", "run", "./normalize-conversations", "-out", str(out), *flags, input=rows, cwd=PLUGINS)
                for table in ("llm.request_items", "llm.sessions", "llm.messages", "llm.calls", "llm.events"):
                    insert(table, out / f"{table}.jsonl")
                return rows

            requests = normalize((NORMALIZER / "requests.sql").read_text(), temp / "proxy", "-requests",
                                 params=(("after", "2000-01-01 00:00:00"), ("before", "2100-01-01 00:00:00")))
            assert len(requests.splitlines()) == 10, requests
            proxied = temp / "proxied.txt"
            proxied.write_text(query("SELECT DISTINCT session_id FROM llm.calls WHERE origin = 'proxy'").stdout)
            normalize((NORMALIZER / "transcripts.sql").read_text(), temp / "transcripts", "-proxied", str(proxied))

            def scalar(sql):
                return query(sql).stdout.strip()

            # Proxy calls keep every column the request bodies and responses
            # are rebuilt from, so llm.requests could be dropped.
            assert scalar("""
                SELECT count() FROM llm.requests AS r INNER JOIN llm.calls AS c FINAL ON c.call_id = r.request_id
                WHERE c.request_envelope = r.request_envelope AND c.request_parts = r.request_parts
                    AND c.response_body = r.response_body AND c.trace_id = r.trace_id
                    AND c.started_at = r.started_at AND c.user_agent = r.user_agent AND c.outcome = r.outcome
            """) == "10"
            # Every transcript row is referenced by exactly one message or
            # event with its exact line, so llm.transcripts could be dropped.
            assert scalar("""
                WITH refs AS (
                    SELECT item, line, count() AS n FROM (
                        SELECT item, line FROM llm.messages FINAL WHERE format NOT IN ('anthropic', 'openai-responses', 'openai-chat', 'proxy')
                        UNION ALL SELECT item, line FROM llm.events FINAL)
                    GROUP BY item, line)
                SELECT countIf(r.n = 1), count() FROM llm.transcripts AS t
                LEFT JOIN refs AS r ON r.item = reinterpretAsUInt128(substring(SHA256(t.line), 1, 16)) AND r.line = t.id
            """) == "50\t50"
            # Raw items exist for every row and hash the way the plugin's do.
            assert scalar("""
                SELECT count() FROM (SELECT item FROM llm.messages UNION ALL SELECT item FROM llm.events)
                WHERE item NOT IN (SELECT hash FROM llm.request_items)
            """) == "0"
            assert scalar("SELECT count() FROM llm.request_items "
                          "WHERE hash != reinterpretAsUInt128(substring(SHA256(item), 1, 16))") == "0"
            # The proxy owns the session both captured.
            assert scalar("SELECT arraySort(groupArray(origin)) FROM llm.sessions FINAL "
                          "WHERE session_id = 'claude:11111111-1111-4111-8111-111111111111'") == "['proxy','transcript']"
            assert scalar("SELECT count() FROM llm.messages FINAL WHERE session_id = "
                          "'claude:11111111-1111-4111-8111-111111111111' AND line != ''") == "0"
            # Grafana keeps seeing only the metrics view.
            for table in ("llm.messages", "llm.calls", "llm.events", "llm.sessions"):
                assert query(f"SELECT * FROM {table}", "grafana", check=False).returncode != 0, table

            sql = examples()
            prompts = query(sql["prompts"]).stdout
            assert "The nightly backup job fails; find out why." in prompts, prompts
            assert "Why does the dashboard show no cost for luna?" in prompts, prompts
            assert "Add a Renovate rule" not in prompts, prompts  # July, not last week
            assert "permissions instructions" not in prompts, prompts

            failures = [line.split("\t") for line in query(sql["tool-failures"]).stdout.splitlines()]
            failures = {(model, tool): (int(uses), int(failed)) for model, tool, uses, failed in failures}
            assert failures[("claude-opus-5-5", "Bash")] == (1, 1), failures
            assert failures[("gpt-5.6-sol", "bash")] == (1, 1), failures
            assert failures[("gpt-5.5", "read")] == (1, 1), failures
            assert failures[("gpt-6.1-sol", "exec")] == (1, 0), failures

            tokens = query(sql["tokens"]).stdout
            assert "2026-11-10\tclaude-code\tclaude-opus-5-5\t2\t" in tokens, tokens

            session = ("session", "claude:11111111-1111-4111-8111-111111111111")
            path = query(sql["conversation"], params=(session,)).stdout
            roles = [(m["role"], m["output"]) for m in map(json.loads, path.splitlines())]
            # The tool result arrives with the user's own text, so it stays a user turn.
            assert roles == [("user", False), ("assistant", True), ("user", False), ("assistant", True)], roles
            exported = json.loads(run("go", "run", "./normalize-conversations", "-export", "openai",
                                      input=path, cwd=PLUGINS).stdout)
            assert [m["role"] for m in exported["messages"]] == ["user", "assistant", "tool", "user", "assistant"], exported
            assert exported["messages"][1]["tool_calls"][0]["function"]["name"] == "Bash", exported

            raw = query(sql["raw"], params=(session,)).stdout
            assert '"cache_control"' in raw and "signature" in raw, raw

            agents = query(sql["subagents"]).stdout
            assert "codex:01a1da81-0000-7000-8000-000000000001\tcodex:01a1da81-0000-7000-8000-000000000001:agent:pricing_review" in agents, agents
            print(f"PASS: {len(sql)} doc examples, lossless proxy and transcript round trips, permissions")
        finally:
            run("docker", "rm", "--force", container, check=False)


if __name__ == "__main__":
    main()
