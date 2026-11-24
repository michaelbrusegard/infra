#!/usr/bin/env bash
# Runs the LLM conversation normalizer next to ClickHouse, as the cluster's
# llm-normalizer CronJob does. It runs in the
# ClickHouse server image, for clickhouse-client, with this directory copied
# from the plugin image.
#
#   normalize.sh cron      one run of the job: the requests that are not
#                          normalized yet, an hour at a time from the
#                          oldest, starting none after BUDGET seconds (300)
#   normalize.sh verify    only the checks
#
# CLICKHOUSE_HOST and CLICKHOUSE_USER name the server and its user, whose
# password clickhouse-client reads from CLICKHOUSE_PASSWORD, and SCRATCH a
# directory for the rows to insert.
set -euo pipefail

here=$(dirname "$(readlink -f "$0")")
normalizer=$here/normalize-conversations
scratch=${SCRATCH:-/scratch}

ch() {
  clickhouse-client --host "${CLICKHOUSE_HOST:-clickhouse}" --user "${CLICKHOUSE_USER:-llm_normalizer}" "$@"
}

# Inserts the rows of a normalizer run. Each table is one insert, and the
# rows are deterministic, so a run interrupted and run again collapses.
insert() {
  local table
  for table in llm.request_items llm.sessions llm.messages llm.calls; do
    if [[ -s $1/$table.jsonl ]]; then
      ch --query "INSERT INTO $table FORMAT JSONEachRow" <"$1/$table.jsonl"
    fi
  done
}

# One run over the requests that started from $1 until $2 and are not in
# llm.calls yet, with the state of the sessions they touch.
proxy() {
  local out=$scratch/proxy sessions
  rm -rf "$out"
  mkdir -p "$out"
  ch --param_after="$1" --param_before="$2" --queries-file "$here/requests.sql" </dev/null >"$scratch/requests.jsonl"
  sessions=$("$normalizer" -requests -sessions <"$scratch/requests.jsonl")
  ch --param_sessions="$sessions" --queries-file "$here/state.sql" </dev/null >"$scratch/state.jsonl"
  "$normalizer" -requests -state "$scratch/state.jsonl" -out "$out" <"$scratch/requests.jsonl"
  insert "$out"
  echo "proxy $1 to $2: $(wc -l <"$out/llm.calls.jsonl") calls"
}

# The requests that are not normalized yet, in start order and $1 hours at
# a time from the oldest window with any, which bounds the items the server
# joins and the normalizer keeps at once: a busy day holds 840 MiB of them,
# and an hour 140 MiB. Each window's rows are inserted before the next
# window reads its state. The current window reaches into the future, and
# its recent requests are held back for the next run. With a budget of $2
# seconds, no window starts once it is spent, and the next run goes on from
# the first window left; every run normalizes one at least.
proxy_windows() {
  local seconds=$(($1 * 3600)) now start windows
  now=$(date -u -d "@$(($(date -u +%s) / seconds * seconds))" '+%F %T')
  windows=$(ch --param_hours="$1" --queries-file "$here/missing.sql" </dev/null)
  while IFS= read -r start; do
    if [[ -z $start || ! $start < $now ]]; then
      break
    fi
    proxy "$start" "$(date -u -d "@$(($(date -u -d "$start" +%s) + seconds))" '+%F %T')"
    spent "${2:-}" && return
  done <<<"$windows"
  proxy "$now" "2100-01-01 00:00:00"
}

# Whether the budget of $1 seconds, if there is one, is spent.
spent() {
  if [[ -n $1 && $SECONDS -ge $1 ]]; then
    echo "the budget is spent; the next run goes on from the next window"
    return 0
  fi
  return 1
}

# The checks of verify.sql fail the run on a violation; its reports only
# print.
verify() {
  local failed
  ch --queries-file "$here/verify.sql" </dev/null | tee "$scratch/verify.tsv"
  failed=$(awk -F '\t' '$1 == "check" && $3 != 0' "$scratch/verify.tsv")
  if [[ -n $failed ]]; then
    echo "failed checks:" >&2
    echo "$failed" >&2
    exit 1
  fi
}

case ${1:-} in
cron)
  mkdir -p "$scratch"
  proxy_windows 1 "${BUDGET:-300}"
  ;;
verify)
  mkdir -p "$scratch"
  verify
  ;;
*)
  echo "usage: $0 cron|verify" >&2
  exit 2
  ;;
esac
