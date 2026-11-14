-- Input for `normalize-conversations -requests`: requests started since
-- {after} that are not in llm.calls yet, in start order, each with the items
-- its parts reference and the session CLIProxy recorded in llm.usage.
--
-- The plugin writes a request before CLIProxy writes its usage, so a request
-- without usage attempts may only be early; the normalizer holds recent ones
-- back rather than place them in a session the usage would have changed.
--
-- The plugin writes a request when it completes, so a long request arrives
-- after later ones. Selecting what is missing, rather than what started
-- after a watermark, picks it up whenever it lands; {after} only bounds the
-- scan and must reach back past the longest request and any outage.
--
-- llm.usage has a row per upstream attempt, and a websocket trace carries
-- many requests one after another. An attempt belongs to exactly one
-- request of its trace: the latest to start whose span holds it, or else,
-- for the clocks, the first to start within 50 ms after it. Every request
-- of the trace competes, normalized or not.
WITH
    selected AS (
        SELECT * FROM llm.requests
        WHERE started_at >= {after:DateTime64(3)}
            AND request_id NOT IN (
                SELECT request_id FROM llm.calls
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
    attempts AS (
        SELECT
            u.request_id AS attempt,
            argMin((r.request_id, u.session_id, u.parent_session_id), (r.started_at > u.requested_at,
                abs(dateDiff('millisecond', r.started_at, u.requested_at)), r.request_id)) AS owner
        FROM (
            SELECT request_id, trace_id, requested_at, session_id, parent_session_id FROM llm.usage
            WHERE trace_id IN (SELECT trace_id FROM selected)
        ) AS u
        INNER JOIN (
            SELECT request_id, trace_id, started_at, completed_at FROM llm.requests
            WHERE trace_id IN (SELECT trace_id FROM selected)
        ) AS r ON r.trace_id = u.trace_id
        WHERE u.requested_at BETWEEN r.started_at - INTERVAL 50 MILLISECOND AND r.completed_at
        GROUP BY attempt
    ),
    sessions AS (
        SELECT owner.1 AS request_id, any(owner.2) AS usage_session, any(owner.3) AS usage_parent,
            count() AS usage_attempts
        FROM attempts
        GROUP BY request_id
    )
SELECT
    r.request_id AS request_id, r.trace_id AS trace_id, r.session_id AS session_id,
    r.started_at AS started_at, r.completed_at AS completed_at, r.source_format AS source_format,
    r.model AS model, r.requested_model AS requested_model, r.stream AS stream, r.outcome AS outcome,
    r.status_code AS status_code, r.error AS error, r.user_agent AS user_agent, r.truncated AS truncated,
    r.request_envelope AS request_envelope, r.request_parts AS request_parts, i.items AS items,
    r.response_body AS response_body,
    s.usage_session AS usage_session_id, s.usage_parent AS usage_parent_session_id,
    s.usage_attempts AS usage_attempts
FROM selected AS r
LEFT JOIN items AS i ON i.request_id = r.request_id
LEFT JOIN sessions AS s ON s.request_id = r.request_id
ORDER BY started_at, request_id
FORMAT JSONEachRow
