#!/usr/bin/env bash
# Point a package that pins GitHub release files at the newest numbered
# release. The package keeps one `version = "…";` and, per file, a hash on the
# line after the line named here.
#
#   update-release.sh <package.nix> <owner/repo> <marker>=<url>...
#
# <marker> is text unique to the line above a hash; <url> may use {version}.
set -euo pipefail

file=$1
repo=$2
shift 2

auth=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

tag=$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/$repo/releases?per_page=20" |
  jq -r '[.[].tag_name | select(test("^v?[0-9]"))][0]')
latest=${tag#v}
current=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file" | head -1)
if [ "$latest" = "$current" ]; then
  exit 0
fi

sed -i "0,/version = \"$current\";/s//version = \"$latest\";/" "$file"
for pair in "$@"; do
  marker=${pair%=*}
  url=${pair##*=}
  hash=$(nix store prefetch-file --json "${url//\{version\}/$latest}" | jq -r .hash)
  line=$(grep -nF -- "$marker" "$file" | head -1 | cut -d: -f1)
  test -n "$line"
  sed -i "$((line + 1))s|hash = \".*\";|hash = \"$hash\";|" "$file"
done
