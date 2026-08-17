---
name: browser-support
description: Inspect and operate the self-hosted Hermes Chromium sidecar with task-aware target routing for diagnostics, sessions, frames, clipboard, click/touch/drag input, media inspection, challenge-state checks, checkpoints, recording, cleanup, and profile backups.
---

# Browser Support

Use `browser-support` when Hermes browser work needs low-level but bounded help
outside the high-level browser tools.

## Target safety

- Prefer the ordinary Hermes browser tools for navigation, semantic refs, and
  snapshots.
- For mutating `browser-support` commands, pass the exact `target_id` for the
  page that Hermes is already using, or pass `--task-id` so the helper resolves
  the active persisted target for that task.
- Obtain the target ID from a recent `browser_snapshot` frame tree, the tab
  listing exposed by the existing browser integration, or a deliberate
  `browser-support targets` inspection when you are doing diagnostics.
- Do not guess target IDs and do not assume the first page target belongs to
  the active task.

## Commands

```sh
browser-support targets
browser-support session-state [task-id]
browser-support session-events [task-id] [--limit N]
browser-support frame-tree <target-id>
browser-support clipboard-get <target-id>
browser-support clipboard-set <target-id> '<text>'
browser-support click --target-id <target-id> <x> <y>
browser-support touch-tap --target-id <target-id> <x> <y>
browser-support touch-swipe --target-id <target-id> <x1> <y1> <x2> <y2> [--steps N]
browser-support drag --target-id <target-id> <x1> <y1> <x2> <y2> [--steps N]
browser-support media-state <target-id>
browser-support challenge-state <target-id> [--previous checkpoint-or-json]
browser-support checkpoint-save <target-id> <name> [--note ...]
browser-support checkpoint-list
browser-support checkpoint-delete <name>
browser-support record-page <target-id> [path] [--seconds N] [--fps N]
browser-support profile-backup [name]
browser-support cleanup <browser-checkpoints|browser-profile-backups|browser-sessions|browser-task-artifacts|all> [--older-than-hours N]
browser-support diagnostics
```

## Guidance

- `challenge-state` is heuristic. Treat it as evidence, not proof. It can
  detect common CAPTCHA and verification markers and suggest next steps, but it
  cannot guarantee that a challenge is solved. With `--previous`, it compares
  the current page state to earlier evidence and reports only possible
  progress, never a false guarantee.
- `session-state` and `--task-id` are the safest way to line low-level helper
  calls up with the task-owned shared-profile page Hermes is already driving.
- `session-events` shows the persisted routing history for each task, including
  overlap warnings when concurrent commands made opener-less popup ownership
  ambiguous. Treat those warnings as a signal to refresh page state and avoid
  assuming Hermes already switched to a newly opened page.
- `click`, `touch-*`, and `drag` are atomic helpers for pages or widgets that
  need raw input events. Re-check the page state after each gesture.
- `media-state` reports bounded audio/video element state for pages that hide
  controls or swap sources dynamically.
- `record-page` captures a short bounded viewport recording to shared browser
  storage so retries or challenge recovery can be reviewed later.
- `checkpoint-save` is useful for shopping and checkout preparation. It stores
  a screenshot-backed JSON record, challenge summary, and media summary under
  shared browser files so the workflow can resume later without assuming that
  the live page state stayed unchanged.
- `profile-backup` archives the persistent Chromium profile. Use it before
  larger browser maintenance or when a site-specific session should be preserved
  explicitly.
- `diagnostics` reports CDP version, current targets, profile size, policy
  files, unpacked extensions, persisted task sessions, and browser-files usage.
