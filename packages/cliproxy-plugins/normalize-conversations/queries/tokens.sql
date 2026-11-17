-- Calls and tokens per day, client, and model, as the responses reported
-- them. For costs, see cost.sql.
SELECT toDate(started_at) AS day, client, model, count() AS calls,
    sum(uncached_input_tokens + cache_read_tokens + cache_write_tokens) AS input_tokens,
    sum(output_tokens) AS output_tokens
FROM llm.calls FINAL
GROUP BY day, client, model
ORDER BY day, input_tokens DESC
