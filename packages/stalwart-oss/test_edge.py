"""Offline fixture safety/contract checks; these do not qualify native SMTP."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import edge


class FixtureTests(unittest.TestCase):
    def test_hash_mismatch_is_rejected(self):
        with patch.object(edge, 'binary_hash', return_value='0' * 64):
            with self.assertRaisesRegex(AssertionError, 'Approved binary hash mismatch'):
                edge.verify_binary()

    def test_approved_hash_is_accepted(self):
        with patch.object(edge, 'binary_hash', return_value=edge.APPROVED_SHA256):
            self.assertEqual(edge.verify_binary(), edge.APPROVED_SHA256)

    def test_hash_failure_never_launches_process(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with (patch.object(edge.sys, 'argv', ['edge.py']),
                  patch.object(edge.tempfile, 'mkdtemp', return_value=str(root)),
                  patch.object(edge, 'binary_hash', return_value='0' * 64),
                  patch.object(edge.subprocess, 'run') as run,
                  patch.object(edge.subprocess, 'Popen') as popen,
                  patch('builtins.print')):
                self.assertEqual(edge.main(), 1)
                run.assert_not_called()
                popen.assert_not_called()
            report = json.loads((root / 'report.json').read_text())
            self.assertFalse(report['qualified'])
            self.assertEqual(report['tests'], {})

    def test_sql_is_bound_and_served_domain_gated(self):
        sql = 'SELECT EXISTS(SELECT 1\nWHERE local = ?1)'
        expression = edge.relay_expression(sql)
        self.assertEqual(expression['else'], 'false')
        clause = expression['match']['0']
        self.assertEqual(clause['if'], "rcpt_domain == 'mail.test'")
        self.assertEqual(clause['then'],
                         'sql_query(\'edge-recipients\', "' + sql + '", [rcpt]) == 1')
        self.assertIn('\n', clause['then'])
        for unsafe in ('SELECT "column"', r'SELECT \\n'):
            with self.assertRaisesRegex(AssertionError, 'Unsafe SQL expression'):
                edge.relay_expression(unsafe)

    def test_static_guard_has_no_io_and_preserves_smtp_code(self):
        script = edge.guard_contents()
        self.assertIn('reject "550 5.7.1 ', script)
        self.assertIn('envelope :domain :is "to" "mail.test"', script)
        self.assertNotIn('sql', script)
        self.assertNotIn('http', script)

    def test_readiness_requires_both_guards(self):
        hook = {'url': 'http://127.0.0.1:8090/rcpt', 'enable': {'else': 'true'},
                'stages': {'rcpt': True}, 'tempFailOnError': True}
        script = {'name': edge.GUARD, 'isActive': True, 'contents': edge.guard_contents()}

        class Client:
            enabled = True

            def jmap(self, method, arguments):
                return {'list': [{'script': {'else': repr(edge.GUARD) if self.enabled else 'false'}}]}

        client = Client()
        data = {'MtaHook': [hook], 'SieveSystemScript': [script]}
        with patch.object(edge, 'objects', side_effect=lambda client, kind: data[kind]):
            self.assertTrue(edge.guard_settings_ready(client))
            data['MtaHook'] = []
            self.assertFalse(edge.guard_settings_ready(client))
            data['MtaHook'] = [hook]
            client.enabled = False
            self.assertFalse(edge.guard_settings_ready(client))
            data['MtaHook'] = []
            self.assertFalse(edge.guard_settings_ready(client))

    def test_v2_policy_exact_address_and_seed_contract_offline(self):
        # Explicit unit-level records, never presented as native qualification.
        policy = edge.load_policy()
        source = policy.Source('fixture', 'https://backend.fixture.test', 'FIXTURE_TOKEN',
                               ('mail.test',), '127.0.0.1', 24, 'localhost')
        with tempfile.TemporaryDirectory() as directory:
            index = policy.Index(Path(directory) / 'index.sqlite3', [source],
                                 inventory={'fixture': ['alice@mail.test']})
            index.initialize()
            self.assertFalse(index.healthy())
            index.record('fixture', 'alice@mail.test', policy.Outcome.POSITIVE)
            self.assertFalse(index.healthy())
            index.complete_seed('fixture')
            self.assertTrue(index.healthy())
            self.assertIsNotNone(index.lookup('alice@mail.test'))
            for address in ('alice+tag@mail.test', 'alice@system', 'alice@outside.test'):
                self.assertIsNone(index.lookup(address))
            with index.connect() as db:
                self.assertEqual(db.execute(policy.RECIPIENT_SQL, ['ALICE@MAIL.TEST']).fetchone(), (1,))
            index.record('fixture', 'alice+tag@mail.test', policy.Outcome.POSITIVE)
            self.assertIsNotNone(index.lookup('alice+tag@mail.test'))
            index.record('fixture', 'alice@mail.test', policy.Outcome.ABSENT)
            self.assertIsNone(index.lookup('alice@mail.test'))
            self.assertIsNotNone(index.lookup('alice+tag@mail.test'))


if __name__ == '__main__':
    unittest.main()
