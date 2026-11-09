-- Project usage and model metadata on the server. Never export message content,
-- instructions, tool arguments, credentials, or response headers.
SELECT
    source, host, session, path, id, ts,
    JSONExtractString(line, 'type') AS kind,
    JSONExtractString(line, 'payload', 'type') AS payload_type,
    multiIf(
        source IN ('claude-code', 'pi'), JSONExtractString(line, 'message', 'model'),
        source = 'codex', JSONExtractString(line, 'payload', 'model'),
        source = 'opencode', if(JSONExtractString(line, 'data', 'modelID') != '',
            JSONExtractString(line, 'data', 'modelID'), JSONExtractString(line, 'data', 'model', 'id')),
        '') AS model,
    JSONExtractString(line, 'modelId') AS changed_model,
    multiIf(
        source = 'pi', if(JSONExtractString(line, 'message', 'provider') != '',
            JSONExtractString(line, 'message', 'provider'), JSONExtractString(line, 'provider')),
        source = 'codex', JSONExtractString(line, 'payload', 'model_provider'),
        source = 'opencode', if(JSONExtractString(line, 'data', 'providerID') != '',
            JSONExtractString(line, 'data', 'providerID'), JSONExtractString(line, 'data', 'model', 'providerID')),
        '') AS provider,
    multiIf(
        source = 'claude-code', JSONExtractString(line, 'message', 'id'),
        source = 'pi', JSONExtractString(line, 'message', 'responseId'),
        source = 'codex', JSONExtractString(line, 'payload', 'response_id'),
        '') AS response_id,
    JSONExtractString(line, 'id') AS entry_id,
    if(kind = 'session_meta', JSONExtractString(line, 'payload', 'id'),
        JSONExtractString(line, 'payload', 'thread_id')) AS native_session,
    JSONExtractString(line, 'payload', 'turn_id') AS turn_id,
    multiIf(
        source = 'codex' AND kind = 'token_usage_record', JSONExtractRaw(line, 'payload', 'usage'),
        source = 'codex', JSONExtractRaw(line, 'payload', 'info', 'last_token_usage'),
        source = 'opencode', JSONExtractRaw(line, 'data', 'tokens'),
        source = 'pi' AND kind = 'compaction', JSONExtractRaw(line, 'usage'),
        JSONExtractRaw(line, 'message', 'usage')) AS usage,
    if(kind = 'token_usage_record', JSONExtractRaw(line, 'payload', 'thread_token_usage'),
        JSONExtractRaw(line, 'payload', 'info', 'total_token_usage')) AS cumulative
FROM llm.transcripts FINAL
WHERE ts < parseDateTime64BestEffort({before:String}, 3, 'UTC')
    AND (
        (source = 'claude-code' AND kind = 'assistant' AND JSONHas(line, 'message', 'usage'))
        OR (source = 'pi' AND (kind IN ('session', 'model_change')
            OR JSONHas(line, 'message', 'usage') OR (kind = 'compaction' AND JSONHas(line, 'usage'))))
        OR (source = 'codex' AND (kind IN ('session_meta', 'turn_context', 'token_usage_record')
            OR (kind = 'event_msg' AND payload_type = 'token_count')))
        OR (source = 'opencode' AND JSONExtractString(line, 'kind') = 'message'
            AND (kind = 'assistant' OR JSONExtractString(line, 'data', 'role') = 'assistant')
            AND JSONHas(line, 'data', 'tokens'))
    )
ORDER BY source, host, session, path, toUInt64OrZero(id), ts, id
SETTINGS max_threads = 1, max_memory_usage = 1073741824,
    max_block_size = 256, preferred_block_size_bytes = 1048576,
    max_bytes_before_external_sort = 134217728
FORMAT JSONEachRow
