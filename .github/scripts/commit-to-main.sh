#!/usr/bin/env bash
# Commits the named paths as the Actions bot and pushes to main, or does
# nothing when they are unchanged. Other workflows push there at the same time,
# so a rejected push is rebased and tried again.
#
#   commit-to-main.sh <message> <path>... [-- <command>...]
#
# The command after -- has to pass on the rebased tree before each push.
set -euo pipefail

message=$1
shift
paths=()
while (($#)) && [[ $1 != -- ]]; do
  paths+=("$1")
  shift
done
if (($#)); then shift; fi

export GIT_AUTHOR_NAME='github-actions[bot]'
export GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com'
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME
export GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL

git add -- "${paths[@]}"
if git diff --cached --quiet -- "${paths[@]}"; then
  exit 0
fi
git commit -m "$message" -- "${paths[@]}"

for _ in 1 2 3 4 5; do
  git pull --rebase origin main
  if (($#)); then "$@"; fi
  if git push; then exit 0; fi
done
echo "main kept moving: the push was rejected five times" >&2
exit 1
