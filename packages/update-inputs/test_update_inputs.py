import contextlib
import io
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import update_inputs


def lock_with(revisions):
    nodes = {"root": {"inputs": {name: name for name in revisions}}}
    for name, revision in revisions.items():
        nodes[name] = {"locked": {"rev": revision}}
    return json.dumps({"nodes": nodes, "root": "root", "version": 7})


def completed(returncode=0, stderr=""):
    return subprocess.CompletedProcess([], returncode, "", stderr)


class InTemporaryCheckout(unittest.TestCase):
    """Runs in a directory holding a lock whose inputs all sit at revision old."""

    inputs = ("alpha", "beta", "gamma", "delta", "epsilon")

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.addCleanup(os.chdir, Path.cwd())
        os.chdir(directory.name)
        self.scratch = Path(directory.name) / "scratch"
        self.scratch.mkdir()
        self.revisions = dict.fromkeys(self.inputs, "old")
        self.write_lock()
        self.updater = update_inputs.Updater([], 1, "gate", self.scratch)
        self.updater.update = self.update

    def write_lock(self):
        update_inputs.LOCK.write_text(lock_with(self.revisions))

    def update(self, *names):
        self.revisions = json.loads(update_inputs.LOCK.read_text())["nodes"]
        self.revisions = {
            name: self.revisions[name]["locked"]["rev"] for name in self.inputs
        }
        for name in names or self.inputs:
            self.revisions[name] = "new"
        self.write_lock()
        return completed()

    def updated(self):
        revisions = update_inputs.locked_revisions()
        return sorted(name for name, revision in revisions.items() if revision == "new")

    def quietly(self, function, *arguments):
        with contextlib.redirect_stdout(io.StringIO()):
            return function(*arguments)


class EvaluationTest(InTemporaryCheckout):
    def broken_when(self, *breaking):
        def broken_hosts():
            return [
                f"host: {name} broke" for name in breaking if name in self.updated()
            ]

        self.updater.broken_hosts = broken_hosts

    def test_inputs_that_break_evaluation_are_held_back_and_the_rest_move(self):
        self.broken_when("beta", "delta")
        accepted = self.quietly(self.updater.update_one_at_a_time, list(self.inputs))
        self.assertEqual(accepted, ["alpha", "gamma", "epsilon"])
        self.assertEqual(self.updated(), ["alpha", "epsilon", "gamma"])
        self.assertEqual(
            self.updater.held_back,
            {"beta": ["host: beta broke"], "delta": ["host: delta broke"]},
        )

    def test_input_whose_update_command_fails_is_held_back_with_its_error(self):
        self.broken_when()
        real_update = self.updater.update

        def update(*names):
            if names == ("beta",):
                return completed(1, "warning: noise\nerror: cannot fetch beta\n")
            return real_update(*names)

        self.updater.update = update
        self.quietly(self.updater.update_one_at_a_time, list(self.inputs))
        self.assertEqual(self.updater.held_back, {"beta": ["error: cannot fetch beta"]})
        self.assertNotIn("beta", self.updated())

    def test_input_already_at_its_newest_revision_is_not_counted_as_updated(self):
        self.broken_when()
        self.revisions["alpha"] = "new"
        self.write_lock()
        accepted = self.quietly(self.updater.update_one_at_a_time, ["alpha", "beta"])
        self.assertEqual(accepted, ["beta"])


class GateTest(InTemporaryCheckout):
    def gate_fails_with(self, *breaking):
        self.gate_runs = 0

        def run(command, **_):
            if command[0] == "git":
                return completed()
            self.gate_runs += 1
            failing = [name for name in breaking if name in self.updated()]
            if failing:
                return subprocess.CompletedProcess(
                    command, 1, f"ERROR: {failing[0]} does not build\n", ""
                )
            return subprocess.CompletedProcess(command, 0, "", "")

        patcher = mock.patch.object(update_inputs.subprocess, "run", side_effect=run)
        patcher.start()
        self.addCleanup(patcher.stop)

    def hold_back(self):
        return self.quietly(
            self.updater.hold_back_what_fails_the_gate, list(self.inputs)
        )

    def test_passing_gate_keeps_every_update(self):
        self.gate_fails_with()
        self.assertEqual(self.hold_back(), list(self.inputs))
        self.assertEqual(self.updated(), sorted(self.inputs))
        self.assertEqual(self.updater.held_back, {})
        self.assertEqual(self.gate_runs, 1)

    def test_each_single_culprit_is_found_wherever_it_sits(self):
        for culprit in self.inputs:
            with self.subTest(culprit=culprit):
                self.updater.held_back = {}
                self.gate_fails_with(culprit)
                kept = self.hold_back()
                self.assertEqual(kept, [n for n in self.inputs if n != culprit])
                self.assertEqual(self.updated(), sorted(kept))
                self.assertEqual(
                    self.updater.held_back,
                    {culprit: [f"ERROR: {culprit} does not build"]},
                )

    def test_two_culprits_are_both_held_back(self):
        self.gate_fails_with("beta", "epsilon")
        kept = self.hold_back()
        self.assertEqual(kept, ["alpha", "gamma", "delta"])
        self.assertEqual(self.updated(), sorted(kept))
        self.assertEqual(sorted(self.updater.held_back), ["beta", "epsilon"])

    def test_gate_that_fails_without_any_update_stops_without_blaming_an_input(self):
        self.gate_fails_with()
        self.gate_runs = 0

        def run(command, **_):
            if command[0] == "git":
                return completed()
            self.gate_runs += 1
            return subprocess.CompletedProcess(
                command, 1, "ERROR: tree is broken\n", ""
            )

        update_inputs.subprocess.run.side_effect = run
        with self.assertRaisesRegex(
            update_inputs.BrokenBaselineError, "ERROR: tree is broken"
        ):
            self.hold_back()
        self.assertEqual(self.updated(), [])
        self.assertEqual(self.updater.held_back, {})
        self.assertEqual(self.gate_runs, 2)

    def test_every_input_failing_the_gate_holds_them_all_back(self):
        self.gate_fails_with(*self.inputs)
        self.assertEqual(self.hold_back(), [])
        self.assertEqual(self.updated(), [])
        self.assertEqual(sorted(self.updater.held_back), sorted(self.inputs))

    def test_search_is_logarithmic(self):
        self.gate_fails_with("epsilon")
        self.hold_back()
        self.assertLessEqual(self.gate_runs, 6)


class MessageTest(unittest.TestCase):
    def test_last_error_starts_at_the_final_error_line(self):
        stderr = "error: first\ntrace\nerror: second\n  at file.nix:3\n"
        self.assertEqual(
            update_inputs.last_error(stderr), "error: second at file.nix:3"
        )

    def test_last_error_falls_back_to_the_tail(self):
        stderr = "\n".join(f"line {number}" for number in range(10))
        self.assertEqual(
            update_inputs.last_error(stderr), "line 6 line 7 line 8 line 9"
        )

    def test_root_cause_prefers_the_builder_line_over_nix_repeating_it(self):
        output = (
            "building\n"
            "ERROR: patch does not apply\n"
            "error: Cannot build '/nix/store/x.drv'\n"
            "error: Cannot build '/nix/store/y.drv'\n"
        )
        self.assertEqual(
            update_inputs.root_cause(output), "ERROR: patch does not apply"
        )

    def test_root_cause_skips_ignored_errors(self):
        output = "error (ignored): cache miss\nerror: attribute 'x' missing\n"
        self.assertEqual(
            update_inputs.root_cause(output), "error: attribute 'x' missing"
        )

    def test_report_lists_updates_and_what_was_held_back(self):
        before = {"alpha": "old", "beta": "old"}
        after = {"alpha": "new", "beta": "old"}
        summary = update_inputs.report(before, after, {"beta": ["x" * 500]})
        self.assertIn("Updated 1 input(s): alpha.", summary)
        self.assertIn("- **beta**", summary)
        self.assertIn(f"`{'x' * 400}`", summary)
        self.assertNotIn("x" * 401, summary)

    def test_report_without_changes_says_none(self):
        summary = update_inputs.report({"alpha": "old"}, {"alpha": "old"}, {})
        self.assertIn("Updated 0 input(s): none.", summary)
        self.assertNotIn("Held back", summary)


class LockTest(unittest.TestCase):
    def test_locked_revisions_follow_inputs_and_fall_back_to_the_hash(self):
        lock = {
            "nodes": {
                "root": {"inputs": {"nixpkgs": "nixpkgs_2", "tarball": "tarball"}},
                "nixpkgs_2": {"locked": {"rev": "abc"}},
                "tarball": {"locked": {"narHash": "sha256-xyz"}},
                "nixpkgs": {"locked": {"rev": "transitive"}},
            }
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "flake.lock"
            path.write_text(json.dumps(lock))
            with mock.patch.object(update_inputs, "LOCK", path):
                self.assertEqual(
                    update_inputs.locked_revisions(),
                    {"nixpkgs": "abc", "tarball": "sha256-xyz"},
                )


if __name__ == "__main__":
    unittest.main()
