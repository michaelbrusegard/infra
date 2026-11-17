-- One call as training data: the system prompt or instructions and the
-- tools it ran with, which are per-call context outside the message tree,
-- and the conversation it saw and produced. The context comes from a proxy
-- call's llm.requests row and the call's context. Context rows
-- have a field, a call row marks the call, and call_output marks the
-- call's own outputs, which the export checks.
WITH RECURSIVE
    path AS (
        SELECT id, parent_id, seq, role, output, model, blocks
        FROM llm.messages FINAL
        WHERE session_id = (SELECT session_id FROM llm.calls FINAL WHERE call_id = {call:String})
            AND id = (SELECT if(empty(output_ids), input_id, output_ids[-1])
                FROM llm.calls FINAL WHERE call_id = {call:String})
        UNION ALL
        SELECT m.id, m.parent_id, m.seq, m.role, m.output, m.model, m.blocks
        FROM llm.messages AS m FINAL
        INNER JOIN path AS p ON m.id = p.parent_id
        WHERE m.session_id = (SELECT session_id FROM llm.calls FINAL WHERE call_id = {call:String})
    ),
    request AS (
        SELECT request_envelope, request_parts, response_body FROM llm.requests
        WHERE request_id = (SELECT request_id FROM llm.calls FINAL WHERE call_id = {call:String})
    ),
    context AS (
        -- Split into items, or small enough to stay in the envelope.
        SELECT part.field AS field, part.position AS position, any(i.item) AS value
        FROM (SELECT request_parts AS parts FROM request
            UNION ALL SELECT context FROM llm.calls FINAL WHERE call_id = {call:String})
        ARRAY JOIN parts AS part
        INNER JOIN llm.request_items AS i ON i.hash = part.hash
        WHERE part.field IN ('system', 'instructions', 'tools')
        GROUP BY field, position
        UNION ALL
        SELECT field, -1, JSONExtractRaw(request_envelope, field)
        FROM request
        ARRAY JOIN ['system', 'instructions', 'tools'] AS field
        WHERE JSONHas(request_envelope, field)
        UNION ALL
        -- What a Responses API response echoed as in effect, which the
        -- export prefers: Codex sends no tools over websockets, and a delta
        -- request sends no instructions or tools at all.
        SELECT 'response', 0, response_body FROM request
    )
SELECT * FROM (
    -- Marks the rows as a call's, so the export checks it as a training
    -- example even when it has no context and no outputs.
    SELECT 'call' AS field, 0 AS position, '' AS value, 0 AS seq, 0 AS id, '' AS role, false AS output,
        '' AS model, [] AS blocks, false AS call_output
    UNION ALL
    SELECT field, position, value, 0, 0, '', false, '', [], false
    FROM context
    UNION ALL
    SELECT '', 0, '', seq, id, role, output, model, blocks,
        id IN (SELECT arrayJoin(output_ids) FROM llm.calls FINAL WHERE call_id = {call:String})
    FROM path)
ORDER BY field = '', field, position, seq
FORMAT JSONEachRow
