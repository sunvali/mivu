"""Check the translator row export and apply."""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalog_rows


def unit(value):
    return {'stringUnit': {'state': 'translated', 'value': value}}


PATH = 'ios/Mivu/Localizable.xcstrings'


def catalogs():
    return {PATH: {'sourceLanguage': 'en', 'strings': {
        'Save': {'comment': 'Button', 'localizations': {'he': unit('שמירה')}},
        '%lld meals': {'localizations': {'en': {'variations': {'plural': {'one': unit('%lld meal'), 'other': unit('%lld meals')}}}}},
        'Of %lld days': {'localizations': {'en': {**unit('Of %#@days@'), 'substitutions': {'days': {
            'argNum': 1, 'formatSpecifier': 'lld', 'variations': {'plural': {'one': unit('%arg day'), 'other': unit('%arg days')}}}}}}},
        'Ask ${applicationName}': {'localizations': {'en': {'stringSet': {'state': 'new', 'values': ['Ask ${applicationName}', 'Open ${applicationName}']}}}},
        '%@ · %@': {'shouldTranslate': False},
    }}}


class Rows(unittest.TestCase):
    def test_export_lists_each_form_the_language_needs(self):
        keys = [row[1] for row in catalog_rows.rows(catalogs(), 'he')]
        self.assertEqual(keys, ['Save', '%lld meals[plural=one]', '%lld meals[plural=other]', '%lld meals[plural=two]',
                                'Of %lld days', 'Of %lld days[sub=days,plural=one]', 'Of %lld days[sub=days,plural=other]',
                                'Of %lld days[sub=days,plural=two]', 'Ask ${applicationName}[phrases]'])
        self.assertIn(('%lld meals[plural=two]', '%lld meals'), [(row[1], row[3]) for row in catalog_rows.rows(catalogs(), 'he')])

    def test_apply_writes_every_shape_and_round_trips(self):
        data = catalogs()
        changes = [{'catalog': PATH, 'key': key, 'current': '', 'proposed': value} for key, value in [
            ('%lld meals[plural=two]', '%lld ארוחות'), ('Of %lld days', 'מתוך %#@days@'),
            ('Of %lld days[sub=days,plural=two]', 'יומיים'), ('Ask ${applicationName}[phrases]', 'לשאול ב-${applicationName} | שאל את ${applicationName}')]]
        self.assertEqual(catalog_rows.apply(data, 'he', changes), [])
        he = {row[1]: row[4] for row in catalog_rows.rows(data, 'he')}
        self.assertEqual([he[c['key']] for c in changes], [c['proposed'] for c in changes])
        sub = data[PATH]['strings']['Of %lld days']['localizations']['he']['substitutions']['days']
        self.assertEqual((sub['argNum'], sub['formatSpecifier']), (1, 'lld'))
        self.assertEqual(json.loads(catalog_rows.dump(data)), data)

    def test_apply_refuses_a_stale_current_value(self):
        data = catalogs()
        refused = catalog_rows.apply(data, 'he', [{'catalog': PATH, 'key': 'Save', 'current': 'שמור', 'proposed': 'לשמור'}])
        self.assertEqual(len(refused), 1)
        self.assertEqual(data[PATH]['strings']['Save']['localizations']['he'], unit('שמירה'))

    def test_dump_matches_the_checked_in_catalogs(self):
        for path in catalog_rows.CATALOGS:
            text = (catalog_rows.ROOT / path).read_text()
            self.assertEqual(catalog_rows.dump(json.loads(text)), text, path)


if __name__ == '__main__':
    unittest.main()
