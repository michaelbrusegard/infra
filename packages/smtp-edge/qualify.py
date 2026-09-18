#!/usr/bin/env python3
"""Disposable direct curl -> native Stalwart proof for the Postfix pipe adapter.

Run: python packages/smtp-edge/qualify.py [--binary /approved/stalwart]
Only the pinned Stalwart SHA-256 and curl 8.20.0 are accepted. Everything runs
inside a fresh unshare -Urn namespace with loopback only: private authoritative
DNS (installed named), a disposable native backend, and curl invoked exactly as
deliver.sh invokes it (PROXY v1 client IP, EHLO as URL path, STARTTLS with a
pinned CA, MAIL FROM:<> when the sender is empty). qualify_postfix.py also runs
this fixture through the actual Postfix queue in an isolated Docker network;
its ready/continue protocol preserves the single-user native isolation guard.

Proven natively, never through a score bridge, Sieve or header emulation:
- SPF and DMARC evaluated using the PROXY-reported original client IP.
- Forged incoming Authentication-Results / Received-SPF headers earn nothing;
  the backend prepends its own authoritative Authentication-Results.
- DMARC pass restores the native sender-authenticated flag: card-exists trust
  overrides GTUBE for a contact; without native DMARC pass, forged headers do not.
- BLOCKED_DOMAIN as Score 1000 lands in Junk with 250, no reject/discard/DSN.
- Local (port 26, no PROXY) path skips sender auth and spam filtering.
- Wrong CA yields a curl failure the adapter maps to a 4.3.0 deferral.
- Native settings survive restart.

Evidence is machine JSON in a mode-0700 /tmp/smtp-edge-qualify-* directory.
No production endpoint, account, mailbox or message is touched.
"""
from __future__ import annotations

import argparse
from email.parser import BytesParser
from email.policy import SMTP, SMTPUTF8, default as email_policy
from email.utils import formatdate
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import smtplib
import socket
import subprocess
import sys
import tempfile
import time
import traceback

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'stalwart-oss'))

from integration import Client, Redactor, Server, check_namespace, namespace_id, require  # noqa: E402
from mail import (certificate, configure_backend, create, fetch_message, isolated, known_message,  # noqa: E402
                  mailbox, port, reload, start_mail, update)
from edge import change, deterministic_spam_settings, email_ids, load_filter_inventory, objects, where  # noqa: E402
from edge_dns import RESOLVER, AuthDNS  # noqa: E402

BINARY = Path('/tmp/stalwart-edge-qualification/stalwart')
APPROVED_SHA256 = '02030a8334e3bc62bae1fa4a9139f498df0a7e105bd97ec5beacfdfa1be8b614'
CURL_VERSION = '8.20.0'
INVENTORY = HERE.parent / 'stalwart-oss' / 'fixtures' / 'spam-rules-v3.0.1.json'
DELIVER = HERE / 'deliver.sh'
DOMAIN = 'manafishrov.com'
RELAY = '127.0.0.1'             # curl peer address (fixture certificate SAN); only peer allowed PROXY
BACKEND_HOST = 'localhost'      # deliver.sh backend name, verified against the fixture certificate SAN
PASS_IP = '192.0.2.10'          # authorised by pass/blocked SPF records
PASS_IP6 = '2001:db8::10'       # authorised by the IPv6 fixture record
FAIL_IP = '192.0.2.11'
GTUBE = 'XJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X'
FORGED = [
    ('Authentication-Results', 'mail.fixture.test; spf=pass smtp.mailfrom=pass.auth.example.com; '
                               'dkim=pass header.d=pass.auth.example.com; dmarc=pass header.from=pass.auth.example.com'),
    ('Authentication-Results', 'forged.test; spf=pass; dkim=pass; dmarc=pass'),
    ('Received-SPF', 'pass (forged.test: domain of pass.auth.example.com designates 192.0.2.10 as permitted sender)'),
    ('X-Spam-Status', 'No, reason=card-exists'),
    ('X-Spam-Score', 'ham, score=-100.00'),
    ('X-Spam-Result', 'SPF_ALLOW (-0.20), DMARC_POLICY_ALLOW (-0.50)'),
]
AUTH_FIELDS = ('spfEhloVerify', 'spfFromVerify', 'dkimVerify', 'dmarcVerify', 'arcVerify', 'reverseIpVerify')
LIMITS = [
    'Disposable native fixture is not production cutover authorization',
    'Standalone mode invokes the adapter directly; only qualify_postfix.py exercises Postfix queue attributes',
    'Native positive-cache expiration is extended while a probe is pending (fixed 1000-second grace)',
    'Production requires the PROXY listener reachable only from the smtp-edge Cilium identity; the loopback peer address is fixture-only',
    'Contact/reply trust remains enabled in production and can override any score, including BLOCKED_DOMAIN 1000',
    'Fixture CA, fixture DNS and disposable accounts only; no production endpoint, account or message',
]


def binary_hash(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def verify_tools(binary):
    actual = binary_hash(binary)
    require(actual == APPROVED_SHA256, f'Approved binary hash mismatch: expected {APPROVED_SHA256}; actual {actual}')
    curl = shutil.which('curl')
    require(curl is not None, 'curl is required')
    version = subprocess.run([curl, '--version'], capture_output=True, text=True, timeout=10, check=True).stdout
    require(version.startswith('curl ' + CURL_VERSION + ' '), 'Qualified curl ' + CURL_VERSION + ' required: ' + version.split('\n')[0])
    require(shutil.which('named') is not None, 'Installed named is required for private authoritative DNS')
    return {'binarySha256': actual, 'curl': version.split('\n')[0], 'curlPath': curl,
            'deliverSha256': hashlib.sha256(DELIVER.read_bytes()).hexdigest(),
            'fixtureSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'inventorySha256': hashlib.sha256(INVENTORY.read_bytes()).hexdigest()}


def listener(client, name, number, *, proxy):
    body = {'name': name, 'protocol': 'smtp', 'bind': {f'{RELAY}:{number}': True},
            'useTls': True, 'tlsImplicit': False}
    if proxy:
        # Native IpAddrOrMask rejects prefixes shorter than /8 (registry ipmask.rs):
        # "all IPs" is not expressible. Production must use the pod CIDR that the
        # Cilium identity policy already restricts; the fixture trusts the relay host.
        body['overrideProxyTrustedNetworks'] = {RELAY + '/32': True}
    return create(client, 'NetworkListener', body)


def expression(listener_names, then, otherwise):
    return {'match': {str(i): {'if': f"listener == '{name}'", 'then': then} for i, name in enumerate(listener_names)},
            'else': otherwise}


def configure_edge_listeners(backend, ports):
    """The exact production shape for the two new private SMTP listeners."""
    client = backend['client']
    # Exact native RCPT verification must not silently resolve unknown plus
    # addresses to their base mailbox. Explicit plus aliases remain supported.
    change(client, 'Domain', backend['domain_id'], {'subAddressing': {'@type': 'Disabled'}})
    listener(client, 'smtp-edge', ports['edge'], proxy=True)
    listener(client, 'smtp-edge-local', ports['local'], proxy=False)
    # Existing LMTP keeps DATA filtering off; the trusted paths need no SASL.
    update(client, 'MtaStageAuth', {
        'require': expression(('fixture-lmtp', 'smtp-edge', 'smtp-edge-local'), 'false', 'true'),
        'saslMechanisms': expression(('fixture-lmtp', 'smtp-edge', 'smtp-edge-local'), 'false', '[plain, login]')})
    update(client, 'MtaStageRcpt', {
        'allowRelaying': {'else': '!is_empty(authenticated_as)', 'match': {}},
        'waitOnFail': expression(('fixture-lmtp', 'smtp-edge', 'smtp-edge-local'), '1ms', '5s')})
    update(client, 'MtaStageEhlo', {'rejectNonFqdn': {'else': 'false', 'match': {}}})
    update(client, 'SenderAuth', {key: expression(('smtp-edge',), 'relaxed', 'disable') for key in AUTH_FIELDS
                                  if key != 'arcVerify'})
    update(client, 'SenderAuth', {'arcVerify': {'else': 'disable', 'match': {}}})
    headers = {key: expression(('smtp-edge',), 'true', 'false') for key in (
        'addReceivedHeader', 'addAuthResultsHeader', 'addReceivedSpfHeader', 'addReturnPathHeader',
        'addDateHeader', 'addMessageIdHeader')}
    update(client, 'MtaStageData', {**headers, 'addDeliveredToHeader': True})
    deterministic_spam_settings(client, 'false')
    update(client, 'MtaStageData', {'enableSpamFilter': expression(('smtp-edge',), 'true', 'false')})
    settings = {kind: client.jmap(f'x:{kind}/get', {'ids': ['singleton']})['list'][0]
                for kind in ('SpamSettings', 'SpamPyzor', 'MtaStageData', 'SenderAuth', 'MtaStageAuth',
                             'MtaStageRcpt', 'MtaStageEhlo', 'Security')}
    require(settings['SpamSettings']['scoreReject'] == 0 and settings['SpamSettings']['scoreDiscard'] == 0,
            'Unsafe thresholds')
    require(settings['SpamPyzor']['enable'] is False, 'Pyzor must stay disabled')
    settings['NetworkListener'] = [o for o in objects(client, 'NetworkListener') if o['name'].startswith('smtp-edge')]
    return settings


def postfix_connection(fixture, number, client_ip=PASS_IP, helo='pass.auth.example.com'):
    class LoopbackSMTP(smtplib.SMTP):
        def _get_socket(self, host, port, timeout):
            # Retain the certificate name while selecting the source family.
            address = '::1' if ':' in client_ip else '127.0.0.1'
            return socket.create_connection((address, port), timeout, self.source_address)
    smtp = LoopbackSMTP('localhost', number, local_hostname=helo,
                        source_address=(client_ip, 0), timeout=45)
    try:
        require(smtp.ehlo(helo)[0] == 250, 'Postfix EHLO failed')
        require(smtp.has_extn('smtputf8') and not smtp.has_extn('auth'), 'Unsafe Postfix capabilities')
        smtp.starttls(context=fixture['context'])
        require(smtp.ehlo(helo)[0] == 250 and not smtp.has_extn('auth'), 'Unsafe post-TLS capabilities')
        return smtp
    except BaseException:
        smtp.close()
        raise


def deliver(fixture, ports, *, client_ip, helo, sender, recipient, raw, ca=None, backend=None,
            postfix_port=None):
    """Invoke deliver.sh exactly as pipe(8) would; curl binds the trusted relay address."""
    isolated()
    time.sleep(0.3)  # Respect the native 5/second connection throttle; do not disable it.
    if postfix_port is not None and client_ip and ca is None:
        started = time.monotonic()
        with postfix_connection(fixture, postfix_port, client_ip, helo) as smtp:
            refused = smtp.sendmail(sender, [recipient], raw, mail_options=['SMTPUTF8', 'BODY=8BITMIME'])
            require(not refused, 'Postfix refused the synthetic recipient')
        return {'path': 'postfix', 'exit': 0, 'seconds': round(time.monotonic() - started, 3),
                'stdout': '', 'stderr': ''}
    command = ['bash', str(DELIVER), backend or BACKEND_HOST, str(ports['edge']), str(ports['local']),
               str(ca or fixture['certificate']), client_ip, helo, sender, recipient]
    started = time.monotonic()
    result = subprocess.run(command, input=raw, capture_output=True, timeout=120,
                            env={'PATH': os.environ['PATH'], 'CURL_HOME': '/nonexistent', 'HOME': '/nonexistent',
                                 'LC_ALL': 'C'})
    return {'path': 'direct-adapter', 'command': command[1:], 'exit': result.returncode, 'seconds': round(time.monotonic() - started, 3),
            'stdout': result.stdout.decode(errors='replace').strip(),
            'stderr': result.stderr.decode(errors='replace').strip()[-500:]}


def message(tag, author, *, sign=None, gtube=False, forged=True):
    body = known_message(tag)
    body.replace_header('From', f'sender@{author}.auth.example.com')
    body.replace_header('To', f'alice@{DOMAIN}')
    body.replace_header('Date', formatdate(localtime=False, usegmt=True))
    if gtube:
        body.replace_header('Subject', GTUBE)
    if forged:
        for name, value in FORGED:
            body[name] = value
    raw = body.as_bytes(policy=SMTP)
    if sign is not None:
        raw = sign(raw)
    return raw


def parse(raw):
    parsed = BytesParser(policy=email_policy).parsebytes(raw)
    received = [str(v) for v in parsed.get_all('Received', [])]
    return {'authenticationResults': [str(v) for v in parsed.get_all('Authentication-Results', [])],
            'receivedSpf': [str(v) for v in parsed.get_all('Received-SPF', [])],
            'received': received,
            'spamStatus': [str(v) for v in parsed.get_all('X-Spam-Status', [])],
            'spamScore': [str(v) for v in parsed.get_all('X-Spam-Score', [])],
            'spamResult': [str(v) for v in parsed.get_all('X-Spam-Result', [])],
            'returnPath': str(parsed.get('Return-Path', '')),
            'deliveredTo': str(parsed.get('Delivered-To', ''))}


def contact(client, fixture, address):
    """Create a synthetic contact through native JMAP in alice's default address book."""
    account = fixture['users']['alice']['id']

    def call(method, arguments):
        response = client.expect('POST', '/jmap', 200, {
            'using': ['urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:contacts'],
            'methodCalls': [[method, arguments, 'qualify']]}, auth='recovery')
        method_name, result, _ = response.document()['methodResponses'][0]
        require(method_name == method, f'{method} failed: {result}')
        return result

    # First AddressBook/get materialises the native default address book.
    books = call('AddressBook/get', {'accountId': account, 'ids': None})['list']
    require(books, 'No default address book was created')
    created = call('ContactCard/set', {'accountId': account, 'create': {'card': {
        'addressBookIds': {books[0]['id']: True},
        'name': {'full': 'Fixture Sender'},
        'emails': {'0': {'address': address}}}}})
    require('card' in created.get('created', {}), f'ContactCard/set failed: {created}')
    return {'addressBookId': books[0]['id'], 'contactId': created['created']['card']['id'], 'email': address}


def run(root, report, binary, *, postfix_control=None, postfix_port=None):
    isolated()
    report['tools'] = verify_tools(binary)
    ip = shutil.which('ip')
    if postfix_control is None:
        for address in (PASS_IP + '/32', FAIL_IP + '/32', PASS_IP6 + '/128'):
            subprocess.run([ip, 'address', 'add', address, 'dev', 'lo'], check=True, timeout=10)

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

    directory = root / 'backend'
    directory.mkdir()
    client = Client(port(), Redactor())
    server = Server(binary, directory, client)
    server.start()
    try:
        fixture = configure_backend(server, client, domain=DOMAIN)
        ports = {'edge': port(), 'local': port()}
        # Reproduce the live variant migration: an existing Reject must become Score.
        create(client, 'SpamTag', {'@type': 'Reject', 'tag': 'BLOCKED_DOMAIN'})
        report['inventory'] = load_filter_inventory(client, INVENTORY)
        require(report['inventory']['convertedToScore'] == ['BLOCKED_DOMAIN'], 'Unexpected action tags in inventory')
        report['nativeSettings'] = configure_edge_listeners(fixture, ports)
        create(client, 'MemoryLookupKey', {'namespace': 'blocked-domains', 'key': 'blocked.auth.example.com',
                                          'isGlobPattern': False})
        update(client, 'DnsResolver', RESOLVER)
        reload(client)
        # Listeners are bound at startup; restart in normal mode after registry writes.
        server.stop()
        start_mail(server)
        client.jmap('x:Action/set', {'create': {'lookup': {'@type': 'ReloadLookupStores'}}})
        wrong_ca = certificate(root)[0]
        report['messages'] = {}
        alice = fixture['users']['alice']['email']

        dns = AuthDNS(root / 'dns', fixture['private_key'])
        zone = root / 'dns' / 'zone'
        original = f'pass.auth.example IN TXT "v=spf1 ip4:{PASS_IP} -all"\n'
        require(original in zone.read_text(), 'Fixture zone changed; review the IPv6 SPF extension')
        zone.write_text(zone.read_text().replace(original, f'pass.auth.example IN AAAA {PASS_IP6}\n'
                        f'pass.auth.example IN TXT "v=spf1 ip4:{PASS_IP} ip6:{PASS_IP6} -all"\n'))
        with dns:
            if postfix_control is not None:
                ready = {'backendHost': RELAY, 'lmtpPort': fixture['ports']['lmtp'],
                         'smtpPort': ports['edge'], 'localSmtpPort': ports['local'],
                         'caFile': str(fixture['certificate']), 'certFile': str(fixture['certificate']),
                         'keyFile': str(fixture['private_key'])}
                (postfix_control / 'ready.json').write_text(json.dumps(ready))
                deadline = time.monotonic() + 180
                while not (postfix_control / 'continue').exists():
                    require(time.monotonic() < deadline, 'Postfix readiness handshake timed out')
                    time.sleep(0.25)
                report['postfixPort'] = postfix_port

            def send(tag, *, client_ip, helo='pass.auth.example.com', sender='sender@pass.auth.example.com',
                     author='pass', sign=None, gtube=False, forged=True, ca=None, expect_exit=0):
                raw = message(tag, author, sign=sign, gtube=gtube, forged=forged)
                (root / (tag + '.in.eml')).write_bytes(raw)
                result = deliver(fixture, ports, client_ip=client_ip, helo=helo, sender=sender, recipient=alice,
                                 raw=raw, ca=ca, postfix_port=postfix_port)
                require(result['exit'] == expect_exit, f'{tag}: deliver.sh exit {result}')
                if expect_exit == 0:
                    folder, delivered = where(fixture, tag)
                    (root / (tag + '.eml')).write_bytes(delivered)
                    result.update({'folder': folder, **parse(delivered)})
                report['messages'][tag] = result
                (root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
                print(tag, json.dumps(result), flush=True)
                return result

            def native_only(result, tag):
                """Native headers are prepended first; the untouched forged copies follow, uncredited.

                The body is never rewritten (a DKIM h= covering Authentication-Results
                stays valid), so the forged headers remain verbatim. The verdict is
                taken only from the first, native header of each name.
                """
                ar = result['authenticationResults']
                require(len(ar) == 3 and ar[0].startswith('mail.fixture.test;\t'), f'{tag}: native Authentication-Results not prepended: {ar}')
                require(ar[1] == FORGED[0][1] and ar[2] == FORGED[1][1], f'{tag}: forged headers were rewritten')
                require('receiver=mail.fixture.test; client-ip=' in result['receivedSpf'][0] and result['receivedSpf'][1:] == [FORGED[2][1]],
                        f'{tag}: native Received-SPF not first: {result["receivedSpf"]}')
                require(result['spamStatus'][1:] == [FORGED[3][1]] and result['spamScore'][1:] == [FORGED[4][1]]
                        and result['spamResult'][1:] == [FORGED[5][1]], f'{tag}: forged X-Spam-* headers not preserved verbatim')
                require(result['spamStatus'][0] in ('Yes', 'No') or result.get('contactExpected'),
                        f'{tag}: forged card-exists reason credited: {result["spamStatus"]}')
                require('ARC_NA' in result['spamResult'][0] and 'DKIM2_NA' in result['spamResult'][0],
                        f'{tag}: first X-Spam-Result is not the native one')

            def tags(result, *expected):
                for item in expected:
                    require(item in result['spamResult'][0], f'missing native tag {item}: {result["spamResult"]}')

            def spf_pass():
                r = send('direct-spf-pass', client_ip=PASS_IP)
                native_only(r, 'direct-spf-pass')
                require(r['folder'] == 'INBOX', r)
                require(f'client-ip={PASS_IP}' in r['receivedSpf'][0], 'Received-SPF does not carry the PROXY client IP')
                require(f'[{PASS_IP}]' in r['received'][0] and 'pass.auth.example.com' in r['received'][0],
                        'Native Received header lacks original IP/EHLO')
                require(f'[{RELAY}]' not in r['received'][0], 'Relay address leaked as the client IP')
                tags(r, 'SPF_ALLOW (-0.20)', 'DMARC_POLICY_ALLOW (-0.50)')
                require('DMARC_POLICY_REJECT' not in r['spamResult'][0] and 'AUTH_NA' not in r['spamResult'][0], r)
            stage('proxyClientIpNativeSpfDmarcPassInbox', spf_pass)

            def spf_pass6():
                r = send('direct-spf-pass-ipv6', client_ip=PASS_IP6)
                native_only(r, 'direct-spf-pass-ipv6')
                require(r['folder'] == 'INBOX' and f'client-ip={PASS_IP6}' in r['receivedSpf'][0], r)
                tags(r, 'SPF_ALLOW (-0.20)', 'DMARC_POLICY_ALLOW (-0.50)')
            stage('proxyClientIpv6NativeSpfPass', spf_pass6)

            def forwarded():
                r = send('direct-spf-fail-dkim-pass', client_ip=FAIL_IP, sender='sender@fail.auth.example.com',
                         author='fail', sign=lambda raw: dns.sign(raw, names=(
                             b'from', b'to', b'subject', b'date', b'message-id',
                             b'authentication-results', b'authentication-results', b'authentication-results')))
                native_only(r, 'direct-spf-fail-dkim-pass')
                require(r['folder'] == 'INBOX', r)
                tags(r, 'SPF_FAIL (1.00)', 'DKIM_ALLOW (-0.20)', 'DMARC_POLICY_ALLOW (-0.50)')
                require('DMARC_POLICY_REJECT' not in r['spamResult'][0], 'SPF failure overrode aligned DKIM pass')
                require('dkim=pass' in r['authenticationResults'][0], 'Native DKIM pass missing')
            stage('spfFailAlignedDkimPassDmarcPassInboxNoReject', forwarded)

            def all_fail():
                def invalid_signature(raw):
                    head, tail = dns.sign(raw).split(b'; b=', 1)
                    replacement = b'A' if tail[:1] != b'A' else b'B'
                    return head + b'; b=' + replacement + tail[1:]
                r = send('direct-all-fail-forged', client_ip=FAIL_IP, sender='sender@fail.auth.example.com',
                         author='fail', sign=invalid_signature)
                native_only(r, 'direct-all-fail-forged')
                # The approved mail-auth version returns DMARC None when no
                # mechanism passes. Postfix's real TLS Received hop also avoids
                # the stock VIOLATED_DIRECT_SPF rule; do not fabricate its score.
                tags(r, 'SPF_FAIL (1.00)', 'DKIM_REJECT (1.00)', 'DMARC_NA (1.00)')
                require('spf=fail' in r['authenticationResults'][0] and 'dmarc=none' in r['authenticationResults'][0]
                        and 'policy.dmarc=reject' in r['authenticationResults'][0], r)
                require('SPF_ALLOW' not in r['spamResult'][0] and 'DKIM_ALLOW' not in r['spamResult'][0]
                        and 'DMARC_POLICY_ALLOW' not in r['spamResult'][0], 'Forged headers earned native credit')
                expected = ('INBOX', 'No') if postfix_port else ('Junk Mail', 'Yes')
                require((r['folder'], r['spamStatus'][0]) == expected, r)
                require(r['exit'] == 0, 'DMARC p=reject caused a rejection; relaxed mode required')
                report['findings'] = report.get('findings', []) + [
                    'Mail with no passing SPF/DKIM yields native dmarc=none/DMARC_NA, not dmarc=fail (mail-auth 0.12.1 dmarc/verify.rs:170-212); '
                    'DMARC_POLICY_REJECT only appears on an actual alignment failure of a pass result']
            stage('allFailForgedHeadersEarnNothingNoReject', all_fail)

            def dmarc_unaligned():
                r = send('native-dmarc-unaligned', client_ip=PASS_IP, author='blocked', sign=dns.sign)
                native_only(r, 'native-dmarc-unaligned')
                tags(r, 'SPF_ALLOW (-0.20)', 'DKIM_ALLOW (-0.20)', 'DMARC_POLICY_REJECT (4.00)')
                require('dmarc=fail' in r['authenticationResults'][0], 'Unaligned authentication did not fail DMARC')
                require('DMARC_POLICY_ALLOW' not in r['spamResult'][0], 'Forged DMARC pass earned credit')
            stage('nativeDmarcAlignmentFailureScoredWithoutReject', dmarc_unaligned)

            def gtube():
                r = send('direct-gtube', client_ip=PASS_IP, gtube=True)
                native_only(r, 'direct-gtube')
                require(r['folder'] == 'Junk Mail', r)
                tags(r, 'GTUBE_TEST (1000.00)')
            stage('gtubeJunkAcceptedNotRejected', gtube)

            def blocked():
                r = send('direct-blocked', client_ip=PASS_IP, sender='sender@blocked.auth.example.com', author='blocked')
                native_only(r, 'direct-blocked')
                require(r['folder'] == 'Junk Mail', r)
                tags(r, 'BLOCKED_DOMAIN (1000.00)', 'SPF_ALLOW (-0.20)', 'DMARC_POLICY_ALLOW (-0.50)')
            stage('blockedDomainScore1000JunkNoReject', blocked)

            def null_sender():
                r = send('direct-null-sender', client_ip=FAIL_IP, sender='', author='fail', sign=dns.sign)
                native_only(r, 'direct-null-sender')
                require(r['folder'] == 'INBOX' and r['returnPath'] == '<>', r)
                tags(r, 'DKIM_ALLOW (-0.20)', 'DMARC_POLICY_ALLOW (-0.50)')
                # SPF falls back to postmaster@HELO on a null reverse-path.
                require('envelope-from="postmaster@pass.auth.example.com"' in r['receivedSpf'][0], r)
            stage('nullSenderProxyPathNativeHeloSpf', null_sender)

            def local():
                r = send('direct-local-generated', client_ip='', sender='postmaster@edge.auth.example.com', author='pass')
                require(r['folder'] == 'INBOX', r)
                require(r['authenticationResults'] == [FORGED[0][1], FORGED[1][1]] and r['receivedSpf'] == [FORGED[2][1]],
                        f'Local listener performed sender authentication: {r["authenticationResults"]}')
                require(r['spamStatus'] == ['No', FORGED[3][1]] and r['spamScore'] == [FORGED[4][1]]
                        and r['spamResult'] == [FORGED[5][1]], f'Local listener ran the spam filter: {r}')
                require(r['received'] == [] and r['returnPath'] == '', 'Local listener added trace headers')
                require(r['deliveredTo'] == alice, 'Delivered-To missing on local path')
                log = (server.root / 'server.log').read_text()
                local_lines = [line for line in log.splitlines() if 'listenerId = "smtp-edge-local"' in line]
                require(local_lines and not any('smtp.spf-' in line or 'smtp.dmarc-' in line or 'spam.classify' in line
                                                for line in local_lines), 'Local listener ran sender auth or spam filter')
            stage('localGeneratedPort26NoProxyNoAuthNoFilter', local)

            def wrong_ca():
                r = send('direct-wrong-ca', client_ip=PASS_IP, ca=wrong_ca, expect_exit=75)
                require(r['stdout'].startswith('4.3.0 '), r)
                require(len(objects(client, 'QueuedMessage')) == 0, 'Wrong CA reached the queue')
            stage('wrongCaDefers430NoDelivery', wrong_ca)

            def proxy_only_peer():
                # A PROXY listener connection without a PROXY header is dropped.
                probe = subprocess.run(['curl', '-sS', '--max-time', '5', f'smtp://{BACKEND_HOST}:{ports["edge"]}/x',
                                        '--mail-rcpt', alice, '-T', '/dev/null'],
                                       capture_output=True, text=True, timeout=15)
                require(probe.returncode != 0, 'Missing PROXY header was accepted on the PROXY listener')
                report['messages']['proxy-required'] = {'exit': probe.returncode, 'stderr': probe.stderr.strip()[-200:]}
            stage('proxyListenerRefusesConnectionsWithoutProxyHeader', proxy_only_peer)

            def contact_trust():
                report['contact'] = contact(client, fixture, 'sender@pass.auth.example.com')
                update(client, 'SpamSettings', {'trustContacts': True, 'trustReplies': True})
                reload(client)
                try:
                    r = send('direct-contact-gtube-dmarc-pass', client_ip=PASS_IP, gtube=True)
                    r['contactExpected'] = True
                    native_only(r, 'direct-contact-gtube-dmarc-pass')
                    tags(r, 'GTUBE_TEST (1000.00)', 'DMARC_POLICY_ALLOW (-0.50)')
                    require(r['folder'] == 'INBOX' and r['spamStatus'][0] == 'No, reason=card-exists',
                            f'Native DMARC-authenticated contact trust not restored: {r}')
                    # Same author, real DMARC fail, forged pass headers: contact trust must not apply.
                    r = send('direct-contact-gtube-dmarc-fail-forged', client_ip=FAIL_IP,
                             sender='sender@fail.auth.example.com', gtube=True)
                    native_only(r, 'direct-contact-gtube-dmarc-fail-forged')
                    tags(r, 'GTUBE_TEST (1000.00)', 'SPF_FAIL (1.00)', 'DMARC_NA (1.00)')
                    require('dmarc=none' in r['authenticationResults'][0], r)
                    require(r['folder'] == 'Junk Mail' and r['spamStatus'][0] == 'Yes',
                            f'Forged headers earned contact trust without native DMARC pass: {r}')
                finally:
                    deterministic_spam_settings(client, 'false')
                    update(client, 'MtaStageData', {'enableSpamFilter': expression(('smtp-edge',), 'true', 'false')})
                    reload(client)
            stage('contactTrustRequiresNativeDmarcPassNotForgedHeaders', contact_trust)

            def utf8():
                alias = 'álïce'
                change(client, 'Account', fixture['users']['alice']['id'], {'aliases': {
                    '0': {'name': 'alias-alice', 'domainId': fixture['domain_id'], 'enabled': True},
                    '1': {'name': alias, 'domainId': fixture['domain_id'], 'enabled': True},
                    '2': {'name': 'alice+explicit', 'domainId': fixture['domain_id'], 'enabled': True}}})
                reload(client)
                tag = 'smtp-utf8-envelope-and-body'
                msg = known_message(tag)
                msg.replace_header('From', 'séndér@pass.auth.example.com')
                msg.replace_header('To', f'{alias}@{DOMAIN}')
                msg.replace_header('Date', formatdate(localtime=False, usegmt=True))
                msg.replace_header('Subject', 'Grüße æøå ' + tag)
                text = 'Grüße æøå ☕\n.leading\n..double\n'
                msg.get_payload()[0].set_content(text, cte='8bit')
                raw = msg.as_bytes(policy=SMTPUTF8)
                result = deliver(fixture, ports, client_ip=PASS_IP, helo='pass.auth.example.com',
                                 sender='séndér@pass.auth.example.com', recipient=f'{alias}@{DOMAIN}',
                                 raw=raw, postfix_port=postfix_port)
                require(result['exit'] == 0, f'SMTPUTF8 delivery failed: {result}')
                # mail.fetch_message intentionally requires its exact ASCII
                # body; this case independently verifies a different UTF8 body.
                delivered = None
                deadline = time.monotonic() + 30
                while delivered is None and time.monotonic() < deadline:
                    with mailbox(fixture) as imap:
                        require(imap.select('INBOX')[0] == 'OK', 'Cannot select UTF8 inbox')
                        status, rows = imap.search(None, 'ALL')
                        require(status == 'OK', 'UTF8 IMAP search failed')
                        for ident in rows[0].split():
                            status, rows = imap.fetch(ident, '(RFC822)')
                            require(status == 'OK', 'UTF8 IMAP fetch failed')
                            candidate = next(row[1] for row in rows if isinstance(row, tuple))
                            if BytesParser(policy=email_policy).parsebytes(candidate)['Message-ID'] == f'<{tag}@fixture.test>':
                                require(delivered is None, 'Duplicate UTF8 delivery')
                                delivered = candidate
                    if delivered is None:
                        time.sleep(0.2)
                require(delivered is not None, 'UTF8 message did not reach INBOX')
                folder = 'INBOX'
                parsed = BytesParser(policy=email_policy).parsebytes(delivered)
                require(str(parsed['Subject']) == str(msg['Subject']), 'UTF8 header changed')
                require(parsed.get_payload()[0].get_payload(decode=True) == text.replace('\n', '\r\n').encode(),
                        'UTF8 body or SMTP dot transparency changed')
                result.update({'folder': folder, **parse(delivered)})
                require('spf=pass' in result['authenticationResults'][0]
                        and 'dmarc=pass' in result['authenticationResults'][0], 'UTF8 native authentication lost')
                report['messages'][tag] = result
            stage('smtpUtf8EnvelopeHeadersBodyAndDotTransparency', utf8)

            control_id = 0

            def control(action):
                nonlocal control_id
                require(postfix_control is not None, 'Postfix control unavailable')
                control_id += 1
                request = postfix_control / 'request.json'
                request.with_suffix('.tmp').write_text(json.dumps({'id': control_id, 'action': action}))
                request.with_suffix('.tmp').replace(request)
                deadline = time.monotonic() + 60
                while time.monotonic() < deadline:
                    response = postfix_control / 'response.json'
                    if response.exists():
                        result = json.loads(response.read_text())
                        if result['id'] == control_id:
                            require(result['status'] == 'PASS', 'Postfix control failed')
                            return result
                    time.sleep(0.2)
                raise TimeoutError('Postfix control timed out: ' + action)

            if postfix_port is not None:
                def recipient_probe(address):
                    with postfix_connection(fixture, postfix_port) as smtp:
                        require(smtp.mail('sender@pass.auth.example.com')[0] == 250, 'Probe MAIL failed')
                        return smtp.rcpt(address)[0]

                def recipient_contract():
                    for address in (alice, f'alias-alice@{DOMAIN}', f'alice+explicit@{DOMAIN}', f'team@{DOMAIN}'):
                        require(recipient_probe(address) == 250, 'Known recipient refused: ' + address)
                    for address in (f'not-a-mailbox@{DOMAIN}', f'alice+not-configured@{DOMAIN}',
                                    f'alice@sub.{DOMAIN}', 'relay@outside.test'):
                        require(500 <= recipient_probe(address) < 600, 'Invalid recipient accepted: ' + address)
                stage('exactRecipientsAliasesListsNoPlusCatchallSubdomainsOrRelay', recipient_contract)

                def local_dsn():
                    alias = 'retired-after-acceptance'
                    current = client.jmap('x:Account/get', {'ids': [fixture['users']['alice']['id']]})['list'][0]['aliases']
                    expanded = dict(current)
                    expanded['99'] = {'name': alias, 'domainId': fixture['domain_id'], 'enabled': True}
                    change(client, 'Account', fixture['users']['alice']['id'], {'aliases': expanded})
                    reload(client)
                    tag = 'revoked-after-postfix-rcpt'
                    with postfix_connection(fixture, postfix_port) as smtp:
                        require(smtp.mail(alice)[0] == 250, 'DSN fixture MAIL failed')
                        require(smtp.rcpt(f'{alias}@{DOMAIN}')[0] == 250, 'Cannot warm disposable alias')
                        change(client, 'Account', fixture['users']['alice']['id'], {'aliases': current})
                        reload(client)
                        require(smtp.data(message(tag, 'pass'))[0] == 250, 'Postfix did not durably accept DATA')
                    delivered = None
                    deadline = time.monotonic() + 45
                    while delivered is None and time.monotonic() < deadline:
                        with mailbox(fixture) as imap:
                            require(imap.select('INBOX')[0] == 'OK', 'Cannot select DSN inbox')
                            status, rows = imap.search(None, 'ALL')
                            require(status == 'OK', 'DSN search failed')
                            for ident in rows[0].split():
                                status, rows = imap.fetch(ident, '(RFC822)')
                                require(status == 'OK', 'DSN fetch failed')
                                raw = next(row[1] for row in rows if isinstance(row, tuple))
                                parsed = BytesParser(policy=email_policy).parsebytes(raw)
                                if parsed.get_content_type() == 'multipart/report' and tag.encode() in raw:
                                    require(delivered is None, 'Duplicate local DSN')
                                    delivered = raw
                        if delivered is None:
                            time.sleep(0.2)
                    require(delivered is not None, 'Postfix-generated DSN did not reach the private local path')
                    result = parse(delivered)
                    require(not result['authenticationResults'] and result['spamStatus'] == ['No']
                            and not result['spamScore'] and not result['spamResult'],
                            f'Local DSN incorrectly entered Internet authentication/filtering: {result}')
                    report['messages']['postfix-generated-local-dsn'] = {'path': 'postfix-generated', 'exit': 0,
                                                                        'folder': 'INBOX', **result}
                    # Accelerate refresh only, not positive expiration. An
                    # observed authoritative negative must not revoke this cache.
                    control('refresh-cache')
                    require(recipient_probe(f'{alias}@{DOMAIN}') == 250, 'Finite positive-cache behavior changed')
                    deadline = time.monotonic() + 15
                    while time.monotonic() < deadline:
                        log = (server.root / 'server.log').read_text()
                        if any('smtp.mailbox-does-not-exist' in line and 'listenerId = "fixture-lmtp"' in line
                               and f'to = "{alias}@{DOMAIN}"' in line for line in log.splitlines()):
                            break
                        time.sleep(0.2)
                    else:
                        raise AssertionError('No authoritative negative refresh observed')
                    require(recipient_probe(f'{alias}@{DOMAIN}') == 250, 'Negative refresh revoked unexpired positive')
                    control('normal-cache')
                stage('postfixGeneratedDsnUsesLocalPathAfterRecipientRevocation', local_dsn)

                def queued_restart():
                    server.stop()
                    tag = 'queued-restart-native-context'
                    raw = message(tag, 'fail', sign=dns.sign)
                    result = deliver(fixture, ports, client_ip=FAIL_IP, helo='fail.auth.example.com',
                                     sender='sender@fail.auth.example.com', recipient=f'alice@{DOMAIN}',
                                     raw=raw, postfix_port=postfix_port)
                    require(result['exit'] == 0, 'Unexpired verified recipient was not accepted during outage')
                    queued = control('queue')
                    require(len(queued['after']) == 1, 'Accepted message is not in the durable queue')
                    restarted = control('restart')
                    require(len(restarted['after']) == 1, 'Queued message lost across restart')
                    start_mail(server)
                    control('flush')
                    folder, delivered = where(fixture, tag)
                    result.update({'folder': folder, **parse(delivered)})
                    require(folder == 'INBOX', 'Queued aligned-DKIM message misclassified')
                    require('fail.auth.example.com' in result['received'][0]
                            and f'[{FAIL_IP}]' in result['received'][0], 'Queued IP/EHLO lost across restart')
                    require('spf=fail' in result['authenticationResults'][0]
                            and 'dkim=pass' in result['authenticationResults'][0]
                            and 'dmarc=pass' in result['authenticationResults'][0], 'Queued native authentication lost')
                    report['messages'][tag] = result
                stage('verifiedRecipientOutageQueueSurvivesBothRestarts', queued_restart)

                def cache_expiration():
                    control('short-cache')
                    bob = fixture['users']['bob']['email']
                    require(recipient_probe(bob) == 250, 'Cannot create short-lived positive')
                    server.stop()
                    # Alice has an outstanding failed refresh from the outage
                    # proof. Postfix's fixed 1000-second probe grace keeps that
                    # positive usable, even beyond the shortened test expiry.
                    require(recipient_probe(alice) == 250, 'Pending-probe grace behavior changed')
                    require(recipient_probe(f'unseen-during-outage@{DOMAIN}') == 451,
                            'Unseen recipient did not defer during outage')
                    time.sleep(6)
                    require(recipient_probe(bob) == 451, 'Expired positive without pending probe did not defer')
                    start_mail(server)
                    control('normal-cache')
                    require(recipient_probe(alice) == 250, 'Recipient did not recover after outage')
                    report['acceleratedCacheExpirationSeconds'] = 5
                    report['nativePendingProbeGraceSeconds'] = 1000
                stage('unseenAndExpiredRecipientsDeferOutsideNativePendingProbeGrace', cache_expiration)

            def restart():
                server.stop()
                start_mail(server)
                after = {kind: client.jmap(f'x:{kind}/get', {'ids': ['singleton']})['list'][0]
                         for kind in ('SpamSettings', 'SenderAuth', 'MtaStageData')}
                for kind, value in after.items():
                    require(value == report['nativeSettings'][kind], f'{kind} changed across restart')
                r = send('direct-restart-spf-pass', client_ip=PASS_IP)
                native_only(r, 'direct-restart-spf-pass')
                require(r['folder'] == 'INBOX', r)
                tags(r, 'SPF_ALLOW (-0.20)', 'DMARC_POLICY_ALLOW (-0.50)')
                require(all(tag['@type'] == 'Score' for tag in objects(client, 'SpamTag')), 'Action tag survived restart')
            stage('nativeSettingsAndVerdictsSurviveRestart', restart)

            def accounting():
                queue = client.jmap('x:QueuedMessage/query', {'limit': 1, 'calculateTotal': True})
                require(queue['ids'] == [] and queue.get('total') == 0, 'Queue metadata is not empty')
                log = (server.root / 'server.log').read_text()
                # dsn-success is logged for ordinary successful recipients too;
                # it is not evidence that a notification message was generated.
                require(not any('delivery.dsn-' in line and 'dsn-success' not in line
                                for line in log.splitlines()), 'Backend generated a failure DSN')
                require(log.count('(queue.message-queued)') == (15 if postfix_port else 13), 'Unexpected additional queued message')
                require(len(email_ids(client, fixture['users']['alice']['id'])) == (15 if postfix_port else 13),
                        'Delivery/discard/duplicate accounting mismatch')
                require('excessive spam score' not in log, 'Backend rejected or discarded on score')
                report['queueEmptyReadback'] = {'ids': queue['ids'], 'total': queue['total']}
            stage('noRejectDiscardOrDsn', accounting)
        report['nativeExercise'] = 'PASS'
    finally:
        server.stop()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, default=BINARY)
    parser.add_argument('--isolated', nargs=3, metavar=('EVIDENCE', 'NETNS', 'USERNS'), help=argparse.SUPPRESS)
    parser.add_argument('--postfix-control', type=Path, help=argparse.SUPPRESS)
    parser.add_argument('--postfix-port', type=int, help=argparse.SUPPRESS)
    args = parser.parse_args()
    binary = args.binary.resolve()
    require((args.postfix_control is None) == (args.postfix_port is None), 'Incomplete Postfix handshake')
    require(args.postfix_control is None or args.isolated is not None, 'Postfix mode requires the isolated orchestrator')
    if args.isolated is None:
        root = Path(tempfile.mkdtemp(prefix='smtp-edge-qualify-', dir='/tmp'))
        command = [sys.executable, str(Path(__file__).resolve()), '--binary', str(binary)]
        report = {'qualified': False, 'binary': str(binary), 'approvedSha256': APPROVED_SHA256, 'tests': {},
                  'blockers': list(LIMITS), 'evidence': str(root), 'reproduce': command}
        try:
            report['tools'] = verify_tools(binary)
        except Exception as error:
            report['blockers'].insert(0, str(error))
            (root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
            print(json.dumps(report, indent=2))
            return 1
        with (root / 'run.log').open('w') as log:
            child = subprocess.Popen(['unshare', '-Urn', *command, '--isolated', str(root),
                                      str(namespace_id('net')), str(namespace_id('user'))],
                                     stdout=log, stderr=subprocess.STDOUT)
            print(f'Evidence: {root}; overall deadline=900s', flush=True)
            try:
                code = child.wait(timeout=900)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                child.terminate()
                try:
                    child.wait(timeout=90)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=10)
                code = 1
        print(f'Evidence: {root}; exit={code}', flush=True)
        return code
    root = Path(args.isolated[0])
    require(root.parent == Path('/tmp') and root.name.startswith('smtp-edge-qualify-'), 'Unsafe evidence path')
    report = {'qualified': False, 'binary': str(binary), 'approvedSha256': APPROVED_SHA256, 'tests': {},
              'blockers': list(LIMITS)}

    def interrupted(signum, frame):
        raise KeyboardInterrupt('Fixture interrupted; native qualification incomplete')

    signal.signal(signal.SIGTERM, interrupted)
    try:
        if args.postfix_control is None:
            check_namespace(int(args.isolated[1]), int(args.isolated[2]))
        else:
            # Docker owns the fresh network; this child maps only its unprivileged
            # UID to root. It must not acquire privileges over that network.
            require(args.postfix_control == root and 1 <= args.postfix_port <= 65535,
                    'Invalid Postfix control path/port')
            require(namespace_id('net') != int(args.isolated[1])
                    and namespace_id('user') != int(args.isolated[2]), 'Host namespace reuse refused')
            isolated()
            interfaces = json.loads(subprocess.check_output(['ip', '-j', 'address', 'show']))
            require(len(interfaces) == 1 and interfaces[0]['ifname'] == 'lo', 'Non-loopback fixture network')
            addresses = {a['local'] for a in interfaces[0]['addr_info']}
            require(addresses == {'127.0.0.1', '::1', PASS_IP, FAIL_IP, PASS_IP6}, 'Unexpected fixture addresses')
        run(root, report, binary, postfix_control=args.postfix_control, postfix_port=args.postfix_port)
    except (Exception, KeyboardInterrupt) as error:
        report['blockers'].insert(0, str(error))
        traceback.print_exc()
    finally:
        (root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2), flush=True)
    return 0 if report.get('nativeExercise') == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
