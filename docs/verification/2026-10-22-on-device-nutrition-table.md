# On-device nutrition table — verification

Plan: [2026-10-22-on-device-nutrition-table](../superpowers/plans/2026-10-22-on-device-nutrition-table.md)

## Task 1: table build (2026-10-22)

- **Source:** USDA FoodData Central, `FoodData_Central_survey_food_csv_2024-10-31.zip` (FNDDS 2021–2023), from https://fdc.nal.usda.gov/fdc-datasets/. Size 3,325,692 bytes; SHA-256 `5ccc25ec2777a8982fbb61378a42f415316173eb11e48c9a8ba4cb19f5a4f29c`. Public domain / CC0; credit "USDA FoodData Central".
- **Script:** `scripts/nutrition/build_fndds.py`. Python 3 standard library only; SQLite 3.54.0 with FTS5 (`porter unicode61`).
- **Test:** `python3 -I -m unittest discover -s scripts/nutrition -p 'test_*.py'` → 1 test, OK. It is not part of the `scripts/ci` hook discovery, so run it whenever the data is rebuilt.
- **Output:** `ios/Mivu/Resources/fndds.sqlite`, 1,667,072 bytes, with 5,431 foods (kcal, carbs, protein and fat per 100 g) and 22,043 portions with gram weight > 0.
- **Spot checks:**

  | Search | Result |
  |---|---|
  | `cola diet` | "Soft drink, cola, diet" (2 kcal/100 g) |
  | `big mac` | "Big Mac (McDonalds)" (261 kcal/100 g) |
  | `grilled chicken breast` | "Chicken breast, grilled without sauce, skin eaten" (206 kcal/100 g) |

  "Apple, raw" portions include "1 medium" (200 g), "1 small" (165 g) and "Quantity not specified" (200 g).

- **Findings for Tasks 2–3:**
  - Plain `apple` ranks pie, cobbler and crisp first, so ranking must surface plain foods in the top 5.
  - `coke zero` matches "Powerade Zero", so extraction should give generic names ("diet cola").
  - Pizza portions say "piece", not "slice", so unit matching needs synonyms; "Quantity not specified" is the default weight.
