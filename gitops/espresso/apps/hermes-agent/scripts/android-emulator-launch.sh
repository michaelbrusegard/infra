#!/usr/bin/env bash
set -euo pipefail

DATA_ROOT=/data
ADB_DIR="$DATA_ROOT/adb"
ANDROID_AVD_HOME=/root/.android/avd
AVD_HOME="$DATA_ROOT/android-home"
AVD_CONFIG_FILE="$AVD_HOME/avd/MediumPhone.avd/config.ini"

mkdir -p /root/.android "$ADB_DIR" "$AVD_HOME" /tmp/android-unknown /tmp/pulse
rm -rf /tmp/*

if [ ! -d "$AVD_HOME/avd/MediumPhone.avd" ]; then
  cp -a /android-home/. "$AVD_HOME/"
fi

ln -snf "$AVD_HOME/avd" "$ANDROID_AVD_HOME"
printf 'path=%s/MediumPhone.avd\n' "$ANDROID_AVD_HOME" > /root/.android/MediumPhone.ini

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
  emulator/emulator
  -avd MediumPhone
  -ports 5556,5557
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
