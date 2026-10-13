"""A non-conventional squash title must fail before it can skip versioning."""
import subprocess
import sys
import unittest
from pathlib import Path


class CommitTitle(unittest.TestCase):
    def test_accepts_features_fixes_breaking_and_release_titles(self):
        script = Path(__file__).with_name('check_commit_title.py')
        for title, valid in (('feat(coach): add historical meal edits', True),
                             ('fix: preserve saved photos', True),
                             ('feat!: change the archive format', True),
                             ('chore(main): release 1.0.1', True),
                             ('Update the app', False), ('fix:', False),
                             ('fix: ', False), ('fix: valid\nsecond line', False)):
            with self.subTest(title=title):
                result = subprocess.run([sys.executable, str(script)], input=title,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, valid, result.stderr)
