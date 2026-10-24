import unittest
from pathlib import Path

import play_ledger

HEADER = '# code name sha date track\n'
ROOT = Path(__file__).resolve().parents[2]


class PlayLedgerTests(unittest.TestCase):
    def test_codes_must_increase(self):
        text = HEADER + '3 1.0.0 abc1234 2026-10-23 internal\n2 1.0.1 abc1235 2026-10-24 internal\n'
        self.assertTrue(play_ledger.errors(text))

    def test_duplicate_code_rejected(self):
        text = '1 1.0.0 abc1234 2026-10-23 internal\n1 1.0.1 abc1235 2026-10-24 internal\n'
        self.assertTrue(play_ledger.errors(text))

    def test_empty_ledger_ok(self):
        self.assertEqual(play_ledger.errors(HEADER), [])

    def test_wrong_field_count_rejected(self):
        self.assertTrue(play_ledger.errors('1 1.0.0 abc1234\n'))

    def test_repository_ledger_valid(self):
        self.assertEqual(play_ledger.errors((ROOT / 'android/play-uploads.txt').read_text()), [])


if __name__ == '__main__':
    unittest.main()
