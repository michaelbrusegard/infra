"""List the cluster resources that differ between a base revision and the working tree.

Flux applies whatever renders, so the rendered resources are what a review of
gitops/ has to look at: which were added, removed or changed, and for a
ConfigMap which keys.
"""

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOTS = [
    "gitops/espresso",
    "gitops/espresso/infrastructure/controllers",
    "gitops/espresso/infrastructure/configs",
    "gitops/espresso/apps",
    "gitops/espresso/projects",
]


def run(*command, cwd=None, stdin=None):
    return subprocess.run(
        command, cwd=cwd, input=stdin, check=True, capture_output=True, text=True
    ).stdout


def render(tree, root):
    if not (Path(tree) / root / "kustomization.yaml").exists():
        return {}
    rendered = run("kustomize", "build", root, cwd=tree)
    resources = {}
    for line in run("yq", "-o=json", "-I=0", ".", stdin=rendered).splitlines():
        resource = json.loads(line) if line.strip() else None
        if resource:
            metadata = resource.get("metadata", {})
            resources[
                (resource.get("kind"), metadata.get("namespace"), metadata.get("name"))
            ] = resource
    return resources


def label(key):
    kind, namespace, name = key
    return f"{kind} {namespace + '/' if namespace else ''}{name}"


def changed_keys(before, after):
    old, new = before.get("data") or {}, after.get("data") or {}
    keys = sorted(key for key in set(old) | set(new) if old.get(key) != new.get(key))
    return f" (keys: {', '.join(keys)})" if keys else ""


def describe(before, after):
    lines = []
    for key in sorted(set(before) | set(after), key=str):
        if key not in before:
            lines.append(f"  added    {label(key)}")
        elif key not in after:
            lines.append(f"  removed  {label(key)}")
        elif before[key] != after[key]:
            detail = (
                changed_keys(before[key], after[key]) if key[0] == "ConfigMap" else ""
            )
            lines.append(f"  changed  {label(key)}{detail}")
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("base", help="revision to compare the working tree against")
    arguments = parser.parse_args()

    head_tree = run("git", "rev-parse", "--show-toplevel").strip()
    with tempfile.TemporaryDirectory() as scratch:
        base_tree = str(Path(scratch) / "base")
        run(
            "git",
            "worktree",
            "add",
            "--detach",
            base_tree,
            arguments.base,
            cwd=head_tree,
        )
        try:
            for root in ROOTS:
                lines = describe(render(base_tree, root), render(head_tree, root))
                print(
                    f"{root}: {'identical' if not lines else f'{len(lines)} resource(s) differ'}"
                )
                print("\n".join(lines), end="\n" if lines else "")
        finally:
            run("git", "worktree", "remove", "--force", base_tree, cwd=head_tree)


if __name__ == "__main__":
    sys.exit(main())
