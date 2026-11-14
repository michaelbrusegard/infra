#!/usr/bin/env bash
# Runs the one-off LLM conversation backfill in the cluster, next to
# ClickHouse, and collects its output; see docs/llm-conversations.md. Run it
# from the repo root once the llm-normalizer image is promoted:
#
#   gitops/espresso/apps/clickhouse/llm-backfill.sh
#
# It creates the llm-backfill Job, which Flux does not apply, waits for it,
# and saves its log, which holds every day's proxy run, the transcript
# coverage, and the checks, to llm-backfill.log. Nothing but the log leaves
# the cluster. KUBECTL is the command prefix that runs kubectl against the
# cluster; the default reaches it through a node.
set -euo pipefail

read -ra kubectl <<< "${KUBECTL:-ssh -o BatchMode=yes deploy-espresso-0 sudo -n k3s kubectl}"
job=$(dirname "$0")/llm-backfill-job.yaml
log=${LOG:-llm-backfill.log}

"${kubectl[@]}" -n clickhouse create -f - < "$job"
echo "waiting for job/llm-backfill"
while :; do
	status=$("${kubectl[@]}" -n clickhouse get job llm-backfill \
		-o 'jsonpath={.status.succeeded}/{.status.failed}' < /dev/null)
	case $status in
	1/*) result=0 && break ;;
	*/1) result=1 && break ;;
	esac
	sleep 60
done
"${kubectl[@]}" -n clickhouse logs job/llm-backfill --all-containers < /dev/null > "$log"
tail -n 40 "$log"
if [[ $result != 0 ]]; then
	echo "job/llm-backfill failed; the full log is in $log" >&2
fi
exit "$result"
