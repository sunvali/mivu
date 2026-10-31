#!/usr/bin/env python3
"""Validate docs/parity.md and require it to change with shared platform code."""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

STATUSES = {'done', 'partial', 'pending', 'equivalent', 'blocked', 'n/a'}
SCOPES = {'baseline', 'post-baseline'}
WATCHED = ('ios/', 'android/', 'fixtures/', 'design-system/mivu/')
COLUMNS = ['id', 'feature', 'scope', 'spec', 'ios', 'android', 'evidence', 'notes']
MATRIX = 'docs/parity.md'


def parse(text):
    """Rows of the first table under '## Features'."""
    rows = []
    section = text.split('## Features', 1)[-1]
    for line in section.splitlines()[1:]:
        if line.startswith('## '):
            break
        if not line.startswith('|'):
            continue
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if cells[0] in ('ID', '---') or set(cells[0]) <= {'-', ':'}:
            continue
        rows.append(dict(zip(COLUMNS, cells)))
    return rows


def evidence_for(cell, platform):
    match = re.search(rf'{platform}: (\S+)(?: \[([^\]]*)\])?', cell)
    if not match or match.group(1) == '-':
        return None, []
    return match.group(1), [t.strip() for t in (match.group(2) or '').split(',') if t.strip()]


def errors(rows, root):
    found, seen = [], set()
    for r in rows:
        rid = r.get('id', '?')
        if rid in seen:
            found.append(f'{rid}: duplicate id')
        seen.add(rid)
        if r.get('scope') not in SCOPES:
            found.append(f"{rid}: unknown scope '{r.get('scope')}'")
        for key, platform in (('ios', 'iOS'), ('android', 'Android')):
            status = r.get(key)
            if status not in STATUSES:
                found.append(f"{rid}: unknown {platform} status '{status}'")
            record, tests = evidence_for(r.get('evidence', ''), platform)
            if status in ('done', 'equivalent') and not record:
                found.append(f'{rid}: {platform} {status} needs an evidence record')
            if not record:
                continue
            path = Path(root) / record
            if not path.is_file():
                found.append(f'{rid}: {platform} evidence {record} does not exist')
                continue
            if status not in ('done', 'equivalent'):
                continue
            body = path.read_text()
            if not tests:
                found.append(f'{rid}: {platform} evidence names no tests')
            found += [f'{rid}: {record} does not mention {t}' for t in tests if t not in body]
            if not re.search(r'\b[0-9a-f]{40}\b', body):
                found.append(f'{rid}: {record} has no 40-character source SHA')
    return found


def needs_update(changed, body):
    if MATRIX in changed or re.search(r'(?m)^Parity: unchanged - \S', body or ''):
        return False
    return any(p.startswith(WATCHED) for p in changed)


def main(argv=None):
    root = Path(__file__).resolve().parents[2]
    found = errors(parse((root / MATRIX).read_text()), root)
    if os.environ.get('GITHUB_EVENT_NAME') == 'pull_request':
        changed = subprocess.check_output(
            ['git', 'diff', '--name-only', 'HEAD^1', 'HEAD'], cwd=root, text=True).split()
        with open(os.environ['GITHUB_EVENT_PATH']) as f:
            body = json.load(f)['pull_request'].get('body') or ''
        if needs_update(changed, body):
            found.append(f'{MATRIX}: change it or add "Parity: unchanged - <reason>" to the PR description')
    print('\n'.join(found))
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
