# Minimal Slack CLI for humans and coding agents.
# Auth: SLACK_TOKEN env var, or token file at ~/.config/slack-cli/token (xoxp user token).

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/slack-cli"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/slack-cli"
CACHE_TTL_SECONDS=86400
mkdir -p "$CACHE_DIR"

usage() {
  cat <<'EOF'
slack - Slack from the command line

Usage:
  slack search <query> [--count N]         Search messages (supports in:#chan from:@user before:/after: operators)
  slack history <#chan|@user|ID> [--since 2d|2026-08-01] [--limit N]
  slack thread <permalink | channel ts>    Read a full thread
  slack unreads                            Unread messages in channels/DMs you are a member of
  slack send <#chan|@user|ID> <text> [--thread <ts>]
  slack react <permalink | channel ts> <emoji-name>
  slack whois <@user|name|ID>              Look up a user
  slack channels [--refresh]               List channels (cached; --refresh to refetch)
  slack file <url_private> [outfile]       Download a file attachment

Output: one message per line as "[ts] author: text  <permalink>".
All commands honor SLACK_TOKEN; otherwise read ~/.config/slack-cli/token.
EOF
  exit "${1:-0}"
}

die() {
  echo "error: $*" >&2
  exit 1
}

get_token() {
  if [ -n "${SLACK_TOKEN:-}" ]; then
    printf '%s' "$SLACK_TOKEN"
  elif [ -f "$CONFIG_DIR/token" ]; then
    tr -d '[:space:]' <"$CONFIG_DIR/token"
  else
    die "no token: set SLACK_TOKEN or write an xoxp user token to $CONFIG_DIR/token"
  fi
}

TOKEN=""

# api <method> [curl-args...]; prints response body, dies on Slack-level error
api() {
  local method="$1" response
  shift
  [ -n "$TOKEN" ] || TOKEN="$(get_token)"
  response="$(curl -sS --max-time 30 -H "Authorization: Bearer $TOKEN" "$@" "https://slack.com/api/$method")" ||
    die "network failure calling $method"
  if [ "$(jq -r '.ok' <<<"$response")" != "true" ]; then
    die "$method failed: $(jq -r '.error // "unknown"' <<<"$response")"
  fi
  printf '%s' "$response"
}

cache_fresh() {
  local file="$1" now mtime
  [ -f "$file" ] || return 1
  now="$(date +%s)"
  mtime="$(stat -c %Y "$file")"
  [ $((now - mtime)) -lt "$CACHE_TTL_SECONDS" ]
}

team_url() {
  local file="$CACHE_DIR/team_url"
  if ! cache_fresh "$file"; then
    api auth.test | jq -r '.url' | sed 's:/$::' >"$file"
  fi
  cat "$file"
}

refresh_users() {
  local cursor="" page all="[]"
  while :; do
    page="$(api users.list -G --data-urlencode "limit=999" --data-urlencode "cursor=$cursor")"
    all="$(jq -s '.[0] + .[1].members' <<<"$all$page")"
    cursor="$(jq -r '.response_metadata.next_cursor // ""' <<<"$page")"
    [ -n "$cursor" ] || break
  done
  jq 'map({key: .id, value: (.profile.display_name | select(. != "")) // .real_name // .name}) | from_entries' \
    <<<"$all" >"$CACHE_DIR/users.json"
}

refresh_channels() {
  local cursor="" page all="[]"
  while :; do
    page="$(api conversations.list -G \
      --data-urlencode "types=public_channel,private_channel,im,mpim" \
      --data-urlencode "exclude_archived=true" \
      --data-urlencode "limit=999" \
      --data-urlencode "cursor=$cursor")"
    all="$(jq -s '.[0] + .[1].channels' <<<"$all$page")"
    cursor="$(jq -r '.response_metadata.next_cursor // ""' <<<"$page")"
    [ -n "$cursor" ] || break
  done
  printf '%s' "$all" >"$CACHE_DIR/channels.json"
}

users_file() {
  cache_fresh "$CACHE_DIR/users.json" || refresh_users
  echo "$CACHE_DIR/users.json"
}

channels_file() {
  cache_fresh "$CACHE_DIR/channels.json" || refresh_channels
  echo "$CACHE_DIR/channels.json"
}

# resolve_user <@name|name|Uxxx> -> user id
resolve_user() {
  local query="${1#@}" id
  case "$query" in U*) printf '%s' "$query"; return ;; esac
  id="$(jq -r --arg n "$query" 'to_entries[] | select(.value == $n) | .key' "$(users_file)" | head -n1)"
  [ -n "$id" ] || die "unknown user: $1 (try: slack whois $1, or slack channels --refresh)"
  printf '%s' "$id"
}

# resolve_channel <#name|@user|Cxxx|Dxxx|Gxxx> -> channel id
resolve_channel() {
  local query="$1" id user
  case "$query" in
    C* | D* | G*) printf '%s' "$query"; return ;;
    "@"*)
      user="$(resolve_user "$query")"
      id="$(jq -r --arg u "$user" '.[] | select(.is_im == true and .user == $u) | .id' "$(channels_file)" | head -n1)"
      [ -n "$id" ] || die "no DM found with $query"
      printf '%s' "$id"
      return
      ;;
  esac
  query="${query#\#}"
  id="$(jq -r --arg n "$query" '.[] | select(.name == $n) | .id' "$(channels_file)" | head -n1)"
  [ -n "$id" ] || die "unknown channel: $1 (try: slack channels --refresh)"
  printf '%s' "$id"
}

# parse_since <2d|5h|30m|YYYY-MM-DD> -> unix timestamp
parse_since() {
  local spec="$1" now amount
  now="$(date +%s)"
  case "$spec" in
    *d) amount=$((${spec%d} * 86400)) ;;
    *h) amount=$((${spec%h} * 3600)) ;;
    *m) amount=$((${spec%m} * 60)) ;;
    *)
      date -d "$spec" +%s 2>/dev/null ||
        die "bad --since value: $spec (use 2d, 5h, 30m, or YYYY-MM-DD)"
      return
      ;;
  esac
  echo $((now - amount))
}

# parse_message_ref <permalink> | <channel> <ts>; sets REF_CHANNEL and REF_TS
parse_message_ref() {
  if [[ "$1" == *"/archives/"* ]]; then
    REF_CHANNEL="$(sed -E 's|.*/archives/([^/]+)/p([0-9]{10})([0-9]+).*|\1|' <<<"$1")"
    REF_TS="$(sed -E 's|.*/archives/([^/]+)/p([0-9]{10})([0-9]+).*|\2.\3|' <<<"$1")"
    [[ "$REF_CHANNEL" != "$1" ]] || die "cannot parse permalink: $1"
  else
    [ $# -ge 2 ] || die "expected a permalink or: <channel> <ts>"
    REF_CHANNEL="$(resolve_channel "$1")"
    REF_TS="$2"
  fi
}

# render_messages <channel-id>; reads a JSON array of message objects on stdin
render_messages() {
  local channel="$1"
  jq -r --arg base "$(team_url)" --arg chan "$channel" --slurpfile users "$(users_file)" '
    ($users[0]) as $u
    | .[]
    | select(.type == "message" or .type == null)
    | (.ts | split(".") | "p" + join("")) as $p
    | (.text // ""
        | gsub("<@(?<id>U[A-Z0-9]+)(\\|[^>]*)?>"; "@" + ($u[.id] // .id))
        | gsub("<#[A-Z0-9]+\\|(?<n>[^>]+)>"; "#" + .n)
        | gsub("<(?<url>https?://[^|>]+)(\\|[^>]*)?>"; .url)
        | gsub("&gt;"; ">") | gsub("&lt;"; "<") | gsub("&amp;"; "&")
        | gsub("\n"; " ⏎ ")) as $text
    | (if .reply_count then "  [thread: \(.reply_count) replies]" else "" end) as $thread
    | "[\(.ts)] \($u[.user] // .username // .user // "?"): \($text)\($thread)  <\($base)/archives/\($chan)/\($p)>"
  '
}

cmd_search() {
  local query="" count=20
  while [ $# -gt 0 ]; do
    case "$1" in
      --count) count="$2"; shift 2 ;;
      *) query="$query $1"; shift ;;
    esac
  done
  query="${query# }"
  [ -n "$query" ] || usage 1
  api search.messages -G \
    --data-urlencode "query=$query" \
    --data-urlencode "count=$count" \
    --data-urlencode "sort=timestamp" |
    jq -r --slurpfile users "$(users_file)" '
      ($users[0]) as $u
      | (.messages.total | "-- \(.) total matches --"),
        (.messages.matches[]
         | "[\(.ts)] #\(.channel.name // .channel.id) \($u[.user] // .username // "?"): \(.text | gsub("\n"; " ⏎ "))  <\(.permalink)>")
    '
}

cmd_history() {
  local target="" oldest="" limit=50
  while [ $# -gt 0 ]; do
    case "$1" in
      --since) oldest="$(parse_since "$2")"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      *) target="$1"; shift ;;
    esac
  done
  [ -n "$target" ] || usage 1
  local channel
  channel="$(resolve_channel "$target")"
  local extra=()
  [ -n "$oldest" ] && extra=(--data-urlencode "oldest=$oldest")
  api conversations.history -G \
    --data-urlencode "channel=$channel" \
    --data-urlencode "limit=$limit" \
    "${extra[@]}" |
    jq '.messages | reverse' | render_messages "$channel"
}

cmd_thread() {
  parse_message_ref "$@"
  api conversations.replies -G \
    --data-urlencode "channel=$REF_CHANNEL" \
    --data-urlencode "ts=$REF_TS" \
    --data-urlencode "limit=200" |
    jq '.messages' | render_messages "$REF_CHANNEL"
}

cmd_unreads() {
  local found=0 channel_id name last_read history
  while IFS=$'\t' read -r channel_id name; do
    last_read="$(api conversations.info -G --data-urlencode "channel=$channel_id" |
      jq -r '.channel.last_read // ""')"
    [ -n "$last_read" ] || continue
    history="$(api conversations.history -G \
      --data-urlencode "channel=$channel_id" \
      --data-urlencode "oldest=$last_read" \
      --data-urlencode "limit=50" | jq '.messages | reverse')"
    if [ "$(jq 'length' <<<"$history")" -gt 0 ]; then
      found=1
      echo "== $name =="
      render_messages "$channel_id" <<<"$history"
    fi
  done < <(jq -r --slurpfile users "$(users_file)" '
    ($users[0]) as $u
    | .[]
    | select(.is_member == true or .is_im == true)
    | [.id, (if .is_im then "@" + ($u[.user] // .user) else "#" + (.name // .id) end)]
    | @tsv' "$(channels_file)")
  [ "$found" -eq 1 ] || echo "No unread messages."
}

cmd_send() {
  local target="" text="" thread=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --thread) thread="$2"; shift 2 ;;
      *)
        if [ -z "$target" ]; then target="$1"; else text="$text $1"; fi
        shift
        ;;
    esac
  done
  text="${text# }"
  { [ -n "$target" ] && [ -n "$text" ]; } || usage 1
  local channel
  channel="$(resolve_channel "$target")"
  if [ -n "${SLACK_SEND_CHANNELS:-}" ]; then
    case ",$SLACK_SEND_CHANNELS," in
      *",$channel,"* | *",$target,"*) ;;
      *) die "sending to $target blocked: not in SLACK_SEND_CHANNELS allowlist" ;;
    esac
  fi
  local extra=()
  [ -n "$thread" ] && extra=(--data-urlencode "thread_ts=$thread")
  api chat.postMessage \
    --data-urlencode "channel=$channel" \
    --data-urlencode "text=$text" \
    "${extra[@]}" |
    jq -r --arg base "$(team_url)" --arg chan "$channel" \
      '"sent  <\($base)/archives/\($chan)/p" + (.ts | split(".") | join("")) + ">"'
}

cmd_react() {
  local emoji="${*: -1}"
  set -- "${@:1:$(($# - 1))}"
  parse_message_ref "$@"
  api reactions.add \
    --data-urlencode "channel=$REF_CHANNEL" \
    --data-urlencode "timestamp=$REF_TS" \
    --data-urlencode "name=${emoji//:/}" >/dev/null
  echo "reacted :${emoji//:/}:"
}

cmd_whois() {
  local id
  id="$(resolve_user "$1")"
  api users.info -G --data-urlencode "user=$id" |
    jq -r '.user | "\(.id)  @\(.profile.display_name // .name)  \(.real_name // "")  \(.profile.title // "")  \(.profile.email // "")"'
}

cmd_channels() {
  [ "${1:-}" = "--refresh" ] && { refresh_channels; refresh_users; }
  jq -r --slurpfile users "$(users_file)" '
    ($users[0]) as $u
    | .[]
    | if .is_im then "\(.id)  @\($u[.user] // .user)  (dm)"
      elif .is_mpim then "\(.id)  \(.name)  (group dm)"
      else "\(.id)  #\(.name)\(if .is_private then "  (private)" else "" end)" end' \
    "$(channels_file)" | sort -k2
}

cmd_file() {
  local url="$1" out="${2:-}"
  [ -n "$TOKEN" ] || TOKEN="$(get_token)"
  [ -n "$out" ] || out="$(basename "${url%%\?*}")"
  curl -sS -L --max-time 120 -H "Authorization: Bearer $TOKEN" -o "$out" "$url" || die "download failed"
  echo "saved $out"
}

[ $# -ge 1 ] || usage 1
subcommand="$1"
shift
case "$subcommand" in
  search) cmd_search "$@" ;;
  history) cmd_history "$@" ;;
  thread) cmd_thread "$@" ;;
  unreads) cmd_unreads "$@" ;;
  send) cmd_send "$@" ;;
  react) cmd_react "$@" ;;
  whois) cmd_whois "$@" ;;
  channels) cmd_channels "$@" ;;
  file) cmd_file "$@" ;;
  help | --help | -h) usage 0 ;;
  *) die "unknown command: $subcommand (see: slack help)" ;;
esac
