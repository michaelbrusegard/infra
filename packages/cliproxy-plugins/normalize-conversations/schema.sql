-- Canonical LLM conversations, proposed in docs/llm-conversations.md and
-- written by packages/cliproxy-plugins/normalize-conversations. Proxy rows
-- are derived from the proxy's raw capture, llm.requests and
-- llm.request_items, which is kept for good: they reference it instead of
-- copying it, and can be dropped and rebuilt at any time. Transcript rows
-- are the only record of the agent logs once llm.transcripts is dropped, so
-- they hold their own content and are rebuilt only from a restored export.

-- What does not change as a session grows, per source: a session captured
-- by both the proxy and transcripts has a row for the proxy and one for each
-- transcript file, by host and path. The transcripts' messages end where the
-- proxy's calls begin.
CREATE TABLE IF NOT EXISTS llm.sessions
(
    session_id String,
    parent_session_id String,
    client LowCardinality(String),
    origin LowCardinality(String),
    host LowCardinality(String),
    path String,
    title String,
    cwd String
)
ENGINE = ReplacingMergeTree
ORDER BY (session_id, origin, host, path);

-- One row per node of a session's conversation tree. A node's ID covers its
-- parent's, so resent context maps to existing nodes. A proxy message's raw
-- source is referenced: an input by the llm.request_items hash it was read
-- from (zero when the request's envelope held it), an output by call_id,
-- whose llm.requests row holds the response. A transcript message's blocks
-- are all that is kept of it; host, path, and line name the line it came
-- from, and part what inside the line, if not the whole line. A node written again keeps the row with the
-- highest version: a model's output over a resent copy, then the earliest,
-- whatever order the calls were normalized in.
CREATE TABLE IF NOT EXISTS llm.messages
(
    session_id String,
    id UInt128,
    parent_id UInt128,
    seq UInt32,
    ts DateTime64(3, 'UTC'),
    role LowCardinality(String),
    output Bool,
    model LowCardinality(String),
    call_id String,
    blocks Array(Tuple(
        type LowCardinality(String),
        source_type LowCardinality(String),
        text String,
        tool_name LowCardinality(String),
        tool_namespace LowCardinality(String),
        tool_call_id String,
        tool_input String,
        is_error Bool,
        media LowCardinality(String))) CODEC(ZSTD(3)),
    format LowCardinality(String),
    item UInt128,
    host LowCardinality(String),
    path String,
    line String,
    part String,
    version UInt64
)
ENGINE = ReplacingMergeTree(version)
-- Conversation order keeps a session's text adjacent, which compresses.
ORDER BY (session_id, seq, id);

-- One row per model call. A proxy call names its llm.requests row, which
-- holds the request and response bodies, trace, status, and error. A
-- transcript call names its file by host and path, and carries the usage its
-- lines recorded and, for Claude Code calls with a request log, the system
-- prompt and tools as items in context, split as request_parts are.
CREATE TABLE IF NOT EXISTS llm.calls
(
    call_id String,
    session_id String,
    response_id String,
    started_at DateTime64(3, 'UTC'),
    completed_at DateTime64(3, 'UTC'),
    origin LowCardinality(String),
    client LowCardinality(String),
    request_id String,
    host LowCardinality(String),
    path String,
    source_format LowCardinality(String),
    model LowCardinality(String),
    input_id UInt128,
    output_ids Array(UInt128),
    uncached_input_tokens UInt64,
    cache_read_tokens UInt64,
    cache_write_tokens UInt64,
    cache_write_5m_tokens UInt64,
    cache_write_1h_tokens UInt64,
    output_tokens UInt64,
    reasoning_tokens UInt64,
    context Array(Tuple(field LowCardinality(String), position Int32, hash UInt128))
)
ENGINE = ReplacingMergeTree
PARTITION BY toYYYYMM(started_at)
ORDER BY (session_id, started_at, call_id);

-- How transcript sessions went, where no message or call records it: API
-- errors, refusal fallbacks, interrupted turns, and rollbacks, each with a
-- detail such as the error. Files that share a session, such as one synced
-- to two hosts, share line numbers and times, so the file is part of the
-- key.
CREATE TABLE IF NOT EXISTS llm.events
(
    session_id String,
    ts DateTime64(3, 'UTC'),
    host LowCardinality(String),
    path String,
    line String,
    type LowCardinality(String),
    detail String
)
ENGINE = ReplacingMergeTree
ORDER BY (session_id, ts, host, path, line);

-- Usage history from before the proxy, in llm.historical_usage's columns:
-- one row per transcript call with usage. llm.usage_metrics reads it in
-- place of llm.historical_usage, whose importer counted Codex's repeated
-- token counts again, so both can be dropped with llm.transcripts. The
-- provider follows the model, as the importer's did.
CREATE OR REPLACE VIEW llm.call_history AS
SELECT
    c.call_id AS event_id, c.client AS source, c.host AS host, c.session_id AS session_id,
    c.started_at AS requested_at,
    multiIf(startsWith(c.model, 'claude-'), 'claude', startsWith(c.model, 'gpt-'), 'codex',
        startsWith(c.model, 'kimi-'), 'kimi', startsWith(c.model, 'gemini-'), 'gemini', 'unknown') AS provider,
    if(c.model = '', '(unknown)', c.model) AS model,
    c.uncached_input_tokens AS uncached_input_tokens, c.cache_read_tokens AS cache_read_tokens,
    c.cache_write_tokens AS cache_creation_tokens, c.cache_write_5m_tokens AS cache_write_5m_tokens,
    c.cache_write_1h_tokens AS cache_write_1h_tokens, c.output_tokens AS output_tokens,
    least(c.reasoning_tokens, c.output_tokens) AS reasoning_tokens
FROM llm.calls AS c FINAL
WHERE c.origin = 'transcript'
    AND c.uncached_input_tokens + c.cache_read_tokens + c.cache_write_tokens + c.output_tokens > 0;
