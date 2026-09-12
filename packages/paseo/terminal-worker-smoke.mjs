import assert from "node:assert/strict";
import path from "node:path";
import { pathToFileURL } from "node:url";

const root = process.argv[2];
assert(root && path.isAbsolute(root), "Pass the installed Paseo runtime directory");
const { createWorkerTerminalManager } = await import(
  pathToFileURL(
    path.join(root, "packages/server/dist/server/terminal/worker-terminal-manager.js"),
  ).href
);

// Exercise the installed worker and its native imports, not the build tree.
// Querying a nonexistent terminal tests IPC without opening a shell or daemon.
const manager = createWorkerTerminalManager({ requestTimeoutMs: 5000 });
try {
  assert.equal(await manager.getTerminalState("packaging-smoke-test"), null);
  console.log("Terminal worker smoke test passed");
} finally {
  manager.killAll();
}
