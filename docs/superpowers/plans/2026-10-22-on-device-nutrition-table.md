# On-Device Nutrition Table Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the Apple Intelligence · iPhone mode, the on-device model only identifies foods and amounts; calories and macros come from a bundled USDA table. ChatGPT and the Cloud mode are unchanged.

**Why:** Apple's guidance for the ~3B on-device model is to keep it off facts and arithmetic ([WWDC25 248](https://developer.apple.com/videos/play/wwdc2025/248)). Measured on 2026-10-22, the model-only path still missed badly on some foods (2 pizza slices 250 kcal vs ~600; 200 g chicken 144 vs ~330) after greedy sampling and the macro floor.

**Architecture:** Everything lives in the on-device path (`AppleLocalInference.swift`) plus one new read-only table type. `CoachEngine`, `CoachTools`, `FoodEvidence`, `ResponsesClient` and `ChatGPTConnection`'s ChatGPT branch are not edited. The local path keeps returning a single `log_food` call with serving totals, so receipts, editing and scaling work as today.

**Tech stack:** Swift 6, FoundationModels (iOS 27), SQLite3 with FTS5 (already linked), Swift Testing, XcodeBuildMCP. Python 3 build script with no third-party packages. No network at runtime.

## Decisions (owner, 2026-10-22)

1. **Dataset:** USDA FNDDS 2021–2023 only (~5,400 everyday foods and dishes, with "Portions and Weights"). Public domain / CC0; credit "USDA FoodData Central" in Settings. ([FoodData Central downloads](https://fdc.nal.usda.gov/download-datasets), [FNDDS at a glance](https://ars.usda.gov/ARSUserFiles/80400530/pdf/fndds/2021_2023_At_A_Glance.pdf))
2. **Units:** keep the person's unit ("2 slice"). Grams come from the matched FNDDS portion; totals are computed in code. Items stay `provenance: .estimate`, `uncertain: true` (identity and portion are still estimates); the reply names the USDA match.
3. **Matching:** FTS5 search returns the top 5 entries; a second small on-device call picks one index or "none" (guided `.anyOf`). Greedy sampling for both calls.

## Data flow (one Coach turn, local mode)

1. **Extract** (call 1): `intent`, `foods[name, quantity, unit, grams]`, `editFood`, `editQuantity`. The nutrition fields stay only as the fallback for an unmatched food.
2. **Search:** for each food, FTS5 over FNDDS descriptions (lowercased; plural "s" folded), top 5.
3. **Pick** (call 2, per food): the prompt holds the food phrase plus the 5 descriptions. The output is an index 1–5 or 0 for none.
4. **Portion grams:**
   - `g`, or `ml` treated as g (or the FNDDS "fl oz" portion density when present): the quantity itself.
   - Otherwise, the first FNDDS portion whose description contains the unit word ("slice", "medium", "cup", "can"), times the quantity.
   - Otherwise, the model's `grams` estimate.
5. **Nutrition:** per-100 g values × grams / 100, then rounding. The existing macro floor stays as a guard for the unmatched fallback.
6. **Save:** the same single `log_food` call as today.

Token budget: both calls are small (the message, or a phrase plus 5 short lines); a photo adds ~197 tokens (measured). Read `SystemLanguageModel.default.contextSize` and assert the prompt's `tokenCount` fits before calling.

## Tasks

### Task 1: Build the table (owner approves the download first)
- [ ] `scripts/nutrition/build_fndds.py`:
  - Reads the FNDDS 2021–2023 CSVs from a local folder the owner downloads. State the file names and sizes, and ask before downloading.
  - Writes `ios/Mivu/Resources/fndds.sqlite`:
    - `foods(code, description, kcal, carbs, protein, fat)` per 100 g;
    - `portions(code, description, grams)`;
    - `foods_fts` (FTS5 over description).
  - Keeps only the four nutrients. Target ≤ 5 MB.
- [ ] `scripts/nutrition/test_build_fndds.py` on a 5-row synthetic CSV fixture (stdlib `unittest`, runs in the existing Linux script checks).
- [ ] Record the source version, row counts and file size in `docs/verification/2026-10-22-on-device-nutrition-table.md`.

### Task 2: `NutritionTable` (read-only)
- [ ] Failing tests in `ios/MivuTests/NutritionTableTests.swift` against a small fixture database built by the same script:
  - search ranks "pepperoni pizza";
  - portion "slice" resolves to grams;
  - an unknown unit returns nil;
  - the per-100 g math.
- [ ] `ios/Mivu/Analysis/NutritionTable.swift`: open the bundled file read-only with `sqlite3_open_v2(SQLITE_OPEN_READONLY)`; `search(_:limit:)` and `portionGrams(code:unit:)`. Reuse the app's existing SQLite statement helpers if they fit.

### Task 3: Extraction-only schema and the pick step
- [ ] Failing engine tests (model calls injected, as in `AppleInferenceTests`):
  - "2 slices of pepperoni pizza" with an injected pick of the pizza row saves 2 slice with the table's slice grams × per-100 g;
  - pick 0 falls back to the model's estimate plus the macro floor;
  - a weighed "200 g chicken" uses 200 g directly.
- [ ] Implement in `AppleLocalInference.swift` behind the existing `generate` seam, plus a `pick` seam with the same pattern.

### Task 4: Credit and wording
- [ ] Settings → Coach AI footer (iPhone mode): "Nutrition from USDA FoodData Central."
- [ ] Reply text names the matched description, e.g. "Pizza, pepperoni, regular crust".

### Task 5: Accuracy gate (local, live model)
- [ ] Rerun the 14-food probe and add 10 more common foods. Pass criteria:
  - median relative error ≤ 10%;
  - no item off by more than 50% when matched;
  - unmatched rate reported.
- [ ] Record the device or simulator, the source SHA and per-food results in the verification doc. Remove the temporary probe after recording.

### Task 6: Verify and ship
- [ ] Focused tests, then the full `MivuTests` and the ChatGPT UI tests (consent, settings, onboarding) through XcodeBuildMCP. The ChatGPT tests must stay green.
- [ ] Install on the owner's iPhone 15 Pro and run a real check: pizza, apple, Coke Zero, chicken 200 g and one photo.
- [ ] Ponytail Review; conventional commits.

## Risks and limits
- **Brand names** (Big Mac, Coke Zero) are only approximated by generic FNDDS entries ("cheeseburger, fast food", "soft drink, cola, diet"). Pick 0 keeps the model fallback.
- **App size** grows by a few MB.
- **Matching** costs about one extra second per food on-device.
- **Language:** FNDDS is US-centric and English-only, which matches the English-only MVP.
- **Out of scope:** using the same table for ChatGPT's `lookup_nutrition`. It could help offline, but it would touch shared code; plan it separately if wanted.
