"""Exercise native script routing without starting Xcode or a simulator."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from git_hooks import UNIT_SELECTORS
from pathlib import Path


class NativeModes(unittest.TestCase):
    def run_mode(self, mode=None, test_status=0, failed_results=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tool = root / 'tool'
            tool.write_text('#!' + sys.executable + '\n' + r'''
import json, os, pathlib, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
output = pathlib.Path(os.environ['MIVU_CI_OUTPUT'])
with (output / 'commands.jsonl').open('a') as log:
    log.write(json.dumps([name, *args]) + '\n')
if name == 'python3':
    data = sys.stdin.buffer.read() if args[0] in ('-', '-c') else None
    if args[0] == '-' and b"glob.glob('/Applications/Xcode_27" in data:
        print('/Applications/Xcode_27.6.app/Contents/Developer')
    else:
        sys.exit(subprocess.run([os.environ['REAL_PYTHON'], *args], input=data).returncode)
elif name == 'xcodebuild':
    if '-version' in args: print('Xcode 27.1')
    if 'test' in args:
        pathlib.Path(args[args.index('-resultBundlePath') + 1]).mkdir()
        sys.exit(int(os.environ['TEST_STATUS']))
elif name == 'xcrun':
    if args[:2] == ['swift', '--version']: print('Apple Swift version 6.3.3')
    elif args[:2] == ['simctl', 'list']:
        print(json.dumps({'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [
            {'name': 'iPhone Air', 'isAvailable': True, 'udid': 'synthetic-simulator'}]}}))
    elif 'summary' in args:
        failed = os.environ['FAILED_RESULTS'] == 'true'
        print(json.dumps(dict(totalTestCount=1, passedTests=0 if failed else 1,
                              failedTests=1 if failed else 0, skippedTests=0)))
    elif 'tests' in args:
        print(json.dumps({'testNodes': [{'nodeType': 'Test Case', 'name': 'syntheticPersistence()',
                                        'result': 'Passed'}]}))
elif name == 'ditto':
    pathlib.Path(args[-1]).write_bytes(b'synthetic package')
''')
            tool.chmod(0o755)
            for name in ('python3', 'xcodebuild', 'xcrun', 'ditto'):
                (root / name).symlink_to(tool)
            output = root / 'results'
            output.mkdir()
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                       REAL_PYTHON=sys.executable, MIVU_CI_OUTPUT=str(output),
                       TEST_STATUS=str(test_status), FAILED_RESULTS=str(failed_results).lower())
            result = subprocess.run(['bash', str(Path(__file__).with_name('native.sh'))] + ([mode] if mode else []),
                                    env=env, capture_output=True, text=True)
            commands = [json.loads(line) for line in (output / 'commands.jsonl').read_text().splitlines()] if (output / 'commands.jsonl').exists() else []
            return result, commands, (output / 'Mivu-simulator.app.zip').exists()

    def test_default_selects_quick_units_without_ui_or_packaging(self):
        result, commands, package = self.run_mode()
        self.assertEqual(result.returncode, 0, result.stderr)
        test = next(c for c in commands if c[:2] == ['xcodebuild', 'test'])
        self.assertEqual(sorted(a.removeprefix('-only-testing:') for a in test if a.startswith('-only-testing:')), sorted(UNIT_SELECTORS))
        self.assertEqual(test[test.index('-testPlan') + 1], 'Mivu')
        self.assertFalse(package)

    def test_unit_mode_selects_unit_target_without_packaging(self):
        result, commands, package = self.run_mode('unit')
        self.assertEqual(result.returncode, 0, result.stderr)
        test = next(c for c in commands if c[:2] == ['xcodebuild', 'test'])
        self.assertEqual(sorted(a.removeprefix('-only-testing:') for a in test if a.startswith('-only-testing:')), sorted(UNIT_SELECTORS))
        self.assertFalse(package)

    def test_full_suite_has_no_target_filter_or_release_packaging(self):
        result, commands, package = self.run_mode('test')
        self.assertEqual(result.returncode, 0, result.stderr)
        test = next(c for c in commands if c[:2] == ['xcodebuild', 'test'])
        self.assertFalse(any(a.startswith(('-only-testing:', '-skip-testing:')) for a in test))
        self.assertEqual(test[test.index('-testPlan') + 1], 'Mivu')
        self.assertFalse(package)

    def test_release_packages_only_after_verified_unit_tests(self):
        result, commands, package = self.run_mode('release')
        self.assertEqual(result.returncode, 0, result.stderr)
        test = next(c for c in commands if c[:2] == ['xcodebuild', 'test'])
        self.assertIn('-only-testing:MivuTests', test)
        self.assertTrue(package)
        self.assertTrue(any(c[:2] == ['xcodebuild', 'build'] for c in commands))

    def test_test_exit_or_failed_results_prevent_packaging(self):
        for status, failed in ((65, False), (0, True)):
            with self.subTest(status=status, failed=failed):
                result, commands, package = self.run_mode('release', status, failed)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(package)
                self.assertFalse(any(c[:2] == ['xcodebuild', 'build'] for c in commands))
