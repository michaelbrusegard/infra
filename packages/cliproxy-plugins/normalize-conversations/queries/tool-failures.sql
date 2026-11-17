-- Tool use and failures per model and tool. Anthropic, Pi, and OpenCode
-- results carry an error flag; Codex reports exit codes in the output text.
-- A tool call ID is one invocation, so copies of the call or its result in
-- other files or later requests count once.
WITH
    tool_calls AS (
        SELECT b.tool_call_id AS id, any(b.tool_name) AS tool, any(model) AS model
        FROM llm.messages FINAL ARRAY JOIN blocks AS b
        WHERE output AND b.type = 'tool_call' AND b.tool_call_id != ''
        GROUP BY id),
    results AS (
        SELECT b.tool_call_id AS id, max(b.is_error) AS failed
        FROM llm.messages FINAL ARRAY JOIN blocks AS b
        WHERE b.type = 'tool_result' AND b.tool_call_id != ''
        GROUP BY id)
SELECT model, tool, count() AS uses, countIf(failed) AS failures
FROM tool_calls INNER JOIN results USING (id)
GROUP BY model, tool
ORDER BY failures DESC, uses DESC
LIMIT 50
