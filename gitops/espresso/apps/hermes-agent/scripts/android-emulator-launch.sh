#!/usr/bin/env bash
set -euo pipefail

DATA_ROOT=/data
ADB_DIR="$DATA_ROOT/adb"
AVD_HOME="$DATA_ROOT/android-home"
AVD_MIGRATIONS="$DATA_ROOT/android-home-migrations"
SYSTEM_BUILD_PROP=$(find /android/sdk/system-images -type f -name build.prop -print -quit)

if [ -z "$SYSTEM_BUILD_PROP" ]; then
  echo "android-emulator: no system-image build.prop found" >&2
  exit 1
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
mkdir -p /root/.android "$ADB_DIR" "$AVD_HOME" /tmp/android-unknown /tmp/pulse

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
cat /tmp/android-unknown/kernel.log | sed -u 's/^/kernel: /g' &
cat /tmp/android-unknown/logcat.log | sed -u 's/^/logcat: /g' &

/android/sdk/platform-tools/adb start-server
socat -d tcp-listen:5555,reuseaddr,fork tcp:127.0.0.1:5557 &

launch_cmd=(
  /android/sdk/emulator/emulator
  -avd "$AVD_NAME"
  -ports "5556,5557"
  -grpc 8554
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
exec "${launch_cmd[@]}"
