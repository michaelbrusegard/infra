import contextlib
import hashlib
import io
import json
import unittest
from unittest import mock

import hosts


def store_hash(*parts):
    return hashlib.sha256(json.dumps(parts, sort_keys=True).encode()).hexdigest()[:32]


class FakeStore:
    """Derivations whose paths depend on their content, as in a real store."""

    def __init__(self):
        self.derivations = {}

    def output(self, drv_path):
        return self.derivations[drv_path]["outputs"]["out"]["path"]

    def add(self, name, env, inputs=()):
        identity = store_hash(name, env, sorted(inputs))
        output = f"/nix/store/{store_hash('out', identity)}-{name}"
        path = f"/nix/store/{identity}-{name}.drv"
        self.derivations[path] = {
            "name": name,
            "system": "x86_64-linux",
            "builder": "/bin/sh",
            "args": ["-c", "build"],
            "env": {**env, "out": output},
            "outputs": {"out": {"path": output}},
            "inputDrvs": {input_path: {"outputs": ["out"]} for input_path in inputs},
            "inputSrcs": [],
        }
        return path

    def closure_of(self, root):
        closure, pending = {}, [root]
        while pending:
            path = pending.pop()
            if path not in closure:
                closure[path] = self.derivations[path]
                pending.extend(self.derivations[path]["inputDrvs"])
        return closure


class CompareTest(unittest.TestCase):
    def setUp(self):
        self.store = FakeStore()
        patcher = mock.patch.object(hosts, "run", side_effect=self.show)
        patcher.start()
        self.addCleanup(patcher.stop)

    def show(self, *command, cwd=None):
        return json.dumps({"derivations": self.store.closure_of(command[-1])})

    def system(self, rules, extra_inputs=()):
        firewall = self.store.add("firewall", {"rules": rules})
        references = [self.store.output(path) for path in (firewall, *extra_inputs)]
        return self.store.add(
            "system", {"paths": " ".join(references)}, [firewall, *extra_inputs]
        )

    def test_same_derivation_is_equal_without_reading_the_store(self):
        system = self.system("accept ssh; drop all")
        with mock.patch.object(hosts, "Closure") as closure:
            self.assertEqual(hosts.compare(system, system), ("EQUAL", [], []))
        closure.assert_not_called()

    def test_moved_tokens_are_order_only_and_name_the_reordered_derivation(self):
        base = self.system("accept ssh; drop all")
        head = self.system("drop all; accept ssh")
        self.assertNotEqual(base, head)
        self.assertEqual(hosts.compare(base, head), ("ORDER-ONLY", ["firewall"], []))

    def test_changed_token_is_reported_on_the_derivation_that_owns_it(self):
        base = self.system("accept ssh; drop all")
        head = self.system("accept https; drop all")
        status, reordered, changed = hosts.compare(base, head)
        self.assertEqual(status, "DIFFERENT")
        self.assertEqual(reordered, [])
        self.assertEqual(changed, [("firewall", {"rules": (["ssh"], ["https"])})])

    def test_repeated_token_counts(self):
        base = self.system("accept ssh")
        head = self.system("accept ssh ssh")
        status, _, changed = hosts.compare(base, head)
        self.assertEqual(status, "DIFFERENT")
        self.assertEqual(changed, [("firewall", {"rules": ([], ["ssh"])})])

    def test_added_input_is_reported(self):
        extra = self.store.add("extra", {"text": "new"})
        base = self.system("accept ssh")
        head = self.system("accept ssh", [extra])
        status, _, changed = hosts.compare(base, head)
        self.assertEqual(status, "DIFFERENT")
        names = [name for name, _ in changed]
        self.assertIn("extra", names)
        added = dict(changed)["extra"]["inputs"]
        self.assertEqual(added, ([], [extra.removeprefix("/nix/store/")]))

    def test_input_that_only_changed_content_is_followed_not_listed_as_swapped(self):
        base = self.system("accept ssh")
        head = self.system("accept https")
        _, _, changed = hosts.compare(base, head)
        self.assertNotIn("inputs", dict(changed)["firewall"])


class ReportTest(unittest.TestCase):
    def report(self, base, head, show_values=True, comparison=None):
        output = io.StringIO()
        with (
            contextlib.redirect_stdout(output),
            contextlib.redirect_stderr(io.StringIO()),
            mock.patch.object(hosts, "compare", return_value=comparison),
        ):
            succeeded = hosts.report("espresso", base, head, show_values)
        return succeeded, output.getvalue()

    def test_head_that_fails_to_evaluate_fails_the_run(self):
        succeeded, output = self.report(("/base.drv", ""), (None, "error: boom"))
        self.assertFalse(succeeded)
        self.assertIn("EVALUATION FAILED", output)

    def test_host_missing_on_the_base_is_new(self):
        error = "error: flake does not provide attribute 'nixosConfigurations.espresso'"
        succeeded, output = self.report((None, error), ("/head.drv", ""))
        self.assertTrue(succeeded)
        self.assertIn("NEW", output)

    def test_base_that_fails_for_another_reason_is_not_called_new(self):
        succeeded, output = self.report((None, "error: boom"), ("/head.drv", ""))
        self.assertTrue(succeeded)
        self.assertIn("NOT COMPARED", output)

    def test_names_only_prints_no_values(self):
        comparison = (
            "DIFFERENT",
            ["firewall"],
            [("unit", {"script": (["hunter2"], ["hunter3"])})],
        )
        _, shown = self.report(("/a.drv", ""), ("/b.drv", ""), True, comparison)
        _, named = self.report(("/a.drv", ""), ("/b.drv", ""), False, comparison)
        self.assertIn("hunter2", shown)
        self.assertNotIn("hunter", named)
        self.assertIn("changed: unit", named)
        self.assertIn("script", named)
        self.assertIn("reordered: firewall", named)


if __name__ == "__main__":
    unittest.main()
