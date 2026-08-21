---
name: show-work
description: Keep a reviewable TSV decision trail for long-running, autonomous, or multi-phase work. Use when the user asks to show the work, preserve an audit trail, or make a complex investigation reviewable after the fact.
---

# Show work

Keep one canonical decision log so a reviewer can reconstruct what was decided,
why, and on what evidence without reading the whole session. Record observable
evidence and concise decision summaries, not hidden chain of thought.

## Format

Copy `references/decision-log-template.tsv` to start a log. It has one row per
decision and six columns:

- `ts`: ISO 8601 timestamp.
- `phase`: phase or workstream.
- `decision`: what was chosen or done, on one line.
- `why`: the reason in plain words.
- `evidence`: a commit, PR, `file:line`, artifact, trace, or screenshot path.
- `result`: the observed state, such as `tests green`, `reverted`,
  `INCONCLUSIVE`, or `open`.

Evidence is a pointer, not a paragraph. Write every cell through `unslop`.

## Log a row

Resolve `<skill-dir>` to this skill's directory and run:

```sh
bash <skill-dir>/scripts/log.sh LOGFILE PHASE DECISION WHY EVIDENCE RESULT
```

The helper writes the header on first use, adds the timestamp, strips embedded
tabs and newlines, and prevents spreadsheet formula execution. Log decisions,
checkpoints, pivots, reverts, blockers, and verification results. For a loop,
write one row per iteration. Skip routine commands and self-evident actions.

## Location

Use `decisions.tsv` in the work directory or `.audit/<task-slug>.tsv` for
multiple efforts. Keep it local by default. Commit it only when a reviewer needs
the trail to trust an ambitious migration, port, or long autonomous run.

## Rules

- Keep one decision or checkpoint per row.
- Append only. Supersede a wrong decision with a new row.
- Prefer evidence produced by committed, rerunnable scripts.
- Never log secrets, raw prompts, unrelated personal data, or speculative inner
  reasoning.
- Preserve required provenance in human-facing artifacts without putting a
  provenance line in every TSV row.

## Audit before handoff

Resolve only the current run's session or use the current conversation. Do not
search unrelated workspaces. Check that every row maps to a real action, every
evidence pointer resolves, and every material fork or abandoned path appears.
Remove invented claims and padding. If the work diverged from a row, the row is
wrong.

When the harness and task authorization permit independent review, ask a fresh
reviewer from a different model family to inspect the trail and session for weak
evidence, skipped verification, risky decisions, and important gaps. End the
handoff with an `Attention` section containing the reviewer's model and flags,
or `No flags`.
