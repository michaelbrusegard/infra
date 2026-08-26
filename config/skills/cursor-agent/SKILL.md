---
name: cursor-agent
description: Operate the standalone Cursor CLI or delegate work to Cursor from another coding agent. Use when the user asks to use Cursor, compare with Cursor, run Cursor headlessly, manage Cursor sessions/models/MCP, or hand a task to Cursor.
---

# Cursor agent

Use the standalone `agent` command. It is Cursor's full CLI, not a model
provider for Pi or CLIProxyAPI.

## Authenticate

Run `agent status` before the first delegated task. If authentication is
missing, ask the user to run `agent login`; browser account authorization is a
human step. Do not request, print, or persist a Cursor API key.

Authentication is complete when `agent status` reports the expected account.

## Choose the execution path

- Interactive Cursor session: tell the user to run `agent` directly.
- Read-only answer or second opinion: run `agent -p --mode ask`.
- Plan: run `agent -p --mode plan`.
- Delegated implementation: run `agent -p --force` only when the user asked
  Cursor to make changes.
- Structured automation: add `--output-format stream-json`; parse events with
  `jq` instead of placing the full stream in model context.
- Persistent Cursor conversation: use `agent create-chat`, `agent --resume`,
  `agent --continue`, or `agent ls`.
- Custom ACP integration: use `agent acp`. ACP is newline-delimited JSON-RPC on
  stdio and requires handling permission and Cursor extension requests.

Set the workspace explicitly with `--workspace "$PWD"` for headless calls.
Use `--trust` only for a repository the user already trusts.

## Isolation

For delegated writes, avoid concurrent edits in the same working tree. Prefer
`--worktree` when Cursor can work independently. Use the current working tree
only when the user explicitly wants Cursor to modify it directly and no other
agent is editing it.

A delegated implementation is complete only after inspecting Cursor's diff and
running the repository's required validation. Cursor's successful exit is not
proof that the change is correct.

## Capabilities

Consult `agent --help` and command-specific help rather than caching flags.
Cursor CLI supports interactive and headless agents, ask/plan modes, model
selection, resumable sessions, images and other referenced files, plugins,
skills, subagents, MCP, sandbox controls, Git worktrees, cloud handoff, private
workers, and ACP.

Use `agent models` for the authenticated account's current model catalog and
`agent mcp` for Cursor's MCP status and authentication.
