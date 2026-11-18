# Spanish and Russian, hidden until approved

Recipe: [adding a language](../development/adding-a-language.md). Glossaries:
[es.md](../languages/es.md), [ru.md](../languages/ru.md). Branch
`feat/spanish-russian`. Tested source: `2bae4af2c2ac9b2cf1829bc6db4c0b4797aca788`
(based on `main` at `c84963f4`).

## Owner decisions (2026-11-17)

- Spanish: neutral Latin American, bare `es`, tú. Russian: bare `ru`, ты, Pip
  is «Пип» (declined), the Coach tab stays "Coach". Register was proposed by a
  native-localizer agent per language and confirmed by the owner.
- "Snap It" stays in English; gender-neutral wording by rewording.
- Both stay in `MIVU_HIDDEN_LANGUAGES` until the owner approves each one.
- Spanish: agent review plus the owner's on-screen check; no human native
  speaker has read it. Russian: the owner reads every string on one review page
  before it ships.
- iOS only; Android not started. Store listing text only; no screenshots.

## Translation and review

Two translator agents per language drafted every row (es 1,372, ru 1,407), then
review agents ran the skill's passes; each pass was edited before applying.

| Pass | Spanish | Russian |
|---|---|---|
| 1 native | 4 errors, 28 improvements | 11 errors, 71 improvements |
| 2 placeholders (Swift callers traced) | 8 errors, 19 improvements | 29 errors, 7 improvements |
| 3 final | 1 error, 9 improvements | 0 errors, 8 improvements |
| 4 final | 0, 0 | not needed |

Dropped from review output: hand-written thousands with commas in Spanish
(glossary keeps a non-breaking space) and «с дружелюбным Coach» in the Russian
listing.

## Code changes found by the review

- The calorie band "Off" had the same key as the switched-off status, so it read
  «Desactivado» / «כבוי». It has its own key, `calorieBand.off`; English is
  unchanged. The lowercase Hebrew band "off" changed from «כבוי» to «לא מדויק»
  (owner to confirm).
- `TimeZoneSync.city` shows the city in the app language («Нью-Йорк»); zones
  with no city keep their name ("UTC", "GMT+5"). The model-facing travel note
  stays English.
- Coach fact lines and receipt summaries format numbers with the phone's locale
  instead of forcing en_US («1 240 ккал», «72,5 кг»). English on a US phone is
  unchanged.
- `?? "Apple Health"`, `"Workout unavailable"`, `"Original meal day"` and
  `?? "Meal"` now go through the catalog (Hebrew values added; owner to
  confirm).
- `CoachReplyCheck` knows Spanish and Russian diary and hedge words.
- `LanguageSweepUITests` has `spanish` and `russian` modes; the Hebrew-only
  tests became `testPhoneGetsItsLanguage` and `testTextIsTranslated` (skips
  Spanish, which is written in Latin letters). The day-title month check now
  queries by month instead of reading every label, which raced the companion's
  pose label and failed on `main` too.

## Local evidence

Environment: Xcode 27.2, macOS 27.0.1, iPhone 17 Pro simulator on iOS 27.0
(region en_IL, Mac clock America/Chicago).

| Check | Result |
|---|---|
| `python3 scripts/ci/languages.py check` | pass |
| `python3 -m unittest discover -s scripts/ci -p 'test_*.py'` | 92 passed |
| MivuTests: CoachReplyLines, CoachReplyCheck, LanguageText, TimeZoneSync, Day, CoachEngine, CoachReceiptFeedback, CoachReceiptPresentation, CoachStore (`TEST_RUNNER_TZ=UTC`) | 209 of 210 passed |
| LanguageSweepUITests `testPhoneGetsItsLanguage`: hebrew, spanish, russian | 3 passed |
| LanguageSweepUITests `testTextIsTranslated`: hebrew, russian | 2 passed |
| Release build: `find Mivu.app -name es.lproj -o -name ru.lproj` | nothing found; `en` and `he` only |

The one failing unit test, `CoachStoreTests/morningWeightStartsCurrentDayAndGuardedCorrectionKeepsManualTime`,
fails the same way on unchanged `main` (`c84963f4`) at the same hour. Without
`TEST_RUNNER_TZ=UTC`, the same 12 tests fail on this branch and on `main`
because of the Mac's time zone.

## Not done

- The full sweep in `english`, `rtl` and `double` modes, largest text, and the
  iPhone Duo poses.
- Spanish and Russian Release launches with `-AppleLanguages`, store
  screenshots, spoken Siri, and Android.
- The owner's Russian read and Spanish screen check. Until they're done, both
  languages stay hidden.
