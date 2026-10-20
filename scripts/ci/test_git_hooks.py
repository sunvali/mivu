"""Exercise real Git hooks in disposable repositories; never run Apple tools."""
import fcntl
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ZERO = '0' * 40


class GitHooks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='mivu-hooks-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        # Hooks export Git's repository variables; foreign fixture repos must not inherit them.
        self.env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
        self.env.pop('DEVELOPER_DIR', None)
        self.env.pop('XCODE_XCCONFIG_FILE', None)
        self.env.pop('MIVU_TEST_SIMULATOR_ID', None)
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1')
        self.git('init', '-q')
        self.git('config', 'user.name', 'Synthetic contributor')
        self.git('config', 'user.email', 'synthetic@example.invalid')
        for name in ('.githooks/pre-commit', '.githooks/pre-push', 'scripts/ci/git_hooks.py'):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        for name in ('native', 'signed'):
            (self.root / f'scripts/ci/{name}.sh').write_text('#!/bin/bash\ntrue\n')
        (self.root / 'scripts/ci/test_fixture.py').write_text(
            'import os, unittest\nclass Quick(unittest.TestCase):\n'
            ' def test_quick(self): self.assertNotIn("QUICK_FAIL", os.environ)\n')
        (self.root / 'ios').mkdir()
        (self.root / 'ios/source.swift').write_text('// Synthetic source\n')
        (self.root / 'README.md').write_text('Synthetic documentation\n')
        self.commit()
        self.base = self.git('rev-parse', 'HEAD').stdout.strip()
        self.git('update-ref', 'refs/remotes/origin/main', self.base)
        self.tools = self.root / 'tools'
        self.tools.mkdir()
        self.developer = self.tools / 'Xcode.app/Contents/Developer'
        self.developer.mkdir(parents=True)
        self.version('27.0')
        (self.tools / 'xcode-select').write_text('#!/bin/sh\nprintf "%s\\n" "$FAKE_DEVELOPER"\n')
        (self.tools / 'xcode-select').chmod(0o755)
        (self.tools / 'xcodebuildmcp').write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
if os.environ.get('ASSERT_GIT_ENV_NAMES') and args != ['--version']:
    assert not any(name in os.environ for name in json.loads(os.environ['ASSERT_GIT_ENV_NAMES']))
    assert os.environ['GIT_ASKPASS'] == 'synthetic-askpass'
    assert os.environ['GIT_SSH_COMMAND'] == 'synthetic-ssh'
    assert os.environ['HTTPS_PROXY'] == 'http://synthetic.invalid'
if args == ['--version']:
    print(os.environ.get('CLI_VERSION', '2.6.2')); sys.exit()
if args[:2] == ['simulator-management', 'list']:
    print(json.dumps({'didError': False, 'data': {'simulators': [
        {'name': 'iPhone Synthetic', 'simulatorId': 'synthetic-id', 'isAvailable': True,
         'state': 'Booted', 'runtime': os.environ.get('RUNTIME', 'iOS 27.0')}]}})); sys.exit()
with open(os.environ['TOOL_LOG'], 'a') as log: log.write(json.dumps(args) + '\\n')
request = json.loads(args[args.index('--json') + 1])
extra = request['extraArgs']
result = Path(extra[extra.index('-resultBundlePath') + 1]); result.mkdir()
mode = os.environ.get('RESULT', 'success')
if os.environ.get('DIRTY_DURING_RUN'): Path('ios/source.swift').write_text('// changed during test\\n')
if os.environ.get('HEAD_DURING_RUN'):
    import subprocess
    Path('README.md').write_text('Changed during test\\n')
    subprocess.run(['git', 'add', 'README.md'], check=True)
    subprocess.run(['git', 'commit', '-qm', 'docs: change during test'], check=True)
if os.environ.get('ENV_DURING_RUN'):
    import plistlib
    with (Path(os.environ['FAKE_DEVELOPER']).parent / 'version.plist').open('wb') as file:
        plistlib.dump({'CFBundleShortVersionString': '28.0', 'ProductBuildVersion': 'changed'}, file)
if mode == 'malformed': print('not JSON'); sys.exit()
print(json.dumps({'schema': 'xcodebuildmcp.output.test-result', 'didError': mode == 'error',
    'data': {'request': {'onlyTesting': ['MivuTests/Subset'] if mode == 'subset' else [a.removeprefix('-only-testing:') for a in extra if a.startswith('-only-testing:')], 'skipTesting': []},
             'summary': {'status': 'FAILED' if mode == 'failed' else 'SUCCEEDED',
                         'counts': {'passed': 0 if mode == 'zero' else ('2' if mode == 'count-type' else 2),
                                    'failed': 1 if mode == 'failed' else 0, 'skipped': 0}},
             'artifacts': {'xcresultPath': str(result)}}}))
''')
        (self.tools / 'xcodebuildmcp').chmod(0o755)
        self.env.update(PATH=str(self.tools) + os.pathsep + self.env['PATH'],
                        FAKE_DEVELOPER=str(self.developer), TOOL_LOG=str(self.tools / 'calls'))

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.root, env=self.env,
                              capture_output=True, text=True, check=True)

    def commit(self):
        self.git('add', '.githooks', 'scripts', 'ios', 'README.md')
        self.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'test: synthetic fixture')

    def version(self, value):
        with (self.developer.parent / 'version.plist').open('wb') as file:
            plistlib.dump({'CFBundleShortVersionString': value, 'ProductBuildVersion': 'synthetic'}, file)

    def hook(self, name, data='', **variables):
        return subprocess.run([str(self.root / '.githooks' / name)], input=data, cwd=self.root,
                              env=dict(self.env, **variables), capture_output=True, text=True)

    def push(self, remote=None, local=None, **variables):
        local = local or self.git('rev-parse', 'HEAD').stdout.strip()
        return self.hook('pre-push', f'refs/heads/test {local} refs/heads/test {remote or self.base}\n', **variables)

    def calls(self):
        log = self.tools / 'calls'
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def native_commit(self):
        (self.root / 'ios/source.swift').write_text('// Synthetic changed source\n')
        self.commit()

    def test_precommit_rejects_invalid_staged_python_even_if_working_file_is_valid(self):
        file = self.root / 'scripts/ci/new.py'
        file.write_text('def broken(\n')
        self.git('add', str(file))
        file.write_text('print("valid working copy")\n')
        self.assertNotEqual(self.hook('pre-commit').returncode, 0)
        file.write_text('  unexpected_indent = 1\n')
        self.git('add', str(file))
        self.assertNotEqual(self.hook('pre-commit').returncode, 0)

    def test_precommit_uses_valid_staged_content_not_invalid_working_content(self):
        file = self.root / 'scripts/ci/new.py'
        file.write_text('print("staged")\n')
        self.git('add', str(file))
        file.write_text('def broken(\n')
        self.assertEqual(self.hook('pre-commit').returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_precommit_rejects_staged_shell_whitespace_and_conflicts(self):
        for name, content in (('new.sh', 'if then\n'), ('README.md', 'trailing whitespace  \n')):
            with self.subTest(name=name):
                (self.root / name).write_text(content)
                self.git('add', name)
                self.assertNotEqual(self.hook('pre-commit').returncode, 0)
                self.git('reset', '-q', 'HEAD', '--', name)
        blob = self.git('rev-parse', 'HEAD:scripts/ci/git_hooks.py').stdout.strip()
        subprocess.run(['git', 'update-index', '--index-info'], cwd=self.root, env=self.env, check=True,
                       input=f'100644 {blob} 1\tconflict.py\n100644 {blob} 2\tconflict.py\n', text=True)
        self.assertNotEqual(self.hook('pre-commit').returncode, 0)

    def test_docs_new_branch_multi_refs_and_deletion_skip_native(self):
        (self.root / 'README.md').write_text('Updated synthetic documentation\n')
        self.commit()
        for remote in (self.base, ZERO):
            with self.subTest(remote=remote):
                result = self.push(remote=remote)
                self.assertEqual(result.returncode, 0, result.stderr)
        head = self.git('rev-parse', 'HEAD').stdout.strip()
        data = (f'refs/heads/a {head} refs/heads/a {self.base}\n'
                f'refs/heads/b {head} refs/heads/b {ZERO}\n'
                f'(delete) {ZERO} refs/heads/c {self.base}\n')
        self.assertEqual(self.hook('pre-push', data).returncode, 0)
        self.assertEqual(self.hook('pre-push', f'(delete) {ZERO} refs/heads/a {self.base}\n', QUICK_FAIL='1').returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_success_cache_reuses_native_inputs_across_docs_commits(self):
        self.native_commit()
        first = self.push()
        self.assertEqual(first.returncode, 0, first.stderr)
        (self.root / 'README.md').write_text('Another documentation change\n')
        self.commit()
        second = self.push()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn('reused', second.stdout)
        self.assertEqual(len(self.calls()), 1)
        args = json.loads(self.calls()[0][self.calls()[0].index('--json') + 1])
        self.assertEqual(args['scheme'], 'Mivu')
        self.assertEqual(args['configuration'], 'Debug')
        self.assertIn('-only-testing:MivuTests/DiaryPreferencesDraftTests', args['extraArgs'])
        self.assertIn('-disableAutomaticPackageResolution', args['extraArgs'])
        (self.root / 'ios/synthetic-resource.txt').write_text('Changed native resource\n')
        self.commit()
        third = self.push()
        self.assertEqual(third.returncode, 0, third.stderr)
        self.assertEqual(len(self.calls()), 2)

    def test_failures_zero_malformed_or_partial_results_are_never_cached(self):
        self.native_commit()
        for mode in ('failed', 'zero', 'malformed', 'error', 'count-type', 'subset'):
            with self.subTest(mode=mode):
                result = self.push(RESULT=mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(list((self.root / '.git/mivu-checks').glob('*.json')))
        self.assertEqual(len(self.calls()), 6)
        self.assertEqual(self.push().returncode, 0)
        self.assertEqual(len(self.calls()), 7)

    def test_xcode_cli_and_runtime_changes_invalidate_success_cache(self):
        self.native_commit()
        self.assertEqual(self.push().returncode, 0)
        self.version('27.1')
        self.assertEqual(self.push().returncode, 0)
        self.assertEqual(self.push(CLI_VERSION='2.7.0').returncode, 0)
        self.assertEqual(self.push(RUNTIME='iOS 28.0').returncode, 0)
        self.assertEqual(self.push(SDKROOT='synthetic-sdk').returncode, 0)
        self.assertEqual(self.push(TOOLCHAINS='synthetic-toolchain').returncode, 0)
        self.assertEqual(len(self.calls()), 6)

    def test_forwarded_test_environment_invalidates_cache_without_storing_values(self):
        self.native_commit()
        self.assertEqual(self.push().returncode, 0)
        secret = 'synthetic-private-runner-value'
        for prefix in ('TEST_RUNNER_', 'SIMCTL_CHILD_'):
            with self.subTest(prefix=prefix):
                variables = {prefix + 'MIVU_NATIVE_BROWSER_PROBE': secret}
                first = self.push(**variables)
                self.assertEqual(first.returncode, 0, first.stderr)
                second = self.push(**variables)
                self.assertEqual(second.returncode, 0, second.stderr)
                self.assertIn('reused', second.stdout)
                self.assertNotIn(secret, first.stdout + first.stderr + second.stdout + second.stderr)
        self.assertEqual(len(self.calls()), 3)
        for file in (self.root / '.git/mivu-checks').rglob('*.json'):
            self.assertNotIn(secret, file.read_text())

    def test_external_xcode_configuration_override_blocks_native_push(self):
        self.native_commit()
        result = self.push(XCODE_XCCONFIG_FILE='untracked-synthetic.xcconfig')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('XCODE_XCCONFIG_FILE', result.stderr)
        self.assertEqual(self.calls(), [])

    def test_explicit_simulator_is_used_and_unavailable_choice_blocks(self):
        self.env['MIVU_TEST_SIMULATOR_ID'] = 'someone-elses-unavailable-id'
        (self.root / 'ios/source.swift').write_text('// changed source\n')
        self.commit()
        result = self.push()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('reserved simulator', result.stderr)
        self.env['MIVU_TEST_SIMULATOR_ID'] = 'synthetic-id'
        result = self.push()
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(self.calls()[0][self.calls()[0].index('--json') + 1])
        self.assertEqual(args['simulatorId'], 'synthetic-id')
        self.assertEqual(args['extraArgs'][args['extraArgs'].index('-testPlan') + 1], 'Mivu')

    def test_unknown_baseline_requires_native_and_missing_simulator_blocks(self):
        self.assertEqual(self.push(remote='1' * 40).returncode, 0)
        self.assertEqual(len(self.calls()), 1)
        self.git('update-ref', '-d', 'refs/remotes/origin/main')
        result = self.push(remote=ZERO, RUNTIME='iOS 25.0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No available iPhone', result.stderr)
        self.assertEqual(len(self.calls()), 1)

    def test_native_non_head_push_is_blocked(self):
        self.native_commit()
        native = self.git('rev-parse', 'HEAD').stdout.strip()
        (self.root / 'README.md').write_text('New HEAD\n')
        self.commit()
        result = self.push(local=native)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('checked-out HEAD', result.stderr)
        self.assertEqual(self.calls(), [])

    def test_dirty_or_untracked_native_inputs_block_native_push(self):
        self.native_commit()
        for name in ('ios/source.swift', 'ios/untracked.swift'):
            with self.subTest(name=name):
                (self.root / name).write_text('// Unsaved synthetic source\n')
                self.assertNotEqual(self.push().returncode, 0)
                if name.endswith('source.swift'): self.git('restore', name)
                else: (self.root / name).unlink()
        self.assertEqual(self.calls(), [])

    def test_source_head_or_environment_changes_during_native_test_block_cache(self):
        self.native_commit()
        for variable in ('DIRTY_DURING_RUN', 'HEAD_DURING_RUN', 'ENV_DURING_RUN'):
            with self.subTest(variable=variable):
                result = self.push(**{variable: '1'})
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(list((self.root / '.git/mivu-checks').glob('*.json')))
                self.git('restore', 'ios/source.swift')
        self.assertEqual(len(self.calls()), 3)

    def test_quick_checks_fail_before_native_or_wrong_script_revision(self):
        self.native_commit()
        self.assertNotEqual(self.push(QUICK_FAIL='1').returncode, 0)
        script = self.root / 'scripts/ci/test_fixture.py'
        script.write_text(script.read_text() + '\n# changed script\n')
        self.assertNotEqual(self.push().returncode, 0)
        self.commit()
        self.assertNotEqual(self.push(local=self.base).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_missing_xcode_or_cli_blocks_without_native_execution(self):
        self.native_commit()
        (self.developer.parent / 'version.plist').unlink()
        result = self.push()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Select a complete Xcode', result.stderr)
        isolated = self.tools / 'without-cli'
        isolated.mkdir()
        for name in ('git', 'python3', 'bash'):
            (isolated / name).symlink_to(shutil.which(name, path=self.env['PATH']))
        result = self.push(PATH=str(isolated))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Install XcodeBuildMCP', result.stderr)
        self.assertEqual(self.calls(), [])

    def test_parallel_native_check_blocks_without_starting_another(self):
        self.native_commit()
        common = self.root / '.git/mivu-checks'
        common.mkdir()
        with (common / 'native.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            result = self.push()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Another native check', result.stderr)
        self.assertEqual(self.calls(), [])

    def test_real_push_clears_repository_git_environment_for_native_children(self):
        self.native_commit()
        remote = self.tools / 'remote.git'
        self.git('init', '--bare', '-q', str(remote))
        self.git('config', 'core.hooksPath', '.githooks')
        names = self.git('rev-parse', '--local-env-vars').stdout.splitlines()
        env = dict(self.env, GIT_DIR=str(self.root / '.git'),
                   GIT_INDEX_FILE=str(self.root / '.git/index'), GIT_WORK_TREE=str(self.root),
                   ASSERT_GIT_ENV_NAMES=json.dumps(names), GIT_ASKPASS='synthetic-askpass',
                   GIT_SSH_COMMAND='synthetic-ssh', HTTPS_PROXY='http://synthetic.invalid')
        result = subprocess.run(['git', 'push', str(remote), 'HEAD:refs/heads/test'],
                                cwd=self.root, env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls()), 1)

    def test_installer_is_opt_in_and_preserves_custom_hooks(self):
        command = ['python3', 'scripts/ci/git_hooks.py', 'install']
        custom = self.root / '.git/hooks/pre-commit'
        custom.write_text('#!/bin/sh\ntrue\n'); custom.chmod(0o755)
        self.assertNotEqual(subprocess.run(command, cwd=self.root, env=self.env, capture_output=True).returncode, 0)
        self.assertEqual(custom.read_text(), '#!/bin/sh\ntrue\n')
        custom.unlink()
        self.git('config', 'core.hooksPath', 'custom-hooks')
        self.assertNotEqual(subprocess.run(command, cwd=self.root, env=self.env, capture_output=True).returncode, 0)
        self.assertEqual(self.git('config', 'core.hooksPath').stdout.strip(), 'custom-hooks')
        self.git('config', '--unset', 'core.hooksPath')
        self.assertEqual(subprocess.run(command, cwd=self.root, env=self.env, capture_output=True).returncode, 0)
        self.assertEqual(self.git('config', 'core.hooksPath').stdout.strip(), '.githooks')
        result = self.push(GIT_DIR=str(self.root / '.git'), GIT_WORK_TREE=str(self.root))
        self.assertEqual(result.returncode, 0, result.stderr)



if __name__ == '__main__':
    unittest.main()
