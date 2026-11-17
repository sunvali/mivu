#!/usr/bin/env python3
"""Rows for a translation review: key, English, translation, translator comment and where the text is used.

Usage: review_page.py <language>  > rows.json
"""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/ci'))
import languages  # noqa: E402

SOURCES = ('ios/Mivu', 'ios/MivuWidgets', 'ios/Shared')


def text(localization):
    """A localization as one readable string; plural forms as 'one: … / other: …'."""
    if not localization:
        return ''
    if 'stringSet' in localization:
        return ' / '.join(localization['stringSet'].get('values', []))
    if 'variations' in localization:
        return ' / '.join(f"{form}: {inner['stringUnit']['value']}" for form, inner in localization['variations']['plural'].items())
    value = localization.get('stringUnit', {}).get('value', '')
    for name, sub in localization.get('substitutions', {}).items():
        forms = ', '.join(f"{form}: {inner['stringUnit']['value']}" for form, inner in sub['variations']['plural'].items())
        value = value.replace(f'%#@{name}@', f'[{forms}]')
    return value


def uses(key, files):
    """file:line for each Swift literal that produces the key; interpolations stand in for placeholders."""
    pattern = re.escape(key.replace('%%', '%'))
    pattern = re.sub(r'%(?:\d+\\\$)?(?:lld|ld|d|@|f|\\\.\d+f)', r'\\\\\\(.+?\\)', pattern)
    literal = re.compile('"' + pattern + '"')
    found = []
    for path, lines in files.items():
        found += [f'{path}:{number}' for number, line in enumerate(lines, 1) if literal.search(line)]
    return found[:4]


def main(language):
    files = {str(p.relative_to(ROOT)): p.read_text().split('\n') for d in SOURCES for p in sorted((ROOT / d).rglob('*.swift'))}
    rows = []
    for path, catalog in languages.load(ROOT).items():
        for key, entry in catalog['strings'].items():
            if entry.get('shouldTranslate') is False:
                continue
            localizations = entry.get('localizations', {})
            rows.append({
                'id': hashlib.sha1(f'{path}\0{key}'.encode()).hexdigest()[:16],
                'catalog': path, 'key': key,
                'en': text(localizations.get('en')) or key,
                'translation': text(localizations.get(language)),
                'comment': entry.get('comment', ''),
                'uses': uses(key, files),
            })
    json.dump(rows, sys.stdout, ensure_ascii=False)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'he')
