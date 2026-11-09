#!/usr/bin/env python3
"""Extract historical usage already archived in ClickHouse.

Default: read-only dry run. --output retains a usage-only JSONL export.
--apply appends deduplicated records to llm.historical_usage. The dashboard
uses FINAL, so rerunning the same import does not change logical totals.
"""

import argparse
from collections import Counter
from contextlib import contextmanager
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import tempfile
import urllib.parse
import urllib.request


def number(value):
    return max(0, int(value or 0))


def object_value(value):
    return json.loads(value) if isinstance(value, str) and value not in ('', 'null') else (value or {})


def provider_for(model, fallback='unknown'):
    for prefix, provider in (('claude-', 'claude'), ('gpt-', 'codex'), ('kimi-', 'kimi'), ('gemini-', 'gemini')):
        if model.startswith(prefix):
            return provider
    return fallback or 'unknown'


class Extractor:
    def __init__(self, database):
        self.db = database
        self.db.execute('CREATE TABLE events (event_id TEXT PRIMARY KEY, response_id TEXT UNIQUE, '
                        'score INTEGER, tokens INTEGER, row TEXT)')
        self.stats = Counter()
        self.file = None
        self.session = self.model = self.turn = ''

    def add(self, item):
        self.stats['projected_records'] += 1
        file = tuple(item.get(k, '') for k in ('source', 'host', 'session', 'path'))
        if file != self.file:
            self.file = file
            self.session, self.model, self.turn = item['session'], '', ''
        source, kind = item['source'], item.get('kind', '')
        if item.get('native_session'):
            self.session = item['native_session']
        if kind == 'turn_context':
            self.model = item.get('model', '')
            self.turn = item.get('turn_id', '')
        if kind in ('session_meta', 'turn_context', 'session', 'model_change'):
            return
        usage = object_value(item.get('usage'))
        if not usage:
            return
        model = item.get('model') or (self.model if source == 'codex' else '') or '(unknown)'
        provider = provider_for(model, item.get('provider', ''))
        read = write = output = reasoning = fresh = short_write = long_write = 0
        score = 1
        if source == 'codex':
            read = number(usage.get('cached_input_tokens'))
            write = number(usage.get('cache_write_input_tokens'))
            fresh = max(0, number(usage.get('input_tokens')) - read - write)
            output = number(usage.get('output_tokens'))
            reasoning = number(usage.get('reasoning_output_tokens'))
            cumulative = object_value(item.get('cumulative'))
            # Both formats describe the same cumulative point. Prefer the newer
            # per-response record; never sum the running total as per-call usage.
            total = number(cumulative.get('total_tokens'))
            if not total:
                self.stats['codex_missing_cumulative'] += 1
                return
            identity = f'codex:{self.session}:{total}'
            score = 4 if kind == 'token_usage_record' else 2
        elif source == 'claude-code':
            fresh = number(usage.get('input_tokens'))
            read = number(usage.get('cache_read_input_tokens'))
            write = number(usage.get('cache_creation_input_tokens'))
            output = number(usage.get('output_tokens'))
            reasoning = number((usage.get('output_tokens_details') or {}).get('thinking_tokens'))
            cache = usage.get('cache_creation') or {}
            short_write = number(cache.get('ephemeral_5m_input_tokens'))
            long_write = number(cache.get('ephemeral_1h_input_tokens'))
            identity = f"claude:{item.get('response_id') or ':'.join(file[1:]) + ':' + item['id']}"
            score = 3
        elif source == 'pi':
            fresh, output = number(usage.get('input')), number(usage.get('output'))
            read, write = number(usage.get('cacheRead')), number(usage.get('cacheWrite'))
            reasoning = number(usage.get('reasoning'))
            # Entry IDs survive Pi branches; the response ID also deduplicates
            # records copied between clients when the provider exposes one.
            identity = f"pi:{item.get('entry_id') or item['id']}:{item.get('ts', '')}"
        elif source == 'opencode':
            fresh = number(usage.get('input'))
            cache = usage.get('cache') or {}
            read, write = number(cache.get('read')), number(cache.get('write'))
            reasoning = number(usage.get('reasoning'))
            raw_output = number(usage.get('output'))
            # Current OpenCode stores text output separately from reasoning.
            # Older records can include reasoning in output; a recorded total
            # distinguishes those without changing the saved token total.
            base = fresh + read + write + raw_output
            output = raw_output if usage.get('total') == base else raw_output + reasoning
            identity = f"opencode:{item.get('entry_id') or self.session + ':' + item['id']}"
        else:
            return
        total = fresh + read + write + output
        if total == 0:
            self.stats['zero_usage'] += 1
            return
        stamp = item.get('ts', '')
        if not stamp or stamp.startswith('1970-'):
            self.stats['missing_timestamp'] += 1
            return
        response = item.get('response_id') or None
        # A response ID is globally unique within its provider, not its client.
        response = f'{provider}:{response}' if response else None
        event_id = hashlib.sha256(identity.encode()).hexdigest()
        row = dict(event_id=event_id, source=source, host=item.get('host', ''), session_id=self.session,
                   requested_at=stamp, provider=provider, model=model,
                   uncached_input_tokens=fresh, cache_read_tokens=read, cache_creation_tokens=write,
                   cache_write_5m_tokens=short_write, cache_write_1h_tokens=long_write,
                   output_tokens=output, reasoning_tokens=min(reasoning, output))
        prior = self.db.execute('SELECT event_id, score, tokens, row FROM events '
                                'WHERE event_id = ? OR response_id = ?', (event_id, response)).fetchall()
        if prior:
            self.stats['duplicate_records'] += 1
            if any((old[1], old[2]) > (score, total) for old in prior):
                return
            for old_id, _, _, old_json in prior:
                old = json.loads(old_json)
                # Stable event time for streamed chunks and copied transcripts.
                row['requested_at'] = min(row['requested_at'], old['requested_at'])
                self.db.execute('DELETE FROM events WHERE event_id = ?', (old_id,))
        self.db.execute('INSERT INTO events VALUES (?, ?, ?, ?, ?)',
                        (event_id, response, score, total, json.dumps(row, separators=(',', ':'))))

    def rows(self):
        for (row,) in self.db.execute('SELECT row FROM events ORDER BY event_id'):
            yield row


def client_args(query):
    return ['kubectl', 'exec', '-i', '-n', 'clickhouse', 'clickhouse-0', '--',
            'clickhouse-client', '--query', query]


@contextmanager
def http_endpoint():
    # HTTP streaming avoids truncated Kubernetes exec streams on large exports.
    # The temporary tunnel listens only on localhost and is always closed.
    command = ['kubectl', 'port-forward', '-n', 'clickhouse', 'svc/clickhouse',
               '--address=127.0.0.1', '--pod-running-timeout=30s', ':8123']
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as process:
        try:
            for line in process.stdout:
                match = re.search(r'Forwarding from 127\.0\.0\.1:(\d+)', line)
                if match:
                    yield f'http://127.0.0.1:{match.group(1)}/'
                    return
            raise RuntimeError('ClickHouse tunnel did not start')
        finally:
            process.terminate()
            process.wait(timeout=10)


def project(sql, cutoff, output):
    with http_endpoint() as endpoint:
        params = urllib.parse.urlencode(dict(param_before=cutoff, enable_http_compression=1,
                                            http_zlib_compression_level=1))
        request = urllib.request.Request(endpoint + '?' + params, data=sql.encode(),
                                         headers={'Accept-Encoding':'gzip'})
        with urllib.request.urlopen(request, timeout=600) as response:
            if response.headers.get('Content-Encoding') == 'gzip':
                shutil.copyfileobj(response, output)
            else:
                with gzip.GzipFile(fileobj=output, mode='wb', compresslevel=1) as compressed:
                    shutil.copyfileobj(response, compressed)


def insert(export, directory):
    compressed = Path(directory) / 'insert.jsonl.gz'
    with export.open('rb') as source, gzip.open(compressed, 'wb', compresslevel=1) as output:
        shutil.copyfileobj(source, output)
    with http_endpoint() as endpoint, compressed.open('rb') as data:
        params = urllib.parse.urlencode({'query':'INSERT INTO llm.historical_usage FORMAT JSONEachRow'})
        request = urllib.request.Request(endpoint + '?' + params, data=data,
            headers={'Content-Encoding':'gzip', 'Content-Length':str(compressed.stat().st_size)})
        with urllib.request.urlopen(request, timeout=600) as response:
            response.read()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--projection', type=Path,
                        help='retain/reuse the compressed usage-only projection for verification')
    args = parser.parse_args()
    cutoff = subprocess.check_output(client_args(
        "SELECT min(requested_at) FROM llm.usage FORMAT TabSeparated"), text=True).strip()
    if cutoff.startswith('1970-'):
        raise SystemExit('No live usage cutoff is available; refusing an overlapping import')
    sql = Path(__file__).with_name('extract.sql').read_text()
    with tempfile.TemporaryDirectory(prefix='llm-usage-backfill-') as directory:
        db = sqlite3.connect(Path(directory) / 'usage.db')
        extractor = Extractor(db)
        projection = args.projection or Path(directory) / 'projection.jsonl.gz'
        if not projection.exists():
            with projection.open('xb') as output:
                projection.chmod(0o600)
                try:
                    project(sql, cutoff, output)
                except Exception:
                    projection.unlink()
                    raise
        with gzip.open(projection, 'rt') as stream:
            for line in stream:
                extractor.add(json.loads(line))
        db.commit()
        export = args.output or Path(directory) / 'usage.jsonl'
        counts, tokens = Counter(), Counter()
        first, last = None, None
        with export.open('w') as output:
            export.chmod(0o600)
            for line in extractor.rows():
                output.write(line + '\n')
                row = json.loads(line)
                if row['requested_at'] >= cutoff:
                    raise SystemExit('Projection contains usage after the live cutoff; refusing import')
                counts[row['source']] += 1
                tokens[row['source']] += sum(row[k] for k in
                    ('uncached_input_tokens', 'cache_read_tokens', 'cache_creation_tokens', 'output_tokens'))
                first = min(first, row['requested_at']) if first else row['requested_at']
                last = max(last, row['requested_at']) if last else row['requested_at']
        print(json.dumps(dict(mode='apply' if args.apply else 'dry-run', live_cutoff=cutoff,
                              first=first, last=last, records=dict(counts), tokens=dict(tokens),
                              diagnostics=dict(extractor.stats)), sort_keys=True), flush=True)
        if args.apply:
            insert(export, directory)
            print('Historical usage inserted; dashboard reads deduplicated rows with FINAL.')


if __name__ == '__main__':
    main()
