#!/usr/bin/env python3
"""Disposable native edge exercise, NEVER a production qualification by itself.

Run: python packages/stalwart-oss/edge.py --binary /path/to/approved/stalwart
Only the pinned SHA below is accepted. No hash override, downloads,
rebuilds, live endpoints or host networking. Evidence remains in a mode-0700
/tmp/stalwart-edge-* directory. Recovery is used solely to bootstrap empty DBs;
all SMTP probes run in normal mode with passwordless API-key administration.

The actual v2 policy Reader, LMTPProbe, Index, Refresher and HTTP server are
used against disposable native backends, with fixture-CA trust injected into
both HTTPS discovery and LMTP. There is no fabricated positive seed. Production
TLS and deployment readiness remain separate gates; this exercise never sets
an operator attestation. Hook-success/native-SQL-read failure can still produce
residual 550 on this image.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import ipaddress
import json
import os
import re
from pathlib import Path
import shutil
import signal
import smtplib
import socket
import subprocess
import sys
import tempfile
import threading
import time
import traceback
import urllib.request

from integration import CORE, ROOT, Acceptance, Client, Redactor, Server, check_namespace, namespace_id, patch, require
from mail import (TLSLMTP, certificate, configure_backend, create, fetch_message, isolated,
                  known_message, port, reload, smtp_connection, smtp_send,
                  start_mail, update)
from retirement import ids as email_ids

BINARY = Path('/nix/store/cldpjs1kzadx6hcxdr8v305jkh9kx1kp-stalwart-native-scim-0.16.21/bin/stalwart')
APPROVED_SHA256 = '02030a8334e3bc62bae1fa4a9139f498df0a7e105bd97ec5beacfdfa1be8b614'
POLICY_PATH = Path(__file__).resolve().parents[2] / 'gitops/espresso/apps/stalwart-edge/policy.py'
DOMAIN = 'mail.test'
INTERNAL = 'machine.fixture.test'
GUARD = 'edge-rcpt-domain-guard'
RELAY = '10.200.0.2'
LIMITS = [
    'Disposable native fixture is not production cutover authorization',
    'JMAP discovery is not an atomic membership snapshot; only LMTP proves recipients',
    'Production upstream certificate validation not tested; disposable self-signed relay only',
    'SQL failure after hook success can still produce residual 550 on unchanged image',
    'Production readiness must verify BOTH hook and trusted Sieve configuration',
]


def binary_hash():
    with BINARY.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def verify_binary():
    actual = binary_hash()
    require(actual == APPROVED_SHA256,
            f'Approved binary hash mismatch: expected {APPROVED_SHA256}; actual {actual}')
    return actual


def load_policy():
    spec = importlib.util.spec_from_file_location('edge_fixture_policy', POLICY_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def guard_contents():
    return ('require ["envelope", "reject"];\n'
            f'if not envelope :domain :is "to" "{DOMAIN}" {{\n'
            ' reject "550 5.7.1 Recipient domain is not served by this edge";\n}\n')


def relay_expression(sql):
    # Native expression strings are not JSON strings. Keep actual newlines;
    # only the outer JMAP transport is JSON encoded by Client.
    require('"' not in sql and '\\' not in sql, 'Unsafe SQL expression string')
    return {'match': {'0': {'if': f"rcpt_domain == '{DOMAIN}'",
                           'then': f"sql_query('edge-recipients', \"{sql}\", [rcpt]) == 1"}},
            'else': 'false'}


def change(client, kind, ident, values):
    return client.jmap(f'x:{kind}/set', {'update': {ident: values}})


def query(client, kind):
    return client.jmap(f'x:{kind}/query', {})['ids']


def objects(client, kind):
    return client.jmap(f'x:{kind}/get', {'ids': query(client, kind)})['list']


def passwordless(client, server, account):
    token = Acceptance(client, server, None).api_key(account)
    credentials = client.jmap('x:Account/get', {'ids': [account]})['list'][0]['credentials']
    removals = {'credentials/' + key: None for key, value in credentials.items()
                if value.get('@type') != 'ApiKey'}
    if removals:
        change(client, 'Account', account, removals)
    client.token = token
    client.recovery = client.redactor.add('Bearer ' + token)


def configure_edge(server, client, backend, index, sql):
    update(client, 'SpamPyzor', {'enable': False})
    create(client, 'Tracer', {'@type': 'Stdout', 'level': 'debug', 'ansi': False})
    cert, key, context = certificate(server.root)
    cert_id = create(client, 'Certificate', {
        'certificate': {'@type': 'File', 'filePath': str(cert)},
        'privateKey': {'@type': 'File', 'filePath': str(key)}})
    domain = create(client, 'Domain', {
        'name': INTERNAL, 'isEnabled': False,
        'certificateManagement': {'@type': 'Manual'},
        'dkimManagement': {'@type': 'Manual'}, 'dnsManagement': {'@type': 'Manual'}})
    update(client, 'SystemSettings', {'defaultHostname': 'edge.fixture.test',
                                    'defaultDomainId': domain, 'defaultCertificateId': cert_id})
    machine = create(client, 'Account', {
        '@type': 'User', 'name': 'edge-control', 'domainId': domain,
        'roles': {'@type': 'Admin'}, 'credentials': {},
        'encryptionAtRest': {'@type': 'Disabled'},
        'permissions': {'@type': 'Replace', 'enabledPermissions': dict.fromkeys([
            'authenticate', 'actionReloadSettings', 'sysActionCreate',
            'sysMtaHookUpdate', 'sysMtaStageRcptUpdate', 'sysMtaStageRcptGet',
            *('sys' + kind + verb for kind in (
                'Account', 'Domain', 'Directory', 'MtaHook', 'SieveSystemScript'
            ) for verb in ('Get', 'Query')),
        ], True)}})
    smtp_port = port()
    for name, protocol, number, tls in (
        ('fixture-smtp', 'smtp', smtp_port, True),
        ('fixture-http', 'http', int(client.origin.rsplit(':', 1)[1]), False)):
        create(client, 'NetworkListener', {'name': name, 'protocol': protocol,
               'bind': {f'127.0.0.1:{number}': True}, 'useTls': tls, 'tlsImplicit': tls})
    create(client, 'StoreLookup', {'namespace': 'edge-recipients', 'store': {
        '@type': 'Sqlite', 'path': str(index.path), 'poolMaxConnections': 4}})
    create(client, 'SieveSystemScript', {'name': GUARD, 'isActive': True,
                                       'contents': guard_contents()})
    hook = create(client, 'MtaHook', {
        'url': 'http://127.0.0.1:8090/rcpt', 'stages': {'rcpt': True},
        'enable': {'else': 'true'}, 'tempFailOnError': True,
        'timeout': 5000, 'maxResponseSize': 16384,
        'httpAuth': {'@type': 'Unauthenticated'}})
    update(client, 'MtaStageRcpt', {'script': {'else': repr(GUARD)},
           'allowRelaying': relay_expression(sql), 'waitOnFail': {'else': '1ms'},
           'rewrite': {'else': 'false'}})
    update(client, 'MtaStageAuth', {'require': {'else': 'false'},
                                  'saslMechanisms': {'match': {}, 'else': 'false'}})
    update(client, 'MtaStageData', {'enableSpamFilter': {'else': 'false'}})
    create(client, 'MtaRoute', {'@type': 'Relay', 'name': 'fixture-backend',
           'address': RELAY, 'port': backend['ports']['lmtp'], 'protocol': 'lmtp',
           'implicitTls': True, 'allowInvalidCerts': True, 'authSecret': {'@type': 'None'}})
    update(client, 'MtaOutboundStrategy', {'route': {'else': "'fixture-backend'"}})
    queue = create(client, 'MtaVirtualQueue', {'name': 'fixture', 'threadsPerNode': 1})
    create(client, 'MtaDeliverySchedule', {
        'name': 'fixture-retry', 'queueId': queue,
        'expiry': {'@type': 'Ttl', 'expire': 600000},
        'retry': {'@type': 'Custom', 'intervals': {'0': {'duration': 2000}}}})
    update(client, 'MtaOutboundStrategy', {'schedule': {'else': "'fixture-retry'"}})
    passwordless(client, server, machine)
    reload(client)
    start_mail(server)
    env = Path(f'/proc/{server.process.pid}/environ').read_bytes()
    require(b'STALWART_RECOVERY_' not in env, 'Recovery environment in SMTP process')
    client.expect('GET', '/api/account', 200)
    client.expect('POST', '/jmap', 401, body={}, auth=None)
    return {'server': server, 'client': client, 'ports': {'smtp': smtp_port},
            'context': context, 'hook': hook, 'machine': machine, 'users': {}}


def recipients(fixture, expected):
    for address, code in expected:
        time.sleep(0.6)  # Respect the production policy per-source probe rate.
        with smtp_connection(fixture) as smtp:
            require(smtp.ehlo()[0] == 250, 'EHLO failed')
            require(not smtp.has_extn('auth'), 'Public SMTP advertises SASL')
            require(smtp.mail('sender@outside.test')[0] == 250, 'MAIL failed')
            actual, response = smtp.rcpt(address)
            require(actual == code, f'RCPT {address}: expected {code}, got {actual}: {response!r}')
            print(f'RCPT {address} {actual}', flush=True)
            smtp.rset()


def guard_settings_ready(client):
    """Independent mandatory check; policy /healthz alone cannot attest guards."""
    try:
        hooks = objects(client, 'MtaHook')
        scripts = objects(client, 'SieveSystemScript')
        stage = client.jmap('x:MtaStageRcpt/get', {'ids': ['singleton']})['list'][0]
        return (
            any(h.get('url') == 'http://127.0.0.1:8090/rcpt'
                and h.get('enable', {}).get('else') == 'true'
                and not h.get('enable', {}).get('match')
                and h.get('stages', {}).get('rcpt') is True
                and h.get('tempFailOnError') is True for h in hooks)
            and any(s.get('name') == GUARD and s.get('isActive') is True
                    and s.get('contents', '').strip() == guard_contents().strip() for s in scripts)
            and stage.get('script', {}).get('else') == repr(GUARD)
            and not stage.get('script', {}).get('match'))
    except Exception:
        return False


def readiness(client):
    if not guard_settings_ready(client):
        return False
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open('http://127.0.0.1:8090/healthz', timeout=3) as response:
            return response.status == 200 and json.load(response) == {'healthy': True}
    except Exception:
        return False


def assert_mailbox_free(client):
    domains = objects(client, 'Domain')
    require(all(d['name'] != DOMAIN for d in domains), 'Public native Domain created')
    require(not query(client, 'Directory'), 'Native Directory created')
    accounts = objects(client, 'Account')
    require(all(not (a.get('emailAddress') or '').lower().endswith('@' + DOMAIN)
                for a in accounts), 'Public native recipient Account created')
    require(all(c.get('@type') == 'ApiKey' for a in accounts
                for c in a.get('credentials', {}).values()), 'Edge non-API-key credential present')
    return sorted(a['id'] for a in accounts)


def lmtp_rcpt_only(backend):
    """Native validation without DATA must not deliver or mutate any mailbox."""
    accounts = query(backend['client'], 'Account')
    before = {account: email_ids(backend['client'], account) for account in accounts}
    domain = backend['client'].jmap('x:Domain/get', {'ids': [backend['domain_id']]})['list'][0]
    require(not domain.get('catchAllAddress') and not domain.get('allowRelaying'),
            'Probe backend has catch-all or unrestricted relay')
    # Disable login via the actual native SCIM extension, not email reception.
    disabled = ROOT + '/Users/' + backend['users']['bob']['id']
    backend['client'].expect('PATCH', disabled, 200,
                            patch({'op': 'replace', 'path': 'active', 'value': False}))
    observed = {}
    for sender in ('', 'sender@outside.test', 'alice@mail.test',
                   'policy-probe@system.edge.asgard.michaelbrusegard.com'):
        with smtp_connection(backend, 'lmtp') as smtp:
            require(smtp.ehlo()[0] == 250, 'LHLO failed')
            for address, expected in (
                ('alice@mail.test', 250), ('ALICE@MAIL.TEST', 250),
                ('alice+probe@mail.test', 250), ('alias-alice@mail.test', 250),
                ('postmaster@mail.test', 250), ('team@mail.test', 250),
                ('bob@mail.test', 250), ('unknown@mail.test', 550),
                ('unknown+probe@mail.test', 550), ('literal+only@mail.test', 550)):
                mail_code, mail_response = smtp.mail(sender)
                require(mail_code == 250, f'LMTP MAIL {sender}: {mail_code} {mail_response!r}')
                code, response = smtp.rcpt(address)
                print(f'LMTP sender={sender!r} recipient={address!r} code={code} response={response!r}', flush=True)
                require(code == expected, f'LMTP RCPT {address}: {code} {response!r}')
                if expected == 550:
                    require(response == b'5.1.2 Mailbox does not exist.',
                            'Native absence response differs from policy classification')
                if address in observed:
                    require(observed[address] == (code, response), 'Recipient existence depends on sender')
                observed[address] = (code, response)
                smtp.rset()  # Deliberately never DATA.
    time.sleep(2)
    after = {account: email_ids(backend['client'], account) for account in accounts}
    require(before == after, 'RCPT-only LMTP probe changed mailbox IDs')
    require(all(not value for value in after.values()), 'RCPT-only probe created Emails')


def scim_lifecycle(backend, edge, refresher, policy):
    client = backend['client']
    client.expect('POST', ROOT + '/Users', 400,
                  {'schemas': [CORE + 'User'], 'userName': 'unqualified-no-realm'})
    created = client.expect('POST', ROOT + '/Users', 201, {
        'schemas': [CORE + 'User'], 'userName': 'edge-lifecycle@mail.test',
        'emails': [{'value': 'edge-lifecycle-alias@mail.test'}]}).document()
    path = ROOT + '/Users/' + created['id']
    recipients(edge, [('edge-lifecycle@mail.test', 250), ('edge-lifecycle-alias@mail.test', 250)])
    client.expect('PATCH', path, 200, patch({
        'op': 'replace', 'path': 'userName', 'value': 'edge-renamed@mail.test'}))
    time.sleep(0.6)
    require(refresher.observe('edge-lifecycle@mail.test', force=True) is policy.Outcome.ABSENT,
            'Native rename did not revoke old address')
    recipients(edge, [('edge-lifecycle@mail.test', 550), ('edge-renamed@mail.test', 250)])
    client.expect('PATCH', path, 200, patch({
        'op': 'add', 'path': 'emails', 'value': [{'value': 'edge-new-alias@mail.test'}]}))
    recipients(edge, [('edge-new-alias@mail.test', 250)])
    client.expect('DELETE', path, 204)
    for address in ('edge-renamed@mail.test', 'edge-lifecycle-alias@mail.test', 'edge-new-alias@mail.test'):
        time.sleep(0.6)
        require(refresher.observe(address, force=True) is policy.Outcome.ABSENT,
                'Native deletion did not revoke cached address ' + address)
    recipients(edge, [('edge-renamed@mail.test', 550), ('edge-new-alias@mail.test', 550)])


class SourceLMTP(TLSLMTP):
    """Explicit native peer address, bound only inside the verified namespace."""
    def __init__(self, fixture, source):
        isolated()
        self.source = source
        super().__init__('127.0.0.1', fixture['ports']['lmtp'], fixture['context'])

    def _get_socket(self, host, number, timeout):
        raw = socket.create_connection((host, number), timeout,
                                       source_address=(self.source, 0))
        return self.context.wrap_socket(raw, server_hostname=host)


def abuse_test(backend, root, stage):
    client, server = backend['client'], backend['server']
    peer = ipaddress.ip_address(RELAY)
    settings = client.jmap('x:SystemSettings/get', {'ids': ['singleton']})['list'][0]
    require(not any(peer in ipaddress.ip_network(net, strict=False)
                    for net in settings.get('proxyTrustedNetworks', {})),
            'Non-loopback probe peer has a trusted-proxy exemption')
    allowed = objects(client, 'AllowedIp')
    require(not any(peer in ipaddress.ip_network(row['address'], strict=False) for row in allowed),
            'Non-loopback probe peer has an AllowedIp exemption')
    original = client.jmap('x:Security/get', {'ids': ['singleton']})['list'][0]
    others = {key: value for key, value in original.items() if key != 'abuseBanRate'}
    (root / 'security-before.json').write_text(json.dumps(original, indent=2))
    original_blocked = set(query(client, 'BlockedIp'))
    update(client, 'Security', {'abuseBanRate': {'count': 35, 'period': 86400000}})
    reload(client)

    def probe(recipient):
        time.sleep(0.26)  # Avoid confounding the native connection-rate limit.
        with SourceLMTP(backend, RELAY) as smtp:
            require(smtp.sock.getsockname()[0] == RELAY, 'Probe source is not non-loopback')
            require(smtp.ehlo()[0] == 250, 'Non-loopback LHLO failed')
            require(smtp.mail('policy-probe@system.edge.asgard.michaelbrusegard.com')[0] == 250,
                    'Non-loopback MAIL failed')
            response = smtp.rcpt(recipient)
            smtp.rset()  # No DATA, including the known-recipient check.
            return response

    def negative_control():
        blocked = False
        for number in range(40):
            try:
                code, response = probe(f'ban-control-{number}@mail.test')
            except (smtplib.SMTPException, OSError):
                blocked = True
                break
            print(f'abuse-negative peer={RELAY} attempt={number + 1} code={code} response={response!r}', flush=True)
            if code != 550:
                blocked = True
                break
        created = set(query(client, 'BlockedIp')) - original_blocked
        rows = client.jmap('x:BlockedIp/get', {'ids': sorted(created)})['list']
        require(blocked and rows, '35/day negative control did not create a ban')
        require(all(ipaddress.ip_network(row['address'], strict=False).num_addresses == 1
                    and peer in ipaddress.ip_network(row['address'], strict=False) for row in rows),
                'Negative control produced an unexpected blocked IP')
        (root / 'fixture-generated-ban.json').write_text(json.dumps(rows, indent=2))
    stage('nonLoopback35PerDayAbuseBanNegativeControl', negative_control)
    # Remove ONLY rows introduced by this fixture; no original bans are touched.
    generated = sorted(set(query(client, 'BlockedIp')) - original_blocked)
    update(client, 'Security', {'abuseBanRate': None})
    client.jmap('x:BlockedIp/set', {'destroy': generated})
    client.jmap('x:Action/set', {'create': {'clear': {'@type': 'ReloadBlockedIps'}}})
    reload(client)

    def safe_sweep():
        accounts = query(client, 'Account')
        before = {account: email_ids(client, account) for account in accounts}
        for number in range(40):
            recipient = ('repeated-unknown' if number < 20 else f'distinct-unknown-{number}') + '@mail.test'
            response = probe(recipient)
            require(response == (550, b'5.1.2 Mailbox does not exist.'),
                    f'Rate-cleared non-loopback RCPT failed: {response!r}')
        require(probe('alice@mail.test')[0] == 250, 'Known recipient blocked after 40 misses')
        require(set(query(client, 'BlockedIp')) == original_blocked, 'A new blocked IP was created')
        current = client.jmap('x:Security/get', {'ids': ['singleton']})['list'][0]
        require(current.get('abuseBanRate') is None, 'Abuse ban rate was not cleared')
        require({k: v for k, v in current.items() if k != 'abuseBanRate'} == others,
                'An unrelated Security property changed')
        require({account: email_ids(client, account) for account in accounts} == before,
                'RCPT-only abuse probes created Emails')
        (root / 'security-after.json').write_text(json.dumps(current, indent=2))
    stage('nonLoopback40MissesAfterOnlyAbuseRateCleared', safe_sweep)
    start_mail(server)
    stage('nonLoopback40MissesAfterRestart', safe_sweep)
    reload(client)
    stage('nonLoopback40MissesAfterReloadSettings', safe_sweep)


def limiter_test(edge, backend, app, refresher, policy, root, stage):
    # Isolate the burst without changing production policy rates or Refresher.
    # Native per-source probes remain production-paced; only refill time freezes.
    app.client_budget = policy.ClientProbeBudget(clock=lambda: 100.0)
    attempts, payloads = [], []
    original_probe_factory = refresher.probe_factory
    original_hook = app.hook

    class CountedProbe:
        def __init__(self, source):
            self.delegate = original_probe_factory(source)

        def probe(self, recipient):
            attempts.append(recipient)
            return self.delegate.probe(recipient)

    def capture(payload):
        payloads.append(json.loads(json.dumps(payload)))
        return original_hook(payload)

    refresher.probe_factory = CountedProbe
    app.hook = capture

    def rcpt(address, source='127.0.0.1'):
        time.sleep(0.65)  # Refresher source budget and native session pacing.
        with smtplib.SMTP_SSL('127.0.0.1', edge['ports']['smtp'], timeout=15,
                context=edge['context'], local_hostname='localhost', source_address=(source, 0)) as smtp:
            require(smtp.ehlo()[0] == 250 and not smtp.has_extn('auth'), 'SMTP greeting/auth regression')
            require(smtp.mail('sender@outside.test')[0] == 250, 'Limiter MAIL failed')
            result = smtp.rcpt(address)
            smtp.rset()
            print(f'limiter source={source} recipient={address} response={result!r}', flush=True)
            return result[0]

    def burst():
        for number in range(10):
            before = len(attempts)
            require(rcpt(f'quota-{number}@mail.test') == 550, 'Admitted unknown did not reach native validation')
            require(len(attempts) == before + 1, 'Admitted miss did not perform exactly one native probe')
        before = len(attempts)
        require(rcpt('quota-11@mail.test') == 451, 'Eleventh uncommitted recipient was not throttled')
        require(len(attempts) == before, 'Exhausted client triggered a backend probe')
        require(payloads[-1]['context']['client']['ip'] == '127.0.0.1', 'Unexpected native IP payload')
    stage('nativeClientQuotaBurst10Then451WithoutProbe', burst)

    def independent():
        before = len(attempts)
        require(rcpt('quota-independent@mail.test', '127.0.0.2') == 550, 'Second native source IP shared quota')
        require(len(attempts) == before + 1, 'Second source IP did not trigger a native probe')
        require(payloads[-1]['context']['client']['ip'] == '127.0.0.2', 'Native second source IP not preserved')
    stage('nativeSecondClientIpHasIndependentQuota', independent)
    backend['server'].stop()
    stage('nativeCommittedPositiveBypassesExhaustedQuotaDuringOutage', lambda: require(
        rcpt('alice@mail.test') == 250, 'Committed positive rejected by client quota'))

    def custom_payloads():
        sample = payloads[0]
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        cases = [('missing', None), ('malformed', 'not-an-ip'), ('mapped', '::ffff:127.0.0.1'),
                 ('forwarded', '127.0.0.1')]
        for name, ip in cases:
            payload = json.loads(json.dumps(sample))
            # Invalid IP must fail even for a committed positive.
            payload['envelope']['to'][-1]['address'] = (
                'alice@mail.test' if name in ('missing', 'malformed') else 'quota-custom@mail.test')
            if ip is None:
                payload['context']['client'].pop('ip', None)
            else:
                payload['context']['client']['ip'] = ip
            before = len(attempts)
            request = urllib.request.Request('http://127.0.0.1:8090/rcpt',
                data=json.dumps(payload).encode(), headers={
                    'Content-Type': 'application/json', 'X-Forwarded-For': '192.0.2.99'})
            with opener.open(request, timeout=10) as response:
                value = json.load(response)
            require(value['action'] == 'reject' and value['response']['status'] == 451,
                    f'Custom {name} payload did not fail closed')
            require(len(attempts) == before, f'Custom {name} payload triggered a backend probe')
    stage('missingMalformedMappedAndForwardedIpFailClosed', custom_payloads)
    (root / 'native-hook-payloads.json').write_text(json.dumps(payloads, indent=2))
    (root / 'limiter-proof.json').write_text(json.dumps({
        'fixtureOnlyLimiterClock': 'frozen at 100.0; production rates/refresher unchanged',
        'nativeProbeAttempts': attempts, 'clientBuckets': dict(app.client_budget.clients),
    }, indent=2))


def run(root, report, group='all'):
    isolated()
    verify_binary()
    subprocess.run([shutil.which('ip'), 'address', 'add', RELAY + '/32', 'dev', 'lo'],
                   check=True, timeout=10)
    policy = load_policy()
    report['policySha256'] = hashlib.sha256(POLICY_PATH.read_bytes()).hexdigest()
    report['policySqlSha256'] = hashlib.sha256(POLICY_PATH.with_name('policy.sql').read_bytes()).hexdigest()
    report['fixtureSha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    http = thread = refresher = None
    servers = []

    def stage(name, function):
        started = time.monotonic()
        print('START ' + name, flush=True)

        def deadline(signum, frame):
            raise TimeoutError(f'{name} exceeded its 180-second deadline')

        previous = signal.signal(signal.SIGALRM, deadline)
        signal.alarm(180)
        try:
            function()
        except Exception as error:
            report['tests'][name] = {'status': 'FAIL', 'error': str(error)}
            (root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
            print(f'FAIL {name}: {error}', flush=True)
            raise
        finally:
            signal.alarm(0)
            signal.signal(signal.SIGALRM, previous)
        report['tests'][name] = {'status': 'PASS', 'seconds': round(time.monotonic() - started, 3)}
        (root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print('PASS ' + name, flush=True)

    try:
        for name in (('backend',) if group == 'abuse' else ('backend', 'edge')):
            directory = root / name
            directory.mkdir()
            client = Client(port(), Redactor())
            server = Server(BINARY, directory, client)
            servers.append(server)
            server.start()
        backend_server = servers[0]
        edge_server = servers[1] if len(servers) == 2 else None
        backend = configure_backend(backend_server, backend_server.client, lmtp_address=RELAY)
        passwordless(backend_server.client, backend_server, backend['admin_id'])
        change(backend_server.client, 'Domain', backend['domain_id'], {'subAddressing': {'@type': 'Enabled'}})
        create(backend_server.client, 'MailingList', {'name': 'postmaster',
               'domainId': backend['domain_id'], 'recipients': {'alice@mail.test': True}})
        create(backend_server.client, 'Account', {
            '@type': 'Group', 'name': 'literal+only', 'domainId': backend['domain_id']})
        reload(backend_server.client)
        start_mail(backend_server)
        if group == 'abuse':
            abuse_test(backend, root, stage)
            report['nativeExercise'] = 'PASS'
            return
        if group == 'all':
            stage('nativeLmtpRcptOnlyNoDataZeroEmails', lambda: lmtp_rcpt_only(backend))
        https_port = port()
        create(backend_server.client, 'NetworkListener', {
            'name': 'fixture-discovery-https', 'protocol': 'http',
            'bind': {f'127.0.0.1:{https_port}': True}, 'useTls': True, 'tlsImplicit': True})
        reload(backend_server.client)
        start_mail(backend_server)
        source = policy.Source('fixture', f'https://127.0.0.1:{https_port}', 'FIXTURE_TOKEN',
                               (DOMAIN,), '127.0.0.1', backend['ports']['lmtp'], 'localhost')
        inventory = {'fixture': [x + '@mail.test' for x in (
            'alice', 'bob', 'alias-alice', 'postmaster', 'team', 'alice+tag', 'alice+durable')]}
        index = policy.Index(root / 'recipients.sqlite3', [source], inventory=inventory)
        index.initialize()
        require(not index.healthy(), 'Empty index is ready')
        os.environ['FIXTURE_TOKEN'] = backend_server.client.token

        class TrustedFixtureReader(policy.Reader):
            def __init__(self, source):
                super().__init__(source)
                self.opener = urllib.request.build_opener(
                    urllib.request.ProxyHandler({}), policy.NoRedirect(),
                    urllib.request.HTTPSHandler(context=backend['context']))

        refresher = policy.Refresher(index, [source], reader_factory=TrustedFixtureReader,
            probe_factory=lambda source: policy.LMTPProbe(source, context=backend['context']))
        stage('realDiscoveryAndNativeVerifiedSeed', lambda: require(
            refresher.seed(budget=60), 'Real discovery/native LMTP seed failed'))
        stage('lmtpUntrustedCertificateIsInconclusive', lambda: require(
            policy.LMTPProbe(source).probe('alice@mail.test') is policy.Outcome.UNKNOWN,
            'Untrusted LMTP certificate produced an authoritative answer'))
        stage('lmtpTrustedCertificateVerifiesKnown', lambda: require(
            policy.LMTPProbe(source, context=backend['context']).probe('alice@mail.test')
            is policy.Outcome.POSITIVE, 'Fixture CA trusted LMTP probe failed'))
        app = policy.Policy(index, refresher, [source])
        http = policy.Server(app)
        thread = threading.Thread(target=http.serve_forever, daemon=True)
        thread.start()
        edge = configure_edge(edge_server, edge_server.client, backend, index, policy.RECIPIENT_SQL)
        client = edge['client']
        before = assert_mailbox_free(client)
        (root / 'guard-readback.json').write_text(json.dumps({
            'hooks': objects(client, 'MtaHook'),
            'scripts': objects(client, 'SieveSystemScript'),
            'rcpt': client.jmap('x:MtaStageRcpt/get', {'ids': ['singleton']}),
            'indexHealthy': index.healthy(),
        }, indent=2))
        stage('bothGuardsAndSnapshotReady', lambda: require(readiness(client), 'Readiness failed'))
        if group == 'limiter':
            limiter_test(edge, backend, app, refresher, policy, root, stage)
            stage('noPublicNativeAccountsBeforeAfter', lambda: require(
                assert_mailbox_free(client) == before, 'Native account set changed'))
            report['nativeExercise'] = 'PASS'
            return
        if group == 'all':
            stage('normalModeKnownUnknownCaseTagPostmasterNoSasl', lambda: recipients(edge, [
                ('alice@mail.test', 250), ('ALICE@MAIL.TEST', 250), ('alice+tag@mail.test', 250),
                ('alias-alice@mail.test', 250), ('postmaster@mail.test', 250),
                ('unknown@mail.test', 550), ('literal+only@mail.test', 550),
                ('recipient@outside.test', 550), ('alice@system', 550),
                ('edge-control@' + INTERNAL, 550)]))
            # Missing hook: SQL must still deny unknown; independent Sieve blocks machine.
            change(client, 'MtaHook', edge['hook'], {'enable': {'else': 'false'}})
            reload(client)
            require(not readiness(client), 'Readiness accepted missing hook')
            stage('missingHookSqlAndStaticGuard', lambda: recipients(edge, [
                ('alice@mail.test', 250), ('unknown@mail.test', 550),
                ('recipient@outside.test', 550), ('edge-control@' + INTERNAL, 550)]))
            update(client, 'MtaStageRcpt', {'script': {'else': 'false'}})
            reload(client)
            require(not readiness(client), 'Readiness accepted both guards missing')
            # Deliberate negative control: native internal canAccept precedes relay SQL.
            # RCPT only, no DATA. This is why readiness must not rely on SQL alone.
            stage('bothGuardsMissingMachineBypassNegativeControl', lambda: recipients(
                edge, [('edge-control@' + INTERNAL, 250)]))
            change(client, 'MtaHook', edge['hook'], {'enable': {'else': 'true'}})
            reload(client)
            require(not readiness(client), 'Readiness accepted missing Sieve guard')
            stage('missingSieveHealthyHookOutsideMachine', lambda: recipients(edge, [
                ('alice@mail.test', 250), ('recipient@outside.test', 550),
                ('edge-control@' + INTERNAL, 550)]))
            update(client, 'MtaStageRcpt', {'script': {'else': repr(GUARD)}})
        if group != 'queue':
            # Point at an unused loopback port: connection-refused hook must tempfail.
            change(client, 'MtaHook', edge['hook'], {'url': f'http://127.0.0.1:{port()}/rcpt'})
            reload(client)
            stage('hookConnectionFailure451', lambda: recipients(edge, [('alice@mail.test', 451)]))
            change(client, 'MtaHook', edge['hook'], {'url': 'http://127.0.0.1:8090/rcpt'})
            reload(client)
            # Partial discovery cannot mark readiness or erase already verified rows.
            class IncompleteDiscovery:
                def __init__(self, source):
                    pass

                def discover(self, deadline):
                    raise policy.Unavailable('injected partial discovery')

            with index.connect(write=True) as db:
                db.execute('DELETE FROM policy_seed')
                count = db.execute('SELECT COUNT(*) FROM policy_recipients').fetchone()[0]
            refresher.reader_factory = IncompleteDiscovery
            require(not refresher.seed(), 'Incomplete discovery marked seed complete')
            require(not index.healthy(), 'Incomplete seed is ready')
            with index.connect() as db:
                require(db.execute('SELECT COUNT(*) FROM policy_recipients').fetchone()[0] == count,
                        'Partial discovery erased verified positives')
            stage('incompleteSeed451NotEmptyAuthorization', lambda: recipients(edge, [('alice@mail.test', 451)]))
            refresher.reader_factory = TrustedFixtureReader
            require(refresher.seed(), 'Real discovery failed to restore seed readiness')
            with index.connect(write=True) as db:
                db.execute('UPDATE policy_meta SET version=999')
            stage('corruptMetadata451', lambda: recipients(edge, [('alice@mail.test', 451)]))
            with index.connect(write=True) as db:
                db.execute('UPDATE policy_meta SET version=?', [policy.SCHEMA_VERSION])
            stage('nativeScimLifecycle', lambda: scim_lifecycle(backend, edge, refresher, policy))
        backend_server.stop()
        with index.connect(write=True) as db:
            db.execute('UPDATE policy_recipients SET verified_at=verified_at-60')
        stage('staleKnownAllowedUnseenAndUnseenTag451', lambda: recipients(edge, [
            ('alice@mail.test', 250), ('new@mail.test', 451), ('alice+unseen-outage@mail.test', 451)]))
        stage('backendOfflineDataAccepted', lambda: smtp_send(
            edge, 'alice+durable@mail.test', known_message('edge-durable')))
        time.sleep(3)
        start_mail(edge_server)
        stage('sameDatabaseRestartStillAcceptsKnown', lambda: recipients(edge, [('alice@mail.test', 250)]))
        require(assert_mailbox_free(client) == before, 'Edge accounts changed while queueing')
        start_mail(backend_server)
        def prove_delivery():
            raw = fetch_message(backend, 'edge-durable', timeout=90)
            (root / 'delivered.eml').write_bytes(raw)
            # Envelope is not necessarily copied into message headers. Prove
            # the exact native outbound RCPT, its 250 and the completed delivery.
            time.sleep(8)  # Several retry intervals; fetch also asserts no duplicates.
            fetch_message(backend, 'edge-durable')
            lines = (edge_server.root / 'server.log').read_text().splitlines()
            tagged = [line for line in lines if 'alice+durable@mail.test' in line]
            queued = [line for line in tagged if '(queue.message-queued)' in line]
            delivered = [line for line in tagged if '(delivery.delivered)' in line]
            require(len(queued) == 1 and len(delivered) == 1, 'Unexpected queue/delivery count')
            queue_id = re.search(r'queueId = (\d+)', queued[0]).group(1)
            require('queueId = ' + queue_id in delivered[0], 'Queue ID changed across restart')
            require(any('(delivery.rcpt-to)' in line and 'code = 250' in line
                        and 'to = "alice+durable@mail.test"' in line for line in tagged),
                    'Native outbound RCPT did not preserve the tag')
            require(any('(delivery.connect-error)' in line for line in tagged),
                    'No evidence of queued retry while backend offline')
            (root / 'queue-proof.log').write_text('\n'.join(tagged) + '\n')
        stage('durableQueueEventuallyExactlyOnceTagIntact', prove_delivery)
        stage('noPublicNativeAccountsBeforeAfter', lambda: require(
            assert_mailbox_free(client) == before, 'Native account set changed'))
        report['nativeExercise'] = 'PASS'
        report['scope'] = 'Selected isolated stage group only; not production cutover authorization'
    finally:
        if http is not None:
            http.shutdown()
            http.server_close()
        if thread is not None:
            thread.join(timeout=5)
        if refresher is not None:
            refresher.close()
        os.environ.pop('FIXTURE_TOKEN', None)
        for server in reversed(servers):
            server.stop()


def main():
    global BINARY
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, default=BINARY)
    parser.add_argument('--group', choices=('all', 'remaining', 'queue', 'abuse', 'limiter'), default='all')
    parser.add_argument('--isolated', nargs=3, metavar=('EVIDENCE', 'NETNS', 'USERNS'), help=argparse.SUPPRESS)
    args = parser.parse_args()
    BINARY = args.binary.resolve()
    # Private child protocol carries namespace ancestry, never a hash override.
    if args.isolated is None:
        root = Path(tempfile.mkdtemp(prefix='stalwart-edge-', dir='/tmp'))
        command = [sys.executable, str(Path(__file__).resolve()), '--binary', str(BINARY), '--group', args.group]
        report = {'qualified': False, 'binary': str(BINARY), 'approvedSha256': APPROVED_SHA256,
                  'tests': {}, 'blockers': list(LIMITS), 'evidence': str(root), 'reproduce': command}
        try:
            report['actualSha256'] = binary_hash()
            verify_binary()
        except Exception as error:
            report['blockers'].insert(0, str(error))
            (root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
            (root / 'run.log').write_text(str(error) + '\n')
            print(json.dumps(report, indent=2))
            return 1
        with (root / 'run.log').open('w') as log:
            child = subprocess.Popen(['unshare', '-Urn', *command, '--isolated', str(root),
                                      str(namespace_id('net')), str(namespace_id('user'))],
                                     stdout=log, stderr=subprocess.STDOUT)
            print(f'Evidence: {root}; overall deadline=1200s', flush=True)
            try:
                code = child.wait(timeout=1200)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                child.terminate()  # Child SIGTERM handler runs native-process cleanup.
                try:
                    child.wait(timeout=90)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=10)
                code = 1
        print(f'Evidence: {root}; exit={code}', flush=True)
        return code
    root = Path(args.isolated[0])
    require(root.parent == Path('/tmp') and root.name.startswith('stalwart-edge-'), 'Unsafe evidence path')
    report = {'qualified': False, 'binary': str(BINARY), 'approvedSha256': APPROVED_SHA256,
              'actualSha256': binary_hash(), 'tests': {}, 'blockers': list(LIMITS)}
    def interrupted(signum, frame):
        raise KeyboardInterrupt('Fixture interrupted; native qualification incomplete')

    signal.signal(signal.SIGTERM, interrupted)
    try:
        check_namespace(int(args.isolated[1]), int(args.isolated[2]))
        report['group'] = args.group
        run(root, report, args.group)
    except (Exception, KeyboardInterrupt) as error:
        report['blockers'].insert(0, str(error))
        traceback.print_exc()
    finally:
        (root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2), flush=True)
    # Native selected-group success is distinct from production qualification.
    return 0 if report.get('nativeExercise') == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
