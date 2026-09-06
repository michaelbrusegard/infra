"""Exercise routed snapshot refs against the existing Chromium sidecar."""

from __future__ import annotations

import uuid
from urllib.parse import quote

from tools import browser_tool


def main() -> None:
    task_id = f"refs-smoke-{uuid.uuid4().hex[:10]}"

    def run(command, args=None):
        result = browser_tool._run_browser_command(task_id, command, args or [])
        assert result.get("success"), (command, result)
        return result.get("data", {})

    def snapshot_ref(role):
        data = run("snapshot", ["-i"])
        refs = [ref for ref, info in data["refs"].items() if info["role"] == role]
        assert len(refs) == 1, data
        return "@" + refs[0]

    try:
        # Initialize the task's daemon and CDP supervisor before loading fixtures.
        run("snapshot")
        for _ in range(3):
            run("open", ["data:text/html," + quote(
                '<title>Hermes ref smoke</title>'
                '<button onclick="document.body.dataset.clicked=\'yes\'">Test</button>'
            )])
            ref = snapshot_ref("button")
            run("click", [ref])
            assert run("eval", ["document.body.dataset.clicked"])["result"] == "yes"

            run("open", ["data:text/html," + quote(
                '<title>Hermes ref smoke</title><label>Name <input></label>'
            )])
            ref = snapshot_ref("textbox")
            run("fill", [ref, "ref survived"])
            assert run("eval", ['document.querySelector("input").value'])["result"] == "ref survived"
        print("Routed snapshot refs: click and fill passed three times")
    finally:
        browser_tool._cleanup_single_browser_session(task_id)


if __name__ == "__main__":
    main()
