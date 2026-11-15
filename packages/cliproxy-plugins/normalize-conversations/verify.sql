-- The checks of the backfill, from Verification in docs/llm-conversations.md,
-- which `normalize.sh verify` runs. A check row counts violations, which
-- must be 0; a report row is a figure to compare and explain. Requests of
-- the last hour may still be held back for their usage.
SELECT 'check', 'requests without a proxy call', count()
FROM (SELECT request_id FROM llm.requests WHERE completed_at < now() - INTERVAL 1 HOUR
    EXCEPT SELECT request_id FROM llm.calls FINAL WHERE origin = 'proxy');

SELECT 'check', 'proxy calls without a request', count()
FROM (SELECT request_id FROM llm.calls FINAL WHERE origin = 'proxy' EXCEPT SELECT request_id FROM llm.requests);

SELECT 'check', 'requests with more than one proxy call', count()
FROM (SELECT request_id FROM llm.calls FINAL WHERE origin = 'proxy' GROUP BY request_id HAVING count() > 1);

SELECT 'check', 'response IDs of more than one call', count()
FROM (SELECT response_id FROM llm.calls FINAL WHERE response_id != '' GROUP BY response_id HAVING count() > 1);

SELECT 'check', 'transcript calls the proxy returned', count()
FROM llm.calls FINAL
WHERE origin = 'transcript' AND response_id != ''
    AND response_id IN (SELECT response_id FROM llm.calls FINAL WHERE origin = 'proxy');

SELECT 'check', 'context items missing', count()
FROM (SELECT DISTINCT arrayJoin(context).hash AS hash FROM llm.calls FINAL)
WHERE hash NOT IN (SELECT hash FROM llm.request_items);

SELECT 'check', 'proxy messages whose item is missing', count()
FROM (SELECT DISTINCT item FROM llm.messages FINAL WHERE item != 0)
WHERE item NOT IN (SELECT hash FROM llm.request_items);

SELECT 'check', 'messages whose parent is not in their session', count()
FROM llm.messages FINAL
WHERE parent_id != 0 AND (session_id, parent_id) NOT IN (SELECT session_id, id FROM llm.messages FINAL)
SETTINGS max_threads = 1;

SELECT 'check', 'call outputs that are no output message of their session', count()
FROM (SELECT session_id, arrayJoin(output_ids) AS id FROM llm.calls FINAL)
WHERE (session_id, id) NOT IN (SELECT session_id, id FROM llm.messages FINAL WHERE output)
SETTINGS max_threads = 1;

SELECT 'check', 'messages that are the output of two calls', count()
FROM (SELECT id FROM (SELECT arrayJoin(output_ids) AS id, call_id FROM llm.calls FINAL)
    GROUP BY id HAVING uniqExact(call_id) > 1);

-- A block the extractor does not know keeps only its type. The transcript
-- import fails on one; the proxy's raw request still holds it, so the
-- extractor learns the type and the proxy windows are normalized again.
SELECT 'check', 'blocks of unknown types', count()
FROM llm.messages FINAL ARRAY JOIN blocks AS b
WHERE b.type = 'other' AND b.source_type != 'missing_context';

SELECT 'report', concat('calls ', origin, ' ', client), count()
FROM llm.calls FINAL
GROUP BY origin, client
ORDER BY origin, client;

-- Transcript calls against the old import, per client: they differ where
-- the importer counted differently, such as Codex's drifted repeats. Once
-- the old import is dropped, it has no rows.
SELECT 'report', concat('history ', source, ' ', what), value
FROM (
    SELECT source, 'calls' AS what, count() AS value FROM llm.call_history
    WHERE requested_at < (SELECT min(requested_at) FROM llm.usage) GROUP BY source
    UNION ALL
    SELECT source, 'tokens', sum(uncached_input_tokens + cache_read_tokens + cache_creation_tokens + output_tokens)
    FROM llm.call_history WHERE requested_at < (SELECT min(requested_at) FROM llm.usage) GROUP BY source
    UNION ALL
    SELECT toString(source), 'old import calls', count() FROM llm.old_import_usage FINAL GROUP BY source
    UNION ALL
    SELECT toString(source), 'old import tokens',
        sum(uncached_input_tokens + cache_read_tokens + cache_creation_tokens + output_tokens)
    FROM llm.old_import_usage FINAL GROUP BY source
)
ORDER BY source, what;
