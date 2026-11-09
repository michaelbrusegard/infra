import json
import sqlite3
import unittest

from backfill import Extractor


class UsageExtractionTest(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.extractor = Extractor(self.db)
        self.addCleanup(self.db.close)

    def add(self, source='claude-code', usage=None, **fields):
        row = dict(source=source, host='forte', session='session-1', path='session.jsonl',
                   id='1', ts='2026-10-01 12:00:00.000', kind='assistant',
                   model='claude-opus-5-5', response_id='msg_1', usage=usage or {})
        row.update(fields)
        self.extractor.add(row)

    def rows(self):
        return [json.loads(row) for row in self.extractor.rows()]

    def test_claude_stream_chunks_are_one_complete_response(self):
        for output in (10, 100, 20):
            self.add(usage=dict(input_tokens=2, cache_read_input_tokens=200,
                                cache_creation_input_tokens=100, output_tokens=output,
                                output_tokens_details=None,
                                cache_creation={'ephemeral_5m_input_tokens':60,
                                                'ephemeral_1h_input_tokens':40}))
        [row] = self.rows()
        self.assertEqual(row['output_tokens'], 100)
        self.assertEqual(row['uncached_input_tokens'], 2)
        self.assertEqual(row['cache_read_tokens'], 200)
        self.assertEqual(row['cache_write_5m_tokens'], 60)
        self.assertEqual(row['cache_write_1h_tokens'], 40)

    def test_response_ids_deduplicate_across_hosts_and_clients(self):
        self.add(usage={'input_tokens':1, 'output_tokens':100})
        self.add(host='lungo', path='copied/session.jsonl', usage={'input_tokens':1, 'output_tokens':100})
        self.add(source='pi', usage={'input':1, 'output':100}, entry_id='pi-entry')
        self.assertEqual(len(self.rows()), 1)
        self.assertEqual(self.rows()[0]['source'], 'claude-code')

    def test_codex_uses_last_usage_not_running_total(self):
        context = dict(source='codex', kind='turn_context', model='gpt-5.5', response_id='')
        self.add(**context, usage={})
        usage = dict(input_tokens=100, cached_input_tokens=50, output_tokens=20,
                     reasoning_output_tokens=10, total_tokens=120)
        for _ in range(3):
            self.add(source='codex', kind='event_msg', model='', response_id='',
                     usage=usage, cumulative={'total_tokens':1000})
        # New Codex formats also save a per-response record for the same point.
        self.add(source='codex', kind='token_usage_record', model='', response_id='resp_1',
                 usage=usage, cumulative={'total_tokens':1000})
        [row] = self.rows()
        self.assertEqual(row['model'], 'gpt-5.5')
        self.assertEqual(row['uncached_input_tokens'], 50)
        self.assertEqual(row['cache_read_tokens'], 50)
        self.assertEqual(row['output_tokens'], 20)
        self.assertEqual(row['reasoning_tokens'], 10)

    def test_codex_response_identity_matches_pi(self):
        self.add(source='codex', kind='token_usage_record', model='gpt-6.1-sol',
                 response_id='resp_1', usage={'input_tokens':100,'output_tokens':20},
                 cumulative={'total_tokens':120})
        self.add(source='pi', model='gpt-6.1-sol', response_id='resp_1',
                 usage={'input':100,'output':20})
        self.assertEqual(len(self.rows()), 1)

    def test_model_context_does_not_leak_between_files(self):
        self.add(source='codex', kind='turn_context', model='gpt-5.5', usage={})
        self.add(source='codex', path='other.jsonl', kind='event_msg', model='', response_id='',
                 usage={'input_tokens':100,'output_tokens':20}, cumulative={'total_tokens':120})
        self.assertEqual(self.rows()[0]['model'], '(unknown)')

    def test_pi_buckets_are_independent_and_copied_entries_deduplicate(self):
        for session in ('original', 'fork'):
            self.add(source='pi', session=session, model='gpt-6-astra', response_id='',
                     entry_id='abcd1234', usage={'input':10,'output':20,'reasoning':5,
                                                'cacheRead':100,'cacheWrite':50})
        [row] = self.rows()
        self.assertEqual(row['provider'], 'codex')
        self.assertEqual(row['uncached_input_tokens'], 10)
        self.assertEqual(row['output_tokens'], 20)
        self.assertEqual(row['cache_read_tokens'], 100)
        self.assertEqual(row['cache_creation_tokens'], 50)

    def test_opencode_reasoning_is_added_only_when_separate(self):
        for total, expected in ((660,60), (650,50), (None,60)):
            with self.subTest(total=total):
                self.db.execute('DELETE FROM events')
                usage = dict(input=100, output=50, reasoning=10, cache={'read':500,'write':0})
                if total is not None:
                    usage['total'] = total
                self.add(source='opencode', model='gpt-5.5', response_id='',
                         entry_id='opencode-msg-1', usage=usage)
                self.assertEqual(self.rows()[0]['output_tokens'], expected)

    def test_zero_usage_and_missing_timestamps_do_not_create_calls(self):
        self.add(usage={'input_tokens':0,'output_tokens':0})
        self.add(usage={'input_tokens':100}, ts='1970-01-01 00:00:00.000')
        self.assertEqual(self.rows(), [])


if __name__ == '__main__':
    unittest.main()
