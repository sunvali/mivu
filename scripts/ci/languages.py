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


def hidden_errors(pbxproj, targets=('Mivu', 'MivuWidgets')):
    """Languages in MIVU_HIDDEN_LANGUAGES must be stripped from every shipped bundle's Release build."""
    hidden = {name for value in re.findall(r'MIVU_HIDDEN_LANGUAGES = "?([^";]*)"?;', pbxproj) for name in value.split()}
    if not hidden:
        return []
    phases = {}
    for block in pbxproj.split('isa = PBXNativeTarget;')[1:]:
        name = re.search(r'\bname = "?([^";]+)"?;', block)
        listed = re.search(r'buildPhases = \((.*?)\);', block, re.S)
        if name and listed:
            phases[name[1]] = listed[1]
    found = []
    for target in targets:
        if 'Strip hidden languages' not in phases.get(target, ''):
            found += [f"hidden language {language!r} is not stripped from {target}" for language in sorted(hidden)]
    return found


def unit_of(value):
    return {'stringUnit': {'state': 'translated', 'value': value}}


def _values(localization):
    """Every stringUnit under a localization, with the plural sets on the way."""
    if 'stringUnit' in localization:
        yield localization['stringUnit']
    if 'stringSet' in localization:  # App Shortcut phrases: several values under one key
        values = localization['stringSet'].get('values', [])
        yield {'state': localization['stringSet'].get('state'), 'value': ' / '.join(values)}
    for kind, forms in localization.get('variations', {}).items():
        if kind == 'plural' and 'other' not in forms:
            yield None
        for form in forms.values():
            yield from _values(form)
    for substitution in localization.get('substitutions', {}).values():
        yield from _values(substitution)


# CLDR plural forms each language needs. shortcut: covers the expected languages; add a row with each new one.
PLURAL_FORMS = {
    'ar': {'zero', 'one', 'two', 'few', 'many', 'other'}, 'he': {'one', 'two', 'other'},
    'ru': {'one', 'few', 'many', 'other'}, 'uk': {'one', 'few', 'many', 'other'}, 'pl': {'one', 'few', 'many', 'other'},
    'es': {'one', 'many', 'other'}, 'fr': {'one', 'many', 'other'}, 'it': {'one', 'many', 'other'}, 'pt': {'one', 'many', 'other'},
    'en': {'one', 'other'}, 'de': {'one', 'other'}, 'ja': {'other'}, 'zh': {'other'}, 'ko': {'other'},
}
# Only these forms may drop the number ("one meal"); the others always cover several counts.
MAY_DROP_NUMBER = {'zero', 'one', 'two'}
PLACEHOLDER = re.compile(r'%(?:\d+\$)?(#@\w+@|[-+ 0#]*\d*(?:\.\d+)?(?:ll|l|h)?[@dDiuUxXoOfeEgGcCsSp])')


def _placeholders(value):
    """The kinds of placeholder in a value, ignoring position: '%2$@' and '%@' are the same."""
    return sorted(re.sub(r'^[-+ 0#]*\d*(?:\.\d+)?', '', kind) for kind in PLACEHOLDER.findall(value.replace('%%', '')))


def _forms(localization, form=None):
    """(plural form or None, value) for every value, with plural dictionaries checked on the way."""
    if 'stringUnit' in localization:
        yield form, localization['stringUnit'].get('value', '')
    for kind, forms in localization.get('variations', {}).items():
        for name, inner in forms.items():
            yield from _forms(inner, name if kind == 'plural' else form)
    for substitution in localization.get('substitutions', {}).values():
        yield from _forms(substitution, form)


def _plural_sets(localization):
    for kind, forms in localization.get('variations', {}).items():
        if kind == 'plural':
            yield set(forms)
        for inner in forms.values():
            yield from _plural_sets(inner)
    for substitution in localization.get('substitutions', {}).values():
        yield from _plural_sets(substitution)


def _format_errors(path, key, language, localization, source):
    found = []
    for missing in sorted({form for forms in _plural_sets(localization) for form in PLURAL_FORMS.get(language, set()) - forms}):
        found.append(f"{path}: {key!r} in {language!r} needs the plural form {missing!r}")
    expected = {}
    for form, value in _forms(source):  # the source's widest form, usually 'other'
        expected[form] = _placeholders(value)
    for form, value in _forms(localization):
        want = next((expected[f] for f in (form, 'other', None) if f in expected), [])  # [] is a real answer: '%arg days'
        got = _placeholders(value)
        if got != want and not (form in MAY_DROP_NUMBER and set(got) <= set(want)):
            found.append(f"{path}: {key!r} in {language!r} ({form or 'value'!r}) has placeholders {got}, the source has {want}")
    return found


def _text(key, entry, source):
    """The source text people read, without placeholders (Info.plist keys are names, so use their value)."""
    value = entry.get('localizations', {}).get(source, {}).get('stringUnit', {}).get('value', key)
    return PLACEHOLDER.sub('', value.replace('%%', ''))


def errors(catalogs, languages):
    found = [f"add CLDR plural forms for {language!r} to PLURAL_FORMS" for language in sorted(languages - set(PLURAL_FORMS))]
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
            text = _text(key, entry, source)
            if not any(ch.isalpha() for ch in text):
                found.append(f"{path}: {key!r} has no words; mark it shouldTranslate false")
                continue
            # A word or two alone ("Open", "Log") can be a verb, a status or a noun; translators need to know which.
            if len(text.split()) <= 2 and not entry.get('comment'):
                found.append(f"{path}: {key!r} needs a translator comment")
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
                elif language != source:
                    found += _format_errors(path, key, language, localizations[language], localizations.get(source, unit_of(key)))
    return found


def xliff_errors(xliff, catalogs):
    """Keys the compiler extracted that no catalog holds."""
    known = {key for catalog in catalogs.values() for key in catalog.get('strings', {})}
    # Plural and substitution units carry their path after '|==|'.
    ids = {unit.get('id').split('|==|')[0] for unit in ET.fromstring(xliff).iter('{urn:oasis:names:tc:xliff:document:1.2}trans-unit')}
    return [f"{key!r} is used in code but is in no string catalog" for key in sorted(ids - known)]


def widget_errors(source, app_strings, widget_strings):
    """The widget resolves text from its own catalog, and Xcode only extracts part of it there:
    any plain literal the widget code uses that the app translates must be in the widget's catalog."""
    source = re.sub(r'#Preview\([^\n]*', '', source)  # preview names are never shown to people
    literals = set(re.findall(r'"((?:[^"\\]|\\.)*)"', source))
    return [f"{key!r} is shown by the widget but is not in its catalog"
            for key in sorted(literals) if key and key in app_strings and key not in widget_strings]


WIDGET_SOURCES = ('ios/MivuWidgets', 'ios/Shared')


def load(root=ROOT):
    # Untracked catalogs count too, so a new one is checked before its first commit.
    paths = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', 'ios/**/*.xcstrings', 'ios/*.xcstrings'], cwd=root, text=True).split('\n')
    return {path: json.loads((root / path).read_text()) for path in paths if path}


def main(argv):
    catalogs = load()
    if argv[1:2] == ['check']:
        pbxproj = (ROOT / PROJECT).read_text()
        found = errors(catalogs, shipped(pbxproj)) + hidden_errors(pbxproj)
        source = ''.join(p.read_text() for d in WIDGET_SOURCES for p in sorted((ROOT / d).glob('*.swift')))
        found += widget_errors(source, catalogs['ios/Mivu/Localizable.xcstrings']['strings'],
                               catalogs['ios/MivuWidgets/Localizable.xcstrings']['strings'])
    elif argv[1:2] == ['xliff'] and len(argv) == 3:
        found = xliff_errors(Path(argv[2]).read_text(), catalogs)
    else:
        print('Use languages.py check | xliff <path to en.xliff>', file=sys.stderr)
        return 2
    print('\n'.join(found))
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
