---
name: mivu-adding-a-language
description: Use when adding a new language to Mivu (Spanish, Arabic, Russian…), translating its string catalogs, reviewing or improving a shipped translation such as Hebrew, or when the owner asks for native-speaker reviewer agents for app text.
---

# Adding a language to Mivu

The app is already language-ready; a new language is translation and review work
plus a few known code spots. The recipe and rules are in
[adding a language](../../../docs/development/adding-a-language.md); read it first.
This skill is the working order and the agent team that got Hebrew right.

**The rule that matters most:** a reviewer must read each string the way it
appears on screen, with its placeholders filled in. Hebrew's worst errors only
showed up once a value was filled in ("נוסף ל-יום ב׳"), and the code that fills
it is in Swift, not in the catalog.

## Order

1. **Owner decisions first** (clickable options): register (tú/usted, du/Sie),
   regional variant (owner's markets: Israel, USA, general), how Pip's name and
   "Snap It" appear, gender approach. They go into the glossary. Use the bare
   code (`es`, not `es-419`) unless the owner asks for a region; reviewer briefs
   name the variant as `<market>`. Mivu follows the iOS language; there is no
   in-app picker (Settings' Language row opens iOS Settings).
2. **Glossary** `docs/languages/<code>.md`, modelled on `he.md`: voice, names,
   fixed terms, the prefix and placeholder rules the language needs.
3. **Hide while working:** add the code to `knownRegions` and to
   `MIVU_HIDDEN_LANGUAGES` (Debug and Release) in `project.pbxproj`. Add its CLDR
   forms to `PLURAL_FORMS` in `scripts/ci/languages.py` if missing.
4. **Draft:** `python3 scripts/ci/catalog_rows.py export <code> <scratch>/rows.tsv --missing`,
   split into 4 batches of whole keys (keep a key's plural rows together), one
   translator agent each, in parallel.
   Merge their JSON and run `catalog_rows.py apply <code> changes.json`, then
   `python3 scripts/ci/languages.py check`.
5. **Code spots** (test first):
   - `CoachReplyCheck.swift`: a `case .<language>` with its diary words beside
     `.hebrew`, and a test beside the Hebrew one in `CoachReplyCheckTests`.
     Without it the language falls to `default`, which grounds every number:
     safe, but stricter.
   - `LanguageSweepUITests.swift`: the `hebrew` mode is hard-coded. Add a mode
     for the code (launch arguments, locale, tab-name map) and the equivalents of
     `testHebrewPhoneGetsHebrew` and `testTextIsHebrew`; drop the right-to-left
     assertion for a left-to-right language.
   - `SampleAnalyzer`/`DiaryModels` `["en","he"]` check stored profile values;
     leave them.
6. **Review passes** (below) until the stop rule holds.
7. **Store:** `docs/app-store/listing.<code>.md` (limits: name and subtitle 30,
   promo 170, keywords 100, description 4000) and the same 5 shots as
   `screenshots/he`: a 6.9-inch simulator launched with `-AppleLanguages (<code>)`,
   a real ChatGPT connection and invented meals in the language, framed with
   `swift scripts/app-store/frame.swift <raw> <out> "<caption>"` into
   `docs/app-store/screenshots/<code>/`. Never touch App Store Connect.
8. **Checks:** `languages.py check`, `scripts/ci` unit tests, the sweep in the
   language's mode on iPhone and Duo, a Release build launched with
   `-AppleLanguages (<code>)`. Targeted runs only.
9. **Owner approval, then ship:** remove the code from `MIVU_HIDDEN_LANGUAGES`.
   Record `docs/verification/<date>-<code>.md` and parity rows (Android pending).

## The agent team

Briefs to copy: [agent briefs](references/agent-briefs.md). All are
`general-purpose`, model `sonnet`, read-only on the repo, and write JSON to the
scratchpad. Re-export the TSV before every pass so `current` is fresh.

| Pass | Agent | Reads | Finds |
|---|---|---|---|
| Draft | Translator ×4 | glossary, its batch | first translation |
| 1 | Native reviewer | all rows, glossary, listing | register, wrong words, platform terms; glossary proposals |
| 2 | Placeholder reviewer | rows with `%`, Swift callers | sentences that break once filled |
| 3+ | Final reviewer | all rows, new rows since last pass | what is still clearly wrong |

Every pass also returns `code.json`: shown text that bypasses translation
(`Label(String)`, `Text(stringVar)`, a ternary inside an interpolation, a plain
`?? "English"` fallback).

**Between passes you are the editor:** read each suggestion, drop taste swaps
and anything against the owner's fixed choices, update the glossary from
accepted term changes (a reviewer who disagrees with an owner choice becomes a
question to the owner, not an edit), apply with `catalog_rows.py apply`, fix code findings
with English unchanged (and teach `languages.py` the pattern if it missed it),
run `languages.py check` and the sweep.

**Stop** when a pass returns no errors and only a handful of improvements.
Hebrew took 116, 66, 10, 16, 7 changes; the placeholder pass came fourth and
found 11 errors, so run it second.

## Common mistakes

| Mistake | Fix |
|---|---|
| Reviewer reads only the catalog | Trace each placeholder string to its Swift caller and read it filled in |
| Prefix glued to a value that can start with a digit or Latin letter | The glossary's placeholder rule; reword when the value varies ("on the date %@") |
| Applying reviewer output blindly | Edit it: owner choices win, taste swaps go |
| Code fix changes English | English text and layout must stay identical; check the English sweep |
| Claiming a human native review | Say the review was by agents; suggest a native speaker reads it before launch |
| Shipping before every surface is done | Keep it in `MIVU_HIDDEN_LANGUAGES` until the owner approves |
