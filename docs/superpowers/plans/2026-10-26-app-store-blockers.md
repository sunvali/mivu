# App Store Blocker Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Enforce adult-only use, local-only health archives and private email reporting of Coach replies, then deliver a tested PR.
**Architecture:** Keep one per-profile adult eligibility rule at the store/runtime boundaries and reuse the current archive pipeline for app-owned local copies. Keep live data private in Application Support and keep Documents sharing disabled and return only portable files through an authenticated Shortcuts action. Use native MessageUI and an explicit copy fallback for reports.
**Tech Stack:** Swift 6, SwiftUI/UIKit, Foundation/SQLite, Swift Testing/XCTest, MessageUI; no new packages or services.
**Spec:** docs/superpowers/specs/2026-10-26-app-store-blockers-design.md

## Global Constraints

- 18+ only at launch; existing records remain readable/exportable/deletable.
- Local backups and exports now; Mivu-hosted cloud later, with no scaffolding here.
- Email reports to support@mivuapp.com, reviewed and sent by the user; no automatic transmission or delivery claims.
- Preserve ownership, epochs, revisions, tombstones, photos, credentials and pending work.
- English, Dynamic Type, VoiceOver, reduced motion and 44-point targets.
- Use focused tests and the 120-second UI smoke on a reserved simulator; no full suite or another worker's simulator.
- Refresh main; isolate changes; use Conventional Commits; no prohibited agent terms in PR/commit prose.

## Review Focus

- A profile switch while Mail/report/export is open must not reveal another profile's data (Task 3).
- A locked/background Siri request must not send or mutate gated profile data (Task 1).
- Two existing storage roots must not be merged or overwritten during migration (Task 2).
- Resumed legacy backup configuration must never write to an old external folder (Task 2).
- Copying, saving or cancelling a mail draft must never claim a submitted report (Task 3).

### Task 1: Adult eligibility across setup and runtime

**Files:** DiaryModels.swift, new AdultEligibility.swift/AdultEligibilityView.swift, DiaryStore.swift and mutation extensions, DiaryViewModel.swift, TodayView.swift, OnboardingView.swift/OnboardingTargets.swift, CoachViewModel.swift/CoachEngine.swift/TellCoachIntent.swift, directly affected fixtures/tests.
**Interfaces:** Produce `DiaryStore.confirmAdultEligibility(expectedProfileID:at:)`, `DiaryStore.requireAdultEligibility(expectedProfileID:)`, profile eligibility state and `DiaryViewModel` confirmation/gate state. Imports clear trusted confirmation without rejecting archive contents. Gate background capture/inference before requests or writes.
- [x] Add an assertion to OnboardingTargetsTests that a 13-year-old gets no computed targets; run that suite and observe the wrong adult target.
- [x] Add AdultEligibilityTests for age 17/18, birthday-year attestation, per-profile confirmation, legacy decode, imported confirmation, manual/Coach writes, and queued/background work preservation.
- [x] Implement shared checks and a native adult confirmation/restricted-read surface. Persist confirmation separately from portable archive trust. Keep existing adult formulas and manual target semantics.
- [x] Update explicit synthetic fixtures to confirm adults rather than hiding policy behind a general test bypass.
- [x] Run new/changed suites and directly affected onboarding/Coach/store callers; expect nonzero passing counts, zero failures.
- [x] Commit with `fix: enforce adult eligibility across diary flows`.

### Task 2: Local health storage, migration and archive destinations

**Files:** new LocalDiaryFiles.swift, DiaryLaunch/DiaryViewModel.swift, FolderBackup.swift, DiaryBackupSettings.swift, DiaryReportSettings.swift, DiaryReport.swift, other health-file owners, ios/Config/Info.plist, ArchiveTests and new LocalDiaryFilesTests.
**Interfaces:** Produce `LocalDiaryFiles` layout/migration/exclusion helpers, local archive destination and export-writing APIs. Consume Task 1 gate for read/export exception; do not gate recovery reads. Operational storage is private; Documents contains portable outputs only.
- [x] Add a failing test demonstrating that a user-selected external backup folder is accepted and written today; verify the test fails before changing destination handling.
- [x] Add tests for first launch, legacy migration, conflicting roots, photo roundtrip, exclusion after replacement, external destination refusal, failure preservation and deletion.
- [x] Implement app-owned local backup/export destinations and startup migration before any diary open. Disable legacy external writes without deleting external archives/bookmarks.
- [x] Replace generic save/share destinations for JSON/PDF/CSV with local export saves and Files/Finder instructions. Exclude health roots and replacements from backup; preserve file protection.
- [x] Run local-file/archive/export suites and directly affected profile/deletion tests; expect nonzero passing counts, zero failures.
- [x] Commit with `fix: keep health backups and exports on device`.

### Task 3: Private Coach reply reports and safety boundaries

**Files:** new CoachReplyReport.swift/CoachReplyReportView.swift, CoachView.swift, SettingsView.swift, OpenAIConsent.swift, CoachEngine.swift, new CoachReplyReportTests.swift and focused UI test, docs/development/coach-reports.md.
**Interfaces:** Produce a bounded `CoachReplyReport` payload from the selected reply/model/version only, reason enum and Mail-result wording; `CoachReplyReportView` owns review/composition/fallback. Consume captured owner/turn IDs and invalidate on profile changes.
- [x] Write payload/privacy/result tests first, then prove failure before implementing each nontrivial behavior.
- [x] Implement Report reply, reason/comment review, native Mail composer after canSendMail, explicit copy fallback and honest queued/cancel/failure wording.
- [x] Add Settings support contact and concise Coach safety boundaries; record inbox response obligations without inventing operational proof.
- [x] Test no prompt/history/photos/profile/token leakage, stale owner invalidation, cancelled/draft/queued states, copy-not-sent fallback and safety instructions.
- [x] Run focused reporting/safety and changed Coach reply suites; expect nonzero passing counts, zero failures.
- [x] Commit with `feat: add private Coach reply reporting`.

### Task 4: Integration, review and PR

**Files:** focused AppStoreSafetyUITests, affected SmokeUITests fixtures, submission/listing/development docs and docs/verification/2026-10-26-app-store-blockers.md.
**Interfaces:** Consume Tasks 1-3. Record exact source SHA, named counts, simulator, result bundles and remaining device/provider/submission gates.
- [ ] Verify age gate, local export and report fallback UI with synthetic fixtures; run required `python3 scripts/ci/smoke.py --simulator-id <reserved UUID>` (120-second cap).
- [ ] Run the directly affected unit suites together, project script checks and whitespace validation; keep native checks separate from Linux hosted checks.
- [ ] Run Ponytail Review as an independent whole-change pass with callers/tests and assumed single-device load. Fix blocking findings and verify affected tests.
- [ ] Update submission guidance and evidence; preserve the nuanced iCloud research conclusion and future cloud deferral.
- [ ] Commit, push the feature branch, open a PR with actual verification and limitations, attach it to this chat and inspect required hosted checks. No merge or public release.
