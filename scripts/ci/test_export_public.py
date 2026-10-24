import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name('export_public.py')
# Git hooks export GIT_DIR and friends; the fixture repository must not inherit them.
ENV = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}


def git(cwd, *args):
    subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True, env=ENV)


class ExportPublic(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.repo, self.out = root / 'repo', root / 'out'
        for path, text in {'ios/App.swift': 'let x = 1\n', 'docs/plan.md': 'private plan\n',
                           'public/LICENSE': 'AGPL\n', 'public/README.md': '# Mivu\n'}.items():
            (self.repo / path).parent.mkdir(parents=True, exist_ok=True)
            (self.repo / path).write_text(text)
        git(self.repo, 'init', '-q')
        git(self.repo, '-c', 'user.name=t', '-c', 'user.email=t@t', 'add', '.')
        git(self.repo, '-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'base')
        git(self.repo, 'tag', 'v1.0.0')

    def tearDown(self):
        self.tmp.cleanup()

    def export(self):
        return subprocess.run(['python3', str(SCRIPT), 'v1.0.0', str(self.out)], cwd=self.repo,
                              capture_output=True, text=True, env=ENV)

    def test_exports_only_the_app_and_public_files(self):
        result = self.export()
        self.assertEqual(result.returncode, 0, result.stderr)
        files = sorted(str(p.relative_to(self.out)) for p in self.out.rglob('*') if p.is_file())
        self.assertEqual(files, ['LICENSE', 'README.md', 'ios/App.swift'])

    def test_replaces_a_previous_export_but_keeps_its_git_history(self):
        (self.out / '.git').mkdir(parents=True)
        (self.out / '.git' / 'HEAD').write_text('ref\n')
        (self.out / 'stale.txt').write_text('old\n')
        self.assertEqual(self.export().returncode, 0)
        self.assertTrue((self.out / '.git' / 'HEAD').exists())
        self.assertFalse((self.out / 'stale.txt').exists())

    def test_refuses_an_export_that_looks_like_it_holds_a_secret(self):
        (self.repo / 'ios/App.swift').write_text('let key = "sk-proj-abcdefghijklmnopqrstuv"\n')
        git(self.repo, '-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qam', 'leak')
        git(self.repo, 'tag', '-f', 'v1.0.0')
        result = self.export()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ios/App.swift', result.stderr)
        self.assertFalse((self.out / 'ios').exists())


if __name__ == '__main__':
    unittest.main()
