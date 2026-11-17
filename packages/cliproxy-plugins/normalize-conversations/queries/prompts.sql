-- What I asked in the last week. Injected context (<system-reminder>,
-- <environment_context>, AGENTS.md) is also user-role text; skipping text
-- that starts with a tag is a heuristic. Retries, compactions, and the
-- proxy's first call in a session a transcript also holds send a prompt
-- again, so each counts once per session, when it was first seen.
SELECT min(ts) AS first_seen, session_id, b.text AS prompt
FROM llm.messages FINAL
ARRAY JOIN blocks AS b
WHERE role = 'user' AND b.type = 'text' AND NOT startsWith(b.text, '<')
GROUP BY session_id, prompt
HAVING first_seen >= now() - INTERVAL 7 DAY
ORDER BY first_seen DESC
LIMIT 100
