#!/usr/bin/env bash
set -euo pipefail

# Pass the rendered home.activation.removeDesktopAutomationMcp.data script.
# Linux user namespaces let this exercise real bind mounts without sudo.
unshare --user --map-root-user --mount bash -euo pipefail -s -- "$1" <<'TEST'
activation_script=$1
fixture_root=$(mktemp -d /tmp/ai-mcp-cleanup.XXXXXX)
trap 'umount "$fixture_root/.claude.json"; rm -r -- "$fixture_root"' EXIT
mkdir -p "$fixture_root/.pi/agent"
cat > "$fixture_root/backing.json" <<'JSON'
{
  "existing": "preserve",
  "mcpServers": {
    "keep": {"command": "keep-me"},
    "open-browser-use": {},
    "open-computer-use": {},
    "open_browser_use": {},
    "open_computer_use": {}
  }
}
JSON
cp "$fixture_root/backing.json" "$fixture_root/.pi/agent/mcp.json"
touch "$fixture_root/.claude.json"
mount --bind "$fixture_root/backing.json" "$fixture_root/.claude.json"
inode=$(stat -c %i "$fixture_root/.claude.json")

script=$(cat "$activation_script")
script=${script//\$HOME/$fixture_root}
printf '%s\n' "$script" > "$fixture_root/activate"
DRY_RUN_CMD=echo bash -e "$fixture_root/activate" > /dev/null
cmp "$fixture_root/backing.json" "$fixture_root/.pi/agent/mcp.json"
jq -e '.mcpServers | length == 5' "$fixture_root/backing.json" > /dev/null

DRY_RUN_CMD= bash -e "$fixture_root/activate"
for config_file in "$fixture_root/.claude.json" "$fixture_root/.pi/agent/mcp.json"; do
  jq -e '.existing == "preserve" and .mcpServers == {"keep": {"command": "keep-me"}}' \
    "$config_file" > /dev/null
  test "$(stat -c %a "$config_file")" = 600
done
test "$(stat -c %i "$fixture_root/.claude.json")" = "$inode"
cmp "$fixture_root/.claude.json" "$fixture_root/backing.json"
DRY_RUN_CMD= bash -e "$fixture_root/activate"
printf '%s\n' 'MCP cleanup preserves bind mounts, unrelated settings, dry runs and repeat activation'
TEST
