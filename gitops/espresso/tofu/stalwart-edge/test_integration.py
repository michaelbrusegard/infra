"""Offline staging checks using the repository's existing kustomize/yq tools."""

import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent
ESPRESSO = ROOT.parent.parent
APP = ESPRESSO / "apps/stalwart-edge"
CONTROLLER = ESPRESSO / "infrastructure/configs/stalwart-edge-tofu"


def render(path):
    yaml = subprocess.check_output(["kustomize", "build", str(path)])
    return json.loads(subprocess.check_output(
        ["yq", "eval-all", "-o=json", "[.]", "-"], input=yaml))


def named(objects, kind, name):
    return next(obj for obj in objects
                if obj["kind"] == kind and obj["metadata"]["name"] == name)


class IntegrationContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = render(APP)
        cls.controller = render(CONTROLLER)
        cls.pod = named(cls.app, "StatefulSet", "stalwart-edge")["spec"]["template"]["spec"]

    def test_shared_vip_keeps_management_reachable_but_smtp_gated(self):
        smtp = named(self.app, "Service", "stalwart-edge")
        management = named(self.app, "Service", "stalwart-edge-management")
        self.assertFalse(smtp["spec"]["publishNotReadyAddresses"])
        self.assertTrue(management["spec"]["publishNotReadyAddresses"])
        self.assertEqual([p["port"] for p in smtp["spec"]["ports"]], [25])
        self.assertEqual([p["port"] for p in management["spec"]["ports"]], [443])
        for key in ("lbipam.cilium.io/ips", "lbipam.cilium.io/sharing-key"):
            self.assertEqual(smtp["metadata"]["annotations"][key],
                             management["metadata"]["annotations"][key])
        self.assertEqual(smtp["spec"]["selector"], management["spec"]["selector"])
        self.assertEqual(smtp["spec"]["externalTrafficPolicy"], "Local")
        self.assertEqual(management["spec"]["externalTrafficPolicy"], "Local")
        self.assertNotIn("external-dns.alpha.kubernetes.io/hostname", smtp["metadata"]["annotations"])
        self.assertEqual(management["metadata"]["annotations"]["external-dns.alpha.kubernetes.io/hostname"],
                         "edge.asgard.michaelbrusegard.com")
        self.assertFalse(any(obj["kind"] in ("HTTPRoute", "DNSEndpoint") for obj in self.app))

    def test_management_is_flux_only_and_no_direct_internet_delivery(self):
        policy = named(self.app, "CiliumNetworkPolicy", "stalwart-edge")["spec"]
        for rule in policy["ingress"]:
            ports = {p["port"] for group in rule["toPorts"] for p in group["ports"]}
            self.assertNotIn("8080", ports)
            if "443" in ports:
                self.assertNotIn("fromEntities", rule)
                self.assertEqual(rule["fromEndpoints"], [{"matchLabels": {
                    "k8s:io.kubernetes.pod.namespace": "flux-system"}}])
        allowed = {p["port"] for rule in policy["egress"]
                   for group in rule["toPorts"] for p in group["ports"]}
        self.assertEqual(allowed, {"53", "24", "443", "465"})
        self.assertTrue(all("toEntities" not in rule for rule in policy["egress"]))
        fqdn = {entry["matchName"] for rule in policy["egress"]
                for entry in rule.get("toFQDNs", [])}
        self.assertEqual(fqdn, {"backend.manafishrov.com", "smtp.resend.com"})

    def test_distinct_secret_consumers_and_hardened_pod(self):
        self.assertFalse(self.pod["automountServiceAccountToken"])
        self.assertNotIn("shareProcessNamespace", self.pod)
        containers = {c["name"]: c for c in self.pod["containers"]}
        self.assertEqual(set(containers), {"stalwart", "policy"})
        for container in containers.values():
            self.assertTrue(container["securityContext"]["readOnlyRootFilesystem"])
            self.assertFalse(container["securityContext"]["allowPrivilegeEscalation"])
            self.assertNotIn("envFrom", container)
            self.assertIn("@sha256:", container["image"])
            self.assertIn("limits", container["resources"])
        main = {item["name"] for item in containers["stalwart"]["env"]}
        self.assertEqual(main, {"STALWART_RESEND_API_KEY", "STALWART_RECOVERY_ADMIN"})
        policy = {item["name"]: item for item in containers["policy"]["env"]}
        self.assertNotIn("STALWART_TOKEN", policy)
        self.assertEqual(policy["STALWART_MANAFISH_SYNC_TOKEN"]["valueFrom"]["secretKeyRef"]["name"], "stalwart-edge-reader")
        self.assertEqual(policy["STALWART_EDGE_READINESS_TOKEN"]["valueFrom"]["secretKeyRef"]["name"], "stalwart-edge-readiness")
        self.assertEqual(containers["policy"]["readinessProbe"]["exec"]["command"],
                         ["python3", "/policy/readiness.py"])

    def test_recovery_is_explicit_and_normal_health_verifies_tls(self):
        scripts = named(self.app, "ConfigMap", "stalwart-edge-entrypoint")["data"]
        entry = scripts["entrypoint.sh"]
        self.assertIn("unset STALWART_RECOVERY_ADMIN STALWART_RECOVERY_MODE", entry)
        self.assertIn("${STALWART_RECOVERY_ADMIN:?", entry)
        self.assertIn("/var/lib/stalwart/.bootstrapped", entry)
        health = scripts["health.sh"]
        self.assertIn("--resolve edge.asgard.michaelbrusegard.com:443:127.0.0.1", health)
        self.assertIn("--proto '=https'", health)
        self.assertNotIn("--insecure", health)
        self.assertNotIn(" -k", health)
        for source in scripts.values():
            subprocess.run(["sh", "-n"], input=source.encode(), check=True)

    def test_policy_code_is_generated_without_legacy_reconciler(self):
        bundled = named(self.app, "ConfigMap", "stalwart-edge-policy")["data"]
        for file in ("policy.py", "policy.sql", "readiness.py"):
            self.assertEqual(bundled[file], (APP / file).read_text())
        names = {obj["metadata"]["name"] for obj in self.app}
        self.assertTrue(names.isdisjoint({"stalwart-edge-plan", "stalwart-edge-reconciler", "stalwart-edge-directory-sync"}))
        runtime = named(self.app, "ConfigMap", "stalwart-edge-policy-runtime")["data"]
        self.assertEqual(runtime["STALWART_EDGE_POLICY_QUALIFIED"], "1")
        self.assertNotIn("inventory.json", runtime)
        self.assertEqual(runtime["STALWART_EDGE_POLICY_INVENTORY"], "/policy-inventory/inventory.json")
        inventory = next(v for v in self.pod["volumes"] if v["name"] == "policy-inventory")
        self.assertEqual(inventory["secret"]["secretName"], "stalwart-edge-inventory")

    def test_controller_adopts_personal_root_state_with_pinned_mirror(self):
        tf = named(self.controller, "Terraform", "stalwart-edge")
        self.assertEqual(tf["metadata"]["namespace"], "flux-system")
        self.assertFalse(tf["spec"]["suspend"])
        self.assertEqual(tf["spec"]["sourceRef"]["name"], "flux-system")
        self.assertEqual(tf["spec"]["path"], "./gitops/espresso/tofu/stalwart-edge")
        runner = tf["spec"]["runnerPodTemplate"]["spec"]
        self.assertEqual(runner["nodeSelector"]["kubernetes.io/arch"], "amd64")
        self.assertNotIn("envFrom", runner)
        token = next(e for e in runner["env"] if e["name"] == "STALWART_TOKEN")
        self.assertEqual(token["valueFrom"]["secretKeyRef"], {"name": "stalwart-edge-tofu", "key": "STALWART_TOKEN"})
        self.assertEqual(tf["spec"]["varsFrom"], [{"kind": "Secret", "name": "stalwart-edge-tofu", "varsKeys": [
            "bootstrap_internal_domain_id", "bootstrap_certificate_id", "bootstrap_https_listener_id", "bootstrap_webui_id",
        ]}])
        script = runner["initContainers"][0]["command"][-1]
        self.assertIn("version=0.2.3", script)
        self.assertIn("9b4b3dc07a73055d7116fc426c6009de86479df7776ab23b6795132eeca8c119", script)
        self.assertIn("sha256sum -c -", script)
        subprocess.run(["sh", "-n"], input=script.encode(), check=True)

    def test_single_configuration_writer_permission_source(self):
        permissions = json.loads((ROOT / "bootstrap-permissions.json").read_text())
        self.assertEqual(len(permissions), 56)
        self.assertEqual(permissions, sorted(set(permissions)))
        self.assertIn("actionReloadSettings", permissions)
        self.assertIn("actionReloadTlsCertificates", permissions)
        self.assertIn("sysActionCreate", permissions)
        self.assertNotIn("sysActionGet", permissions)
        self.assertEqual([p for p in permissions if p.endswith("Query")], ["sysQueuedMessageQuery"])
        self.assertIn("sysQueuedMessageGet", permissions)
        self.assertIn('jsondecode(file("${path.module}/bootstrap-permissions.json"))',
                      (ROOT / "outputs.tf").read_text())


if __name__ == "__main__":
    unittest.main()
