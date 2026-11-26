#!/usr/bin/env bash
set -e

set -a
# shellcheck disable=SC1091 # shellcheck is run on this file alone
source packages/hermes-android-image/versions.env
set +a
test -c /dev/kvm
sudo chmod 0666 /dev/kvm
smoke_root=$(mktemp -d)
mkdir -p "$smoke_root/data" "$smoke_root/tmp"
chmod 0777 "$smoke_root/tmp"
docker run --rm \
  --volume "$smoke_root/data:/data" \
  --entrypoint bash \
  "$ANDROID_IMAGE_REF:ci" -euc '
    mkdir -p /data/adb /data/android-home /data/apks /data/companion
    /android/sdk/platform-tools/adb keygen /data/adb/adbkey
    od -An -tx1 -N 32 /dev/urandom | tr -d " \n" >/data/companion/auth-token
    cp /opt/hermes/apks/AuroraStore-*.apk /data/apks/
    cp /opt/hermes/apks/HermesAccessibility-*.apk /data/apks/
    chmod 0600 /data/adb/adbkey /data/companion/auth-token
    chmod 0644 /data/adb/adbkey.pub /data/apks/*.apk
  '

start_emulator() {
  docker rm --force hermes-android-smoke >/dev/null 2>&1 || true
  docker run --detach \
    --name hermes-android-smoke \
    --device /dev/kvm \
    --volume "$PWD/gitops/espresso/apps/hermes-agent/scripts/android-emulator-launch.sh:/bootstrap/android-emulator-launch.sh:ro" \
    --volume "$SOURCE_ROOT/grpcurl:/opt/hermes/bin/grpcurl:ro" \
    --volume "$smoke_root/data:/data" \
    --volume "$smoke_root/tmp:/tmp" \
    --env ADB_VENDOR_KEYS=/data/adb \
    --env ANDROID_REQUIRED_RELEASE=17 \
    --env ANDROID_REQUIRED_SDK=37 \
    --env 'AVD_CONFIG=disk.dataPartition.size=4096M
hw.keyboard=yes' \
    --env 'EMULATOR_PARAMS=-gpu swiftshader_indirect -timezone UTC' \
    --entrypoint bash \
    "$ANDROID_IMAGE_REF:ci" \
    /bootstrap/android-emulator-launch.sh
}

wait_for_boot() {
  for attempt in $(seq 1 90); do
    # The launcher writes this after starting its ADB server. Calling
    # ADB earlier races two server processes for the same listener.
    case "$(jq -r '.state // empty' "$smoke_root/data/status/launcher.json" 2>/dev/null)" in
    starting | running)
      docker exec hermes-android-smoke \
        /android/sdk/platform-tools/adb connect 127.0.0.1:5555 \
        >/dev/null 2>&1 || true
      if [ "$(docker exec hermes-android-smoke \
        /android/sdk/platform-tools/adb -s 127.0.0.1:5555 \
        shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
        return 0
      fi
      ;;
    esac
    if [ "$(docker inspect --format '{{.State.Running}}' \
      hermes-android-smoke 2>/dev/null || true)" != true ]; then
      docker logs hermes-android-smoke 2>&1 || true
      return 1
    fi
    if [ "$attempt" = 90 ]; then
      docker logs hermes-android-smoke
      return 1
    fi
    sleep 5
  done
}

adb_cmd() {
  docker exec hermes-android-smoke \
    /android/sdk/platform-tools/adb -s 127.0.0.1:5555 "$@"
}

assert_running_launcher() {
  test "$(jq -r '.state' "$smoke_root/data/status/launcher.json")" = running
}

wait_for_accessibility() {
  for attempt in $(seq 1 60); do
    if [ "$(jq -r '.state // empty' "$smoke_root/data/status/accessibility.json" 2>/dev/null)" = ready ]; then
      return 0
    fi
    if [ "$attempt" = 60 ]; then
      docker logs hermes-android-smoke
      return 1
    fi
    sleep 2
  done
}

accessibility_request() {
  token=$(docker exec --user 0:0 hermes-android-smoke \
    sh -c 'tr -d "\r\n" </data/companion/auth-token')
  request=$(jq -cn --argjson payload "$1" --arg token "$token" \
    '$payload + {token: $token}')
  accessibility_raw_request "$request"
}

accessibility_raw_request() {
  encoded=$(printf '%s\n' "$1" | base64 --wrap=0)
  adb_cmd shell \
    "printf %s $encoded | base64 -d | nc -w 20 127.0.0.1 8765"
}

grpc_request() {
  token=$(docker exec --user 0:0 hermes-android-smoke \
    sh -c 'tr -d "\r\n" </data/companion/emulator-grpc-token')
  docker exec hermes-android-smoke /opt/hermes/bin/grpcurl \
    -plaintext \
    -H "authorization: Bearer $token" \
    -import-path /data/companion \
    -proto emulator_controller.proto \
    -d "$1" \
    127.0.0.1:8554 \
    "$2"
}

smoke_stage=setup
mark_smoke_stage() {
  smoke_stage=$1
  printf 'Android smoke stage: %s\n' "$smoke_stage"
}

cleanup_smoke() {
  exit_code=$?
  trap - EXIT
  if [ "$exit_code" -ne 0 ]; then
    echo "::error::Android smoke failed during: $smoke_stage"
    if docker inspect hermes-android-smoke >/dev/null 2>&1; then
      for status_file in launcher accessibility; do
        printf 'Android %s status: ' "$status_file"
        docker exec hermes-android-smoke cat \
          "/data/status/$status_file.json" 2>/dev/null | jq -c . || echo unavailable
      done
      printf 'Android boot properties: '
      # shellcheck disable=SC2016 # Expanded by the Android guest shell.
      adb_cmd shell 'printf "boot=%s sdk=%s release=%s abi=%s\\n" \
        "$(getprop sys.boot_completed)" \
        "$(getprop ro.build.version.sdk)" \
        "$(getprop ro.build.version.release)" \
        "$(getprop ro.product.cpu.abilist)"' 2>/dev/null || echo unavailable
      for package in \
        com.android.vending \
        com.google.android.gms \
        com.hermes.agent.accessibility \
        com.aurora.store; do
        printf 'Android package %s: ' "$package"
        package_path=$(adb_cmd shell pm path "$package" 2>/dev/null | head -1 || true)
        printf '%s\n' "${package_path:-missing}"
      done
    fi
  fi
  docker rm --force hermes-android-smoke >/dev/null 2>&1 || true
  exit "$exit_code"
}

trap cleanup_smoke EXIT
mark_smoke_stage 'initial emulator boot'
start_emulator
wait_for_boot
mark_smoke_stage 'initial launcher status'
assert_running_launcher
mark_smoke_stage 'initial accessibility readiness'
wait_for_accessibility
mark_smoke_stage 'Android SDK property'
test "$(adb_cmd shell getprop ro.build.version.sdk | tr -d '\r')" = 37
mark_smoke_stage 'Android release property'
test "$(adb_cmd shell getprop ro.build.version.release | tr -d '\r')" = 17
mark_smoke_stage 'ARM64 translation ABI'
adb_cmd shell getprop ro.product.cpu.abilist | tr -d '\r' |
  grep --quiet 'arm64-v8a'
mark_smoke_stage 'Play Store package'
adb_cmd shell pm path com.android.vending | grep --quiet '^package:'
mark_smoke_stage 'Google Play services package'
adb_cmd shell pm path com.google.android.gms | grep --quiet '^package:'
mark_smoke_stage 'accessibility companion package'
adb_cmd shell pm path com.hermes.agent.accessibility | grep --quiet '^package:'
mark_smoke_stage 'enabled accessibility service'
enabled_accessibility_services=$(adb_cmd shell settings get secure \
  enabled_accessibility_services | tr -d '\r')
case ":$enabled_accessibility_services:" in
*":com.hermes.agent.accessibility/.HermesAccessibilityService:"*) ;;
*)
  echo "Hermes accessibility service is not enabled" >&2
  exit 1
  ;;
esac
mark_smoke_stage 'authenticated accessibility health'
accessibility_request '{"op":"health"}' | jq -e '.ok and .connected'
mark_smoke_stage 'accessibility authentication rejection'
accessibility_raw_request '{"op":"health","token":"wrong"}' |
  jq -e '(.ok | not) and (.error | contains("invalid companion token"))'
mark_smoke_stage 'initial accessibility snapshot'
initial_snapshot_ready=false
initial_snapshot=
for attempt in $(seq 1 30); do
  initial_snapshot=$(accessibility_request '{"op":"snapshot","ttl_ms":30000}')
  if printf '%s\n' "$initial_snapshot" | jq -e \
    '.ok and .backend == "accessibility-service" and (.node_count > 0)' \
    >/dev/null; then
    initial_snapshot_ready=true
    break
  fi
  sleep 1
done
if [ "$initial_snapshot_ready" != true ]; then
  printf 'Initial accessibility snapshot: %s\n' \
    "$(printf '%s\n' "$initial_snapshot" | jq -c \
      '{ok,backend,node_count,error}')" >&2
  exit 1
fi
mark_smoke_stage 'Settings UI launch'
adb_cmd shell am start -a android.settings.SETTINGS >/dev/null
sleep 2
mark_smoke_stage 'Settings UI search control discovery'
mark_smoke_stage 'Settings UI search control click'
click_response=
# A freshly booted Settings keeps laying itself out for a while on a slow
# runner, and the companion refuses to act on a node that moved since the
# snapshot. Allow as long as the first snapshot gets.
for attempt in $(seq 1 30); do
  settings_tree=$(accessibility_request '{"op":"snapshot","ttl_ms":30000}')
  settings_tree_id=$(printf '%s\n' "$settings_tree" | jq -r '.tree_id')
  settings_search_ref=$(printf '%s\n' "$settings_tree" | jq -r \
    '.nodes[] | select(.view_id == "com.android.settings:id/search_action_bar" and .clickable) | .ref' |
    head -1)
  if [ -n "$settings_search_ref" ]; then
    click_request=$(jq -cn \
      --arg tree_id "$settings_tree_id" \
      --arg ref "$settings_search_ref" \
      '{op:"action",tree_id:$tree_id,ref:$ref,action:"click",verify_timeout_ms:3000}')
    click_response=$(accessibility_request "$click_request")
    if printf '%s\n' "$click_response" | jq -e \
      '.ok and .accepted' >/dev/null; then
      break
    fi
  fi
  sleep 1
done
if ! printf '%s\n' "$click_response" | jq -e \
  '.ok and .accepted' >/dev/null; then
  printf 'Settings search click response: %s\n' \
    "$(printf '%s\n' "$click_response" | jq -c .)" >&2
  exit 1
fi
sleep 1
mark_smoke_stage 'Settings UI editor discovery'
mark_smoke_stage 'Unicode accessibility text entry'
text_response=
for attempt in $(seq 1 30); do
  search_tree=$(accessibility_request '{"op":"snapshot","ttl_ms":30000}')
  search_tree_id=$(printf '%s\n' "$search_tree" | jq -r '.tree_id')
  search_edit_ref=$(printf '%s\n' "$search_tree" | jq -r \
    '.nodes[] | select(.editable) | .ref' | head -1)
  if [ -n "$search_edit_ref" ]; then
    text_request=$(jq -cn \
      --arg tree_id "$search_tree_id" \
      --arg ref "$search_edit_ref" \
      --arg value 'Grüße ☕' \
      '{op:"action",tree_id:$tree_id,ref:$ref,action:"set_text",value:$value,verify_timeout_ms:3000}')
    text_response=$(accessibility_request "$text_request")
    if printf '%s\n' "$text_response" | jq -e \
      '.ok and .accepted' >/dev/null; then
      break
    fi
  fi
  sleep 1
done
if ! printf '%s\n' "$text_response" | jq -e \
  '.ok and .accepted' >/dev/null; then
  printf 'Unicode text entry response: %s\n' \
    "$(printf '%s\n' "$text_response" | jq -c .)" >&2
  exit 1
fi
mark_smoke_stage 'Unicode accessibility text verification'
unicode_text_visible=false
for attempt in $(seq 1 10); do
  if accessibility_request '{"op":"snapshot","ttl_ms":30000}' |
    jq -e '.nodes | any(.text == "Grüße ☕")' >/dev/null; then
    unicode_text_visible=true
    break
  fi
  sleep 1
done
test "$unicode_text_visible" = true
mark_smoke_stage 'accessibility gesture injection'
accessibility_request '{"op":"gesture","type":"tap","x":100,"y":100,"duration_ms":1}' |
  jq -e '.ok and .accepted'
mark_smoke_stage 'stale accessibility reference rejection'
accessibility_request '{"op":"action","tree_id":"stale","ref":"r0","action":"click"}' |
  jq -e '(.ok | not) and (.error | contains("stale tree_id"))'
mark_smoke_stage 'emulator gRPC token publication'
test -s "$smoke_root/data/companion/emulator-grpc-token"
mark_smoke_stage 'unauthenticated emulator gRPC rejection'
if docker exec hermes-android-smoke /opt/hermes/bin/grpcurl \
  -plaintext \
  -import-path /data/companion \
  -proto emulator_controller.proto \
  -d '{}' \
  127.0.0.1:8554 \
  android.emulation.control.EmulatorController/getVmState; then
  echo "emulator gRPC unexpectedly accepted an unauthenticated request" >&2
  exit 1
fi
mark_smoke_stage 'authenticated emulator gRPC state'
grpc_request '{}' \
  android.emulation.control.EmulatorController/getVmState |
  jq -e '.state == "RUNNING"'
mark_smoke_stage 'emulator gRPC clipboard write'
grpc_request '{"text":"Grüße ☕"}' \
  android.emulation.control.EmulatorController/setClipboard >/dev/null
mark_smoke_stage 'emulator gRPC clipboard read'
grpc_request '{}' \
  android.emulation.control.EmulatorController/getClipboard |
  jq -e '.text == "Grüße ☕"'
mark_smoke_stage 'Aurora Store installation'
adb_cmd install -r -g "/data/apks/AuroraStore-$AURORA_STORE_VERSION.apk"
mark_smoke_stage 'Aurora Store package verification'
adb_cmd shell pm path com.aurora.store | grep --quiet '^package:'
mark_smoke_stage 'Aurora Store launch and screenshot'
adb_cmd shell monkey -p com.aurora.store \
  -c android.intent.category.LAUNCHER 1 >/dev/null
adb_cmd shell screencap -p /sdcard/aurora-smoke.png
adb_cmd pull /sdcard/aurora-smoke.png /data/aurora-smoke.png
test -s "$smoke_root/data/aurora-smoke.png"

mark_smoke_stage 'first graceful shutdown'
docker stop --timeout 70 hermes-android-smoke
test "$(jq -r '.state' "$smoke_root/data/status/launcher.json")" = stopped
mark_smoke_stage 'second emulator boot'
start_emulator
wait_for_boot
mark_smoke_stage 'second boot readiness'
assert_running_launcher
wait_for_accessibility
mark_smoke_stage 'second boot package persistence'
adb_cmd shell pm path com.aurora.store | grep --quiet '^package:'
adb_cmd shell pm path com.android.vending | grep --quiet '^package:'
adb_cmd shell pm path com.google.android.gms | grep --quiet '^package:'
adb_cmd shell pm path com.hermes.agent.accessibility | grep --quiet '^package:'
mark_smoke_stage 'second graceful shutdown'
docker stop --timeout 70 hermes-android-smoke

mark_smoke_stage 'third emulator boot'
start_emulator
wait_for_boot
mark_smoke_stage 'third boot readiness'
assert_running_launcher
wait_for_accessibility
mark_smoke_stage 'third boot health and persistence'
adb_cmd shell pm path com.aurora.store | grep --quiet '^package:'
accessibility_request '{"op":"health"}' | jq -e '.ok and .connected'
mark_smoke_stage 'final graceful shutdown'
docker stop --timeout 70 hermes-android-smoke
trap - EXIT
