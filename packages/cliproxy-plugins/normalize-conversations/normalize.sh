#!/usr/bin/env bash
# Runs the LLM conversation normalizer next to ClickHouse, as the cluster's
# llm-normalizer CronJob and the one-off llm-backfill Job do; see
# docs/llm-conversations.md. It runs in the ClickHouse server image, for
# clickhouse-client, with this directory copied from the plugin image.
#
#   normalize.sh cron      one run of the job: the last day's requests that
#                          are not normalized yet
#   normalize.sh backfill  the proxy from its first request, a day at a time,
#                          then the transcript import, then the checks
#   normalize.sh verify    only the checks
#
# CLICKHOUSE_HOST and CLICKHOUSE_USER name the server and its user, and
# SCRATCH a directory for the downloads and the rows to insert.
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

# The proxy's capture, in start order and a day at a time, which bounds
# the items the server joins at once; each day's rows are inserted before
# the next day reads its state. The last day reaches into the future, and
# its recent requests are held back for the job.
backfill_proxy() {
	local day last
	day=$(ch --query "SELECT toDate(if(count() = 0, today(), min(started_at))) FROM llm.requests")
	last=$(date -u +%F)
	while [[ $day < $last ]]; do
		proxy "$day 00:00:00" "$(date -u -d "$day + 1 day" +%F) 00:00:00"
		day=$(date -u -d "$day + 1 day" +%F)
	done
	proxy "$last 00:00:00" "2100-01-01 00:00:00"
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
	proxy "$(date -u -d '1 day ago' '+%F %T')" "2100-01-01 00:00:00"
	;;
backfill)
	mkdir -p "$scratch"
	backfill_proxy
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
