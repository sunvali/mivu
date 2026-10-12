#!/usr/bin/env python3
"""Reject a green XCTest wrapper when no real named tests ran."""
import json
import sys
from pathlib import Path


def validate(summary, tests):
    passed = summary.get('passedTests', 0)
    if summary.get('totalTestCount', 0) <= 0 or passed <= 0:
        raise ValueError('No passing tests in xcresult; zero-test runs cannot pass.')
    if summary.get('failedTests', 0) or summary.get('expectedFailures', 0):
        raise ValueError('xcresult contains failures or expected failures.')
    names = []

    def visit(nodes):
        for node in nodes:
            if node.get('nodeType') == 'Test Case' and node.get('result') == 'Passed':
                names.append(node['name'])
            visit(node.get('children', []))

    visit(tests.get('testNodes', []))
    if not names:
        raise ValueError('xcresult contains no named passing test cases.')
    return passed, sorted(set(names))


if __name__ == '__main__':
    directory = Path(sys.argv[1])
    summary = json.loads((directory / 'test-summary.json').read_text())
    tests = json.loads((directory / 'test-cases.json').read_text())
    try:
        passed, names = validate(summary, tests)
    except ValueError as error:
        sys.exit(str(error))
    report = (f"Tests: {passed} passed, {summary.get('failedTests', 0)} failed, "
              f"{summary.get('skippedTests', 0)} skipped.\n\n" + '\n'.join(names) + '\n')
    (directory / 'test-report.txt').write_text(report)
    print(report)
