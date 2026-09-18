"""Offline contracts for the shared helpers; native delivery has its own proof."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, call, patch

import smtp_fixture as fixture


class InventoryClient:
    """Small in-memory registry for inventory update/readback assertions."""
    def __init__(self):
        self.rows = {
            'SpamTag': [
                {'id': 'blocked', '@type': 'Reject', 'tag': 'BLOCKED_DOMAIN'},
                {'id': 'allow', '@type': 'Score', 'tag': 'SPF_ALLOW', 'score': 99},
            ],
            'SpamRule': [{'id': 'rule', '@type': 'Any', 'name': 'existing', 'enable': False}],
        }
        self.calls = []

    def jmap(self, method, arguments):
        self.calls.append((method, copy.deepcopy(arguments)))
        kind, operation = method.removeprefix('x:').split('/')
        rows = self.rows[kind]
        if operation == 'query':
            return {'ids': [row['id'] for row in rows]}
        if operation == 'get':
            return {'list': copy.deepcopy([row for row in rows if row['id'] in arguments['ids']])}
        if operation == 'set':
            for ident, values in arguments.get('update', {}).items():
                next(row for row in rows if row['id'] == ident).update(values)
            created = {}
            for key, value in arguments.get('create', {}).items():
                ident = kind + '-' + str(len(rows))
                rows.append({'id': ident, **value})
                created[key] = {'id': ident}
            return {'created': created}
        raise AssertionError('Unexpected fixture method: ' + method)


class SharedFixtureTests(unittest.TestCase):
    def inventory(self):
        return {
            'SpamTag': [
                {'@type': 'Reject', 'tag': 'BLOCKED_DOMAIN'},
                {'@type': 'Score', 'tag': 'SPF_ALLOW', 'score': -0.2},
                {'@type': 'Discard', 'tag': 'DISCARD_TAG'},
            ],
            'SpamRule': [
                {'@type': 'Any', 'name': 'existing', 'enable': True},
                {'@type': 'Any', 'name': 'new-rule', 'enable': True},
            ],
        }

    def load(self, client, inventory):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'rules.json'
            path.write_text(json.dumps(inventory))
            return fixture.load_filter_inventory(client, path)

    def test_registry_queries_and_updates_preserve_ids(self):
        client = Mock()
        client.jmap.side_effect = [{'ids': ['a']}, {'list': [{'id': 'a'}]}, {'updated': ['a']}]
        self.assertEqual(fixture.objects(client, 'Account'), [{'id': 'a'}])
        self.assertEqual(fixture.change(client, 'Account', 'a', {'name': 'alice'}), {'updated': ['a']})
        self.assertEqual(client.jmap.call_args_list, [
            call('x:Account/query', {}), call('x:Account/get', {'ids': ['a']}),
            call('x:Account/set', {'update': {'a': {'name': 'alice'}}}),
        ])

    def test_inventory_converts_actions_in_place_and_replays_without_duplicates(self):
        client = InventoryClient()
        result = self.load(client, self.inventory())
        first = copy.deepcopy(client.rows)
        self.assertEqual(self.load(client, self.inventory()), result)
        self.assertEqual(client.rows, first)
        self.assertEqual(result, {'tags': 3, 'rules': 2, 'convertedToScore': ['BLOCKED_DOMAIN', 'DISCARD_TAG']})
        tags = {row['tag']: row for row in client.rows['SpamTag']}
        self.assertEqual(tags['BLOCKED_DOMAIN'], {'id': 'blocked', '@type': 'Score',
                                                'tag': 'BLOCKED_DOMAIN', 'score': 1000})
        self.assertEqual(tags['SPF_ALLOW']['score'], -0.2)
        self.assertEqual(tags['DISCARD_TAG']['score'], 1000)
        updates = [args['update'] for method, args in client.calls if 'update' in args]
        self.assertTrue(all('tag' not in row.get('allow', {}) for row in updates))
        self.assertTrue(all('name' not in row.get('rule', {}) for row in updates))
        self.assertTrue(all('destroy' not in args for method, args in client.calls))
        self.assertEqual(sum('create' in args for method, args in client.calls), 2)

    def test_inventory_rejects_unknown_variants_unstripped_or_disabled_rules(self):
        for change in ('variant', 'id', 'disabled'):
            with self.subTest(change=change):
                inventory = self.inventory()
                if change == 'variant':
                    inventory['SpamTag'][0]['@type'] = 'Unknown'
                elif change == 'id':
                    inventory['SpamRule'][0]['id'] = 'production-id'
                else:
                    inventory['SpamRule'][0]['enable'] = False
                with self.assertRaises(AssertionError):
                    self.load(InventoryClient(), inventory)

    def test_inventory_refuses_unexpected_existing_tags_without_deleting_them(self):
        client = InventoryClient()
        client.rows['SpamTag'].append({'id': 'extra', '@type': 'Score', 'tag': 'EXTRA', 'score': 7})
        with self.assertRaisesRegex(AssertionError, 'Unexpected native SpamTag inventory'):
            self.load(client, self.inventory())
        self.assertTrue(any(row['id'] == 'extra' for row in client.rows['SpamTag']))
        self.assertTrue(all('destroy' not in args for method, args in client.calls))

    def test_email_ids_uses_mail_capability_and_account_scoped_query(self):
        client = Mock()
        client.expect.return_value.document.return_value = {
            'methodResponses': [['Email/query', {'ids': ['message']}, 'mail-fixture']]}
        self.assertEqual(fixture.email_ids(client, 'account'), ['message'])
        client.expect.assert_called_once_with('POST', '/jmap', 200, {
            'using': ['urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:mail'],
            'methodCalls': [['Email/query', {'accountId': 'account'}, 'mail-fixture']],
        }, auth='recovery')

    def test_email_ids_rejects_failed_or_uncorrelated_responses(self):
        for calls in ([], [['error', {}, 'mail-fixture']], [['Email/query', {}, 'wrong-id']]):
            with self.subTest(calls=calls):
                client = Mock()
                client.expect.return_value.document.return_value = {'methodResponses': calls}
                with self.assertRaisesRegex(AssertionError, 'Unexpected Email/query response'):
                    fixture.email_ids(client, 'account')

    def test_filter_settings_are_junk_only_and_keep_native_trust(self):
        client = Mock()
        fixture.deterministic_spam_settings(client, "listener == 'fixture-smtp'")
        settings = {method: args['update']['singleton'] for (method, args), _ in client.jmap.call_args_list}
        self.assertEqual(settings['x:SpamSettings/set'], {
            'enable': True, 'scoreSpam': 5, 'scoreReject': 0, 'scoreDiscard': 0,
            'trustContacts': True, 'trustReplies': True, 'spamFilterRulesUrl': None})
        self.assertEqual(settings['x:SpamPyzor/set'], {'enable': False})
        self.assertEqual(settings['x:SpamLlm/set'], {'@type': 'Disable'})
        self.assertEqual(settings['x:MtaStageData/set'], {
            'enableSpamFilter': {'else': "listener == 'fixture-smtp'", 'match': {}}})

    def test_message_lookup_checks_junk_only_after_inbox_absence(self):
        with patch.object(fixture, 'fetch_message', side_effect=[AssertionError('not delivered'), b'message']) as fetch:
            self.assertEqual(fixture.where('fixture', 'tag'), ('Junk Mail', b'message'))
            self.assertEqual(fetch.call_args_list, [call('fixture', 'tag', folder='INBOX', timeout=12),
                                                   call('fixture', 'tag', folder='Junk Mail', timeout=12)])
        with patch.object(fixture, 'fetch_message', return_value=b'message') as fetch:
            self.assertEqual(fixture.where('fixture', 'tag'), ('INBOX', b'message'))
            self.assertEqual(fetch.call_count, 1)
        with patch.object(fixture, 'fetch_message', side_effect=AssertionError('not delivered')):
            with self.assertRaisesRegex(AssertionError, 'not found in Inbox or Junk Mail'):
                fixture.where('fixture', 'tag')
        with patch.object(fixture, 'fetch_message', side_effect=AssertionError('body corrupted')) as fetch:
            with self.assertRaisesRegex(AssertionError, 'body corrupted'):
                fixture.where('fixture', 'tag')
            self.assertEqual(fetch.call_count, 1)


if __name__ == '__main__':
    unittest.main()
