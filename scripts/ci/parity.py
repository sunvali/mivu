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
IGNORED = ('ios/MivuTests/', 'ios/MivuUITests/', 'android/app/src/test/', 'android/app/src/androidTest/',
           'ios/version.txt', 'ios/CHANGELOG.md', 'android/version.txt', 'android/CHANGELOG.md')
COLUMNS = ['id', 'feature', 'scope', 'spec', 'ios', 'android', 'evidence', 'notes']
MATRIX = 'docs/parity.md'
UNCHANGED = re.compile(r'(?im)^Parity:\s*unchanged\s*[-–—:]\s*\S')
PROMPT = f'{MATRIX}: change it or add "Parity: unchanged - <reason>" to a commit message or the PR description'


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


def needs_update(changed, body='', *, messages=()):
    if MATRIX in changed or any(UNCHANGED.search(t or '') for t in (body, *messages)):
        return False
    return any(p.startswith(WATCHED) and not p.startswith(IGNORED) for p in changed)


def check_range(root, base, head, body=''):
    changed = subprocess.check_output(
        ['git', 'diff', '--name-only', base, head], cwd=root, text=True).split()
    log = subprocess.check_output(
        ['git', 'log', '--format=%B%x00', f'{base}..{head}'], cwd=root, text=True)
    messages = [m.strip() for m in log.split('\0') if m.strip()]
    return [PROMPT] if needs_update(changed, body, messages=messages) else []


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    root = Path(__file__).resolve().parents[2]
    found = errors(parse((root / MATRIX).read_text()), root)
    if argv[:1] == ['--range'] and len(argv) == 3:
        found += check_range(root, argv[1], argv[2])
    elif os.environ.get('GITHUB_EVENT_NAME') == 'pull_request':
        with open(os.environ['GITHUB_EVENT_PATH']) as f:
            body = json.load(f)['pull_request'].get('body') or ''
        found += check_range(root, 'HEAD^1', 'HEAD', body)
    if found:
        print('\n'.join(found))
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
