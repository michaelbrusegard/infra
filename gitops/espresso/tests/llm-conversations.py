#!/usr/bin/env python3
"""Test the canonical conversation prototype against a real ClickHouse.

Inserts the fixtures as source rows, normalizes them from there the way the
normalizer job would, and runs the example queries from
docs/llm-conversations.md. Nothing touches the cluster.

Run with `nix develop --command python3 gitops/espresso/tests/llm-conversations.py`.
Requires Docker and Go.
"""

from datetime import datetime, timedelta, timezone
import itertools
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
DOC = ROOT / "docs/llm-conversations.md"
# The fixtures are from November 2026; pin "now" so the examples stay stable.
NOW = "toDateTime64('2026-11-14 00:00:00', 3, 'UTC')"
# llm_normalizer's password, which the cluster reads from a secret.
PASSWORD = secrets.token_hex(16)


TRANSCRIPTS = """
CREATE TABLE IF NOT EXISTS llm.transcripts
(
    source LowCardinality(String),
    host LowCardinality(String),
    session String,
    id String,
    path String,
    line String CODEC(ZSTD(3)),
    ts DateTime64(3, 'UTC') DEFAULT parseDateTime64BestEffortOrZero(JSONExtractString(line, 'timestamp'), 3, 'UTC'),
    ingested_at DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(ingested_at)
ORDER BY (source, host, session, path, id);
"""


# A file synced to a second host shares its session, line numbers, and
# times with the first.
SYNCED = ("INSERT INTO llm.transcripts (source, host, session, id, path, line) "
          "SELECT source, 'ristretto', session, id, path, line FROM llm.transcripts "
          "WHERE path LIKE '%019f6478-0000-7000-8000-000000000004.jsonl'")


def run(*args, input=None, check=True, **kwargs):
    result = subprocess.run(args, input=input, text=True, capture_output=True, **kwargs)
    if check and result.returncode != 0:
        raise RuntimeError(f"{args[-3:]} failed:\n{result.stderr}")
    return result


def examples():
    """The ```sql blocks of the design doc that start with `-- example: <name>`."""
    found = {}
    for block in re.findall(r"```sql\n(.*?)```", DOC.read_text(), re.S):
        match = re.match(r"-- example: (\S+)", block)
        if match:
            found[match.group(1)] = block.replace("now()", NOW)
    return found


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
    # The production schema, and the one-off transcript import as it exists
    # live until it is dropped; the schema no longer creates it.
    schema = config["schema.sql"] + "\n" + TRANSCRIPTS
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
            # A file synced to a second host shares its session, line numbers,
            # and times with the first.
            query(SYNCED)

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

            canonical = ("llm.request_items", "llm.sessions", "llm.messages", "llm.calls", "llm.events")

            def load(out):
                for table in canonical:
                    insert(table, out / f"{table}.jsonl")

            # The normalizer never changes the proxy's raw capture. It adds
            # items only for the context of transcript calls.
            def checksums():
                return [scalar(f"SELECT count(), sum(cityHash64(*)) FROM {table}") for table in (
                    "llm.requests", "llm.transcripts",
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

            # Until the transcript import lands, the dashboard's history is
            # the old import's.
            history = "SELECT trace_id, origin, input_tokens, output_tokens, estimated_cost_usd FROM llm.usage_metrics " \
                      "WHERE origin LIKE 'history:%' ORDER BY trace_id FORMAT JSONEachRow"
            query("INSERT INTO llm.historical_usage FORMAT JSONEachRow\n" + json.dumps({
                "event_id": "old-import", "source": "codex", "requested_at": "2026-07-01 00:00:00.000",
                "provider": "codex", "model": "gpt-5.5", "uncached_input_tokens": 100, "output_tokens": 10}))
            assert [json.loads(r)["trace_id"] for r in query(history, "grafana").stdout.splitlines()] == ["old-import"]

            # Transcripts once, after the proxy, which owns each session it
            # captured from its first call on.
            proxied = temp / "proxied.tsv"
            proxied.write_text(query((NORMALIZER / "proxied.sql").read_text()).stdout)
            # The import's input, read in parts of whole files, as the
            # backfill Job reads it, and concatenated.
            def transcript_lines():
                parts = query((NORMALIZER / "files.sql").read_text(), params=(("bytes", 4096),)).stdout.splitlines()
                assert len(parts) > 2, parts
                return "".join(query((NORMALIZER / "transcripts.sql").read_text(), params=(("files", part),)).stdout
                               for part in parts)

            transcripts = transcript_lines()

            def import_transcripts(name, lines):
                out = temp / name
                out.mkdir()
                (temp / f"{name}.jsonl").write_text(lines)
                run(str(normalizer), "-in", str(temp / f"{name}.jsonl"), "-proxied", str(proxied), "-out", str(out))
                return out

            out = import_transcripts("transcripts", transcripts)
            load(out)
            transcript_calls = scalar("SELECT count() FROM llm.calls FINAL WHERE origin = 'transcript'")
            # The import's rows do not depend on the order of the files.
            files = [list(group) for _, group in itertools.groupby(
                transcripts.splitlines(keepends=True),
                lambda line: [json.loads(line)[k] for k in ("source", "host", "session", "path")])]
            reversed_out = import_transcripts("transcripts-reversed", "".join(itertools.chain(*files[::-1])))
            for table in (*canonical, "coverage.tsv"):
                name = table if table.endswith(".tsv") else f"{table}.jsonl"
                rows = [sorted((directory / name).read_text().splitlines()) for directory in (out, reversed_out)]
                assert rows[0] == rows[1], table
            assert checksums() == before, "normalizing changed the raw capture"

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
            # llm.transcripts is dropped after the import, so every line is
            # covered: the normalizer counts each line once, by what became of
            # it, and the lines messages and events name are exactly those it
            # counts as messages and events. Every kind it drops is in the
            # design doc's table of dropped kinds.
            coverage = [line.split("\t") for line in (out / "coverage.tsv").read_text().splitlines()]
            assert sum(int(c[4]) for c in coverage) == int(scalar("SELECT count() FROM llm.transcripts FINAL")) == 62
            lines = "SELECT toString(host), path, id FROM llm.transcripts FINAL"
            named = """SELECT * FROM (
                SELECT toString(host), path, line FROM llm.messages FINAL WHERE path != '' AND part = ''
                UNION ALL SELECT toString(host), path, line FROM llm.events FINAL)"""
            assert scalar(f"SELECT count() FROM ({named})") \
                == str(sum(int(c[4]) for c in coverage if c[2] in ("message", "event")))
            assert scalar(f"SELECT count() FROM ({named} EXCEPT {lines})") == "0"
            assert scalar(f"SELECT count() FROM (SELECT DISTINCT * FROM ({named}))") \
                == scalar(f"SELECT count() FROM ({named})")
            documented = set(re.findall(r"^\| `([a-z-]+)` \| `([^`]+)` \|", DOC.read_text(), re.M))
            assert documented, "no table of dropped kinds"
            assert not {(c[0], c[1]) for c in coverage if c[2] == "dropped"} - documented, coverage
            # Every line that is no dropped kind names where its content is
            # now, and that row holds it: each destination is checked against
            # the canonical tables, not only counted.
            def lines_to(source, disposition, destination, kind=None):
                return sum(int(c[4]) for c in coverage if (c[0], c[2], c[3]) == (source, disposition, destination)
                           and kind in (None, c[1]))
            assert all((c[2] == "dropped") == (c[3] == "") for c in coverage), coverage
            assert {c[3] for c in coverage} <= {"", "llm.messages", "llm.events", "llm.sessions", "llm.calls",
                                               "llm.calls.usage", "llm.calls.model", "llm.calls.context",
                                               "llm.messages.part", "llm.messages.parent_id", "llm.messages.blocks"}, coverage
            # Codex usage lines are each the usage of one call of their file.
            assert lines_to("codex", "call", "llm.calls.usage") == int(scalar(
                "SELECT count() FROM llm.calls FINAL WHERE origin = 'transcript' AND client = 'codex' "
                "AND uncached_input_tokens + cache_read_tokens + output_tokens > 0")) > 0, coverage
            # Turn settings give the calls after them their model.
            assert lines_to("codex", "call", "llm.calls.model") > 0 and scalar(
                "SELECT countIf(model = '') FROM llm.calls FINAL WHERE origin = 'transcript' AND client = 'codex'") == "0"
            # Claude Code's request logs are the context of the calls naming
            # them, one call per request in these files.
            assert lines_to("claude-code", "call", "llm.calls.context", "api-request") == int(scalar(
                "SELECT count() FROM llm.calls FINAL WHERE origin = 'transcript' AND client = 'claude-code' "
                "AND notEmpty(context)")) > 0, coverage
            # Session lines are in the sessions of their files.
            assert scalar("SELECT count() FROM (SELECT DISTINCT host, path FROM llm.transcripts FINAL "
                          "EXCEPT SELECT DISTINCT host, path FROM llm.sessions FINAL WHERE origin = 'transcript')") == "0"
            # Compacted histories are messages built from their lines, and
            # OpenCode's part records hold blocks of messages that exist.
            assert lines_to("codex", "structure", "llm.messages.part") == int(scalar(
                "SELECT uniqExact(host, path, line) FROM llm.messages FINAL WHERE format = 'openai-responses' "
                "AND part != ''"))
            assert lines_to("opencode", "structure", "llm.messages.blocks") == int(scalar(
                "SELECT count() FROM llm.transcripts FINAL WHERE source = 'opencode' "
                "AND JSONExtractString(line, 'kind') = 'part' AND (host, path, concat('message:', "
                "JSONExtractString(line, 'message_id'))) IN (SELECT host, path, line FROM llm.messages)")) > 0
            # A line is the proxy's only when the proxy returned the reply it
            # leads to: every reply among those lines is a proxy call's.
            proxied_replies = scalar("""
                SELECT count() FROM (SELECT ts, multiIf(source = 'claude-code', JSONExtractString(line, 'message', 'id'),
                        source = 'pi', JSONExtractString(line, 'message', 'responseId'),
                        JSONExtractString(line, 'payload', 'response_id')) AS reply FROM llm.transcripts FINAL)
                WHERE reply != '' AND reply IN (SELECT response_id FROM llm.calls FINAL WHERE origin = 'proxy')
                    AND ts >= (SELECT min(started_at) FROM llm.calls FINAL WHERE origin = 'proxy')""")
            assert int(proxied_replies) > 0 and sum(int(c[4]) for c in coverage if c[2] == "proxied") \
                >= int(proxied_replies), coverage
            # Messages built from inside a line name it, and calls their file.
            assert scalar("""
                SELECT count() FROM llm.messages FINAL
                WHERE part != '' AND (host, path, line) NOT IN (SELECT host, path, id FROM llm.transcripts)
            """) == "0"
            assert scalar("""
                SELECT count() FROM llm.calls FINAL
                WHERE origin = 'transcript' AND (host, path) NOT IN (SELECT host, path FROM llm.transcripts)
            """) == "0"
            # Two Codex compaction items, and two entries Pi sends again.
            assert scalar("SELECT groupArray((line, part)) FROM (SELECT line, part FROM llm.messages FINAL "
                          "WHERE part != '' ORDER BY line, part)") == "[('12','0'),('12','1'),('7','p2'),('7','p3')]"
            # The Claude Code call whose request log the transcript holds
            # carries its system prompt and tools as items.
            assert scalar("SELECT arrayMap(p -> (p.field, p.position), context) FROM llm.calls FINAL "
                          "WHERE call_id = 'req_011'") == "[('system',0),('system',1),('tools',0),('tools',1)]"
            assert scalar("SELECT count() FROM (SELECT arrayJoin(context).hash AS hash FROM llm.calls) "
                          "WHERE hash NOT IN (SELECT hash FROM llm.request_items)") == "0"
            assert scalar("SELECT count() FROM llm.request_items "
                          "WHERE hash != reinterpretAsUInt128(substring(SHA256(item), 1, 16))") == "0"
            # Both captured this session. The transcript keeps the line from
            # before the proxy's first call as a message, and the later one is
            # the proxy's; so are its calls and tokens.
            both = "'claude:11111111-1111-4111-8111-111111111111'"
            assert scalar(f"SELECT arraySort(groupArray(origin)) FROM llm.sessions FINAL WHERE session_id = {both}") \
                == "['proxy','transcript']"
            assert scalar(f"SELECT groupArray(line) FROM llm.messages FINAL WHERE session_id = {both} AND line != ''") \
                == "['1']"
            assert ["claude-code", "assistant", "proxied", "llm.calls", "1"] in coverage, coverage
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
            for table in ("llm.messages", "llm.calls", "llm.events", "llm.sessions", "llm.call_history", "llm.old_import_usage",
                          "llm.transcript_import"):
                assert query(f"SELECT * FROM {table}", "grafana", check=False).returncode != 0, table

            # Once the transcript calls landed, the production view reads the
            # dashboard's history from them through llm.call_history, and no
            # longer from llm.historical_usage. Each transcript call with
            # usage before the proxy is one row, priced as the importer's
            # rows were: the Claude Code call wrote 2,000 tokens to the
            # one-hour cache.
            def history_rows():
                return {r["trace_id"]: r for r in map(json.loads, query(history, "grafana").stdout.splitlines())}

            def expected_history():
                return sorted(scalar("SELECT groupArray(event_id) FROM llm.call_history WHERE requested_at < "
                                     "(SELECT min(requested_at) FROM llm.usage)").strip("[]").replace("'", "").split(","))

            # Until the backfill marks the import complete, which it does
            # after its checks, the history stays the old import's: an
            # import that failed part way leaves some calls.
            assert list(history_rows()) == ["old-import"]
            query("INSERT INTO llm.transcript_import VALUES (now64(3))")
            rows = history_rows()
            assert sorted(rows) == expected_history() and "old-import" not in rows, rows
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
            bare = scalar("SELECT call_id FROM llm.calls FINAL WHERE origin = 'transcript' AND client = 'codex' "
                          "AND empty(context) AND notEmpty(output_ids) ORDER BY started_at LIMIT 1")
            for call, reason in ((bare, "does not define"), ("c1", "no output")):
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

            # The Claude Code call exports as a training example with the system
            # prompt and tools its request log recorded.
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

            # The collision audit finds the item keys the normalizer reports:
            # two Codex calls whose first items share a call ID. A response
            # without items, such as a compaction's, and two responses with
            # no input between are calls of their own, so they collide with
            # nothing.
            def usage(response):
                return {"type": "token_usage_record", "payload": {"response_id": response, "usage": {}}}

            def item(payload):
                return {"type": "response_item", "payload": payload}

            def tool_call(item_id, call_id):
                return item({"type": "function_call", "id": item_id, "name": "exec", "arguments": "{}", "call_id": call_id})

            def reply(item_id):
                return item({"type": "message", "id": item_id, "role": "assistant", "content": []})

            for name, lines in (("c", [tool_call("fc_1", "call_shared"), usage("resp_c1")]),
                                ("d", [tool_call("fc_2", "call_shared"), usage("resp_c2")]),
                                ("e", [tool_call("fc_3", "call_e"), usage("resp_e1"),
                                       item({"type": "function_call_output", "call_id": "call_e", "output": "ok"}),
                                       usage("resp_e2"), {"type": "compacted", "payload": {"replacement_history": []}},
                                       reply("msg_e3"), usage("resp_e3"), reply("msg_e4"), usage("resp_e4")])):
                thread = f"01a1da81-0000-7000-8000-0000000000{name}{name}"
                path = f".codex/sessions/2026/11/12/rollout-2026-11-12T10-00-00-{thread}.jsonl"
                lines = [{"type": "session_meta", "payload": {"id": thread}}, *lines]
                query("INSERT INTO llm.transcripts FORMAT JSONEachRow\n" + "\n".join(json.dumps({
                    "source": "codex", "host": "lungo", "session": path.removesuffix(".jsonl").rsplit("/", 1)[1],
                    "id": str(i + 1), "path": path,
                    "line": json.dumps({"timestamp": f"2026-11-12T10:00:0{i}.000Z", **line})}) for i, line in enumerate(lines)))
            audit = [line.split("\t") for line in query(sql["collisions"]).stdout.splitlines()]
            out = temp / "collisions"
            out.mkdir()
            (temp / "collisions.jsonl").write_text(transcript_lines())
            reported = run(str(normalizer), "-in", str(temp / "collisions.jsonl"), "-proxied", str(proxied),
                           "-out", str(out)).stderr
            assert audit == [["item:call_shared", "['resp_c1','resp_c2']"]], audit
            assert reported.splitlines()[1:] == ["item:call_shared resp_c1 resp_c2"], reported

            # transcripts.sql sends only the type of the largest kinds of line
            # the import drops, such as Claude Code's request blobs and Codex's
            # item events, and the normalizer writes the same rows as from the
            # whole lines. Errors and interruptions stay events.
            claude = ".claude/projects/-Users-michaelbrusegard-Projects-infra/22222222-2222-4222-8222-222222222222.jsonl"
            codex = ".codex/sessions/2026/11/12/rollout-2026-11-12T10-00-00-01a1da81-0000-7000-8000-0000000000ee.jsonl"
            codex_session = codex.rsplit("/", 1)[1].removesuffix(".jsonl")
            added = (
                ("claude-code", claude, "22222222-2222-4222-8222-222222222222", "100",
                 {"type": "api-request-blob", "hash": "h1", "sessionId": "s",
                  "message": {"role": "user", "content": "x" * 4096}}),
                ("claude-code", claude, "22222222-2222-4222-8222-222222222222", "101",
                 {"type": "system", "subtype": "api_error", "uuid": "e1", "parentUuid": "x2",
                  "timestamp": "2026-10-01T09:00:05.000Z", "error": {"message": "Connection error.",
                                                                    "formatted": "Can't reach the API server"}}),
                ("codex", codex, codex_session, "100", {"timestamp": "2026-11-12T10:01:00.000Z", "type": "world_state",
                                                        "payload": {"cwd": "/" * 4096}}),
                ("codex", codex, codex_session, "101", {"timestamp": "2026-11-12T10:01:01.000Z", "type": "event_msg",
                                                        "payload": {"type": "item_completed", "item": "/" * 4096}}),
                ("codex", codex, codex_session, "102", {"timestamp": "2026-11-12T10:01:02.000Z", "type": "event_msg",
                                                        "payload": {"type": "turn_aborted", "reason": "interrupted"}}))
            query("INSERT INTO llm.transcripts FORMAT JSONEachRow\n" + "\n".join(json.dumps({
                "source": source, "host": "lungo", "session": session, "id": id, "path": path,
                "line": json.dumps(line)}) for source, path, session, id, line in added))
            whole = query("SELECT source, host, session, id, path, line, toString(ts) AS ts FROM llm.transcripts FINAL "
                          "ORDER BY source, host, path, session, toUInt64OrZero(id), id FORMAT JSONEachRow").stdout
            stripped = transcript_lines()
            assert len(stripped) < len(whole) - 8000, (len(stripped), len(whole))
            outs = [import_transcripts(name, lines) for name, lines in (("whole", whole), ("stripped", stripped))]
            for table in (*canonical, "coverage.tsv"):
                name = table if table.endswith(".tsv") else f"{table}.jsonl"
                rows = [sorted((directory / name).read_text().splitlines()) for directory in outs]
                assert rows[0] == rows[1], table
            events = sorted((e["type"], e["detail"]) for e in jsonl(outs[1] / "llm.events.jsonl"))
            assert events == [("api_error", "Can't reach the API server"), ("turn_aborted", "interrupted")], events

            # ClickHouse runs schema.sql on every restart. Rerunning it keeps
            # the history, and so does dropping the old import after it is
            # verified, at once and after the next restart: no view names
            # llm.historical_usage, schema.sql does not create llm.transcripts
            # again, and the empty llm.historical_usage it creates is ignored.
            def restart():
                run("docker", "exec", "-i", container, "clickhouse-client", "--multiquery", input=config["schema.sql"])

            def checks():
                return query((NORMALIZER / "verify.sql").read_text()).stdout

            kept = history_rows()
            restart()
            assert history_rows() == kept
            assert "old import calls" in checks()
            query("DROP TABLE llm.transcripts")
            query("DROP TABLE llm.historical_usage")
            assert history_rows() == kept and sorted(kept) == expected_history(), kept
            assert "old import calls" not in checks()
            restart()
            assert scalar("EXISTS TABLE llm.transcripts") == "0" and scalar("SELECT count() FROM llm.historical_usage") == "0"
            assert history_rows() == kept and sorted(kept) == expected_history(), kept
            print(f"PASS: {len(sql)} doc examples, proxy references both ways, transcript coverage, "
                  "unchanged raw capture, usage history cutover and drop, permissions")
        finally:
            run("docker", "rm", "--force", container, check=False)
        backfill_in_cluster(image, temp, schema, sources, transcript_calls)
        backfill_runner(temp)


def backfill_in_cluster(image, temp, schema, sources, transcript_calls):
    """The cluster's backfill Job: normalize.sh in the ClickHouse image, as
    llm_normalizer over the native port, from the same source rows."""
    container = f"infra-llm-backfill-test-{os.getpid()}"
    tools = temp / "normalizer"
    tools.mkdir()
    run("go", "build", "-o", str(tools / "normalize-conversations"), "./normalize-conversations", cwd=PLUGINS,
        env={**os.environ, "CGO_ENABLED": "0"})
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
                                     "EXISTS TABLE llm.events", check=False).stdout.strip() == "1" else 0
            if ready == 2:
                break
            time.sleep(1)
        for table, user in (("llm.request_items", "cliproxy"), ("llm.requests", "cliproxy"),
                            ("llm.usage", "cliproxy"), ("llm.transcripts", "default")):
            query(f"INSERT INTO {table} FORMAT JSONEachRow\n" + (sources / f"{table}.jsonl").read_text(), user)
        query(SYNCED)

        def normalize(mode, *env):
            return run("docker", "exec", "-u", "101", "-e", "CLICKHOUSE_HOST=localhost", "-e", "SCRATCH=/tmp/scratch",
                       "-e", "HOME=/tmp", "-e", f"CLICKHOUSE_PASSWORD={PASSWORD}", *env, container,
                       "/opt/normalizer/normalize.sh", mode, check=False)

        result = normalize("backfill")
        assert result.returncode == 0, result.stdout + result.stderr
        checks = [line.split("\t") for line in result.stdout.splitlines() if line.startswith("check\t")]
        assert len(checks) >= 10 and all(c[2] == "0" for c in checks), checks
        assert "coverage (source, kind, disposition, destination, lines):" in result.stdout, result.stdout
        assert query("SELECT count() FROM llm.calls FINAL WHERE origin = 'proxy'") == "10"
        assert query("SELECT count() FROM llm.calls FINAL WHERE origin = 'transcript'") == transcript_calls
        assert query("SELECT count() FROM llm.transcript_import") == "1"
        # The job finds nothing left.
        rows = query("SELECT count() FROM llm.messages")
        result = normalize("cron")
        assert result.returncode == 0 and query("SELECT count() FROM llm.messages") == rows, result.stderr
        # A second backfill waits for deletes still going, as a recovery's
        # are, and is then refused rather than mixed with the first.
        query("INSERT INTO llm.events (session_id, type) VALUES ('deleted', 'deleted')")
        query("SYSTEM STOP MERGES llm.events")
        query("ALTER TABLE llm.events DELETE WHERE type = 'deleted'")
        backfill = subprocess.Popen(
            ["docker", "exec", "-u", "101", "-e", "CLICKHOUSE_HOST=localhost", "-e", "SCRATCH=/tmp/scratch",
             "-e", "HOME=/tmp", "-e", f"CLICKHOUSE_PASSWORD={PASSWORD}", container, "/opt/normalizer/normalize.sh",
             "backfill"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        time.sleep(15)
        assert backfill.poll() is None, backfill.communicate()
        query("SYSTEM START MERGES llm.events")
        out, err = backfill.communicate(timeout=120)
        assert backfill.returncode != 0 and "waiting for 1 deletes in llm" in out \
            and "delete the transcript rows first" in err, (out, err)
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
        # The checks run after the old import is dropped, too.
        query("DROP TABLE llm.transcripts")
        query("DROP TABLE llm.historical_usage")
        result = normalize("verify")
        assert result.returncode == 0, result.stdout + result.stderr
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
        print("PASS: the in-cluster backfill and job, with the normalizer's grants")
    finally:
        run("docker", "rm", "--force", container, check=False)


# kubectl for llm-backfill.sh: it names each Job it creates, and reports
# the conditions of a run's outcome, with no pod counters.
KUBECTL = r"""#!/usr/bin/env bash
set -euo pipefail
state=$(dirname "$0")
touch "$state/jobs"
case "$*" in
"-n clickhouse get jobs -o json")
	jq -Rn '{items: [inputs | split(" ") | {metadata: {name: .[0]},
		status: {conditions: (if .[1] == "Running" then [] else [{type: .[1], status: "True"}] end)}}]}' < "$state/jobs"
	;;
"-n clickhouse delete job "*" --wait=true")
	grep -v "^$5 " "$state/jobs" > "$state/jobs.new" || true
	mv "$state/jobs.new" "$state/jobs"
	echo "$5" >> "$state/deleted"
	;;
"-n clickhouse get pod clickhouse-0 -o jsonpath={.spec.nodeName}")
	echo espresso-2
	;;
"get --raw /api/v1/nodes/espresso-2/proxy/stats/summary")
	# The tmpfs root has room; only the persistent disk's figure counts.
	echo "{\"node\":{\"fs\":{\"availableBytes\":$((100 << 30)),\"inodesFree\":9000000},\"runtime\":{\"imageFs\":{\"availableBytes\":$(cat "$state/free"),\"inodesFree\":5000000}}}}"
	;;
"-n clickhouse create -o name -f -")
	cat > "$state/manifest.yaml"
	runs=$(($(cat "$state/runs" 2>/dev/null || echo 0) + 1))
	echo "$runs" > "$state/runs"
	result=Failed
	[[ $runs == 2 ]] && result=Complete
	echo "llm-backfill-run$runs $result" >> "$state/jobs"
	echo "job.batch/llm-backfill-run$runs"
	;;
"-n clickhouse get job.batch/llm-backfill-run1 -o json")
	echo '{"status":{"conditions":[{"type":"FailureTarget","status":"True"},{"type":"Failed","status":"True"}]}}'
	;;
"-n clickhouse get job.batch/llm-backfill-run2 -o json")
	echo '{"status":{"conditions":[{"type":"Suspended","status":"False"},{"type":"Complete","status":"True"}]}}'
	;;
"-n clickhouse logs job.batch/llm-backfill-run"[12]" --all-containers")
	echo "log of $4"
	;;
*)
	echo "unexpected kubectl $*" >&2
	exit 2
	;;
esac
"""


def backfill_runner(temp):
    """llm-backfill.sh against a stand-in for kubectl: each run is a Job of
    its own, a rerun first deletes the finished attempt, whose kept pod would
    hold its scratch volume, and the Job's conditions decide the result. It
    refuses to start beside a running attempt or on a node short of disk."""
    stub = temp / "kubectl"
    stub.write_text(KUBECTL)
    stub.chmod(0o755)
    script = BASE / "apps/clickhouse/llm-backfill.sh"
    env = {**os.environ, "KUBECTL": str(stub), "LOG": str(temp / "llm-backfill.log")}
    (temp / "free").write_text(str(5 << 30))
    short = run(str(script), env=env, check=False, cwd=ROOT)
    assert short.returncode == 1 and "espresso-2 has 5 GiB" in short.stderr, short
    assert not (temp / "runs").exists(), "a Job was created on a node short of disk"
    (temp / "free").write_text(str(50 << 30))
    failed = run(str(script), env=env, check=False, cwd=ROOT)
    assert failed.returncode == 1 and "job.batch/llm-backfill-run1 failed" in failed.stderr, failed
    manifest = (temp / "manifest.yaml").read_text()
    assert "generateName: llm-backfill-" in manifest and "\n  name:" not in manifest, manifest
    rerun = run(str(script), env=env, check=False, cwd=ROOT)
    assert rerun.returncode == 0 and (temp / "llm-backfill.log").read_text() == "log of job.batch/llm-backfill-run2\n", rerun
    assert (temp / "deleted").read_text() == "llm-backfill-run1\n", "the failed attempt was not removed"
    (temp / "jobs").write_text("llm-backfill-run3 Running\n")
    busy = run(str(script), env=env, check=False, cwd=ROOT)
    assert busy.returncode == 1 and "llm-backfill-run3 is still running" in busy.stderr, busy
    print("PASS: the backfill runner, a rerun after a failed Job, Job conditions, and its disk and overlap checks")


if __name__ == "__main__":
    main()
