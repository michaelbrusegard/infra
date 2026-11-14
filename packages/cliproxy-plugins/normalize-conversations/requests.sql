-- Input for `normalize-conversations -requests`: requests started since
-- {after} that are not in llm.calls yet, in start order, each with the items
-- its parts reference and the session CLIProxy recorded in llm.usage.
--
-- The plugin writes a request when it completes, so a long request arrives
-- after later ones. Selecting what is missing, rather than what started
-- after a watermark, picks it up whenever it lands; {after} only bounds the
-- scan and must reach back past the longest request and any outage.
--
-- llm.usage has a row per upstream attempt, and a websocket trace carries
-- many requests one after another. An attempt belongs to the request in its
-- trace whose span holds it, with 50 ms of slack for the clocks.
WITH
    selected AS (
        SELECT * FROM llm.requests
        WHERE started_at >= {after:DateTime64(3)}
            AND request_id NOT IN (
                SELECT call_id FROM llm.calls
                WHERE origin = 'proxy' AND started_at >= {after:DateTime64(3)})
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
        SELECT r.request_id AS request_id, any(u.session_id) AS usage_session, any(u.parent_session_id) AS usage_parent
        FROM selected AS r
        INNER JOIN (
            SELECT trace_id, requested_at, session_id, parent_session_id FROM llm.usage
            WHERE trace_id IN (SELECT trace_id FROM selected)
        ) AS u ON u.trace_id = r.trace_id
        WHERE u.requested_at BETWEEN r.started_at - INTERVAL 50 MILLISECOND AND r.completed_at
        GROUP BY r.request_id
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
LEFT JOIN sessions AS s ON s.request_id = r.request_id
ORDER BY started_at, request_id
FORMAT JSONEachRow
