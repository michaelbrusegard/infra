-- The windows of {hours} hours, oldest first, whose requests are not all
-- in llm.calls yet: what a run of the job, or the backfill, normalizes a
-- window at a time. A request lands when it completes and is selected by
-- what is missing, so a run picks up every request, however late it
-- landed and however long the job was stopped. Request IDs are compared
-- by hash, which bounds the set to 8 bytes a call.
SELECT DISTINCT toDateTime(toStartOfInterval(started_at, INTERVAL {hours:UInt32} HOUR)) AS window
FROM llm.requests
WHERE cityHash64(request_id) NOT IN (SELECT cityHash64(request_id) FROM llm.calls WHERE origin = 'proxy')
ORDER BY window
FORMAT TSV
