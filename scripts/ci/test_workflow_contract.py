"""Protect the signed lane's trigger/source boundary without paid environments."""
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


class SignedWorkflowContract(unittest.TestCase):
    def test_signed_lane_requires_manual_main_and_tested_source(self):
        release = load_workflow('release.yml')
        signed = release['jobs']['signed']
        self.assertNotIn('environment', signed, 'Private GitHub Free must not require a paid environment.')
        self.assertEqual(signed['needs'], 'artifacts')
        self.assertEqual(signed['if'], "github.event_name == 'workflow_dispatch' && (inputs.signed_delivery || inputs.upload_testflight) && github.ref == 'refs/heads/main'")
        self.assertEqual(release['permissions'], {'contents': 'read'})
        self.assertNotIn('permissions', signed)
        checkout = signed['steps'][0]
        self.assertEqual(checkout['with']['ref'], '${{ needs.artifacts.outputs.sha }}')
        self.assertFalse(checkout['with']['persist-credentials'])


class ReleaseAutomation(unittest.TestCase):
    def test_hosted_jobs_use_cheapest_compatible_runners_and_short_limits(self):
        for name in ('ci.yml', 'commit-title.yml', 'release-please.yml', 'release.yml'):
            for job in load_workflow(name)['jobs'].values():
                with self.subTest(workflow=name, job=job):
                    self.assertIn(job['runs-on'], ('ubuntu-slim', 'macos-26'))
                    self.assertIsInstance(job['timeout-minutes'], int)
                    self.assertLessEqual(job['timeout-minutes'], 8)
        ci = load_workflow('ci.yml')
        triggers = ci.get('on', ci.get('true'))
        self.assertNotIn('push', triggers, 'Merging an already-tested PR must not repeat paid native checks')
        native = next(s for s in ci['jobs']['native']['steps'] if s.get('name') == 'Build and test native iPhone app')
        self.assertEqual(native['run'], 'bash scripts/ci/native.sh unit')

    def test_title_edits_run_only_the_lightweight_title_check(self):
        path = Path(__file__).resolve().parents[2] / '.github/workflows/commit-title.yml'
        self.assertTrue(path.exists(), 'Title corrections need their own lightweight trigger')
        workflow = load_workflow('commit-title.yml')
        triggers = workflow.get('on', workflow.get('true'))
        self.assertIn('edited', triggers['pull_request']['types'])
        self.assertEqual(workflow['permissions'], {'contents': 'read'})
        self.assertEqual(set(workflow['jobs']), {'title'})
        self.assertEqual(workflow['jobs']['title']['runs-on'], 'ubuntu-slim')

    def test_unverified_native_allowance_cannot_pass_as_a_skipped_source_check(self):
        step = next(s for s in load_workflow('ci.yml')['jobs']['checks']['steps'] if s.get('id') == 'changes')
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'output'
            env = dict(os.environ, EVENT_NAME='workflow_dispatch', BASE_SHA='',
                       NATIVE_USAGE_APPROVED='false', GITHUB_OUTPUT=str(output))
            result = subprocess.run(['bash', '-e', '-c', step['run']],
                                    env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Native verification blocked', result.stderr)
            self.assertEqual(output.read_text().strip(), 'needs_native=true')

    def test_release_bot_runs_only_on_main_and_explicitly_dispatches_builds(self):
        path = Path(__file__).resolve().parents[2] / '.github/workflows/release-please.yml'
        self.assertTrue(path.exists(), 'The trusted release workflow is missing')
        workflow = load_workflow('release-please.yml')
        triggers = workflow.get('on', workflow.get('true'))  # Ruby YAML 1.1 treats "on" as true.
        self.assertEqual(triggers['push']['branches'], ['main'])
        self.assertNotIn('pull_request', triggers)
        self.assertEqual(workflow['permissions'], {'contents': 'read'})
        job = workflow['jobs']['release']
        self.assertEqual(job['permissions']['actions'], 'write')
        steps = job['steps']
        bot = next(step for step in steps if step.get('id') == 'release')
        self.assertRegex(bot['uses'], r'^googleapis/release-please-action@[0-9a-f]{40}$')
        self.assertEqual(bot['with']['target-branch'], 'main')
        dispatch = next(step for step in steps if step.get('name') == 'Package the new release')
        self.assertEqual(dispatch['if'], "vars.MIVU_AUTO_PACKAGE_RELEASES == 'true' && steps.release.outputs.release_created == 'true'")
        self.assertEqual(dispatch['env']['RELEASE_TAG'], '${{ steps.release.outputs.tag_name }}')

    def test_existing_release_receives_artifacts_without_recreation_or_overwrite(self):
        step = next(s for s in load_workflow('release.yml')['jobs']['publish']['steps'] if 'run' in s)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tool = root / 'gh'
            tool.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$COMMAND_LOG"
if [ "$2" = view ]; then exit "$RELEASE_EXISTS_STATUS"; fi
''')
            tool.chmod(0o755)
            (root / 'products').mkdir()
            for name in ('Mivu-simulator.app.zip', 'test-provenance.json', 'test-report.txt'):
                (root / 'products' / name).write_text('synthetic')
            for status, expected in (('0', 'release upload'), ('1', 'release create')):
                log = root / ('commands-' + status)
                env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                           COMMAND_LOG=str(log), RELEASE_EXISTS_STATUS=status,
                           RELEASE_TAG='v1.0.1', SOURCE_SHA='1' * 40)
                result = subprocess.run(['bash', '-e', '-c', step['run']], cwd=root,
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                commands = log.read_text()
                self.assertIn(expected + ' v1.0.1', commands)
                self.assertNotIn('--clobber', commands)
                if status == '0': self.assertNotIn('release create', commands)

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
