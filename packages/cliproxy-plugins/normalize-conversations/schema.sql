-- Canonical LLM conversations, proposed in docs/llm-conversations.md and
-- written by packages/cliproxy-plugins/normalize-conversations. These tables
-- are a view derived from the raw capture, which stays the only copy of
-- every source record: llm.requests and llm.request_items for the proxy,
-- llm.transcripts for agent logs. Rows reference raw rows instead of
-- copying them, so the tables can be dropped and rebuilt at any time.

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
-- are for querying, and the raw source is referenced: a proxy input by the
-- llm.request_items hash it was read from (zero when the request's envelope
-- held it), a proxy output by call_id, whose llm.requests row holds the
-- response, and a transcript message by its llm.transcripts line, as host,
-- path, and line ID. part names what inside the line a message was built
-- from, if not the whole line. A node written again keeps the row with the
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
-- lines recorded; its messages and events name the lines.
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
    output_tokens UInt64,
    reasoning_tokens UInt64
)
ENGINE = ReplacingMergeTree
PARTITION BY toYYYYMM(started_at)
ORDER BY (session_id, started_at, call_id);

-- Transcript lines that are not messages, such as token counts, turn
-- settings, or attachments the model never saw, by their llm.transcripts
-- line. Files that share a session, such as one synced to two hosts, share
-- line numbers and times, so the file is part of the key.
CREATE TABLE IF NOT EXISTS llm.events
(
    session_id String,
    ts DateTime64(3, 'UTC'),
    host LowCardinality(String),
    path String,
    line String,
    type LowCardinality(String)
)
ENGINE = ReplacingMergeTree
ORDER BY (session_id, ts, host, path, line);
