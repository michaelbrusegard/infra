---
name: browser-support
description: Inspect and operate the self-hosted Hermes Chromium sidecar with task-aware CDP target IDs for diagnostics, frames, clipboard, touch, drag, challenge-state checks, checkpoints, cleanup, and profile backups.
---

# Browser Support

Use `browser-support` when Hermes browser work needs low-level but bounded help
outside the high-level browser tools.

## Target safety

- Prefer the ordinary Hermes browser tools for navigation, semantic refs, and
  snapshots.
- For mutating `browser-support` commands, pass the exact `target_id` for the
  page that Hermes is already using.
- Obtain the target ID from a recent `browser_snapshot` frame tree, the tab
  listing exposed by the existing browser integration, or a deliberate
  `browser-support targets` inspection when you are doing diagnostics.
- Do not guess target IDs and do not assume the first page target belongs to
  the active task.

## Commands

```sh
browser-support targets
browser-support frame-tree <target-id>
browser-support clipboard-get <target-id>
browser-support clipboard-set <target-id> '<text>'
browser-support touch-tap <target-id> <x> <y>
browser-support touch-swipe <target-id> <x1> <y1> <x2> <y2> [--steps N]
browser-support drag <target-id> <x1> <y1> <x2> <y2> [--steps N]
browser-support challenge-state <target-id>
browser-support checkpoint-save <target-id> <name> [--note ...]
browser-support checkpoint-list
browser-support checkpoint-delete <name>
browser-support profile-backup [name]
browser-support cleanup <browser-checkpoints|browser-profile-backups|all> [--older-than-hours N]
browser-support diagnostics
```

## Guidance

- `challenge-state` is heuristic. Treat it as evidence, not proof. It can
  detect common CAPTCHA and verification markers and suggest next steps, but it
  cannot guarantee that a challenge is solved.
- `touch-*` and `drag` are atomic helpers for pages or widgets that need raw
  input events. Re-check the page state after each gesture.
- `checkpoint-save` is useful for shopping and checkout preparation. It stores
  a screenshot-backed JSON record under shared browser files so the workflow can
  resume later without assuming that the live page state stayed unchanged.
- `profile-backup` archives the persistent Chromium profile. Use it before
  larger browser maintenance or when a site-specific session should be preserved
  explicitly.
- `diagnostics` reports CDP version, current targets, profile size, policy
  files, unpacked extensions, and browser-files usage.
