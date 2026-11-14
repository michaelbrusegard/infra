-- Canonical LLM conversations, proposed in docs/llm-conversations.md and
-- written by packages/cliproxy-plugins/normalize-conversations. Raw JSON
-- lives once in llm.request_items, referenced by content hash.

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
-- parent's, so resent context maps to existing nodes. The extracted blocks
-- are for querying; item is the exact source JSON. A node written again
-- keeps the row with the highest version: a model's output over a resent
-- copy, then the earliest, whatever order the calls were normalized in.
-- Transcript messages record the line and the host and path of its file.
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
    line String,
    host LowCardinality(String),
    path String,
    version UInt64
)
ENGINE = ReplacingMergeTree(version)
-- Conversation order keeps a session's text adjacent, which compresses.
ORDER BY (session_id, seq, id);

-- One row per model call. Proxy calls keep every llm.requests column
-- verbatim, so the archived row rebuilds exactly: request_id is call_id, and
-- session_id and model, whose names here hold the canonical session and the
-- responding model, are source_session_id and source_model. Transcript
-- calls carry the usage their lines recorded.
CREATE TABLE IF NOT EXISTS llm.calls
(
    call_id String,
    session_id String,
    trace_id String,
    response_id String,
    started_at DateTime64(3, 'UTC'),
    completed_at DateTime64(3, 'UTC'),
    origin LowCardinality(String),
    client LowCardinality(String),
    source_format LowCardinality(String),
    model LowCardinality(String),
    input_id UInt128,
    output_ids Array(UInt128),
    uncached_input_tokens UInt64,
    cache_read_tokens UInt64,
    cache_write_tokens UInt64,
    output_tokens UInt64,
    reasoning_tokens UInt64,
    source_session_id String,
    source_model LowCardinality(String),
    requested_model LowCardinality(String),
    stream Bool,
    outcome LowCardinality(String),
    status_code UInt16,
    error String,
    user_agent LowCardinality(String),
    truncated Bool,
    request_envelope String CODEC(ZSTD(3)),
    request_parts Array(Tuple(field LowCardinality(String), position Int32, hash UInt128)) CODEC(ZSTD(3)),
    response_body String CODEC(ZSTD(3))
)
ENGINE = ReplacingMergeTree
PARTITION BY toYYYYMM(started_at)
ORDER BY (session_id, started_at, call_id);

-- Transcript records that are not messages, such as token counts, turn
-- settings, or attachments the model never saw. Files that share a session,
-- such as one synced to two hosts, share line numbers and times, so the
-- file is part of the key.
CREATE TABLE IF NOT EXISTS llm.events
(
    session_id String,
    ts DateTime64(3, 'UTC'),
    host LowCardinality(String),
    path String,
    line String,
    type LowCardinality(String),
    item UInt128
)
ENGINE = ReplacingMergeTree
ORDER BY (session_id, ts, host, path, line);
