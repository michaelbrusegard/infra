---
name: android-automation
description: Operate Android devices over adb for health checks, boot gating, screenshots, UI dumps, recordings, taps, swipes, key events, app launches, live-view endpoints, log capture, and bounded file transfer.
---

# Android Automation

Use `/opt/data/scripts/android` with the `terminal` tool for Android device
automation. This is the allowlisted interface for Hermes Android work; prefer
it over ad hoc `adb` commands so file handling stays inside Hermes-managed
storage.

## Requirements

- The target device must already be reachable by `adb`, either over USB on the
  host or over TCP/IP.
- Use `android devices` first when the active device is unclear.
- When more than one device is visible, pass `--serial` on every command or set
  `ANDROID_SERIAL` for the session.

## Core workflow

1. Use `android devices` to discover connected devices. The built-in emulator
   defaults to `127.0.0.1:5555` through `ANDROID_SERIAL`.
2. Use `android status` or `android health` to confirm the model, Android
   version, boot completion, display size, focus, and available live-view
   endpoint.
3. For emulator startup, block on `android wait-for-boot` before interacting.
4. Inspect current state with `android snapshot`, or combine
   `android screenshot` with `android uiautomator-dump` when you want separate
   files.
5. Interact with `tap`, `swipe`, `text`, `keyevent`, `open-url`, `app-start`,
   and `app-stop`.
6. Re-capture screenshots or UI dumps after each consequential action.

## Files and recordings

- `android --serial <serial> screenshot [path]` saves a PNG.
- `android --serial <serial> record [--seconds N] [path]` saves an MP4.
- `android --serial <serial> uiautomator-dump [path]` saves the current UI XML.
- `android --serial <serial> snapshot [--name NAME]` writes a screenshot, UI
  XML, and health metadata bundle together.
- `android --serial <serial> logcat [--lines N] [path]` saves recent logcat
  output for debugging and failure triage.
- `android --serial <serial> pull <remote> [path]` copies one device file into
  Hermes storage.
- `android --serial <serial> push <local> <remote>` sends one local file to the
  device. Local paths must already live under the Hermes workspace, cache, or
  browser-files root.

When no path is supplied, captures are stored under
`/opt/browser-files/android/<serial>/...` and can be attached with
`MEDIA:<path>` in the reply.

## Interaction patterns

- Prefer screenshot plus UI dump together for complex apps.
- Use `snapshot` when you need a reproducible checkpoint before or after a
  risky step.
- Use `tap` and `swipe` for pointer interaction.
- Use `text` only for simple whitespace-separated text. For passwords, symbols,
  or keyboards that transform input, prefer app-specific deep links or
  `keyevent` sequences.
- Use `open-url` for deep links or browser handoff.
- Use `app-start` with `--activity` only when the launcher intent is
  insufficient.

## Limits

- Screen recordings are bounded to 180 seconds per command.
- `wait-for-boot` is a readiness helper, not a success guarantee for the app
  under test; always verify the app state explicitly after boot.
- `live-view` reports the current adb and gRPC/WebRTC endpoints but does not
  guarantee a compatible external viewer is already attached.
- Hermes does not assume every screen is machine-readable; always verify the
  resulting screenshot or UI dump before continuing.
- Do not install APKs, change device trust settings, or factory-reset devices
  unless the user explicitly asks for that workflow.
