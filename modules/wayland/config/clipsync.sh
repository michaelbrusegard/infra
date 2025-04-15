#!/usr/bin/env sh
#
# Two-way clipboard syncronization between Wayland and X11, with cliphy support!
# !! Recommended use: Drop this file off @ /usr/local/bin/clipsync && make it executable
# Requires: wl-clipboard, xclip, clipnotify.
# Modified from: https://github.com/hyprwm/Hyprland/issues/6132#issuecomment-2127153823
#
# Usage:
#   clipsync watch [with-notifications|without-notifications] - run in background.
#   clipsync stop - kill all background processes.
#   echo -n any | clipsync insert [with-notifications|without-notifications] - insert clipboard content from stdin.
#   clipsync help - display help information.
#
# Workaround for issue:
# "Clipboard synchronization between wayland and xwayland clients broken"
# https://github.com/hyprwm/Hyprland/issues/6132
#
# Also pertains to:
# https://github.com/hyprwm/Hyprland/issues/6247
# https://github.com/hyprwm/Hyprland/issues/6443
# https://github.com/hyprwm/Hyprland/issues/6148

# Updates clipboard content of both Wayland and X11 if current clipboard content differs.
# Usage: echo -e "1\n2" | clipsync insert [with-notifications|without-notifications]
get_mime_type() {
  wl-paste --list-types | head -n 1
}

insert() {
  mime_type=$(get_mime_type)
  case "$mime_type" in
  text/*)
    value=$(wl-paste -n | tr -d '\0')
    insert_text "$value" "$1"
    ;;
  image/*)
    insert_image "$1"
    ;;
  *)
    insert_file "$1"
    ;;
  esac
}

insert_text() {
  value="$1"
  notification_mode="$2"
  wValue=$(wl-paste -n 2>/dev/null | tr -d '\0' || printf "")
  xValue=$(xclip -o -selection clipboard 2>/dev/null | tr -d '\0' || printf "")

  notify() {
    if [ "$notification_mode" != "without-notifications" ]; then
      truncated_value=$(printf "%.50s" "$value")
      notify-send -u low -c clipboard "Text copied" "$truncated_value"
    fi
  }

  update_clipboard() {
    if [ "$value" != "$1" ]; then
      notify
      printf "%s" "$value" | $2
      command -v cliphist >/dev/null 2>&1 && printf "%s" "$value" | cliphist store
    fi
  }

  update_clipboard "$wValue" "wl-copy"
  update_clipboard "$xValue" "xclip -selection clipboard"
}

insert_image() {
  notification_mode="$1"
  tmp_file=$(mktemp)
  wl-paste >"$tmp_file"

  [ "$notification_mode" != "without-notifications" ] && notify-send -u low -c clipboard "Image copied" "Image data copied to clipboard"

  wl-copy <"$tmp_file"
  xclip -selection clipboard -t "$(get_mime_type)" <"$tmp_file"
  command -v cliphist >/dev/null 2>&1 && wl-copy <"$tmp_file" | cliphist store

  rm "$tmp_file"
}

insert_file() {
  notification_mode="$1"
  tmp_file=$(mktemp)
  wl-paste >"$tmp_file"

  [ "$notification_mode" != "without-notifications" ] && notify-send -u low -c clipboard "File copied" "File data copied to clipboard"

  wl-copy <"$tmp_file"
  xclip -selection clipboard -t "$(get_mime_type)" <"$tmp_file"
  command -v cliphist >/dev/null 2>&1 && wl-copy <"$tmp_file" | cliphist store

  rm "$tmp_file"
}

# Watch for clipboard changes and synchronize between Wayland and X11
# Usage: clipsync watch [with-notifications|without-notifications]
watch() {
  sleep 1
  notification_mode=${1:-with-notifications}

  watch_clipboard() {
    $1 | while read -r _; do
      clipsync insert "$notification_mode"
    done &
  }

  watch_clipboard "wl-paste --watch printf ''"
  watch_clipboard "wl-paste --primary --watch printf ''"
  watch_clipboard "clipnotify"
  watch_clipboard "clipnotify -s PRIMARY"

  wait
}

# Kill all background processes related to clipsync
stop_clipsync() {
  pkill -f "wl-paste --type text --watch"
  pkill clipnotify
  pkill -f "xclip -selection clipboard"
  pkill -f "clipsync insert"
}

help() {
  cat <<EOF
clipsync - Two-way clipboard synchronization between Wayland and X11, with cliphist support

Usage:
  clipsync watch [with-notifications|without-notifications]
    Run clipboard synchronization in the background.
    Options:
      with-notifications (default): Show desktop notifications for clipboard changes.
      without-notifications: Operate silently without notifications.

  clipsync stop
    Stop all background processes related to clipsync.

  echo -n "text" | clipsync insert [with-notifications|without-notifications]
    Insert clipboard content from stdin.
    Notification options work the same as in the watch command.

  clipsync help
    Display this help information.

Requirements: wl-clipboard, xclip, clipnotify
Optional: cliphist (for Hyprland users)
EOF
}

case "$1" in
watch)
  watch "$2"
  ;;
stop)
  stop_clipsync
  ;;
insert)
  insert "$2"
  ;;
help)
  help
  ;;
*)
  echo "Usage: $0 {watch [with-notifications|without-notifications]|stop|insert [with-notifications|without-notifications]|help}"
  echo "Run '$0 help' for more information."
  exit 1
  ;;
esac
