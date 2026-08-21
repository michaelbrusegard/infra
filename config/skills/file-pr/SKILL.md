---
name: file-pr
description: Write, improve, or open a focused pull request from the current branch. Use when the user asks to draft, file, open, submit, create, or improve a PR or pull request.
---

# File PR

Write for the reviewer. Give enough background to understand the change, then
stop. Use `unslop` on the title, description, and commit bodies.

## Before writing

1. Establish the primary reason for the PR from the conversation. Ask only when
   it is still unclear.
2. Read repository instructions, full diff, commit history, current branch,
   base, working tree, and real test evidence. Do not write from commit subjects
   alone or silently include unrelated work.
3. Resolve whether a PR already exists for the branch. Update it rather than
   creating a duplicate.
4. Check repository and remote rules before committing, pushing, or creating a
   public artifact. An explicit request to file or open the PR authorizes that
   PR, not unrelated external actions.
5. Shape the work into small, ordered commits and focused PRs. Independent work
   branches from the normal base. Dependent slices form a visible stack in the
   repository's stacking tool. Ask before reorganizing published history or
   making a substantial split.
6. Bring the branch up to date only when it is safe and does not require an
   unauthorized force-push. Otherwise state the stale-base risk.
7. Run required checks and inspect the final diff for generated complexity,
   narrating comments, debug residue, accidental files, and scope creep.

## Title

Follow the repository's established convention. When none exists, use a
Conventional Commit-style title with an imperative, specific subject. Keep it
under 72 characters when practical and mark breaking behavior clearly.

## Description

Lead with why the change matters, then state the net change and its boundary.
Explain only choices the diff cannot. Contrast old and new behavior when that
makes the scope clearer.

Use structure that helps this PR. Do not force `Summary`, `Test plan`, or a
fixed template onto a small change. Include only sections with content:

- actual behavioral or end-to-end verification, not a dump of routine lint and
  typecheck commands;
- screenshots or a short recording for visible UI changes;
- related issues or conversations when the relationship is verified;
- breaking behavior, required manual action, known risk, secret handling, or
  infrastructure apply details when relevant.

Never claim a test that was not run. If meaningful end-to-end verification was
not performed, say so plainly. Preserve the provenance required by the global
agent instructions.

## File and hand off

Show the title, base, and full description before creation when the user asked
for a draft or the destination is ambiguous. Otherwise create or update the PR
requested by the user.

Return the URL, title, base and head, draft state, verification evidence, and
known follow-up. Suggest reviewers only when code ownership or recent work gives
a real reason. Continue into `babysit-pr` only when the user asked for ongoing
monitoring.
