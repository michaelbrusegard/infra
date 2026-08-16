---
name: browser-navigation
description: Operate interactive websites reliably with Hermes browser snapshots, vision, coordinate clicks, dialogs, and recovery from verification or challenge pages. Use for multi-step browsing, sign-in, forms, carts, checkout preparation, and visual-only interfaces.
---

# Browser Navigation

Use the browser tools for interactive pages. Prefer `web_search` or
`web_extract` when no interaction is required.

## Browser task routing

When operating as the user-facing parent and `delegate_task` is available,
delegate interactive browser workflows before making the first browser call.
Pass the child the complete objective, target URLs, relevant conversation
context, constraints, required output, and authorization boundaries. Ask the
child to perform the browser workflow through completion and return verified
findings for the parent to present to the user.

Do not delegate ordinary `web_search` or `web_extract` requests, transcript
extraction, or work that does not require interactive browser tools. When
delegation is unavailable, including inside a leaf child agent, operate the
browser directly using the guidance below. Avoid splitting one browser workflow
between parent and child because their tab groups are isolated. Browser tasks
share the persistent login profile, but each task owns its own root tab and any
tabs or popups opened from it.

## Reliable interaction loop

1. Start with `browser_navigate`. It returns a compact accessibility snapshot.
2. Prefer `browser_click` and `browser_type` with current `@eN` refs.
3. After navigation, a modal, or any substantial DOM change, take a fresh
   `browser_snapshot`; do not reuse stale refs.
4. Verify every consequential action from the resulting page state before
   continuing. Do not infer success from a tool call alone.
5. Use `browser_dialog` for native prompts and `browser_console` when page
   behavior is unclear.
6. A clicked link may make a new tab active. Refresh the snapshot after the
   click and continue there; the popup remains part of the same task.

Dismiss cookie banners, location prompts, sign-in overlays, and obstructing
modals before retrying a covered target. Prefer semantic refs over selectors or
coordinates whenever a usable ref exists.

## Visual-only interfaces

When the target is a canvas, image, map, unlabeled icon, verification widget,
or otherwise absent from the accessibility snapshot:

1. Call `browser_vision` with `annotate=true`. Ask for the screenshot dimensions
   and the center-point coordinates of the exact target.
2. Check that the coordinates lie within the reported viewport and identify
   what visible state should change after the click.
3. Call `browser_click_at` once with those coordinates.
4. Immediately call `browser_vision` or `browser_snapshot` again to verify the
   result. Recalculate coordinates from the new screenshot; never assume that
   tiles, dialogs, or controls stayed in the same place.

Coordinate clicks are viewport CSS pixels with origin `[0, 0]` at the top-left.
They are a last resort because layout movement can invalidate them.

## Files

- To upload a user attachment or generated file, call `browser_upload` with a
  current file-input ref and absolute paths under the Hermes workspace or
  attachment cache. Do not type a path into a file input.
- To save a link or button download, call `browser_download` with its current
  ref and the expected filename including extension. Use the returned path for
  inspection or attach it to the reply with `MEDIA:<path>`.
- Refresh the snapshot after an upload or download action and verify the page
  acknowledges the expected file.

## Verification and challenge recovery

Treat “checking your browser,” CAPTCHA, unusual-traffic, bot-check, and similar
pages as stateful flows rather than ordinary forms.

- Always attempt to clear a challenge to the best of your ability. Bot
  detection or repeated verification is not by itself a reason to stop.
- First inspect with `browser_snapshot` and `browser_vision`; determine whether
  the page is waiting automatically, offers a semantic checkbox/button, or is
  visual-only.
- For an automatic interstitial, wait 5–10 seconds, then inspect again before
  choosing the next interaction.
- Use a snapshot ref for an accessible checkbox or button.
- For a visual-only challenge, use the visual interaction workflow above and
  re-analyze after every click because challenge imagery can update in place.
- If a challenge reloads or makes no progress, vary the tactic. Reload, use a
  new tab, recover the session, or reset relevant site state when that offers a
  better path forward.
- Login state is shared across browser tasks and persists across pod restarts.
  Account, cookie, and site-data changes therefore affect every browser task
  using that site.
- After any unsuccessful interaction, capture the new state and select the
  most promising next action from the current evidence.
- After the challenge clears, take a fresh snapshot before continuing the
  original task.

## Long workflows

Keep one tab and the persistent login session when possible. Before submitting
an order, purchase, message, or other externally visible action, confirm that
the requested state and values match the user's instructions. A request to
prepare a cart does not itself authorize final checkout.
