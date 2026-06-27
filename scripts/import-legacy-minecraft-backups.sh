#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
backup_root="${BACKUP_ROOT:-$HOME/Downloads/mc_backups}"
namespace="${NAMESPACE:-minecraft}"
restic_image="${RESTIC_IMAGE:-docker.io/restic/restic:0.19.0}"
secrets_file="${SECRETS_FILE:-$repo_root/../infra-secrets/gitops/espresso/apps/minecraft/secrets.yaml}"
work_base="${WORK_BASE:-$backup_root/.restic-import-work}"
workdir="${WORKDIR:-}"

usage() {
  cat >&2 <<'EOF'
usage: import-legacy-minecraft-backups.sh [--dry-run]

Imports a curated set of old Minecraft zip backups into the active VolSync
restic repositories. The script is idempotent: each snapshot gets a unique
legacy-id-* tag and is skipped if that tag already exists.
EOF
}

dry_run=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=1
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 64
      ;;
  esac
  shift
done

require_tool() {
  local tool="$1"

  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "missing required tool: $tool" >&2
    exit 69
  fi
}

for tool in base64 docker find jq kubectl mktemp unzip; do
  require_tool "$tool"
done

if [ -z "$workdir" ]; then
  mkdir -p "$work_base"
  workdir="$(mktemp -d "$work_base/legacy-minecraft-import.XXXXXXXXXX")"
  cleanup_workdir=1
else
  mkdir -p "$workdir"
  cleanup_workdir=0
fi

cleanup() {
  if [ "$cleanup_workdir" -eq 1 ]; then
    rm -rf "$workdir"
  fi
}
trap cleanup EXIT

secret_value() {
  local secret="$1"
  local key="$2"
  local encoded
  local value

  if encoded="$(kubectl -n "$namespace" get secret "$secret" -o "jsonpath={.data.$key}" 2>/dev/null)"; then
    printf '%s' "$encoded" | base64 -d
    return
  fi

  require_tool sops
  require_tool yq
  if [ ! -f "$secrets_file" ]; then
    echo "cannot read Kubernetes secret $secret and fallback file is missing: $secrets_file" >&2
    exit 69
  fi

  if [ ! -f "$workdir/minecraft-secrets.yaml" ]; then
    sops -d "$secrets_file" >"$workdir/minecraft-secrets.yaml"
    chmod 600 "$workdir/minecraft-secrets.yaml"
  fi

  value="$(yq -r "select(.metadata.name == \"$secret\") | .stringData.$key" "$workdir/minecraft-secrets.yaml")"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    echo "missing $key in fallback secret $secret from $secrets_file" >&2
    exit 69
  fi
  printf '%s' "$value"
}

load_repo_env() {
  local secret="$1"

  RESTIC_REPOSITORY="$(secret_value "$secret" RESTIC_REPOSITORY)"
  RESTIC_PASSWORD="$(secret_value "$secret" RESTIC_PASSWORD)"
  RESTIC_REST_USERNAME="$(secret_value "$secret" RESTIC_REST_USERNAME)"
  RESTIC_REST_PASSWORD="$(secret_value "$secret" RESTIC_REST_PASSWORD)"
  export RESTIC_REPOSITORY RESTIC_PASSWORD RESTIC_REST_USERNAME RESTIC_REST_PASSWORD
}

restic_docker() {
  docker run --rm \
    -e RESTIC_REPOSITORY \
    -e RESTIC_PASSWORD \
    -e RESTIC_REST_USERNAME \
    -e RESTIC_REST_PASSWORD \
    "$restic_image" "$@"
}

restic_docker_with_data() {
  local data_dir="$1"
  shift

  docker run --rm \
    -e RESTIC_REPOSITORY \
    -e RESTIC_PASSWORD \
    -e RESTIC_REST_USERNAME \
    -e RESTIC_REST_PASSWORD \
    -v "$data_dir:/data:ro" \
    "$restic_image" "$@"
}

snapshot_time() {
  local value="$1"

  if [[ "$value" =~ ^[0-9]{10}$ ]]; then
    date -u -d "@$value" "+%Y-%m-%d %H:%M:%S"
  else
    printf '%s\n' "$value"
  fi
}

move_children() {
  local from="$1"
  local to="$2"

  find "$from" -mindepth 1 -maxdepth 1 -exec mv -t "$to" {} +
}

normalize_archive() {
  local zip="$1"
  local mode="$2"
  local extract_dir="$3"
  local data_dir="$4"

  rm -rf "$extract_dir" "$data_dir"
  mkdir -p "$extract_dir" "$data_dir"
  unzip -q "$zip" -d "$extract_dir"

  if [ "$mode" = "world-only" ]; then
    local world_dir
    world_dir="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d -print -quit)"
    if [ -z "$world_dir" ]; then
      echo "world-only archive has no top-level world directory: $zip" >&2
      exit 65
    fi
    mkdir -p "$data_dir/world"
    move_children "$world_dir" "$data_dir/world"
    return
  fi

  local top_count
  top_count="$(find "$extract_dir" -mindepth 1 -maxdepth 1 | wc -l)"
  if [ "$top_count" -eq 1 ] && [ -d "$(find "$extract_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    move_children "$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d -print -quit)" "$data_dir"
  else
    move_children "$extract_dir" "$data_dir"
  fi
}

snapshot_exists() {
  local legacy_id="$1"

  restic_docker snapshots --json --tag "$legacy_id" \
    | jq -e 'length > 0' >/dev/null
}

import_one() {
  local server="$1"
  local secret="$2"
  local time_ref="$3"
  local legacy_id="$4"
  local mode="$5"
  local rel_path="$6"
  local zip="$backup_root/$rel_path"
  local extract_dir="$workdir/extract"
  local data_dir="$workdir/data"
  local time_arg

  if [ ! -f "$zip" ]; then
    echo "missing backup archive: $zip" >&2
    exit 66
  fi

  load_repo_env "$secret"
  if snapshot_exists "$legacy_id"; then
    echo "skip $legacy_id ($server): already imported"
    return
  fi

  echo "stage $legacy_id ($server): $zip"
  normalize_archive "$zip" "$mode" "$extract_dir" "$data_dir"
  time_arg="$(snapshot_time "$time_ref")"

  if [ "$dry_run" -eq 1 ]; then
    echo "dry-run $legacy_id ($server): would import $(du -sh "$data_dir" | cut -f1) at $time_arg"
    return
  fi

  echo "import $legacy_id ($server): $(du -sh "$data_dir" | cut -f1) at $time_arg"
  restic_docker_with_data "$data_dir" backup /data \
    --host volsync \
    --time "$time_arg" \
    --tag legacy-minecraft \
    --tag "minecraft-$server" \
    --tag "$legacy_id"
}

while IFS='|' read -r server secret time_ref legacy_id mode rel_path; do
  [ -n "$server" ] || continue
  case "$server" in
    \#*) continue ;;
  esac
  import_one "$server" "$secret" "$time_ref" "$legacy_id" "$mode" "$rel_path"
done <<'IMPORTS'
vanilla|freddo-restic-minecraft-vanilla-world|2019-06-14 18:33:42|legacy-id-vanilla-1-13-2-world-only|world-only|Vanilla/Vanilla_1.13.2 (world only).zip
vanilla|freddo-restic-minecraft-vanilla-world|2020-02-08 23:14:40|legacy-id-vanilla-1-14-4|full|Vanilla/Vanilla_1.14.4.zip
vanilla|freddo-restic-minecraft-vanilla-world|1594129795|legacy-id-vanilla-20w06a-1594129795|full|Vanilla/Vanilla_20w06a_1594129795.zip
vanilla|freddo-restic-minecraft-vanilla-world|1619298158|legacy-id-vanilla-1-16-1-1619298158|full|Vanilla/Vanilla_1.16.1_1619298158.zip
vanilla|freddo-restic-minecraft-vanilla-world|1644943524|legacy-id-vanilla-1-17-1-1644943524|full|Vanilla/Vanilla_1.17.1_1644943524.zip
vanilla|freddo-restic-minecraft-vanilla-world|1655564161|legacy-id-vanilla-1-18-1-1655564161|full|Vanilla/Vanilla_1.18.1_1655564161.zip
vanilla|freddo-restic-minecraft-vanilla-world|1662814635|legacy-id-vanilla-1-19-1662814635|full|Vanilla/Vanilla_1.19_1662814635.zip
vanilla|freddo-restic-minecraft-vanilla-world|1667133136|legacy-id-vanilla-1-19-2-1667133136|full|Vanilla/Vanilla_1.19.2_1667133136.zip
vanilla|freddo-restic-minecraft-vanilla-world|1683941632|legacy-id-vanilla-1-19-2-1683941632|full|Vanilla/Vanilla_1.19.2_1683941632.zip
vanilla|freddo-restic-minecraft-vanilla-world|1692731333|legacy-id-vanilla-1-20-1-1692731333|full|Vanilla/Vanilla_1.20.1_1692731333.zip
vanilla|freddo-restic-minecraft-vanilla-world|1694459284|legacy-id-vanilla-1-20-1-1694459284|full|Vanilla/Vanilla_1.20.1_1694459284.zip
revelation|freddo-restic-minecraft-revelation-world|1619920800|legacy-id-revelation-1-12-2-1619920800|full|FTB Revelation/FTB_Revelation_1.12.2_1619920800.zip
revelation|freddo-restic-minecraft-revelation-world|1625709601|legacy-id-revelation-1-12-2-1625709601|full|FTB Revelation/FTB_Revelation_1.12.2_1625709601.zip
revelation|freddo-restic-minecraft-revelation-world|1645066801|legacy-id-revelation-1-12-2-1645066801|full|FTB Revelation/FTB_Revelation_1.12.2_1645066801.zip
revelation|freddo-restic-minecraft-revelation-world|1648782003|legacy-id-revelation-1-12-2-1648782003|full|FTB Revelation/FTB_Revelation_1.12.2_1648782003.zip
revelation|freddo-restic-minecraft-revelation-world|1654048804|legacy-id-revelation-1-12-2-1654048804|full|FTB Revelation/FTB_Revelation_1.12.2_1654048804.zip
IMPORTS
