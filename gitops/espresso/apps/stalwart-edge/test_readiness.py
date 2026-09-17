"""Offline readiness checks; native execution is qualified separately."""

import copy
import json
import unittest
from unittest.mock import MagicMock, patch

import readiness


class ReadinessTests(unittest.TestCase):
    def test_expression_preserves_sql_and_rejects_changed_match(self):
        readiness.expression({"else": "false", "match": {"0": {
            "if": "domain", "then": "SELECT\n1"}}}, "false", [("domain", "SELECT\n1")])
        with self.assertRaises(RuntimeError):
            readiness.expression({"else": "true"}, "false")
        with self.assertRaises(RuntimeError):
            readiness.expression({"else": "false", "match": [{"if": "x", "then": "true"}]}, "false")

    def test_empty_match_representations(self):
        for value in (None, {}, []):
            readiness.expression({"else": "false", "match": value}, "false")

    def test_readiness_permissions_are_read_only(self):
        self.assertEqual(len(readiness.READINESS_PERMISSIONS), len(set(readiness.READINESS_PERMISSIONS)))
        for permission in readiness.READINESS_PERMISSIONS:
            self.assertTrue(permission == "authenticate" or permission.endswith(("Get", "Query")))

    def filtering_objects(self, *, installed=True, bound=True, edge_filter=False):
        scripts = [{"name": "edge-rcpt-domain-guard"}]
        if installed:
            scripts.append({"name": readiness.AUTH_VERDICT_NAME, "isActive": True,
                            "contents": "canonical fixture script"})
        return {"SieveSystemScript": scripts, "MtaStageData": [{
            "script": {"else": repr(readiness.AUTH_VERDICT_NAME) if bound else "false"},
            "enableSpamFilter": {"else": "local_port == 25" if edge_filter else "false"},
        }], "SenderAuth": [{**{field: {"else": "relaxed"} for field in (
            "spfEhloVerify", "spfFromVerify", "dkimVerify", "dmarcVerify", "reverseIpVerify")},
            "dkimSignDomain": {"else": "false"}}]}

    def test_filtering_rollout_states(self):
        states = [(False, False, True), (True, False, True),
                  (True, True, True), (True, True, False)]
        with patch.object(readiness, "AUTH_VERDICT_PATH") as script:
            script.read_text.return_value = "canonical fixture script\n"
            for stage in ("legacy", "prepare", "backend"):
                for installed, bound, filtering in states:
                    with self.subTest(stage=stage, state=(installed, bound, filtering)), patch.dict(
                            readiness.os.environ, {"STALWART_EDGE_FILTERING_STAGE": stage}):
                        objects = self.filtering_objects(installed=installed, bound=bound,
                                                         edge_filter=filtering)
                        allowed = stage == "prepare" or (stage == "legacy" and not installed) or (
                            stage == "backend" and bound and not filtering)
                        if allowed:
                            readiness.check_filtering(objects)
                        else:
                            with self.assertRaises(RuntimeError):
                                readiness.check_filtering(objects)

    def test_filtering_rejects_unsafe_or_unknown_states(self):
        valid = self.filtering_objects()
        bad = [self.filtering_objects(bound=False), self.filtering_objects(installed=False)]
        for field in ("contents", "isActive", "name"):
            value = copy.deepcopy(valid)
            value["SieveSystemScript"][1][field] = False if field == "isActive" else "tampered"
            bad.append(value)
        value = copy.deepcopy(valid)
        value["SieveSystemScript"].append(copy.deepcopy(value["SieveSystemScript"][1]))
        bad.append(value)
        for field in valid["SenderAuth"][0]:
            value = copy.deepcopy(valid)
            value["SenderAuth"][0][field] = {"else": "disable"}
            bad.append(value)
        value = copy.deepcopy(valid)
        value["MtaStageData"][0]["script"]["match"] = [{"if": "true", "then": "false"}]
        bad.append(value)
        with patch.object(readiness, "AUTH_VERDICT_PATH") as script:
            script.read_text.return_value = "canonical fixture script"
            for stage in ("prepare", "backend"):
                with patch.dict(readiness.os.environ, {"STALWART_EDGE_FILTERING_STAGE": stage}):
                    for objects in bad:
                        with self.subTest(stage=stage, objects=objects), self.assertRaises(RuntimeError):
                            readiness.check_filtering(objects)
        with patch.dict(readiness.os.environ, {"STALWART_EDGE_FILTERING_STAGE": "typo"}):
            with self.assertRaises(RuntimeError):
                readiness.filtering_stage()

    def test_legacy_registry_reads_do_not_require_new_permissions(self):
        for stage in ("legacy", "prepare", "backend"):
            batches, methods = [], []
            conn = MagicMock()
            def request(_method, _path, body, _headers):
                calls = json.loads(body)["methodCalls"]
                batches.append(calls)
                methods.extend(call[0] for call in calls)
            def response(_limit):
                rows = []
                for method, arguments, tag in batches[-1]:
                    value = ({"ids": [], "position": 0, "total": 0} if method.endswith("/query") else
                             {"list": [{"id": "singleton"}] if arguments.get("ids") else []})
                    rows.append([method, value, tag])
                return json.dumps({"methodResponses": rows}).encode()
            conn.request.side_effect = request
            conn.getresponse.return_value.status = 200
            conn.getresponse.return_value.read.side_effect = response
            with patch.dict(readiness.os.environ, {"STALWART_EDGE_FILTERING_STAGE": stage,
                            "STALWART_EDGE_READINESS_TOKEN": "fixture"}), patch.object(
                            readiness, "LoopbackHTTPS", return_value=conn):
                readiness.read_registry()
            for kind in readiness.FILTERING_SINGLETONS:
                self.assertEqual(f"x:{kind}/get" in methods, stage != "legacy")

    def test_new_bootstrap_has_only_additional_read_permissions(self):
        self.assertIn("sysMtaStageDataGet", readiness.READINESS_PERMISSIONS)
        self.assertIn("sysSenderAuthGet", readiness.READINESS_PERMISSIONS)
        with patch.dict(readiness.os.environ, {}, clear=True):
            self.assertEqual(readiness.filtering_stage(), "legacy")

    def test_native_key_sets_do_not_include_disabled_entries(self):
        self.assertEqual(readiness.enabled_keys({"rcpt": True, "data": False}), {"rcpt"})

    def test_smtp_probe_never_submits_data(self):
        for reply in (550, 250):
            with self.subTest(reply=reply), patch.object(readiness.smtplib, "SMTP") as smtp:
                conn = MagicMock()
                smtp.return_value.__enter__.return_value = conn
                conn.ehlo.return_value = (250, b"ok")
                conn.has_extn.side_effect = lambda extension: extension == "starttls"
                conn.starttls.return_value = (220, b"ready")
                conn.mail.return_value = (250, b"ok")
                conn.rcpt.return_value = (reply, b"response")
                if reply == 550:
                    readiness.check_smtp()
                    self.assertEqual(conn.rcpt.call_count, 3)
                else:
                    with self.assertRaises(RuntimeError):
                        readiness.check_smtp()
                conn.data.assert_not_called()
                conn.sendmail.assert_not_called()
                self.assertEqual(conn._host, readiness.HOST)


if __name__ == "__main__":
    unittest.main()
