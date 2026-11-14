-- Input for `normalize-conversations -proxied`: the proxy's calls, each
-- with its session's parent session and client, its response ID, and its
-- start, for handing transcript sessions over to the proxy and telling the
-- replies it returned.
SELECT c.session_id, s.parent_session_id, c.client, c.response_id, c.started_at
FROM llm.calls AS c FINAL
INNER JOIN (SELECT session_id, parent_session_id FROM llm.sessions FINAL WHERE origin = 'proxy') AS s
    ON s.session_id = c.session_id
WHERE c.origin = 'proxy'
FORMAT TSV
