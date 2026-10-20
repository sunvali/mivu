#!/usr/bin/env python3
"""Run the short E2E suite on an explicitly reserved simulator, capped at 120s."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
SELECTOR = 'MivuUITests/SmokeUITests'


def command(simulator, derived, bundle):
    args = dict(projectPath=str(ROOT / 'ios/Mivu.xcodeproj'), scheme='Mivu',
                configuration='Debug', simulatorId=simulator, derivedDataPath=str(derived),
                preferXcodebuild=True, progress=False,
                extraArgs=['-testPlan', 'MivuQuick', '-only-testing:' + SELECTOR,
                           '-parallel-testing-enabled', 'NO',
                           '-onlyUsePackageVersionsFromResolvedFile', '-disableAutomaticPackageResolution',
                           '-skipPackageUpdates', '-resultBundlePath', str(bundle)])
    return ['xcodebuildmcp', 'simulator', 'test', '--json', json.dumps(args), '--output', 'json']


def execute(args, output):
    with (output / 'result.json').open('w') as stdout, (output / 'stderr.txt').open('w') as stderr:
        process = subprocess.Popen(args, stdout=stdout, stderr=stderr, cwd=ROOT, start_new_session=True)
        try:
            return process.wait(timeout=120)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            print('FAIL: smoke exceeded 120 seconds; no success recorded.', file=sys.stderr)
            return 124


def passed(result):
    try:
        data = result['data']
        counts = data['summary']['counts']
        return (result.get('didError') is False and data['summary']['status'] == 'SUCCEEDED'
                and all(type(counts.get(k)) is int for k in ('passed', 'failed', 'skipped'))
                and counts['passed'] == 1 and counts['failed'] == counts['skipped'] == 0
                and counts.get('expectedFailures', 0) == 0
                and data['request']['onlyTesting'] == [SELECTOR])
    except (KeyError, TypeError):
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator-id', required=True, help='UUID of a simulator reserved for this run')
    parser.add_argument('--derived-data', type=Path, default=ROOT / 'build/smoke/DerivedData')
    args = parser.parse_args()
    base = ROOT / 'build/smoke'
    base.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='run-', dir=base))
    cmd = command(args.simulator_id, args.derived_data.resolve(), output / 'Mivu.xcresult')
    start = time.monotonic()
    print('Smoke (120s cap); evidence: ' + str(output), flush=True)
    status = execute(cmd, output)
    try:
        result = json.loads((output / 'result.json').read_text())
        success = status == 0 and passed(result) and (output / 'Mivu.xcresult').is_dir()
    except (OSError, ValueError):
        success = False
    elapsed = round(time.monotonic() - start, 2)
    record = dict(sourceCommit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                  dirty=bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)),
                  command=cmd, elapsedSeconds=elapsed, exitStatus=status, passed=success)
    (output / 'provenance.json').write_text(json.dumps(record, indent=2) + '\n')
    print(('PASS' if success else 'FAIL') + f': smoke in {elapsed}s; evidence: {output}')
    return 0 if success else status or 1


if __name__ == '__main__':
    sys.exit(main())
