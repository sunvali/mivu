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
proof. English/Hebrew,44pt, VoiceOver/Dynamic Type/reduced motion. Photos retained
until explicit delete; private app-owned profiles. Input captured before analysis;
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

## Task1: Durable diary domain and business operations

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

- [ ] Add meaningful failing tests for capture-save failure, retry stableIDs,
review exclusion, revision guard/delete late result, photos retention/delete,
nullable sums, profile isolation, four-hour expiry/date rollover/DST/timezone,
weight/newday idempotence and history/completeness.
- [ ] Run isolated Foundation harness RED via XcodeBuildMCP swift-package test.
- [ ] Implement exact contract and tested minimal store/sample proposal worker.
- [ ] Run GREEN, copy owned sources after coordination; report hashes/evidence.
- [ ] Independent scoped review and original-worker fixes before integration.

## Task2: Complete native user flow

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

- [ ] Test UI composition state for save failure/review/cancel/background/profile
switching and same-meal correction before adding behavior.
- [ ] Implement native flow in staged owned files with clear errors and accessibility.
- [ ] Integrate agreed domain; native targeted tests, actual camera/library fallback.
- [ ] English/Hebrew/light/dark/large type render and core simulator interaction checks.
- [ ] Independent scoped review/fixes; aggregate UI smoke evidence and source hashes.

## Task3: Private backup/export/restore and deletion

Files: ios/Mivu/Diary/DiaryArchive.swift, FolderBackup.swift;
ios/MivuTests/ArchiveTests.swift; settings integration owned Task2 worker.
Consumes validated snapshot contract. Pure archive codec version1 owns photoData
and profileID/schema; excludes credentials. Restores transactionally after explicit
UI confirmation, validates complete archive before replacing. Delete/tombstone
policy rejects stale snapshots that contain locally tombstoned meals. Backup
folder bookmark lives outside exported diary; all work checks selected profile
and snapshot revision, with a serial writer and atomic destination replacement.
Use file coordination/security scoped resource and defer stopAccessing correctly.

- [ ] Failing fresh-store roundtrip photos/pending/revisions/owner tests, badversion,
truncated/oversized/invalid numeric/refID input, write-failure preservation,
older-backup resurrection, deletion propagation and profile switch races.
- [ ] Implement minimal codec/folder writer; native API wrapped only at actual boundary.
- [ ] GREEN isolated/native tests; integrate actual Files picker/export/import.
- [ ] Independently review data-loss/privacy paths and fix before acceptance.

## Task4: Real GitHub Actions CI/CD

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

- [ ] Validate actual runner availability and cost/allowance, no hidden paid run.
- [ ] Implement workflows and exact reproducible scripts; fail on zero tests.
- [ ] Run Actions on branch/PR and release rehearsal, inspect logs/artifacts.
- [ ] Independent workflow/security review; fix and rerun relevant failures.
- [ ] Document signing prerequisites and actual delivery artifacts, not just YAML.

## Task5: Final acceptance and delivery

Root coordinates integration only, delegates source fixes to original owner.
- [ ] Aggregate native suite and meaningful simulator UI journey: capture/text/photo,
review/directedit/halfcorrection/dayhistory/weight/profiles/settings/archive delete.
- [ ] Fresh-store acknowledged backup restoration including pending photos;
profile isolation and tombstone/no-resurrection verified.
- [ ] Inspect final rendered states, localization, DynamicType and accessibility.
- [ ] Independent whole-branch review and scoped fix review, no recurring full audits.
- [ ] Clean source commit and exact test/Actions evidence in docs/verification,
README/status accurate; focused PR attached, checks observed to completion.
- [ ] Release rehearsal creates downloadable verified artifacts. Signed Apple
external delivery remains explicitly incomplete if human/legal credentials are absent.
- [ ] Audit every MVP requirement and CI/CD outcome against authoritative evidence;
keep goal active if required outcome absent. No14-day pilot claim before14days.

## Execution authorization

Owner requested nonstop autonomous implementation overnight on2026-10-12,
retaining earlier Sol/Luna parallel delegation. This plan is reviewable now but
execution will not wait for feedback; reversible decisions are recorded in ledger.
