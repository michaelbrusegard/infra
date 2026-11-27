#!/usr/bin/env bash
# Point every entry in sources.json at its latest stable release. The apps ship
# several times a week and publish their own checksum file, so nothing is
# downloaded here.
set -euo pipefail

cd "$(dirname "$0")"

auth=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

sri() {
  local digest
  digest=$(awk -v file="$2" '$2 == file { print $1 }' <<<"$1")
  test -n "$digest"
  nix hash convert --hash-algo sha256 --to sri "$digest"
}

updated=$(mktemp)
cp sources.json "$updated"

for name in $(jq -r 'keys[]' sources.json); do
  repo=$(jq -r --arg name "$name" '.[$name].repo' sources.json)
  version=$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/$repo/releases/latest" | jq -r '.tag_name | ltrimstr("v")')
  if [ "$version" = "$(jq -r --arg name "$name" '.[$name].version' sources.json)" ]; then
    continue
  fi
  sums=$(curl -fsSL "https://github.com/$repo/releases/download/v$version/SHA256SUMS.txt")
  if [ "$name" = artcraft-launcher ]; then
    mac=dmgHash
    macFile="$name-$version-macos-universal.dmg"
  else
    mac=cliHash
    macFile="$name-cli-$version-macos-universal.zip"
  fi
  jq --arg name "$name" --arg version "$version" --arg mac "$mac" \
    --arg hash "$(sri "$sums" "$name-$version-linux-x86_64.tar.gz")" \
    --arg macHash "$(sri "$sums" "$macFile")" \
    '.[$name] |= (.version = $version | .hash = $hash | .[$mac] = $macHash)' "$updated" >"$updated.next"
  mv "$updated.next" "$updated"
done

mv "$updated" sources.json
