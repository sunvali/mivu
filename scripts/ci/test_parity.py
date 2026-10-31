"""Check the parity matrix validator."""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import parity

ROOT = Path(__file__).resolve().parents[2]
SHA = 'a' * 40


def table(*rows):
    head = '## Features\n\n| ID | Feature | Scope | Spec | iOS | Android | Evidence | Notes |\n|---|---|---|---|---|---|---|---|\n'
    return head + ''.join(f'| {r} |\n' for r in rows)


def row(id='today', scope='baseline', ios='partial', android='pending', evidence='-'):
    return f'{id} | Today | {scope} | - | {ios} | {android} | {evidence} | note'


def check(text, root=ROOT):
    return parity.errors(parity.parse(text), root)


class ParityMatrix(unittest.TestCase):
    def test_rejects_duplicate_ids(self):
        errs = check(table(row(), row()))
        self.assertTrue(any('today' in e and 'duplicate' in e for e in errs))

    def test_rejects_unknown_status(self):
        errs = check(table(row(ios='finished')))
        self.assertTrue(any('today' in e and 'finished' in e for e in errs))

    def test_rejects_unknown_scope(self):
        errs = check(table(row(scope='later')))
        self.assertTrue(any('today' in e and 'later' in e for e in errs))

    def test_done_requires_evidence_link(self):
        errs = check(table(row(ios='done')))
        self.assertTrue(any('today' in e for e in errs))

    def test_evidence_record_must_name_tests_and_sha(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'rec.md').write_text('TestA passed\n')
            evidence = 'iOS: rec.md [TestA] · Android: -'
            self.assertTrue(any('today' in e for e in check(table(row(ios='done', evidence=evidence)), root)))
            (root / 'rec.md').write_text(f'TestA passed at {SHA}\n')
            self.assertEqual(check(table(row(ios='done', evidence=evidence)), root), [])
            missing = 'iOS: nope.md [TestA] · Android: -'
            self.assertTrue(any('today' in e for e in check(table(row(ios='done', evidence=missing)), root)))

    def test_shared_paths_need_matrix_change(self):
        self.assertTrue(parity.needs_update(['android/app/x.kt'], ''))
        self.assertFalse(parity.needs_update(['android/app/x.kt', 'docs/parity.md'], ''))
        self.assertFalse(parity.needs_update(['design-system/mivu/x'], 'Parity: unchanged - asset rename'))
        self.assertFalse(parity.needs_update(['README.md'], ''))

    def test_repository_matrix_is_valid(self):
        text = (ROOT / 'docs/parity.md').read_text()
        self.assertEqual(check(text), [])


if __name__ == '__main__':
    unittest.main()
