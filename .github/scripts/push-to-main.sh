#!/usr/bin/env bash
# Pushes the commit a workflow just made to main. Other workflows push there at
# the same time, so a rejected push is rebased and tried again. Any arguments
# are a command that has to pass on the rebased tree before it is pushed.
set -euo pipefail

for _ in 1 2 3 4 5; do
  git pull --rebase origin main
  if (($#)); then "$@"; fi
  if git push; then exit 0; fi
done
echo "main kept moving: the push was rejected five times" >&2
exit 1
