"""Offline fixture safety/contract checks; these do not qualify native SMTP."""
import json
import re
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

    def test_declarative_auth_script_matches_qualified_native_fixture(self):
        self.assertEqual(edge.POLICY_PATH.with_name('auth-verdict.sieve').read_text(),
                         edge.verdict_script())

    def test_auth_script_uses_only_native_enumerated_variables(self):
        script = edge.verdict_script()
        self.assertEqual(script.count('deleteheader "X-Edge-Auth";'), 1)
        self.assertEqual(script.count('addheader "X-Edge-Auth"'), 1)
        self.assertLess(script.index('deleteheader'), script.index('addheader'))
        for field in ('spf.result', 'dkim.result', 'dmarc.result', 'dmarc.policy'):
            self.assertIn('${env.' + field + '}', script)
        self.assertEqual(script.count('deleteheader "Authentication-Results";'), 1)
        self.assertNotIn('ARC-', script)
        for forbidden in ('envelope', 'pass-or-none', 'eval ', 'http', 'sql'):
            self.assertNotIn(forbidden, script)
        with self.assertRaises(TypeError):
            edge.verdict_script('forced@sender.example')

    @staticmethod
    def bridge_tags(spf='none', dkim='none', dmarc='none', policy='reject', peer=edge.RELAY, value=None):
        rules, _ = edge.auth_header_rules(edge.RELAY, {'DMARC_NA': 1.0, 'AUTH_NA': 1.0})
        value = value if value is not None else f'spf={spf}; dkim={dkim}; dmarc={dmarc}; policy={policy};'
        context = {'remote_ip': peer, 'name_lower': 'x-edge-auth', 'value': value,
                   'value_lower': value.lower(), 'true': True,
                   'contains': lambda haystack, needle: needle in haystack,
                   'matches': lambda pattern, text: re.fullmatch(pattern, text) is not None}
        tags = set()
        # Evaluate only our generated, trusted boolean subset (not a native test).
        for rule in rules:
            for branch in rule['condition']['match'].values():
                expression = branch['if'].replace('&&', ' and ').replace('||', ' or ')
                expression = re.sub(r'!(?!=)', ' not ', expression).strip()
                if eval(expression, {'__builtins__': {}}, context):
                    tags.add(branch['then'].strip("'"))
                    break
        return tags

    def test_forwarding_spf_failure_does_not_override_dmarc_pass(self):
        tags = self.bridge_tags('fail', 'pass', 'pass')
        self.assertEqual(tags, {'SPF_FAIL', 'DKIM_ALLOW', 'DMARC_POLICY_ALLOW',
                               'EDGE_AUTH_VALID', 'EDGE_DMARC_NA_OFFSET'})
        weights = {'SPF_FAIL': 1, 'DKIM_ALLOW': -0.2, 'DMARC_POLICY_ALLOW': -0.5,
                   'EDGE_AUTH_VALID': 0, 'EDGE_DMARC_NA_OFFSET': -1}
        self.assertAlmostEqual(1 + sum(weights[t] for t in tags), 0.3)
        self.assertNotIn('DMARC_POLICY_REJECT', tags)

    def test_auth_mapping_preserves_native_result_and_policy_distinctions(self):
        for field, mapping in edge.AUTH_TAGS.items():
            for value, tag in mapping.items():
                args = {'spf': 'none', 'dkim': 'none', 'dmarc': 'none', field: value}
                self.assertIn(tag, self.bridge_tags(**args))
        for policy, tag in [('reject', 'DMARC_POLICY_REJECT'),
                            ('quarantine', 'DMARC_POLICY_QUARANTINE'),
                            ('none', 'DMARC_POLICY_SOFTFAIL'),
                            ('unspecified', 'DMARC_POLICY_SOFTFAIL')]:
            self.assertIn(tag, self.bridge_tags('pass', 'none', 'fail', policy))
        self.assertEqual(self.bridge_tags('none', 'none', 'none'),
                         {'SPF_NA', 'DKIM_NA', 'DMARC_NA', 'AUTH_NA', 'EDGE_AUTH_VALID'})
        self.assertIn('AUTH_NA_OR_FAIL', self.bridge_tags('temperror', 'none', 'none'))
        self.assertNotIn('AUTH_NA_OR_FAIL', self.bridge_tags('pass', 'none', 'pass'))

    def test_auth_baselines_use_existing_weights_and_only_trusted_peer(self):
        rules, tags = edge.auth_header_rules(edge.RELAY, {'DMARC_NA': 1.25, 'AUTH_NA': 0.75})
        self.assertEqual([tag['score'] for tag in tags], [-1.25, 0])
        self.assertTrue(all(rule['@type'] == 'Header' and rule['enable'] for rule in rules))
        self.assertEqual(self.bridge_tags('fail', 'fail', 'fail', peer='192.0.2.10'), set())
        with self.assertRaises(ValueError):
            edge.auth_header_rules("x' || true", {'DMARC_NA': 1, 'AUTH_NA': 1})

    def test_malformed_trusted_header_never_gets_mapping_or_credit(self):
        for name, value in edge.MALFORMED_AUTH.items():
            with self.subTest(name=name):
                self.assertEqual(self.bridge_tags(value=value), set())
        for value in ('spf=pass; dkim=softfail; dmarc=pass; policy=none;',
                      'spf=pass; dkim=pass; dmarc=neutral; policy=none;',
                      'spf=pass; dkim=pass; dmarc=pass; policy=bogus;'):
            self.assertEqual(self.bridge_tags(value=value), set())

    def test_auth_na_override_changes_actual_tag_before_bounce_rules(self):
        override = edge.auth_na_override()
        self.assertEqual(override['name'], 'STWT_AUTH_NA')
        self.assertEqual(override['priority'], 1004)
        expression = override['condition']['match']['0']['if']
        def run_native_fallback(tags):
            native = {'DKIM_NA', 'SPF_NA', 'DMARC_NA', 'ARC_NA'} | tags
            condition = re.sub(r'\$([A-Z_]+)', lambda m: str(m[1] in native), expression)
            if eval(condition.replace('!', ' not ').replace('&&', ' and ').strip(), {'__builtins__': {}}):
                native.add('AUTH_NA')
            return native
        for args in [('pass', 'none', 'pass'), ('fail', 'pass', 'pass')]:
            tags = run_native_fallback(self.bridge_tags(*args))
            self.assertNotIn('AUTH_NA', tags)
            self.assertNotIn('AUTH_NA_OR_FAIL', tags)
        for tags in (self.bridge_tags(), self.bridge_tags(value='garbage'),
                     self.bridge_tags(peer='192.0.2.10')):
            self.assertIn('AUTH_NA', run_native_fallback(tags))
        tags = run_native_fallback(self.bridge_tags('temperror', 'none', 'none'))
        self.assertNotIn('AUTH_NA', tags)
        self.assertIn('AUTH_NA_OR_FAIL', tags)

    def test_verdict_parser_counts_folded_case_variant_duplicates(self):
        raw = (b'X-Edge-Auth: spf=pass;\r\n dkim=pass;\r\n'
               b'x-edge-auth: forged\r\nX-EDGE-AUTH: forged-again\r\n\r\nbody')
        self.assertEqual(edge.verdict_lines(raw), ['spf=pass; dkim=pass;', 'forged', 'forged-again'])

    def test_inventory_converts_action_in_place_and_preserves_scores(self):
        rows = {'SpamTag': [{'id': 'blocked', '@type': 'Reject', 'tag': 'BLOCKED_DOMAIN'},
                            {'id': 'allow', '@type': 'Score', 'tag': 'SPF_ALLOW', 'score': 99}],
                'SpamRule': [{'id': 'rule', '@type': 'Any', 'name': 'existing', 'enable': False}]}
        inventory = {'SpamTag': [{'@type': 'Reject', 'tag': 'BLOCKED_DOMAIN'},
                                 {'@type': 'Score', 'tag': 'SPF_ALLOW', 'score': -0.2}],
                     'SpamRule': [{'@type': 'Any', 'name': 'existing', 'enable': True}]}
        calls = []
        class Client:
            def jmap(self, method, args):
                calls.append((method, args))
                kind = method.split(':')[1].split('/')[0]
                for ident, values in args['update'].items():
                    next(row for row in rows[kind] if row['id'] == ident).update(values)
                return {}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'rules.json'
            path.write_text(json.dumps(inventory))
            with patch.object(edge, 'objects', side_effect=lambda client, kind: rows[kind]):
                result = edge.load_filter_inventory(Client(), path)
                edge.load_filter_inventory(Client(), path)
        self.assertEqual(result['convertedToScore'], ['BLOCKED_DOMAIN'])
        self.assertEqual(rows['SpamTag'][0], {'id': 'blocked', '@type': 'Score', 'tag': 'BLOCKED_DOMAIN', 'score': 1000})
        self.assertEqual(rows['SpamTag'][1]['score'], -0.2)
        self.assertTrue(rows['SpamRule'][0]['enable'])
        self.assertTrue(all('destroy' not in args and 'create' not in args for _, args in calls))

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
