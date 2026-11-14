#!/usr/bin/env bash
# One-off migration of llm.requests rows that still hold request_body to the
# llm.request_items layout. Run it from the repo root in `nix develop`:
#
#   gitops/espresso/apps/clickhouse/migrate-request-items.sh copy
#   gitops/espresso/apps/clickhouse/migrate-request-items.sh drop
#
# `copy` swaps in an empty table without request_body, then copies the old
# rows into it chunk by chunk, splitting bodies with the archive plugin's own
# Go code (ClickHouse's JSON functions rewrite numbers and escapes, so they
# cannot produce the same items). Each chunk is verified against the original
# bodies before it is marked done. It is resumable: rerun it after a failure.
# `drop` rechecks everything and only then drops the old table.
#
# ALTER TABLE ... UPDATE and DROP COLUMN are not used: ClickHouse does not
# mutate a part larger than the free disk space, and the archive has parts far
# larger than what is free. Copying rows without their bodies and dropping the
# old table whole needs only the space of the new rows.
#
# Roll out the plugin that writes request_items first: the new table has no
# request_body, so rows from the old plugin would lose their bodies. `copy`
# refuses to swap until the newest rows are in the new layout.
#
# CLICKHOUSE_EXEC is the command prefix that runs a program in the ClickHouse
# container; the default reaches the live pod.
set -euo pipefail

read -ra exec_in <<< "${CLICKHOUSE_EXEC:-ssh -o BatchMode=yes deploy-espresso-0 sudo -n k3s kubectl -n clickhouse exec -i clickhouse-0 --}"
# Raw body bytes per chunk. The view holds a chunk's bodies in memory while
# verifying it.
chunk_bytes=${CHUNK_BYTES:-134217728}
# Stop before a chunk while less than this is free.
min_free_bytes=${MIN_FREE_BYTES:-1073741824}
plugins=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/packages/cliproxy-plugins

parts_type='Array(Tuple(field LowCardinality(String), position Int32, hash UInt128))'
columns='request_id, trace_id, session_id, started_at, completed_at, source_format, model,
    requested_model, stream, outcome, status_code, error, user_agent, truncated'

sql() { "${exec_in[@]}" clickhouse-client --multiquery; }

upload() {
	"${exec_in[@]}" dd "of=$2" status=none < "$1"
	"${exec_in[@]}" chmod 755 "$2"
}

# Runs inside the container, once per chunk.
chunk_script=$(cat <<EOF
set -euo pipefail
ch() { clickhouse-client --max_threads 2 --param_chunk="\$1" "\${@:2}"; }
chunk=\$1
in_chunk="request_id IN (SELECT request_id FROM llm.request_backfill_chunks WHERE chunk = {chunk:UInt32})"
ch \$chunk --query "TRUNCATE TABLE llm.request_backfill"
ch \$chunk --max_block_size 16 --query "
    SELECT request_id, request_body FROM llm.requests_legacy
    WHERE \$in_chunk AND request_envelope = '' AND empty(request_parts)
    FORMAT JSONEachRow" \\
    | /tmp/request-backfill \\
    | ch \$chunk --query "INSERT INTO llm.request_backfill FORMAT JSONEachRow"
ch \$chunk --multiquery <<SQL
INSERT INTO llm.request_items
SELECT item.hash, item.item FROM llm.request_backfill ARRAY JOIN items AS item
WHERE item.hash NOT IN (SELECT hash FROM llm.request_items);

INSERT INTO llm.requests ($columns, request_envelope, request_parts, response_body)
SELECT $columns, b.request_envelope, b.request_parts, response_body
FROM llm.requests_legacy AS l
INNER JOIN llm.request_backfill AS b USING (request_id)
WHERE l.\$in_chunk AND l.request_id NOT IN (SELECT request_id FROM llm.requests);

-- Rows the new plugin wrote before the swap are already split.
INSERT INTO llm.requests ($columns, request_envelope, request_parts, response_body)
SELECT $columns, request_envelope, request_parts, response_body
FROM llm.requests_legacy
WHERE \$in_chunk AND (request_envelope != '' OR notEmpty(request_parts))
    AND request_id NOT IN (SELECT request_id FROM llm.requests);

-- Every row must be readable through the view, as exactly the bytes the Go
-- code reassembles, and as the same JSON as its original body. Bodies
-- ClickHouse cannot parse but Go could, such as lone surrogate escapes, are
-- listed instead of compared.
SELECT
    count() AS rows,
    countIf(v.request_id = '') AS missing,
    countIf(legacy AND v.exact != b.body_hash) AS unstored,
    countIf(legacy AND v.exact != original AND isValidJSON(l.request_body)
        AND v.normal != sipHash128(arraySort(JSONExtractKeysAndValuesRaw(l.request_body)))) AS changed,
    throwIf(missing + unstored + changed > 0, 'chunk does not match the original bodies') AS failed,
    groupArrayIf(20)(l.request_id, legacy AND v.exact != original AND NOT isValidJSON(l.request_body)) AS unchecked
FROM (
    SELECT request_id, request_body, request_envelope = '' AND empty(request_parts) AS legacy,
        reinterpretAsUInt128(substring(SHA256(request_body), 1, 16)) AS original
    FROM llm.requests_legacy WHERE \$in_chunk
) AS l
LEFT JOIN (
    SELECT request_id,
        reinterpretAsUInt128(substring(SHA256(request_body), 1, 16)) AS exact,
        sipHash128(arraySort(JSONExtractKeysAndValuesRaw(request_body))) AS normal
    FROM llm.request_bodies WHERE \$in_chunk
) AS v USING (request_id)
LEFT JOIN llm.request_backfill AS b USING (request_id)
FORMAT TSV;

INSERT INTO llm.request_backfill_done SELECT {chunk:UInt32};
SQL
EOF
)

copy() {
	sql <<SQL
-- The new layout must exist, from schema.sql.
SELECT throwIf(count() != 2, 'apply the new schema.sql first') FROM system.tables
WHERE database = 'llm' AND name IN ('request_items', 'request_bodies') FORMAT Null;

CREATE TABLE IF NOT EXISTS llm.request_backfill
(
    request_id String,
    request_envelope String,
    request_parts $parts_type,
    body_hash UInt128,
    items Array(Tuple(hash UInt128, item String))
)
ENGINE = MergeTree
ORDER BY request_id;
CREATE TABLE IF NOT EXISTS llm.request_backfill_chunks (request_id String, chunk UInt32)
ENGINE = MergeTree ORDER BY chunk;
CREATE TABLE IF NOT EXISTS llm.request_backfill_done (chunk UInt32)
ENGINE = MergeTree ORDER BY chunk;
SQL
	if [[ $(sql <<< "EXISTS TABLE llm.requests_legacy") == 0 ]]; then
		swap
	fi
	sql <<SQL
-- Nothing writes to the old table any more; its merges would only use disk.
SYSTEM STOP MERGES llm.requests_legacy;
-- Chunks follow the sort key, so each reads a contiguous range of every part.
INSERT INTO llm.request_backfill_chunks
SELECT request_id, (SELECT max(chunk) + 1 FROM llm.request_backfill_chunks)
    + toUInt32(intDiv(sum(length(request_body)) OVER (ORDER BY session_id, started_at, request_id), $chunk_bytes))
FROM llm.requests_legacy
WHERE request_id NOT IN (SELECT request_id FROM llm.request_backfill_chunks);
SQL

	local build
	build=$(mktemp -d)
	trap 'rm -rf "$build"' RETURN
	(cd "$plugins" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		go build -trimpath -o "$build/request-backfill" ./request-backfill)
	printf '%s\n' "$chunk_script" > "$build/chunk.sh"
	upload "$build/request-backfill" /tmp/request-backfill
	upload "$build/chunk.sh" /tmp/request-items-chunk.sh

	local chunks chunk
	chunks=$(sql <<< "SELECT DISTINCT chunk FROM llm.request_backfill_chunks
		WHERE chunk NOT IN (SELECT chunk FROM llm.request_backfill_done) ORDER BY chunk")
	for chunk in $chunks; do
		sql <<SQL
SELECT throwIf(free_space < $min_free_bytes, 'too little free disk space to continue')
FROM system.disks WHERE name = 'default' FORMAT Null;
SQL
		printf 'chunk %s: ' "$chunk"
		"${exec_in[@]}" bash /tmp/request-items-chunk.sh "$chunk" < /dev/null \
			| awk -F'\t' '{print "rows " $1 ", unchecked " $6}'
	done
	echo "All chunks copied and verified. Review any unchecked rows, then run: $0 drop"
}

swap() {
	local new_has_body
	new_has_body=$(sql <<'SQL'
SELECT count() FROM system.columns
WHERE database = 'llm' AND table = 'requests_new' AND name = 'request_body'
SQL
)
	if [[ $(sql <<< "EXISTS TABLE llm.requests") == 1 && $new_has_body == 1 \
		&& $(sql <<< "EXISTS TABLE llm.requests_legacy") == 0 \
		&& $(sql <<< "SELECT count() FROM system.columns WHERE database = 'llm' AND table = 'requests' AND name = 'request_body'") == 0 ]]; then
		# A previous run stopped between the exchange and the rename.
		sql <<< "RENAME TABLE llm.requests_new TO llm.requests_legacy"
		return
	fi
	sql <<'SQL'
SELECT throwIf(count() != uniqExact(request_id), 'request_id is not unique') FROM llm.requests FORMAT Null;
SELECT throwIf(count() = 0 OR countIf(request_envelope = '' AND empty(request_parts)) > 0,
    'the newest rows still hold request_body: roll out the new archive plugin first')
FROM (SELECT request_envelope, request_parts FROM llm.requests ORDER BY started_at DESC LIMIT 10) FORMAT Null;
-- The same table minus request_body, which is the shape schema.sql creates.
CREATE TABLE IF NOT EXISTS llm.requests_new AS llm.requests;
SELECT throwIf(count() > 0, 'llm.requests_new is not empty') FROM llm.requests_new FORMAT Null;
ALTER TABLE llm.requests_new DROP COLUMN IF EXISTS request_body;
EXCHANGE TABLES llm.requests AND llm.requests_new;
RENAME TABLE llm.requests_new TO llm.requests_legacy;
SQL
}

drop() {
	sql <<SQL
SELECT throwIf(count() > 0, 'some chunks are not verified: run copy again')
FROM (SELECT DISTINCT chunk FROM llm.request_backfill_chunks)
WHERE chunk NOT IN (SELECT chunk FROM llm.request_backfill_done) FORMAT Null;
SELECT throwIf(count() > 0, 'some old rows were never copied: run copy again')
FROM llm.requests_legacy
WHERE request_id NOT IN (SELECT request_id FROM llm.requests) FORMAT Null;
SELECT throwIf(count() > 0, 'some requests reference missing items')
FROM (SELECT arrayJoin(request_parts.hash) AS hash FROM llm.requests)
WHERE hash NOT IN (SELECT hash FROM llm.request_items) FORMAT Null;
SELECT throwIf(count() > 0, 'some items do not match their hash')
FROM llm.request_items
WHERE hash != reinterpretAsUInt128(substring(SHA256(item), 1, 16)) FORMAT Null;
DROP TABLE llm.requests_legacy SYNC;
DROP TABLE llm.request_backfill SYNC;
DROP TABLE llm.request_backfill_chunks SYNC;
DROP TABLE llm.request_backfill_done SYNC;
SQL
	"${exec_in[@]}" rm -f /tmp/request-backfill /tmp/request-items-chunk.sh
	echo "Dropped the old table."
}

case ${1:-} in
copy) copy ;;
drop) drop ;;
*)
	echo "usage: $0 copy|drop" >&2
	exit 2
	;;
esac
