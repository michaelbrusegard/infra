"""Update flake inputs, keeping every update that leaves all hosts evaluating.

Updating everything at once is tried first. When that breaks a host, each
input is updated on its own instead and one that breaks evaluation is held
back at its locked revision, so a single fast-moving input cannot block
security updates to the rest.
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


def nix(*arguments, check=True):
    return subprocess.run(
        ["nix", *arguments],
        check=check,
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


def evaluate(host, nix_arguments):
    result = nix(
        "eval",
        *nix_arguments,
        "--raw",
        f".#{host['attribute']}.drvPath",
        check=False,
    )
    if result.returncode == 0:
        return None
    return f"{host['name']}: {last_error(result.stderr)}"


def broken_hosts(nix_arguments, jobs):
    """Return why hosts fail to evaluate, or an empty list when all do."""
    matrix = nix("eval", *nix_arguments, "--json", ".#ci.hosts", check=False)
    if matrix.returncode != 0:
        return [f"the flake itself: {last_error(matrix.stderr)}"]
    hosts = json.loads(matrix.stdout)
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        failures = pool.map(lambda host: evaluate(host, nix_arguments), hosts)
    return [failure for failure in failures if failure]


def update(nix_arguments, *inputs):
    return nix("flake", "update", *inputs, *nix_arguments, check=False)


def update_one_at_a_time(names, nix_arguments, jobs, good_lock):
    held_back = {}
    for name in names:
        result = update(nix_arguments, name)
        failures = (
            [last_error(result.stderr)]
            if result.returncode != 0
            else broken_hosts(nix_arguments, jobs)
        )
        if failures:
            held_back[name] = failures
            shutil.copyfile(good_lock, LOCK)
            print(f"held back  {name}", flush=True)
        else:
            shutil.copyfile(LOCK, good_lock)
            print(f"updated    {name}", flush=True)
    return held_back


def report(before, after, held_back):
    lines = ["## Flake input update", ""]
    updated = sorted(name for name in after if before.get(name) != after[name])
    lines.append(f"Updated {len(updated)} input(s): {', '.join(updated) or 'none'}.")
    if held_back:
        lines += [
            "",
            "Held back because a host stops evaluating with the new revision:",
            "",
        ]
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

    before = locked_revisions()
    held_back = {}
    with tempfile.TemporaryDirectory() as scratch:
        good_lock = Path(scratch) / "flake.lock"
        shutil.copyfile(LOCK, good_lock)

        everything = update(arguments.nix_argument)
        if everything.returncode != 0 or broken_hosts(
            arguments.nix_argument, arguments.jobs
        ):
            print(
                "Updating everything at once breaks a host; trying one input at a time.",
                flush=True,
            )
            shutil.copyfile(good_lock, LOCK)
            held_back = update_one_at_a_time(
                sorted(before), arguments.nix_argument, arguments.jobs, good_lock
            )

    summary = report(before, locked_revisions(), held_back)
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as output:
            output.write(summary)

    blocked = sorted(set(arguments.required) & set(held_back))
    if blocked:
        sys.exit(f"Required input(s) could not be updated: {', '.join(blocked)}")


if __name__ == "__main__":
    main()
