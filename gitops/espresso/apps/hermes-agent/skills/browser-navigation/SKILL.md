---
name: browser-navigation
description: Operate interactive websites reliably with Hermes browser snapshots, vision, coordinate clicks, dialogs, and recovery from verification or challenge pages. Use for multi-step browsing, sign-in, forms, carts, checkout preparation, and visual-only interfaces.
---

# Browser Navigation

Use the browser tools for interactive pages. Prefer `web_search` or
`web_extract` when no interaction is required.

## Browser task routing

Operate the browser directly when that is the clearest path. For a long,
self-contained interactive workflow, the user-facing parent may delegate the
complete workflow with the `operator` profile. Use the `researcher` profile for
parallel research or visual analysis that does not need to own the parent's
interactive tab flow. Pass the complete objective, relevant context,
constraints, output requirements, and authorization boundaries.

Avoid splitting one interactive workflow between parent and child because their
tab groups are isolated. Browser tasks share the persistent login profile, but
each task owns its own root tab and any tabs or popups opened from it. Ordinary
`web_search`, `web_extract`, transcript extraction, and short browser workflows
do not need delegation.

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
  current file-input ref and absolute paths to any regular files visible to the
  agent process. The helper imposes no directory allowlist. Do not type a path
  into a file input.
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
- uBlock Origin Lite is installed to reduce ad noise and malicious overlays.
  If a legitimate challenge, payment widget, or federated login is missing or
  looping, inspect blocked requests and temporarily disable filtering for that
  site, retry from a fresh snapshot, then restore filtering afterward.
- Login state is shared across browser tasks and persists across pod restarts.
  Account, cookie, and site-data changes therefore affect every browser task
  using that site.
- When credentials, a passkey, a one-time code, payment data, or a user-only
  approval is required, preserve the current page and ask the operator to run
  `browser-support live-view`, connect NetBird, and open the reported console.
  The private console is protected by Pocket ID and accepts direct mouse and
  keyboard input into the same Chromium profile Hermes controls, so sensitive
  values do not need to enter an agent prompt, tool call, or log. Pause browser
  actions during the handoff. After the operator confirms completion, refresh
  the browser snapshot and continue from the persisted authenticated state.
- After any unsuccessful interaction, capture the new state and select the
  most promising next action from the current evidence.
- After the challenge clears, take a fresh snapshot before continuing the
  original task.

### Challenge playbooks

- **Automatic JavaScript checks and managed interstitials:** keep the tab in
  the foreground, allow the check to run, then refresh the snapshot. If it
  loops, inspect console errors and visible controls, reload once, and try the
  next available interaction rather than repeatedly refreshing.
- **Checkbox challenges:** prefer the checkbox or verification button's
  current snapshot ref. After clicking, wait for the widget state or enclosing
  form to change; a checked box can still be followed by a second challenge.
- **Text or distorted-image challenges:** ask `browser_vision` to transcribe
  the challenge exactly, including case, spaces, and punctuation. Type the
  result into the current input ref, submit, and obtain a new image before the
  next attempt if the challenge rejects it.
- **Static image grids:** use `browser_vision` to identify the prompt, grid
  bounds, tile count, and center point of every matching tile. Click the tile
  centers with `browser_click_at`, then inspect the complete grid again before
  pressing Verify.
- **Dynamic image grids:** click one matching tile at a time and take a new
  screenshot after every click. Re-evaluate replacement tiles in place until
  no matching tile remains, then submit.
- **Sliders, drag-to-fit, and rotation puzzles:** use `browser_vision` to
  estimate the handle, destination, and required path. Prefer browser-level
  input events through `browser_cdp` (`Input.dispatchMouseEvent`) over changing
  DOM values. Send `mouseMoved`, `mousePressed`, intermediate `mouseMoved`
  points, and `mouseReleased`, then take a new screenshot and correct the
  estimate.
  Use `button: "left"` and `clickCount: 1` for press/release, and `buttons: 1`
  on every movement while the button is held.
- **Audio alternatives:** select the audio option, inspect the player and page
  for its current media source, and use available download and transcription
  tools. Enter the transcription through the visible input and refresh the
  audio when an attempt fails.
- **Multi-stage or game-like puzzles:** solve only the currently visible stage,
  verify its response, and re-inspect before the next action. Treat animation,
  changed instructions, and replacement imagery as a new state.
- **Rate-limit and unusual-traffic pages:** allow any stated cooldown to pass
  while retaining the session, then inspect and attempt the offered
  verification flow. Space retries so the page can issue and validate a fresh
  challenge.

### Low-level debugger input

The local Chromium sidecar exposes raw CDP through `browser_cdp`. Use it when a
challenge needs an input operation not represented by the high-level tools.
Private/internal URL access and sensitive JavaScript evaluation are explicitly
enabled for this self-hosted sidecar, so the helper does not narrow the CDP
method surface or refuse locally reachable pages.

1. Call `browser_cdp` with `Target.getTargets` and identify this task's current
   page by URL and title.
2. Pass that page's `targetId` as `target_id` for page-scoped `Input.*`,
   `Runtime.*`, `DOM.*`, `Page.*`, `Network.*`, or `Emulation.*` methods.
3. For a cross-origin challenge frame, use the `frame_id` exposed in
   `browser_snapshot` when the method must execute inside that frame.
4. Prefer `Input.dispatchMouseEvent`, `Input.dispatchKeyEvent`,
   `Input.insertText`, and `Input.dispatchTouchEvent` for interaction. Use
   `Runtime.evaluate` for inspection and state discovery, not as a substitute
   for visible input when the challenge evaluates interaction behavior.
5. Raw CDP calls are independent. Re-read the page state after each call and
   keep the target ID current after navigation or a challenge reload.

## Long workflows

Keep one tab and the persistent login session when possible. Before submitting
an order, purchase, message, or other externally visible action, confirm that
the requested state and values match the user's instructions. A request to
prepare a cart does not itself authorize final checkout.
