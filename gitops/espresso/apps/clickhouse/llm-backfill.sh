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
# coverage, and the checks, to <job>.log. Nothing but the log leaves the
# cluster. KUBECTL is the command prefix that runs kubectl against the
# cluster; the default reaches it through a node.
set -euo pipefail

read -ra kubectl <<< "${KUBECTL:-ssh -o BatchMode=yes deploy-espresso-0 sudo -n k3s kubectl}"
manifest=$(dirname "$0")/llm-backfill-job.yaml
# The Job writes about 14 GiB of scratch to the node's own disk.
min_free_bytes=${MIN_FREE_BYTES:-21474836480}

# A finished attempt keeps its pod, and with it its scratch volume, until
# its Job goes. Earlier runs saved their logs, so remove finished attempts
# first, and never start beside one that is still running.
attempts=$("${kubectl[@]}" -n clickhouse get jobs -o json < /dev/null |
	jq -r '.items[] | select(.metadata.name | startswith("llm-backfill-")) |
		[.metadata.name, ([.status.conditions[]? | select(.status == "True") | .type] | join(","))] | @tsv')
while IFS=$'\t' read -r name state; do
	[[ -z $name ]] && continue
	case ",$state," in
	*,Complete,* | *,Failed,*) "${kubectl[@]}" -n clickhouse delete job "$name" --wait=true < /dev/null ;;
	*) echo "$name is still running; wait for it or delete it first" >&2 && exit 1 ;;
	esac
done <<< "$attempts"

# The scratch volume lives on ClickHouse's node, whose free space the
# volume's 40Gi size does not reserve. It is under /var/local/openebs, on
# the persistent disk that also holds containerd's images, which the
# kubelet reports as the image filesystem; the node filesystem is the
# tmpfs root.
node=$("${kubectl[@]}" -n clickhouse get pod clickhouse-0 -o jsonpath='{.spec.nodeName}' < /dev/null)
read -r free inodes < <("${kubectl[@]}" get --raw "/api/v1/nodes/$node/proxy/stats/summary" < /dev/null |
	jq -r '"\(.node.runtime.imageFs.availableBytes) \(.node.runtime.imageFs.inodesFree)"')
if ((free < min_free_bytes || inodes < 1000000)); then
	echo "$node has $((free >> 30)) GiB and $inodes inodes free; the backfill needs $((min_free_bytes >> 30)) GiB" >&2
	exit 1
fi

# Each run is a Job of its own, which Kubernetes names, so a rerun never
# reuses a name.
job=$("${kubectl[@]}" -n clickhouse create -o name -f - < "$manifest")
log=${LOG:-${job#*/}.log}
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
