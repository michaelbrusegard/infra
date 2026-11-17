-- Estimated cost per session and model of proxy calls, as the dashboard
-- prices them. Usage links to a call's llm.requests row by trace_id. A
-- websocket trace carries many calls, so joining on trace_id alone would
-- count each upstream attempt once per call. Each attempt belongs to one
-- call of its trace instead: the latest to start whose span holds it, or
-- else the first to start within 50 ms after it. The view has no attempt
-- ID, but the owner depends only on the trace and time. Unpriced attempts
-- are NULL and left out of the sum.
WITH
    calls AS (
        SELECT c.call_id AS call_id, c.session_id AS session_id, c.model AS model,
            r.trace_id AS trace_id, r.started_at AS started_at, r.completed_at AS completed_at
        FROM (SELECT call_id, session_id, model, request_id FROM llm.calls FINAL WHERE origin = 'proxy') AS c
        INNER JOIN (SELECT request_id, trace_id, started_at, completed_at FROM llm.requests) AS r
            ON r.request_id = c.request_id),
    owners AS (
        SELECT u.trace_id AS trace_id, u.requested_at AS requested_at,
            argMin(c.call_id, (c.started_at > u.requested_at,
                abs(dateDiff('millisecond', c.started_at, u.requested_at)), c.call_id)) AS call_id
        FROM (SELECT DISTINCT trace_id, requested_at FROM llm.usage_metrics WHERE origin = 'live') AS u
        INNER JOIN calls AS c ON c.trace_id = u.trace_id
        WHERE u.requested_at BETWEEN c.started_at - INTERVAL 50 MILLISECOND AND c.completed_at
        GROUP BY trace_id, requested_at)
SELECT c.session_id AS session, c.model AS model, count() AS attempts,
    sum(u.estimated_cost_usd) AS cost_usd
FROM llm.usage_metrics AS u
INNER JOIN owners AS o ON o.trace_id = u.trace_id AND o.requested_at = u.requested_at
INNER JOIN calls AS c ON c.call_id = o.call_id
GROUP BY session, model
ORDER BY cost_usd DESC
LIMIT 50
