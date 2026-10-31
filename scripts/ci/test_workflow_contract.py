"""Keep hosted checks Linux-only and version dispatches on trusted branches."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


def load_workflow(name):
    return load_yaml(Path(__file__).resolve().parents[2] / '.github/workflows' / name)


def load_yaml(workflow):
    if shutil.which('yq'):
        return json.loads(subprocess.check_output(['yq', '-o=json', '.', str(workflow)], text=True))
    return json.loads(subprocess.check_output([
        'ruby', '-r', 'yaml', '-r', 'json', '-e',
        'puts JSON.generate(YAML.load_file(ARGV.fetch(0)))', str(workflow)
    ], text=True))


class ReleaseAutomation(unittest.TestCase):
    def test_dependabot_updates_pinned_actions_with_valid_titles(self):
        config = load_yaml(Path(__file__).resolve().parents[2] / '.github/dependabot.yml')
        updates = config['updates']
        self.assertEqual([u['package-ecosystem'] for u in updates], ['github-actions'])
        title = updates[0]['commit-message']['prefix'] + '(deps): bump actions/checkout from 7.0.1 to 7.0.2'
        result = subprocess.run(['python3', str(Path(__file__).with_name('check_commit_title.py'))],
                                input=title, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, 'Dependabot PR titles must pass the squash-title check')

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
        self.assertEqual(scripts['run'].splitlines(), [
            "python3 -m unittest discover -s scripts/ci -p 'test_*.py'",
            'bash -n scripts/ci/native.sh scripts/ci/signed.sh',
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
            for branch, accepted in (('release-please--branches--main--components--ios', True),
                                     ('release-please--branches--main--components--android', True),
                                     ('release-please--branches--main--components--mivu', False),
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


class PlatformVersions(unittest.TestCase):
    """iOS and Android are versioned, tagged and released independently."""
    root = Path(__file__).resolve().parents[2]

    def test_each_platform_is_its_own_release_package(self):
        config = json.loads((self.root / 'release-please-config.json').read_text())
        manifest = json.loads((self.root / '.release-please-manifest.json').read_text())
        self.assertEqual(set(config['packages']), {'ios', 'android'})
        self.assertEqual(set(manifest), {'ios', 'android'})
        self.assertTrue(config['separate-pull-requests'], 'One version PR per platform')
        self.assertTrue(config['include-component-in-tag'], 'Tags must name their platform')
        self.assertNotIn('plugins', config, 'Plugins such as linked-versions couple the platforms')
        names = {path: package['package-name'] for path, package in config['packages'].items()}
        self.assertEqual(names, {'ios': 'ios', 'android': 'android'})
        for path, package in config['packages'].items():
            for extra in package.get('extra-files', []):
                with self.subTest(package=path, file=extra):
                    file = extra if isinstance(extra, str) else extra['path']
                    self.assertFalse(file.startswith(('/', '..')), 'Version files stay inside their package')
                    self.assertTrue((self.root / path / file).exists())

    def test_ios_counts_commits_from_its_last_release_only(self):
        config = json.loads((self.root / 'release-please-config.json').read_text())
        self.assertRegex(config['last-release-sha'], r'^[0-9a-f]{40}$')
        for package in config['packages'].values():
            self.assertNotIn('last-release-sha', package, 'Release-please reads this key only at the top level')

    def test_test_only_changes_release_nothing(self):
        config = json.loads((self.root / 'release-please-config.json').read_text())
        self.assertEqual(config['packages']['ios']['exclude-paths'], ['ios/MivuTests', 'ios/MivuUITests'])

    def test_each_app_reads_only_its_own_version(self):
        self.assertFalse((self.root / 'version.txt').exists(), 'No shared root version')
        for platform in ('ios', 'android'):
            self.assertRegex((self.root / platform / 'version.txt').read_text(), r'^\d+\.\d+\.\d+\n?$')
        xcconfig = (self.root / 'ios/Config/Shared.xcconfig').read_text()
        self.assertRegex(xcconfig, r'MARKETING_VERSION = [\d.]+ // x-release-please-version')


if __name__ == '__main__':
    unittest.main()
