# Coach Chat History and Camera Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Coach a smooth, continuous, genuinely paged conversation with direct camera capture, reliable historical navigation and trustworthy dated receipts.

**Architecture:** Keep profile-local SQLite and DiaryStore as the sole live writer. Introduce indexed metadata, explicit screen projections and targeted transactions before activating a coordinated storage cutover; render a bounded, anchored timeline independently of worker context. Reuse existing diary rules, analysis, photo normalization, native editors, Precision Glass and painted Lottie Pip.

**Tech Stack:** Swift 6, iOS 26+, SwiftUI, SQLite3, AVFoundation, PhotosPicker, existing Lottie runtime, Swift Testing/XCTest, XcodeBuildMCP. No new dependency or hosted service.

**Spec:** [Approved design](../specs/2026-10-18-coach-chat-history-design.md). Read it with this plan; its examples and acceptance table remain requirements.

## Global Constraints

- One continuous conversation per private profile; dividers follow committed waking/tracking-day recognition, not a separate midnight timer.
- Latest/adjacent/seek pages contain at most **20 exchanges**; history previews contain **30 days**. Resident and reserved/prefetched pages together contain at most **100 exchanges / five pages**.
- Thumbnail cache: **16 MiB decoded cost**; **two concurrent decode/import jobs**. Draft: **eight attachments**. Preserve profile limit **350,000,000 bytes**, **250,000,000 original-photo bytes**, **10,000,000 bytes per stored photo**, **10,000 turns**, and the remaining existing row/import/vision limits.
- Capture time, timezone, active day and operation identity are durable before inference. History position never assigns a new message's date. Keep current explicit day-choice behavior.
- Normal startup, profile listing/selection, refresh, capture, mutations and worker paths must not read/reconcile a complete snapshot. A projection is never a partial DiarySnapshot.
- Complete snapshots are explicit archive/import/backup operations only. Preserve schema 1 snapshots, archive envelope 3, and decoding of envelopes 1/2/3.
- Keep revision/lineage, epoch, ownership, file replacement, tombstone, idempotency and backup acknowledgement protections. Never delete an unloaded row.
- Native English MVP; semantic light/dark colors, Dynamic Type, VoiceOver, Reduce Motion and minimum **44-point** targets. No new Pip assets or animation timing changes.
- Hardware targets after migration: cold usable latest page **≤2 s**, warm reopen **≤500 ms**, edge fetch/application **p95 ≤200 ms**, prepend displacement **≤2 pt**. These are gates to measure, not claims already proved.
- Use rtk for verbose commands and XcodeBuildMCP for all native jobs. Native jobs run serially. Preserve hooks and private delivery rules; no new hosted native jobs, billing, release or public upload.

## Review Focus

1. DST/travel/backward clock/equal timestamps: immutable append order and captured relative-date meaning survive retries (Tasks 1, 2, 3, 6).
2. Colliding photo UUIDs across parents/profiles and late callbacks after restore: exact ownership and content identity prevent wrong images or attachments (Tasks 1, 4, 9, 10).
3. Overlapping edge requests, eviction, profile change and background replies: reservations stay bounded and the visible/focused exchange stays anchored (Tasks 11, 12, 13).
4. Export during writes/deletion/file replacement: consistent data may be exported, but obsolete work cannot acknowledge or resurrect a profile (Tasks 7, 8).
5. Disk/quota failures and replay after deletion: migration and mixed writes are atomic; old retries cannot restore removed records (Tasks 1, 3, 4, 5).

---

## Execution and integration order

The owner selected subagent-driven work. Use fresh implementer/reviewer contexts with file ownership per task; use 6.1-sol for storage, concurrency, camera and scrolling, and Luna for bounded fixture/documentation work. Review specification compliance and code quality for each task, then review the entire branch. Root integrates shared-file changes and owns all native job scheduling.

Work in the existing attached checkout `/private/tmp/mivu-local-hooks`, branch `codex/coach-chat-design`, starting from `ae54546163f7fd17e67a8451cca79863e07f19ad` plus this plan commit. Recheck status/remotes before execution; preserve newer work. Do not create competing checkouts or silently reset the branch.

Dependency order:

```text
1 → 2 → 3 → 4 → 5 → 6 → 7 → 8  (storage and production cutover)
1 → 9 → 10                       (photo/camera components)
2 → 11                           (pure timeline components)
8 + 9 + 10 + 11 → 12 → 13 → 14 → 15
```

Tasks 9–11 can overlap the storage track after their dependencies and shared types are committed. Their components remain unwired until Task 12. Never run two writers against shared files or two native jobs. Commit each reviewed task; push at integration milestones with normal hooks. Intermediate storage commits are not deployment candidates.

### Storage activation boundary

Task 1 exposes migration explicitly for fixture/component tests; it does **not** automatically migrate shipping profiles. Tasks 2–7 implement and test the new architecture against those migrated databases. Task 8 activates migration, replaces ordinary snapshot readers/writers and applies a database-version fence **in one integration commit**. Once storage version 1 is active, the legacy `write(snapshot, expected:, maximumBytes:)` must refuse it. Explicit full-profile creation/replacement remains available for imports/restores. Do not ship a feature flag permitting both writer architectures on the same profile.

## File responsibilities

Paths below are relative to the checkout. Modify existing types instead of making parallel owners.

| Files | Responsibility / task owner |
|---|---|
| `ios/Mivu/Diary/DiaryReadModels.swift` (new) | Photo-free head/current-day/day-detail/meal/progress projections, invalidations; 1/4/5 |
| `ios/Mivu/Coach/CoachTimelineModels.swift` (new) | Identity, cursors, pages, seek/navigation contracts, typed receipts; 1/2 |
| `ios/Mivu/Diary/DiaryDatabaseMigration.swift` (new), `DiaryDatabase.swift` | Storage version, derived indexes, query diagnostics, transaction primitives; 1/3 |
| `ios/Mivu/Diary/DiaryDatabaseQueries.swift` (new) | Indexed projections, paging, worker/context/grounded reads; 2/4/6 |
| `ios/Mivu/Diary/DiaryDatabaseMutations.swift` (new) | Targeted validated row operations and atomic mixed batches; 3/4/5 |
| `ios/Mivu/Diary/DiaryStore.swift` | Sole live writer, selected head/epoch, production API cutover; 3–8 |
| `ios/Mivu/Diary/DiaryExportCoordinator.swift` (new), `DiaryArchive.swift`, `FolderBackup.swift`, `DiaryBackupSettings.swift` | Consistent complete clone/export, replacement and acknowledgement fences; 7 |
| `ios/Mivu/Diary/DiaryViewModel.swift`, `TodayView.swift`, `HistoryView.swift`, `MealDetailView.swift`, `MealComposerView.swift`, `SettingsView.swift`; `ios/Mivu/Progress/{ProgressAnalytics,ProgressEditorViews,ProgressView}.swift` | Current-screen projections, on-demand detail, date/source routes; 8/13 |
| `ios/Mivu/Coach/{CoachViewModel,CoachEngine,CoachTools,CoachManualEdits}.swift` | Capture/worker/read/write caller migration; 5/6/8 |
| `ios/Mivu/Diary/DiaryPhotoLoader.swift`, `PhotoPreparation.swift` (new) | Owned lazy thumbnails; extract existing PhotoPreparation from DiaryViewModel; 9/10 |
| `ios/Mivu/Coach/{CoachCameraView,CoachCameraSession,CoachAttachmentDraft}.swift` (new); `ios/Mivu/Diary/PhotoCapture.swift` | Camera lifecycle, picker, bounded draft; 10 |
| `ios/Mivu/Coach/CoachHistoryWindow.swift`, `CoachTimelineViewModel.swift` (new) | Pure bounded window and asynchronous paging orchestration; 11 |
| `ios/Mivu/Coach/{CoachView,CoachActivityView}.swift`, `CoachTimelineView.swift`, `CoachReceiptView.swift`, `CoachHistoryView.swift` (new) | Virtualized rows, receipts, history sheet; 12/13 |
| `ios/Mivu/Design/CompanionRuntime.swift` | Preserve feedback identity/lifecycle through projected data; 8/14 |
| `ios/MivuTests/ChatHistoryFixture.swift` (new) | Synthetic valid small/large profiles and bounded query diagnostics; 1, extended by owning tests |
| `ios/MivuTests/*Tests.swift`, `ios/MivuUITests/*Tests.swift` | Named focused tests in each task below; existing regressions retained |
| `docs/development/coach-chat-behavior.md`, `docs/verification/2026-10-18-coach-chat-history.md` (new evidence file) | Final contracts, reproducible fixtures and measured/blocked acceptance; 15 |

### Shared contracts to freeze in Task 1

All values crossing actors are Sendable; UI orchestration is MainActor. Do not make SQLite handles or camera sessions unchecked Sendable to satisfy the compiler.

- `DiaryHead`: profile, revision, lineage, activeDayID, timelineGeneration. Selected store state holds this head and its existing selection epoch, not a full graph.
- `CoachTimelineIdentity`: profileID + timelineGeneration. `CoachCursor`: identity + immutable Int64 sequence + turnID. Reject mismatched identity before reading.
- `DiaryPhotoOwner`: `.meal(UUID)` / `.coachTurn(UUID)`. `DiaryPhotoReference`: profileID, owner, photoID, createdAt, role, persisted UUID `contentToken`. Physical composite photo IDs remain unchanged.
- `MealReadModel`: record identity/day/times/revision, committed items, required submission state, photo references, optional sourceTurnID; preserve existing pure totals/review rules. `DiaryReadModel`: head, active day/previous-day confirmation, active-day meals/weight/workouts, active goal and pending-analysis count. `DiaryDayReadModel` is one requested day; progress/history use bounded range/summary reads. No `[MealPhoto]` with empty Data pretending to be complete content.
- `DiaryChanges`: changed day/meal/turn/weight/workout ID sets plus profile/timeline reset indication. `DiaryCommit<Value: Sendable>`: value, committed head, changes. Existing public mutation returns may remain unchanged; publish this internal result after commit.
- `CoachExchangeSummary`: stable ID/sequence, capturedAt/timeZoneID, captured conversation-day/segment identity, text, reply, typed work state, photo references, typed committed receipts. No image bytes or view-parsed resultJSON.
- `CoachPageRequest`: `.latest`, `.before(CoachCursor)`, `.after(CoachCursor)`, `.aroundTurn(UUID)`, `.atDay(UUID)`. `CoachPage`: identity, ascending exchanges, exclusive before/after cursors, hasEarlier/hasLater and boundary-neighbor segment metadata. Distinguish no-chat/missing-target from an empty successful latest page using typed query errors/results.
- `CoachDayCursor`: identity + last segment sequence + stable segment ID; `CoachDayPage`: at most 30 date/preview/target rows, cursor and hasMore. A stable segment ID survives repeated labels; opening a day resolves its first exchange.
- `CoachSeekTarget`: `.day(UUID)` / `.turn(UUID)`. `CoachNavigationRequest`: profileID, target, requestID. No implicit profile switching.

### Focused test commands

At execution, inspect `xcodebuildmcp simulator test --help`, available simulators and existing hook recipe. Select an available iOS 26+ iPhone explicitly. The currently observed candidate is `42CE2315-9339-4EF1-A5B4-064444D0FA44` (iPhone 17 Pro, iOS 26.5); availability is not permanent. Use this shell helper from the checkout, replacing the ID when necessary:

```sh
export MIVU_PLAN_SIMULATOR_ID=42CE2315-9339-4EF1-A5B4-064444D0FA44
mivu_test() {
  local mivu_test_json
  mivu_test_json=$(python3 - "$@" <<'PY'
import json, os, sys
print(json.dumps({
    "projectPath": os.path.join(os.getcwd(), "ios/Mivu.xcodeproj"),
    "scheme": "Mivu", "configuration": "Debug",
    "simulatorId": os.environ["MIVU_PLAN_SIMULATOR_ID"],
    "derivedDataPath": "/private/tmp/mivu-chat-derived",
    "extraArgs": ["-parallel-testing-enabled", "NO",
                  "-disableAutomaticPackageResolution",
                  "-onlyUsePackageVersionsFromResolvedFile"]
                 + ["-only-testing:" + name for name in sys.argv[1:]]
}))
PY
  )
  rtk proxy xcodebuildmcp simulator test --json "$mivu_test_json" --output json
}
```

Each `mivu_test Target/Suite` below means run that suite, retaining exact command/result bundle/named cases/counts. RED means the named assertion fails (or the newly required interface is missing), not an unrelated environment failure. GREEN requires the intended named cases executed with zero failures; zero tests is failure. No arguments runs the full scheme, including UI. Use suites rather than unsupported Swift Testing method selectors. Do not bypass hooks or count Linux checks as native evidence.

## Task 1: Versioned metadata migration and explicit projections

**Files:** Create the shared model files, migration file, `ios/MivuTests/ChatHistoryFixture.swift`, `DiaryMigrationTests.swift`; modify `DiaryDatabase.swift` and existing `DiaryDatabaseTests.swift`.

**Interfaces:** Freeze the shared contracts above. Add `DiaryDatabase.migrateForPagedStorage(maximumBytes: Int) throws`; storage `user_version` 0 → 1 only when explicitly called at this stage. Add injectable `DiaryQueryDiagnostics` counters for decoded turn payloads, original photo bytes, complete reads/reconciles and query plans (no personal text). Fixture builds valid 100/10,000-exchange databases, equal timestamps, legacy missing-day data, colliding photo IDs and failure injection; add builders needed by later tasks alongside their tests.

- [ ] **1. Write failing migration tests.** Named cases: `migrationPreservesIdentityBytesAndLegacyDayEvidence`, `migrationIsIdempotentAndRollsBackOnFailure`, `storageBudgetMatchesPortableEncoding`. Assertions:
  ```swift
  #expect(after == before) // explicit full snapshots, including photo bytes
  #expect(secondGeneration == firstGeneration)
  #expect(legacyDaysAfter == legacyDaysBefore)
  #expect(failedMigrationVersion == 0)
  #expect(accountedBytes == (try JSONEncoder().encode(before)).count)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/DiaryMigrationTests`.
- [ ] **3. Implement migration and projections.** Add separate `coach_index` with unique immutable sequence (legacy ordinal then ID), captured metadata, pending state and segment ID; keep legacy ordinal for complete interchange ordering. Add indexed day/segment previews, record-source relationships, parent photo lookup and persisted photo content tokens. Backfill in bounded batches with no image decode; never create tracking days from legacy labels. Maintain exact portable-encoding quota contributions/counters, including base64, escaping and array separators; allow bounded streaming during one-time accounting instead of building the full graph. Tiny injected limits must model the real 350,000,000-byte boundary. Mint tokens on byte replacement; rebuild generation/tokens on restore. Validate relationships/counts and rollback disk/full/malformed failures atomically. Do not wire automatic migration yet.
- [ ] **4. Run GREEN:** migration and `DiaryDatabaseTests`; inspect indexes and verify no image decode during migration.
- [ ] **5. Commit reviewed files:** `feat: add versioned conversation metadata`.

## Task 2: Indexed pages, direct seeks and day previews

**Files:** Create `DiaryDatabaseQueries.swift`, `ios/MivuTests/CoachPagingTests.swift`; extend timeline models/fixture.

**Interfaces:** `DiaryDatabase.coachPage(_ request: CoachPageRequest, expectedProfileID: UUID) throws -> CoachPage`; `coachDays(before: CoachDayCursor?, expectedProfileID: UUID) throws -> CoachDayPage`. Public store wrappers are connected in Task 8.

- [ ] **1. Write failing tests:** `keysetPagesCoverEqualTimestampTurnsOnce`, `oldestDayAndSourceSeekAreIndexed`, `emptyDayIsNotNearestDay`, `foreignAndRestoredCursorsAreRejected`:
  ```swift
  #expect(page.exchanges.count <= 20)
  #expect(Set(allIDs).count == allIDs.count)
  #expect(allIDs == expectedSequenceIDs)
  #expect(dayPage.rows.count <= 30)
  #expect(metrics.turnPayloadsDecoded <= 20)
  #expect(metrics.originalPhotoBytes == 0)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/CoachPagingTests`.
- [ ] **3. Implement exclusive keyset queries.** Ascending display order, bounded around-turn window, first-exchange day seek, small neighbor metadata. Day previews come from indexed metadata rather than decoding every message. Return separate missing/no-chat outcomes. Use EXPLAIN QUERY PLAN assertions for range/seek predicates; avoid growing OFFSET or full payload scans. Repeated dates use stable segment IDs; infer legacy labels without diary mutations.
- [ ] **4. Run GREEN:** paging and migration suites with both fixture sizes, equal times/backward-clock sequences and page-edge dividers.
- [ ] **5. Commit:** `feat: query bounded conversation pages`.

## Task 3: Atomic targeted capture and status transactions

**Files:** Create `DiaryDatabaseMutations.swift`, `ios/MivuTests/CoachCaptureTransactionTests.swift`; modify `DiaryDatabase.swift`, `DiaryStore.swift`, fixture.

**Interfaces:** Private `DiaryDatabase.transaction<Value: Sendable>(expected: DiaryHead, maximumBytes: Int, _ body: (DiaryTransaction) throws -> Value) throws -> DiaryCommit<Value>`. `DiaryTransaction` owns head CAS, touched-row validation, quota deltas and row writes. Add store internal capture/status adapters with the existing public signatures; do not activate production selection yet.

- [ ] **1. Write failing tests:** `captureAppendsWithoutReadingOrReplacingHistory`, `repeatedCaptureRetainsDateAndSequence`, `staleRemovedOrReplacedDatabaseRejectsCommit`, `quotaAndCommitFailureLeaveHeadAndRowsUnchanged`:
  ```swift
  #expect(retriedTurn.id == firstTurn.id)
  #expect(retriedCaptureContext == firstCaptureContext)
  #expect(unloadedTurnAfter == unloadedTurnBefore)
  #expect(metrics.completeReads == 0 && metrics.completeReconciles == 0)
  #expect(failedHead == originalHead)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/CoachCaptureTransactionTests`.
- [ ] **3. Implement targeted append/state change.** Short-lived connection + profile/epoch/file identity fence; BEGIN IMMEDIATE, revision/lineage compare-and-swap, validate changed rows/ownership/quota, append next sequence once, commit once, then publish changes. Persist capture timezone/day/instant and operation ID before inference. Increment revision/lineage once per successful mutation; preserve idempotent no-op behavior. No complete snapshot comparison. Replay cannot mint a new capture date after timezone/clock change.
- [ ] **4. Run GREEN:** new suite plus existing stale/removed/replaced database tests and `CompanionReceiptTests`; retain existing public path until cutover.
- [ ] **5. Commit:** `feat: persist targeted chat captures atomically`.

## Task 4: Targeted diary, meal, review and photo operations

**Files:** Modify mutation/query files, `DiaryStore.swift`, read models; create `ios/MivuTests/DiaryProjectionMutationTests.swift`; retain `DayTests`, `DiaryTests`, `DiaryReviewFixTests` coverage.

**Interfaces:** Database/store projection capabilities: `diaryReadModel(expectedProfileID: UUID) throws -> DiaryReadModel`, `diaryDay(id: UUID, expectedProfileID: UUID) throws -> DiaryDayReadModel`, `meal(id: UUID, expectedProfileID: UUID) throws -> MealReadModel`, `photoContent(_ reference: DiaryPhotoReference, expectedProfileID: UUID) throws -> Data`. Preserve existing day/meal/review public operation names and expected-revision parameters through targeted adapters. Photo-free day-history summaries use a bounded keyset query, not every detailed meal.

- [ ] **1. Write failing tests:** `projectionMutationPreservesUnloadedRecords`, `collidingParentPhotoIDsResolveExactly`, `staleReviewAndQuotaFailurePreserveCommittedMeal`, `backdatedRecordDoesNotActivateChatDay`:
  ```swift
  #expect(activeDayAfter == activeDayBefore)
  #expect(oldMealAfter.items == oldCommittedItems)
  #expect(firstParentBytes != secondParentBytes)
  #expect(unrelatedPhotoTokenAfter == unrelatedPhotoTokenBefore)
  #expect(metrics.originalPhotoBytes == 0) // ordinary projection/mutation
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/DiaryProjectionMutationTests`.
- [ ] **3. Implement adapters.** Day start/confirmation/assignment, capture, edit/move/delete, review acceptance, submission retries, shared-photo lifecycle and tombstones operate on touched records. A committed active-day change owns the latest empty chat segment; creating a backdated day does not activate a segment. Read originals only for explicit content access or an operation actually requiring bytes. Photo owner includes parent kind/ID; insert/replace changes token, metadata-only updates do not rewrite BLOBs. Preserve unknown nutrition and pending proposals. Grounded writes retain original source-turn relationship, never infer it from display text. Maintain exact quota/row-count counters on rollback/deletion, without full-table integrity scans per write.
- [ ] **4. Run GREEN:** new suite plus day/diary/review and existing photo ownership/deletion regressions.
- [ ] **5. Commit:** `feat: update diary records without full snapshots`.

## Task 5: Atomic progress and mixed Coach writes

**Files:** Modify `DiaryDatabaseMutations.swift`, queries/read models, `DiaryStore.swift`, `CoachTools.swift`, `CoachManualEdits.swift`; create `ios/MivuTests/CoachBatchTransactionTests.swift`.

**Interfaces:** Add targeted implementation behind existing Coach mixed-batch entry point and existing weight/workout/goal/preferences methods. Internal batch returns `DiaryCommit<[CoachReceipt]>`; one transaction owns every touched record and receipt. Add bounded progress-range projection queries consumed in Task 8.

- [ ] **1. Write failing tests:** `mixedBatchIncrementsHeadOnceOrRollsBackEverything`, `replayedDeletedRecordIsNotResurrected`, `staleOrForeignProgressRejectsWholeBatch`:
  ```swift
  #expect(committedHead.revision == previousHead.revision + 1)
  #expect(receiptRevisions.allSatisfy { $0 == committedHead.revision })
  #expect(failedRecords == originalRecords && failedReceipts == originalReceipts)
  #expect(replayedMeal == nil)
  #expect(metrics.completeReads == 0 && metrics.completeReconciles == 0)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/CoachBatchTransactionTests`.
- [ ] **3. Implement whole-operation-set validation and atomic writes.** Reuse current operation validation/receipt semantics, reading only touched and referenced records; do not weaken stale/foreign/duplicate-operation checks. Persist receipt identity independently of surviving target rows. Historical dates update correct totals; receipt data is typed, committed and available to paging. Preserve shared progress-photo deletion behavior and preference/goal revision checks.
- [ ] **4. Run GREEN:** new suite, `CoachStoreTests`, `ProgressStoreTests`, `CoachManualEngineTests`, `CoachReceiptFeedbackTests`; specifically retain batch-failure and replay-after-deletion cases.
- [ ] **5. Commit:** `feat: commit mixed coaching operations atomically`.

## Task 6: Bounded workers and viewport-independent context

**Files:** Modify queries, `DiaryStore.swift`, `CoachEngine.swift`, `CoachTools.swift`; create `ios/MivuTests/CoachIndexedContextTests.swift`; extend existing flow/inference tests.

**Interfaces:** `nextPendingCoachTurn(includeWaitingForConnection: Bool, expectedProfileID: UUID) throws -> CoachWorkItem?`; `nextUnlinkedPendingSubmission(expectedProfileID: UUID) throws -> PendingSubmissionReference?`. Define these photo-reference-based work projections here. Retain existing context/tool call signatures, replacing their internals with indexed preceding-turn and grounded record reads.

- [ ] **1. Write failing tests:** `contextExcludesFutureQueuedTurnsAndIgnoresViewport`, `pendingWorkSurvivesEviction`, `historicalDateReadAndRelativeRetryStayGrounded`, `legacyRecoveryUsesIndexedUnlinkedSubmissions`:
  ```swift
  #expect(contextTurnSequences.allSatisfy { $0 < processedSequence })
  #expect(contextTurnSequences.count <= 12)
  #expect(contextBeforeSeek == contextAfterSeek)
  #expect(retryResolvedDate == originalResolvedDate)
  #expect(metrics.completeReads == 0)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/CoachIndexedContextTests`.
- [ ] **3. Implement pending-state/sequence selection and legacy anti-join recovery.** Bound dialogue to **12 preceding exchanges / 8,192 bytes** of encoded recent dialogue, grounded meals **24,000 bytes**, total encoded context **60,000 bytes**, preserving existing per-field truncation and omission-reference behavior. Fetch original photos only for selected inference job with current vision limits. Query explicit dates outside recent 14-day context directly. Preserve questions vs consumption, ambiguous date/target clarification, multi-date writes and committed-serving reuse; parsing/tool constraints use saved capture timezone, never retry time or viewport. No second inference/photo pipeline.
- [ ] **4. Run GREEN:** new suite, `CoachFlowTests`, `CoachInferenceTests`, `CoachManualEngineTests`, `CoachStoreTests`; assert pending query row work is independent of historical length.
- [ ] **5. Commit:** `feat: ground coaching in indexed bounded context`.

## Task 7: Consistent complete export and protected replacement

**Files:** Create `DiaryExportCoordinator.swift`, `ios/MivuTests/DiaryExportConcurrencyTests.swift`; modify `DiaryArchive.swift`, `FolderBackup.swift`, `DiaryBackupSettings.swift`, `DiaryStore.swift`.

**Interfaces:** Define `DiaryExportRequest` (profile/head/epoch/generation/source file identity/optional backup generation) and `DiaryExportTicket` (protected clone URL, actual clone head, request ownership). `DiaryExportCoordinator.makeClone(_ request: DiaryExportRequest) async throws -> DiaryExportTicket`; `DiaryStore.exportRequest(expectedProfileID: UUID) throws -> DiaryExportRequest`. Serialize complete data from the clone; existing archive/public backup APIs adapt to these owners.

- [ ] **1. Write failing tests:** `oneLoadedPageExportsEveryTurnAndPhoto`, `concurrentExportIsOneConsistentRevision`, `deleteRestoreOrReplacementRejectsDelayedAcknowledgement`, `archiveVersionsOneTwoThreeRemainReadable`:
  ```swift
  #expect(roundTrip.coachTurns.count == 10_000)
  #expect(roundTripPhotos == allOriginalPhotos)
  #expect(exportedSnapshot.revision == ticket.head.revision)
  #expect(obsoleteAcknowledgement == nil)
  #expect(deletedProfileRecreated == false)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/DiaryExportConcurrencyTests`.
- [ ] **3. Implement SQLite online-backup cloning, not raw file copy.** A background coordinator owns a read-only source connection and bounded backup steps into an isolated protected temporary database; DiaryStore remains the only live writer. Validate identity/epoch before/after steps and before final handoff; cleanup on cancellation. Read the actual consistent clone head, even if backup restarts on concurrent writes. Capture FolderBackup generation before scheduling, preserve deletion/high-water/lineage checks, and acknowledge only eligible actual clone revision. Serialization/Files calls never occupy the live writer for their duration. The version-1 complete assembler must accept ordinal gaps left by targeted deletion and emit correctly ordered complete arrays without renumbering live rows; use immutable sequence for chat. Restore validates complete input and builds/migrates a replacement database before the existing protected replacement boundary; new timeline generation rejects stale work. Keep current archive versions and size limits.
- [ ] **4. Run GREEN:** new suite and all `ArchiveTests`; prove a capture can commit while export/provider work is deliberately suspended.
- [ ] **5. Commit:** `feat: export consistent profiles without blocking capture`.

## Task 8: Activate storage and remove complete-graph hot paths

**Files:** Modify `DiaryDatabase.swift`, `DiaryStore.swift`, `DiaryViewModel.swift`, normal diary/progress readers from the file map, `CoachView.swift`, `CoachViewModel.swift`, `CoachEngine.swift`, `CompanionRuntime.swift`, and any `Connection/ChatGPTConnection.swift` snapshot caller found by inventory; create `ios/MivuTests/DiaryProjectionIntegrationTests.swift`.

**Interfaces:** Shipping `profiles() -> [DiaryProfile]` reads metadata only; `selectProfile(_ id: UUID) throws -> DiaryReadModel` and current refresh return projections. Expose Task 2/4/6 query wrappers through DiaryStore and `changes(expectedProfileID: UUID) -> AsyncStream<DiaryChanges>` with epoch-bound cancellation. Rename complete snapshot access to `snapshotForExport` and restrict to explicit interchange/testing callers.

- [ ] **1. Write failing integration tests:** `productionStartupCaptureAndWorkerRemainBounded`, `allMutationFamiliesPreserveUnloadedHistory`, `legacyReconcileRefusesMigratedDatabase`. Measure actual view-model/store/worker call paths on 100 and 10,000 valid exchanges:
  ```swift
  #expect(metrics.completeReads == 0 && metrics.completeReconciles == 0)
  #expect(startupMetrics.turnPayloadsDecoded <= 20)
  #expect(startupMetrics.originalPhotoBytes == 0)
  #expect(legacyWriterError == .invalidData)
  #expect(allUntouchedIDsAfter == allUntouchedIDsBefore)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/DiaryProjectionIntegrationTests`.
- [ ] **3. Perform the coordinated production cutover.** Activate migration before selected-profile operations, replace cached snapshot with head/epoch, wire all targeted adapters, migrate editor input to explicit detail, progress to ranges and root/header to projections. Inventory every `snapshot`, `readSnapshot`, reconcile and `current` use; record its new owner in the test/evidence notes. Remove ordinary complete-cache/reconcile paths; fence version-1 databases from legacy writes. New/imported/restored profiles use validated explicit complete creation. Derive canSend, pending work, companion activity and linked-record summaries from bounded projections/activity metadata, never loaded-page last-turn heuristics. Adapt the existing Coach rows to latest-page summaries so this commit compiles and remains usable; the full history renderer arrives in Task 12. Keep complete export isolated. No placeholder empty arrays to emulate complete state.
- [ ] **4. Run GREEN:** integration plus all affected unit suites; run the full `MivuTests` target once after cutover. Inspect diagnostics on real startup/send/worker paths and profile listing across multiple large profiles.
- [ ] **5. Commit:** `refactor: activate projection-based diary storage`. This is the first integrated storage candidate; camera/timeline UI is still pending.

## Task 9: Owned, lazy, bounded photo display

**Files:** Create `DiaryPhotoLoader.swift`, `ios/MivuTests/DiaryPhotoLoaderTests.swift`; adapt photo consumers in Coach, meal detail and progress in Task 12/13.

**Interfaces:** `DiaryPhotoLoader.thumbnail(for: DiaryPhotoReference, pixelSize: Int) async throws ->` an immutable Sendable image result, with MainActor UI adaptation. Define result in this file; original viewer uses Task 4 content API. Shared `PhotoWorkLimiter` actor limits total import/decode operations to two. Inject content reader and decoder for deterministic tests.

- [ ] **1. Write failing tests:** `cacheIncludesOwnerProfileContentAndSize`, `cancelledOffscreenDecodeDoesNotPublish`, `memoryPressurePurgesAndCostIsBounded`:
  ```swift
  #expect(firstParentImage != secondParentImage)
  #expect(cachedDecodedCost <= 16 * 1024 * 1024)
  #expect(maximumConcurrentPhotoJobs <= 2)
  #expect(staleImagePublications == 0)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/DiaryPhotoLoaderTests`.
- [ ] **3. Implement off-main downsampling with ImageIO and costed eviction.** Key by profile, parent kind/ID, photo ID, content token and requested size. Reserve decode cost before admitting jobs, cancel offscreen, purge on memory pressure/profile reset. References/photos occupy fixed preview geometry. No page prefetch of originals; open viewer/inference/draft are explicit separately bounded consumers.
- [ ] **4. Run GREEN:** loader tests with collisions, byte replacement under same UUID, cancellation/profile reset and memory warning.
- [ ] **5. Commit:** `feat: load bounded photo thumbnails on demand`.

## Task 10: Camera-first capture and durable draft ownership

**Files:** Create camera/session/draft files from map and `ios/MivuTests/CoachCameraTests.swift`, `CoachAttachmentDraftTests.swift`; extract PhotoPreparation to its own file; modify PhotoCapture only for shared normalization, preserving MealComposer behavior.

**Interfaces:** `CoachCameraSession` owns authorization, start/stop/capture and interrupted/unavailable/retry state on a serial non-main executor. Define a narrow preview adapter to attach its private session to AVCaptureVideoPreviewLayer on MainActor, following the linked AVCam ownership pattern. `CoachAttachmentDraft` owns stable attachment IDs, ordering, text, submissionID, capacity reservations and profile/presentation generation; `importSelections`, `retake`, `remove`, `cancelPendingImports` are async/event operations with injected import/session dependencies.

- [ ] **1. Write failing tests:** `cameraIsFirstDestinationAndLibraryCancelResumesIt`, `draftImportsAreOrderedBoundedAndPartiallyRecoverable`, `lateProfileOrPresentationResultIsDiscarded`, `failedSaveRetainsDraftAndOperationIdentity`:
  ```swift
  #expect(firstDestination == .camera)
  #expect(draft.attachments.count + reservedAttachmentCount <= 8)
  #expect(maximumConcurrentPhotoJobs <= 2)
  #expect(retrySubmissionID == originalSubmissionID)
  #expect(mealsCreatedBeforeSend == 0)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/CoachCameraTests MivuTests/CoachAttachmentDraftTests`.
- [ ] **3. Implement full-screen native camera with shutter/Close/Choose photos.** Camera permission only; PhotosPicker needs no broad library access and no latest-photo scan. Denied/restricted/no-hardware retain library/Close and useful Settings action. Pause session while covered/backgrounded, resume after cancelled library, release on dismissal, recover interruption visibly. Captured/selected images return to composer without send. Retake replaces one stable attachment; retain successful partial imports/text. Use existing JPEG/vision normalization off MainActor under shared limiter; check owner/generation before publishing. Restore keyboard focus without feedback replay. No unsafe camera-session actor transfer or frame upload.
- [ ] **4. Run GREEN:** both suites, existing `CoachPhotoTests`/capture-options tests. Hardware permission/preview/interruption remains a Task 15 gate; injected tests do not claim it.
- [ ] **5. Commit:** `feat: add camera-first coaching drafts`.

## Task 11: Bounded timeline state and asynchronous paging

**Files:** Replace existing `CoachHistoryWindow.swift`; create `CoachTimelineViewModel.swift`, `ios/MivuTests/CoachTimelineTests.swift`; replace/extend existing `CoachHistoryWindowTests.swift`.

**Interfaces:** Define `CoachViewportAnchor(rowID: UUID, offset: Double, focusedExchangeID: UUID?)`, viewport mode and explicit restoration instructions. `CoachTimelineViewModel` injects `@Sendable (CoachPageRequest, UUID) async throws -> CoachPage`; methods `loadLatest()`, `loadEarlier(anchor:)`, `loadLater(anchor:)`, `seek(_:)`, `apply(_ changes: DiaryChanges)`, `setViewport(_:)`, `jumpToLatest()`, `invalidate(identity:)`. The pure window owns loaded/reserved pages and edge state; view model owns cancellation/generation.

- [ ] **1. Write failing tests:** `oppositeEdgeRequestsReserveBeforeFetching`, `focusedPageCannotBeEvicted`, `staleResponsesAfterSeekOrProfileChangeAreIgnored`, `replyWhileReadingDoesNotFollowLatest`:
  ```swift
  #expect(residentExchanges + reservedExchangeCapacity <= 100)
  #expect(inFlightEarlierRequests <= 1 && inFlightLaterRequests <= 1)
  #expect(visibleIDs.contains(focusedExchangeID))
  #expect(anchorAfter == anchorBefore)
  #expect(showsJumpToLatest)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/CoachTimelineTests MivuTests/CoachHistoryWindowTests`.
- [ ] **3. Implement pure page transitions.** Reserve capacity before fetch; defer when safe eviction is impossible. Pin visible/focused page and avoid conflicting eviction during interaction; evict distant page only with anchor captured. Discard generation-stale work, merge visible-turn deltas by ID, preserve other pages, handle empty/error/end separately. Reload either edge after eviction, retain draft outside window, never preload unbounded results. New message/day transition updates latest indicator without forcing historical viewport. No database/image work per frame.
- [ ] **4. Run GREEN:** suites with controlled delayed/reordered responses, six-plus pages, failed fetch/retry and active-day empty divider.
- [ ] **5. Commit:** `feat: manage an anchored bounded chat window`.

## Task 12: Native timeline, truthful receipts and composer integration

**Files:** Modify CoachView/ViewModel/ActivityView; create CoachTimelineView/CoachReceiptView and `ios/MivuUITests/CoachHistoryUITests.swift`; extend receipt/activity unit suites.

**Interfaces:** `CoachTimelineView` binds Task 11 state and reports measured viewport anchor; `CoachReceiptView` consumes typed committed receipt plus current record summary/revision and opens existing review/editor. Reuse existing draft/send/activity owners; connect Task 10 camera directly to camera icon.

- [ ] **1. Write failing UI tests:** `prependAndThumbnailArrivalPreserveMeasuredOffset`, `historySendKeepsViewportAndUsesCurrentDay`, `receiptShowsCommittedDateAndUnknownEstimates`, `cameraDraftDoesNotAutoSubmit`:
  ```swift
  XCTAssertLessThanOrEqual(abs(afterAnchorY - beforeAnchorY), 2)
  XCTAssertEqual(sourceTurnIDAfterCorrection, sourceTurnIDBeforeCorrection)
  XCTAssertTrue(app.buttons["Jump to latest"].exists)
  XCTAssertFalse(unknownNutritionWasRenderedAsZero)
  ```
- [ ] **2. Run RED:** `mivu_test MivuUITests/CoachHistoryUITests` with synthetic launch fixtures.
- [ ] **3. Implement stable exchange rows and segment dividers in LazyVStack.** Use native scroll position/geometry to restore row plus offset; demonstrate offset tolerance rather than assuming `scrollTo(id:)` preserves it. If native APIs fail this measured gate, introduce one narrow UIScrollView-backed timeline bridge in this file boundary, keeping the same state contract and virtualization budget. Keep edge indicators fixed, thumbnails sized, page insertion unanimated. Copy/select text, show active logging day near composer, keep draft while history open. Receipt uses record target date, typed estimate/status, Review/Edit; never parse assistant prose or invent success. Distinguish durable input, analysis, retry/review and file backup. Sending while reading preserves position and offers latest action.
- [ ] **4. Run GREEN:** new UI suite plus existing Coach UI/activity/receipt suites, light/dark and late image/reply scenarios. Record anchor measurements in native tests.
- [ ] **5. Commit:** `feat: present continuous chat with stable scrolling`.

## Task 13: History sheet and Diary-to-chat navigation

**Files:** Create CoachHistoryView and `ios/MivuTests/CoachNavigationTests.swift`; modify DiaryRootView inside TodayView.swift, HistoryView, MealDetailView, CoachView/ViewModel; extend CoachHistoryUITests.

**Interfaces:** Root owns one optional `CoachNavigationRequest` routed to the existing Coach instance. History sheet consumes `coachDays` and resolves calendar selection to existing day identity without creating a day. Diary Open chat supplies day ID; meal View conversation supplies persisted source turn ID. Request consumed once only after ownership validation.

- [ ] **1. Write failing tests:** `oldestDiaryDayAndBackdatedMealOpenExactWindow`, `missingDayAndLegacyMealHaveHonestEmptyStates`, `profileChangedBeforeRouteCannotOpenForeignChat`:
  ```swift
  #expect(openedTurnID == backdatedMealSourceTurnID)
  #expect(routeProfileID == selectedProfileID)
  #expect(noChatDidNotOpenNearestDay)
  #expect(draftAfterNavigation == draftBeforeNavigation)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/CoachNavigationTests MivuUITests/CoachHistoryUITests`.
- [ ] **3. Implement recent-first 30-day preview paging, direct date seek and Diary links.** No intermediate transcript walk. Distinguish no-chat, no attributable source, deleted target and removed profile. Do not fabricate source links for legacy meals or change profile implicitly. Highlight target briefly/static under Reduce Motion; support earlier/later/latest after seek and preserve draft/scroll mode.
- [ ] **4. Run GREEN:** navigation and UI suites, including day with multiple segments and source on another conversation day. Check query diagnostics during oldest-window navigation.
- [ ] **5. Commit:** `feat: link diary dates and meals to chat history`.

## Task 14: Accessible lifecycle and Pip regression gates

**Files:** Modify new chat/camera views and CompanionRuntime only as needed; extend `CoachActivityTests`, `CompanionReceiptTests`, `CompanionSurfaceTests`, `CoachHistoryUITests`, `CompanionUITests`.

**Interfaces:** Keep existing companion activity/operation/receipt identities; derive these from active operation metadata, not the viewport. Add accessibility load/retry/latest actions and single page-completion announcements without stealing focus.

- [ ] **1. Write failing regressions:** `pagingAndPhotoLoadsEmitNoCompanionFeedback`, `cameraCoverPausesWithoutReplayingSaved`, `focusedExchangeSurvivesPagingAtLargestText`:
  ```swift
  #expect(feedbackIDsAfterPaging == feedbackIDsBeforePaging)
  #expect(savedFeedbackCount == durableReceiptCount)
  XCTAssertEqual(focusedExchangeAfter, focusedExchangeBefore)
  XCTAssertGreaterThanOrEqual(smallestActionTargetHeight, 44)
  ```
- [ ] **2. Run RED:** relevant companion/activity suites and `MivuUITests/CoachHistoryUITests`.
- [ ] **3. Implement lifecycle/accessibility adjustments.** Hidden/camera-covered/background surfaces pause using existing policy; retain Reduce Motion/low-power/thermal behavior and typing quietness. Save feedback only after durable capture/receipt, accepted-submit gesture before inference await. No animation-asset changes. VoiceOver has explicit Load earlier/later, Retry and Jump to latest; announce requested-page completion once and retain focus. Test largest text with composer/library/editor actions reachable and status understandable without color.
- [ ] **4. Run GREEN:** focused suites plus existing companion mount/selection/Lottie preview regressions. Visually inspect Today/Coach for unrelated-pose flashes through camera/background/navigation; apply repository animation verification recipe if lifecycle changed.
- [ ] **5. Commit:** `fix: preserve accessible chat and companion lifecycle`.

## Task 15: Performance evidence and delivery review

**Files:** Add `ios/MivuTests/CoachPerformanceTests.swift`, extend synthetic UI fixtures in `CoachUITestInference.swift` and history tests; update `docs/development/coach-chat-behavior.md`, create the verification evidence file from the map.

**Interfaces:** Reuse diagnostics/fixtures from Task 1, actual production call paths from Task 8 and anchor measurement from Task 12. Record exact source SHA, environment, dataset, command, named cases/counts/result bundle and blocked gates; no new runtime analytics dependency.

- [ ] **1. Write failing performance/regression gates:** `historyLengthDoesNotIncreaseDecodedStartupOrWorkingSet`, `seekAndPagingStayWithinDeclaredBounds`; add deterministic assertions before timing measurements:
  ```swift
  #expect(largeStartup.turnPayloadsDecoded <= 20)
  #expect(largeStartup.originalPhotoBytes == 0)
  #expect(residentAndReservedExchanges <= 100)
  #expect(decodedCacheCost <= 16 * 1024 * 1024)
  #expect(completeHotPathReads == 0)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/CoachPerformanceTests`; confirm a deliberate unbounded-read fixture is detected by the instrumentation, not silently excluded.
- [ ] **3. Complete measurement fixtures and repair any failing path.** Compare 100/10,000 exchanges holding non-chat contents constant, bounded valid synthetic photos and limits respected. For append tests start at 9,999 turns and finish at 10,000; separately assert an over-limit append fails without altering the draft or stored data. Measure cold/warm first usable page, oldest-day seek, edge-fetch/apply p95, anchor offset, main-thread stalls, image work and resident memory on a connected physical iPhone; document repeated trials, thermal state and migration separately. Measure explicit exports separately. Use native Instruments/signposts without per-frame DB calls. Do not weaken budgets to turn evidence green. Hardware camera first permission/denial/capture/library/retake/interruption/background and actual VoiceOver are required observations; record unavailable device gates honestly and finish simulator work first.
- [ ] **4. Run final verification.** `mivu_test` for full native unit/UI scheme, serially, after final source changes; preserve nonzero named-test/count evidence. Run `rtk proxy python3 -m unittest discover -s scripts/ci -p 'test_*.py'` and shell syntax checks from CI contract. Have a fresh reviewer perform Ponytail Review and whole-spec/data-safety review; fix blocking findings and rerun affected checks. Recheck current commit, clean inputs and hook results. No 60/120-fps or device acceptance claim from simulator alone.
- [ ] **5. Commit docs/remaining reviewed changes:** `test: verify chat performance and migration safety`. Push with normal hooks, open a draft PR describing final behavior, migrations, native evidence and any device gates. Attach its URL to the task. This plan authorizes no merge, release publication or iPhone installation; those follow the owner's subsequent request.

## Plan review and handoff

Storage and camera/UX planning were independently inspected by two subagents. This plan incorporates their findings on profile-list hydration, composite photo ownership, archive versions, immutable sequence, migration cutover, generation races, native anchor measurement and background export. Author self-review checked every spec section against task ownership, shared interfaces, all five Review Focus cases and document proportion. It corrected context-byte constants, export ordering after deletion, the cutover's temporary UI adapter and append fixtures at the 10,000-turn limit. Documentation validation checked task/step counts, links, shell recipe and whitespace; native/product acceptance is intentionally pending execution.

The owner already chose subagent-driven execution. Present this written plan for review, preserve that choice, and wait for the review before implementation, as required by the writing-plans workflow. No product code, migration activation, simulator deployment or device installation is part of this planning change.
