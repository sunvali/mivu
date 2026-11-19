# Update prompts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show calm update prompts in Mivu: an update card on Today, an update row in Settings, an emergency block driven by a minimum version on the website, and a one-time Pip "What's New" card.

**Architecture:** One `@Observable` `AppUpdate` owns the version checks and the stored state; one `WhatsNew` struct owns the bundled highlights. Views only read them. The block is an overlay on `DiaryRootView`, so the diary still loads underneath and export works.

**Tech Stack:** SwiftUI, URLSession, Swift Testing, XCTest UI tests, String Catalog.

**Spec:** `docs/superpowers/specs/2026-11-19-update-prompts-design.md`

## Global Constraints

- App Store ID `6826633410`. Lookup URL `https://itunes.apple.com/lookup?id=6826633410`. Config URL `https://mivuapp.com/app-config.json`, format `{"ios":"x.y.z","android":"x.y.z"}`.
- Card shows only when `currentVersionReleaseDate` is at least 7 days old. It shows once per version and once more 7 days after the first dismiss.
- Fail open: a failed or invalid config fetch keeps the last stored minimum.
- Checks are skipped in UI tests and sample mode, and run at most once an hour. Requests carry no IDs.
- State lives in `DiaryLaunch.defaults`. Versions are compared with `compare(_:options: .numeric)`.
- Priority on Today: morning check-in, then What's New, then the update card.
- Every new string is translated in `ios/Mivu/Localizable.xcstrings` (en, es, ru, he). Touch targets are at least 44 pt. Pip art is hidden from VoiceOver.

## Review Focus

- Config returns 404 or HTML (captive Wi-Fi): the minimum is unchanged and there is no block. Test: `configFailureKeepsLastMinimum`.
- The minimum is lowered after a block: the block lifts on the next check. Test: `lowerMinimumUnblocks`.
- The App Store lags behind the installed version (TestFlight or a fresh release): no card, because only a newer version counts. Test: `olderStoreVersionShowsNothing`.
- First run of this feature, or a new install: no What's New. Test: `firstRunRecordsWithoutShowing`.
- Malformed lookup JSON or an empty `results`: no card and no crash. Test: `malformedLookupShowsNothing`.

---

### Task 1: `AppUpdate` and `WhatsNew` logic

**Files:**
- Create: `ios/Mivu/Diary/AppUpdate.swift`
- Modify: `ios/Mivu/Connection/OpenAIConsent.swift` (add `MivuLinks.appStore = https://apps.apple.com/app/id6826633410`)
- Test: `ios/MivuTests/AppUpdateTests.swift` (Swift Testing, with a private `URLProtocol` stub as in `FeedbackTests`)

**Interfaces (produces):**
- `@MainActor @Observable final class AppUpdate { static let shared; init(defaults: UserDefaults, version: String, session: URLSession = .shared) }`
- `private(set) var available: String?` holds the newer store version, set only when it is 7 or more days old.
- `var isBlocked: Bool`: `version` is below the stored `appMinimumVersion`.
- `func check(now: Date = Date()) async` fetches both URLs, throttled to once an hour. It sets `available` and stores the minimum only from a 200 response with valid JSON.
- `func showsCard(now: Date = Date()) -> Bool` and `func dismissCard(now: Date = Date())` use the keys `updateCardVersion`, `updateCardDismissedAt` and `updateCardDismissals`.
- `struct WhatsNew { static let notes: [String: [LocalizedStringResource]]` is empty for now. It has `init(defaults:version:notes:)`, `func recordLaunch()`, `var pending: [LocalizedStringResource]?` and `func markSeen()`, using the keys `lastRunVersion` and `whatsNewVersion`.
- In DEBUG UI tests the flags are `--update-available-fixture` (available `"99.0"`), `--update-required-fixture` (blocked) and `--whats-new-fixture` (pending, with two fixture lines). Read them in `AppUpdate.shared` and `WhatsNew` setup.

- [ ] **Step 1: Write failing tests:**
  - `newerStoreVersionAfterSevenDaysIsAvailable`: store 1.9.0 released 8 days ago, app 1.8.0, so `available == "1.9.0"`. Released 6 days ago gives nil.
  - `olderStoreVersionShowsNothing`
  - `malformedLookupShowsNothing`
  - `cardReturnsOnceAWeekAfterDismiss`: shows; after the first dismiss it is hidden at 6 days, shows at 7, and stays hidden after the second dismiss.
  - `newVersionResetsCard`
  - `minimumAboveVersionBlocks`
  - `configFailureKeepsLastMinimum` (404 and failed connection)
  - `lowerMinimumUnblocks`
  - `numericCompare`: 1.10.0 is newer than 1.9.0.
  - `firstRunRecordsWithoutShowing`
  - `updateWithNotesShowsOnceUntilSeen`
  - `updateWithoutNotesShowsNothing`
- [ ] **Step 2:** Run `MivuTests/AppUpdateTests` with XcodeBuildMCP. Expected: compile failure.
- [ ] **Step 3:** Implement `AppUpdate.swift`. Decode the lookup with `JSONDecoder` and `.iso8601` dates into `results.first.version` and `currentVersionReleaseDate`.
- [ ] **Step 4:** Run the tests. Expected: all pass.
- [ ] **Step 5:** Commit `feat(update): version checks and what's new state`.

### Task 2: Today cards, Settings row, emergency block

**Files:**
- Create: `ios/Mivu/Diary/UpdateViews.swift` (`UpdateCard`, `WhatsNewCard`, `UpdateRequiredView`)
- Modify: `ios/Mivu/Diary/TodayView.swift`:
  - `leadingSections` (~L717): priority chain, with What's New before the summary section and the update card after it
  - `DiaryRootView.body` (~L169): `.overlay { if blocked { UpdateRequiredView } }`, with `lifecycleView.accessibilityHidden(blocked)`
  - when the block appears, clear `routes.route`, `coachHistory`, `noteMealID` and `quickLogOwner`; `openQuickLog` returns early while blocked
  - run `check()` and `recordLaunch()` in the launch task and when the scene becomes active
- Modify: `ios/Mivu/Diary/SettingsView.swift`. In Support, before Send feedback, add a `Link(destination: MivuLinks.appStore)` row: "Update available", symbol `arrow.down.circle`, value = version, id `updateAvailable`.
- Modify: `ios/Mivu/Diary/DiaryBackupSettings.swift`. Extract the export button, its state, the `.fileExporter` and the "Export saved" label into `struct DiaryExportButton: View { model; title: LocalizedStringKey }`. The Settings behaviour stays the same.
- Modify: `ios/Mivu/Localizable.xcstrings`. Add es, ru and he for every new string.
- Test: `ios/MivuUITests/UpdatePromptUITests.swift`

**Copy (exact, from the approved mockups):**
- Card:
  - "Mivu \(version) is available"
  - "A newer version is ready in the App Store." (the mockup's feature line comes from the release, so a generic line is used here)
  - button "Update in App Store"
  - dismiss label "Hide update"
- Block:
  - "Please update Mivu"
  - "This version of Mivu needs an update to keep working. Your diary stays on this iPhone."
  - "Update in App Store"
  - "Export my diary"
  - "Saves a copy to Files"
- What's New:
  - "New in Mivu \(version)"
  - "Got it"

**Look:**
- The update card uses `diarySummaryCard()` with an 8% accent tint and a small bordered accent button at least 44 pt tall.
- The What's New card uses `Image("PipResting")` at 56 pt (hidden from VoiceOver), with SF Symbol `sparkle` bullets.
- The block uses `PipResting` at 112 pt, a scroll view for the content, and buttons pinned at the bottom.

- [ ] **Step 1: Write the failing UI tests** (launch args `--diary-ui-test <uuid> --proof-english` plus the fixture flag):
  - `testUpdateCardDismisses`: `updateCard` exists below the intake card, tapping `updateCardDismiss` hides it, and it stays hidden after relaunch with the same uuid.
  - `testSettingsShowsUpdateRow`: the `updateAvailable` row exists.
  - `testRequiredUpdateBlocksAndOffersExport`: `updateRequired`, `updateRequiredStore` and `updateRequiredExport` exist; `profileSettings` is not hittable.
  - `testWhatsNewShowsUntilGotIt`: `whatsNewCard` exists; after `whatsNewDone` it is gone.
- [ ] **Step 2:** Run them with XcodeBuildMCP. Expected: they fail.
- [ ] **Step 3:** Implement the views and the wiring above.
- [ ] **Step 4:** Run the UI tests, `AppUpdateTests` and `FeedbackUITests` (to cover the Settings regression). Expected: pass. Take screenshots of all three surfaces in light, dark and `--proof-largest-text` for the UX reviewer.
- [ ] **Step 5:** Commit `feat(update): update card, settings row and required-update screen`.

### Task 3: Docs and site file

**Files:**
- Modify: `docs/development/app-store-submission.md`. Change "decided, not built yet" to built, and add "Raising the minimum":
  1. Confirm the fixed version is live everywhere.
  2. Edit `mivu-site/public/app-config.json`.
  3. Run `aws sts get-caller-identity --profile mivu` and check the account is 582169340364.
  4. Run `mivu-site/deploy.sh`.
  5. Open the URL and check the value.
  Also add "write What's New highlights in `WhatsNew.notes` for feature releases".
- In the separate repo `mivu-site` (own branch and PR): create `public/app-config.json` with `{"ios":"1.0.0","android":"1.0.0"}`, and add one line to the privacy page saying Mivu checks Apple's App Store and mivuapp.com for newer versions and sends no personal data. Do not deploy; the owner deploys.

- [ ] **Step 1:** Make the edits and commit `docs(release): update prompts and minimum-version steps`.
- [ ] **Step 2:** Make the site branch, commit and open the PR.
