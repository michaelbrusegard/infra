---
name: android-automation
description: Operate Android devices over adb for screenshots, UI dumps, taps, swipes, key events, app launches, recordings, and bounded file transfer.
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

1. Use `android devices` to discover connected devices.
2. Use `android --serial <serial> status` to confirm the model and Android
   version.
3. Inspect current state with `android --serial <serial> screenshot` and, when
   structure matters, `android --serial <serial> uiautomator-dump`.
4. Interact with `tap`, `swipe`, `text`, `keyevent`, `open-url`, `app-start`,
   and `app-stop`.
5. Re-capture screenshots or UI dumps after each consequential action.

## Files and recordings

- `android --serial <serial> screenshot [path]` saves a PNG.
- `android --serial <serial> record [--seconds N] [path]` saves an MP4.
- `android --serial <serial> uiautomator-dump [path]` saves the current UI XML.
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
- Use `tap` and `swipe` for pointer interaction.
- Use `text` only for simple whitespace-separated text. For passwords, symbols,
  or keyboards that transform input, prefer app-specific deep links or
  `keyevent` sequences.
- Use `open-url` for deep links or browser handoff.
- Use `app-start` with `--activity` only when the launcher intent is
  insufficient.

## Limits

- Screen recordings are bounded to 180 seconds per command.
- Hermes does not assume every screen is machine-readable; always verify the
  resulting screenshot or UI dump before continuing.
- Do not install APKs, change device trust settings, or factory-reset devices
  unless the user explicitly asks for that workflow.
