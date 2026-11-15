# Languages step 2: Hebrew, Coach languages and voice

Plan: [2026-11-15-languages-step2-hebrew.md](../superpowers/plans/2026-11-15-languages-step2-hebrew.md).
Glossary: [he.md](../languages/he.md). Branch `feat/languages-step2`.

## What changed

- Hebrew in all four catalogs (1,213 strings), gender-neutral, from the glossary.
  The owner reviewed the strings on one page, approved them and chose five terms:
  - "היום שלך" for "waking day";
  - "Snap It" kept in Latin letters;
  - "את/ה" for "You";
  - "בודקים…" for "Thinking…";
  - Siri accepting both gendered commands.
- Release builds strip every language in `MIVU_HIDDEN_LANGUAGES` (now `he`)
  from Mivu and MivuWidgets. Debug builds, tests and captures keep it.
- Coach replies in the language of each message, gender-neutral, naming foods
  in the language used; the context names the app language as the fallback.
- The reply check reads comma decimals ("72,5") and space-grouped thousands.
  A hedged typical value ("~95") may skip grounding only in English and
  Hebrew, whose diary words are known; any other language grounds every number.
- Mixed text aligns by the script with more letters (ties right to left).
- Gregorian dates in Coach, reports, chat times and Today. Plural fixes in
  English: "in 1 day", "Added 1 photo.", "1 of 1 day logged",
  "Weight chart: 1 measured date.", "(1 meal)" in import and replace, and
  "No finished days in the last 1 day yet." (not reachable, kept for languages
  that need the form).
- Display units: weight ("kg", "lb") and common food units ("g", "slice",
  "serving"…) show translated; stored and model-facing values stay as written.
- Voice: the mic listens in the app language; a long press lists the
  keyboard languages speech supports. Falls back to US English when the chosen
  language can't be transcribed.
- Lint: translator comment required for keys of two words or fewer (482
  written), letterless keys `shouldTranslate: false`, plural forms required for
  each bundled language, and the strip phase checked.

Not done: receipt cards in the turn's language (plan Task 6). SwiftUI's locale
environment would switch only formatting, not about 30 card strings; doing it
right needs a language bundle through every card string. Cards follow the app
language.

## Evidence

Environment: macOS, Xcode 26 toolchain, "Mivu languages iPhone 18 Pro
(Claude)" simulator (iOS 27.1), "Mivu languages Duo (Claude)" simulator,
owner's iPhone Duo (physical).

| Check | Result |
|---|---|
| `python3 scripts/ci/languages.py check` | exit 0 |
| `scripts/ci/test_languages.py` | 23/23 |
| Release simulator build | no `he.lproj` in Mivu.app or MivuWidgets.appex; no Hebrew text in the bundle |
| Debug build | `he.lproj` in both |
| Unit suites for changed code (CoachReplyCheck, CoachEngine, CoachVoiceLanguages, CoachVoiceInput, LanguageText, TextDirection, CoachReceiptPresentation, DiaryReport, CoachFocus, CoachContextMessages) | all pass except `DiaryReportTests/summaryCountsEveryCalendarDayInTheRequestedRange`, which fails on `main` too |
| LanguageSweepUITests, english / rtl / hebrew / double | see "Final run" |
| Owner on iPhone Duo (Debug build of this branch with #134) | approved |

`testTextIsHebrew` found leftover English on five screens in its first run
(weight unit, food units, a Debug-only row, the system "GMT" format and the
"Dynamic Island" name); the first two were fixed and the rest are allowed as
names. Two sweep runs hit a screen-open timeout at load average 80; each passed
on rerun.

## Final run

Merged branch (main at `b78cf22e` plus this branch), iPhone 18 Pro simulator:

| Suite | Source | Passed | Failed | Skipped (other modes) |
|---|---|---|---|---|
| LanguageSweep english | `02037b5d` | 3 | 0 | 6 |
| LanguageSweep rtl | `02037b5d` | 5 | 0 | 4 |
| LanguageSweep double | `02037b5d` | 3 | 0 | 6 |
| LanguageSweep hebrew | `cb8bbca7` (owner's wording choices) | 6 | 0 | 3 |
| CompanionUITests + CoachReplyUITests | `02037b5d` | 20 | 1 | 0 |

The one failure, `CoachReplyUITests/testUnrecordedDayAskPipPrefillsDate`,
fails on `main` too (seen at `bc0753a8` during step 1). `cb8bbca7` changed
only Hebrew strings and the Hebrew sweep's list of Latin names after `02037b5d`.

## Blocked or not run

- Scripted live model check with a ChatGPT sign-in (plan Task 11): not run.
  The owner used the build on a real iPhone Duo instead.
- Siri phrases in Hebrew and real-device VoiceOver in Hebrew: not checked.
- Hebrew speech on a device: not checked by script; the Simulator has no
  Hebrew transcriber, which is why the fallback exists.
