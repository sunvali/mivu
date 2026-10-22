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

- **Findings that shaped Tasks 2–3** (handled there):
  - Plain `apple` ranks pie, cobbler and crisp first, so ranking must surface plain foods in the top 5.
  - `coke zero` matches "Powerade Zero", so extraction should give generic names ("diet cola").
  - Pizza portions say "piece", not "slice", so unit matching needs synonyms; "Quantity not specified" is the default weight.

## Tasks 2–3: table reader and on-device wiring (2026-10-22)

- **Code:**
  - `ios/Mivu/Analysis/NutritionTable.swift`: read-only FTS5 search, re-ranked so plain foods come first; portion grams with unit synonyms.
  - `AppleLocalInference.swift`: extraction adds `searchName`; the on-device pick step chooses a table entry (greedy, 0 = none).
- **Grams rule:** a weighed amount (g, ml) or a portion naming the person's unit or a synonym; otherwise the model's estimate (with the calorie floor). ChatGPT, Cloud, `CoachEngine`, `CoachTools` and `FoodEvidence` are unchanged.
- **Tests:** `NutritionTableTests` (2) and `AppleInferenceTests` (15): 17 passed on the iOS 27.0 simulator (iPhone 18 Pro Max).
- **Live accuracy:** iOS 27.0 simulator, on-device model, 24 synthetic text foods with rough reference calories (several references are themselves approximate, e.g. FNDDS puts a medium apple at 122 kcal).

  | Variant | Median relative error | Worst | Over 50% |
  |---|---|---|---|
  | Model only (pick → none) | 23% | 50% | 0 |
  | Table with default "Quantity not specified" serving | 22% | 269% | 3 |
  | Table + model serving weight | 28% | 108% | 4 |
  | **Shipped: table only for weighed or unit-matched portions** | **21%** | 75% (cheesecake slice → large "piece") | 1 |

  Clear wins:

  | Food | Model only | Shipped | Reference |
  |---|---|---|---|
  | 200 g chicken | 165 | 302 | 330 |
  | 150 g salmon | 199 | 282 | 310 |
  | 2 slices pepperoni pizza | 300 | 531 | 600 |
  | 2 tbsp peanut butter | 152 | 191 | 190 |

  Remaining misses:
  - oatmeal 40 g, matched as cooked;
  - latte;
  - croissant;
  - "a can" of Coke Zero read as 3 cans.

- **Gate:** the plan's gate (median ≤ 10%, no matched food > 50% off) is **not met** in either mode. This is reported, not hidden; further gains likely need the Cloud mode or better portion and preparation handling.
- **Not run yet:** an on-device check on the owner's iPhone 15 Pro; photo turns with the table.

## On-device onboarding targets (2026-10-23)

- **Check:** a live simulator run (iOS 27.0, iPhone 18 Pro Max) of `AppleInference.respondLocally(namespace: nil)` with three synthetic profiles (female, male, unspecified), parsed by `OnboardingTargets.parse`.
- **Result:** 3 of 3 parsed. The model returned the formula estimate unchanged, plus a one-line explanation.
- **Test:** none permanent, because the path calls the live model.
