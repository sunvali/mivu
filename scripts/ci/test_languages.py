"""Check the string catalog validator."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import languages


def unit(value):
    return {'stringUnit': {'state': 'translated', 'value': value}}


def catalog(**strings):
    return {'ios/Mivu/Localizable.xcstrings': {'sourceLanguage': 'en', 'strings': strings}}


PLURAL = {'variations': {'plural': {'one': unit('%lld meal'), 'other': unit('%lld meals')}}}
HEBREW_PLURAL = {'variations': {'plural': {'one': unit('ארוחה אחת'), 'two': unit('%lld ארוחות'), 'other': unit('%lld ארוחות')}}}


class Catalogs(unittest.TestCase):
    def test_language_outside_known_regions_fails(self):
        errs = languages.errors(catalog(Account={'localizations': {'he': unit('חשבון')}}), {'en'})
        self.assertTrue(any("'he'" in e and 'knownRegions' in e for e in errs), errs)

    def test_missing_translation_fails(self):
        errs = languages.errors(catalog(Account={'localizations': {'he': unit('חשבון')}}, Diary={}), {'en', 'he'})
        self.assertEqual(len(errs), 1, errs)
        self.assertIn("'Diary'", errs[0]); self.assertIn("'he'", errs[0])

    def test_untranslated_state_fails(self):
        entry = {'localizations': {'he': {'stringUnit': {'state': 'new', 'value': ''}}}}
        self.assertTrue(languages.errors(catalog(Account=entry), {'en', 'he'}))

    def test_missing_plural_form_fails(self):
        entry = {'localizations': {'en': {'variations': {'plural': {'one': unit('%lld meal')}}}}}
        errs = languages.errors(catalog(**{'%lld meals': entry}), {'en'})
        self.assertTrue(any('other' in e for e in errs), errs)

    def test_stale_key_fails(self):
        errs = languages.errors(catalog(Old={'extractionState': 'stale'}), {'en'})
        self.assertTrue(any("'Old'" in e and 'stale' in e for e in errs), errs)

    def test_clean_catalogs_pass(self):
        strings = {'Account': {'localizations': {'he': unit('חשבון')}},
                   '%lld meals': {'localizations': {'en': PLURAL, 'he': HEBREW_PLURAL}},
                   'Mivu': {'shouldTranslate': False}}
        self.assertEqual(languages.errors(catalog(**strings), {'en', 'he'}), [])

    def test_source_language_needs_no_entry(self):
        self.assertEqual(languages.errors(catalog(Account={}), {'en'}), [])

    def test_source_language_keeps_the_state_xcode_extracts(self):
        entry = {'extractionState': 'extracted_with_value', 'localizations': {'en': {'stringUnit': {'state': 'new', 'value': '%1$@ of %2$@'}}}}
        self.assertEqual(languages.errors(catalog(**{'%@ of %@': entry}), {'en'}), [])
        entry['localizations']['he'] = {'stringUnit': {'state': 'new', 'value': '%1$@ of %2$@'}}
        self.assertTrue(languages.errors(catalog(**{'%@ of %@': entry}), {'en', 'he'}))

    def test_xliff_key_missing_from_catalog_fails(self):
        xliff = ('<xliff xmlns="urn:oasis:names:tc:xliff:document:1.2"><file original="Mivu/Localizable.xcstrings"><body>'
                 '<trans-unit id="Account"><source>Account</source></trans-unit>'
                 '<trans-unit id="Brand new"><source>Brand new</source></trans-unit></body></file></xliff>')
        errs = languages.xliff_errors(xliff, catalog(Account={}))
        self.assertEqual(len(errs), 1, errs)
        self.assertIn("'Brand new'", errs[0])

    def test_xliff_plural_units_resolve_to_their_key(self):
        xliff = ('<xliff xmlns="urn:oasis:names:tc:xliff:document:1.2"><file original="Mivu/Localizable.xcstrings"><body>'
                 '<trans-unit id="%lld meals|==|plural.one"><source>%lld meal</source></trans-unit></body></file></xliff>')
        self.assertEqual(languages.xliff_errors(xliff, catalog(**{'%lld meals': {}})), [])

    def test_widget_text_must_be_in_the_widget_catalog(self):
        source = 'Text("Snap It"); capsule("Coach", systemImage: "x"); let id = "calories"'
        app = {'Snap It': {}, 'Coach': {}, 'Unused': {}}
        self.assertEqual(languages.widget_errors(source, app, {'Snap It': {}}), ["'Coach' is shown by the widget but is not in its catalog"])

    def test_widget_literal_after_an_interpolated_one_is_checked(self):
        source = 'Text("\\(x) kcal"); Text("Open Mivu")\n#Preview("Expanded", as: .dynamicIsland(.expanded)) {'
        errs = languages.widget_errors(source, {'Open Mivu': {}, 'Expanded': {}}, {})
        self.assertEqual(errs, ["'Open Mivu' is shown by the widget but is not in its catalog"])

    def test_shortcut_phrase_sets_count_as_values(self):
        entry = {'localizations': {'en': {'stringSet': {'state': 'new', 'values': ['Tell ${applicationName}']}}}}
        self.assertEqual(languages.errors(catalog(**{'Tell ${applicationName}': entry}), {'en'}), [])
        entry['localizations']['he'] = {'stringSet': {'state': 'new', 'values': ['Tell']}}
        self.assertTrue(languages.errors(catalog(**{'Tell ${applicationName}': entry}), {'en', 'he'}))

    def test_shipped_languages_come_from_known_regions(self):
        text = 'knownRegions = (\n\t\t\t\ten,\n\t\t\t\the,\n\t\t\t\tBase,\n\t\t\t);'
        self.assertEqual(languages.shipped(text), {'en', 'he'})


    def test_translation_must_keep_the_source_placeholders(self):
        entry = {'localizations': {'he': unit('%1$@ מתוך')}}
        errs = languages.errors(catalog(**{'%@ of %@': entry}), {'en', 'he'})
        self.assertTrue(any('placeholder' in e for e in errs), errs)
        entry = {'localizations': {'he': unit('%2$@ מתוך %1$@')}}
        self.assertEqual(languages.errors(catalog(**{'%@ of %@': entry}), {'en', 'he'}), [])

    def test_plural_counting_form_must_keep_the_number(self):
        forms = {'one': unit('%lld ужин'), 'few': unit('ужина'), 'many': unit('%lld ужинов'), 'other': unit('%lld ужина')}
        errs = languages.errors(catalog(**{'%lld meals': {'localizations': {'en': PLURAL, 'ru': {'variations': {'plural': forms}}}}}), {'en', 'ru'})
        self.assertTrue(any('placeholder' in e and "'few'" in e for e in errs), errs)

    def test_plural_needs_every_form_the_language_uses(self):
        errs = languages.errors(catalog(**{'%lld meals': {'localizations': {'en': PLURAL, 'he': PLURAL}}}), {'en', 'he'})
        self.assertTrue(any("'two'" in e for e in errs), errs)

    def test_substitution_placeholders_are_compared_by_name(self):
        en = {'stringUnit': {'state': 'translated', 'value': 'Set %1$lld: %#@reps@'},
              'substitutions': {'reps': {'argNum': 2, 'formatSpecifier': 'lld', 'variations': PLURAL['variations']}}}
        he = {'stringUnit': {'state': 'translated', 'value': 'סט %1$lld: %#@reps@'},
              'substitutions': {'reps': {'argNum': 2, 'formatSpecifier': 'lld', 'variations': HEBREW_PLURAL['variations']}}}
        self.assertEqual(languages.errors(catalog(**{'Set %lld: %lld meals': {'localizations': {'en': en, 'he': he}}}), {'en', 'he'}), [])


if __name__ == '__main__':
    unittest.main()
