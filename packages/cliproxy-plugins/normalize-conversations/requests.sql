-- Input for `normalize-conversations -requests`: requests started in
-- [after, before), in start order, each with the items its parts reference
-- and, when the trace has one, the session CLIProxy recorded in llm.usage.
WITH
    selected AS (
        SELECT * FROM llm.requests
        WHERE started_at >= {after:DateTime64(3)} AND started_at < {before:DateTime64(3)}
    ),
    items AS (
        SELECT
            request_id,
            -- Items are unique only after merges; duplicates are identical.
            arrayMap(x -> x.2, arraySort(arrayDistinct(groupArray((n, i.item))))) AS items
        FROM (
            SELECT request_id, part.hash AS hash, n
            FROM selected
            ARRAY JOIN request_parts AS part, arrayEnumerate(request_parts) AS n
        ) AS p
        INNER JOIN llm.request_items AS i ON i.hash = p.hash
        GROUP BY request_id
    ),
    sessions AS (
        SELECT trace_id, any(session_id) AS usage_session, any(parent_session_id) AS usage_parent
        FROM llm.usage
        WHERE trace_id IN (SELECT trace_id FROM selected)
        GROUP BY trace_id
        HAVING uniqExact(session_id) = 1
    )
SELECT
    r.request_id AS request_id, r.trace_id AS trace_id, r.session_id AS session_id,
    r.started_at AS started_at, r.completed_at AS completed_at, r.source_format AS source_format,
    r.model AS model, r.requested_model AS requested_model, r.stream AS stream, r.outcome AS outcome,
    r.status_code AS status_code, r.error AS error, r.user_agent AS user_agent, r.truncated AS truncated,
    r.request_envelope AS request_envelope, r.request_parts AS request_parts, i.items AS items,
    r.response_body AS response_body,
    s.usage_session AS usage_session_id, s.usage_parent AS usage_parent_session_id
FROM selected AS r
LEFT JOIN items AS i ON i.request_id = r.request_id
LEFT JOIN sessions AS s ON s.trace_id = r.trace_id
ORDER BY started_at, request_id
FORMAT JSONEachRow
