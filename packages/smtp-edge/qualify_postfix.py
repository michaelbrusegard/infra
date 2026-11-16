#!/usr/bin/env python3
"""Qualify the Postfix edge image against a native Stalwart backend, offline.

Needs local Docker, plus python3, ip, openssl and unshare from the Nix store on
PATH: /nix/store is mounted read-only into the backend container, which runs
qualify.py. The containers share one network with only loopback addresses and
no filesystems. Postfix runs with the production profile: read-only root,
default seccomp, no-new-privileges, the production capability set, and
root-owned mode-0400 TLS files, as Kubernetes Secret mounts would provide.
"""
from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import uuid

HERE = Path(__file__).resolve().parent
CAPS = ['CHOWN', 'SETUID', 'SETGID', 'DAC_OVERRIDE', 'FOWNER', 'KILL', 'NET_BIND_SERVICE']
ADDRESSES = ['192.0.2.10/32', '2001:db8::10/128']
POSTFIX_PORT = 2525
PROBE = ('import socket; s=socket.create_connection(("127.0.0.1",%d),2); '
         's.settimeout(2); assert s.recv(1024).startswith(b"220 ")' % POSTFIX_PORT)
CACHE = {
    'refresh-cache': ('1h', '1s', '1m', '15s'),
    'short-cache': ('5s', '1s', '5s', '1s'),
    'normal-cache': ('1h', '1m', '1m', '15s'),
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(*args, timeout=45, check=True, **kwargs):
    return subprocess.run(list(map(str, args)), capture_output=True, text=True,
                          timeout=timeout, check=check, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', required=True, help='Docker image ID')
    parser.add_argument('--binary', type=Path, required=True, help='Native Stalwart binary')
    parser.add_argument('--deadline', type=int, default=1200)
    args = parser.parse_args()
    evidence = Path(tempfile.mkdtemp(prefix='smtp-edge-postfix-', dir='/tmp'))
    report = {'qualified': False, 'evidence': str(evidence)}
    token = uuid.uuid4().hex[:12]
    network, container = 'smtp-edge-net-' + token, 'smtp-edge-postfix-' + token
    helper = 'smtp-edge-native-' + token
    root = '/tmp/smtp-edge-qualify-' + token
    started, children, logs = [], [], []
    stop_at = time.monotonic() + args.deadline

    def execute(*command, target=container, user=None, env=None, timeout=45, check=True):
        options = ['docker', 'exec']
        if user:
            options += ['--user', user]
        for key, value in (env or {}).items():
            options += ['--env', f'{key}={value}']
        return run(*options, target, *command, timeout=timeout, check=check)

    def native_execute(*command, **kwargs):
        return execute(*command, target=helper, **kwargs)

    def spawn(log_name, command):
        log = (evidence / log_name).open('w')
        logs.append(log)
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        children.append(process)
        return process

    def start_postfix(log_name):
        process = spawn(log_name, ['docker', 'exec', container, '/bin/postfix', 'start-fg'])
        end = min(stop_at, time.monotonic() + 60)
        while time.monotonic() < end:
            if native_execute(tools['python3'], '-c', PROBE, check=False).returncode == 0:
                return process
            require(process.poll() is None, 'Postfix exited during startup')
            time.sleep(0.5)
        raise TimeoutError('Postfix listener did not start')

    try:
        binary = args.binary.resolve(strict=True)
        # Fixture tools run inside the containers from the mounted /nix/store.
        tools = {name: str(Path(shutil.which(name) or name).resolve()) for name in ('python3', 'ip', 'openssl', 'unshare')}
        require(all(path.startswith('/nix/store/') for path in tools.values()),
                f'Fixture tools must come from the Nix store: {tools}')
        # Image bash/curl come first; only fixture tools come from the host closure.
        fixture_path = '/bin:' + ':'.join(dict.fromkeys(str(Path(p).parent) for p in tools.values()))
        store = ['--mount', 'type=bind,src=/nix/store,dst=/nix/store,readonly']
        setup = '; '.join(f'{tools["ip"]} address add {address} dev lo' for address in ADDRESSES)
        # The network owner has no external interface; NET_ADMIN only adds
        # the TEST-NET client addresses to loopback.
        run('docker', 'run', '-d', '--name', network, '--network', 'none', '--read-only',
            '--cap-drop', 'ALL', '--cap-add', 'NET_ADMIN', *store,
            '--entrypoint', '/bin/bash', args.image, '-ec', setup + '; exec /bin/sleep infinity')
        started.append(network)
        cap_args = [part for cap in CAPS for part in ('--cap-add', cap)]
        # Unconfined seccomp lets the backend create its single-UID user namespace.
        run('docker', 'run', '-d', '--name', helper, '--network', 'container:' + network,
            '--read-only', '--cap-drop', 'ALL', *cap_args, '--security-opt', 'seccomp=unconfined',
            '--tmpfs', '/run:rw,nosuid,nodev', '--tmpfs', '/tmp:rw,nosuid,nodev', *store,
            '--mount', f'type=bind,src={HERE},dst=/fixture/packages/smtp-edge,readonly',
            '--mount', f'type=bind,src={HERE.parent / "stalwart-oss"},dst=/fixture/packages/stalwart-oss,readonly',
            '--mount', f'type=bind,src={binary},dst=/fixture/stalwart,readonly',
            '--entrypoint', '/bin/sleep', args.image, 'infinity')
        started.append(helper)
        native_execute('/bin/install', '-d', '-m', '0700', '-o', '102', '-g', '102', root)
        native = spawn('native.log', [
            'docker', 'exec', '--user', '102:102', '--env', 'PATH=' + fixture_path,
            '--env', 'PYTHONDONTWRITEBYTECODE=1', helper, tools['unshare'], '-Ur', tools['python3'],
            '/fixture/packages/smtp-edge/qualify.py', '--binary', '/fixture/stalwart',
            '--root', root, '--postfix-port', str(POSTFIX_PORT)])
        end = min(stop_at, time.monotonic() + 180)
        while (ready := native_execute('/bin/cat', root + '/ready.json', check=False)).returncode != 0:
            require(native.poll() is None, 'Native fixture exited before it was ready; see native.log')
            require(time.monotonic() < end, 'Timed out waiting for the native fixture')
            time.sleep(0.5)
        ready = json.loads(ready.stdout)
        # Copy only the fixture TLS material into Postfix's secrets mount.
        secrets = evidence / 'postfix-secrets'
        secrets.mkdir(mode=0o755)
        for key, name in (('caFile', 'ca.crt'), ('certFile', 'tls.crt'), ('keyFile', 'tls.key')):
            encoded = native_execute('/bin/base64', '-w0', ready[key]).stdout
            (secrets / name).write_bytes(base64.b64decode(encoded, validate=True))
        (secrets / 'resend').write_text('offline-fixture-not-a-real-key\n')
        run('docker', 'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
            '--cap-add', 'CHOWN', '--cap-add', 'FOWNER', '--cap-add', 'DAC_OVERRIDE',
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
        report['versions'] = {'postfix': execute('postconf', '-dh', 'mail_version').stdout.strip(),
                              'curl': execute('curl', '--version').stdout.split()[1]}
        env = {'POSTFIX_HOSTNAME': 'edge.fixture.test', 'BACKENDS': 'manafishrov.com=' + ready['backendHost'],
               'BACKEND_TLS_SERVERNAME': 'localhost', 'BACKEND_LMTP_PORT': ready['lmtpPort'],
               'BACKEND_SMTP_PORT': ready['smtpPort'], 'BACKEND_LOCAL_SMTP_PORT': ready['localSmtpPort'],
               'BACKEND_CA_FILE': '/run/fixture-tls/ca.crt', 'INBOUND_TLS_CERT_FILE': '/run/fixture-tls/tls.crt',
               'INBOUND_TLS_KEY_FILE': '/run/fixture-tls/tls.key', 'RESEND_PASSWORD_FILE': '/run/fixture-tls/resend'}
        execute('/bin/smtp-edge-entrypoint', 'check', env=env, timeout=120)
        execute('postconf', '-MX', 'smtp/inet')
        execute('postconf', '-M', f'{POSTFIX_PORT}/inet={POSTFIX_PORT} inet n - n - - smtpd')
        postfix = start_postfix('postfix.log')
        native_execute('/bin/touch', root + '/continue')

        # Serve the fixture's Postfix control requests until it finishes.
        last_request = 0
        while native.poll() is None:
            require(time.monotonic() < stop_at, 'Qualification deadline exceeded')
            request = native_execute('/bin/cat', root + '/request.json', check=False)
            if request.returncode == 0 and (request := json.loads(request.stdout))['id'] > last_request:
                ident, action = request['id'], request['action']
                before = [json.loads(line) for line in execute('postqueue', '-j').stdout.splitlines()]
                if action == 'restart':
                    execute('postfix', 'stop')
                    postfix.wait(timeout=30)
                    postfix = start_postfix(f'postfix-restart-{ident}.log')
                elif action == 'flush':
                    execute('postqueue', '-f')
                elif action in CACHE:
                    names = ('positive_expire', 'positive_refresh', 'negative_expire', 'negative_refresh')
                    execute('postconf', '-e', *[f'address_verify_{name}_time={value}'
                                               for name, value in zip(names, CACHE[action])])
                    execute('postfix', 'reload')
                    time.sleep(1)
                after = [json.loads(line) for line in execute('postqueue', '-j').stdout.splitlines()]
                response = json.dumps({'id': ident, 'action': action, 'before': before, 'after': after})
                native_execute(tools['python3'], '-c',
                               'from pathlib import Path; import sys; p=Path(sys.argv[1]); '
                               'p.with_suffix(".tmp").write_text(sys.argv[2]); p.with_suffix(".tmp").replace(p)',
                               root + '/response.json', response)
                last_request = ident
            time.sleep(0.25)
        native.wait(timeout=10)
        native_report = json.loads(native_execute('/bin/cat', root + '/report.json').stdout)
        report['tests'] = native_report['tests']
        require(native_report['passed'], 'Native fixture failed: ' + native_report.get('error', 'unknown'))
        require(not execute('postqueue', '-j').stdout.strip(), 'Postfix still has queued messages')
        report['qualified'] = True
    except (Exception, KeyboardInterrupt) as error:
        report['error'] = str(error)
        if isinstance(error, subprocess.CalledProcessError):
            report['commandError'] = {'argv': list(map(str, error.cmd)), 'stdout': error.stdout, 'stderr': error.stderr}
    finally:
        try:
            for name, filename in ((container, 'container.log'), (helper, 'native-container.log')):
                if name in started:
                    output = run('docker', 'logs', name, check=False)
                    (evidence / filename).write_text(output.stdout + output.stderr)
            if helper in started:
                exported = native_execute(tools['python3'], '-c',
                                          'from pathlib import Path; import base64,json,sys; r=Path(sys.argv[1]); '
                                          'paths=[*r.glob("*.json"),*r.glob("*.eml"),r/"backend/server.log"]; '
                                          'print(json.dumps({str(p.relative_to(r)):base64.b64encode(p.read_bytes()).decode() '
                                          'for p in paths if p.is_file()}))', root, check=False)
                if exported.returncode == 0:
                    for name, content in json.loads(exported.stdout).items():
                        destination = evidence / 'native' / name
                        destination.parent.mkdir(parents=True, exist_ok=True)
                        destination.write_bytes(base64.b64decode(content))
            if container in started:
                report['finalPostfixQueue'] = execute('postqueue', '-j', check=False).stdout
                execute('postfix', 'stop', check=False)
        except Exception as error:
            report['qualified'] = False
            report['evidenceError'] = str(error)
        finally:
            for name in reversed(started):
                run('docker', 'rm', '-f', name, check=False)
            for child in children:
                if child.poll() is None:
                    child.terminate()
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=10)
            for log in logs:
                log.close()
            (evidence / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'qualified': report['qualified'], 'evidence': str(evidence), 'error': report.get('error')}, indent=2))
    return 0 if report['qualified'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
