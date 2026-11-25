"""Update flake inputs, keeping every update that leaves the hosts working.

Updating everything at once is tried first. When that stops a host from
evaluating, each input is updated on its own and the ones that break
evaluation are held back at their locked revision. When a gate command is
given and fails on the result, the input that makes it fail is searched for
and held back too. One fast-moving input therefore cannot block security
updates to the rest.

Exits 0 when nothing was held back, 2 when the lock moved but something was
held back, and 1 when a required input could not move.
"""

import argparse
import concurrent.futures
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

LOCK = Path("flake.lock")
ERROR_LINES = 4
HELD_BACK = 2


def nix(*arguments):
    return subprocess.run(
        ["nix", *arguments],
        check=False,
        capture_output=True,
        text=True,
        stdin=subprocess.DEVNULL,
    )


def locked_revisions():
    nodes = json.loads(LOCK.read_text())["nodes"]
    revisions = {}
    for name, target in nodes["root"]["inputs"].items():
        node = nodes[target if isinstance(target, str) else target[0]]
        locked = node.get("locked", {})
        revisions[name] = locked.get("rev") or locked.get("narHash")
    return revisions


def last_error(stderr):
    lines = [line.strip() for line in stderr.splitlines() if line.strip()]
    errors = [index for index, line in enumerate(lines) if line.startswith("error:")]
    start = errors[-1] if errors else max(len(lines) - ERROR_LINES, 0)
    return " ".join(lines[start : start + ERROR_LINES])


def root_cause(output):
    """Pick the lines of a failed build or check that say what went wrong.

    A builder's own ERROR line names the cause; nix's "Cannot build" lines
    only repeat it for every derivation downstream.
    """
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    lines = [line for line in lines if "(ignored)" not in line]
    for marker in ("ERROR", "FAIL", "error:"):
        matching = [line for line in lines if marker in line]
        if matching:
            return " | ".join(matching[:ERROR_LINES])
    return " | ".join(lines[-ERROR_LINES:])


class Updater:
    def __init__(self, nix_arguments, jobs, gate, scratch):
        self.nix_arguments = nix_arguments
        self.jobs = jobs
        self.gate = gate
        self.original_lock = Path(scratch) / "original.lock"
        self.good_lock = Path(scratch) / "good.lock"
        shutil.copyfile(LOCK, self.original_lock)
        shutil.copyfile(LOCK, self.good_lock)
        self.held_back = {}

    def update(self, *inputs):
        return nix("flake", "update", *inputs, *self.nix_arguments)

    def evaluate(self, host):
        result = nix(
            "eval", *self.nix_arguments, "--raw", f".#{host['attribute']}.drvPath"
        )
        if result.returncode == 0:
            return None
        return f"{host['name']}: {last_error(result.stderr)}"

    def broken_hosts(self):
        matrix = nix("eval", *self.nix_arguments, "--json", ".#ci.hosts")
        if matrix.returncode != 0:
            return [f"the flake itself: {last_error(matrix.stderr)}"]
        with concurrent.futures.ThreadPoolExecutor(max_workers=self.jobs) as pool:
            failures = pool.map(self.evaluate, json.loads(matrix.stdout))
        return [failure for failure in failures if failure]

    def update_one_at_a_time(self, names):
        accepted = []
        for name in names:
            before = LOCK.read_bytes()
            result = self.update(name)
            failures = (
                [last_error(result.stderr)]
                if result.returncode != 0
                else self.broken_hosts()
            )
            if failures:
                self.held_back[name] = failures
                shutil.copyfile(self.good_lock, LOCK)
                print(f"held back  {name}", flush=True)
            else:
                if LOCK.read_bytes() != before:
                    accepted.append(name)
                shutil.copyfile(LOCK, self.good_lock)
                print(f"evaluates  {name}", flush=True)
        return accepted

    def passes_gate(self, names):
        """Lock exactly these updates on a clean tree and run the gate on it."""
        subprocess.run(["git", "checkout", "--quiet", "HEAD", "--", "."], check=True)
        shutil.copyfile(self.original_lock, LOCK)
        if names and self.update(*names).returncode != 0:
            return False, "nix flake update failed"
        result = subprocess.run(
            self.gate,
            shell=True,
            check=False,
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
        )
        return result.returncode == 0, root_cause(result.stdout + result.stderr)

    def first_breaking(self, names):
        """Return the input whose update first makes the gate fail.

        Assumes that once a prefix of the updates fails, every longer prefix
        fails too, which holds when one input is the cause.
        """
        low, high = 0, len(names) - 1
        failure = ""
        while low < high:
            middle = (low + high) // 2
            passed, output = self.passes_gate(names[: middle + 1])
            print(
                f"gate {'passes' if passed else 'fails'} with the first "
                f"{middle + 1} of {len(names)} updates",
                flush=True,
            )
            if passed:
                low = middle + 1
            else:
                high, failure = middle, output
        return names[low], failure

    def hold_back_what_fails_the_gate(self, names):
        while names:
            passed, output = self.passes_gate(names)
            if passed:
                print(f"gate passes with {len(names)} update(s)", flush=True)
                return names
            culprit, failure = self.first_breaking(names)
            self.held_back[culprit] = [failure or output]
            names = [name for name in names if name != culprit]
            print(f"held back  {culprit}", flush=True)
        self.passes_gate([])
        return names


def report(before, after, held_back):
    updated = sorted(name for name in after if before.get(name) != after[name])
    lines = [
        "## Flake input update",
        "",
        f"Updated {len(updated)} input(s): {', '.join(updated) or 'none'}.",
    ]
    if held_back:
        lines += ["", "Held back, each with what failed on its new revision:", ""]
        for name, failures in sorted(held_back.items()):
            lines.append(f"- **{name}**")
            lines += [f"  - `{failure[:400]}`" for failure in failures]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument(
        "--required",
        action="append",
        default=[],
        help="input that must not be held back; the run fails if it is",
    )
    parser.add_argument(
        "--gate",
        help="shell command that must pass on the updated tree, such as a build",
    )
    parser.add_argument(
        "--jobs", type=int, default=int(os.environ.get("UPDATE_JOBS", "4"))
    )
    parser.add_argument(
        "--nix-argument",
        action="append",
        default=[],
        help="extra argument for every nix call",
    )
    arguments = parser.parse_args()
    os.chdir(
        subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    )

    dirty = subprocess.run(
        ["git", "status", "--porcelain"], check=True, capture_output=True, text=True
    ).stdout
    if arguments.gate and dirty:
        sys.exit(
            "The gate resets the working tree between attempts. "
            "Commit or stash your changes first."
        )

    before = locked_revisions()
    with tempfile.TemporaryDirectory() as scratch:
        updater = Updater(
            arguments.nix_argument, arguments.jobs, arguments.gate, scratch
        )
        everything = updater.update()
        if everything.returncode == 0 and not updater.broken_hosts():
            after = locked_revisions()
            accepted = sorted(name for name in after if before.get(name) != after[name])
        else:
            print(
                "Updating everything at once breaks a host; "
                "trying one input at a time.",
                flush=True,
            )
            shutil.copyfile(updater.good_lock, LOCK)
            accepted = updater.update_one_at_a_time(sorted(before))
        if arguments.gate:
            updater.hold_back_what_fails_the_gate(accepted)
        held_back = updater.held_back

    summary = report(before, locked_revisions(), held_back)
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as output:
            output.write(summary)

    blocked = sorted(set(arguments.required) & set(held_back))
    if blocked:
        sys.exit(f"Required input(s) could not be updated: {', '.join(blocked)}")
    if held_back:
        sys.exit(HELD_BACK)


if __name__ == "__main__":
    main()
