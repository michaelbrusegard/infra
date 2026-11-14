-- The transcript files by source, host, and session, in parts of about
-- {bytes} bytes of lines, one line per part: the {files} array of
-- transcripts.sql. Each part's query then reads and sorts only its files.
SELECT toString(groupArray((source, host, session))) AS files
FROM (
    SELECT source, host, session,
        intDiv(sum(bytes) OVER (ORDER BY source, host, session ROWS UNBOUNDED PRECEDING) - bytes, {bytes:UInt64}) AS part
    FROM (
        SELECT toString(source) AS source, toString(host) AS host, session, sum(length(line)) AS bytes
        FROM llm.transcripts
        GROUP BY source, host, session
    )
)
GROUP BY part
ORDER BY part
SETTINGS max_threads = 1
FORMAT TSVRaw
