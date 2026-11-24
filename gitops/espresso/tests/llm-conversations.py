#!/usr/bin/env python3
"""Test the canonical conversation prototype against a real ClickHouse.

Inserts the fixtures as source rows, normalizes them from there the way the
normalizer job would, adds rows as the one-off transcript import left them,
and runs the example queries in normalize-conversations/queries. Nothing
touches the cluster.

Run with `nix develop --command python3 gitops/espresso/tests/llm-conversations.py`.
Requires Docker and Go.
"""

import hashlib
import json
import os
import secrets
import subprocess
import tempfile
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "gitops/espresso"
PLUGINS = ROOT / "packages/cliproxy-plugins"
NORMALIZER = PLUGINS / "normalize-conversations"
NOW = "toDateTime64('2026-11-14 00:00:00', 3, 'UTC')"
PASSWORD = secrets.token_hex(16)
SECOND_BATCH = {"claude-2", "claude-agent", "codex-2"}
CANONICAL = (
    "llm.request_items",
    "llm.sessions",
    "llm.messages",
    "llm.calls",
)
HISTORY = (
    "SELECT trace_id, origin, input_tokens, output_tokens, estimated_cost_usd FROM llm.usage_metrics "
    "WHERE origin LIKE 'history:%' ORDER BY trace_id FORMAT JSONEachRow"
)
SESSION = ("session", "claude:11111111-1111-4111-8111-111111111111")


SYSTEM = json.dumps([{"type": "text", "text": "You are Claude Code."}])
TOOLS = json.dumps(
    [
        {
            "name": "Bash",
            "description": "Run a command.",
            "input_schema": {"type": "object"},
        },
        {
            "name": "Read",
            "description": "Read a file.",
            "input_schema": {"type": "object"},
        },
    ]
)


def item_hash(item):
    """llm.request_items' hash: reinterpretAsUInt128(substring(SHA256(item), 1, 16))."""
    return str(int.from_bytes(hashlib.sha256(item.encode()).digest()[:16], "little"))


def transcript_rows():
    """Rows the one-off transcript import left in the canonical tables.

    No raw source names them any more: a Claude Code call with its request's
    system prompt and tools as items, a Codex call whose transcript recorded
    no tools, a Pi compaction without outputs, and a prompt the proxy later
    sent again in the same session.
    """
    claude = ".claude/projects/-Users-michaelbrusegard-Projects-infra/"
    files = {
        "claude:22222222-2222-4222-8222-222222222222": (
            "claude-code",
            claude + "22222222-2222-4222-8222-222222222222.jsonl",
        ),
        "claude:11111111-1111-4111-8111-111111111111": (
            "claude-code",
            claude + "11111111-1111-4111-8111-111111111111.jsonl",
        ),
        "codex:019f6478-0000-7000-8000-000000000003": (
            "codex",
            ".codex/sessions/2026/07/15/rollout-2026-07-15T14-09-54-019f6478-0000-7000-8000-000000000003.jsonl",
        ),
        "pi:01a039ec-0000-7000-8000-000000000005": (
            "pi",
            ".pi/agent/sessions/2026-08-25T17-16-23-878Z_01a039ec-0000-7000-8000-000000000005.jsonl",
        ),
    }

    def message(
        session, id, parent, seq, ts, role, blocks, output=False, model="", call=""
    ):
        _, path = files[session]
        return {
            "session_id": session,
            "id": id,
            "parent_id": parent,
            "seq": seq,
            "ts": ts,
            "role": role,
            "output": output,
            "model": model,
            "call_id": call,
            "blocks": blocks,
            "format": files[session][0],
            "host": "lungo",
            "path": path,
            "line": str(seq + 1),
        }

    def text(t):
        return {"type": "text", "source_type": "text", "text": t}

    def tool_call(name, id, input):
        return {
            "type": "tool_call",
            "source_type": "tool_use",
            "tool_name": name,
            "tool_call_id": id,
            "tool_input": input,
        }

    def call(session, id, started, model, input, outputs, context=(), **tokens):
        client, path = files[session]
        return {
            "call_id": id,
            "session_id": session,
            "started_at": started,
            "completed_at": started,
            "origin": "transcript",
            "client": client,
            "host": "lungo",
            "path": path,
            "model": model,
            "input_id": input,
            "output_ids": outputs,
            "context": list(context),
            **tokens,
        }

    cc, _, cx, pi = list(files)[:4]
    return {
        "llm.request_items": [
            {"hash": item_hash(i), "item": i} for i in (SYSTEM, TOOLS)
        ],
        "llm.sessions": [
            {
                "session_id": s,
                "client": c,
                "origin": "transcript",
                "host": "lungo",
                "path": p,
            }
            for s, (c, p) in files.items()
        ],
        "llm.messages": [
            message(
                cc,
                "101",
                "0",
                0,
                "2026-10-01 09:00:00.000",
                "user",
                [text("Why is the ingress returning 502?")],
            ),
            message(
                cc,
                "102",
                "101",
                1,
                "2026-10-01 09:00:05.000",
                "assistant",
                [
                    tool_call(
                        "Bash",
                        "toolu_t1",
                        '{"command":"kubectl -n ingress logs deploy/traefik"}',
                    )
                ],
                output=True,
                model="claude-opus-5",
                call="req_011",
            ),
            message(
                list(files)[1],
                "111",
                "0",
                0,
                "2026-11-10 08:59:00.000",
                "user",
                [text("The nightly backup job fails; find out why.")],
            ),
            message(
                cx,
                "201",
                "0",
                0,
                "2026-07-15 14:09:54.865",
                "user",
                [text("Add a Renovate rule for flake inputs.")],
            ),
            message(
                cx,
                "202",
                "201",
                1,
                "2026-07-15 14:10:00.000",
                "assistant",
                [tool_call("exec", "call_t1", '{"cmd":"ls"}')],
                output=True,
                model="gpt-5.5",
                call="codex-t1",
            ),
            message(
                pi,
                "301",
                "0",
                0,
                "2026-08-25 17:16:30.000",
                "user",
                [text("Run the tofu approval test.")],
            ),
        ],
        "llm.calls": [
            call(
                cc,
                "req_011",
                "2026-10-01 09:00:01.000",
                "claude-opus-5",
                "101",
                ["102"],
                [
                    {"field": "system", "position": 0, "hash": item_hash(SYSTEM)},
                    {"field": "tools", "position": 0, "hash": item_hash(TOOLS)},
                ],
                uncached_input_tokens=10,
                cache_write_tokens=2000,
                cache_write_1h_tokens=2000,
                output_tokens=64,
            ),
            call(
                cx,
                "codex-t1",
                "2026-07-15 14:09:55.000",
                "gpt-5.5",
                "201",
                ["202"],
                uncached_input_tokens=8000,
                output_tokens=100,
            ),
            call(
                pi,
                "c1",
                "2026-08-25 18:00:00.000",
                "gpt-5.6-sol",
                "301",
                [],
                uncached_input_tokens=180000,
                cache_read_tokens=10000,
                output_tokens=900,
            ),
        ],
    }


def insert_transcript_rows(query):
    for table, rows in transcript_rows().items():
        query(
            f"INSERT INTO {table} FORMAT JSONEachRow\n"
            + "".join(json.dumps(r) + "\n" for r in rows)
        )


def run(*args, input=None, check=True, **kwargs):
    result = subprocess.run(
        args, input=input, text=True, capture_output=True, **kwargs, check=False
    )
    if check and result.returncode != 0:
        raise RuntimeError(f"{args[-3:]} failed:\n{result.stderr}")
    return result


def jsonl(path):
    return [json.loads(line) for line in path.read_text().splitlines()]


def examples():
    """The example queries by name, with "now" pinned."""
    return {
        f.stem: f.read_text().replace("now()", NOW)
        for f in (NORMALIZER / "queries").glob("*.sql")
    }


def check_password_guard(image, command):
    """The server refuses to start without the normalizer's password, which
    ClickHouse would otherwise treat as no password at all."""
    for env in ([], ["-e", "LLM_NORMALIZER_PASSWORD="]):
        refused = run(
            "docker",
            "run",
            "--rm",
            "--network",
            "none",
            *env,
            "--entrypoint",
            command[0],
            image,
            *command[1:],
            check=False,
        )
        assert refused.returncode != 0 and "refusing to start" in refused.stderr, (
            env,
            refused,
        )


class Archive:
    def __init__(self, container, temp):
        self.container = container
        self.temp = temp
        self.sources = temp / "sources"
        self.normalizer = temp / "normalize-conversations"

    def start(self, image, command):
        run(
            "docker",
            "run",
            "--detach",
            "--name",
            self.container,
            "--network",
            "none",
            "--memory",
            "2g",
            "--cpus",
            "2",
            "-e",
            "CLICKHOUSE_SKIP_USER_SETUP=1",
            "-e",
            f"LLM_NORMALIZER_PASSWORD={PASSWORD}",
            "-v",
            f"{self.temp}/config.xml:/etc/clickhouse-server/config.d/archive.xml:ro",
            "-v",
            f"{self.temp}/users.xml:/etc/clickhouse-server/users.d/archive.xml:ro",
            "-v",
            f"{self.temp}/schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro",
            "--entrypoint",
            command[0],
            image,
            *command[1:],
        )

    def query(self, sql, user="default", check=True, params=()):
        args = [
            "docker",
            "exec",
            "-i",
            self.container,
            "clickhouse-client",
            "--user",
            user,
        ]
        for name, value in params:
            args.append(f"--param_{name}={value}")
        return run(*args, input=sql, check=check)

    def scalar(self, sql):
        return self.query(sql).stdout.strip()

    def insert(self, table, path, user="default"):
        data = path.read_text() if path.exists() else ""
        if data:
            self.query(f"INSERT INTO {table} FORMAT JSONEachRow\n" + data, user)

    def wait_for_schema(self):
        for _ in range(120):
            ready = self.query("EXISTS TABLE llm.usage_metrics", check=False)
            if ready.returncode == 0 and ready.stdout.strip() == "1":
                break
            time.sleep(0.5)
        else:
            raise RuntimeError(run("docker", "logs", self.container).stdout)

    def insert_plugin_sources(self):
        self.sources.mkdir()
        run(
            "go",
            "test",
            "-count=1",
            "./conversations",
            "-run",
            "TestDumpSources",
            "-args",
            "-dump",
            str(self.sources),
            cwd=PLUGINS,
        )
        run(
            "go",
            "build",
            "-o",
            str(self.normalizer),
            "./normalize-conversations",
            cwd=PLUGINS,
        )
        self.insert(
            "llm.request_items", self.sources / "llm.request_items.jsonl", "cliproxy"
        )
        self.requests_rows, self.usage_rows = (
            jsonl(self.sources / "llm.requests.jsonl"),
            jsonl(self.sources / "llm.usage.jsonl"),
        )

    def arrive(self, batch, tables=("llm.requests", "llm.usage")):
        """Insert proxy batch 1 or 2 into the given tables, as the plugin does.

        The second batch holds a delta request and a full resend continuing
        calls from the first, and claude-agent, which started before requests
        of the first batch.
        """
        for table, rows, key in (
            ("llm.requests", self.requests_rows, "request_id"),
            ("llm.usage", self.usage_rows, "request_id"),
        ):
            if table not in tables:
                continue
            data = "".join(
                json.dumps(row) + "\n"
                for row in rows
                if (row[key].removeprefix("usage-") in SECOND_BATCH) == (batch == 2)
            )
            self.query(f"INSERT INTO {table} FORMAT JSONEachRow\n" + data, "cliproxy")

    def load(self, out):
        for table in CANONICAL:
            self.insert(table, out / f"{table}.jsonl")

    def raw_capture_checksums(self):
        """The proxy's requests and the items they reference. The normalizer
        may add items, but only for call context a request did not store."""
        return [
            self.scalar(f"SELECT count(), sum(cityHash64(*)) FROM {table}")
            for table in (
                "llm.requests",
                "llm.request_items FINAL WHERE hash IN (SELECT part.hash FROM llm.requests "
                "ARRAY JOIN request_parts AS part)",
            )
        ]

    def job(self, name, hold="10m"):
        """One run of the job: the requests not normalized yet, the state of
        the sessions they touch, then the normalizer. Returns the request ids
        it read and the messages it wrote."""
        out = self.temp / name
        out.mkdir()
        rows = self.query(
            (NORMALIZER / "requests.sql").read_text(),
            params=(
                ("after", "2000-01-01 00:00:00"),
                ("before", "2100-01-01 00:00:00"),
            ),
        ).stdout
        sent = [
            item
            for row in rows.splitlines()
            for item in json.loads(row)["items"]
            if item
        ]
        assert len(sent) == len(set(sent)), "an item was sent twice"
        sessions = run(
            str(self.normalizer), "-requests", "-sessions", input=rows
        ).stdout.strip()
        state = self.temp / f"{name}-state.jsonl"
        state.write_text(
            self.query(
                (NORMALIZER / "state.sql").read_text(),
                params=(("sessions", sessions),),
            ).stdout
        )
        run(
            str(self.normalizer),
            "-requests",
            "-hold",
            hold,
            "-state",
            str(state),
            "-out",
            str(out),
            input=rows,
        )
        self.load(out)
        return [json.loads(row)["request_id"] for row in rows.splitlines()], jsonl(
            out / "llm.messages.jsonl"
        )

    def export(self, dialect, rows, check=True):
        return run(str(self.normalizer), "-export", dialect, input=rows, check=check)

    def history_rows(self):
        return {
            r["trace_id"]: r
            for r in map(json.loads, self.query(HISTORY, "grafana").stdout.splitlines())
        }

    def expected_history(self):
        return sorted(
            self.scalar(
                "SELECT groupArray(event_id) FROM llm.call_history WHERE requested_at < "
                "(SELECT min(requested_at) FROM llm.usage)"
            )
            .strip("[]")
            .replace("'", "")
            .split(",")
        )


def normalize_the_first_batch(archive):
    archive.arrive(1)
    return archive.job("proxy-1")


def check_recent_requests_wait_for_their_usage(archive, first):
    archive.arrive(2, ["llm.requests"])
    recent = f"{int(time.time() - datetime(2026, 11, 10, 8, tzinfo=UTC).timestamp())}s"
    assert sorted(archive.job("proxy-2-early", recent)[0]) == sorted(SECOND_BATCH), (
        "the early run did not read the second batch's requests"
    )
    assert archive.scalar("SELECT count() FROM llm.calls") == str(len(first)), (
        "placed requests without usage"
    )


def check_the_second_batch_continues_the_first(archive, first, first_messages):
    second, second_messages = archive.job("proxy-2")
    assert sorted(first) == sorted(
        r["request_id"]
        for r in archive.requests_rows
        if r["request_id"] not in SECOND_BATCH
    ), first
    assert sorted(second) == sorted(SECOND_BATCH), second
    assert (
        archive.scalar(
            "SELECT session_id FROM llm.calls FINAL WHERE call_id = 'claude-agent'"
        )
        == "claude:11111111-1111-4111-8111-111111111111:agent:a1b2c3d4e5f6a7b8c"
    ), "claude-agent is not in its own subagent session"
    assert archive.job("proxy-3")[0] == [], "a third run found requests left"
    written = {m["id"] for m in first_messages}
    assert not [m for m in second_messages if m["id"] in written], (
        "the second run wrote the first run's messages again",
        second_messages,
    )


def check_history_is_empty_until_the_transcript_import(archive):
    assert archive.query(HISTORY, "grafana").stdout == "", (
        "history rows before any transcript call was imported"
    )
    insert_transcript_rows(archive.query)


def check_every_request_is_exactly_one_proxy_call(archive):
    calls = "SELECT request_id FROM llm.calls FINAL WHERE origin = 'proxy'"
    assert (
        archive.scalar(f"SELECT count() FROM ({calls})")
        == archive.scalar("SELECT count() FROM llm.requests")
        == "10"
    ), "proxy calls and requests differ in number"
    assert (
        archive.scalar(
            f"SELECT count() FROM (SELECT request_id FROM llm.requests EXCEPT {calls})"
        )
        == "0"
    ), "a request has no proxy call"
    assert (
        archive.scalar(
            f"SELECT count() FROM ({calls} EXCEPT SELECT request_id FROM llm.requests)"
        )
        == "0"
    ), "a proxy call names a missing request"


def check_only_the_unarchived_previous_response_starts_at_a_marker(archive):
    assert (
        archive.scalar("SELECT count() FROM llm.messages FINAL WHERE format = 'proxy'")
        == "1"
    ), "proxy marker messages other than the unarchived previous response"


def check_every_proxy_message_resolves_to_its_raw_source(archive):
    assert (
        archive.scalar("""
                SELECT count() FROM llm.messages FINAL
                WHERE item != 0 AND ((call_id, item) NOT IN (
                        SELECT request_id, part.hash FROM llm.requests ARRAY JOIN request_parts AS part)
                    OR item NOT IN (SELECT hash FROM llm.request_items))
            """)
        == "0"
    ), "an input message's item is not one its call's request sent"
    assert archive.scalar("SELECT countIf(item != 0) > 0 FROM llm.messages") == "1", (
        "no message points at a request item"
    )
    assert (
        archive.scalar("""
                SELECT count() FROM llm.messages FINAL
                WHERE path = '' AND output AND call_id NOT IN (SELECT request_id FROM llm.requests)
            """)
        == "0"
    ), "an output message's call has no request"
    assert (
        archive.scalar(
            "SELECT count() FROM (SELECT arrayJoin(context).hash AS hash FROM llm.calls) "
            "WHERE hash NOT IN (SELECT hash FROM llm.request_items)"
        )
        == "0"
    ), "a call's context names a missing request item"
    assert (
        archive.scalar(
            "SELECT count() FROM llm.request_items "
            "WHERE hash != reinterpretAsUInt128(substring(SHA256(item), 1, 16))"
        )
        == "0"
    ), "a request item's hash is not the SHA256 prefix of its bytes"


def check_grafana_sees_only_the_metrics_view(archive):
    for table in (
        "llm.messages",
        "llm.calls",
        "llm.events",
        "llm.sessions",
        "llm.call_history",
    ):
        assert (
            archive.query(f"SELECT * FROM {table}", "grafana", check=False).returncode
            != 0
        ), table


def check_history_is_transcript_calls_priced_like_the_proxys(archive):
    rows = archive.history_rows()
    assert (
        sorted(rows) == archive.expected_history() == ["c1", "codex-t1", "req_011"]
    ), rows
    assert (
        rows["req_011"]["origin"] == "history:claude-code"
        and rows["req_011"]["input_tokens"] == 2010
    ), rows
    assert (
        abs(
            rows["req_011"]["estimated_cost_usd"] - (10 * 5 + 2000 * 10 + 64 * 25) / 1e6
        )
        < 1e-12
    ), ("the one-hour cache write is not priced as the proxy prices it", rows)


def check_prompts_count_each_prompt_once(archive, sql):
    prompts = archive.query(sql["prompts"]).stdout
    assert prompts.count("The nightly backup job fails; find out why.") == 1, (
        "a prompt both sources hold counted twice",
        prompts,
    )
    assert prompts.count("List the flake inputs.") == 1, prompts
    assert "Why does the dashboard show no cost for luna?" in prompts, prompts
    assert "Add a Renovate rule" not in prompts, (
        "a July prompt counted as last week's",
        prompts,
    )
    assert "permissions instructions" not in prompts, prompts


def check_tool_failures_per_model_and_tool(archive, sql):
    failures = [
        line.split("\t")
        for line in archive.query(sql["tool-failures"]).stdout.splitlines()
    ]
    failures = {
        (model, tool): (int(uses), int(failed))
        for model, tool, uses, failed in failures
    }
    assert failures[("claude-opus-5-5", "Bash")] == (1, 1), failures
    assert failures[("gpt-6.1-sol", "exec")] == (1, 0), failures


def check_tokens_count_every_claude_code_call_of_the_day(archive, sql):
    tokens = archive.query(sql["tokens"]).stdout
    assert "2026-11-10\tclaude-code\tclaude-opus-5-5\t3\t" in tokens, (
        "claude-1, claude-2 and the truncated request are not three calls",
        tokens,
    )


def check_usage_shared_by_a_trace_is_priced_once(archive, sql):
    cost = sum(
        float(line.split("\t")[3])
        for line in archive.query(sql["cost"]).stdout.splitlines()
        if not line.endswith("\\N")
    )
    live = float(
        archive.scalar(
            "SELECT sum(estimated_cost_usd) FROM llm.usage_metrics WHERE origin = 'live'"
        )
    )
    by_trace = float(
        archive.scalar(
            "SELECT sum(u.estimated_cost_usd) FROM llm.calls AS c FINAL "
            "INNER JOIN llm.requests AS r ON r.request_id = c.request_id "
            "INNER JOIN llm.usage_metrics AS u ON u.trace_id = r.trace_id"
        )
    )
    assert live > 0 and abs(cost - live) < 1e-9 and by_trace > live, (
        "a usage row of trace ws-1 was priced more than once",
        cost,
        live,
        by_trace,
    )


def check_a_tool_result_with_user_text_stays_a_user_turn(archive, sql):
    path = archive.query(sql["conversation"], params=(SESSION,)).stdout
    roles = [(m["role"], m["output"]) for m in map(json.loads, path.splitlines())]
    assert roles == [
        ("user", False),
        ("assistant", True),
        ("user", False),
        ("assistant", True),
    ], roles
    exported = json.loads(archive.export("openai", path).stdout)
    assert [m["role"] for m in exported["messages"]] == [
        "user",
        "assistant",
        "tool",
        "user",
        "assistant",
    ], exported
    assert exported["messages"][1]["tool_calls"][0]["function"]["name"] == "Bash", (
        exported
    )


def check_calls_export_with_the_instructions_and_tools_they_ran_with(archive, sql):
    """codex-2 is a delta request that sent no instructions or tools; its
    response echoes the tools in effect."""
    for call, system, tools in (
        ("claude-2", "You are Claude Code", ["Bash", "Read"]),
        ("codex-1", "You are Codex", ["exec", "update_plan"]),
        ("codex-2", "", ["exec", "update_plan"]),
    ):
        rows = archive.query(sql["call"], params=(("call", call),)).stdout
        openai = json.loads(archive.export("openai", rows).stdout)
        anthropic = json.loads(archive.export("anthropic", rows).stdout)
        for exported in (openai, anthropic):
            names = [
                (t.get("function") or t.get("custom") or t)["name"]
                for t in exported.get("tools", [])
            ]
            assert names == tools, (call, exported)
            assert exported["messages"][-1]["role"] == "assistant", (
                call,
                exported,
            )
        weights = [
            m.get("weight") for m in openai["messages"] if m["role"] == "assistant"
        ]
        assert weights[-1] is None and all(w == 0 for w in weights[:-1]), (
            "only the call's own output is a training target",
            call,
            weights,
        )
        if call == "codex-1":
            assert openai["tools"][0]["type"] == "custom", (
                "the freeform exec tool is not custom",
                openai["tools"],
            )
            assert openai["messages"][-1]["tool_calls"][0]["type"] == "custom", (
                "the freeform exec call is not custom",
                openai["messages"],
            )
            assert anthropic["messages"][-1]["content"][-1]["input"] == {
                "input": "const r = await tools.exec_command({cmd: 'rg luna'});\ntext(r)"
            }, ("the freeform exec call lost its input", anthropic["messages"])
        first = openai["messages"][0]
        assert (first["role"] == "system") == bool(system) and first[
            "content"
        ].startswith(system), (call, first)
        assert anthropic["system"].startswith(system or "<permissions instructions>"), (
            call,
            anthropic,
        )


def check_calls_without_tools_or_outputs_are_refused(archive, sql):
    """The call query marks a Pi compaction's rows as a call's even without
    context or outputs, so the export must refuse it itself."""
    for call, reason in (("codex-t1", "does not define"), ("c1", "no output")):
        rows = archive.query(sql["call"], params=(("call", call),)).stdout
        failed = archive.export("openai", rows, check=False)
        assert failed.returncode != 0 and reason in failed.stderr, (
            call,
            failed,
        )


def check_a_truncated_request_is_no_training_example(archive, sql):
    rows = archive.query(sql["call"], params=(("call", "truncated"),)).stdout
    failed = archive.export("openai", rows, check=False)
    assert failed.returncode != 0 and "no output" in failed.stderr, failed


def check_raw_returns_request_items_and_response_bodies(archive, sql):
    raw = archive.query(sql["raw"], params=(SESSION,)).stdout
    assert '"cache_control"' in raw and "signature_delta" in raw, raw


def check_a_transcript_call_exports_with_its_context(archive, sql):
    rows = archive.query(sql["call"], params=(("call", "req_011"),)).stdout
    anthropic = json.loads(archive.export("anthropic", rows).stdout)
    assert anthropic["system"].startswith("You are Claude Code") and [
        t["name"] for t in anthropic["tools"]
    ] == ["Bash", "Read"], anthropic


def check_subagents_lists_a_codex_subagent_under_its_parent(archive, sql):
    agents = archive.query(sql["subagents"]).stdout
    assert (
        "codex:01a1da81-0000-7000-8000-000000000001\tcodex:01a1da81-0000-7000-8000-000000000001:agent:pricing_review"
        in agents
    ), agents


def check_each_attempt_belongs_to_exactly_one_call(archive, sql):
    """In trace ws-tight, call A spans 0-30 ms and B starts at 40 ms, so A's
    attempt at 0 ms is also within B's 50 ms of slack, and B's attempt at
    35 ms only within the slack. Each attempt still belongs to exactly one
    call, for its session and its cost."""
    base = "2026-11-10 13:00:00"
    for call, started, completed, attempt in (
        ("tight-a", ".000", ".030", ".000"),
        ("tight-b", ".040", ".070", ".035"),
    ):
        body = json.dumps(
            {
                "type": "response.completed",
                "response": {
                    "id": f"resp_{call}",
                    "object": "response",
                    "model": "gpt-6.1-sol",
                    "output": [],
                    "usage": {"input_tokens": 1000, "output_tokens": 10},
                },
            }
        )
        archive.query(
            "INSERT INTO llm.requests FORMAT JSONEachRow\n"
            + json.dumps(
                {
                    "request_id": call,
                    "trace_id": "ws-tight",
                    "started_at": base + started,
                    "completed_at": base + completed,
                    "source_format": "openai-response",
                    "model": "gpt-6.1-sol",
                    "outcome": "succeeded",
                    "status_code": 200,
                    "user_agent": "T3 Code/0.0.30",
                    "request_envelope": "{}",
                    "request_parts": [],
                    "response_body": body,
                }
            ),
            "cliproxy",
        )
        archive.query(
            "INSERT INTO llm.usage FORMAT JSONEachRow\n"
            + json.dumps(
                {
                    "request_id": f"usage-{call}",
                    "trace_id": "ws-tight",
                    "session_id": f"codex:{call}",
                    "requested_at": base + attempt,
                    "provider": "codex",
                    "model": "gpt-6.1-sol",
                    "input_tokens": 1000,
                    "output_tokens": 10,
                }
            ),
            "cliproxy",
        )
    assert sorted(archive.job("proxy-tight")[0]) == ["tight-a", "tight-b"]
    assert (
        archive.scalar(
            "SELECT groupArray((call_id, session_id)) FROM (SELECT call_id, session_id "
            "FROM llm.calls FINAL WHERE call_id LIKE 'tight-%' ORDER BY call_id)"
        )
        == "[('tight-a','codex:tight-a'),('tight-b','codex:tight-b')]"
    ), "a tight call is not in its own attempt's session"
    cost = [line.split("\t") for line in archive.query(sql["cost"]).stdout.splitlines()]
    assert sorted(
        (session, attempts) for session, _, attempts, _ in cost if "tight" in session
    ) == [("codex:tight-a", "1"), ("codex:tight-b", "1")], (
        "a tight attempt counted for both calls",
        cost,
    )
    live = float(
        archive.scalar(
            "SELECT sum(estimated_cost_usd) FROM llm.usage_metrics WHERE origin = 'live'"
        )
    )
    assert abs(sum(float(c[3]) for c in cost if c[3] != "\\N") - live) < 1e-9, (
        "the cost query and the live usage disagree",
        cost,
        live,
    )


def check_a_failed_empty_delta_request_is_no_training_example(archive, sql):
    """codex-failed continues codex-2, sent nothing new and got nothing back,
    so it ends where codex-2 ended. That output is codex-2's."""
    archive.query(
        "INSERT INTO llm.requests FORMAT JSONEachRow\n"
        + json.dumps(
            {
                "request_id": "codex-failed",
                "trace_id": "ws-failed",
                "started_at": "2026-11-10 10:00:20.000",
                "completed_at": "2026-11-10 10:00:21.000",
                "source_format": "openai-response",
                "model": "gpt-6.1-sol",
                "outcome": "failed",
                "status_code": 502,
                "user_agent": "T3 Code/0.0.30",
                "request_envelope": json.dumps(
                    {"previous_response_id": "resp_B", "input": []}
                ),
                "request_parts": [],
                "response_body": "",
            }
        ),
        "cliproxy",
    )
    archive.query(
        "INSERT INTO llm.usage FORMAT JSONEachRow\n"
        + json.dumps(
            {
                "request_id": "usage-codex-failed",
                "trace_id": "ws-failed",
                "session_id": "codex:01a1da81-0000-7000-8000-000000000001",
                "requested_at": "2026-11-10 10:00:20.001",
                "provider": "codex",
                "model": "gpt-6.1-sol",
            }
        ),
        "cliproxy",
    )
    assert archive.job("proxy-failed")[0] == ["codex-failed"]
    rows = archive.query(sql["call"], params=(("call", "codex-failed"),)).stdout
    assert json.loads(rows.splitlines()[-1])["output"], (
        "codex-failed does not end at codex-2's output",
        rows,
    )
    failed = archive.export("openai", rows, check=False)
    assert failed.returncode != 0 and "no output" in failed.stderr, failed


def check_rerunning_the_schema_keeps_the_history(archive, schema):
    kept = archive.history_rows()
    run(
        "docker",
        "exec",
        "-i",
        archive.container,
        "clickhouse-client",
        "--multiquery",
        input=schema,
    )
    assert (
        archive.history_rows() == kept and sorted(kept) == archive.expected_history()
    ), ("rerunning schema.sql changed the history", kept)


def main():
    config = json.loads(
        run("yq", "-o=json", str(BASE / "apps/clickhouse/configmap.yaml")).stdout
    )["data"]
    statefulset = json.loads(
        run("yq", "-o=json", str(BASE / "apps/clickhouse/statefulset.yaml")).stdout
    )
    server = statefulset["spec"]["template"]["spec"]["containers"][0]
    image, command = server["image"], server["command"]
    check_password_guard(image, command)
    schema = config["schema.sql"]
    container = f"infra-llm-conversations-test-{os.getpid()}"
    with tempfile.TemporaryDirectory(prefix="infra-llm-conversations-") as directory:
        temp = Path(directory)
        temp.chmod(0o755)
        for name, text in (
            ("config.xml", config["config.xml"]),
            ("users.xml", config["users.xml"]),
            ("schema.sql", schema),
        ):
            (temp / name).write_text(text)
        archive = Archive(container, temp)
        try:
            archive.start(image, command)
            archive.wait_for_schema()
            archive.insert_plugin_sources()

            first, first_messages = normalize_the_first_batch(archive)
            check_recent_requests_wait_for_their_usage(archive, first)
            archive.arrive(2, ["llm.usage"])
            raw_capture = archive.raw_capture_checksums()
            check_the_second_batch_continues_the_first(archive, first, first_messages)
            assert archive.raw_capture_checksums() == raw_capture, (
                "normalizing changed the raw capture"
            )

            check_history_is_empty_until_the_transcript_import(archive)
            check_every_request_is_exactly_one_proxy_call(archive)
            check_only_the_unarchived_previous_response_starts_at_a_marker(archive)
            check_every_proxy_message_resolves_to_its_raw_source(archive)
            check_grafana_sees_only_the_metrics_view(archive)
            check_history_is_transcript_calls_priced_like_the_proxys(archive)

            sql = examples()
            check_prompts_count_each_prompt_once(archive, sql)
            check_tool_failures_per_model_and_tool(archive, sql)
            check_tokens_count_every_claude_code_call_of_the_day(archive, sql)
            check_usage_shared_by_a_trace_is_priced_once(archive, sql)
            check_a_tool_result_with_user_text_stays_a_user_turn(archive, sql)
            check_calls_export_with_the_instructions_and_tools_they_ran_with(
                archive, sql
            )
            check_calls_without_tools_or_outputs_are_refused(archive, sql)
            check_a_truncated_request_is_no_training_example(archive, sql)
            check_raw_returns_request_items_and_response_bodies(archive, sql)
            check_a_transcript_call_exports_with_its_context(archive, sql)
            check_subagents_lists_a_codex_subagent_under_its_parent(archive, sql)
            check_each_attempt_belongs_to_exactly_one_call(archive, sql)
            check_a_failed_empty_delta_request_is_no_training_example(archive, sql)
            check_rerunning_the_schema_keeps_the_history(archive, schema)
            print(
                f"PASS: {len(sql)} example queries, proxy references both ways, unchanged raw capture, "
                "usage history, permissions"
            )
        finally:
            run("docker", "rm", "--force", container, check=False)
        job_in_cluster(image, temp, archive.sources)


class ClusterJob:
    def __init__(self, container):
        self.container = container

    def start(self, image, temp, tools):
        run(
            "docker",
            "run",
            "--detach",
            "--name",
            self.container,
            "--network",
            "none",
            "--memory",
            "2g",
            "--cpus",
            "2",
            "-e",
            "CLICKHOUSE_SKIP_USER_SETUP=1",
            "-e",
            f"LLM_NORMALIZER_PASSWORD={PASSWORD}",
            "-v",
            f"{temp}/config.xml:/etc/clickhouse-server/config.d/archive.xml:ro",
            "-v",
            f"{temp}/users.xml:/etc/clickhouse-server/users.d/archive.xml:ro",
            "-v",
            f"{temp}/schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro",
            "-v",
            f"{tools}:/opt/normalizer:ro",
            image,
        )

    def query(self, sql, user="default"):
        return run(
            "docker",
            "exec",
            "-i",
            self.container,
            "clickhouse-client",
            "--user",
            user,
            input=sql,
        ).stdout.strip()

    def wait_for_the_real_server(self):
        """The entrypoint runs schema.sql on a temporary server, then starts
        the real one, so the schema is ready once it answers twice."""
        ready = 0
        for _ in range(240):
            ready = (
                ready + 1
                if run(
                    "docker",
                    "exec",
                    self.container,
                    "clickhouse-client",
                    "--query",
                    "EXISTS TABLE llm.usage_metrics",
                    check=False,
                ).stdout.strip()
                == "1"
                else 0
            )
            if ready == 2:
                break
            time.sleep(1)
        else:
            raise RuntimeError(run("docker", "logs", self.container).stdout)

    def normalize(self, mode, *env):
        return run(
            "docker",
            "exec",
            "-u",
            "101",
            "-e",
            "CLICKHOUSE_HOST=localhost",
            "-e",
            "SCRATCH=/tmp/scratch",
            "-e",
            "HOME=/tmp",
            "-e",
            f"CLICKHOUSE_PASSWORD={PASSWORD}",
            *env,
            self.container,
            "/opt/normalizer/normalize.sh",
            mode,
            check=False,
        )

    def as_normalizer(self, sql, *password):
        return run(
            "docker",
            "exec",
            "-i",
            self.container,
            "clickhouse-client",
            "--user",
            "llm_normalizer",
            *password,
            input=sql,
            check=False,
        )

    def over_http(self, password):
        url = (
            "http://localhost:8123/?user=llm_normalizer"
            + (f"&password={password}" if password else "")
            + "&query=SELECT%20count()%20FROM%20llm.requests"
        )
        return run(
            "docker",
            "exec",
            "-i",
            self.container,
            "clickhouse-client",
            input=f"SELECT * FROM url('{url}', TSV, 'n UInt64')",
            check=False,
        )


def build_the_job_for_the_container_platform(temp):
    tools = temp / "normalizer"
    tools.mkdir()
    arch = run("docker", "version", "--format", "{{.Server.Arch}}").stdout.strip()
    run(
        "go",
        "build",
        "-o",
        str(tools / "normalize-conversations"),
        "./normalize-conversations",
        cwd=PLUGINS,
        env={**os.environ, "CGO_ENABLED": "0", "GOOS": "linux", "GOARCH": arch},
    )
    for name in ["normalize.sh", *(p.name for p in NORMALIZER.glob("*.sql"))]:
        (tools / name).write_bytes((NORMALIZER / name).read_bytes())
        (tools / name).chmod(0o755)
    return tools


def insert_sources_and_transcript_rows(job, sources):
    for table in ("llm.request_items", "llm.requests", "llm.usage"):
        job.query(
            f"INSERT INTO {table} FORMAT JSONEachRow\n"
            + (sources / f"{table}.jsonl").read_text(),
            "cliproxy",
        )
    insert_transcript_rows(job.query)


def check_cron_normalizes_every_proxy_request(job):
    result = job.normalize("cron")
    assert result.returncode == 0, result.stdout + result.stderr
    assert (
        job.query("SELECT count() FROM llm.calls FINAL WHERE origin = 'proxy'") == "10"
    ), "the job did not make a proxy call of every request"


def check_verify_passes_over_proxy_and_transcript_rows(job):
    result = job.normalize("verify")
    assert result.returncode == 0, result.stdout + result.stderr
    checks = [
        line.split("\t")
        for line in result.stdout.splitlines()
        if line.startswith("check\t")
    ]
    assert len(checks) >= 10 and all(c[2] == "0" for c in checks), checks


def check_cron_finds_nothing_left(job):
    rows = job.query("SELECT count() FROM llm.messages")
    result = job.normalize("cron")
    assert (
        result.returncode == 0 and job.query("SELECT count() FROM llm.messages") == rows
    ), ("a second run wrote messages", result.stderr)


def check_cron_catches_up_from_the_oldest_missed_request(job):
    """After a stop of any length, the job catches up an hour at a time from
    the oldest request it misses. Once its budget is spent it stops after the
    window it ran, and the next run goes on."""
    late = (("late-6d", 150), ("late-3d", 75), ("late-2h", 2))
    for call, hours in late:
        started = (datetime.now(UTC) - timedelta(hours=hours)).strftime(
            "%Y-%m-%d %H:%M:%S"
        )
        body = json.dumps(
            {
                "type": "response.completed",
                "response": {
                    "id": f"resp_{call}",
                    "object": "response",
                    "model": "gpt-6.1-sol",
                    "output": [],
                    "usage": {"input_tokens": 100, "output_tokens": 1},
                },
            }
        )
        job.query(
            "INSERT INTO llm.requests FORMAT JSONEachRow\n"
            + json.dumps(
                {
                    "request_id": call,
                    "trace_id": call,
                    "started_at": f"{started}.000",
                    "completed_at": f"{started}.500",
                    "source_format": "openai-response",
                    "model": "gpt-6.1-sol",
                    "outcome": "succeeded",
                    "status_code": 200,
                    "user_agent": "T3 Code/0.0.30",
                    "request_envelope": "{}",
                    "request_parts": [],
                    "response_body": body,
                }
            ),
            "cliproxy",
        )
        job.query(
            "INSERT INTO llm.usage FORMAT JSONEachRow\n"
            + json.dumps(
                {
                    "request_id": f"usage-{call}",
                    "trace_id": call,
                    "session_id": f"codex:{call}",
                    "requested_at": f"{started}.001",
                    "provider": "codex",
                    "model": "gpt-6.1-sol",
                }
            ),
            "cliproxy",
        )
    caught_up = "SELECT groupArray(call_id) FROM (SELECT call_id FROM llm.calls FINAL WHERE call_id LIKE 'late-%' ORDER BY started_at)"
    for done in (1, 2, 3):
        result = job.normalize("cron", "-e", "BUDGET=0")
        assert result.returncode == 0 and "the budget is spent" in result.stdout, (
            result.stdout + result.stderr
        )
        assert (
            job.query(caught_up)
            == "[" + ",".join(f"'{call}'" for call, _ in late[:done]) + "]"
        ), (
            "a run with its budget spent did not stop after one window",
            done,
            result.stdout,
        )
    result = job.normalize("cron")
    assert result.returncode == 0 and len(result.stdout.splitlines()) == 1, (
        result.stdout + result.stderr
    )


def check_grafana_still_sees_the_transcript_history(job):
    assert (
        job.query(
            "SELECT countIf(origin LIKE 'history:%') > 0 FROM llm.usage_metrics",
            "grafana",
        )
        == "1"
    ), "the history before the proxy is missing from the metrics view"


def check_the_normalizer_reads_sources_and_only_appends(job, requests):
    assert (
        job.as_normalizer(
            "SELECT count() FROM llm.requests", "--password", PASSWORD
        ).stdout.strip()
        == requests
    ), "the normalizer cannot read the requests"
    for sql in (
        "SELECT * FROM llm.usage_metrics",
        "INSERT INTO llm.requests (request_id) VALUES ('x')",
        "ALTER TABLE llm.calls DELETE WHERE 1",
        "DROP TABLE llm.events",
    ):
        denied = job.as_normalizer(sql, "--password", PASSWORD)
        assert denied.returncode != 0 and "ACCESS_DENIED" in denied.stderr, (
            sql,
            denied.stderr,
        )


def check_the_normalizer_needs_its_password_on_both_ports(job, requests):
    """CLIProxy's and Grafana's pods reach the HTTP port, so without the
    password neither port may read the raw history as the normalizer."""
    assert job.over_http(PASSWORD).stdout.strip() == requests, (
        "the normalizer cannot read the requests over HTTP"
    )
    for password in ("", "wrong"):
        denied = job.over_http(password)
        assert denied.returncode != 0 and "AUTHENTICATION_FAILED" in denied.stderr, (
            denied.stderr
        )
        denied = job.as_normalizer(
            "SELECT count() FROM llm.requests",
            *(["--password", password] if password else []),
        )
        assert denied.returncode != 0 and "AUTHENTICATION_FAILED" in denied.stderr, (
            denied.stderr
        )


def job_in_cluster(image, temp, sources):
    """The cluster's llm-normalizer CronJob: normalize.sh in the ClickHouse
    image, as llm_normalizer over the native port, from the same source rows."""
    container = f"infra-llm-normalizer-test-{os.getpid()}"
    tools = build_the_job_for_the_container_platform(temp)
    job = ClusterJob(container)
    try:
        job.start(image, temp, tools)
        job.wait_for_the_real_server()
        insert_sources_and_transcript_rows(job, sources)
        check_cron_normalizes_every_proxy_request(job)
        check_verify_passes_over_proxy_and_transcript_rows(job)
        check_cron_finds_nothing_left(job)
        check_cron_catches_up_from_the_oldest_missed_request(job)
        check_grafana_still_sees_the_transcript_history(job)
        requests = job.query("SELECT count() FROM llm.requests")
        check_the_normalizer_reads_sources_and_only_appends(job, requests)
        check_the_normalizer_needs_its_password_on_both_ports(job, requests)
        print(
            "PASS: the in-cluster job, its catch-up and checks, with the normalizer's grants"
        )
    finally:
        run("docker", "rm", "--force", container, check=False)


if __name__ == "__main__":
    main()
