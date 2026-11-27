#!/bin/sh
set -eu

ROOTFS=/opt/android-image/rootfs
APKS=/opt/android-image/apks
STATE=${ANDROID_STATE_DIR:-/opt/android}
DATA=$STATE/data
BUNDLE=/run/android/bundle
NETNS=android
CONTAINER=android
HOST_ADDRESS=10.231.0.1
GUEST_ADDRESS=10.231.0.2
SERIAL=127.0.0.1:5555
STATUS_FILE=$STATE/status/launcher.json
ACCESSIBILITY_STATUS_FILE=$STATE/status/accessibility.json
ACCESSIBILITY_PACKAGE=com.hermes.agent.accessibility
ACCESSIBILITY_SERVICE=$ACCESSIBILITY_PACKAGE/.HermesAccessibilityService
VNC_PACKAGE=net.christianbeier.droidvnc_ng
TOKEN_FILE=$STATE/companion/auth-token

write_status() {
  printf '{"state":"%s","updated_at":"%s","release":"%s"}\n' \
    "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(cat /opt/android-image/release)" >"$STATUS_FILE.tmp"
  mv "$STATUS_FILE.tmp" "$STATUS_FILE"
}

write_accessibility_status() {
  printf '{"state":"%s","detail":"%s","updated_at":"%s"}\n' \
    "$1" "$2" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$ACCESSIBILITY_STATUS_FILE.tmp"
  mv "$ACCESSIBILITY_STATUS_FILE.tmp" "$ACCESSIBILITY_STATUS_FILE"
}

device_shell() {
  adb -s $SERIAL shell "$@"
}

booted() {
  adb connect $SERIAL >/dev/null 2>&1 || true
  [ "$(device_shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]
}

configure_device() {
  device_shell settings put system system_locales en-US
  device_shell settings put system time_12_24 24
  device_shell cmd alarm set-timezone "${ANDROID_TIMEZONE:-America/Los_Angeles}"
  device_shell settings put global device_name "'Pixel 8'"
}

enable_accessibility_service() {
  enabled=$(device_shell settings get secure enabled_accessibility_services 2>/dev/null | tr -d '\r')
  case ":$enabled:" in
  *":$1:"*) return ;;
  ":null:" | "::") enabled=$1 ;;
  *) enabled="$enabled:$1" ;;
  esac
  device_shell settings put secure enabled_accessibility_services "$enabled"
  device_shell settings put secure accessibility_enabled 1
}

# Android has no video encoder on these nodes, so the viewer cannot use a
# stream; this app serves the screen as VNC from a screen capture instead.
enable_viewer() {
  if device_shell "netstat -tln" 2>/dev/null | grep -q ':5900 '; then
    return 0
  fi
  token=$(tr -d '\r\n' <"$TOKEN_FILE")
  if ! device_shell pm path $VNC_PACKAGE >/dev/null 2>&1; then
    adb -s $SERIAL install -r -g "$APKS/droidvnc-ng.apk" >/dev/null || return 1
  fi
  files=/sdcard/Android/data/$VNC_PACKAGE/files
  if ! device_shell ls $files/defaults.json >/dev/null 2>&1; then
    printf '{"accessKey":"%s","port":5900,"password":"","scaling":0.5,"startOnBoot":false}\n' "$token" \
      >/run/android/vnc-defaults.json
    device_shell mkdir -p $files
    adb -s $SERIAL push /run/android/vnc-defaults.json $files/defaults.json >/dev/null
  fi
  device_shell cmd appops set $VNC_PACKAGE PROJECT_MEDIA allow
  enable_accessibility_service $VNC_PACKAGE/.InputService
  device_shell am start-foreground-service -n $VNC_PACKAGE/.MainService \
    -a $VNC_PACKAGE.ACTION_START --es $VNC_PACKAGE.EXTRA_ACCESS_KEY "$token" \
    --ei $VNC_PACKAGE.EXTRA_PORT 5900 --ef $VNC_PACKAGE.EXTRA_SCALING 0.5 --ez $VNC_PACKAGE.EXTRA_VIEW_ONLY false >/dev/null
}

enable_companion() {
  apk=$(find "$APKS" -maxdepth 1 -name 'HermesAccessibility-*.apk' | head -1)
  version=${apk##*/HermesAccessibility-}
  version=${version%.apk}
  installed=$(device_shell dumpsys package $ACCESSIBILITY_PACKAGE 2>/dev/null |
    sed -n 's/^ *versionName=//p' | head -1 | tr -d '\r')
  if [ "$installed" != "$version" ]; then
    adb -s $SERIAL install -r -g "$apk" >/dev/null || {
      write_accessibility_status degraded install-failed
      return 1
    }
  fi
  adb -s $SERIAL push "$APKS/hermes-clipboard.jar" /data/local/tmp/hermes-clipboard.jar >/dev/null

  enable_accessibility_service $ACCESSIBILITY_SERVICE

  if [ ! -s "$TOKEN_FILE" ]; then
    write_accessibility_status degraded missing-auth-token
    return 1
  fi
  token=$(tr -d '\r\n' <"$TOKEN_FILE")
  device_shell am broadcast --receiver-foreground \
    -a $ACCESSIBILITY_PACKAGE.CONFIGURE -n $ACCESSIBILITY_PACKAGE/.ConfigReceiver \
    --es token "$token" >/dev/null

  tries=0
  while [ $tries -lt 30 ]; do
    if printf '{"op":"health","token":"%s"}\n' "$token" |
      device_shell nc -w 2 127.0.0.1 8765 2>/dev/null | grep -q '"ok":true'; then
      write_accessibility_status ready connected
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  write_accessibility_status degraded socket-unavailable
  return 1
}

supervise() {
  until booted; do
    sleep 2
  done
  write_status running
  configure_device || true
  while :; do
    enable_companion || true
    enable_viewer || true
    sleep 30
  done
}

# shellcheck disable=SC2329 # Invoked indirectly by the EXIT trap.
stop_android() {
  set +e
  write_status stopping
  [ -z "${supervisor:-}" ] || kill "$supervisor" 2>/dev/null
  timeout 10 adb -s "$SERIAL" shell reboot -p >/dev/null 2>&1
  tries=0
  while crun state "$CONTAINER" >/dev/null 2>&1 && [ "$tries" -lt 20 ]; do
    tries=$((tries + 1))
    sleep 1
  done
  crun delete -f "$CONTAINER" 2>/dev/null
  write_status stopped
}

mkdir -p "$DATA" "$BUNDLE" "$STATE/status" /root/.android
# The volume's root carries the pod's group and the set-group-ID bit, which
# everything Android creates under /data would otherwise inherit.
chown 1000:1000 "$DATA"
chmod 0771 "$DATA"
rm -rf "$STATE/android-home" "$STATE/android-home-migrations"
write_status starting
write_accessibility_status starting waiting-for-boot

cp "$STATE/adb/adbkey" "$STATE/adb/adbkey.pub" /root/.android/
chmod 0600 /root/.android/adbkey
mkdir -p "$DATA/misc/adb"
cp "$STATE/adb/adbkey.pub" "$DATA/misc/adb/adb_keys"
chown 1000:2000 "$DATA/misc/adb" "$DATA/misc/adb/adb_keys"
chmod 2750 "$DATA/misc/adb"
chmod 0640 "$DATA/misc/adb/adb_keys"

# A node has no battery, and Android powers off at boot when it reads an empty
# one that is not charging, so its battery service is shown a full one on mains.
power=/run/android/power_supply
mkdir -p $power/ac $power/battery
supply() {
  printf '%s\n' "$3" >"$power/$1/$2"
}
supply ac type Mains
supply ac online 1
supply battery type Battery
supply battery present 1
supply battery status Full
supply battery health Good
supply battery capacity 100
supply battery capacity_level Full
supply battery technology Li-ion
supply battery voltage_now 4400000
supply battery current_now 0
supply battery charge_counter 4500000
supply battery charge_full 4500000
supply battery temp 250
supply battery cycle_count 1

crun delete -f $CONTAINER 2>/dev/null || true
ip netns delete $NETNS 2>/dev/null || true
ip link delete android0 2>/dev/null || true
ip netns add $NETNS
ip link add android0 type veth peer name eth0 netns $NETNS
ip addr add $HOST_ADDRESS/30 dev android0
ip link set android0 up
ip -n $NETNS link set lo up
ip -n $NETNS link set eth0 up
ip -n $NETNS addr add $GUEST_ADDRESS/30 dev eth0
ip -n $NETNS route add default via $HOST_ADDRESS dev eth0 onlink
sysctl -qw net.ipv4.ip_forward=1
iptables -t nat -C POSTROUTING -s $GUEST_ADDRESS -j MASQUERADE 2>/dev/null ||
  iptables -t nat -A POSTROUTING -s $GUEST_ADDRESS -j MASQUERADE
resolver=$(awk '$1 == "nameserver" && $2 !~ /:/ { print $2; exit }' /etc/resolv.conf)

device() {
  if [ $# = 1 ]; then
    set -- "$1" "$(($(stat -c '0x%t' "$1")))" "$(($(stat -c '0x%T' "$1")))"
  fi
  owner='"uid":0,"gid":0'
  case $1 in
  /dev/null | /dev/zero | /dev/full | /dev/random | /dev/urandom | /dev/tty) mode=438 ;;
  /dev/tun)
    mode=432
    owner='"uid":1000,"gid":1016'
    ;;
  *) mode=384 ;;
  esac
  printf '{"path":"%s","type":"c","major":%s,"minor":%s,"fileMode":%s,%s}' "$1" "$2" "$3" "$mode" "$owner"
}
devices="$(device /dev/null 1 3),$(device /dev/zero 1 5),$(device /dev/full 1 7),$(device /dev/random 1 8),$(device /dev/urandom 1 9),$(device /dev/tty 5 0),$(device /dev/kmsg 1 11),$(device /dev/fuse 10 229),$(device /dev/tun 10 200),$(device /dev/loop-control 10 237)"
codecs=0
if [ -c /dev/dma_heap/system ]; then
  devices="$devices,$(device /dev/dma_heap/system)"
  codecs=1
fi
i=0
while [ "$i" -lt 64 ]; do
  [ -b "/dev/loop$i" ] || mknod -m 660 "/dev/loop$i" b 7 "$i"
  devices="$devices,{\"path\":\"/dev/block/loop$i\",\"type\":\"b\",\"major\":7,\"minor\":$i,\"fileMode\":432,\"uid\":0,\"gid\":0}"
  i=$((i + 1))
done
capabilities='"CAP_CHOWN","CAP_DAC_OVERRIDE","CAP_DAC_READ_SEARCH","CAP_FOWNER","CAP_FSETID","CAP_KILL","CAP_SETGID","CAP_SETUID","CAP_SETPCAP","CAP_LINUX_IMMUTABLE","CAP_NET_BIND_SERVICE","CAP_NET_BROADCAST","CAP_NET_ADMIN","CAP_NET_RAW","CAP_IPC_LOCK","CAP_IPC_OWNER","CAP_SYS_MODULE","CAP_SYS_RAWIO","CAP_SYS_CHROOT","CAP_SYS_PTRACE","CAP_SYS_PACCT","CAP_SYS_ADMIN","CAP_SYS_BOOT","CAP_SYS_NICE","CAP_SYS_RESOURCE","CAP_SYS_TIME","CAP_SYS_TTY_CONFIG","CAP_MKNOD","CAP_LEASE","CAP_AUDIT_WRITE","CAP_AUDIT_CONTROL","CAP_SETFCAP","CAP_MAC_OVERRIDE","CAP_MAC_ADMIN","CAP_SYSLOG","CAP_WAKE_ALARM","CAP_BLOCK_SUSPEND","CAP_AUDIT_READ","CAP_PERFMON","CAP_BPF","CAP_CHECKPOINT_RESTORE"'
arguments='"/init","qemu=1","androidboot.hardware=redroid","androidboot.redroid_gpu_mode=guest","androidboot.use_memfd=true"'
arguments="$arguments,\"androidboot.redroid_width=${ANDROID_WIDTH:-1080}\",\"androidboot.redroid_height=${ANDROID_HEIGHT:-1920}\",\"androidboot.redroid_dpi=${ANDROID_DPI:-420}\",\"androidboot.redroid_fps=${ANDROID_FPS:-30}\""
arguments="$arguments,\"androidboot.use_redroid_c2=$codecs\""
arguments="$arguments,\"androidboot.redroid_net_ndns=1\",\"androidboot.redroid_net_dns1=$HOST_ADDRESS\""
arguments="$arguments,\"ro.adb.secure=1\",\"ro.debuggable=0\",\"ro.secure=1\",\"ro.build.tags=release-keys\""
arguments="$arguments,\"ro.dalvik.vm.native.bridge=libnb.so\",\"ro.dalvik.vm.isa.arm64=x86_64\""

cat >"$BUNDLE/config.json" <<JSON
{
  "ociVersion": "1.0.2",
  "process": {
    "terminal": false,
    "user": {"uid": 0, "gid": 0},
    "args": [$arguments],
    "env": ["PATH=/system/bin:/system/xbin:/vendor/bin", "HOME=/"],
    "cwd": "/",
    "capabilities": {"bounding": [$capabilities], "effective": [$capabilities], "permitted": [$capabilities], "inheritable": [$capabilities], "ambient": [$capabilities]},
    "noNewPrivileges": false
  },
  "root": {"path": "$ROOTFS", "readonly": false},
  "hostname": "localhost",
  "mounts": [
    {"destination": "/proc", "type": "proc", "source": "proc"},
    {"destination": "/dev", "type": "tmpfs", "source": "tmpfs", "options": ["nosuid", "strictatime", "mode=755", "size=65536k"]},
    {"destination": "/dev/pts", "type": "devpts", "source": "devpts", "options": ["nosuid", "noexec", "newinstance", "ptmxmode=0666", "mode=0620"]},
    {"destination": "/dev/shm", "type": "tmpfs", "source": "shm", "options": ["nosuid", "noexec", "nodev", "mode=1777", "size=65536k"]},
    {"destination": "/dev/mqueue", "type": "mqueue", "source": "mqueue", "options": ["nosuid", "noexec", "nodev"]},
    {"destination": "/sys", "type": "sysfs", "source": "sysfs", "options": ["nosuid", "noexec", "nodev", "rw"]},
    {"destination": "/sys/fs/cgroup", "type": "cgroup", "source": "cgroup", "options": ["rw"]},
    {"destination": "/sys/class/power_supply", "type": "bind", "source": "$power", "options": ["rbind", "ro"]},
    {"destination": "/data", "type": "bind", "source": "$DATA", "options": ["rbind", "rw"]}
  ],
  "linux": {
    "resources": {"devices": [{"allow": true, "access": "rwm"}]},
    "devices": [$devices],
    "namespaces": [
      {"type": "pid"}, {"type": "ipc"}, {"type": "uts"}, {"type": "mount"}, {"type": "cgroup"},
      {"type": "network", "path": "/run/netns/$NETNS"}
    ],
    "rootfsPropagation": "rprivate"
  }
}
JSON

adb start-server >/dev/null 2>&1
socat tcp-listen:5555,reuseaddr,fork tcp:$GUEST_ADDRESS:5555 &
socat tcp-listen:5900,bind=127.0.0.1,reuseaddr,fork tcp:$GUEST_ADDRESS:5900 &
# The pod's resolver can be a loopback address, which Android's own network
# cannot reach, and the nodes load no kernel module that could redirect to it.
socat udp4-recvfrom:53,bind=$HOST_ADDRESS,reuseaddr,fork udp4-sendto:"$resolver":53 &
socat tcp4-listen:53,bind=$HOST_ADDRESS,reuseaddr,fork tcp4:"$resolver":53 &
trap stop_android EXIT
trap 'exit 143' TERM INT

# netd attaches its traffic programs to the root of Android's cgroup tree,
# which the kernel refuses on a cgroup that already carries the container's
# own. A privileged container sees the node's whole tree, so the child is made
# under this container's group to stay inside the pod's limits.
cgroup=/sys/fs/cgroup$(sed -n 's/^0:://p' /proc/self/cgroup)
cgroup=${cgroup%/}/android
mkdir -p "$cgroup"
(
  echo 0 >"$cgroup/cgroup.procs"
  exec crun --cgroup-manager=disabled run --bundle "$BUNDLE" $CONTAINER
) &
android=$!
supervise &
supervisor=$!
status=0
wait $android || status=$?
write_status exited
exit $status
