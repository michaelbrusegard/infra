-- Input for `normalize-conversations`: transcript lines, grouped by file in
-- line order. Files come in path order, which puts a Claude Code session
-- before its sub-agents, so a reply a sub-agent copied stays its parent's
-- call. Pass the proxy's calls with -proxied, from
-- SELECT c.session_id, s.parent_session_id, c.client, c.response_id, c.started_at
-- FROM llm.calls AS c FINAL
-- INNER JOIN (SELECT session_id, parent_session_id FROM llm.sessions FINAL WHERE origin = 'proxy') AS s
--     ON s.session_id = c.session_id
-- WHERE c.origin = 'proxy' FORMAT TSV
SELECT source, host, session, id, path, line, toString(ts) AS ts
FROM llm.transcripts FINAL
ORDER BY source, host, path, session, toUInt64OrZero(id), id
SETTINGS max_threads = 1, max_block_size = 256, preferred_block_size_bytes = 1048576
FORMAT JSONEachRow
