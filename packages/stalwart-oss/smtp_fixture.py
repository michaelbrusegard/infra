"""Small native-mail fixture helpers shared by isolated SMTP exercises.

No edge routing, recipient policy, authentication bridge or live endpoint setup.
Callers own namespace isolation and supply disposable native clients/fixtures.
"""
import json
from pathlib import Path

from integration import require
from mail import create, fetch_message, update


def change(client, kind, ident, values):
    return client.jmap(f'x:{kind}/set', {'update': {ident: values}})


def query(client, kind):
    return client.jmap(f'x:{kind}/query', {})['ids']


def objects(client, kind):
    return client.jmap(f'x:{kind}/get', {'ids': query(client, kind)})['list']


def email_ids(client, account_id):
    response = client.expect('POST', '/jmap', 200, {
        'using': ['urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:mail'],
        'methodCalls': [['Email/query', {'accountId': account_id}, 'mail-fixture']],
    }, auth='recovery')
    calls = response.document()['methodResponses']
    require(len(calls) == 1 and calls[0][0] == 'Email/query' and calls[0][2] == 'mail-fixture',
            'Unexpected Email/query response')
    return calls[0][1]['ids']


def load_filter_inventory(client, path, *, get_objects=objects):
    """Load ID-stripped native rules, converting Reject/Discard tags to scores.

    Never delete tags or overwrite unrelated score weights. The optional reader
    keeps the retiring edge's existing mocked inventory tests usable unchanged.
    """
    inventory = json.loads(Path(path).read_text())
    existing = {t['tag']: t for t in get_objects(client, 'SpamTag')}
    converted = []
    for tag in inventory['SpamTag']:
        require(tag['@type'] in ('Score', 'Reject', 'Discard'), 'Unknown tag variant')
        body = {'@type': 'Score', 'tag': tag['tag'], 'score': float(tag.get('score', 1000.0))}
        if tag['@type'] in ('Reject', 'Discard'):
            body['score'] = 1000.0
            converted.append(tag['tag'])
        if tag['tag'] in existing:
            # Variant conversion needs the tag; same-variant patches must not
            # write that immutable primary key.
            values = body if existing[tag['tag']]['@type'] != 'Score' else {'score': body['score']}
            change(client, 'SpamTag', existing[tag['tag']]['id'], values)
        else:
            create(client, 'SpamTag', body)
    existing_rules = {r['name']: r['id'] for r in get_objects(client, 'SpamRule')}
    for rule in inventory['SpamRule']:
        require('id' not in rule and rule['enable'], 'Inventory must be ID-stripped enabled rules')
        if rule['name'] in existing_rules:
            change(client, 'SpamRule', existing_rules[rule['name']],
                   {key: value for key, value in rule.items() if key != 'name'})
        else:
            create(client, 'SpamRule', rule)
    actual = {tag['tag']: tag for tag in get_objects(client, 'SpamTag')}
    require(set(actual) == {tag['tag'] for tag in inventory['SpamTag']}, 'Unexpected native SpamTag inventory')
    for tag in inventory['SpamTag']:
        expected = tag['score'] if tag['@type'] == 'Score' else 1000.0
        require(actual[tag['tag']]['@type'] == 'Score' and actual[tag['tag']]['score'] == expected,
                'SpamTag action/weight readback mismatch: ' + tag['tag'])
    return {'tags': len(inventory['SpamTag']), 'rules': len(inventory['SpamRule']),
            'convertedToScore': converted}


def deterministic_spam_settings(client, enable_expression):
    update(client, 'SpamSettings', {'enable': True, 'scoreSpam': 5.0, 'scoreReject': 0.0,
                                    'scoreDiscard': 0.0, 'trustContacts': True, 'trustReplies': True,
                                    'spamFilterRulesUrl': None})
    update(client, 'SpamPyzor', {'enable': False})
    update(client, 'SpamLlm', {'@type': 'Disable'})
    update(client, 'MtaStageData', {'enableSpamFilter': {'else': enable_expression, 'match': {}}})


def where(fixture, tag):
    for folder in ('INBOX', 'Junk Mail'):
        try:
            return folder, fetch_message(fixture, tag, folder=folder, timeout=12)
        except AssertionError as error:
            if 'not delivered' not in str(error):
                raise
    raise AssertionError('Message ' + tag + ' not found in Inbox or Junk Mail')
