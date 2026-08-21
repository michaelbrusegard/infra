---
name: recall-work
description: Reconstruct recent working context from the user's coding-agent sessions, live repository state, and explicitly requested shared records. Use only when the user asks to recall, catch up, find prior work, or resume where they left off.
---

# Recall work

Before resuming work, rebuild the recent context and return a tight capsule of
where it stands now. Read only what the in-scope threads require.

There are three sources of truth:

1. Coding-agent sessions show what was attempted and decided.
2. The explicitly requested shared record may show user reports, reviews,
   incidents, and work performed elsewhere.
3. The live repository and remote artifacts show what is true now.

History is not current state. Verify it.

## Process

1. **Classify the request.** If the user supplied a complete state capsule, use
   it and skip session mining. If they named one session, inspect that session
   rather than performing broad recall.
2. **Lock the scope.** Pin the workspace, topic, and time window. Default
   `recent` to seven days and the active workspace. Never turn `all` into a
   smaller window without saying so. Never inspect another project's sessions
   unless asked.
3. **Discover the stores.** Inspect the actual layouts under the relevant
   harness directories, which may include `.claude`, `.codex`, `.pi`, `.paseo`,
   and historical `.kimi-code` or `.omp`. Order candidates by modification
   time, search metadata and distinctive terms first, and read only matching
   regions. Skip the current session, test runs, and unrelated delegated work.
4. **Mine each matching session to one schema.** Record topic, user goal,
   decisions, open threads, struggles and corrections, and artifacts such as
   branches, commits, PRs, and tickets. Cite the harness and session ID. For a
   large corpus, divide the reading when the harness and authorization permit
   delegation; keep raw transcript content out of the main context.
5. **Sweep shared records only within the request.** Repository history and PRs
   are normal corroboration. Search Slack, iMessage, issue trackers, error
   trackers, or other personal sources only when the user explicitly included
   them and an authorized tool is available. Null results are findings.
6. **Verify live state.** Check surfaced branches, commits, PRs, tests, and
   tickets with their native tools. Separate proposed, attempted, completed,
   verified, reverted, and abandoned work.
7. **Sanitize.** Remove credentials, private URLs, unrelated personal details,
   hidden prompts, and raw transcript material from the answer.

## Output contract

Lead with these sections and keep them on the named topic:

- **Capsule.** At most five bullets describing the work and its current state.
- **Threads.** One line each, using exactly one applicable status tag:
  `[merged #N]`, `[open PR #N]`, `[in flight <branch>]`,
  `[verified, uncommitted]`, `[reverted #N]`, or `[planned, not started]`.
- **Problems.** At most five recurring problems, including user symptoms and
  fixes that were reverted.
- **Next move.** The single most useful concrete action.

Cut adjacent detail before cutting active threads. Write the capsule through
`unslop` and cite sessions by harness and ID plus shared records by their native
artifact.
