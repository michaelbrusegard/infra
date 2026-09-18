"""Disposable authoritative DNS and DKIM signing for isolated SMTP fixtures."""
import base64
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import time

from integration import require
from mail import isolated


class AuthDNS:
    """Use the already installed BIND, with no forwarding or host DNS changes."""
    def __init__(self, root, key):
        isolated()
        self.root, self.key, self.process, self.log = Path(root), key, None, None
        self.root.mkdir()
        public = subprocess.run(['openssl', 'pkey', '-in', str(key), '-pubout', '-outform', 'DER'],
                                capture_output=True, check=True, timeout=10).stdout
        public = base64.b64encode(public).decode()
        # Serve com only inside netns: parent DMARC queries need NXDOMAIN,
        # not REFUSED. example.com avoids invalid-TLD spam penalties for .test.
        zone = ('$TTL 60\n@ IN SOA ns.auth.example.com. hostmaster.auth.example.com. (1 60 60 60 60)\n'
                '@ IN NS ns.auth.example.com.\nns.auth.example IN A 127.0.0.1\n'
                'edge.auth.example IN A 10.200.0.2\n'
                'pass.auth.example IN A 192.0.2.10\npass.auth.example IN TXT "v=spf1 ip4:192.0.2.10 -all"\n'
                'fail.auth.example IN A 192.0.2.11\nfail.auth.example IN TXT "v=spf1 -all"\n'
                'na.auth.example IN A 192.0.2.10\n'
                'blocked.auth.example IN A 192.0.2.10\n'
                'blocked.auth.example IN TXT "v=spf1 ip4:192.0.2.10 -all"\n'
                '_dmarc.blocked.auth.example IN TXT "v=DMARC1; p=reject; aspf=s; adkim=s"\n'
                '_dmarc.pass.auth.example IN TXT "v=DMARC1; p=reject; aspf=s; adkim=s"\n'
                '_dmarc.fail.auth.example IN TXT "v=DMARC1; p=reject; aspf=s; adkim=s"\n')
        txt = 'v=DKIM1; k=rsa; p=' + public
        zone += 'fixture._domainkey.fail.auth.example IN TXT (' + ' '.join(
            '"' + txt[i:i + 200] + '"' for i in range(0, len(txt), 200)) + ')\n'
        (self.root / 'zone').write_text(zone)
        (self.root / 'named.conf').write_text(
            f'options {{ directory "{self.root}"; listen-on port 15353 {{ 127.0.0.1; }}; '
            'listen-on-v6 { none; }; recursion no; dnssec-validation no; querylog yes; '
            f'pid-file "{self.root}/named.pid"; session-keyfile "{self.root}/session.key"; }};\n'
            f'controls {{ }}; zone "com" {{ type primary; file "{self.root}/zone"; }};\n')

    def __enter__(self):
        require(shutil.which('named') is not None, 'Fixture needs the installed named executable')
        self.log = (self.root / 'named.log').open('w')
        self.process = subprocess.Popen(['named', '-g', '-n', '1', '-c', str(self.root / 'named.conf')],
                                        stdout=self.log, stderr=subprocess.STDOUT)
        time.sleep(0.5)
        if self.process.poll() is not None:
            self.__exit__(None, None, None)
            raise AssertionError('Fixture authoritative DNS failed to start')
        return self

    def __exit__(self, *_):
        if self.process is not None:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=10)
        if self.log is not None:
            self.log.close()

    def sign(self, raw, names=None):
        """RSA-SHA256 relaxed/relaxed; signs only newly generated fixture mail."""
        headers, body = raw.split(b'\r\n\r\n', 1)
        body = b'\r\n'.join(re.sub(rb'[ \t]+', b' ', line).rstrip(b' ')
                            for line in body.split(b'\r\n')).rstrip(b'\r\n') + b'\r\n'
        names = names or (b'from', b'to', b'subject', b'date', b'message-id')
        fields = []
        for field in re.split(rb'\r\n(?![ \t])', headers):
            name, value = field.split(b':', 1)
            value = re.sub(rb'[ \t\r\n]+', b' ', value).strip()
            if name.lower() in names:
                fields.append((name.lower(), name.lower() + b':' + value))
        # DKIM selects repeated fields from the bottom, consuming each match.
        # An absent occurrence is allowed in h= (oversigning) but contributes
        # no canonicalized header bytes to the signature input.
        remaining = list(reversed(fields))
        signed = []
        for name in names:
            for index, (key, value) in enumerate(remaining):
                if key == name:
                    signed.append(value)
                    remaining.pop(index)
                    break
        signature = (b'v=1; a=rsa-sha256; c=relaxed/relaxed; d=fail.auth.example.com; s=fixture; h='
                     + b':'.join(names) + b'; bh=' + base64.b64encode(hashlib.sha256(body).digest()) + b'; b=')
        data = b'\r\n'.join(signed) + b'\r\ndkim-signature:' + signature
        result = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', str(self.key)], input=data,
                                capture_output=True, check=True, timeout=10).stdout
        return b'DKIM-Signature: ' + signature + base64.b64encode(result) + b'\r\n' + raw


RESOLVER = {'@type': 'Custom', 'servers': {'0': {
    'protocol': 'udp', 'address': '127.0.0.1', 'port': 15353}},
    'attempts': 1, 'timeout': 1000, 'concurrency': 2, 'enableEdns': False, 'tcpOnError': False}
