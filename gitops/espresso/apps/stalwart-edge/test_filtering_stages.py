"""Offline rollout ordering; not a substitute for native or controller proof."""

from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest


APP = Path(__file__).resolve().parent
ROOT = APP.parents[3]
INGRESS = Path("gitops/espresso/tofu/stalwart-edge/ingress.tf")
POD = Path("gitops/espresso/apps/stalwart-edge/statefulset.yaml")


class FilteringStagesTests(unittest.TestCase):
    def test_only_backward_compatible_preparation_is_active(self):
        self.assertNotIn("STALWART_EDGE_FILTERING_STAGE", (ROOT / POD).read_text())
        self.assertFalse((ROOT / INGRESS.parent / "filtering.tf").exists())
        self.assertIn('enable_spam_filter = { else = "local_port == 25", match = [] }',
                      (ROOT / INGRESS).read_text())
        config = (APP / "kustomization.yaml").read_text()
        self.assertIn("      - auth-verdict.sieve", config)
        self.assertIn("kustomize.toolkit.fluxcd.io/substitute: disabled", config)

    def test_queue_drain_request_is_unfiltered_and_metadata_only(self):
        request = json.loads((APP / "filtering-stages/queue-empty-request.json").read_text())
        self.assertEqual(request["methodCalls"], [["x:QueuedMessage/query",
                         {"limit": 1, "calculateTotal": True}, "queue-drain"]])

    def test_patches_separate_producer_filter_switch_and_readiness(self):
        with tempfile.TemporaryDirectory(prefix="edge-filtering-stages-") as directory:
            root = Path(directory)
            for name in (INGRESS, POD):
                (root / name).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, root / name)
            patches = sorted((APP / "filtering-stages").glob("*.patch"))
            self.assertEqual(len(patches), 4)
            for index, patch in enumerate(patches):
                subprocess.run(["git", "apply", "--check", str(patch)], cwd=root,
                               check=True, capture_output=True)
                subprocess.run(["git", "apply", str(patch)], cwd=root,
                               check=True, capture_output=True)
                ingress, pod = (root / INGRESS).read_text(), (root / POD).read_text()
                self.assertIn("value: backend" if index == 3 else "value: prepare", pod)
                self.assertIn('enable_spam_filter = { else = "' +
                              ("false" if index >= 2 else "local_port == 25") +
                              '", match = [] }', ingress)
                self.assertEqual("stalwart_sieve_system_script.auth_verdict.name" in ingress,
                                 index >= 1)
                self.assertIn("stalwart_sieve_system_script.rcpt_domain_guard.name", ingress)
                self.assertIn("http://127.0.0.1:8090/rcpt", ingress)
            definition = (root / INGRESS.parent / "filtering.tf").read_text()
            self.assertIn('file("${path.module}/../../apps/stalwart-edge/auth-verdict.sieve")', definition)


if __name__ == "__main__":
    unittest.main()
