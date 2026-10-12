# Native diary MVP implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the full native Mivu MVP using labeled apple sample analysis,
with verified GitHub Actions CI/CD and portable private backup recovery.
**Architecture:** Foundation-only Codable domain and one protected atomic diary
store per profile; a small MainActor screen model drives native SwiftUI capture,
correction, history and settings. A versioned analysis proposal operation is
separate from totals/revisions. Files-folder backup uses owned archive snapshots.
**Tech Stack:** Swift6, SwiftUI, Foundation, PhotosUI/UIKit camera, Swift Testing,
existing singleJOSESwift dependency, GitHub Actions and XcodeBuildMCP locally.
**Spec:** docs/superpowers/specs/2026-10-12-sample-mvp-addendum.md plus the accepted
2026-10-11-food-logger-design.md.

## Global constraints

Native iPhone/iOS26+, no server or paid services. Preserve existing connection
proof. English-only MVP acceptance; disable the Hebrew selector and preserve
existing profile/archive records and stored language values. Hebrew RTL is not
required for MVP acceptance. 44pt, VoiceOver/Dynamic Type/reduced motion.
Premium native glass and cheerful food palette follow
design-system/mivu/MASTER.md. Photos retained until explicit delete; private
app-owned profiles. Input captured before analysis;
all synthetic nutrition labeled. No credentials/logged personal contents in
archives, tests, artifacts or Actions output. Never mention prohibited workflow
branding in commits/PRs. Branch feature/native-diary-mvp; no direct main push.
Owner requested overnight continuous parallel Sol features/Luna routine work;
this explicitly overrides new-spec/plan approval waits and sequential workers.

## Review focus

1. Persist failure must keep composer/input; no false saved/backup success.
2. Deleted or corrected meals cannot be resurrected by a delayed result.
3.04:00/DST/timezone changes cannot silently start/move a waking day.
4. Switching profile cannot reveal records or dispatch another profile's work.
5. Failed/older backup restore cannot erase current records or tombstones.

## Task 1: Durable diary domain and business operations

Files: ios/Mivu/Diary/DiaryModels.swift, DiaryStore.swift, SampleAnalyzer.swift;
ios/MivuTests/DiaryTests.swift and DayTests.swift. No UI/project edits.
Foundation-only, no generic repositories. Atomic protected per-owner JSON files
include photo bytes; write-first transactions update in-memory snapshots only
on success. Explicit schema/version validation and reasonable input bounds.

Public contract to coordinate before UI implementation:
`DiaryProfile`(id UUID,name String,language String,timeZoneID String,preferences String);
`DiarySnapshot`(profile,days [TrackingDay],meals [DiaryMeal],weights [WeightEntry],
activeDayID UUID?,previousDayConfirmedAt Date?,deletedMealIDs [UUID]);
`TrackingDay`(id,localDate String,timeZoneID,startAt Date,completeness enum);
`DiaryMeal`(id,dayID,capturedAt,eatenAt,revision Int,items [FoodItem],
photos [MealPhoto],submissions [MealSubmission]); nullable kcal/carbs/protein/fat.
`MealPhoto`(id,data Data,createdAt,role before/after/unspecified);
`MealSubmission`(id,baseRevision,text,photoIDs,reviewFirst,state,proposal?).
`SampleAnalyzer` outputs one apple estimate and supports explicit quantity/half
correction against current values without applying half twice on retry.
Actor `DiaryStore(directory:)` offers profile listing/create/select snapshot,
startDay,dayAssignment(at:) -> existing/new/ask,confirmPreviousDay,
capture(text:photos:reviewFirst:dayID:at:submissionID:), processPending,
acceptReview,editItem,correctMeal,addPhotos,deletePhoto,deleteMeal,moveMeal,
setCompleteness,recordWeight,updateProfile,deleteProfile and snapshot export/restore.
Finalize exact signatures with controller before other workers consume them.

- [x] Add meaningful failing tests for capture-save failure, retry stableIDs,
review exclusion, revision guard/delete late result, photos retention/delete,
nullable sums, profile isolation, four-hour expiry/date rollover/DST/timezone,
weight/newday idempotence and history/completeness.
- [x] Run isolated Foundation harness RED via XcodeBuildMCP swift-package test.
- [x] Implement exact contract and tested minimal store/sample proposal worker.
- [x] Run GREEN, copy owned sources after coordination; report hashes/evidence.
- [x] Independent scoped review and original-worker fixes before integration.

## Task 2: Complete native user flow

Files: ios/Mivu/Diary/DiaryViewModel.swift, TodayView.swift, MealComposerView.swift,
MealDetailView.swift, HistoryView.swift, SettingsView.swift, DiaryStyle.swift,
PhotoCapture.swift, Localizable.xcstrings,MivuApp.swift; ios/MivuTests/DiaryFlowTests.swift.
Consume Task1 agreed contract, no domain edits without coordination. Initial
work can stage native views while domain contract is finalized. Native composer
PhotosPicker and UIImagePickerController camera with real permissions/denial
states; clamp/import JPEG bytes to bounded size and discard location metadata.
Today opens on launch: sample mode, totals/pending, startday/weight, recentmeals,
fast capture. Send only closes after local acknowledgement; worker runs separately
and cancels safely/background resume. Ambiguous day sheet prior/new; per-meal
review accept/edit/correct/addphotos/delete/move all target same stableID.
History completeness/weight/coverage. Settings local profiles/signout, language,
timezone/preferences, connection diagnostic, archive controls. Backups connected
through Task3 interfaces after Task1 completion; no invented success state.

- [x] Add focused failing UI tests for save/review/cancel/profile state before
implementing the native flow; the reports record the RED and GREEN iterations.
- [x] Implement Today, sample capture/review, same-meal correction, history,
profiles/settings and durable capture integration in native SwiftUI.
- [x] Pass the native core journey for capture, review, half correction, item
edit, weight, history, cancellation and profile isolation. PR #3 and main report
199 passed, 0 failed, 1 skipped; English-focused suite reports 10/10 passed.
- [x] Render and inspect English light, dark, accessibility-3 and
accessibility-5 states; the focused accessibility-5/photo UI run passed 2/2 and
Log meal was hittable. Root inspected the dark accessibility-5 screenshot:
English LTR, wrapping labels, no permanent horizontal clipping, and scrollable
below-fold content in the native list.
- [ ] Complete the full VoiceOver audit; physical-device accessibility remains
unverified.
- [x] Complete the Task 2 scoped review and fixes; PR #3 merged after whole-branch
review. See the delivery record in docs/development/ci-cd.md.
- [ ] Verify physical camera behavior and hardware-only accessibility/haptics.

## Task 3: Private backup/export/restore and deletion

Files: ios/Mivu/Diary/DiaryArchive.swift, FolderBackup.swift;
ios/MivuTests/ArchiveTests.swift; settings integration owned Task2 worker.
Consumes validated snapshot contract. Pure archive codec version1 owns photoData
and profileID/schema; excludes credentials. Restores transactionally after explicit
UI confirmation, validates complete archive before replacing. Delete/tombstone
policy rejects stale snapshots that contain locally tombstoned meals. Backup
folder bookmark lives outside exported diary; all work checks selected profile
and snapshot revision, with a serial writer and atomic destination replacement.
Use file coordination/security scoped resource and defer stopAccessing correctly.

- [x] Add focused archive tests and pass archive photo/pending/revision roundtrip,
acknowledged deletion propagation, configured-folder history and stale-restore
rejection (`archiveRoundTripRetainsPhotoPendingAndRevision`,
`acknowledgedMutationsAutomaticallyReachBackupIncludingDeletion`,
`configuredFolderHistoryReceivesPhotoMealAndProfileDeletion`,
`deleteRejectsLateResultAndOlderRestore`).
- [x] Implement the versioned archive, folder writer and native export/restore
controls; complete independent scoped review and its recovery/privacy fixes.
- [ ] Exercise actual Files folder selection/write/status, export/import and fresh
profile restore including photos. This provider journey is pending while it is
being exercised; automated archive tests are not a substitute.

## Task 4: Real GitHub Actions CI/CD

Files:.github/workflows/ci.yml,.github/workflows/release.yml,scripts/ci/*,
docs/development/ci-cd.md. No app-code edits. Read authoritative current runner,
action and Apple signing docs. Pin third-party actions to verified commits;
minimal permissions, concurrency, fork/secret isolation and artifact retention.
Check Actions allowance/spending configuration without enabling billing. PR/main
CI builds+tests iOS26-or-newer simulator; captures meaningful named Swift Testing
counts and xcresult, builds native app. Release tag/manual workflow builds same
source, verifies tests and publishes app+unsigned archive with honest labeling.
A separately gated signed lane exportsIPA/uploadsTestFlight only with required
owner secrets/certificates/team IDs, no fake signing or paid enrollment.

- [x] Validate actual runner availability and cost/allowance, no hidden paid run.
- [x] Implement workflows and exact reproducible scripts; fail on zero tests.
- [x] PR #3 and main Actions runs completed successfully with named native test
reports and simulator artifacts; see docs/development/ci-cd.md.
- [x] Initial `v1.0.0-rehearsal.1` completed and produced a private draft with
five digest-validated assets.
- [x] Workflow/security review fixes were completed before PR #3 merged.
- [ ] Run a final release rehearsal after the last native source change, then
record its exact run and draft-release evidence.
- [x] Signing prerequisites and the observed unsigned artifact limits are
documented; signed delivery remains blocked on owner-provided Apple credentials.

## Task 5: Final acceptance and delivery

Root coordinates integration only, delegates source fixes to original owner.
- [x] Aggregate hosted native test suite: main source `9f02a1568701f62a2afd482bf02fc5ed9d9f30bb`,
199 passed, 0 failed, 1 skipped. Interactive end-to-end and Files provider
acceptance remain open.
- [x] Final local aggregate on the uncommitted native UI working tree: 200 passed,
0 failed, 1 skipped, exit 0 in 109.4s; xcresult is recorded in
docs/development/ci-cd.md. It ran at HEAD `251aafce…` plus local `DiaryStyle.swift`
and `DiaryUITests.swift` changes; HEAD alone does not identify this tested source.
- [ ] Fresh Files-folder backup write and restore to a fresh profile, including
photos and pending records; profile isolation and stale-delete protection remain
under automated coverage, while the actual provider journey is pending.
- [x] Inspect English light, dark, accessibility-3 and accessibility-5 renders.
- [ ] Complete the full VoiceOver audit; hardware accessibility checks remain open.
- [ ] Verify physical-camera and haptics behavior on hardware.
- [x] Complete independent whole-branch review and scoped source fixes before PR #3
merged.
- [x] PR #3 merged and main CI passed; verification details are in
docs/development/ci-cd.md.
- [ ] Complete the final release rehearsal after any last native UI fix.
- [x] Initial private draft release rehearsal produced five validated assets.
Signed Apple delivery remains NOT_RUN_BLOCKED with required credentials absent.
- [ ] Merge the remaining native UI/Files changes, run the final release rehearsal
against that immutable source, then update the verification matrix in a docs-only
follow-up tied to the same run. Reconcile remaining acceptance rows against that
source. No 14-day pilot claim before 14 days of evidence.

## Execution authorization

Owner requested nonstop autonomous implementation overnight on2026-10-12,
retaining earlier Sol/Luna parallel delegation. This plan is reviewable now but
execution will not wait for feedback; reversible decisions are recorded in ledger.
