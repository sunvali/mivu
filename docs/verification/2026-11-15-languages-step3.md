# Languages step 3: Hebrew on every surface, and Hebrew ships

Plan: [2026-11-15-languages-step3-surfaces.md](../superpowers/plans/2026-11-15-languages-step3-surfaces.md).
Glossary: [he.md](../languages/he.md). Branch `feat/languages-step3`.
Step 2 record: [2026-11-15-languages-step2.md](2026-11-15-languages-step2.md).

## What changed

- PDF report lays out right to left when the language shown is right to left
  (`Bundle.main.preferredLocalizations`, not the phone's locale). Each cell
  draws in its own text's direction. The weight chart keeps time running left
  to right and Pip's artwork does not flip. English pages are pixel-identical
  to `main`.
- CSV keeps machine dates and numbers. It starts with a UTF-8 byte-order mark
  only when its text is not all ASCII, so Excel reads Hebrew; an all-English
  export is byte-for-byte unchanged.
- The morning reminder is rescheduled each time Mivu opens, so its text follows
  a language change.
- Settings → Diary preferences has a Language row that opens Mivu's page in iOS
  Settings. It shows only when more than one language ships.
- Fixes found by using the app in Hebrew: the Dynamic Island caption, the setup
  "Sex" and "Fat" labels, setup height and weight units, ChatGPT's setup
  explanation (now asked for in the app language), "kg" in weight receipts,
  Today's goal line, and the "serving" default in manual entry.
- Lint (`languages.py check`): a ternary inside `Text`/`Label`/… whose literals
  aren't catalog keys, a ternary inside a translated string's interpolation,
  and Siri phrases that lack `${applicationName}` or are shared between
  shortcuts.
- Hebrew App Store listing ([listing.he.md](../app-store/listing.he.md)) and five
  framed 6.9-inch screenshots ([screenshots/he](../app-store/screenshots/he)),
  captured with a real ChatGPT connection and invented Hebrew meals. Framing
  script: `scripts/app-store/frame.swift`. Nothing was entered in App Store
  Connect and no build was uploaded.
- `MIVU_HIDDEN_LANGUAGES` is empty, so Release builds ship Hebrew. The strip
  phases stay for the next language.

The owner reviewed the new Hebrew strings, the listing and the screenshots and
approved them (2026-11-15). Receipt cards follow the app language (owner,
2026-11-15).

## Captures

In [languages/step3](languages/step3): PDF summary and meal pages, small and
medium Home Screen widgets, compact and expanded Dynamic Island, and the
Shortcuts list, all in Hebrew.

## Evidence

Source: `3891a4b73b7bed18c422a82a2035709afa4d2ae7` (`feat(languages): ship Hebrew`).
Environment: macOS, Xcode 26 toolchain, "Mivu languages iPhone 18 Pro (Claude)"
simulator (iOS 27.0), "Mivu languages Duo (Claude)" simulator (iOS 27.1),
"Mivu screenshots (Claude)" simulator (iPhone 17 Pro Max) for the store shots.

| Check | Result |
|---|---|
| `python3 scripts/ci/languages.py check` | exit 0 |
| `scripts/ci/test_languages.py` | 25/25 |
| Release simulator build | `he.lproj` in Mivu.app and MivuWidgets.appex |
| Release build, launched with `-AppleLanguages (he)` | Today and Settings in Hebrew; Language row shows "שפת האפליקציה, עברית" |
| Release build, launched in English | Today unchanged; the Language row shows "App language, English" |
| Unit suites `DiaryReportTests`, `HebrewSurfaceTextTests`, `MealNotificationTests`, `CoachReplyNotificationTests`, `DayProgressActivityTests`, `LanguageTextTests`, `TextDirectionTests`, `OnboardingTargetsTests` | 67/68; the one failure, `DiaryReportTests/summaryCountsEveryCalendarDayInTheRequestedRange`, fails on `main` too |
| `DiaryUITests/testHebrewPhoneLanguageRowOpensSystemSettings` | 1/1 |

Sweeps (`LanguageSweepUITests`, default text):

| Mode | iPhone | Duo |
|---|---|---|
| english | 3 passed, 6 skipped | 3 passed, 6 skipped |
| rtl | 5 passed, 4 skipped | 5 passed, 4 skipped |
| double | 3 passed, 6 skipped | 3 passed, 6 skipped |
| hebrew | 6 passed, 3 skipped | 6 passed, 3 skipped (rerun) |

The first Hebrew run on the Duo failed `testHebrewPhoneGetsHebrew`: it compared
tab positions side by side, but the Duo's side rail stacks the tabs. The test
now skips that comparison for a rail, as `testRightToLeftFlagMirrorsTheApp`
already did (that test passed on the Duo); the rerun with the fix passed.
The test fix is the only change after `3891a4b7`.

`CompanionUITests` + `LiveActivityUITests`: 15 of 17 passed in the combined run.
`testSettingsReturnKeepsCoachSendReachable` and
`testLargestTextGoalKeyboardDoneKeepsCoachSendReachable` could not find the
Goals row (Settings opened before the diary loaded). Run on their own, both
passed on this branch (2/2) and on `main` at `d2e7c49c` (2/2).

## Blocked or not run

- Lock Screen accessory widgets and the Control Center control: not captured;
  their text is in the checked catalogs.
- Running "Tell Coach" from the Simulator's Shortcuts app showed no reply; its
  Hebrew dialog text is covered by `HebrewSurfaceTextTests`.
- Spoken Siri in Hebrew, VoiceOver in Hebrew and Hebrew dictation on a real
  device: not checked.
- Users get Hebrew only with the next App Store version the owner submits; the
  1.2.0 build in review is unchanged.
