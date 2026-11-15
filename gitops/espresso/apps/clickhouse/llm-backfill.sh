#!/usr/bin/env bash
# Runs the one-off LLM conversation backfill in the cluster, next to
# ClickHouse, and collects its output; see docs/llm-conversations.md. Run it
# from the repo root, in the dev shell for jq, once the llm-normalizer image
# is promoted:
#
#   gitops/espresso/apps/clickhouse/llm-backfill.sh
#
# It creates a llm-backfill Job, which Flux does not apply, waits for it,
# and saves its log, which holds every day's proxy run, the transcript
# coverage, and the checks, to llm-backfill.log. Nothing but the log leaves
# the cluster. KUBECTL is the command prefix that runs kubectl against the
# cluster; the default reaches it through a node.
set -euo pipefail

read -ra kubectl <<< "${KUBECTL:-ssh -o BatchMode=yes deploy-espresso-0 sudo -n k3s kubectl}"
manifest=$(dirname "$0")/llm-backfill-job.yaml
log=${LOG:-llm-backfill.log}

# Each run is a Job of its own, which Kubernetes names: a finished one is
# kept for a week with its log, so a rerun must not reuse its name.
job=$("${kubectl[@]}" -n clickhouse create -o name -f - < "$manifest")
echo "waiting for $job"
# The Job's conditions say how it ended; its pod counters do not, such as
# when it passes its deadline.
while :; do
	conditions=$("${kubectl[@]}" -n clickhouse get "$job" -o json < /dev/null |
		jq -r '[.status.conditions[]? | select(.status == "True") | .type] | join(" ")')
	case " $conditions " in
	*" Complete "*) result=0 && break ;;
	*" Failed "*) result=1 && break ;;
	esac
	sleep 60
done
"${kubectl[@]}" -n clickhouse logs "$job" --all-containers < /dev/null > "$log"
tail -n 40 "$log"
if [[ $result != 0 ]]; then
	echo "$job failed; the full log is in $log" >&2
fi
exit "$result"
