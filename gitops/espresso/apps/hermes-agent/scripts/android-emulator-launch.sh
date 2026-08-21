#!/usr/bin/env bash
set -euo pipefail

DATA_ROOT=/data
ADB_DIR="$DATA_ROOT/adb"
AVD_HOME="$DATA_ROOT/android-home"
AVD_MIGRATIONS="$DATA_ROOT/android-home-migrations"
STATUS_DIR="$DATA_ROOT/status"
STATUS_FILE="$STATUS_DIR/launcher.json"
ACCESSIBILITY_STATUS_FILE="$STATUS_DIR/accessibility.json"
COMPANION_DIR="$DATA_ROOT/companion"
GRPC_TOKEN_FILE="$COMPANION_DIR/emulator-grpc-token"
GRPC_ALLOWLIST_FILE="$COMPANION_DIR/emulator-access.json"
ACCESSIBILITY_PACKAGE=com.hermes.agent.accessibility
ACCESSIBILITY_SERVICE="$ACCESSIBILITY_PACKAGE/.HermesAccessibilityService"
COMPANION_AUTH_TOKEN_FILE="$COMPANION_DIR/auth-token"
SYSTEM_BUILD_PROP=$(find /android/sdk/system-images -type f -name build.prop -print -quit)

mkdir -p "$STATUS_DIR" "$COMPANION_DIR"

if [ -z "$SYSTEM_BUILD_PROP" ]; then
  echo "android-emulator: no system-image build.prop found" >&2
  exit 1
fi

system_sdk=$(sed -n 's/^ro\.build\.version\.sdk=//p' "$SYSTEM_BUILD_PROP" | head -1)
system_release=$(sed -n 's/^ro\.build\.version\.release=//p' "$SYSTEM_BUILD_PROP" | head -1)
required_sdk="${ANDROID_REQUIRED_SDK:-}"
required_release="${ANDROID_REQUIRED_RELEASE:-}"

if [ -n "$required_sdk" ] && [ "$system_sdk" != "$required_sdk" ]; then
  refusal="system image sdk=${system_sdk:-unknown}; expected sdk=$required_sdk"
else
  refusal=
fi

if [ -n "$required_release" ] && [ "$system_release" != "$required_release" ]; then
  refusal="${refusal:+$refusal; }system image release=${system_release:-unknown}; expected release=$required_release"
fi

if [ -n "$refusal" ]; then
  echo "android-emulator: disabled: $refusal" >&2
  cat >"$STATUS_FILE.tmp" <<EOF
{"state":"disabled","reason":"wrong-platform","detail":"$refusal","updated_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","sdk":"${system_sdk:-}","release":"${system_release:-}"}
EOF
  mv "$STATUS_FILE.tmp" "$STATUS_FILE"
  trap 'exit 0' INT TERM
  while true; do
    sleep 3600 &
    wait $!
  done
fi

SYSTEM_IMAGE_ID=$(sha256sum "$SYSTEM_BUILD_PROP" | cut -d ' ' -f1)
SYSTEM_IMAGE_MARKER="$AVD_HOME/.hermes-system-image-sha256"

seed_ini=$(find /android-home -maxdepth 1 -type f -name '*.ini' -print -quit)
persisted_ini=$(find "$AVD_HOME" -maxdepth 1 -type f -name '*.ini' -print -quit 2>/dev/null || true)
reset_reason=
if [ -n "$persisted_ini" ] && [ -s "$SYSTEM_IMAGE_MARKER" ]; then
  persisted_system_image_id=$(tr -d '\r\n' < "$SYSTEM_IMAGE_MARKER")
  if [ "$persisted_system_image_id" != "$SYSTEM_IMAGE_ID" ]; then
    reset_reason="system image changed from ${persisted_system_image_id:0:12} to ${SYSTEM_IMAGE_ID:0:12}"
  fi
elif [ -n "$persisted_ini" ] && [ -n "$seed_ini" ]; then
  persisted_config="${persisted_ini%.ini}.avd/config.ini"
  seed_config="${seed_ini%.ini}.avd/config.ini"
  persisted_tag=$(sed -n 's/^tag.id=//p' "$persisted_config" 2>/dev/null | head -1)
  seed_tag=$(sed -n 's/^tag.id=//p' "$seed_config" 2>/dev/null | head -1)
  if [ -n "$persisted_tag" ] && [ -n "$seed_tag" ] && [ "$persisted_tag" != "$seed_tag" ]; then
    reset_reason="system image tag changed from $persisted_tag to $seed_tag"
  fi
fi

if [ -n "$reset_reason" ]; then
  migration_dir="$AVD_MIGRATIONS/$(date -u +%Y%m%dT%H%M%SZ)-${SYSTEM_IMAGE_ID:0:12}"
  mkdir -p "$AVD_MIGRATIONS"
  mv "$AVD_HOME" "$migration_dir"
  mkdir -p "$AVD_HOME"
  echo "android-emulator: preserved incompatible AVD at $migration_dir ($reset_reason)" >&2
fi

rm -rf /tmp/android-unknown /tmp/pulse /tmp/pulse-socket
mkdir -p /root/.android "$ADB_DIR" "$AVD_HOME" "$STATUS_DIR" "$COMPANION_DIR" /tmp/android-unknown /tmp/pulse
find /android/sdk/emulator/lib -maxdepth 1 -type f -name '*.proto' \
  -exec install -m 0644 {} "$COMPANION_DIR/" \;
cp /android/sdk/emulator/lib/emulator_access.json "$GRPC_ALLOWLIST_FILE"
sed -i '\|/android.emulation.control.EmulatorController/\.\*|a\                "/android.emulation.control.v2.Rtc/.*",' \
  "$GRPC_ALLOWLIST_FILE"
chmod 0644 "$GRPC_ALLOWLIST_FILE"

if ! find "$AVD_HOME" -maxdepth 1 -type f -name '*.ini' -print -quit | grep -q .; then
  cp -a /android-home/. "$AVD_HOME/"
fi
printf '%s\n' "$SYSTEM_IMAGE_ID" > "$SYSTEM_IMAGE_MARKER"

AVD_INI=$(find "$AVD_HOME" -maxdepth 1 -type f -name '*.ini' -print -quit)
if [ -z "$AVD_INI" ]; then
  echo "android-emulator: no AVD metadata found in $AVD_HOME" >&2
  exit 1
fi

AVD_NAME=$(basename "$AVD_INI" .ini)
AVD_DIR="$AVD_HOME/$AVD_NAME.avd"
AVD_CONFIG_FILE="$AVD_DIR/config.ini"
if [ ! -s "$AVD_CONFIG_FILE" ]; then
  echo "android-emulator: missing AVD config $AVD_CONFIG_FILE" >&2
  exit 1
fi

sed -i "s|^path=.*|path=$AVD_DIR|" "$AVD_INI"
export ANDROID_AVD_HOME="$AVD_HOME"
find "$AVD_DIR" -maxdepth 1 -type f -name '*.lock' -delete

if [ ! -s "$ADB_DIR/adbkey" ] || [ ! -s "$ADB_DIR/adbkey.pub" ]; then
  echo "android-emulator: missing persisted adb key material in $ADB_DIR" >&2
  exit 1
fi

cp "$ADB_DIR/adbkey" /root/.android/adbkey
cp "$ADB_DIR/adbkey.pub" /root/.android/adbkey.pub
chmod 600 /root/.android/adbkey

if [ -n "${AVD_CONFIG:-}" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key=${line%%=*}
    value=${line#*=}
    if grep -q "^${key}=" "$AVD_CONFIG_FILE"; then
      sed -i "s|^${key}=.*|${key}=${value}|" "$AVD_CONFIG_FILE"
    else
      printf '%s\n' "$line" >> "$AVD_CONFIG_FILE"
    fi
  done <<< "${AVD_CONFIG}"
fi

export PULSE_SERVER=unix:/tmp/pulse-socket
pulseaudio -D --exit-idle-time=-1
pactl list >/dev/null

mkfifo /tmp/android-unknown/kernel.log
mkfifo /tmp/android-unknown/logcat.log
tail --retry -f /tmp/android-unknown/goldfish_rtc_0 2>/dev/null | sed -u 's/^/video: /g' &
video_pid=$!
cat /tmp/android-unknown/kernel.log | sed -u 's/^/kernel: /g' &
kernel_pid=$!
cat /tmp/android-unknown/logcat.log | sed -u 's/^/logcat: /g' &
logcat_pid=$!

/android/sdk/platform-tools/adb start-server
socat -d tcp-listen:5555,reuseaddr,fork tcp:127.0.0.1:5557 &
socat_pid=$!

launch_cmd=(
  /android/sdk/emulator/emulator
  -avd "$AVD_NAME"
  -ports "5556,5557"
  -grpc 8554
  -grpc-use-token
  -grpc-allowlist "$GRPC_ALLOWLIST_FILE"
  -no-window
  -no-snapshot-save
  -no-boot-anim
  -shell-serial file:/tmp/android-unknown/kernel.log
  -logcat '*:V'
  -feature AllowSnapshotMigration
)

if [ -n "${EMULATOR_PARAMS:-}" ]; then
  # shellcheck disable=SC2206
  extra_params=(${EMULATOR_PARAMS})
  launch_cmd+=("${extra_params[@]}")
fi

launch_cmd+=(-qemu -append panic=1)

echo "android-emulator: ${launch_cmd[*]}"

write_status() {
  state=$1
  cat >"$STATUS_FILE.tmp" <<EOF
{"state":"$state","updated_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","sdk":"${system_sdk:-}","release":"${system_release:-}","system_image_id":"$SYSTEM_IMAGE_ID"}
EOF
  mv "$STATUS_FILE.tmp" "$STATUS_FILE"
}

write_accessibility_status() {
  state=$1
  detail=${2:-}
  cat >"$ACCESSIBILITY_STATUS_FILE.tmp" <<EOF
{"state":"$state","detail":"$detail","updated_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF
  mv "$ACCESSIBILITY_STATUS_FILE.tmp" "$ACCESSIBILITY_STATUS_FILE"
}

adb_device() {
  /android/sdk/platform-tools/adb -s 127.0.0.1:5555 "$@"
}

wait_for_boot() {
  for _ in $(seq 1 180); do
    /android/sdk/platform-tools/adb connect 127.0.0.1:5555 >/dev/null 2>&1 || true
    if [ "$(adb_device shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
      return 0
    fi
    sleep 2
  done
  return 1
}

publish_grpc_token() {
  token=
  for discovery_file in /root/.android/avd/running/pid_*.ini /tmp/pid_*_info.ini; do
    [ -f "$discovery_file" ] || continue
    grpc_port=$(sed -n 's/^grpc\.port=//p' "$discovery_file" | head -1)
    [ "$grpc_port" = 8554 ] || continue
    token=$(sed -n 's/^grpc\.token=//p' "$discovery_file" | head -1)
    [ -n "$token" ] && break
  done
  if [ -z "$token" ]; then
    return 1
  fi
  printf '%s\n' "$token" >"$GRPC_TOKEN_FILE.tmp"
  chmod 600 "$GRPC_TOKEN_FILE.tmp"
  chown 10000:10000 "$GRPC_TOKEN_FILE.tmp"
  mv "$GRPC_TOKEN_FILE.tmp" "$GRPC_TOKEN_FILE"
}

enable_accessibility_companion() {
  companion_apk=$(find "$DATA_ROOT/apks" -maxdepth 1 -type f -name 'HermesAccessibility-*.apk' -print -quit)
  if [ -z "$companion_apk" ]; then
    write_accessibility_status degraded missing-apk
    return 1
  fi
  companion_version=$(basename "$companion_apk")
  companion_version=${companion_version#HermesAccessibility-}
  companion_version=${companion_version%.apk}
  installed_version=$(adb_device shell dumpsys package "$ACCESSIBILITY_PACKAGE" 2>/dev/null | \
    sed -n 's/^ *versionName=//p' | head -1 | tr -d '\r')
  if [ "$installed_version" != "$companion_version" ]; then
    if ! adb_device install -r -g "$companion_apk" >/dev/null; then
      write_accessibility_status degraded install-failed
      return 1
    fi
  fi

  enabled=$(adb_device shell settings get secure enabled_accessibility_services 2>/dev/null | tr -d '\r')
  case ":$enabled:" in
    *":$ACCESSIBILITY_SERVICE:"*) ;;
    ":null:"|"::") enabled=$ACCESSIBILITY_SERVICE ;;
    *) enabled="$enabled:$ACCESSIBILITY_SERVICE" ;;
  esac
  adb_device shell settings put secure enabled_accessibility_services "$enabled"
  adb_device shell settings put secure accessibility_enabled 1
  if [ ! -s "$COMPANION_AUTH_TOKEN_FILE" ]; then
    write_accessibility_status degraded missing-auth-token
    return 1
  fi
  companion_auth_token=$(tr -d '\r\n' <"$COMPANION_AUTH_TOKEN_FILE")
  adb_device shell am broadcast \
    --receiver-foreground \
    -a com.hermes.agent.accessibility.CONFIGURE \
    -n "$ACCESSIBILITY_PACKAGE/.ConfigReceiver" \
    --es token "$companion_auth_token" >/dev/null

  health_request_file="/tmp/hermes-accessibility-health-$$.json"
  remote_health_request="/data/local/tmp/hermes-accessibility-health-$$.json"
  printf '{"op":"health","token":"%s"}\n' "$companion_auth_token" >"$health_request_file"
  chmod 600 "$health_request_file"
  if ! adb_device push "$health_request_file" "$remote_health_request" >/dev/null; then
    rm -f "$health_request_file"
    write_accessibility_status degraded request-upload-failed
    return 1
  fi

  for _ in $(seq 1 30); do
    response=$(adb_device shell \
      "nc -w 2 127.0.0.1 8765 < $remote_health_request" 2>/dev/null || true)
    if printf '%s' "$response" | grep -q '"ok":true'; then
      adb_device shell rm -f "$remote_health_request" >/dev/null 2>&1 || true
      rm -f "$health_request_file"
      write_accessibility_status ready connected
      return 0
    fi
    sleep 1
  done
  adb_device shell rm -f "$remote_health_request" >/dev/null 2>&1 || true
  rm -f "$health_request_file"
  write_accessibility_status degraded socket-unavailable
  return 1
}

supervise_control_plane() {
  if ! wait_for_boot; then
    write_accessibility_status degraded boot-timeout
    return
  fi
  while kill -0 "$emulator_pid" 2>/dev/null; do
    publish_grpc_token || true
    enable_accessibility_companion || true
    sleep 30
  done
}

# shellcheck disable=SC2329 # Invoked indirectly by the EXIT trap.
cleanup() {
  if [ "${cleanup_complete:-false}" = true ]; then
    return
  fi
  cleanup_complete=true
  write_status "stopping"
  if [ -n "${control_pid:-}" ]; then
    kill -TERM "$control_pid" 2>/dev/null || true
  fi
  if [ -n "${emulator_pid:-}" ] && kill -0 "$emulator_pid" 2>/dev/null; then
    adb_device shell sync >/dev/null 2>&1 || true
    adb_device emu kill >/dev/null 2>&1 || true
    for _ in $(seq 1 15); do
      if ! kill -0 "$emulator_pid" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    kill -TERM "$emulator_pid" 2>/dev/null || true
    for _ in $(seq 1 15); do
      if ! kill -0 "$emulator_pid" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    kill -KILL "$emulator_pid" 2>/dev/null || true
  fi
  for pid in "${socat_pid:-}" "${video_pid:-}" "${kernel_pid:-}" "${logcat_pid:-}"; do
    if [ -n "$pid" ]; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  pulseaudio --kill >/dev/null 2>&1 || true
  write_status "stopped"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
rm -f "$GRPC_TOKEN_FILE"
write_accessibility_status "starting" "waiting-for-boot"
write_status "starting"
"${launch_cmd[@]}" &
emulator_pid=$!
supervise_control_plane &
control_pid=$!
write_status "running"
set +e
wait "$emulator_pid"
emulator_status=$?
set -e
write_status "exited"
exit "$emulator_status"
