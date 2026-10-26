#!/usr/bin/env bash
# Bump vite-plus to the latest npm release and refresh each platform's hash.
set -euo pipefail

cd "$(dirname "$0")"

latest=$(curl -fsSL https://registry.npmjs.org/@voidzero-dev/vite-plus-cli-linux-x64-gnu/latest | jq -r .version)
current=$(sed -n 's/^  version = "\(.*\)";$/\1/p' default.nix)

if [ "$latest" = "$current" ]; then
  exit 0
fi

sed -i "s/^  version = \"$current\";$/  version = \"$latest\";/" default.nix

for platform in darwin-arm64 linux-x64-gnu linux-arm64-gnu; do
  url="https://registry.npmjs.org/@voidzero-dev/vite-plus-cli-$platform/-/vite-plus-cli-$platform-$latest.tgz"
  hash=$(nix store prefetch-file --json "$url" | jq -r .hash)
  sed -i "/platform = \"$platform\";/{n;s|hash = \".*\";|hash = \"$hash\";|}" default.nix
done
