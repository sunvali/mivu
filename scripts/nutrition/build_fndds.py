#!/usr/bin/env python3
"""Build the bundled on-device nutrition table from USDA FNDDS CSVs (public domain, CC0).

Usage: build_fndds.py <unzipped FoodData_Central_survey_food_csv folder> <output .sqlite>
Run it once per app, so the two copies never link at build time:
  ios/Mivu/Resources/fndds.sqlite and android/app/src/main/assets/fndds.sqlite
"""
import csv
import sqlite3
import sys
from pathlib import Path

# FNDDS survey foods key food_nutrient by nutrient number, per 100 g.
NUTRIENTS = {'208': 'kcal', '205': 'carbs', '203': 'protein', '204': 'fat'}


def rows(path):
    with path.open(newline='', encoding='utf-8') as file:
        yield from csv.DictReader(file)


def build(source, output):
    source, output = Path(source), Path(output)
    foods = {row['fdc_id']: {'description': row['description']} for row in rows(source / 'food.csv')}
    for row in rows(source / 'food_nutrient.csv'):
        name = NUTRIENTS.get(row['nutrient_id'])
        if name and row['fdc_id'] in foods:
            foods[row['fdc_id']][name] = float(row['amount'])
    complete = {code: food for code, food in foods.items() if all(name in food for name in NUTRIENTS.values())}
    portions = [(int(row['fdc_id']), row['portion_description'], float(row['gram_weight']))
                for row in rows(source / 'food_portion.csv')
                if row['fdc_id'] in complete and float(row['gram_weight'] or 0) > 0]

    output.unlink(missing_ok=True)
    database = sqlite3.connect(output)
    with database:
        database.executescript('''
            create table foods(code integer primary key, description text not null,
                               kcal real not null, carbs real not null, protein real not null, fat real not null);
            create table portions(code integer not null references foods(code), description text not null, grams real not null);
            create index portions_code on portions(code);
            create virtual table foods_fts using fts5(description, content='foods', content_rowid='code', tokenize='porter unicode61');
        ''')
        database.executemany('insert into foods values (?, ?, ?, ?, ?, ?)',
                             [(int(code), food['description'], food['kcal'], food['carbs'], food['protein'], food['fat'])
                              for code, food in complete.items()])
        database.executemany('insert into portions values (?, ?, ?)', portions)
        database.execute("insert into foods_fts(foods_fts) values ('rebuild')")
    database.execute('vacuum')
    database.close()
    return {'foods': len(complete), 'portions': len(portions)}


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    print(build(sys.argv[1], sys.argv[2]))
