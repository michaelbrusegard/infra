#!/usr/bin/env bash
# Runs the LLM conversation normalizer next to ClickHouse, as the cluster's
# llm-normalizer CronJob and the one-off llm-backfill Job do; see
# docs/llm-conversations.md. It runs in the ClickHouse server image, for
# clickhouse-client, with this directory copied from the plugin image.
#
#   normalize.sh cron      one run of the job: the requests that are not
#                          normalized yet, an hour at a time from the
#                          oldest, starting none after BUDGET seconds (300)
#   normalize.sh backfill  the proxy from its first request, a day at a time,
#                          then the transcript import, then the checks
#   normalize.sh verify    only the checks
#
# CLICKHOUSE_HOST and CLICKHOUSE_USER name the server and its user, whose
# password clickhouse-client reads from CLICKHOUSE_PASSWORD, and SCRATCH a
# directory for the downloads and the rows to insert.
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
	for table in llm.request_items llm.sessions llm.messages llm.calls llm.events; do
		if [[ -s $1/$table.jsonl ]]; then
			ch --query "INSERT INTO $table FORMAT JSONEachRow" < "$1/$table.jsonl"
		fi
	done
}

# One run over the requests that started from $1 until $2 and are not in
# llm.calls yet, with the state of the sessions they touch.
proxy() {
	local out=$scratch/proxy sessions
	rm -rf "$out"
	mkdir -p "$out"
	ch --param_after="$1" --param_before="$2" --queries-file "$here/requests.sql" < /dev/null > "$scratch/requests.jsonl"
	sessions=$("$normalizer" -requests -sessions < "$scratch/requests.jsonl")
	ch --param_sessions="$sessions" --queries-file "$here/state.sql" < /dev/null > "$scratch/state.jsonl"
	"$normalizer" -requests -state "$scratch/state.jsonl" -out "$out" < "$scratch/requests.jsonl"
	insert "$out"
	echo "proxy $1 to $2: $(wc -l < "$out/llm.calls.jsonl") calls"
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
	windows=$(ch --param_hours="$1" --queries-file "$here/missing.sql" < /dev/null)
	while IFS= read -r start; do
		if [[ -z $start || ! $start < $now ]]; then
			break
		fi
		proxy "$start" "$(date -u -d "@$(($(date -u -d "$start" +%s) + seconds))" '+%F %T')"
		spent "${2:-}" && return
	done <<< "$windows"
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

# Deletes are mutations, which ClickHouse applies in the background: the
# rows that a recovery or a rebuild deletes, as the design doc's Rebuild
# describes, stay until theirs finish. A backfill waits for them, rather
# than refuse an import because old rows still count, or insert next to
# rows that are still going.
settled() {
	local pending
	while :; do
		pending=$(ch --query "SELECT count() FROM system.mutations WHERE database = 'llm' AND NOT is_done")
		if [[ $pending == 0 ]]; then
			return
		fi
		echo "waiting for $pending deletes in llm to finish"
		sleep 10
	done
}

# The transcript import, once, after the proxy: which file holds a reply's
# call depends on the proxy's calls. It reads every transcript line, in
# parts of whole files that bound the server's sort, into one compressed
# input, and inserts only if the normalizer accounts for every line.
backfill_transcripts() {
	local out=$scratch/transcripts files
	if [[ $(ch --query "SELECT count() FROM llm.calls WHERE origin = 'transcript'") != 0 ]]; then
		echo "llm.calls holds transcript calls already; delete the transcript rows first" >&2
		exit 1
	fi
	rm -rf "$out"
	mkdir -p "$out"
	ch --queries-file "$here/proxied.sql" < /dev/null > "$scratch/proxied.tsv"
	ch --param_bytes=268435456 --queries-file "$here/files.sql" < /dev/null > "$scratch/files.txt"
	: > "$scratch/transcripts.jsonl.gz"
	while IFS= read -r files; do
		ch --param_files="$files" --queries-file "$here/transcripts.sql" < /dev/null | gzip -1 >> "$scratch/transcripts.jsonl.gz"
	done < "$scratch/files.txt"
	"$normalizer" -in "$scratch/transcripts.jsonl.gz" -proxied "$scratch/proxied.tsv" -out "$out"
	local lines covered
	lines=$(ch --query "SELECT count() FROM llm.transcripts FINAL")
	covered=$(awk -F '\t' '{ n += $5 } END { print n + 0 }' "$out/coverage.tsv")
	if [[ $lines != "$covered" ]]; then
		echo "coverage counts $covered lines of $lines" >&2
		exit 1
	fi
	insert "$out"
	echo "coverage (source, kind, disposition, destination, lines):"
	cat "$out/coverage.tsv"
}

# The checks of docs/llm-conversations.md that need no judgment fail the
# run; the others print their differences.
verify() {
	local failed
	ch --queries-file "$here/verify.sql" < /dev/null | tee "$scratch/verify.tsv"
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
backfill)
	mkdir -p "$scratch"
	settled
	proxy_windows 24
	backfill_transcripts
	verify
	;;
verify)
	mkdir -p "$scratch"
	verify
	;;
*)
	echo "usage: $0 cron|backfill|verify" >&2
	exit 2
	;;
esac
