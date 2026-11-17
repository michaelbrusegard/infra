-- A session's conversation, root to its latest message. For the exact
-- context and reply of one call, start from its last output_ids instead.
WITH RECURSIVE path AS (
    SELECT id, parent_id, seq, role, output, model, blocks
    FROM llm.messages FINAL
    WHERE session_id = {session:String}
        AND id = (SELECT argMax(id, (ts, seq)) FROM llm.messages FINAL WHERE session_id = {session:String})
    UNION ALL
    SELECT m.id, m.parent_id, m.seq, m.role, m.output, m.model, m.blocks
    FROM llm.messages AS m FINAL
    INNER JOIN path AS p ON m.id = p.parent_id
    WHERE m.session_id = {session:String}
)
SELECT seq, role, output, model, blocks FROM path ORDER BY seq
FORMAT JSONEachRow
