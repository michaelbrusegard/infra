#!/usr/bin/env bash
set -euo pipefail

# Every app under gitops/espresso/apps needs a namespace, a network policy and
# a backup. Exemptions are "app|piece|reason", where piece is one of
# namespace, network-policy or backup.
exemptions=(
  "ollama|backup|the PVC only caches nomic-embed-text, which the model-pull init container re-downloads"
  "searxng|network-policy|runs with hostNetwork for IPv6 source rotation, so pod policies do not apply; the Cilium host firewall covers it"
  "searxng|backup|stateless Deployment with only emptyDir volumes"
  "uptime-kuma|backup|monitors and status pages are rebuilt from Git by AutoKuma and the reconciler; heartbeat history is not kept"
)

apps=gitops/espresso/apps
failures=()

exempt() {
  local entry
  for entry in "${exemptions[@]}"; do
    [[ $entry == "$1|$2|"* ]] && return 0
  done
  return 1
}

has() {
  local match
  for match in "$1"/$2; do
    [[ -e $match ]] && return 0
  done
  return 1
}

check() {
  local dir=$1 app=$2 piece=$3 pattern=$4 advice=$5
  if has "$dir" "$pattern"; then
    if exempt "$app" "$piece"; then
      failures+=("$app: has $pattern but is exempt from $piece. Remove the \"$app|$piece|...\" exemption from $0.")
    fi
  elif ! exempt "$app" "$piece"; then
    failures+=("$app: missing $piece. $advice, list it in $dir/kustomization.yaml, or add the exemption \"$app|$piece|<reason>\" to $0.")
  fi
}

for dir in "$apps"/*/; do
  dir=${dir%/}
  app=${dir##*/}
  check "$dir" "$app" namespace namespace.yaml \
    "Add $dir/namespace.yaml with the app's Namespace"
  check "$dir" "$app" network-policy '*network-policy.yaml' \
    "Add $dir/network-policy.yaml with a CiliumNetworkPolicy that allows only the flows the app needs"
  check "$dir" "$app" backup 'backup*.yaml' \
    "Add $dir/backup.yaml with a VolSync ReplicationSource for each PVC that holds state"
done

for entry in "${exemptions[@]}"; do
  app=${entry%%|*}
  [[ -d $apps/$app ]] || failures+=("$app: exempt in $0 but $apps/$app does not exist. Remove the exemption.")
done

if ((${#failures[@]})); then
  printf '%s\n' "${failures[@]}" >&2
  exit 1
fi
echo "App shape check passed"
