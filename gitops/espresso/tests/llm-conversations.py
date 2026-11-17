#!/usr/bin/env python3
"""Test the canonical conversation prototype against a real ClickHouse.

Inserts the fixtures as source rows, normalizes them from there the way the
normalizer job would, adds rows as the one-off transcript import left them,
and runs the example queries in normalize-conversations/queries. Nothing
touches the cluster.

Run with `nix develop --command python3 gitops/espresso/tests/llm-conversations.py`.
Requires Docker and Go.
"""

from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "gitops/espresso"
PLUGINS = ROOT / "packages/cliproxy-plugins"
NORMALIZER = PLUGINS / "normalize-conversations"
# The fixtures are from November 2026; pin "now" so the examples stay stable.
NOW = "toDateTime64('2026-11-14 00:00:00', 3, 'UTC')"
# llm_normalizer's password, which the cluster reads from a secret.
PASSWORD = secrets.token_hex(16)


# Rows the one-off transcript import left in the canonical tables, which
# hold their own content: no raw source names them any more. A Claude Code
# call with the system prompt and tools of its request log as items, a Codex
# call whose transcript recorded no tools, a Pi compaction, which has no
# outputs, and a prompt the proxy later sent again in the same session.
SYSTEM = json.dumps([{"type": "text", "text": "You are Claude Code."}])
TOOLS = json.dumps([{"name": "Bash", "description": "Run a command.", "input_schema": {"type": "object"}},
                    {"name": "Read", "description": "Read a file.", "input_schema": {"type": "object"}}])


def item_hash(item):
    """llm.request_items' hash: reinterpretAsUInt128(substring(SHA256(item), 1, 16))."""
    return str(int.from_bytes(hashlib.sha256(item.encode()).digest()[:16], "little"))


def transcript_rows():
    claude = ".claude/projects/-Users-michaelbrusegard-Projects-infra/"
    files = {
        "claude:22222222-2222-4222-8222-222222222222": ("claude-code", claude + "22222222-2222-4222-8222-222222222222.jsonl"),
        "claude:11111111-1111-4111-8111-111111111111": ("claude-code", claude + "11111111-1111-4111-8111-111111111111.jsonl"),
        "codex:019f6478-0000-7000-8000-000000000003": (
            "codex", ".codex/sessions/2026/07/15/rollout-2026-07-15T14-09-54-019f6478-0000-7000-8000-000000000003.jsonl"),
        "pi:01a039ec-0000-7000-8000-000000000005": (
            "pi", ".pi/agent/sessions/2026-08-25T17-16-23-878Z_01a039ec-0000-7000-8000-000000000005.jsonl"),
    }

    def message(session, id, parent, seq, ts, role, blocks, output=False, model="", call=""):
        _, path = files[session]
        return {"session_id": session, "id": id, "parent_id": parent, "seq": seq, "ts": ts, "role": role,
                "output": output, "model": model, "call_id": call, "blocks": blocks, "format": files[session][0],
                "host": "lungo", "path": path, "line": str(seq + 1)}

    def text(t):
        return {"type": "text", "source_type": "text", "text": t}

    def tool_call(name, id, input):
        return {"type": "tool_call", "source_type": "tool_use", "tool_name": name, "tool_call_id": id, "tool_input": input}

    def call(session, id, started, model, input, outputs, context=(), **tokens):
        client, path = files[session]
        return {"call_id": id, "session_id": session, "started_at": started, "completed_at": started,
                "origin": "transcript", "client": client, "host": "lungo", "path": path, "model": model,
                "input_id": input, "output_ids": outputs, "context": list(context), **tokens}

    cc, cx, pi = list(files)[0], list(files)[2], list(files)[3]
    return {
        "llm.request_items": [{"hash": item_hash(i), "item": i} for i in (SYSTEM, TOOLS)],
        "llm.sessions": [{"session_id": s, "client": c, "origin": "transcript", "host": "lungo", "path": p}
                         for s, (c, p) in files.items()],
        "llm.messages": [
            message(cc, "101", "0", 0, "2026-10-01 09:00:00.000", "user", [text("Why is the ingress returning 502?")]),
            message(cc, "102", "101", 1, "2026-10-01 09:00:05.000", "assistant",
                    [tool_call("Bash", "toolu_t1", '{"command":"kubectl -n ingress logs deploy/traefik"}')],
                    output=True, model="claude-opus-5", call="req_011"),
            message(list(files)[1], "111", "0", 0, "2026-11-10 08:59:00.000", "user",
                    [text("The nightly backup job fails; find out why.")]),
            message(cx, "201", "0", 0, "2026-07-15 14:09:54.865", "user", [text("Add a Renovate rule for flake inputs.")]),
            message(cx, "202", "201", 1, "2026-07-15 14:10:00.000", "assistant",
                    [tool_call("exec", "call_t1", '{"cmd":"ls"}')], output=True, model="gpt-5.5", call="codex-t1"),
            message(pi, "301", "0", 0, "2026-08-25 17:16:30.000", "user", [text("Run the tofu approval test.")]),
        ],
        "llm.calls": [
            call(cc, "req_011", "2026-10-01 09:00:01.000", "claude-opus-5", "101", ["102"],
                 [{"field": "system", "position": 0, "hash": item_hash(SYSTEM)},
                  {"field": "tools", "position": 0, "hash": item_hash(TOOLS)}],
                 uncached_input_tokens=10, cache_write_tokens=2000, cache_write_1h_tokens=2000, output_tokens=64),
            call(cx, "codex-t1", "2026-07-15 14:09:55.000", "gpt-5.5", "201", ["202"],
                 uncached_input_tokens=8000, output_tokens=100),
            call(pi, "c1", "2026-08-25 18:00:00.000", "gpt-5.6-sol", "301", [],
                 uncached_input_tokens=180000, cache_read_tokens=10000, output_tokens=900),
        ],
    }


def insert_transcript_rows(query):
    for table, rows in transcript_rows().items():
        query(f"INSERT INTO {table} FORMAT JSONEachRow\n" + "".join(json.dumps(r) + "\n" for r in rows))


def run(*args, input=None, check=True, **kwargs):
    result = subprocess.run(args, input=input, text=True, capture_output=True, **kwargs)
    if check and result.returncode != 0:
        raise RuntimeError(f"{args[-3:]} failed:\n{result.stderr}")
    return result


def examples():
    """The example queries by name, with "now" pinned."""
    return {f.stem: f.read_text().replace("now()", NOW) for f in (NORMALIZER / "queries").glob("*.sql")}


def check_password_guard(image, command):
    """The server refuses to start without the normalizer's password, which
    ClickHouse would otherwise treat as no password at all."""
    for env in ([], ["-e", "LLM_NORMALIZER_PASSWORD="]):
        refused = run("docker", "run", "--rm", "--network", "none", *env,
                      "--entrypoint", command[0], image, *command[1:], check=False)
        assert refused.returncode != 0 and "refusing to start" in refused.stderr, (env, refused)


def main():
    config = json.loads(run("yq", "-o=json", str(BASE / "apps/clickhouse/configmap.yaml")).stdout)["data"]
    statefulset = json.loads(run("yq", "-o=json", str(BASE / "apps/clickhouse/statefulset.yaml")).stdout)
    server = statefulset["spec"]["template"]["spec"]["containers"][0]
    image, command = server["image"], server["command"]
    check_password_guard(image, command)
    schema = config["schema.sql"]
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
                "-e", f"LLM_NORMALIZER_PASSWORD={PASSWORD}",
                "-v", f"{temp}/config.xml:/etc/clickhouse-server/config.d/archive.xml:ro",
                "-v", f"{temp}/users.xml:/etc/clickhouse-server/users.d/archive.xml:ro",
                "-v", f"{temp}/schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro",
                "--entrypoint", command[0], image, *command[1:])

            def query(sql, user="default", check=True, params=()):
                args = ["docker", "exec", "-i", container, "clickhouse-client", "--user", user]
                for name, value in params:
                    args.append(f"--param_{name}={value}")
                return run(*args, input=sql, check=check)

            def scalar(sql):
                return query(sql).stdout.strip()

            def insert(table, path, user="default"):
                data = path.read_text() if path.exists() else ""
                if data:
                    query(f"INSERT INTO {table} FORMAT JSONEachRow\n" + data, user)

            for _ in range(120):
                ready = query("EXISTS TABLE llm.usage_metrics", check=False)
                if ready.returncode == 0 and ready.stdout.strip() == "1":
                    break
                time.sleep(0.5)
            else:
                raise RuntimeError(run("docker", "logs", container).stdout)

            # Source rows, the plugin's, with its grants.
            sources = temp / "sources"
            sources.mkdir()
            run("go", "test", "-count=1", "./conversations", "-run", "TestDumpSources",
                "-args", "-dump", str(sources), cwd=PLUGINS)
            normalizer = temp / "normalize-conversations"
            run("go", "build", "-o", str(normalizer), "./normalize-conversations", cwd=PLUGINS)
            insert("llm.request_items", sources / "llm.request_items.jsonl", "cliproxy")

            def jsonl(path):
                return [json.loads(line) for line in path.read_text().splitlines()]

            # The proxy's rows arrive in two batches, the way the plugin writes
            # requests as they complete. The second holds a delta request and a
            # full resend continuing calls from the first, and claude-agent,
            # which started before requests of the first batch.
            later = {"claude-2", "claude-agent", "codex-2"}
            requests_rows, usage_rows = jsonl(sources / "llm.requests.jsonl"), jsonl(sources / "llm.usage.jsonl")

            def arrive(batch, tables=("llm.requests", "llm.usage")):
                for table, rows, key in (("llm.requests", requests_rows, "request_id"),
                                         ("llm.usage", usage_rows, "request_id")):
                    if table not in tables:
                        continue
                    data = "".join(json.dumps(row) + "\n" for row in rows
                                   if (row[key].removeprefix("usage-") in later) == (batch == 2))
                    query(f"INSERT INTO {table} FORMAT JSONEachRow\n" + data, "cliproxy")

            canonical = ("llm.request_items", "llm.sessions", "llm.messages", "llm.calls")

            def load(out):
                for table in canonical:
                    insert(table, out / f"{table}.jsonl")

            # The normalizer never changes the proxy's raw capture. It adds
            # items only for call context a request did not store as items.
            def checksums():
                return [scalar(f"SELECT count(), sum(cityHash64(*)) FROM {table}") for table in (
                    "llm.requests",
                    "llm.request_items FINAL WHERE hash IN (SELECT part.hash FROM llm.requests "
                    "ARRAY JOIN request_parts AS part)")]

            # One run of the job: the requests not normalized yet, the state of
            # the sessions they touch, then the normalizer.
            def job(name, hold="10m"):
                out = temp / name
                out.mkdir()
                rows = query((NORMALIZER / "requests.sql").read_text(),
                             params=(("after", "2000-01-01 00:00:00"), ("before", "2100-01-01 00:00:00"))).stdout
                # Each item the normalizer reads is sent once a run.
                sent = [item for row in rows.splitlines() for item in json.loads(row)["items"] if item]
                assert len(sent) == len(set(sent)), "an item was sent twice"
                sessions = run(str(normalizer), "-requests", "-sessions", input=rows).stdout.strip()
                state = temp / f"{name}-state.jsonl"
                state.write_text(query((NORMALIZER / "state.sql").read_text(), params=(("sessions", sessions),)).stdout)
                run(str(normalizer), "-requests", "-hold", hold, "-state", str(state), "-out", str(out), input=rows)
                load(out)
                return [json.loads(row)["request_id"] for row in rows.splitlines()], jsonl(out / "llm.messages.jsonl")

            arrive(1)
            first, first_messages = job("proxy-1")
            # The plugin writes requests before CLIProxy writes their usage. A
            # run in between, while they are recent, holds them back rather
            # than put claude-agent in its parent's session for good.
            arrive(2, ["llm.requests"])
            recent = f"{int(time.time() - datetime(2026, 11, 10, 8, tzinfo=timezone.utc).timestamp())}s"
            assert sorted(job("proxy-2-early", recent)[0]) == sorted(later)
            assert scalar("SELECT count() FROM llm.calls") == str(len(first)), "placed requests without usage"
            arrive(2, ["llm.usage"])
            before = checksums()
            second, second_messages = job("proxy-2")
            assert sorted(first) == sorted(r["request_id"] for r in requests_rows if r["request_id"] not in later), first
            assert sorted(second) == sorted(later), second
            assert scalar("SELECT session_id FROM llm.calls FINAL WHERE call_id = 'claude-agent'") \
                == "claude:11111111-1111-4111-8111-111111111111:agent:a1b2c3d4e5f6a7b8c"
            assert job("proxy-3")[0] == []
            # The second run extended the first run's trees without writing
            # their nodes again, and found the response codex-2 continues.
            written = {m["id"] for m in first_messages}
            assert not [m for m in second_messages if m["id"] in written], second_messages

            assert checksums() == before, "normalizing changed the raw capture"

            # The dashboard's history before the proxy is the transcript
            # calls', through llm.call_history.
            history = "SELECT trace_id, origin, input_tokens, output_tokens, estimated_cost_usd FROM llm.usage_metrics " \
                      "WHERE origin LIKE 'history:%' ORDER BY trace_id FORMAT JSONEachRow"
            assert query(history, "grafana").stdout == ""
            insert_transcript_rows(query)

            # Every request is exactly one proxy call, which names it, and no
            # call names a missing request.
            calls = "SELECT request_id FROM llm.calls FINAL WHERE origin = 'proxy'"
            assert scalar(f"SELECT count() FROM ({calls})") == scalar("SELECT count() FROM llm.requests") == "10"
            assert scalar(f"SELECT count() FROM (SELECT request_id FROM llm.requests EXCEPT {calls})") == "0"
            assert scalar(f"SELECT count() FROM ({calls} EXCEPT SELECT request_id FROM llm.requests)") == "0"
            # Only the unarchived previous response starts at a marker.
            assert scalar("SELECT count() FROM llm.messages FINAL WHERE format = 'proxy'") == "1"
            # Every proxy message's raw source resolves: an input's item, which
            # its call's request sent, and an output's call.
            assert scalar("""
                SELECT count() FROM llm.messages FINAL
                WHERE item != 0 AND ((call_id, item) NOT IN (
                        SELECT request_id, part.hash FROM llm.requests ARRAY JOIN request_parts AS part)
                    OR item NOT IN (SELECT hash FROM llm.request_items))
            """) == "0"
            assert scalar("SELECT countIf(item != 0) > 0 FROM llm.messages") == "1"
            assert scalar("""
                SELECT count() FROM llm.messages FINAL
                WHERE path = '' AND output AND call_id NOT IN (SELECT request_id FROM llm.requests)
            """) == "0"
            assert scalar("SELECT count() FROM (SELECT arrayJoin(context).hash AS hash FROM llm.calls) "
                          "WHERE hash NOT IN (SELECT hash FROM llm.request_items)") == "0"
            assert scalar("SELECT count() FROM llm.request_items "
                          "WHERE hash != reinterpretAsUInt128(substring(SHA256(item), 1, 16))") == "0"
            # Grafana keeps seeing only the metrics view.
            for table in ("llm.messages", "llm.calls", "llm.events", "llm.sessions", "llm.call_history"):
                assert query(f"SELECT * FROM {table}", "grafana", check=False).returncode != 0, table

            # Each transcript call with usage before the proxy is one row,
            # priced as the proxy's are: the Claude Code call wrote 2,000
            # tokens to the one-hour cache.
            def history_rows():
                return {r["trace_id"]: r for r in map(json.loads, query(history, "grafana").stdout.splitlines())}

            def expected_history():
                return sorted(scalar("SELECT groupArray(event_id) FROM llm.call_history WHERE requested_at < "
                                     "(SELECT min(requested_at) FROM llm.usage)").strip("[]").replace("'", "").split(","))

            rows = history_rows()
            assert sorted(rows) == expected_history() == ["c1", "codex-t1", "req_011"], rows
            assert rows["req_011"]["origin"] == "history:claude-code" and rows["req_011"]["input_tokens"] == 2010, rows
            assert abs(rows["req_011"]["estimated_cost_usd"] - (10 * 5 + 2000 * 10 + 64 * 25) / 1e6) < 1e-12, rows

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
                                    "INNER JOIN llm.requests AS r ON r.request_id = c.request_id "
                                    "INNER JOIN llm.usage_metrics AS u ON u.trace_id = r.trace_id"))
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
                    names = [(t.get("function") or t.get("custom") or t)["name"] for t in exported.get("tools", [])]
                    assert names == tools, (call, exported)
                    assert exported["messages"][-1]["role"] == "assistant", (call, exported)
                # Only the call's own output is a target; earlier turns are
                # context.
                weights = [m.get("weight") for m in openai["messages"] if m["role"] == "assistant"]
                assert weights[-1] is None and all(w == 0 for w in weights[:-1]), (call, weights)
                if call == "codex-1":
                    # The freeform exec tool and its call agree in each dialect.
                    assert openai["tools"][0]["type"] == "custom", openai["tools"]
                    assert openai["messages"][-1]["tool_calls"][0]["type"] == "custom", openai["messages"]
                    assert anthropic["messages"][-1]["content"][-1]["input"] == {
                        "input": "const r = await tools.exec_command({cmd: 'rg luna'});\ntext(r)"}, anthropic["messages"]
                first = openai["messages"][0]
                assert (first["role"] == "system") == bool(system) and first["content"].startswith(system), (call, first)
                assert anthropic["system"].startswith(system or "<permissions instructions>"), (call, anthropic)

            # A transcript call whose transcript records no tools is refused
            # rather than exported with its tool calls undefined, and so is a
            # call without outputs, such as a Pi compaction: the call query
            # marks its rows as a call's even without context or outputs.
            for call, reason in (("codex-t1", "does not define"), ("c1", "no output")):
                rows = query(sql["call"], params=(("call", call),)).stdout
                failed = run(str(normalizer), "-export", "openai", input=rows, check=False)
                assert failed.returncode != 0 and reason in failed.stderr, (call, failed)

            # The truncated request produced nothing, so it is no training
            # example, and the export says why instead of writing one.
            rows = query(sql["call"], params=(("call", "truncated"),)).stdout
            failed = run(str(normalizer), "-export", "openai", input=rows, check=False)
            assert failed.returncode != 0 and "no output" in failed.stderr, failed

            raw = query(sql["raw"], params=(session,)).stdout
            # The request items and a response body.
            assert '"cache_control"' in raw and "signature_delta" in raw, raw

            # The Claude Code transcript call exports as a training example
            # with the system prompt and tools of its context.
            rows = query(sql["call"], params=(("call", "req_011"),)).stdout
            anthropic = json.loads(run(str(normalizer), "-export", "anthropic", input=rows).stdout)
            assert anthropic["system"].startswith("You are Claude Code") \
                and [t["name"] for t in anthropic["tools"]] == ["Bash", "Read"], anthropic

            agents = query(sql["subagents"]).stdout
            assert "codex:01a1da81-0000-7000-8000-000000000001\tcodex:01a1da81-0000-7000-8000-000000000001:agent:pricing_review" in agents, agents

            # In trace ws-tight, call A spans 0-30 ms and B starts at 40 ms, so
            # A's attempt at 0 ms is also within B's 50 ms of slack, and B's
            # attempt at 35 ms only within the slack. Each attempt still
            # belongs to exactly one call, for its session and its cost.
            base = "2026-11-10 13:00:00"
            for call, started, completed, attempt in (("tight-a", ".000", ".030", ".000"),
                                                      ("tight-b", ".040", ".070", ".035")):
                body = json.dumps({"type": "response.completed", "response": {
                    "id": f"resp_{call}", "object": "response", "model": "gpt-6.1-sol", "output": [],
                    "usage": {"input_tokens": 1000, "output_tokens": 10}}})
                query("INSERT INTO llm.requests FORMAT JSONEachRow\n" + json.dumps({
                    "request_id": call, "trace_id": "ws-tight", "started_at": base + started,
                    "completed_at": base + completed, "source_format": "openai-response", "model": "gpt-6.1-sol",
                    "outcome": "succeeded", "status_code": 200, "user_agent": "T3 Code/0.0.30",
                    "request_envelope": "{}", "request_parts": [], "response_body": body}), "cliproxy")
                query("INSERT INTO llm.usage FORMAT JSONEachRow\n" + json.dumps({
                    "request_id": f"usage-{call}", "trace_id": "ws-tight", "session_id": f"codex:{call}",
                    "requested_at": base + attempt, "provider": "codex", "model": "gpt-6.1-sol",
                    "input_tokens": 1000, "output_tokens": 10}), "cliproxy")
            assert sorted(job("proxy-tight")[0]) == ["tight-a", "tight-b"]
            assert scalar("SELECT groupArray((call_id, session_id)) FROM (SELECT call_id, session_id "
                          "FROM llm.calls FINAL WHERE call_id LIKE 'tight-%' ORDER BY call_id)") \
                == "[('tight-a','codex:tight-a'),('tight-b','codex:tight-b')]"
            cost = [line.split("\t") for line in query(sql["cost"]).stdout.splitlines()]
            assert sorted((session, attempts) for session, _, attempts, _ in cost if "tight" in session) \
                == [("codex:tight-a", "1"), ("codex:tight-b", "1")], cost
            live = float(scalar("SELECT sum(estimated_cost_usd) FROM llm.usage_metrics WHERE origin = 'live'"))
            assert abs(sum(float(c[3]) for c in cost if c[3] != "\\N") - live) < 1e-9, (cost, live)

            # A failed delta request that sent nothing new and got nothing back
            # ends where codex-2, which it continues, ended. That output is
            # codex-2's, so this call is no training example.
            query("INSERT INTO llm.requests FORMAT JSONEachRow\n" + json.dumps({
                "request_id": "codex-failed", "trace_id": "ws-failed", "started_at": "2026-11-10 10:00:20.000",
                "completed_at": "2026-11-10 10:00:21.000", "source_format": "openai-response", "model": "gpt-6.1-sol",
                "outcome": "failed", "status_code": 502, "user_agent": "T3 Code/0.0.30",
                "request_envelope": json.dumps({"previous_response_id": "resp_B", "input": []}),
                "request_parts": [], "response_body": ""}), "cliproxy")
            query("INSERT INTO llm.usage FORMAT JSONEachRow\n" + json.dumps({
                "request_id": "usage-codex-failed", "trace_id": "ws-failed",
                "session_id": "codex:01a1da81-0000-7000-8000-000000000001", "requested_at": "2026-11-10 10:00:20.001",
                "provider": "codex", "model": "gpt-6.1-sol"}), "cliproxy")
            assert job("proxy-failed")[0] == ["codex-failed"]
            rows = query(sql["call"], params=(("call", "codex-failed"),)).stdout
            assert json.loads(rows.splitlines()[-1])["output"], rows
            failed = run(str(normalizer), "-export", "openai", input=rows, check=False)
            assert failed.returncode != 0 and "no output" in failed.stderr, failed

            # ClickHouse runs schema.sql on every restart, which keeps the
            # history and the checks.
            kept = history_rows()
            run("docker", "exec", "-i", container, "clickhouse-client", "--multiquery", input=config["schema.sql"])
            assert history_rows() == kept and sorted(kept) == expected_history(), kept
            print(f"PASS: {len(sql)} example queries, proxy references both ways, unchanged raw capture, "
                  "usage history, permissions")
        finally:
            run("docker", "rm", "--force", container, check=False)
        job_in_cluster(image, temp, sources)


def job_in_cluster(image, temp, sources):
    """The cluster's llm-normalizer CronJob: normalize.sh in the ClickHouse
    image, as llm_normalizer over the native port, from the same source rows."""
    container = f"infra-llm-normalizer-test-{os.getpid()}"
    tools = temp / "normalizer"
    tools.mkdir()
    # For the container's platform, which differs from the host's on macOS.
    arch = run("docker", "version", "--format", "{{.Server.Arch}}").stdout.strip()
    run("go", "build", "-o", str(tools / "normalize-conversations"), "./normalize-conversations", cwd=PLUGINS,
        env={**os.environ, "CGO_ENABLED": "0", "GOOS": "linux", "GOARCH": arch})
    for name in ["normalize.sh", *(p.name for p in NORMALIZER.glob("*.sql"))]:
        (tools / name).write_bytes((NORMALIZER / name).read_bytes())
        (tools / name).chmod(0o755)
    try:
        run("docker", "run", "--detach", "--name", container, "--network", "none",
            "--memory", "2g", "--cpus", "2", "-e", "CLICKHOUSE_SKIP_USER_SETUP=1",
            "-e", f"LLM_NORMALIZER_PASSWORD={PASSWORD}",
            "-v", f"{temp}/config.xml:/etc/clickhouse-server/config.d/archive.xml:ro",
            "-v", f"{temp}/users.xml:/etc/clickhouse-server/users.d/archive.xml:ro",
            "-v", f"{temp}/schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro",
            "-v", f"{tools}:/opt/normalizer:ro", image)

        def query(sql, user="default"):
            return run("docker", "exec", "-i", container, "clickhouse-client", "--user", user, input=sql).stdout.strip()

        # The entrypoint runs schema.sql on a temporary server, then starts
        # the real one, so the schema is ready once it answers twice.
        ready = 0
        for _ in range(240):
            ready = ready + 1 if run("docker", "exec", container, "clickhouse-client", "--query",
                                     "EXISTS TABLE llm.usage_metrics", check=False).stdout.strip() == "1" else 0
            if ready == 2:
                break
            time.sleep(1)
        for table in ("llm.request_items", "llm.requests", "llm.usage"):
            query(f"INSERT INTO {table} FORMAT JSONEachRow\n" + (sources / f"{table}.jsonl").read_text(), "cliproxy")
        insert_transcript_rows(query)

        def normalize(mode, *env):
            return run("docker", "exec", "-u", "101", "-e", "CLICKHOUSE_HOST=localhost", "-e", "SCRATCH=/tmp/scratch",
                       "-e", "HOME=/tmp", "-e", f"CLICKHOUSE_PASSWORD={PASSWORD}", *env, container,
                       "/opt/normalizer/normalize.sh", mode, check=False)

        result = normalize("cron")
        assert result.returncode == 0, result.stdout + result.stderr
        assert query("SELECT count() FROM llm.calls FINAL WHERE origin = 'proxy'") == "10"
        # The checks pass over the proxy's rows and the transcript import's.
        result = normalize("verify")
        assert result.returncode == 0, result.stdout + result.stderr
        checks = [line.split("\t") for line in result.stdout.splitlines() if line.startswith("check\t")]
        assert len(checks) >= 10 and all(c[2] == "0" for c in checks), checks
        # The job finds nothing left.
        rows = query("SELECT count() FROM llm.messages")
        result = normalize("cron")
        assert result.returncode == 0 and query("SELECT count() FROM llm.messages") == rows, result.stderr
        # After a stop of any length, the job catches up an hour at a time
        # from the oldest request it misses. Once its budget is spent it
        # stops after the window it ran, and the next run goes on.
        late = (("late-6d", 150), ("late-3d", 75), ("late-2h", 2))
        for call, hours in late:
            started = (datetime.now(timezone.utc) - timedelta(hours=hours)).strftime("%Y-%m-%d %H:%M:%S")
            body = json.dumps({"type": "response.completed", "response": {
                "id": f"resp_{call}", "object": "response", "model": "gpt-6.1-sol", "output": [],
                "usage": {"input_tokens": 100, "output_tokens": 1}}})
            query("INSERT INTO llm.requests FORMAT JSONEachRow\n" + json.dumps({
                "request_id": call, "trace_id": call, "started_at": f"{started}.000", "completed_at": f"{started}.500",
                "source_format": "openai-response", "model": "gpt-6.1-sol", "outcome": "succeeded", "status_code": 200,
                "user_agent": "T3 Code/0.0.30", "request_envelope": "{}", "request_parts": [], "response_body": body}),
                "cliproxy")
            query("INSERT INTO llm.usage FORMAT JSONEachRow\n" + json.dumps({
                "request_id": f"usage-{call}", "trace_id": call, "session_id": f"codex:{call}",
                "requested_at": f"{started}.001", "provider": "codex", "model": "gpt-6.1-sol"}), "cliproxy")
        caught_up = "SELECT groupArray(call_id) FROM (SELECT call_id FROM llm.calls FINAL WHERE call_id LIKE 'late-%' ORDER BY started_at)"
        for done in (1, 2, 3):
            result = normalize("cron", "-e", "BUDGET=0")
            assert result.returncode == 0 and "the budget is spent" in result.stdout, result.stdout + result.stderr
            assert query(caught_up) == "[" + ",".join(f"'{call}'" for call, _ in late[:done]) + "]", (done, result.stdout)
        result = normalize("cron")
        assert result.returncode == 0 and len(result.stdout.splitlines()) == 1, result.stdout + result.stderr
        assert query("SELECT countIf(origin LIKE 'history:%') > 0 FROM llm.usage_metrics", "grafana") == "1"
        # The normalizer's user reads the sources and appends to the
        # canonical tables, and nothing else.
        def as_normalizer(sql, *password):
            return run("docker", "exec", "-i", container, "clickhouse-client", "--user", "llm_normalizer",
                       *password, input=sql, check=False)

        requests = query("SELECT count() FROM llm.requests")
        assert as_normalizer("SELECT count() FROM llm.requests", "--password", PASSWORD).stdout.strip() == requests
        for sql in ("SELECT * FROM llm.usage_metrics", "INSERT INTO llm.requests (request_id) VALUES ('x')",
                    "ALTER TABLE llm.calls DELETE WHERE 1", "DROP TABLE llm.events"):
            denied = as_normalizer(sql, "--password", PASSWORD)
            assert denied.returncode != 0 and "ACCESS_DENIED" in denied.stderr, (sql, denied.stderr)
        # CLIProxy's and Grafana's pods reach the HTTP port, and cannot read
        # the raw history as the normalizer without its password, there or
        # on the native port; with it, the same request reads it.
        def over_http(password):
            url = "http://localhost:8123/?user=llm_normalizer" + (f"&password={password}" if password else "") \
                + "&query=SELECT%20count()%20FROM%20llm.requests"
            return run("docker", "exec", "-i", container, "clickhouse-client", input=f"SELECT * FROM url('{url}', "
                       "TSV, 'n UInt64')", check=False)

        assert over_http(PASSWORD).stdout.strip() == requests
        for password in ("", "wrong"):
            denied = over_http(password)
            assert denied.returncode != 0 and "AUTHENTICATION_FAILED" in denied.stderr, denied.stderr
            denied = as_normalizer("SELECT count() FROM llm.requests", *(["--password", password] if password else []))
            assert denied.returncode != 0 and "AUTHENTICATION_FAILED" in denied.stderr, denied.stderr
        print("PASS: the in-cluster job, its catch-up and checks, with the normalizer's grants")
    finally:
        run("docker", "rm", "--force", container, check=False)


if __name__ == "__main__":
    main()
