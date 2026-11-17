-- The raw source behind each proxy message of a session, which holds
-- images, signatures, encrypted reasoning, and anything else the blocks
-- leave out: the request item an input was read from, or the response body
-- of the call that produced an output. Transcript messages have only their
-- blocks once llm.transcripts is dropped.
WITH messages AS (SELECT * FROM llm.messages FINAL WHERE session_id = {session:String} AND path = '')
SELECT m.seq AS seq, m.role AS role, multiIf(m.item != 0, i.item, m.output, r.response_body, '') AS raw
FROM messages AS m
LEFT JOIN (SELECT hash, any(item) AS item FROM llm.request_items
    WHERE hash IN (SELECT item FROM messages) GROUP BY hash) AS i ON i.hash = m.item
LEFT JOIN (SELECT request_id, response_body FROM llm.requests
    WHERE request_id IN (SELECT call_id FROM messages WHERE output)) AS r ON r.request_id = m.call_id
ORDER BY seq
