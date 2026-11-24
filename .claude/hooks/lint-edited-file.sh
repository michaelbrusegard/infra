#!/usr/bin/env bash
set -uo pipefail

file=$(jq -r '.tool_input.file_path // empty')
[[ -n $file && -f $file ]] || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
[[ $file == "$PWD"/* ]] || exit 0

if ! output=$(nix fmt -- "$file" 2>&1); then
  printf 'nix fmt failed on %s:\n%s\n' "$file" "$output" >&2
  exit 2
fi

if command -v ast-grep >/dev/null && ! output=$(ast-grep scan "$file" 2>&1); then
  printf 'lint rules failed on %s:\n%s\n' "$file" "$output" >&2
  exit 2
fi
