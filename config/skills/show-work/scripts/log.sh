#!/usr/bin/env bash
# Append a well-formed row to a show-work decision log.
# Usage: log.sh <logfile> <phase> <decision> <why> <evidence> <result>
set -euo pipefail

if [ "$#" -ne 6 ]; then
	printf 'usage: log.sh <logfile> <phase> <decision> <why> <evidence> <result>\n' >&2
	exit 1
fi

logfile="$1"
shift

logdir="$(dirname "$logfile")"
if [ -n "$logdir" ] && [ "$logdir" != "." ] && [ ! -d "$logdir" ]; then
	mkdir -p "$logdir"
fi

if [ ! -f "$logfile" ]; then
	printf 'ts\tphase\tdecision\twhy\tevidence\tresult\n' > "$logfile"
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

clean() {
	local value
	value=$(printf '%s' "$1" | tr '\t\n\r' '   ')
	case "$value" in
		=*|+*|-*|@*) printf "'%s" "$value" ;;
		*) printf '%s' "$value" ;;
	esac
}

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
	"$ts" "$(clean "$1")" "$(clean "$2")" "$(clean "$3")" \
	"$(clean "$4")" "$(clean "$5")" >> "$logfile"
