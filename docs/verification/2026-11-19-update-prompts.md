# Update prompts

Plan: [2026-11-19-update-prompts.md](../superpowers/plans/2026-11-19-update-prompts.md).
Spec: [2026-11-19-update-prompts-design.md](../superpowers/specs/2026-11-19-update-prompts-design.md).
Branch `feat/update-prompts`, from `main` at `7d94c658`.

## What changed

- **Version checks.** `AppUpdate` reads the App Store lookup and
  `https://mivuapp.com/app-config.json` at launch and on return to the app, at
  most once an hour. UI tests and sample mode skip both. Neither request
  carries anything about the person.
- **Update card on Today.** It sits below the intake card and appears once a
  newer App Store version has been out for 7 days. It shows once per version,
  then once more a week after it was dismissed.
- **Settings row.** Support › Update available opens the App Store.
- **Required update.** When the website's iOS minimum is above this version, a
  full-screen view covers the app with Update in App Store and Export my diary.
  The export reuses the Settings export, now `DiaryExportButton`. A failed
  fetch keeps the last minimum.
- **What's New.** Pip's card shows bundled highlights once, after an update
  into a version that has highlights. The table is empty in this change.
- **Today shows one prompt at a time:** the morning check-in first, then
  What's New, then the update card.
- New strings have Spanish, Russian and Hebrew in the catalog;
  `languages.py check` passes.

## Evidence

Source SHA `40da790471058ceedb28e27b8b7d5f4326ec1021`. Xcode 27.2, iPhone 17
Pro simulator on iOS 27.0 (`Mivu update-prompts`), test plan `Mivu`, run with
xcodebuildmcp.

Focused run: 23 passed, 0 failed, 0 skipped.

- `AppUpdateTests` (14)
- `RatingPromptTests`
- `UpdatePromptUITests` (5): `testUpdateCardDismisses`,
  `testSettingsShowsUpdateRow`, `testRequiredUpdateBlocksAndOffersExport`,
  `testBlockOnReturnClosesOpenSheets`, `testWhatsNewShowsUntilGotIt`
- `FeedbackUITests` (the Settings Support section)
- `DiaryUITests/testNewDayShowsMorningCheckInThatNeverBlocksLogging`

Screenshots of the card, block and What's New in light, dark and the largest
text were reviewed by the UX reviewer. Its fixes were applied: readable button
text in dark mode, a scrolling block at the largest text, a prominent Got it
button, and Pip hidden at accessibility sizes.

A whole-branch code review found two Important issues, and both are fixed with
tests that failed first:

- Sheets left open stayed above the block. The block now closes them, and
  notifications, Coach requests and plan notices wait while blocked
  (`testBlockOnReturnClosesOpenSheets`).
- The hourly limit kept a blocked person waiting after the minimum was lowered.
  A blocked app now checks on every return (`blockedChecksIgnoreTheHourlyLimit`).

## Not verified

- A live App Store release behind the lookup. Fixtures stand in for it.
- The full native UI suite. Only the focused tests above ran.
- A physical phone.
- The site file `app-config.json` is not deployed yet. Until it is, the fetch
  fails and the app fails open.
