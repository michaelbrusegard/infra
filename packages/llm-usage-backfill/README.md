# Historical usage backfill

Extract recorded usage from the Claude, Codex, Pi, and OpenCode transcripts
already stored in `llm.transcripts`. The default is a read-only dry run:

```sh
nix develop --command python3 packages/llm-usage-backfill/backfill.py
```

After deploying the ClickHouse schema, import the records with:

```sh
nix develop --command python3 packages/llm-usage-backfill/backfill.py --apply
```

`--projection /tmp/llm-usage-projection.jsonl.gz` retains and reuses a compressed
usage-only projection. `--output /tmp/llm-usage.jsonl` retains normalized rows.
Neither export contains message content. Refresh the projection when importing
additional transcripts.

Historical records stop at the earliest captured live call. This prevents
overlap with `llm.usage`; direct calls after that boundary are excluded too.
Claude stream chunks, repeated Codex cumulative points, copied Pi entries, and
shared provider response IDs are deduplicated. Codex uses per-response counts,
or the last-call counters in older logs, rather than summing running totals.
OpenCode session and part summaries are excluded because message totals already
contain their usage. Missing usage and model names are not guessed.

`llm.historical_usage` uses stable event IDs and a ReplacingMergeTree. Grafana
reads it with `FINAL`, so repeating an import cannot increase logical totals.
The declarative metrics view applies current published API rates, including
recorded Claude cache-write TTLs. Unsupported models and unknown write TTLs
remain unpriced. Historical failures and latency are unknown; those panels use
live data only.
