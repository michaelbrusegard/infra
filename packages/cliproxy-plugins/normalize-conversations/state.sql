-- Input for `normalize-conversations -requests -state`: what earlier runs
-- wrote for the sessions a run touches, which
-- `normalize-conversations -requests -sessions` prints as {sessions}. Nodes
-- let full-resend requests extend their trees without writing them again,
-- and response leaves let delta requests continue a response from an
-- earlier run.
SELECT session_id, id, seq, version, '' AS response_id
FROM llm.messages FINAL
WHERE session_id IN {sessions:Array(String)}
UNION ALL
SELECT session_id, if(empty(output_ids), input_id, output_ids[-1]), 0, 0, response_id
FROM llm.calls FINAL
WHERE session_id IN {sessions:Array(String)} AND response_id != ''
FORMAT JSONEachRow
