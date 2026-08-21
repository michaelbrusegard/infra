---
name: self-review
description: Review the current branch and working tree against repository instructions, then let the user choose improvements to apply. Use when the user asks to self-review, check the diff, or find problems in the agent's own work.
---

# Self review

Treat the current implementation as untrusted.

## Process

### 1. Gather every part of the diff

Read repository instructions and run `git status`. Resolve the intended parent,
then inspect committed branch changes, unstaged changes, and staged changes.
Separate work introduced by this task from pre-existing user changes.

### 2. Walk the principles

Read every applicable `AGENTS.md` and other durable repository instruction.
Walk each concrete principle in order and test it against the diff. Then trace
changed behavior through callers, boundaries, failure paths, persistence, and
tests. Use `blast-radius` when the safety of a shared contract depends on hidden
consumers.

Look for correctness bugs, regressions, missing edge cases, unsafe fallbacks,
authorization errors, data loss, races, compatibility breaks, unproven claims,
needless generated abstraction, narrating comments, debug residue, accidental
files, and unrelated cleanup.

Run focused tests and static checks. A candidate must have evidence and a
specific improvement, not exist merely to make the review look productive.

### 3. Present candidates

Show all candidates as a numbered list with a short title, affected path, and
one-line explanation. Then walk them one by one:

- **Apply.** Make the edit, run the relevant verification, summarize it, and
  commit the coherent improvement before moving on.
- **Skip.** Drop the candidate.
- **Show details.** Explain the proposed change, then ask again.

Do not batch independent improvements into one opaque edit. Preserve user-owned
changes and leave the branch untouched when there are no confirmed issues.

## Output

Report applied improvements and commits, verification results, skipped
candidates with the user's reason when useful, and residual risk.
