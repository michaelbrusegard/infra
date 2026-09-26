---
name: self-review
description: Review the current branch and working tree against repository instructions and fix what is wrong. Use when the user asks to self-review, check the diff, or find problems in the agent's own work.
---

# Self review

Treat the current implementation as untrusted. Fix confirmed problems; do not
ask the user to pick.

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

Run focused tests and static checks. A finding must have evidence and a
specific improvement, not exist merely to make the review look productive.

### 3. Fix

Apply each confirmed finding as its own coherent edit, run the relevant
verification, and commit it. Do not batch independent fixes into one opaque
edit. Preserve user-owned changes and leave the branch untouched when there are
no confirmed issues.

Do not fix a finding that needs a product decision, changes scope, or would
rewrite published history. List it instead.

## Output

Report each fix with its commit and verification result, findings left for the
user with the reason, and residual risk.
