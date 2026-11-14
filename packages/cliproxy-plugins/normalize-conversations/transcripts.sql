-- Input for `normalize-conversations`: transcript lines, grouped by file in
-- line order. Pass the proxy's sessions with -proxied, from
-- SELECT DISTINCT session_id FROM llm.calls WHERE origin = 'proxy'.
SELECT source, host, session, id, path, line, toString(ts) AS ts
FROM llm.transcripts FINAL
ORDER BY source, host, session, path, toUInt64OrZero(id), id
SETTINGS max_threads = 1, max_block_size = 256, preferred_block_size_bytes = 1048576
FORMAT JSONEachRow
