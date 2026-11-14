-- Input for `normalize-conversations`: transcript lines, grouped by file in
-- line order. Pass the proxy's sessions, each with the start of its first
-- proxied call, with -proxied, from
-- SELECT session_id, min(started_at) FROM llm.calls FINAL WHERE origin = 'proxy'
-- GROUP BY session_id FORMAT TSV
SELECT source, host, session, id, path, line, toString(ts) AS ts
FROM llm.transcripts FINAL
ORDER BY source, host, session, path, toUInt64OrZero(id), id
SETTINGS max_threads = 1, max_block_size = 256, preferred_block_size_bytes = 1048576
FORMAT JSONEachRow
