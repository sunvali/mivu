#!/usr/bin/env python3
"""Validate the iOS string catalogs: a bundled language is complete everywhere, or it is not bundled."""
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = 'ios/Mivu.xcodeproj/project.pbxproj'


def shipped(pbxproj):
    """The bundled languages: knownRegions without Base."""
    block = re.search(r'knownRegions = \((.*?)\);', pbxproj, re.S)
    return {name for name in re.findall(r'[\w-]+', block[1] if block else '') if name != 'Base'}


def _values(localization):
    """Every stringUnit under a localization, with the plural sets on the way."""
    if 'stringUnit' in localization:
        yield localization['stringUnit']
    for kind, forms in localization.get('variations', {}).items():
        if kind == 'plural' and 'other' not in forms:
            yield None
        for form in forms.values():
            yield from _values(form)
    for substitution in localization.get('substitutions', {}).values():
        yield from _values(substitution)


def errors(catalogs, languages):
    found = []
    for path, catalog in sorted(catalogs.items()):
        source = catalog.get('sourceLanguage', 'en')
        for key, entry in sorted(catalog.get('strings', {}).items()):
            if entry.get('extractionState') == 'stale':
                found.append(f"{path}: {key!r} is stale; delete it or restore its use")
            localizations = entry.get('localizations', {})
            for language in sorted(set(localizations) - languages):
                found.append(f"{path}: {key!r} has {language!r}, which is not in knownRegions")
            if entry.get('shouldTranslate') is False:
                continue
            for language in sorted(languages):
                if language not in localizations:
                    if language != source:
                        found.append(f"{path}: {key!r} has no {language!r} translation")
                    continue
                units = list(_values(localizations[language]))
                if None in units:
                    found.append(f"{path}: {key!r} in {language!r} has a plural without 'other'")
                # Xcode leaves extracted source strings in state 'new'; only a translation must be marked done.
                done = (lambda u: bool(u.get('value'))) if language == source else (lambda u: u.get('state') == 'translated' and bool(u.get('value')))
                if not units or any(u and not done(u) for u in units):
                    found.append(f"{path}: {key!r} in {language!r} is not fully translated")
    return found


def xliff_errors(xliff, catalogs):
    """Keys the compiler extracted that no catalog holds."""
    known = {key for catalog in catalogs.values() for key in catalog.get('strings', {})}
    ids = {unit.get('id') for unit in ET.fromstring(xliff).iter('{urn:oasis:names:tc:xliff:document:1.2}trans-unit')}
    return [f"{key!r} is used in code but is in no string catalog" for key in sorted(ids - known)]


def load(root=ROOT):
    paths = subprocess.check_output(['git', 'ls-files', 'ios/**/*.xcstrings', 'ios/*.xcstrings'], cwd=root, text=True).split('\n')
    return {path: json.loads((root / path).read_text()) for path in paths if path}


def main(argv):
    catalogs = load()
    if argv[1:2] == ['check']:
        found = errors(catalogs, shipped((ROOT / PROJECT).read_text()))
    elif argv[1:2] == ['xliff'] and len(argv) == 3:
        found = xliff_errors(Path(argv[2]).read_text(), catalogs)
    else:
        print('Use languages.py check | xliff <path to en.xliff>', file=sys.stderr)
        return 2
    print('\n'.join(found))
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
