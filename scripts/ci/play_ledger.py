#!/usr/bin/env python3
"""Validate the Play upload ledger: five fields per line, strictly increasing codes."""
import sys
from pathlib import Path


def errors(text):
    found, last = [], 0
    for n, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.startswith('#'):
            continue
        fields = line.split()
        if len(fields) != 5 or not fields[0].isdigit():
            found.append(f'line {n}: expected "code name sha date track"')
            continue
        code = int(fields[0])
        if code <= last:
            found.append(f'line {n}: code {code} must exceed {last}')
        last = max(last, code)
    return found


if __name__ == '__main__':
    problems = errors(Path(sys.argv[1]).read_text())
    print('\n'.join(problems))
    sys.exit(1 if problems else 0)
