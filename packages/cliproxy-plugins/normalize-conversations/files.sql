-- The transcript files by source, host, and session, with their bytes, for
-- splitting transcripts.sql into parts.
SELECT source, host, session, sum(length(line)) AS bytes
FROM llm.transcripts FINAL
GROUP BY source, host, session
ORDER BY source, host, session
FORMAT JSONEachRow
