#!/usr/bin/env python3
"""Run the approved native fixture through the immutable Postfix image, offline.

Requires local Docker and installed Nix python3, named, ip, openssl and unshare.
The network owner has NET_ADMIN only to configure TEST-NET loopback addresses.
Postfix uses default Docker seccomp, no-new-privileges, production capabilities,
read-only root, and root-owned mode-0400 synthetic TLS mounts. A separate native
helper uses unconfined seccomp only for its single-UID namespace child. They
share only an isolated network, not filesystems or PID/user namespaces. No host
credentials, Docker socket, host network, or writable repository is mounted.

qualify.py owns native fixtures and authentication assertions. Its handshake is
--postfix-control ROOT --postfix-port 2525 --isolated ROOT HOST_NETNS HOST_USERNS:
write ready.json while native/DNS remain alive, wait for ROOT/continue, then
exercise actual SMTP ingress. Direct-only cases must remain labelled as such.
Image changes require an explicit new --image sha256:... approval, never a tag.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

HERE = Path(__file__).resolve().parent
IMAGE = 'sha256:8073c80ee903205fc9b2ad1096fbc57565d81441f7adc623156f478c6e505da0'
BINARY = Path('/tmp/stalwart-edge-qualification/stalwart')
BINARY_SHA256 = '02030a8334e3bc62bae1fa4a9139f498df0a7e105bd97ec5beacfdfa1be8b614'
CAPS = ['CHOWN', 'SETUID', 'SETGID', 'DAC_OVERRIDE', 'FOWNER', 'KILL', 'NET_BIND_SERVICE']
CAP_MASK = sum(1 << bit for bit in (0, 1, 3, 5, 6, 7, 10))
ADDRESSES = ['192.0.2.10/32', '192.0.2.11/32', '2001:db8::10/128']


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def run(*args, timeout=45, check=True, **kwargs):
    return subprocess.run(list(map(str, args)), capture_output=True, text=True,
                          timeout=timeout, check=check, **kwargs)


def inspect(name):
    return json.loads(run('docker', 'inspect', name).stdout)[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', default=IMAGE, help='Explicit approved immutable Docker image ID')
    parser.add_argument('--binary', type=Path, default=BINARY)
    parser.add_argument('--deadline', type=int, default=1200)
    args = parser.parse_args()
    evidence = Path(tempfile.mkdtemp(prefix='smtp-edge-postfix-', dir='/tmp'))
    evidence.chmod(0o700)
    report = {'qualified': False, 'evidence': str(evidence), 'tests': {}, 'limitations': [
        'Disposable fixture only; not production cutover approval',
        'Resend is unreachable; production DSN acceptance is not qualified',
        'Native report distinguishes direct-adapter-only cases from Postfix ingress cases',
        'Finite optimistic verification cache deliberately differs from the retired custom policy',
    ]}
    token = uuid.uuid4().hex[:12]
    network, container = 'smtp-edge-net-' + token, 'smtp-edge-proof-' + token
    helper = 'smtp-edge-native-' + token
    root = '/tmp/smtp-edge-qualify-' + token
    started = []
    children = []
    files = []
    stop_at = time.monotonic() + args.deadline

    def execute(*command, target=container, user=None, env=None, timeout=45, check=True):
        options = ['docker', 'exec']
        if user:
            options += ['--user', user]
        for key, value in (env or {}).items():
            options += ['--env', key + '=' + str(value)]
        return run(*options, target, *command, timeout=timeout, check=check)

    def native_execute(*command, **kwargs):
        return execute(*command, target=helper, **kwargs)

    def spawn(log_name, command):
        log = (evidence / log_name).open('w')
        files.append(log)
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        children.append(process)
        return process

    def wait_file(path, process, timeout=180):
        end = min(stop_at, time.monotonic() + timeout)
        while time.monotonic() < end:
            result = native_execute('/bin/cat', path, check=False)
            if result.returncode == 0:
                return result.stdout
            require(process.poll() is None, f'Native fixture exited before {path}; inspect native.log')
            time.sleep(0.5)
        raise TimeoutError('Timed out waiting for ' + path)

    try:
        require(re.fullmatch(r'sha256:[0-9a-f]{64}', args.image), 'Refusing a mutable image reference')
        require(60 <= args.deadline <= 3600, 'Deadline must be between 60 and 3600 seconds')
        binary = args.binary.resolve(strict=True)
        require(digest(binary) == BINARY_SHA256, 'Unapproved native Stalwart binary')
        require(not os.environ.get('DOCKER_HOST'), 'Use the local Unix-socket Docker context, not DOCKER_HOST')
        context = json.loads(run('docker', 'context', 'inspect').stdout)[0]
        require(context['Endpoints']['docker']['Host'].startswith('unix://'), 'Refusing remote Docker context')
        image = inspect(args.image)
        require(image['Id'] == args.image, 'Docker image identity mismatch')
        report['image'] = {'id': image['Id'], 'size': image['Size']}
        report['binarySha256'] = BINARY_SHA256
        report['sourceSha256'] = {p.name: digest(p) for p in
                                 [Path(__file__), HERE / 'qualify.py', HERE / 'deliver.sh',
                                  HERE / 'main.cf', HERE / 'master.cf', HERE / 'entrypoint.sh',
                                  *(HERE.parent / 'stalwart-oss' / name for name in
                                    ('integration.py', 'mail.py', 'smtp_fixture.py', 'edge_dns.py'))]}
        tools = {}
        for name in ('python3', 'named', 'ip', 'openssl', 'unshare'):
            path = shutil.which(name)
            require(path is not None, 'Missing fixture tool ' + name)
            resolved = Path(path).resolve(strict=True)
            require(str(resolved).startswith('/nix/store/'), 'Fixture tool is not in immutable Nix store: ' + name)
            tools[name] = str(resolved)
        # Keep image bash/curl first; only fixture tools come from the host closure.
        fixture_path = '/bin:' + ':'.join(dict.fromkeys(str(Path(p).parent) for p in tools.values()))
        host_net = os.stat('/proc/self/ns/net').st_ino
        host_user = os.stat('/proc/self/ns/user').st_ino
        report['hostNamespaces'] = {'net': host_net, 'user': host_user}
        # The approved host binary may be mode 0700. Give the isolated UID a
        # read-only copy, without changing the original artifact's permissions.
        mounted_binary = evidence / 'approved-stalwart'
        run('cp', '--reflink=auto', '--', binary, mounted_binary)
        mounted_binary.chmod(0o555)
        require(digest(mounted_binary) == BINARY_SHA256, 'Copied binary identity mismatch')
        mounts = ['--mount', 'type=bind,src=/nix/store,dst=/nix/store,readonly']
        setup = '; '.join([f'{tools["ip"]} address add {address} dev lo' for address in ADDRESSES])
        run('docker', 'run', '-d', '--name', network, '--network', 'none', '--read-only',
            '--cap-drop', 'ALL', '--cap-add', 'NET_ADMIN', *mounts,
            '--entrypoint', '/bin/bash', args.image, '-ec', setup + '; exec /bin/sleep infinity')
        started.append(network)
        net_state = inspect(network)
        require(net_state['HostConfig']['NetworkMode'] == 'none', 'Network owner is not network-none')
        require(not net_state['HostConfig']['Privileged'], 'Privileged fixture forbidden')
        cap_args = [part for cap in CAPS for part in ('--cap-add', cap)]
        run('docker', 'run', '-d', '--name', helper, '--network', 'container:' + network,
            '--read-only', '--cap-drop', 'ALL', *cap_args, '--security-opt', 'seccomp=unconfined',
            '--tmpfs', '/run:rw,nosuid,nodev', '--tmpfs', '/tmp:rw,nosuid,nodev', *mounts,
            '--mount', f'type=bind,src={HERE},dst=/fixture/packages/smtp-edge,readonly',
            '--mount', f'type=bind,src={HERE.parent / "stalwart-oss"},dst=/fixture/packages/stalwart-oss,readonly',
            '--mount', f'type=bind,src={mounted_binary},dst=/approved/stalwart,readonly',
            '--entrypoint', '/bin/sleep', args.image, 'infinity')
        started.append(helper)
        state = inspect(helper)
        config = state['HostConfig']
        require(state['Image'] == args.image and config['ReadonlyRootfs'], 'Unexpected runtime image/root mode')
        require(config['NetworkMode'] in ('container:' + network, 'container:' + net_state['Id']),
                'Postfix is outside the isolated network owner')
        require(not config['Privileged'] and not config.get('PortBindings'), 'Unsafe container privileges/ports')
        require({c.removeprefix('CAP_') for c in config['CapAdd']} == set(CAPS)
                and config['CapDrop'] == ['ALL'], 'Capability drift')
        require(all(not m['RW'] for m in state['Mounts'] if m['Type'] == 'bind'), 'Writable host bind mount')
        report['nativeContainerGuard'] = {'id': state['Id'], 'networkOwner': net_state['Id'],
                                          'networkOwnerMode': 'none', 'readonlyRoot': True,
                                          'seccomp': 'unconfined (native helper only)'}
        addresses = json.loads(native_execute(tools['ip'], '-j', 'addr', 'show').stdout)
        require(len(addresses) == 1 and addresses[0]['ifname'] == 'lo', 'Non-loopback fixture interface')
        allowed = {'127.0.0.1', '::1', '192.0.2.10', '192.0.2.11', '2001:db8::10'}
        require({a['local'] for a in addresses[0]['addr_info']} == allowed, 'Unexpected loopback addresses')
        report['addresses'] = addresses
        require(native_execute('/bin/sha256sum', '/approved/stalwart').stdout.split()[0] == BINARY_SHA256,
                'Mounted binary identity mismatch')
        native_execute('/bin/install', '-d', '-m', '0700', '-o', '102', '-g', '102', root)
        command = ['docker', 'exec', '--user', '102:102', '--env', 'PATH=' + fixture_path,
                   '--env', 'PYTHONDONTWRITEBYTECODE=1', helper, tools['unshare'], '-Ur', tools['python3'],
                   '/fixture/packages/smtp-edge/qualify.py', '--binary', '/approved/stalwart',
                   '--postfix-control', root, '--postfix-port', '2525', '--isolated', root,
                   str(host_net), str(host_user)]
        report['nativeCommand'] = command
        native = spawn('native.log', command)
        ready = json.loads(wait_file(root + '/ready.json', native))
        require(ready['backendHost'] == '127.0.0.1', 'Non-loopback backend in ready contract')
        for name in ('lmtpPort', 'smtpPort', 'localSmtpPort'):
            require(type(ready[name]) is int and 1 <= ready[name] <= 65535 and ready[name] != 2525,
                    'Invalid backend port: ' + name)
        for name in ('caFile', 'certFile', 'keyFile'):
            require(str(ready[name]).startswith(root + '/') and '..' not in Path(ready[name]).parts,
                    'Fixture TLS file escaped evidence root')
        report['ready'] = ready
        # Independent copies, not a shared helper volume. Only fixture TLS
        # material crosses this boundary; native state/control files stay private.
        secrets = evidence / 'postfix-secrets'
        secrets.mkdir(mode=0o755)
        secrets.chmod(0o755)
        for key, name in (('caFile', 'ca.crt'), ('certFile', 'tls.crt'), ('keyFile', 'tls.key')):
            encoded = native_execute('/bin/base64', '-w0', ready[key]).stdout
            (secrets / name).write_bytes(base64.b64decode(encoded, validate=True))
            (secrets / name).chmod(0o400)
        (secrets / 'resend').write_text('offline-fixture-not-a-real-key\n')
        # A bounded, network-none setup container sets synthetic file ownership
        # to root, matching Kubernetes Secret mounts without host sudo or secrets.
        run('docker', 'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
            '--cap-add', 'CHOWN', '--cap-add', 'FOWNER', '--cap-add', 'DAC_OVERRIDE',
            '--security-opt', 'no-new-privileges=true',
            '--mount', f'type=bind,src={secrets},dst=/secrets', '--entrypoint', '/bin/bash', args.image,
            '-ec', 'chown 0:0 /secrets/*; chmod 0400 /secrets/*; chmod 0644 /secrets/ca.crt')
        run('docker', 'run', '-d', '--name', container, '--network', 'container:' + network,
            '--read-only', '--cap-drop', 'ALL', *cap_args, '--security-opt', 'no-new-privileges=true',
            '--tmpfs', '/run:rw,nosuid,nodev', '--tmpfs', '/tmp:rw,nosuid,nodev',
            '--tmpfs', '/var/lib/postfix:rw,nosuid,nodev',
            '--tmpfs', '/var/lib/postfix/queue/pid:rw,nosuid,nodev,mode=0755',
            '--mount', f'type=bind,src={secrets},dst=/run/fixture-tls,readonly',
            '--entrypoint', '/bin/sleep', args.image, 'infinity')
        started.append(container)
        state = inspect(container)
        config = state['HostConfig']
        require(state['Image'] == args.image and config['ReadonlyRootfs'], 'Unexpected Postfix image/root mode')
        require(config['NetworkMode'] in ('container:' + network, 'container:' + net_state['Id']),
                'Postfix is outside the isolated network owner')
        require(not config['Privileged'] and not config.get('PortBindings'), 'Unsafe Postfix privileges/ports')
        require({c.removeprefix('CAP_') for c in config['CapAdd']} == set(CAPS)
                and config['CapDrop'] == ['ALL'], 'Postfix capability drift')
        require(config['SecurityOpt'] == ['no-new-privileges=true'], 'Unexpected Postfix security overrides')
        binds = [m for m in state['Mounts'] if m['Type'] == 'bind']
        require(len(binds) == 1 and binds[0]['Destination'] == '/run/fixture-tls' and not binds[0]['RW'],
                'Postfix may mount only its read-only synthetic secrets, never host tools/native state')
        require(not config['PidMode'] and not config['UsernsMode'], 'Unexpected shared PID/user namespace')
        report['containerGuard'] = {'id': state['Id'], 'networkOwner': net_state['Id'], 'networkOwnerMode': 'none',
                                    'capabilities': CAPS, 'readonlyRoot': True, 'noNewPrivileges': True,
                                    'seccomp': 'Docker default', 'bindMounts': binds}
        modes = execute('/bin/stat', '-c', '%u:%g %a %n', '/run/fixture-tls/tls.crt',
                        '/run/fixture-tls/tls.key', '/run/fixture-tls/resend').stdout.splitlines()
        require(len(modes) == 3 and all(row.startswith('0:0 400 ') for row in modes), 'Secret mount mode/owner drift')
        report['secretMountModes'] = modes
        for name in ('master.cf', 'deliver.sh'):
            require(execute('/bin/cat', '/opt/smtp-edge/' + name).stdout == (HERE / name).read_text(),
                    'Image/source mismatch: ' + name)
        require(execute('/bin/cat', '/opt/smtp-edge/main.cf').stdout.startswith((HERE / 'main.cf').read_text()),
                'Image/source mismatch: main.cf')
        report['versions'] = {'postfix': execute('postconf', '-dh', 'mail_version').stdout.strip(),
                              'curl': execute('curl', '--version').stdout.splitlines()[0]}
        require(report['versions']['postfix'] == '3.11.3' and report['versions']['curl'].startswith('curl 8.20.0 '),
                'Unexpected executable version')
        env = {'POSTFIX_HOSTNAME': 'edge.fixture.test', 'BACKEND_HOST': ready['backendHost'],
               'BACKEND_TLS_SERVERNAME': 'localhost', 'BACKEND_LMTP_PORT': ready['lmtpPort'],
               'BACKEND_SMTP_PORT': ready['smtpPort'], 'BACKEND_LOCAL_SMTP_PORT': ready['localSmtpPort'],
               'BACKEND_CA_FILE': '/run/fixture-tls/ca.crt', 'INBOUND_TLS_CERT_FILE': '/run/fixture-tls/tls.crt',
               'INBOUND_TLS_KEY_FILE': '/run/fixture-tls/tls.key', 'RESEND_PASSWORD_FILE': '/run/fixture-tls/resend'}
        execute('/bin/smtp-edge-entrypoint', 'check', env=env, timeout=120)
        execute('postconf', '-MX', 'smtp/inet')
        execute('postconf', '-M', '2525/inet=2525 inet n - n - - smtpd')
        if os.environ.get('SMTP_EDGE_TRACE_SYNTHETIC') == '1':
            service = execute('postconf', '-M', 'forward/unix').stdout.strip()
            execute('postconf', '-M', 'forward/unix=' + service.replace('argv=/bin/bash ', 'argv=/bin/bash -x '))
            report['syntheticTraceEnabled'] = True
        postfix = spawn('postfix.log', ['docker', 'exec', container, '/bin/postfix', 'start-fg'])
        end = min(stop_at, time.monotonic() + 60)
        while time.monotonic() < end:
            result = native_execute(tools['python3'], '-c',
                             'import socket; s=socket.create_connection(("127.0.0.1",2525),2); '
                             's.settimeout(2); assert s.recv(1024).startswith(b"220 "); s.close()', check=False)
            if result.returncode == 0:
                break
            require(postfix.poll() is None, 'Postfix exited during startup')
            time.sleep(0.5)
        else:
            raise TimeoutError('Postfix listener did not start')
        report['postconf'] = execute('postconf', '-n').stdout
        report['masterCf'] = execute('postconf', '-M').stdout
        require(execute('postconf', '-h', 'header_checks').stdout.strip() == '', 'Unexpected header rewriting')
        status = execute('/bin/bash', '-ec',
                         'read -r pid < /var/lib/postfix/queue/pid/master.pid; cat /proc/$pid/status').stdout
        cap_eff = re.search(r'^CapEff:\s*([0-9a-f]+)$', status, re.M)
        require(cap_eff and int(cap_eff[1], 16) == CAP_MASK, 'Postfix effective capabilities differ from production set')
        report['postfixCapabilities'] = cap_eff[1]
        require(re.search(r'^NoNewPrivs:\s*1$', status, re.M)
                and re.search(r'^Seccomp:\s*2$', status, re.M), 'Postfix lacks NNP/seccomp enforcement')
        report['postfixProcessSecurity'] = {'noNewPrivileges': 1, 'seccomp': 2, 'capEff': cap_eff[1]}
        report['tests']['productionCapabilitiesStartup'] = {'status': 'PASS'}
        native_execute('/bin/touch', root + '/continue')
        last_request = 0
        report['controls'] = []
        while native.poll() is None:
            require(time.monotonic() < stop_at, 'Native deadline exceeded')
            request = native_execute('/bin/cat', root + '/request.json', check=False)
            if request.returncode == 0:
                request = json.loads(request.stdout)
                ident, action = request['id'], request['action']
                require(type(ident) is int and ident > 0 and action in ('queue', 'restart', 'flush', 'refresh-cache', 'short-cache', 'normal-cache'),
                        'Invalid fixture control request')
                if ident > last_request:
                    before = [json.loads(line) for line in execute('postqueue', '-j').stdout.splitlines()]
                    if action == 'restart':
                        execute('postfix', 'stop')
                        postfix.wait(timeout=30)
                        postfix = spawn(f'postfix-restart-{ident}.log',
                                        ['docker', 'exec', container, '/bin/postfix', 'start-fg'])
                        end = time.monotonic() + 30
                        while time.monotonic() < end:
                            probe = native_execute(tools['python3'], '-c',
                                            'import socket; s=socket.create_connection(("127.0.0.1",2525),2); '
                                            's.settimeout(2); assert s.recv(1024).startswith(b"220 "); s.close()', check=False)
                            if probe.returncode == 0:
                                break
                            time.sleep(0.2)
                        else:
                            raise TimeoutError('Postfix restart failed')
                    elif action == 'flush':
                        execute('postqueue', '-f')
                    elif action.endswith('-cache'):
                        settings = {
                            'refresh-cache': ('1h', '1s', '1m', '15s'),
                            'short-cache': ('5s', '1s', '5s', '1s'),
                            'normal-cache': ('1h', '1m', '1m', '15s'),
                        }[action]
                        names = ('positive_expire', 'positive_refresh', 'negative_expire', 'negative_refresh')
                        execute('postconf', '-e', *[f'address_verify_{name}_time={value}'
                                                   for name, value in zip(names, settings)])
                        execute('postfix', 'reload')
                        time.sleep(1)
                    after = [json.loads(line) for line in execute('postqueue', '-j').stdout.splitlines()]
                    response = {'id': ident, 'action': action, 'status': 'PASS', 'before': before, 'after': after}
                    if action == 'restart':
                        require(sorted(row['queue_id'] for row in before) == sorted(row['queue_id'] for row in after),
                                'Queue IDs changed across Postfix restart')
                    report['controls'].append(response)
                    native_execute(tools['python3'], '-c',
                            'from pathlib import Path; import sys; p=Path(sys.argv[1]); '
                            'p.with_suffix(".tmp").write_text(sys.argv[2]); p.with_suffix(".tmp").replace(p)',
                            root + '/response.json', json.dumps(response))
                    last_request = ident
            time.sleep(0.25)
        code = native.wait(timeout=10)
        native_report = json.loads(native_execute('/bin/cat', root + '/report.json').stdout)
        report['nativeReport'] = native_report
        require(code == 0 and native_report.get('nativeExercise') == 'PASS', 'Native Postfix exercise failed')
        tests = native_report.get('tests', {})
        require(tests and all(t.get('status') == 'PASS' for t in tests.values()), 'Native assertions incomplete')
        sample = native_execute('/bin/cat', root + '/direct-spf-pass.eml').stdout
        require('by edge.fixture.test (Postfix)' in sample, 'Native proof lacks an actual Postfix Received hop')
        require(any('utf8' in name.lower() for name in tests), 'Native SMTPUTF8 envelope/body assertion missing')
        queue = execute('postqueue', '-j').stdout
        require(not queue.strip(), 'Postfix still has queued messages after native delivery assertions')
        report['tests']['nativeAuthenticationThroughPostfix'] = {'status': 'PASS'}
        report['tests']['postfixQueueDrained'] = {'status': 'PASS'}
        require(not report.get('syntheticTraceEnabled'), 'Diagnostic tracing is not release qualification')
        report['qualified'] = True
    except (Exception, KeyboardInterrupt) as error:
        report['error'] = str(error)
        if isinstance(error, subprocess.CalledProcessError):
            report['commandError'] = {'argv': list(map(str, error.cmd)), 'stdout': error.stdout, 'stderr': error.stderr}
    finally:
        try:
            for name, filename in ((container, 'container.log'), (helper, 'native-container.log')):
                if name in started:
                    logs = run('docker', 'logs', name, check=False)
                    (evidence / filename).write_text(logs.stdout + logs.stderr)
            # Export synthetic evidence from the native helper, not Postfix's
            # independent filesystem. No host Python/tool mounts enter Postfix.
            if helper in started and 'tools' in locals():
                exported = native_execute(tools['python3'], '-c',
                                          'from pathlib import Path; import base64,json,sys; r=Path(sys.argv[1]); '
                                          'paths=[*r.glob("*.json"),*r.glob("*.eml"),r/"backend/server.log"]; '
                                          'print(json.dumps({str(p.relative_to(r)):base64.b64encode(p.read_bytes()).decode() '
                                          'for p in paths if p.is_file()}))', root, check=False)
                if exported.returncode == 0:
                    for name, content in json.loads(exported.stdout).items():
                        relative = Path(name)
                        require(not relative.is_absolute() and '..' not in relative.parts, 'Unsafe evidence path')
                        destination = evidence / 'native' / relative
                        destination.parent.mkdir(parents=True, exist_ok=True)
                        destination.write_bytes(base64.b64decode(content))
            if container in started:
                report['finalPostfixQueue'] = execute('postqueue', '-j', check=False).stdout
                report['finalQueueEnvelopeMetadata'] = []
                for line in report['finalPostfixQueue'].splitlines():
                    ident = json.loads(line)['queue_id']
                    require(re.fullmatch(r'[A-Za-z0-9]+', ident), 'Invalid queue ID')
                    report['finalQueueEnvelopeMetadata'].append(execute('postcat', '-qe', ident, check=False).stdout)
                execute('postfix', 'stop', check=False)
        except Exception as error:
            report['qualified'] = False
            report['evidenceError'] = str(error)
        finally:
            for name in reversed(started):
                try:
                    run('docker', 'rm', '-f', name, check=False)
                except Exception as error:
                    report['qualified'] = False
                    report.setdefault('cleanupErrors', []).append(str(error))
            for child in children:
                if child.poll() is None:
                    child.terminate()
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=10)
            for log in files:
                log.close()
            (evidence / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'qualified': report['qualified'], 'evidence': str(evidence), 'error': report.get('error')}, indent=2))
    return 0 if report['qualified'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
