---
name: android-automation
description: Operate the persistent Android emulator through structured UI refs, screenshots, recordings, app controls, a browser-accessible live console, and unrestricted adb/debugger passthrough. Use Android as an alternate interaction surface for shopping, sign-in, apps, WebViews, CAPTCHA recovery, or sites that reject desktop automation.
---

# Android Automation

Use `/opt/data/scripts/android` with the `terminal` tool. The built-in emulator
uses the persistent serial `127.0.0.1:5555`; its installed apps, login state,
and device data survive pod restarts.

When the underlying Android system image changes, the launcher compares the
image fingerprint before boot. It moves an incompatible prior AVD to
`/opt/android/android-home-migrations/` as seen from the agent and seeds a clean
device instead of corrupting the old userdata. Ordinary pod and container
restarts do not trigger this migration.

## Reliable interaction loop

1. Run `android wait-for-boot`, then `android health`.
2. Run `android snapshot --name <checkpoint>` before a long or consequential
   flow. It saves the screenshot, UI XML, and device health together.
3. Run `android ui-tree`. Prefer a semantic node with text, content
   description, or resource ID.
4. Use `android tap-ref <ref> --tree-id <tree-id>` to reject a stale ref if the
   screen changed. Use coordinate `tap`, `long-press`, or `swipe` when the
   target is visual-only.
5. Re-run `ui-tree`, `screenshot`, or `snapshot` after every consequential
   action. Verify the visible result instead of assuming an input succeeded.

Use `android live-view` for the browser-compatible noVNC console URL. The
console is backed by scrcpy, accepts mouse and keyboard input, and reconnects
when the emulator or app restarts. The same command also reports the raw ADB
and emulator gRPC endpoints for debugging.

For a manual login or approval handoff, keep the noVNC service cluster-local
and have the operator run
`kubectl -n hermes-agent port-forward svc/hermes-android 6080:6080`, then open
`http://127.0.0.1:6080/vnc.html?autoconnect=true&resize=scale`. Credentials,
passkeys, one-time codes, and payment data can be entered directly into the
visible phone without placing them in an ADB command or agent log. After the
handoff, refresh `android health` and `android ui-tree` and continue from the
persisted device state.

## Commands

```sh
android devices
android status
android health
android wait-for-boot [--timeout N]
android live-view
android screenshot [path]
android record [--seconds N] [path]
android snapshot [--name NAME]
android uiautomator-dump [path]
android ui-tree
android tap <x> <y>
android tap-ref <ref> [--tree-id ID]
android long-press <x> <y> [--duration-ms N]
android swipe <x1> <y1> <x2> <y2> [--duration-ms N]
android text '<text>'
android keyevent <keycode-or-name>
android rotate <auto|portrait|landscape|reverse-portrait|reverse-landscape>
android open-url <url>
android app-start <package> [--activity ACTIVITY]
android app-stop <package>
android packages [--third-party|--system] [--filter TEXT]
android install <apk> [--grant-all] [--downgrade] [--test-only]
android install-aurora
android uninstall <package> [--keep-data]
android permission <grant|revoke> <package> <permission>
android push <local> <remote>
android pull <remote> [local]
android logcat [--lines N] [path]
```

Recordings longer than Android's per-process screenrecord limit are captured
in segments and joined automatically. Capture files default to
`/opt/browser-files/android/<serial>/...` and can be attached with
`MEDIA:<path>`.

## Installing apps

The emulator uses the stable Android 17/API 37 x86_64 Play Store image with
ARM64 translation. Prefer the built-in Play Store for apps that use Play
delivery, split APKs, or Play services. Use the visible UI to sign in, search,
install, update, and grant requested permissions exactly as on a phone.

Aurora Store 4.8.4 is also bundled from the official AuroraOSS release with a
pinned SHA-256 checksum. Run `android install-aurora`, launch
`com.aurora.store`, complete its visible first-run flow, and use either an
anonymous session or an account as appropriate. Aurora's anonymous accounts
can be rate-limited, regionally inconsistent, or temporarily unavailable; the
Play Store and direct APK installation remain available at the same time.

For Amazon Shopping, search for the official package
`com.amazon.mShop.android.shopping`, verify the publisher and package before
installing, then launch it with
`android app-start com.amazon.mShop.android.shopping`. Complete login in the
visible app, keep the device session intact, and stop before submitting an
order unless the user's request explicitly authorizes that purchase.

For any other APK, download it to any path visible inside the agent container
and run `android install <path>`. The structured helper does not impose a path
allowlist, and `android adb install-multiple ...` remains available for split
packages. Never claim an app is usable merely because installation returned
success: launch it and verify its first screen, network access, and login flow.

Some apps require real-device Play Integrity, hardware-backed keys, a SIM,
passkeys, or account approval. The agent can complete every locally visible
step and preserve the exact state for a user handoff, but an emulator cannot
truthfully supply missing physical hardware attestation.

## Full debugger access

`android adb <arguments...>` passes any command directly to ADB with inherited
stdin, stdout, stderr, and exit status. It supports the complete debugger
surface, including interactive shell, `dumpsys`, activity/package managers,
port forwarding, reverse tunnels, bug reports, file sync, install-multiple,
input events, settings, and raw logcat. `--serial` before `adb` selects a
device. Use `android adb --no-serial ...` for server-wide commands or when
passing your own device selector. All remaining ADB arguments are unfiltered
and unmodified. The Play Store system image is a production-style build, so
Android itself can refuse privileged operations such as `adb root`; that is a
property of the guest image, not a filter in the Hermes helper. UI automation,
package installation, shell commands, input injection, port forwarding, file
transfer, screenshots, recordings, bug reports, and permitted logcat/dumpsys
surfaces remain available.

Examples:

```sh
android adb shell dumpsys window
android adb shell cmd package resolve-activity --brief com.android.chrome
android adb forward tcp:9000 localabstract:service
android adb install-multiple base.apk split_config.arm64_v8a.apk
android adb --no-serial devices -l
android adb --no-serial -s another-device shell
```

## CAPTCHA and verification recovery

Always inspect and attempt the available local verification flow. Treat it as
a state machine and preserve evidence after every attempt.

- **Checkboxes and ordinary buttons:** use `ui-tree` and a current ref. Verify
  that the widget, enclosing form, or page changed; a checkbox may reveal a
  second stage.
- **Text or distorted-image prompts:** take a screenshot, read the prompt and
  image carefully, enter the exact text, and capture a new image after any
  rejection.
- **Static image grids:** identify the prompt, grid bounds, tile count, and
  center of every matching tile. Tap each center, re-screenshot the full grid,
  then submit.
- **Dynamic image grids:** tap one matching tile at a time and capture a new
  screenshot after every replacement. Re-evaluate until the requested object
  no longer appears.
- **Sliders, drag-to-fit, and rotation puzzles:** estimate the handle and
  destination from the screenshot, perform a continuous `swipe` with a
  realistic duration, then inspect the new state and refine the path.
- **Audio alternatives:** select the audio route, use the live console and
  device logs or debugger to locate the current media source, transcribe it
  with available local tools, and enter the result through the visible UI.
- **Managed interstitials and WebView checks:** keep the app foregrounded,
  allow the check to finish, then inspect again. If it loops, collect a
  snapshot and logcat, restart only the affected app, and retry from the
  preserved device session.
- **Game-like, multi-stage challenges:** solve only the current stage, verify
  its response, and treat changed instructions or imagery as a new state.

If the Android app succeeds where Chromium is repeatedly challenged, keep the
workflow in Android so its device identity, cookies, app data, and login state
remain coherent. If a provider requires hardware-backed attestation, an
account approval, or a human-only action, record the exact remaining state;
do not report that the challenge cleared until the original task screen is
visibly restored.
