-- Sub-agent sessions under their parents, with their size.
-- A session has a row per source, so they are deduplicated first.
SELECT s.parent_session_id AS parent, s.session_id AS agent, count() AS messages
FROM (SELECT DISTINCT session_id, parent_session_id FROM llm.sessions FINAL
    WHERE parent_session_id != '') AS s
INNER JOIN llm.messages AS m FINAL ON m.session_id = s.session_id
GROUP BY parent, agent
ORDER BY parent, agent
