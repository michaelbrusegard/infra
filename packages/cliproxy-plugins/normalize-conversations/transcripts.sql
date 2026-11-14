-- Input for `normalize-conversations -in`: every transcript line, grouped by
-- file in line order. The import is one pass over all of them, since which
-- file holds a reply's call depends on every file. Pass the proxy's calls
-- with -proxied, from
-- SELECT c.session_id, s.parent_session_id, c.client, c.response_id, c.started_at
-- FROM llm.calls AS c FINAL
-- INNER JOIN (SELECT session_id, parent_session_id FROM llm.sessions FINAL WHERE origin = 'proxy') AS s
--     ON s.session_id = c.session_id
-- WHERE c.origin = 'proxy' FORMAT TSV
--
-- The largest kinds of line the import drops are sent as their type alone,
-- which is all the normalizer reads of them, to count them: Codex events
-- other than token counts, interruptions, and rollbacks, Codex world state,
-- and Claude Code's request blobs. That is about a fifth of the bytes, and
-- the normalizer's rows are the same either way.
SELECT source, host, session, id, path,
    multiIf(
        source = 'codex' AND (type = 'world_state'
            OR type = 'event_msg' AND subtype NOT IN ('token_count', 'turn_aborted', 'thread_rolled_back')),
            concat('{"type":', toJSONString(type), ',"payload":{"type":', toJSONString(subtype), '}}'),
        source = 'claude-code' AND type = 'api-request-blob',
            concat('{"type":', toJSONString(type), '}'),
        raw) AS line,
    toString(ts) AS ts
FROM (
    SELECT source, host, session, id, path, line AS raw, ts,
        JSONExtractString(raw, 'type') AS type, JSONExtractString(raw, 'payload', 'type') AS subtype
    FROM llm.transcripts FINAL
)
ORDER BY source, host, path, session, toUInt64OrZero(id), id
SETTINGS max_threads = 1, max_block_size = 256, preferred_block_size_bytes = 1048576
FORMAT JSONEachRow
