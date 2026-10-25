---
name: review-pr
description: Review a pull request against repository instructions, intended behavior, and code-quality risks. Use when the user asks to review, inspect, assess, or comment on a PR.
---

# Review PR

Review the exact head SHA. The default result is a read-only findings report.
Posting comments or a GitHub review requires an explicit request.

## Process

### 1. Fetch the PR

Resolve the title, state, author, base, head branch, base SHA, head SHA, URL,
description, linked issues, commits, checks, and full diff. Read enough
surrounding code to understand the changed paths rather than reviewing isolated
hunks.

### 2. Run applicable repository checks

Read every applicable `AGENTS.md` and other repository instruction file. Walk
their concrete principles in order and test each against the diff. Run relevant
unused-code or repository review commands only when the local branch matches the
PR head. If the branch differs or the command fails, state that the check did
not run.

### 3. Review behavior

Inspect correctness, edge cases, data loss, races, retries, idempotency,
authorization, secrets, injection, trust boundaries, migrations, compatibility,
rollout, rollback, hot-path cost, and tests that prove behavior. Reproduce or
trace every suspected issue. Prefer no finding over a speculative complaint.

Rank actionable candidates by severity. Each candidate needs a changed
`file:line`, concrete failure mode, evidence, and smallest useful remediation.
Exclude style comments unless an explicit rule is violated or readability hides
a defect.

### 4. Present candidates

Show a numbered list with file, line, short title, and one-line explanation. If
the user requested a posted review, find or create a pending review and walk the
candidates one by one:

- **Add.** Attach the comment to the pending review immediately.
- **Skip.** Drop it.
- **Show details.** Show the exact proposed comment, then ask again.

Leave the review pending. Do not submit, approve, or request changes unless the
user explicitly asks for that disposition. Apply the global provenance rule to
every posted comment.

### 5. Recheck the head

Resolve the PR head again before finalizing and mark findings stale if it moved.
When no actionable findings remain, say so and name residual risks or checks
that could not be performed.
