"""Compare host derivations between a base revision and the working tree.

Module merge order changes with almost any refactor, so two systems that are
the same in substance rarely share a derivation path. Each environment value
is therefore compared as a multiset of tokens: a host is EQUAL when the
derivation path matches, ORDER-ONLY when only the order of tokens moved, and
DIFFERENT otherwise, in which case the derivations that really changed are
listed with the tokens found on one side only.
"""

import argparse
import collections
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

TOKEN_SEPARATOR = re.compile(r"[\s\"',;:\[\]{}()=\\]+")
STORE_PATH = re.compile(r"/nix/store/([0-9a-z]{32})-([^\s\"',;:\[\]{}()=\\$/]*)")
REFERENCE = re.compile(r"<[0-9a-f]{24}!")
STORE_PREFIX = "/nix/store/"
HASH_END = len(STORE_PREFIX) + 32
SHOWN_TOKENS = 8


def run(*command, cwd=None):
    return subprocess.run(
        command, cwd=cwd, check=True, capture_output=True, text=True
    ).stdout


def store_path(path):
    return path if path.startswith(STORE_PREFIX) else STORE_PREFIX + path


def digest(*parts):
    return hashlib.sha256(json.dumps(parts, sort_keys=True).encode()).hexdigest()


class Closure:
    def __init__(self, drv_path):
        shown = json.loads(run("nix", "derivation", "show", "-r", drv_path))
        derivations = shown.get("derivations", shown)
        self.derivations = {store_path(path): drv for path, drv in derivations.items()}
        self.owner_of_output = {}
        for path, drv in self.derivations.items():
            for output_name, output in drv.get("outputs", {}).items():
                if output.get("path"):
                    output_hash = store_path(output["path"])[
                        len(STORE_PREFIX) : HASH_END
                    ]
                    self.owner_of_output[output_hash] = (path, output_name)
        self.identity = {}
        self.exact = {}
        self.tokens = {}
        self.token_digest = {}

    def name(self, path):
        return self.derivations[path].get("name")

    def inputs(self, path):
        drv = self.derivations[path]
        inputs = drv.get("inputDrvs")
        if inputs is None:
            inputs = drv.get("inputs", {}).get("drvs", {})
        return [store_path(input_path) for input_path in inputs]

    def sources(self, path):
        drv = self.derivations[path]
        sources = drv.get("inputSrcs")
        if sources is None:
            sources = drv.get("inputs", {}).get("srcs", [])
        return sorted(store_path(source) for source in sources)

    def with_stable_references(self, path, text):
        def replace(match):
            owner = self.owner_of_output.get(match.group(1))
            if owner is None:
                return match.group(0)
            owner_path, output_name = owner
            if owner_path == path:
                return f"<self!{output_name}>"
            if owner_path not in self.identity:
                return match.group(0)
            return f"<{self.identity[owner_path]}!{output_name}>"

        return STORE_PATH.sub(replace, text)

    def resolve(self, root):
        pending = [(root, False)]
        while pending:
            path, inputs_resolved = pending.pop()
            if path in self.identity:
                continue
            if inputs_resolved:
                self.resolve_one(path)
                continue
            pending.append((path, True))
            pending.extend(
                (input_path, False)
                for input_path in self.inputs(path)
                if input_path not in self.identity
            )
        return self.identity[root]

    def resolve_one(self, path):
        drv = self.derivations[path]
        environment = dict(drv.get("env", {}))
        if drv.get("structuredAttrs") is not None:
            environment["__structured"] = json.dumps(
                drv["structuredAttrs"], sort_keys=True
            )
        environment["__builder"] = str(drv.get("builder"))
        environment["__args"] = "\x00".join(drv.get("args", []))
        text = {
            key: self.with_stable_references(
                path, value if isinstance(value, str) else json.dumps(value)
            )
            for key, value in environment.items()
        }
        fixed = [drv.get("name"), drv.get("system"), self.sources(path)]
        tokens = {
            key: sorted(token for token in TOKEN_SEPARATOR.split(value) if token)
            for key, value in text.items()
        }
        self.exact[path] = digest(fixed, text)
        self.tokens[path] = tokens
        self.token_digest[path] = digest(fixed, tokens)
        input_identities = sorted(
            self.identity[input_path] for input_path in self.inputs(path)
        )
        self.identity[path] = digest(self.token_digest[path], input_identities)[:24]


def without_reference_identities(tokens):
    return collections.Counter(REFERENCE.sub("<input!", token) for token in tokens)


def one_sided_tokens(before, after):
    """Return the tokens on one side only, ignoring which input a reference points at.

    A derivation whose inputs changed has different references but is not itself
    the cause, so only derivations with a difference of their own are reported.
    """
    difference = {}
    for key in sorted(set(before) | set(after)):
        removed = without_reference_identities(before.get(key, []))
        added = without_reference_identities(after.get(key, []))
        if removed != added:
            difference[key] = (
                list((removed - added).elements())[:SHOWN_TOKENS],
                list((added - removed).elements())[:SHOWN_TOKENS],
            )
    return difference


def inputs_by_name(closure, path):
    grouped = collections.defaultdict(dict)
    for input_path in closure.inputs(path):
        grouped[closure.name(input_path)][closure.identity[input_path]] = input_path
    return grouped


def compare(base_drv, head_drv):
    if base_drv == head_drv:
        return "EQUAL", [], []
    base, head = Closure(base_drv), Closure(head_drv)
    same_content = base.resolve(base_drv) == head.resolve(head_drv)
    reordered = set()
    changed = []
    visited = set()
    pending = [(base_drv, head_drv)]
    while pending:
        base_path, head_path = pending.pop()
        if base_path == head_path or (base_path, head_path) in visited:
            continue
        visited.add((base_path, head_path))
        if base.token_digest[base_path] != head.token_digest[head_path]:
            difference = one_sided_tokens(
                base.tokens[base_path], head.tokens[head_path]
            )
            if difference:
                changed.append((base.name(base_path), difference))
        elif base.exact[base_path] != head.exact[head_path]:
            reordered.add(base.name(base_path))
        base_inputs = inputs_by_name(base, base_path)
        head_inputs = inputs_by_name(head, head_path)
        for name in sorted(set(base_inputs) | set(head_inputs)):
            before, after = base_inputs.get(name, {}), head_inputs.get(name, {})
            pending.extend(
                (before[identity], after[identity])
                for identity in before
                if identity in after
            )
            only_before = [
                path for identity, path in before.items() if identity not in after
            ]
            only_after = [
                path for identity, path in after.items() if identity not in before
            ]
            if len(only_before) == 1 and len(only_after) == 1:
                pending.append((only_before[0], only_after[0]))
            elif only_before or only_after:
                changed.append(
                    (
                        name,
                        {
                            "inputs": (
                                [Path(p).name for p in only_before],
                                [Path(p).name for p in only_after],
                            )
                        },
                    )
                )
    return ("ORDER-ONLY" if same_content else "DIFFERENT"), sorted(reordered), changed


def evaluate(tree, attribute, nix_arguments):
    try:
        return run(
            "nix", "eval", *nix_arguments, "--raw", f".#{attribute}.drvPath", cwd=tree
        ).strip()
    except subprocess.CalledProcessError as error:
        sys.stderr.write(error.stderr[-2000:])
        return None


def report(host, base_drv, head_drv):
    if head_drv is None:
        print(f"{host}: EVALUATION FAILED on the working tree")
        return False
    if base_drv is None:
        print(f"{host}: NEW (does not evaluate on the base revision)")
        return True
    status, reordered, changed = compare(base_drv, head_drv)
    print(f"{host}: {status}")
    if reordered:
        print(f"  reordered: {', '.join(reordered)}")
    for name, difference in changed:
        print(f"  changed: {name}")
        for key, (removed, added) in difference.items():
            print(f"    {key}: -{removed} +{added}")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("base", help="revision to compare the working tree against")
    parser.add_argument(
        "hosts", nargs="*", help="hosts to compare (default: every host in ci.hosts)"
    )
    parser.add_argument(
        "--nix-argument",
        action="append",
        default=[],
        help="extra argument for nix eval",
    )
    arguments = parser.parse_args()

    head_tree = run("git", "rev-parse", "--show-toplevel").strip()
    matrix = json.loads(
        run(
            "nix",
            "eval",
            *arguments.nix_argument,
            "--json",
            ".#ci.hosts",
            cwd=head_tree,
        )
    )
    attributes = {host["name"]: host["attribute"] for host in matrix}
    hosts = arguments.hosts or sorted(attributes)
    unknown = [host for host in hosts if host not in attributes]
    if unknown:
        sys.exit(f"Unknown host(s) {unknown}; ci.hosts lists {sorted(attributes)}")

    succeeded = True
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
            for host in hosts:
                base_drv = evaluate(base_tree, attributes[host], arguments.nix_argument)
                head_drv = evaluate(head_tree, attributes[host], arguments.nix_argument)
                succeeded = report(host, base_drv, head_drv) and succeeded
        finally:
            run("git", "worktree", "remove", "--force", base_tree, cwd=head_tree)
    sys.exit(0 if succeeded else 1)


if __name__ == "__main__":
    main()
