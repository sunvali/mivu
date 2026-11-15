# Adding a language

Mivu is built to take any language, including right-to-left ones. The
[design](../superpowers/specs/2026-11-14-languages-design.md) has the reasons;
this page is the recipe. A language ships whole or not at all: until every
surface below is translated, its strings stay out of the bundle.

## What a language pull request contains

1. A glossary at `docs/languages/<code>.md`, written before the draft: voice
   (Hebrew uses gender-neutral wording), how the names appear (Mivu stays in
   Latin letters; Pip is translated, for example "פיפ"), and key food and
   nutrition terms. Old Hebrew drafts are kept in `docs/languages/he-legacy.json`.
2. Translations in all four catalogs:
   - `ios/Mivu/Localizable.xcstrings` (app),
   - `ios/MivuWidgets/Localizable.xcstrings` (widgets, Live Activity, control),
   - `ios/Mivu/InfoPlist.xcstrings` (permission prompts),
   - `ios/Mivu/AppShortcuts.xcstrings` (Siri and Shortcuts phrases).
   Every plural key needs every form the language has (Arabic has six).
   Add the language's CLDR plural forms to `PLURAL_FORMS` in
   `scripts/ci/languages.py` if it is not listed yet.
3. The language code added to `knownRegions` in `ios/Mivu.xcodeproj/project.pbxproj`.
4. Store text and screenshots for that language.
5. The capture sweep below, on iPhone and iPhone Duo.

`python3 scripts/ci/languages.py check` must pass. It fails when a bundled
language misses any key, plural form or catalog, when a catalog holds a language
that is not bundled, when widget text is missing from the widget catalog, and
when a translation drops or changes a placeholder (only the `zero`, `one` and
`two` plural forms may leave the number out).

## Writing new text

| Text | What to do |
|---|---|
| Literal in `Text`, `Label`, `Button`, `Toggle`, `Section`, `.navigationTitle`, `.alert`, accessibility modifiers | Already a catalog key. |
| A `String` a person reads, built outside a view (view models, notifications, Siri replies, receipts, Pip's lines, errors, report headings) | `String(localized: "English text")`. |
| A sentence with values | One whole string with placeholders, never glued parts: `String(localized: "Remove the whole \(names) meal?")`. |
| A count next to a noun | One key with plural variations in the catalog. |
| A word that changes with a value (a workout kind, a day) | One whole sentence per value. Never lowercase, capitalize or glue a translated word into another sentence. |
| A short or ambiguous key (`open`, `Off`, `%@: %@`) | Add a `comment:` saying where it appears and what it means. |
| A unit people see (`kcal`, `g`, `kg`) | Part of the translatable string: `"\(value) kcal"`. |
| A date pattern people see | Pass it to `DiaryWeek.format`, which looks the pattern up in the catalog, so each language orders its own. |
| A stored value shown on screen (an enum raw value, a diet tag) | Show it through `LocalizedStringKey(value)` and add a manual catalog key; keep the stored value English. |
| Text the model reads, stored data, logs, support email, test fixtures | Leave it in English. Stored and model-facing values never localize. |
| Widget text | Prefer SwiftUI literals (`Text("…")`): Xcode extracts only those into the widget catalog. Strings from `ios/Shared` that the widget shows must also be in the widget catalog. |

Never compare a displayed string; compare the value behind it. Never check for a
language by name in layout code.

## Direction

- Layouts mirror automatically. Use leading/trailing, and `chevron.forward` /
  `chevron.backward` rather than left/right.
- Charts over time keep `.environment(\.layoutDirection, .leftToRight)`: time
  runs left to right in every language.
- Pip's artwork, photos and the camera never flip.
- Text a person typed or a model wrote uses `.directionFromContent(text)`, so a
  Hebrew message reads right to left on an English phone and back.
- Digits stay 0–9. The Coach reply check reads digits in any script and rejects
  numbers it cannot ground. Numbers people read are formatted with the phone's
  locale, so before Arabic ships, decide whether its numbers use 0–9 or Arabic
  digits and check the reply check reads comma decimals ("73,5").

## Sweep

Run `MivuUITests/LanguageSweepUITests` (see
[the sweep notes](../verification/languages/README.md)) in `english`, `rtl` and
`double` modes, at default and largest text, on iPhone and on the iPhone Duo
(closed, open upright, open sideways, book and table poses). Review the `rtl`
captures for anything that did not mirror and the `double` captures for clipped
text. For a new language, also run the sweep with `-AppleLanguages (<code>)`.

## Review bar

- Hebrew: the owner reads every string on one review page before it ships.
- A language the owner cannot read: a draft, a check by an independent reviewer
  for meaning, tone and fit, and the on-screen sweep.
