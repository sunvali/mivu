"""Documentation edits must not start a simulator; unknown files must."""
import subprocess
import sys
import unittest
from pathlib import Path


class NativeSelection(unittest.TestCase):
    def test_selects_native_for_source_or_unknown_paths(self):
        script = Path(__file__).with_name('needs_native.py')
        for paths, expected in ((['docs/development/ci-cd.md', 'README.md'], 'false'),
                                (['docs/guide.md', 'ios/Mivu/Coach/CoachEngine.swift'], 'true'),
                                (['.github/workflows/ci.yml'], 'true'),
                                (['release-please-config.json'], 'true'),
                                (['a new unknown file'], 'true'),
                                ([], 'true')):
            with self.subTest(paths=paths):
                result = subprocess.run([sys.executable, str(script)],
                                        input='\0'.join(paths).encode(), capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.decode().strip(), expected)
