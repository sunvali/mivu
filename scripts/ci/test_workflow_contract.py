"""Keep hosted checks Linux-only and version dispatches on trusted branches."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


def load_workflow(name):
    workflow = Path(__file__).resolve().parents[2] / '.github/workflows' / name
    if shutil.which('yq'):
        return json.loads(subprocess.check_output(['yq', '-o=json', '.', str(workflow)], text=True))
    return json.loads(subprocess.check_output([
        'ruby', '-r', 'yaml', '-r', 'json', '-e',
        'puts JSON.generate(YAML.load_file(ARGV.fetch(0)))', str(workflow)
    ], text=True))


class ReleaseAutomation(unittest.TestCase):
    def test_all_hosted_jobs_are_slim_only_with_two_minute_limits(self):
        directory = Path(__file__).resolve().parents[2] / '.github/workflows'
        workflows = sorted(path for path in directory.iterdir() if path.suffix in ('.yml', '.yaml'))
        self.assertTrue(workflows, 'Hosted checks must exist')
        for path in workflows:
            for name, job in load_workflow(path.name)['jobs'].items():
                with self.subTest(workflow=path.name, job=name):
                    self.assertEqual(job['runs-on'], 'ubuntu-slim')
                    self.assertIsInstance(job['timeout-minutes'], int)
                    self.assertLessEqual(job['timeout-minutes'], 2)
                    for step in job['steps']:
                        self.assertNotRegex(step.get('run', ''),
                                            r'(?m)^\s*(?:(?:bash|sh)\s+)?(?:scripts/ci/(?:native|signed)\.sh|xcodebuild|xcrun)(?:\s|$)',
                                            'Native execution belongs on the local Mac')

    def test_ci_runs_only_script_checks(self):
        ci = load_workflow('ci.yml')
        triggers = ci.get('on', ci.get('true'))
        self.assertEqual(set(triggers), {'pull_request', 'workflow_dispatch'})
        self.assertEqual(ci['permissions'], {'contents': 'read'})
        self.assertEqual(set(ci['jobs']), {'checks'})
        checks = ci['jobs']['checks']
        self.assertNotIn('outputs', checks)
        self.assertEqual(len(checks['steps']), 2)
        checkout, scripts = checks['steps']
        self.assertFalse(checkout['with']['persist-credentials'])
        self.assertEqual(checkout['with']['fetch-depth'], 2)
        self.assertEqual(scripts['run'].splitlines(), [
            "python3 -m unittest discover -s scripts/ci -p 'test_*.py'",
            'bash -n scripts/ci/native.sh scripts/ci/signed.sh',
            'python3 scripts/ci/parity.py',
        ])

    def test_title_edits_run_only_the_lightweight_title_check(self):
        path = Path(__file__).resolve().parents[2] / '.github/workflows/commit-title.yml'
        self.assertTrue(path.exists(), 'Title corrections need their own lightweight trigger')
        workflow = load_workflow('commit-title.yml')
        triggers = workflow.get('on', workflow.get('true'))
        self.assertIn('edited', triggers['pull_request']['types'])
        self.assertEqual(workflow['permissions'], {'contents': 'read'})
        self.assertEqual(set(workflow['jobs']), {'title'})
        self.assertEqual(workflow['jobs']['title']['runs-on'], 'ubuntu-slim')

    def test_release_bot_runs_only_on_main_and_explicitly_dispatches_checks(self):
        path = Path(__file__).resolve().parents[2] / '.github/workflows/release-please.yml'
        self.assertTrue(path.exists(), 'The trusted release workflow is missing')
        workflow = load_workflow('release-please.yml')
        triggers = workflow.get('on', workflow.get('true'))  # Ruby YAML 1.1 treats "on" as true.
        self.assertEqual(triggers['push']['branches'], ['main'])
        self.assertNotIn('pull_request', triggers)
        self.assertEqual(workflow['permissions'], {'contents': 'read'})
        job = workflow['jobs']['release']
        self.assertEqual(job['if'], "github.ref == 'refs/heads/main'")
        self.assertEqual(job['permissions']['actions'], 'write')
        steps = job['steps']
        bot = next(step for step in steps if step.get('id') == 'release')
        self.assertRegex(bot['uses'], r'^googleapis/release-please-action@[0-9a-f]{40}$')
        self.assertEqual(bot['with']['target-branch'], 'main')
        self.assertEqual(len(steps), 2, 'Version automation must not dispatch packaging')

    def test_version_pr_dispatch_accepts_the_configured_component_branch_only(self):
        step = next(s for s in load_workflow('release-please.yml')['jobs']['release']['steps']
                    if s.get('name') == 'Check the version pull request')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tool = root / 'gh'
            tool.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$COMMAND_LOG"\n')
            tool.chmod(0o755)
            for branch, accepted in (('release-please--branches--main--components--mivu', True),
                                     ('release-please--branches--main', False),
                                     ('feature/untrusted', False)):
                with self.subTest(branch=branch):
                    log = root / 'commands'
                    log.unlink(missing_ok=True)
                    env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                               COMMAND_LOG=str(log), GH_REPO='synthetic/mivu',
                               RELEASE_PR=json.dumps({'headBranchName': branch,
                                                      'title': 'chore(main): release 1.1.0'}))
                    result = subprocess.run(['bash', '-e', '-c', step['run']],
                                            env=env, capture_output=True, text=True)
                    if accepted:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        commands = log.read_text().splitlines()
                        self.assertEqual(len(commands), 2)
                        self.assertIn('commit-title.yml', commands[0])
                        self.assertIn('ci.yml', commands[1])
                        self.assertTrue(all('--ref ' + branch in command for command in commands))
                    else:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertFalse(log.exists(), 'Unexpected branches must not dispatch workflows')


if __name__ == '__main__':
    unittest.main()
