#!/usr/bin/env python3
"""Small opt-in Git checks; successful native evidence stays in Git's common directory."""
import ast
import datetime
import fcntl
import hashlib
import json
import os
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

NATIVE = ('ios', 'scripts/ci/git_hooks.py', '.githooks/pre-push')
QUICK = ('scripts/ci', '.githooks', '.github/workflows')
QUICK_UNIT_SUITES = ['CoachReceiptPresentationTests', 'DiaryPreferencesDraftTests', 'ManualNutritionDraftTests', 'ProgressEditorStateTests', 'CoachCaptureOptionsTests']
UNIT_SELECTORS = ['MivuTests/' + suite for suite in QUICK_UNIT_SUITES]
EXTRA = ['-testPlan', 'Mivu', *['-only-testing:' + suite for suite in UNIT_SELECTORS],
         '-parallel-testing-enabled', 'NO',
         '-onlyUsePackageVersionsFromResolvedFile', '-disableAutomaticPackageResolution',
         '-skipPackageUpdates', 'SWIFT_VERSION=6.0']


def run(args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs)


def git(*args):
    return run(['git', *args], stderr=subprocess.PIPE)


def clean(paths):
    if git('status', '--porcelain', '--untracked-files=all', '--', *paths):
        raise ValueError('Commit or remove dirty/untracked check inputs before pushing.')


def tree(commit, paths):
    return git('ls-tree', '-r', '-z', commit, '--', *paths)


def pre_commit():
    if git('ls-files', '--unmerged'):
        raise ValueError('Resolve staged conflicts before committing.')
    subprocess.run(['git', 'diff', '--cached', '--check'], check=True)
    paths = git('diff', '--cached', '--name-only', '-z', '--diff-filter=ACMR').split('\0')
    for name in filter(None, paths):
        if name.endswith('.py'):
            ast.parse(git('show', ':' + name), filename=name)
        elif name.endswith('.sh') or name.startswith('.githooks/'):
            result = subprocess.run(['bash', '-n'], input=git('show', ':' + name),
                                    text=True, capture_output=True)
            if result.returncode:
                raise ValueError('Invalid staged shell syntax: ' + name)


def native_environment(developer):
    env = dict(os.environ, DEVELOPER_DIR=str(developer))
    for name in git('rev-parse', '--local-env-vars').splitlines():
        env.pop(name, None)
    return env


def environment():
    if os.environ.get('XCODE_XCCONFIG_FILE'):
        raise ValueError('Unset XCODE_XCCONFIG_FILE; external build configuration is not tracked.')
    forwarded = {name: value for name, value in os.environ.items()
                 if name.startswith(('TEST_RUNNER_', 'SIMCTL_CHILD_'))}
    cli = shutil.which('xcodebuildmcp')
    if not cli:
        raise ValueError('Install XcodeBuildMCP before pushing native changes.')
    developer = Path(os.environ.get('DEVELOPER_DIR') or git_tool_path()).resolve()
    try:
        with (developer.parent / 'version.plist').open('rb') as file:
            version = plistlib.load(file)
        xcode = [version['CFBundleShortVersionString'], version['ProductBuildVersion']]
    except (OSError, KeyError, plistlib.InvalidFileException) as error:
        raise ValueError('Select a complete Xcode installation before pushing native changes.') from error
    env = native_environment(developer)
    listed = json.loads(run([cli, 'simulator-management', 'list', '--enabled', '--output', 'json'], env=env))
    if listed.get('didError') is not False:
        raise ValueError('Could not list available iPhone simulators.')
    candidates = []
    reserved = os.environ.get('MIVU_TEST_SIMULATOR_ID')
    for device in listed['data']['simulators']:
        match = re.fullmatch(r'iOS\s+(\d+)\.(\d+)(?:\.(\d+))?', device['runtime'])
        if reserved and device['simulatorId'] != reserved:
            continue
        if match and int(match[1]) >= 26 and device['isAvailable'] and (reserved or device['name'].startswith('iPhone')):
            candidates.append((device['state'] == 'Booted', tuple(int(n or 0) for n in match.groups()),
                               device['name'], device['simulatorId'], device['runtime']))
    if not candidates:
        raise ValueError('The reserved simulator is unavailable or not iOS 26 or newer.' if reserved
                         else 'No available iPhone simulator with iOS 26 or newer.')
    selected = max(candidates)
    return dict(developer=str(developer), xcode=xcode, architecture=platform.machine(),
                hostOS=platform.mac_ver()[0] or platform.platform(),
                toolchains=os.environ.get('TOOLCHAINS'), sdkRoot=os.environ.get('SDKROOT'),
                testEnvironmentDigest=hashlib.sha256(json.dumps(forwarded, sort_keys=True).encode()).hexdigest(),
                cli=str(Path(cli).resolve()), cliVersion=run([cli, '--version'], env=env).strip(),
                simulator=selected[3], runtime=selected[4])


def git_tool_path():
    if not shutil.which('xcode-select'):
        raise ValueError('Xcode is required for native pushes on the local Mac.')
    return run(['xcode-select', '-p'], stderr=subprocess.PIPE).strip()


def successful(result):
    data = result['data']
    counts = data['summary']['counts']
    if (result.get('didError') is not False or data['summary']['status'] != 'SUCCEEDED'
            or any(type(counts.get(k)) is not int or counts[k] < 0 for k in ('passed', 'failed', 'skipped'))
            or counts['passed'] <= 0 or counts['failed'] != 0
            or counts.get('expectedFailures', 0) != 0
            or sorted(data['request']['onlyTesting']) != sorted(UNIT_SELECTORS) or data['request'].get('skipTesting')):
        raise ValueError('Native unit tests failed or returned incomplete/zero-test evidence.')
    return counts


def native_check(head):
    common = Path(git('rev-parse', '--git-common-dir').strip()).resolve() / 'mivu-checks'
    common.mkdir(parents=True, exist_ok=True)
    tools = environment()
    with (common / ('native-' + tools['simulator'] + '.lock')).open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError('Another native check is running; push again after it finishes.') from error
        clean(NATIVE)
        if git('rev-parse', 'HEAD').strip() != head:
            raise ValueError('HEAD changed before native verification; push again.')
        inputs = tree(head, NATIVE)
        key = hashlib.sha256(json.dumps([inputs, tools, EXTRA], sort_keys=True).encode()).hexdigest()
        cache = common / (key + '.json')
        prior = None
        try:
            prior = json.loads(cache.read_text())
            counts = successful(prior['result'])
            if (prior['key'] != key or prior['exitStatus'] != 0
                    or not Path(prior['result']['data']['artifacts']['xcresultPath']).is_dir()):
                prior = None
        except (OSError, ValueError, KeyError, TypeError):
            prior = None
        if prior is not None:
            unchanged(head, inputs, tools)
            print(f"Native units: reused {counts['passed']} passed, 0 failed ({cache}).")
            return
        output = Path(tempfile.mkdtemp(prefix='native-', dir=common))
        bundle = output / 'Mivu.xcresult'
        args = dict(projectPath=str(Path('ios/Mivu.xcodeproj').resolve()), scheme='Mivu',
                    configuration='Debug', simulatorId=tools['simulator'],
                    derivedDataPath=str(common / ('DerivedData-' + tools['simulator'])), preferXcodebuild=True,
                    testRunnerEnv={}, progress=False,
                    extraArgs=EXTRA + ['-clonedSourcePackagesDirPath', str(common / ('SourcePackages-' + tools['simulator'])),
                                       '-resultBundlePath', str(bundle)])
        command = [tools['cli'], 'simulator', 'test', '--json', json.dumps(args), '--output', 'json']
        print('Running local MivuTests units; evidence: ' + str(output), flush=True)
        with (output / 'result.json').open('w') as stdout, (output / 'stderr.txt').open('w') as stderr:
            status = subprocess.run(command, stdout=stdout, stderr=stderr,
                                    env=native_environment(tools['developer'])).returncode
        if status:
            raise ValueError('Native tool failed; inspect evidence at ' + str(output))
        result = json.loads((output / 'result.json').read_text())
        counts = successful(result)
        if result['data']['artifacts']['xcresultPath'] != str(bundle) or not bundle.is_dir():
            raise ValueError('Native result bundle is missing or belongs to another run.')
        unchanged(head, inputs, tools)
        record = dict(key=key, sourceCommit=head, utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                      environment=tools, command=command, exitStatus=status, result=result)
        cache.write_text(json.dumps(record, indent=2) + '\n')
        print(f"Native units: {counts['passed']} passed, 0 failed, {counts['skipped']} skipped.")


def unchanged(head, inputs, tools):
    clean(NATIVE)
    if git('rev-parse', 'HEAD').strip() != head or tree('HEAD', NATIVE) != inputs or environment() != tools:
        raise ValueError('Source or native environment changed during verification; push again.')


def pre_push():
    refs = []
    for line in sys.stdin:
        fields = line.split()
        if len(fields) != 4 or not all(re.fullmatch(r'(?:[0-9a-f]{40}|[0-9a-f]{64})', fields[i]) for i in (1, 3)):
            raise ValueError('Invalid Git pre-push input; cannot determine pushed source.')
        if set(fields[1]) != {'0'}:
            refs.append((git('rev-parse', fields[1] + '^{commit}').strip(), fields[3]))
    if not refs:
        return
    head = git('rev-parse', 'HEAD').strip()
    clean(QUICK)
    if any(tree(source, QUICK) != tree(head, QUICK) for source, _ in refs):
        raise ValueError('Check scripts differ from pushed source; check out that commit before pushing.')
    native = False
    for source, remote in refs:
        try:
            baseline = (git('merge-base', source, 'origin/main').strip() if set(remote) == {'0'}
                        else git('rev-parse', remote + '^{commit}').strip())
            needs_native = tree(source, NATIVE) != tree(baseline, NATIVE)
        except subprocess.CalledProcessError:
            needs_native = True
        if needs_native and source != head:
            raise ValueError('Native changes must be pushed from their checked-out HEAD.')
        native |= needs_native
    subprocess.run(['python3', '-m', 'unittest', 'discover', '-s', 'scripts/ci', '-p', 'test_*.py'],
                   env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'), check=True)
    subprocess.run(['bash', '-n', 'scripts/ci/native.sh', 'scripts/ci/signed.sh'], check=True)
    if native:
        native_check(head)
    else:
        print('Quick checks passed; native inputs unchanged.')
    clean(QUICK)
    if git('rev-parse', 'HEAD').strip() != head:
        raise ValueError('HEAD changed during push checks; push again.')


def install():
    configured = subprocess.run(['git', 'config', '--get', 'core.hooksPath'], text=True, capture_output=True)
    if configured.returncode == 0:
        if configured.stdout.strip() == '.githooks':
            print('Local hooks already enabled.')
            return
        raise ValueError('Existing core.hooksPath preserved; integrate custom hooks manually.')
    hooks = Path(git('rev-parse', '--git-path', 'hooks').strip())
    if hooks.exists() and any(path.is_file() and not path.name.endswith('.sample') and os.access(path, os.X_OK)
                              for path in hooks.iterdir()):
        raise ValueError('Existing executable Git hooks preserved; integrate them manually.')
    if not all(os.access(Path('.githooks') / name, os.X_OK) for name in ('pre-commit', 'pre-push')):
        raise ValueError('Versioned executable hook files are missing in this checkout.')
    subprocess.run(['git', 'config', '--local', 'core.hooksPath', '.githooks'], check=True)
    print('Local hooks enabled for this repository.')


if __name__ == '__main__':
    try:
        os.chdir(git('rev-parse', '--show-toplevel').strip())
        {'pre-commit': pre_commit, 'pre-push': pre_push, 'install': install}[sys.argv[1]]()
    except (ValueError, KeyError, TypeError, OSError, SyntaxError, subprocess.CalledProcessError) as error:
        print('Local check blocked: ' + str(error), file=sys.stderr)
        sys.exit(1)
