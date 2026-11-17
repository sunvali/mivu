#!/usr/bin/env python3
"""One row per translatable value, for translators and reviewers, and back into the catalogs.

  catalog_rows.py export <lang> <out.tsv> [--missing]   columns: catalog, key, comment, english, current
  catalog_rows.py apply <lang> <changes.json>            [{"catalog","key","current","proposed"}, ...]

Row keys: "Key", "Key[plural=few]", "Key[sub=days,plural=two]", "Key[phrases]" (Siri phrases joined by " | ").
Apply refuses a change whose "current" is not the catalog's value now; run languages.py check afterwards.
"""
import json
import re
import sys
from pathlib import Path

from languages import PLURAL_FORMS

ROOT = Path(__file__).resolve().parents[2]
CATALOGS = ['ios/Mivu/Localizable.xcstrings', 'ios/MivuWidgets/Localizable.xcstrings',
            'ios/Mivu/InfoPlist.xcstrings', 'ios/Mivu/AppShortcuts.xcstrings']
PHRASES = ' | '


def _unit(loc):
    return loc.get('stringUnit', {}).get('value', '') if loc else ''


def _form(forms, form):
    """The English for a plural form the source may not have (Hebrew 'two' reads English 'other')."""
    return _unit(forms.get(form) or forms.get('other'))


def rows(catalogs, lang):
    """(catalog, row key, comment, english, current) for every value the language needs."""
    forms = sorted(PLURAL_FORMS[lang])
    for path, catalog in catalogs.items():
        for key, entry in catalog['strings'].items():
            if entry.get('shouldTranslate') is False:
                continue
            locs = entry.get('localizations', {})
            en, target = locs.get('en', {}), locs.get(lang, {})
            note = (entry.get('comment') or '').replace('\t', ' ').replace('\n', ' ')
            if 'stringSet' in en:
                yield path, f'{key}[phrases]', note, PHRASES.join(en['stringSet']['values']), PHRASES.join(target.get('stringSet', {}).get('values', []))
            elif 'plural' in en.get('variations', {}):
                for form in forms:
                    yield path, f'{key}[plural={form}]', note, _form(en['variations']['plural'], form), _unit(target.get('variations', {}).get('plural', {}).get(form))
            else:
                yield path, key, note, _unit(en) or key, _unit(target)
                for name, sub in en.get('substitutions', {}).items():
                    mine = target.get('substitutions', {}).get(name, {}).get('variations', {}).get('plural', {})
                    for form in forms:
                        yield path, f'{key}[sub={name},plural={form}]', note, _form(sub['variations']['plural'], form), _unit(mine.get(form))


def _translated(value):
    return {'stringUnit': {'state': 'translated', 'value': value}}


def apply(catalogs, lang, changes):
    """Write each proposed value; returns the changes refused, with the reason."""
    current = {(path, key): value for path, key, _, _, value in rows(catalogs, lang)}
    refused = []
    for change in changes:
        path, row = change['catalog'], change['key']
        if (path, row) not in current:
            refused.append((change, 'no such row'))
            continue
        if current[path, row] != change['current']:
            refused.append((change, f'catalog now has {current[path, row]!r}'))
            continue
        key, part = re.fullmatch(r'(.*?)(?:\[(.*)\])?', row, re.S).groups()
        entry = catalogs[path]['strings'][key]
        loc = entry.setdefault('localizations', {}).setdefault(lang, {})
        value = change['proposed']
        if part == 'phrases':
            loc['stringSet'] = {'state': 'translated', 'values': [p.strip() for p in value.split(PHRASES.strip())]}
        elif part and part.startswith('plural='):
            loc.setdefault('variations', {}).setdefault('plural', {})[part[7:]] = _translated(value)
        elif part:
            name, form = re.fullmatch(r'sub=(\w+),plural=(\w+)', part).groups()
            source = entry['localizations']['en']['substitutions'][name]
            sub = loc.setdefault('substitutions', {}).setdefault(name, {k: v for k, v in source.items() if k != 'variations'})
            sub.setdefault('variations', {}).setdefault('plural', {})[form] = _translated(value)
        else:
            loc['stringUnit'] = _translated(value)['stringUnit']
        current[path, row] = value
    return refused


def dump(catalog):
    """Xcode's own formatting, so a save in Xcode changes nothing."""
    text = json.dumps(catalog, indent=2, separators=(',', ' : '), ensure_ascii=False)
    return re.sub(r'^( *)(.*)\{\}', r'\1\2{\n\n\1}', text, flags=re.M)


def main(argv):
    command, lang, file = (argv[1:4] + [None] * 3)[:3]
    if command not in ('export', 'apply') or not file or lang not in PLURAL_FORMS:
        print(__doc__ if lang in PLURAL_FORMS or not lang else f'Add {lang!r} to PLURAL_FORMS in languages.py first')
        return 2
    catalogs = {path: json.loads((ROOT / path).read_text()) for path in CATALOGS}
    if command == 'export':
        found = [r for r in rows(catalogs, lang) if '--missing' not in argv or not r[4]]
        Path(file).write_text('\n'.join('\t'.join(r) for r in [('catalog', 'key', 'comment', 'english', 'current'), *found]) + '\n')
        print(f'{len(found)} rows')
        return 0
    changes = json.loads(Path(file).read_text())
    refused = apply(catalogs, lang, changes)
    for path, catalog in catalogs.items():
        (ROOT / path).write_text(dump(catalog))
    for change, reason in refused:
        print(f"refused {change['catalog']} {change['key']!r}: {reason}")
    print(f'{len(changes) - len(refused)} applied, {len(refused)} refused')
    return 1 if refused else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
