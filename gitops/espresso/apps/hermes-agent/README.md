# Hermes Agent

Self-hosted Hermes gateway with a persistent Chromium sidecar and a KVM-backed
Android emulator pinned to `espresso-0`.

## Browser layout

- Persistent profile PVC: `/opt/browser`
- Shared task artifact PVC: `/opt/browser-files`
- Session metadata: `/opt/browser-files/browser-sessions/*.json`
- Session event logs: `/opt/browser-files/browser-session-events/*.jsonl`
- Checkpoints: `/opt/browser-files/browser-checkpoints/`
- Profile backups: `/opt/browser-files/browser-profile-backups/`

The browser sidecar runs headed Chromium behind Xvfb and exposes:

- CDP: `http://127.0.0.1:9222`
- noVNC: `http://127.0.0.1:6080/vnc.html`

Supervisor state is written to:

- `/opt/browser-files/browser-supervisor/status.json`

## Browser controls

Optional site policies and unpacked extensions are profile-owned, not image-owned.

- Managed Chromium policy drop-ins: `/opt/browser/policies/managed/*.json`
- Unpacked extensions: `/opt/browser/extensions-unpacked/<name>/<version>/manifest.json`
- Extra Chromium args: `/opt/browser/chromium-extra-args`

The image always installs uBlock Origin Lite through managed policy. Additional
policy files and extensions are loaded from the persistent profile at startup.

## Browser helpers

Hermes task routing and diagnostics are backed by:

- `browser_upload` and `browser_download` for task-scoped file exchange
- `browser-support` for frame, clipboard, raw input, checkpoint, recording,
  verification, cleanup, diagnostics, and profile-backup operations

Use `browser-support diagnostics` to inspect current targets, supervisor state,
policy files, unpacked extensions, persisted sessions, and browser-files usage.

## Android layout

- Emulator PVC: `/opt/android` in the gateway container, `/data` in the emulator
- Persistent ADB auth keys: `/opt/android/adb/adbkey{,.pub}`
- Default ADB target: `127.0.0.1:5555`
- Default WebRTC endpoint: `http://hermes-android.hermes-agent.svc.cluster.local:8554`

The workload is pinned to `espresso-0` because that node is the only one with
`/dev/kvm`.

Captured Android artifacts land under:

- `/opt/browser-files/android/<serial>/screenshots/`
- `/opt/browser-files/android/<serial>/recordings/`
- `/opt/browser-files/android/<serial>/uiautomator/`
- `/opt/browser-files/android/<serial>/snapshots/`
- `/opt/browser-files/android/<serial>/logcat/`

## Validation

Relevant checks for this app:

```sh
nix-shell -p 'python3.withPackages (ps: with ps; [ requests websocket-client ])' \
  --run 'python3 -m unittest discover -s gitops/espresso/apps/hermes-agent/tests -p "test_*.py"'

nix develop -c sh -c '
  kustomize build gitops/espresso | kubeconform -strict -ignore-missing-schemas \
    -schema-location default \
    -schema-location "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
'
```
