#!/usr/bin/env bash
set -euo pipefail

# external-dns ignores DNSEndpoint records outside its domainFilters, so such
# a record is silently never created.
release=gitops/espresso/infrastructure/controllers/external-dns/helm-release.yaml
mapfile -t zones < <(
  yq 'select(.kind == "HelmRelease" and .metadata.name == "external-dns") | .spec.values.domainFilters[]' "$release"
)
if ((${#zones[@]} == 0)); then
  echo "No domainFilters found in $release. Update $0 if external-dns moved." >&2
  exit 1
fi

mapfile -t manifests < <(git ls-files 'gitops/espresso/*.yaml' ':!gitops/espresso/flux-system/')
failures=()
records=0

while IFS=$'\t' read -r file name; do
  records=$((records + 1))
  name=${name%.}
  covered=false
  for zone in "${zones[@]}"; do
    if [[ $name == "$zone" || $name == *".$zone" ]]; then
      covered=true
      break
    fi
  done
  $covered || failures+=("$file: $name is outside every external-dns zone (${zones[*]}). Add its zone to domainFilters in $release, or define the record in gitops/espresso/tofu/dns.")
done < <(
  yq ea -N 'select(.kind == "DNSEndpoint") | .spec.endpoints[].dnsName | filename + "	" + .' "${manifests[@]}"
)

if ((${#failures[@]})); then
  printf '%s\n' "${failures[@]}" >&2
  exit 1
fi
echo "DNS zone check passed ($records records in ${#zones[@]} zones)"
