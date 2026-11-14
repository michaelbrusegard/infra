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
            normalizer = temp / "normalize-conversations"
            run("go", "build", "-o", str(normalizer), "./normalize-conversations", cwd=PLUGINS)
            insert("llm.request_items", sources / "llm.request_items.jsonl", "cliproxy")
            insert("llm.transcripts", sources / "llm.transcripts.jsonl")

            def jsonl(path):
                return [json.loads(line) for line in path.read_text().splitlines()]

            # The proxy's rows arrive in two batches, the way the plugin writes
            # requests as they complete. The second holds a delta request and a
            # full resend continuing calls from the first, and claude-agent,
            # which started before requests of the first batch.
            later = {"claude-2", "claude-agent", "codex-2"}
            requests_rows, usage_rows = jsonl(sources / "llm.requests.jsonl"), jsonl(sources / "llm.usage.jsonl")

            def arrive(batch):
                for table, rows, key in (("llm.requests", requests_rows, "request_id"),
                                         ("llm.usage", usage_rows, "request_id")):
                    data = "".join(json.dumps(row) + "\n" for row in rows
                                   if (row[key].removeprefix("usage-") in later) == (batch == 2))
                    query(f"INSERT INTO {table} FORMAT JSONEachRow\n" + data, "cliproxy")

            def load(out):
                for table in ("llm.request_items", "llm.sessions", "llm.messages", "llm.calls", "llm.events"):
                    insert(table, out / f"{table}.jsonl")

            # One run of the job: the requests not normalized yet, the state of
            # the sessions they touch, then the normalizer.
            def job(name):
                out = temp / name
                out.mkdir()
                rows = query((NORMALIZER / "requests.sql").read_text(),
                             params=(("after", "2000-01-01 00:00:00"),)).stdout
                sessions = run(str(normalizer), "-requests", "-sessions", input=rows).stdout.strip()
                state = temp / f"{name}-state.jsonl"
                state.write_text(query((NORMALIZER / "state.sql").read_text(), params=(("sessions", sessions),)).stdout)
                run(str(normalizer), "-requests", "-state", str(state), "-out", str(out), input=rows)
                load(out)
                return [json.loads(row)["request_id"] for row in rows.splitlines()], jsonl(out / "llm.messages.jsonl")

            arrive(1)
            first, first_messages = job("proxy-1")
            arrive(2)
            second, second_messages = job("proxy-2")
            assert sorted(first) == sorted(r["request_id"] for r in requests_rows if r["request_id"] not in later), first
            assert sorted(second) == sorted(later), second
            assert job("proxy-3")[0] == []
            # The second run extended the first run's trees without writing
            # their nodes again, and found the response codex-2 continues.
            written = {m["id"] for m in first_messages}
            assert not [m for m in second_messages if m["id"] in written], second_messages

            # Transcripts once, after the proxy, which owns each session it
            # captured from its first call on.
            proxied = temp / "proxied.tsv"
            proxied.write_text(query("SELECT session_id, response_id, started_at FROM llm.calls FINAL "
                                     "WHERE origin = 'proxy' FORMAT TSV").stdout)
            out = temp / "transcripts"
            out.mkdir()
            run(str(normalizer), "-proxied", str(proxied), "-out", str(out),
                input=query((NORMALIZER / "transcripts.sql").read_text()).stdout)
            load(out)

            def scalar(sql):
                return query(sql).stdout.strip()

            # Proxy calls keep every llm.requests column verbatim, so
            # llm.requests could be dropped. The column list comes from the
            # deployed schema, so a new column there fails this.
            columns = scalar("SELECT groupArray(name) FROM (SELECT name FROM system.columns "
                             "WHERE database = 'llm' AND table = 'requests' ORDER BY position) FORMAT JSONEachRow")
            columns = json.loads(columns)["groupArray(name)"]
            renamed = {"request_id": "call_id", "session_id": "source_session_id", "model": "source_model"}
            source = ", ".join(columns)
            kept = ", ".join(f"{renamed.get(c, c)} AS {c}" for c in columns)
            calls = f"SELECT {kept} FROM llm.calls FINAL WHERE origin = 'proxy'"
            assert len(columns) == 17, columns
            assert scalar(f"SELECT count() FROM (SELECT {source} FROM llm.requests EXCEPT {calls})") == "0"
            assert scalar(f"SELECT count() FROM ({calls} EXCEPT SELECT {source} FROM llm.requests)") == "0"
            assert scalar(f"SELECT count() FROM ({calls})") == "10"
            # Only the unarchived previous response starts at a marker.
            assert scalar("SELECT count() FROM llm.messages FINAL WHERE format = 'proxy'") == "1"
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
            """) == "57\t57"
            # Raw items exist for every row and hash the way the plugin's do.
            assert scalar("""
                SELECT count() FROM (SELECT item FROM llm.messages UNION ALL SELECT item FROM llm.events)
                WHERE item NOT IN (SELECT hash FROM llm.request_items)
            """) == "0"
            assert scalar("SELECT count() FROM llm.request_items "
                          "WHERE hash != reinterpretAsUInt128(substring(SHA256(item), 1, 16))") == "0"
            # Both captured this session. The transcript keeps the line from
            # before the proxy's first call as a message, and the later one
            # as an event; its calls and tokens are the proxy's.
            both = "'claude:11111111-1111-4111-8111-111111111111'"
            assert scalar(f"SELECT arraySort(groupArray(origin)) FROM llm.sessions FINAL WHERE session_id = {both}") \
                == "['proxy','transcript']"
            assert scalar(f"SELECT groupArray(line) FROM llm.messages FINAL WHERE session_id = {both} AND line != ''") \
                == "['1']"
            assert scalar(f"SELECT groupArray(line) FROM llm.events FINAL WHERE session_id = {both}") == "['2']"
            assert scalar(f"SELECT groupUniqArray(origin) FROM llm.calls FINAL WHERE session_id = {both}") == "['proxy']"
            # Pi's proxied calls have only CLIProxy's session. The replies both
            # recorded put the transcript in it, so its replies count once.
            pi = scalar("SELECT session_id FROM llm.calls FINAL WHERE call_id = 'chat-1'")
            assert scalar(f"SELECT arraySort(groupArray(origin)) FROM llm.sessions FINAL WHERE session_id = '{pi}'") \
                == "['proxy','transcript']"
            assert scalar(f"SELECT groupArray(line) FROM llm.messages FINAL WHERE session_id = '{pi}' AND line != ''") \
                == "['2']"
            assert scalar("SELECT count() FROM llm.calls FINAL WHERE response_id IN ('chatcmpl-1', 'chatcmpl-2')") == "2"
            # Grafana keeps seeing only the metrics view.
            for table in ("llm.messages", "llm.calls", "llm.events", "llm.sessions"):
                assert query(f"SELECT * FROM {table}", "grafana", check=False).returncode != 0, table

            sql = examples()
            prompts = query(sql["prompts"]).stdout
            # Both sources hold the first prompt; it counts once.
            assert prompts.count("The nightly backup job fails; find out why.") == 1, prompts
            assert prompts.count("List the flake inputs.") == 1, prompts
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
            # claude-1, claude-2, and the truncated request.
            assert "2026-11-10\tclaude-code\tclaude-opus-5-5\t3\t" in tokens, tokens

            # Three calls share the websocket trace ws-1. Each usage row is
            # priced once, where joining on the trace alone would count it
            # once per call.
            cost = sum(float(line.split("\t")[3]) for line in query(sql["cost"]).stdout.splitlines()
                       if not line.endswith("\\N"))
            live = float(scalar("SELECT sum(estimated_cost_usd) FROM llm.usage_metrics WHERE origin = 'live'"))
            by_trace = float(scalar("SELECT sum(u.estimated_cost_usd) FROM llm.calls AS c FINAL "
                                    "INNER JOIN llm.usage_metrics AS u ON u.trace_id = c.trace_id"))
            assert live > 0 and abs(cost - live) < 1e-9 and by_trace > live, (cost, live, by_trace)

            session = ("session", "claude:11111111-1111-4111-8111-111111111111")
            path = query(sql["conversation"], params=(session,)).stdout
            roles = [(m["role"], m["output"]) for m in map(json.loads, path.splitlines())]
            # The tool result arrives with the user's own text, so it stays a user turn.
            assert roles == [("user", False), ("assistant", True), ("user", False), ("assistant", True)], roles
            exported = json.loads(run(str(normalizer), "-export", "openai", input=path).stdout)
            assert [m["role"] for m in exported["messages"]] == ["user", "assistant", "tool", "user", "assistant"], exported
            assert exported["messages"][1]["tool_calls"][0]["function"]["name"] == "Bash", exported

            # A call exports with what it ran with beside its messages. The
            # delta request codex-2 sent no instructions or tools; its
            # response echoes the tools in effect.
            for call, system, tools in (("claude-2", "You are Claude Code", ["Bash", "Read"]),
                                        ("codex-1", "You are Codex", ["exec", "update_plan"]),
                                        ("codex-2", "", ["exec", "update_plan"])):
                rows = query(sql["call"], params=(("call", call),)).stdout
                openai = json.loads(run(str(normalizer), "-export", "openai", input=rows).stdout)
                anthropic = json.loads(run(str(normalizer), "-export", "anthropic", input=rows).stdout)
                for exported in (openai, anthropic):
                    assert [t.get("function", t)["name"] for t in exported.get("tools", [])] == tools, (call, exported)
                    assert exported["messages"][-1]["role"] == "assistant", (call, exported)
                first = openai["messages"][0]
                assert (first["role"] == "system") == bool(system) and first["content"].startswith(system), (call, first)
                assert anthropic["system"].startswith(system or "<permissions instructions>"), (call, anthropic)

            raw = query(sql["raw"], params=(session,)).stdout
            assert '"cache_control"' in raw and "signature" in raw, raw

            agents = query(sql["subagents"]).stdout
            assert "codex:01a1da81-0000-7000-8000-000000000001\tcodex:01a1da81-0000-7000-8000-000000000001:agent:pricing_review" in agents, agents
            print(f"PASS: {len(sql)} doc examples, lossless proxy and transcript round trips, permissions")
        finally:
            run("docker", "rm", "--force", container, check=False)


if __name__ == "__main__":
    main()
