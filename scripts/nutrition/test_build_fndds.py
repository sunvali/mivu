#!/usr/bin/env python3
import csv
import sqlite3
import tempfile
import unittest
from pathlib import Path

from build_fndds import build


def write(path, header, rows):
    with path.open('w', newline='') as file:
        writer = csv.writer(file, quoting=csv.QUOTE_ALL)
        writer.writerow(header)
        writer.writerows(rows)


class BuildFNDDS(unittest.TestCase):
    def test_keeps_four_nutrients_real_portions_and_stemmed_search(self):
        with tempfile.TemporaryDirectory() as folder:
            source, output = Path(folder), Path(folder) / 'fndds.sqlite'
            write(source / 'food.csv', ['fdc_id', 'data_type', 'description', 'food_category_id', 'publication_date'],
                  [['1', 'survey_fndds_food', 'Pizza, pepperoni, regular crust', '3802', '2022-10-28'],
                   ['2', 'survey_fndds_food', 'Soft drink, cola, diet', '7102', '2022-10-28']])
            write(source / 'food_nutrient.csv', ['id', 'fdc_id', 'nutrient_id', 'amount'],
                  [['10', '1', '208', '276'], ['11', '1', '205', '30.1'], ['12', '1', '203', '11.9'], ['13', '1', '204', '12.1'],
                   ['14', '1', '301', '180'], ['15', '2', '208', '2'], ['16', '2', '205', '0.3'], ['17', '2', '203', '0.1'], ['18', '2', '204', '0']])
            write(source / 'food_portion.csv', ['id', 'fdc_id', 'seq_num', 'amount', 'measure_unit_id', 'portion_description', 'modifier', 'gram_weight'],
                  [['20', '1', '1', '', '9999', '1 slice', '', '107.0'], ['21', '1', '2', '', '9999', 'Quantity not specified', '', '0.0'],
                   ['22', '2', '1', '', '9999', '1 can (12 fl oz)', '', '368.0']])

            counts = build(source, output)

            self.assertEqual(counts, {'foods': 2, 'portions': 2})
            database = sqlite3.connect(output)
            self.assertEqual(database.execute('select description, kcal, carbs, protein, fat from foods where code = 1').fetchone(),
                             ('Pizza, pepperoni, regular crust', 276, 30.1, 11.9, 12.1))
            self.assertEqual(database.execute('select description, grams from portions where code = 1').fetchall(), [('1 slice', 107.0)])
            hits = database.execute("select rowid from foods_fts where foods_fts match 'pepperonis pizzas' order by rank").fetchall()
            self.assertEqual(hits, [(1,)])
            self.assertEqual({row[1] for row in database.execute('pragma table_info(foods)')}, {'code', 'description', 'kcal', 'carbs', 'protein', 'fat'})


if __name__ == '__main__':
    unittest.main()
