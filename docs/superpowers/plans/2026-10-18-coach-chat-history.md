# Coach Chat History and Camera Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Coach a smooth, continuous, genuinely paged conversation with direct camera capture, reliable historical navigation and trustworthy dated receipts.

**Architecture:** Keep profile-local SQLite and DiaryStore as the sole live writer. Introduce indexed metadata, explicit screen projections and targeted transactions before activating a coordinated storage cutover; render a bounded, anchored timeline independently of worker context. Reuse existing diary rules, analysis, photo normalization, native editors, Precision Glass and painted Lottie Pip.

**Tech Stack:** Swift 6, iOS 26+, SwiftUI, SQLite3, AVFoundation, PhotosPicker, existing Lottie runtime, Swift Testing/XCTest, XcodeBuildMCP. No new dependency or hosted service.

**Spec:** [Approved design](../specs/2026-10-18-coach-chat-history-design.md). Read it with this plan; its examples and acceptance table remain requirements.

## Global Constraints

- One continuous conversation per private profile; dividers follow committed waking/tracking-day recognition, not a separate midnight timer.
- Latest/adjacent/seek pages contain at most **20 exchanges**; history previews contain at most **30 date/segment rows** (at most **30 days**, repeated labels stay distinct). Resident and reserved/prefetched pages together contain at most **100 exchanges / five pages**.
- Thumbnail cache: **16 MiB decoded cost**; **two concurrent decode/import jobs**. Draft: **eight attachments**. Preserve profile limit **350,000,000 bytes**, **250,000,000 original-photo bytes**, **10,000,000 bytes per stored photo**, **10,000 turns**, and the remaining existing row/import/vision limits.
- Capture time, timezone, active day and operation identity are durable before inference. History position never assigns a new message's date. Keep current explicit day-choice behavior.
- Normal startup, profile listing/selection, refresh, capture, mutations and worker paths must not read/reconcile a complete snapshot. A projection is never a partial DiarySnapshot.
- Complete snapshots are explicit archive/import/backup operations only. Preserve schema 1 snapshots, archive envelope 3, and decoding of envelopes 1/2/3.
- Keep revision/lineage, epoch, ownership, file replacement, tombstone, idempotency and backup acknowledgement protections. Never delete an unloaded row.
- Native English MVP; semantic light/dark colors, Dynamic Type, VoiceOver, Reduce Motion and minimum **44-point** targets. No new Pip assets or animation timing changes.
- Hardware targets after migration: cold usable latest page **≤2 s**, warm reopen **≤500 ms**, edge fetch/application **p95 ≤200 ms**, prepend displacement **≤2 pt**. These are gates to measure, not claims already proved.
- Use rtk for verbose commands and XcodeBuildMCP for all native jobs. Native jobs run serially. Preserve hooks and private delivery rules; no new hosted native jobs, billing, release or public upload.

## Review Focus

1. Legacy nil-day segments, repeated date labels, DST/travel and stale routes: identities stay separate, exact navigation and captured date meaning survive retry/restore (Tasks 1, 2, 3, 6, 13).
2. Colliding photo UUIDs, shared progress references and late callbacks: deleting one consumer never removes another's valid content or exposes a foreign image (Tasks 1, 4, 5, 9, 10).
3. Variable-height rows, overlapping edge requests, eviction and background replies: reserved pages stay bounded and measured anchors/focus survive paging; prove renderer feasibility before cutover (Tasks 11A, 11, 12, 14).
4. Export/migration interrupted by disk shortage, deletion or replacement: preserve consistent data and stale-ack fences; recovery never assumes an older binary understands the version fence (Tasks 1, 7, 8, 15).
5. Uncertain capture, crash after receipt commit, stale live records and quota drift: stable identities permit one business application, no partial batch or resurrection, and exact differential accounting (Tasks 1, 3–6, 10, 15).

---

## Execution and integration order

The owner selected subagent-driven work. Use fresh implementer/reviewer contexts with file ownership per task; use 6.1-sol for storage, concurrency, camera and scrolling, and Luna for bounded fixture/documentation work. Review specification compliance and code quality for each task, then review the entire branch. Root integrates shared-file changes and owns all native job scheduling.

Work in the existing attached checkout `/private/tmp/mivu-local-hooks`, branch `codex/coach-chat-design`. The original plan was committed as `73ae129`; this in-place revision follows it. Recheck HEAD/status/remotes before execution and preserve newer work. These references are provenance, not reset targets. Do not create competing checkouts or silently reset the branch.

Dependency order:

```text
1 → 2 → 3 → 4 → 5 → 6 → 7       (storage components)
1 + 2 → 11A                     (isolated scrolling feasibility gate)
1 → 9; 3 + 9 → 10               (photo/camera plus accepted-payload contracts)
7 + 9 + 11A → 8                 (gated production storage cutover)
2 + 11A → 11                     (pure timeline components)
8 + 9 + 10 + 11 → 12 → 13 → 14 → 15
```

Tasks 9–11, including early subtask 11A, can overlap the storage track after their dependencies and shared types are committed. Their components remain unwired until Task 12. Root schedules 11A before Task 8, even though it is documented under its owning Task 11. Never run two writers against shared files or two native jobs. Commit each reviewed task; push at integration milestones with normal hooks. Intermediate storage commits are not deployment candidates.

### Storage activation boundary

Task 1 exposes migration explicitly for fixture/component tests; it does **not** automatically migrate shipping profiles. Tasks 2–7 implement and test the new architecture against those migrated databases. Task 8 activates migration, replaces ordinary snapshot readers/writers and applies a database-version fence **in one integration commit**, only after migration rollback, targeted mutations, all crash/replay boundaries, seeded quota checks, archive/restore and 11A renderer-decision evidence are green. A focused rehearsal of actual startup/profile listing/selection/send/correction/worker paths must also pass before enabling automatic migration. Isolated queries alone cannot pass this gate.

Once storage version 1 is active, the revised legacy `write(snapshot, expected:, maximumBytes:)` must refuse it. Explicit full-profile creation/replacement remains available for imports/restores. This fence protects calls in the new code; existing older binaries do not check `user_version`. Do not ship a feature flag permitting both writer architectures on the same profile. See the recovery policy below; no downgrade safety is implied.

### Recovery and disk-space policy (Tasks 1, 7, 8, 15)

| Situation | Supported behavior and evidence |
|---|---|
| Failure before migration commits | Roll back the transaction; original version-0 profile remains authoritative. Clean only owned incomplete temporary artifacts; display recoverable error, never an empty replacement. Inject migration/commit/ENOSPC failures and reopen the original. |
| Defect found after activation | Stop the affected operation, preserve the version-1 database and any validated complete archives, and recover with a corrected **compatible** build. Export a complete consistent archive when possible; if integrity prevents export, retain the original files for diagnosis. Reverting a source commit is not a storage rollback. Never silently restore an older archive over later captures. |
| Validated complete archive restore | Existing ownership/revision/lineage/deletion policy still decides eligibility. Build and validate a protected replacement off the live store; switch atomically, rebuild indexes/generation and reject old jobs/acks. A conflicting archive needs existing explicit recovery handling; it cannot bypass tombstones. |
| Older app against migrated storage | Unsupported. The inspected older open/write paths ignore `user_version`; they can rewrite old tables while leaving new indexes stale. Do not install/recommend an older binary with this live store, and do not claim it fails safely. Test the revised writer fence separately from this known compatibility limitation. Returning to a genuinely pre-migration backup also loses subsequent data and is not the normal supported recovery. |

Logical profile/row/photo quotas do not reserve physical disk. Migration rollback journals, consistent export clones, archive output and atomic replacement can need additional space. Check available capacity before expensive allocation where supported, still handle ENOSPC at every write/commit, cancel safely and remove only incomplete task-owned artifacts. Preserve the source and completed validated output; never delete unrelated backups or silently raise/reinterpret logical quotas. Tests inject failures during clone, serialization and replacement and verify source integrity, pending acknowledgement/error state and cleanup. Physical storage behavior remains part of Task 15 evidence.

## File responsibilities

Paths below are relative to the checkout. Modify existing types instead of making parallel owners.

| Files | Responsibility / task owner |
|---|---|
| `ios/Mivu/Diary/DiaryReadModels.swift` (new) | Photo-free head/current-day/day-detail/meal/progress projections, invalidations; 1/4/5 |
| `ios/Mivu/Coach/CoachTimelineModels.swift` (new) | Identity, segment summaries/date lookups, cursors, pages, seek/navigation contracts, typed receipts; 1/2 |
| `ios/Mivu/Diary/DiaryDatabaseMigration.swift` (new), `DiaryDatabase.swift` | Storage version, derived indexes, query diagnostics, transaction primitives; 1/3 |
| `ios/Mivu/Diary/DiaryDatabaseQueries.swift` (new) | Indexed projections, paging, worker/context/grounded reads; 2/4/6 |
| `ios/Mivu/Diary/DiaryDatabaseMutations.swift` (new) | Targeted validated row operations and atomic mixed batches; 3/4/5 |
| `ios/Mivu/Diary/DiaryStore.swift`, `ios/Mivu/Coach/CoachModels.swift` | Sole live writer, immutable accepted payload/reconciliation, existing work states, receipt recovery, selected head/epoch and cutover; 3–8 |
| `ios/Mivu/Diary/DiaryExportCoordinator.swift` (new), `DiaryArchive.swift`, `FolderBackup.swift`, `DiaryBackupSettings.swift` | Consistent complete clone/export, replacement and acknowledgement fences; 7 |
| `ios/Mivu/Diary/DiaryViewModel.swift`, `TodayView.swift`, `HistoryView.swift`, `MealDetailView.swift`, `MealComposerView.swift`, `SettingsView.swift`; `ios/Mivu/Progress/{ProgressAnalytics,ProgressEditorViews,ProgressView}.swift` | Current-screen projections, on-demand detail, date/source routes; 8/13 |
| `ios/Mivu/Coach/{CoachViewModel,CoachEngine,CoachTools,CoachManualEdits}.swift` | Capture/worker/read/write caller migration; 5/6/8 |
| `ios/Mivu/Diary/DiaryPhotoLoader.swift`, `PhotoPreparation.swift` (new) | Owned lazy thumbnails; extract existing PhotoPreparation from DiaryViewModel; 9/10 |
| `ios/Mivu/Coach/{CoachCameraView,CoachCameraSession,CoachAttachmentDraft}.swift` (new); `ios/Mivu/Diary/PhotoCapture.swift` | Camera lifecycle, picker, bounded draft; 10 |
| `ios/Mivu/Coach/CoachHistoryWindow.swift`, `CoachTimelineViewModel.swift` (new) | Pure bounded window and asynchronous paging orchestration; 11A/11 |
| `ios/Mivu/Coach/CoachScrollSpikeView.swift` (temporary test-only new file), `ios/MivuUITests/CoachScrollSpikeUITests.swift` (new) | Injected synthetic scrolling feasibility; root/Task 11A owns these and the renderer decision; remove temporary view after Task 12 adopts the single selected renderer |
| `ios/MivuTests/DiaryQuotaAccountingTests.swift` (new) | Seeded incremental-versus-complete encoding oracle; 1/3–5/15 |
| `ios/Mivu/Coach/{CoachView,CoachActivityView}.swift`, `CoachTimelineView.swift`, `CoachReceiptView.swift`, `CoachHistoryView.swift` (new) | Virtualized rows, receipts, history sheet; 12/13 |
| `ios/Mivu/Design/CompanionRuntime.swift` | Preserve feedback identity/lifecycle through projected data; 8/14 |
| `ios/MivuTests/ChatHistoryFixture.swift` (new) | Synthetic valid small/large profiles and bounded query diagnostics; 1, extended by owning tests |
| `ios/MivuTests/*Tests.swift`, `ios/MivuUITests/*Tests.swift` | Named focused tests in each task below; existing regressions retained |
| `docs/development/coach-chat-behavior.md`, `docs/verification/2026-10-18-coach-chat-history.md` (new evidence file) | Final contracts, fixtures and measured/blocked acceptance; 11A creates renderer evidence, 15 completes it |

### Shared contracts to freeze in Task 1

All values crossing actors are Sendable; UI orchestration is MainActor. Do not make SQLite handles or camera sessions unchecked Sendable to satisfy the compiler.

- `DiaryHead`: profile, revision, lineage, activeDayID, timelineGeneration. Selected store state holds this head and its existing selection epoch, not a full graph.
- `CoachTimelineIdentity`: profileID + timelineGeneration. `CoachCursor`: identity + immutable Int64 sequence + turnID. Reject mismatched identity before reading.
- `DiaryPhotoOwner`: `.meal(UUID)` / `.coachTurn(UUID)`, the two verified byte owners. `DiaryPhotoReference`: profileID, owner, photoID, createdAt, role, persisted UUID `contentToken`. Physical composite IDs remain unchanged. Progress records have no BLOB fields: receipts link them to the originating turn, whose photos are initially `.coachTurn`-owned; existing food/attachment operations may move bytes to a linked `.meal`. Resolve the actual owner through these links, never invent `.progress`. Index consumer links and check them before deleting content; UUID alone is never an ownership key. Preserve existing byte transfers, without broadening retention/deletion policy.
- `MealReadModel`: record identity/day/times/revision, committed items, required submission state, photo references, optional sourceTurnID; preserve existing pure totals/review rules. `DiaryReadModel`: head, active day/previous-day confirmation, active-day meals/weight/workouts, active goal and pending-analysis count. `DiaryDayReadModel` is one requested day; progress/history use bounded range/summary reads. No `[MealPhoto]` with empty Data pretending to be complete content.
- `DiaryChanges`: changed day/meal/turn/weight/workout ID sets plus profile/timeline reset indication. `DiaryCommit<Value: Sendable>`: value, committed head, changes. Existing public mutation returns may remain unchanged; publish this internal result after commit.
- `CoachExchangeSummary`: stable ID/sequence, capturedAt/timeZoneID, `segmentID`, optional captured `trackingDayID`, displayLocalDate/displayTimeZoneID, text, reply, typed work state, photo references, typed committed receipts. No image bytes or view-parsed resultJSON. TrackingDay UUID identifies a diary day, segment UUID identifies one contiguous conversation run, and the date label is presentation evidence, never an identity. One day can own multiple segments; repeated labels can belong to different days or inferred nil-day segments.
- `CoachPageRequest`: `.latest`, `.before(CoachCursor)`, `.after(CoachCursor)`, `.aroundTurn(UUID)`, `.atDay(UUID)`. `CoachPage`: identity, ascending exchanges, exclusive before/after cursors, hasEarlier/hasLater and boundary-neighbor segment metadata. Distinguish no-chat/missing-target from an empty successful latest page using typed query errors/results.
- `CoachSegmentSummary`: segmentID, optional trackingDayID, displayLocalDate/displayTimeZoneID, firstExchangeID, firstCapturedAt, firstSequence, lastSequence, preview. `CoachDayPage` keeps its existing planned name but contains at most 30 **segment** rows, cursor and hasMore; History labels the date and distinguishes repeated segments with capture time/timezone when needed. `CoachDayCursor`: identity + lastSequence + segmentID + optional date-filter scope; cursors cannot cross that scope.
- `CoachSeekTarget`: `.day(UUID)` / `.turn(UUID)` remains sufficient; no segment-seek variant. History row → `.turn(firstExchangeID)`. Diary day → minimum sequence across all segments assigned to that exact day UUID. Meal link → exact source turn. `CoachNavigationRequest`: timeline identity, target, requestID; selection epoch/seek generation remain local async fences. Validate before resolution and application; consume only matching requestID, never a newer request. No implicit profile switching.

### Durable capture, replay and live-record reads (Tasks 3, 5, 6, 10)

Reuse `CoachTurnState` rather than adding a second queue state machine:

| Boundary / existing state | Durable truth, transaction owner and recovery |
|---|---|
| Unsent composer / before capture commit | Memory only, no accepted row or saved acknowledgement and no food mutation. Task 10 retains the draft during this session; process restart does not restore it. |
| Capture outcome uncertain | Task 3 capture transaction may already have committed. Reconcile same profile/submission ID and immutable payload before resubmitting or clearing the composer; no new identity on uncertainty. |
| `captured`, including crash before scheduling | Task 3 atomically persisted accepted input, manifest, capture context and sequence. Task 6 indexed worker discovers it after restart without a UI scheduling acknowledgement. |
| `analyzing` interrupted / `waitingForNetwork` | Status transaction owns state only. Task 6 resets interrupted analysis/retries eligible network work using the same accepted submission; remote inference may execute again. |
| `waitingForConnection` / `needsRetry` | Existing authorization gate / explicit retry respectively; Task 6 preserves capture, receipts and semantic operation keys. |
| `needsClarification` | Existing explicit day/target recovery; no speculative writes. A successful ask_clarification reply can be `completed` today; do not invent a durable state for it. |
| Inference returned, before record commit | No inferred business changes durable. Task 5 revalidates the complete batch and commits record changes plus receipts atomically, or neither. |
| Records/receipts committed, UI/worker/final reply absent | Task 5 receipts are authoritative, independent of worker acknowledgement. Task 6 restart uses recorded results, never reapplies those mutations. Deleted targets stay deleted: retain the historical receipt and surface target-unavailable (`notFound` on existing record-replay APIs), never successful current-record existence. Final grounded reply may retry from prior receipts and current target availability. |
| `completed` / profile epoch or timeline changed | No automatic replay of completed work; late work is rejected on identity change. Reopen current projections instead of publishing an old result. |

Task 3 defines `CoachSubmissionPayload` (submissionID/turnID, exact submitted text, ordered stable attachments and frozen capture instant/timezone/active-day context) and a compact persisted `CoachSubmissionManifest` (those identities/context, text fingerprint and ordered attachment ID/role/createdAt/content-fingerprint tuples), without duplicating text or photo bytes. Use existing CryptoKit SHA256/canonical-encoding patterns, not a new dependency. Store optional manifest metadata compatibly in CoachTurn; legacy decoder defaults and current envelope/schema versions remain unchanged. Never fabricate fingerprints for already deleted legacy content or overwrite a legacy accepted turn; receipts/existing durable evidence govern its recovery. New captures never overwrite a manifest under the same ID. Explicit photo deletion can remove bytes/visible references while the original manifest preserves payload identity; it does not retain deleted image content.

`reconcileCoachCapture(submissionID: UUID, expectedManifest: CoachSubmissionManifest, expectedProfileID: UUID) throws -> CoachCaptureReconciliation` returns `.absent`, `.accepted(CoachExchangeSummary)` or `.conflictingPayload`. Task 10 freezes proposed identity/attachment IDs and capture context before first send; Task 3 verifies that context against the selected profile/day before acceptance, rejecting stale context rather than silently rewriting it. On an uncertain outcome, match the original attempted context/manifest before any new send. Absent permits retrying that frozen attempt; accepted resumes existing work and clears only a still-matching composer; conflict never overwrites accepted input. An intentionally edited payload gets a new submission ID after reconciliation, while the already accepted input remains visible. Retrying accepted input preserves its ID and context. This is not a persistent-unsent-draft subsystem.

Mutation keys remain semantic `turnID/CoachWrite.target`, never transport tool-call IDs or retry UUIDs. Task 5 adds an optional canonical `commandFingerprint` to CoachReceipt, committed with the intended mutation; legacy receipts without it remain authoritative prior results, not permission to overwrite the operation. A regenerated call cannot change committed arguments or substitute another target. At `CoachEngine.run` entry, existing receipts mean recovery completes from receipts/grounded reads and cannot admit a new mutation target from regenerated inference; matched replay is read-only, conflicting intent needs clarification. Preserve legitimate uninterrupted tool rounds and multi-date atomic batches; do not declare uncommitted remainder saved. Distinguish status-only revisions from business applications: test stable record/receipt identities and per-operation applications, not globally unchanged revision across state updates. No exactly-once claim for remote inference.

Dialogue eligibility is historical (`sequence < processedSequence`); diary/tool reads are **current committed records at each read**, not record versions frozen at capture. Task 6 carries retrieved revisions, then Task 5 rereads/revalidates touched records inside commit after awaits. A referenced meal edited/deleted meanwhile rejects the stale batch; unrelated edits may pass by refreshing the scalar head/lineage and revalidating unchanged touched revisions, without rerunning inference or bypassing CAS. Existing pending-meal preparation can refresh its base revision **before** inference, never silently rebase an inferred correction afterward. No historical snapshots or event sourcing.

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

**Files:** Create the shared model files, migration file, `ios/MivuTests/ChatHistoryFixture.swift`, `DiaryMigrationTests.swift`, `DiaryQuotaAccountingTests.swift`; modify `DiaryDatabase.swift` and existing `DiaryDatabaseTests.swift`.

**Interfaces:** Freeze shared contracts, segment metadata and ownership links. Add `DiaryDatabase.migrateForPagedStorage(maximumBytes: Int) throws`; storage `user_version` 0 → 1 only when explicitly called at this stage. Add injectable `DiaryQueryDiagnostics` counters for decoded turn payloads, original photo bytes, complete reads/reconciles and query plans (no personal text). Fixture builds valid 100/10,000-exchange databases, equal times, nil-day segments, colliding photo IDs and failures. Own the seeded mutation generator and test-only `ChatHistoryFixture.completeReference(databaseURL: URL) throws -> DiarySnapshot` (full row assembly supporting ordinal gaps, including optional manifests/bindings) for the reference encoder; later tasks extend commands. This helper must not enter production paths.

**Quota oracle contract:** Tasks 3–5 each run at least 100 reproducible valid commands per fixed seed over the mutation families they introduce; their union covers all requested inserts/edits/deletes/replacement/mixed-batch/receipt/encoding edges **before Task 8**. After every successful transaction compare incremental counters to `JSONEncoder().encode(completeReference).count` in tests only; after every failure compare stored data and counters to the pre-transaction state. Record seed/operation index/command on failure. Task 3 also owns `quotaJustUnderAtAndOverLimitPreservesRollbackCounters`: for the same candidate result of size N on fresh identical initial stores that fit all three limits, test N+1, N and N−1, with other constraints valid. Task 15 repeats/extends this evidence after final integration, not first after activation.

- [ ] **1. Write failing migration tests.** Named cases: `migrationPreservesIdentityBytesAndLegacyDayEvidence`, `migrationIsIdempotentAndRollsBackOnFailure`, `legacyNilDaySegmentsRetainDatesWithoutCreatingDiaryDays`, `storageBudgetMatchesPortableEncoding`, `seededQuotaOracleCoversEncodingEdges`. Assertions:
  ```swift
  #expect(after == before) // explicit full snapshots, including photo bytes
  #expect(secondGeneration == firstGeneration)
  #expect(legacyDaysAfter == legacyDaysBefore)
  #expect(failedMigrationVersion == 0)
  #expect(accountedBytes == (try JSONEncoder().encode(before)).count)
  #expect(nilDaySegments.allSatisfy { $0.trackingDayID == nil })
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/DiaryMigrationTests`.
- [ ] **3. Implement migration and projections.** Add separate `coach_index` with unique immutable sequence (legacy ordinal then ID), captured metadata, pending state and segment ID; keep legacy ordinal for complete interchange ordering. Add indexed `(trackingDayID, sequence)`, `(displayLocalDate, lastSequence, segmentID)` lookups, record-source/consumer links and parent photo content tokens. Backfill contiguous runs from captured active-day evidence; nil-day runs use persisted capture local date/timezone as inferred labels only, never resolved meal dates or label-matched DiaryDay associations. Backfill in bounded batches with no image decode. Maintain exact portable-encoding quota contributions/counters, including base64, escaping and array separators; permit bounded streaming during one-time accounting. The oracle uses fixed seeds `42`, `20261018`, `0xC0FFEE`, records seed/operation index on failure, and covers Unicode/quotes/backslashes/newlines, optional fields, finite valid numeric/date edges, base64 lengths modulo three and zero/one/many separators. Mint tokens on byte replacement; rebuild generation/tokens on restore. Validate relationships/counts and roll back disk/full/malformed failures atomically. Do not wire automatic migration yet.
- [ ] **4. Run GREEN:** migration, quota oracle and `DiaryDatabaseTests`; inspect indexes and verify no image decode during migration. Complete reference encoding is test-only or explicit interchange, never an ordinary mutation strategy.
- [ ] **5. Commit reviewed files:** `feat: add versioned conversation metadata`.

## Task 2: Indexed pages, direct seeks and day previews

**Files:** Create `DiaryDatabaseQueries.swift`, `ios/MivuTests/CoachPagingTests.swift`; extend timeline models/fixture.

**Interfaces:** `DiaryDatabase.coachPage(_ request: CoachPageRequest, expectedProfileID: UUID) throws -> CoachPage`; `coachDays(before: CoachDayCursor?, expectedProfileID: UUID) throws -> CoachDayPage`; `coachSegments(displayLocalDate: String, before: CoachDayCursor?, expectedIdentity: CoachTimelineIdentity) throws -> CoachDayPage`. The last is an indexed, exact date-label filter over segment metadata, including nil-day segments, with matching cursor scope. Public store wrappers are connected in Task 8.

- [ ] **1. Write failing tests:** `keysetPagesCoverEqualTimestampTurnsOnce`, `oldestDayAndSourceSeekAreIndexed`, `emptyDayIsNotNearestDay`, `foreignAndRestoredCursorsAreRejected`, `diaryDaySeekUsesFirstExchangeAcrossAllSegments`, `repeatedDisplayDatesRetainDistinctSegmentTargets`, `datePickerFindsLegacySegmentWithoutTrackingDay`:
  ```swift
  #expect(page.exchanges.count <= 20)
  #expect(Set(allIDs).count == allIDs.count)
  #expect(allIDs == expectedSequenceIDs)
  #expect(dayPage.rows.count <= 30)
  #expect(metrics.turnPayloadsDecoded <= 20)
  #expect(metrics.originalPhotoBytes == 0)
  #expect(dayTargetID == allAssignedSegments.min(by: { $0.firstSequence < $1.firstSequence })?.firstExchangeID)
  #expect(legacyDateRows.contains { $0.trackingDayID == nil && $0.firstExchangeID == legacyTurnID })
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/CoachPagingTests`.
- [ ] **3. Implement exclusive keyset queries.** Ascending display order, bounded around-turn window and small neighbor metadata. `.atDay(id)` means first exchange across all segments with that exact tracking-day UUID, not a matching label. History rows keep separate repeated labels/segments; calendar lookup returns exact matching segment choices in pages of 30, zero means no-chat and one may route directly to its first turn. Never substitute nearest date. Preview/date lookup uses indexes, not transcript decoding; EXPLAIN QUERY PLAN asserts range/seek predicates. Return separate missing/no-chat outcomes and reject wrong profile/generation/filter cursors.
- [ ] **4. Run GREEN:** paging and migration suites with both fixture sizes, equal times/backward-clock sequences and page-edge dividers.
- [ ] **5. Commit:** `feat: query bounded conversation pages`.

## Task 3: Atomic targeted capture and status transactions

**Files:** Create `DiaryDatabaseMutations.swift`, `ios/MivuTests/CoachCaptureTransactionTests.swift`; modify `DiaryDatabase.swift`, `DiaryStore.swift`, `CoachModels.swift`, fixture/quota tests.

**Interfaces:** Private `DiaryDatabase.transaction<Value: Sendable>(expected: DiaryHead, maximumBytes: Int, _ body: (DiaryTransaction) throws -> Value) throws -> DiaryCommit<Value>`. `DiaryTransaction` owns head CAS, touched-row validation, quota deltas and row writes. Define shared payload/manifest/reconciliation types here and `captureCoachSubmission(_ payload: CoachSubmissionPayload, expectedProfileID: UUID) throws -> CoachExchangeSummary`, plus the reconciliation signature above. Existing capture/status adapters delegate to this boundary; do not activate production selection yet.

- [ ] **1. Write failing tests:** `captureAppendsWithoutReadingOrReplacingHistory`, `repeatedCaptureRetainsDateAndSequence`, `staleRemovedOrReplacedDatabaseRejectsCommit`, `quotaAndCommitFailureLeaveHeadAndRowsUnchanged`, `crashBeforeCaptureProducesNoAcknowledgementOrMutation`, `crashAfterCaptureBeforeSchedulingRecoversSameSubmission`, `acceptedIDRejectsChangedTextAttachmentOrContext`, `uncertainCaptureReconcilesWithoutDuplicateOrDraftLoss`, `diskFullAppendRollsBackWithoutLosingExistingPhotos`:
  ```swift
  #expect(retriedTurn.id == firstTurn.id)
  #expect(retriedCaptureContext == firstCaptureContext)
  #expect(unloadedTurnAfter == unloadedTurnBefore)
  #expect(metrics.completeReads == 0 && metrics.completeReconciles == 0)
  #expect(failedHead == originalHead)
  #expect(recoveredSubmissionID == submittedID && recoveredPhotoIDs == submittedPhotoIDs)
  #expect(acceptedCaptureCount == 1 && foodMutationsBeforeWorker == 0)
  #expect(savedAcknowledgementsBeforeCommit == 0)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/CoachCaptureTransactionTests`.
- [ ] **3. Implement targeted append/state change.** Short-lived connection + profile/epoch/file identity fence; BEGIN IMMEDIATE, head CAS, changed-row validation/quota, immutable manifest and next sequence, then commit before notification/scheduling. Compare exact manifest on repeated ID; never return success for changed input merely because ID exists. Derive content fingerprints once under bounded photo preparation, no duplicate stored BLOB. Profile revision/lineage can advance for status changes; business capture remains single. Reconciliation checks original attempt independently of the current edited composer. No full snapshot comparison or retry-clock reinterpretation. Extend seeded accounting with capture/text/state/receipt-field changes and failed-commit counter rollback.
- [ ] **4. Run GREEN:** new suite, quota oracle including `quotaJustUnderAtAndOverLimitPreservesRollbackCounters`, existing stale/removed/replaced database tests and `CompanionReceiptTests`; simulate restart with a fresh store at both capture boundaries, retain existing public path until cutover.
- [ ] **5. Commit:** `feat: persist targeted chat captures atomically`.

## Task 4: Targeted diary, meal, review and photo operations

**Files:** Modify mutation/query files, `DiaryStore.swift`, read models; create `ios/MivuTests/DiaryProjectionMutationTests.swift`; retain `DayTests`, `DiaryTests`, `DiaryReviewFixTests` coverage.

**Interfaces:** Database/store projection capabilities: `diaryReadModel(expectedProfileID: UUID) throws -> DiaryReadModel`, `diaryDay(id: UUID, expectedProfileID: UUID) throws -> DiaryDayReadModel`, `meal(id: UUID, expectedProfileID: UUID) throws -> MealReadModel`, `photoContent(_ reference: DiaryPhotoReference, expectedProfileID: UUID) throws -> Data`. Preserve existing day/meal/review public operation names and expected-revision parameters through targeted adapters. Photo-free day-history summaries use a bounded keyset query, not every detailed meal.

- [ ] **1. Write failing tests:** `projectionMutationPreservesUnloadedRecords`, `collidingParentPhotoIDsResolveExactly`, `staleReviewAndQuotaFailurePreserveCommittedMeal`, `backdatedRecordDoesNotActivateChatDay`, `deletingMealDoesNotTouchAnotherOwnersCollidingPhoto`, `deletingMealWithSurvivingProgressReceiptRetainsEvidence`, `explicitPhotoRemovalDoesNotRetainHiddenContent`, `seededMealPhotoMutationsMatchReferenceAccounting`:
  ```swift
  #expect(activeDayAfter == activeDayBefore)
  #expect(oldMealAfter.items == oldCommittedItems)
  #expect(firstParentBytes != secondParentBytes)
  #expect(unrelatedPhotoTokenAfter == unrelatedPhotoTokenBefore)
  #expect(metrics.originalPhotoBytes == 0) // ordinary projection/mutation
  #expect(retainedConsumerPhotoBytes == originalSharedBytes)
  #expect(incrementalBytes == (try JSONEncoder().encode(referenceSnapshot)).count)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/DiaryProjectionMutationTests`.
- [ ] **3. Implement adapters.** Day/confirmation/capture/edit/move/delete/review/retry operations touch affected records only. Active-day change owns the latest empty segment; backdating does not activate it. Keep two byte owners and current cleanup except the verified shared-evidence gap: deleting a meal whose photos still serve a surviving progress receipt must atomically return that evidence to the originating `.coachTurn` owner(s), update references/tokens/accounting and then delete the meal. Reuse existing ownership transfer primitives, no third owner/global BLOB architecture. Explicit photo removal still removes its content and links; no hidden retention or cross-parent UUID deletion. Insert/replace/owner transfer mints appropriate tokens; metadata updates do not rewrite BLOBs. Keep pending proposals/unknown nutrition/source turn. Seed inserts/edits/deletes/replacement/transfer and collection/counter rollback, with no production full-reference encoding/scans.
- [ ] **4. Run GREEN:** new suite plus day/diary/review and existing photo ownership/deletion regressions.
- [ ] **5. Commit:** `feat: update diary records without full snapshots`.

## Task 5: Atomic progress and mixed Coach writes

**Files:** Modify `DiaryDatabaseMutations.swift`, queries/read models, `DiaryStore.swift`, `CoachModels.swift`, `CoachTools.swift`, `CoachManualEdits.swift`; create `ios/MivuTests/CoachBatchTransactionTests.swift`.

**Interfaces:** Add targeted implementation behind existing Coach mixed-batch entry point and existing weight/workout/goal/preferences methods. Internal batch returns `DiaryCommit<[CoachReceipt]>`; one transaction owns every touched record and receipt. Add bounded progress-range projection queries consumed in Task 8.

- [ ] **1. Write failing tests:** `mixedBatchIncrementsHeadOnceOrRollsBackEverything`, `replayedDeletedRecordIsNotResurrected`, `staleOrForeignProgressRejectsWholeBatch`, `crashAfterInferenceBeforeCommitLeavesNoPartialFood`, `crashAfterReceiptCommitBeforeAcknowledgementReplaysOnce`, `regeneratedTransportIDsCannotChangeCommittedOperation`, `sharedProgressPhotoSurvivesOneRecordDeletion`, `seededMixedBatchesAndReceiptGrowthMatchReferenceAccounting`:
  ```swift
  #expect(committedHead.revision == previousHead.revision + 1)
  #expect(receiptRevisions.allSatisfy { $0 == committedHead.revision })
  #expect(failedRecords == originalRecords && failedReceipts == originalReceipts)
  #expect(replayedMeal == nil)
  #expect(metrics.completeReads == 0 && metrics.completeReconciles == 0)
  #expect(replayedOperationKeys == committedOperationKeys)
  #expect(Set(recordApplicationsByOperation.keys) == Set(intendedOperationKeys))
  #expect(recordApplicationsByOperation.values.allSatisfy { $0 == 1 })
  #expect(receiptsAfterReplay == committedReceipts)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/CoachBatchTransactionTests`.
- [ ] **3. Implement whole-operation-set validation and atomic writes.** Commit records, normalized semantic bindings and receipts together, one batch revision. Match prior keys before applying; replay uses original committed result, while a deleted target retains its receipt and existing `notFound`/unavailable behavior without recreation. Reject changed arguments/retargeting under committed intent rather than assign retry keys. Preserve multi-date operations, stale/foreign guards and preference/goal checks. Shared progress references resolve the actual byte owner; workout deletion keeps photos while a surviving weight/meal/workout/pending link needs them, including mixed food/progress turns. Extend seeded tests with batches/progress/goal/preferences/receipts/rollback. Assert one business application independently of state-only revisions.
- [ ] **4. Run GREEN:** new suite, quota oracle, `CoachStoreTests`, `ProgressStoreTests`, `CoachManualEngineTests`, `CoachReceiptFeedbackTests`; fresh-store fault tests cover both sides of atomic commit and retain `workoutDeletionRetainsSharedProgressPhotosOnly`, batch failure and replay after deletion.
- [ ] **5. Commit:** `feat: commit mixed coaching operations atomically`.

## Task 6: Bounded workers and viewport-independent context

**Files:** Modify queries, `DiaryStore.swift`, `CoachEngine.swift`, `CoachTools.swift`; create `ios/MivuTests/CoachIndexedContextTests.swift`; extend existing flow/inference tests.

**Interfaces:** `nextPendingCoachTurn(includeWaitingForConnection: Bool, expectedProfileID: UUID) throws -> CoachWorkItem?`; `nextUnlinkedPendingSubmission(expectedProfileID: UUID) throws -> PendingSubmissionReference?`. Define these photo-reference-based work projections here. Retain existing context/tool call signatures, replacing their internals with indexed preceding-turn and grounded record reads.

- [ ] **1. Write failing tests:** `contextExcludesFutureQueuedTurnsAndIgnoresViewport`, `pendingWorkSurvivesEviction`, `historicalDateReadAndRelativeRetryStayGrounded`, `legacyRecoveryUsesIndexedUnlinkedSubmissions`, `restartRecoversEveryEligibleWorkState`, `committedReceiptsSurviveLostWorkerNotification`, `referencedMealEditedDuringInferenceRejectsStaleBatch`, `referencedMealDeletedDuringInferencePreservesTombstone`, `unrelatedEditDuringInferenceAllowsValidTouchedRecords`:
  ```swift
  #expect(contextTurnSequences.allSatisfy { $0 < processedSequence })
  #expect(contextTurnSequences.count <= 12)
  #expect(contextBeforeSeek == contextAfterSeek)
  #expect(retryResolvedDate == originalResolvedDate)
  #expect(metrics.completeReads == 0)
  #expect(referencedMealAfter == independentlyEditedMeal)
  #expect(staleBatchBusinessWrites == 0)
  #expect(recoveredReceiptKeys == originalReceiptKeys)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/CoachIndexedContextTests`.
- [ ] **3. Implement pending-state/sequence selection and legacy anti-join recovery using the recovery table.** Dialogue stays **12 preceding exchanges / 8,192 encoded bytes**, grounded meals **24,000 bytes**, total context **60,000 bytes**, with current truncation/omission references. Diary reads use current records; carry revisions and revalidate after awaits in Task 5 commit, rejecting stale/deleted targets instead of silently rebasing. Pending-meal refresh occurs before inference only. Recovery with receipts uses prior results and stable semantic keys, never fresh transport IDs or changed-target writes as substitute intake. Fetch originals only for chosen inference job with current vision limits; explicit dates outside 14 days use indexed reads. Retain captured-date semantics, clarification, multi-date intent, questions-vs-consumption and serving reuse. No historical snapshot or second processing pipeline.
- [ ] **4. Run GREEN:** new suite, `CoachFlowTests`, `CoachInferenceTests`, `CoachManualEngineTests`, `CoachStoreTests`. Suspend inference, independently edit/delete the referenced meal, then resume and verify zero stale writes; also test unrelated edit success. Fresh stores recover capture-before-scheduling and receipt-before-notification boundaries independently of viewport.
- [ ] **5. Commit:** `feat: ground coaching in indexed bounded context`.

## Task 7: Consistent complete export and protected replacement

**Files:** Create `DiaryExportCoordinator.swift`, `ios/MivuTests/DiaryExportConcurrencyTests.swift`; modify `DiaryArchive.swift`, `FolderBackup.swift`, `DiaryBackupSettings.swift`, `DiaryStore.swift`.

**Interfaces:** Define `DiaryExportRequest` (profile/head/epoch/generation/source file identity/optional backup generation) and `DiaryExportTicket` (protected clone URL, actual clone head, request ownership). `DiaryExportCoordinator.makeClone(_ request: DiaryExportRequest) async throws -> DiaryExportTicket`; `DiaryStore.exportRequest(expectedProfileID: UUID) throws -> DiaryExportRequest`. Serialize complete data from the clone; existing archive/public backup APIs adapt to these owners.

- [ ] **1. Write failing tests:** `oneLoadedPageExportsEveryTurnAndPhoto`, `concurrentExportIsOneConsistentRevision`, `deleteRestoreOrReplacementRejectsDelayedAcknowledgement`, `archiveVersionsOneTwoThreeRemainReadable`, `archiveRoundTripRetainsSubmissionManifestAndReceiptBinding`, `diskFullBackupRemovesPartialCloneAndLeavesLiveDiaryWritable`, `cancelledExportRemovesOwnedTemporaryFiles`, `failedSerializationOrProviderWriteDoesNotAcknowledgeBackup`, `validatedRestoreFailurePreservesLiveDatabase`:
  ```swift
  #expect(roundTrip.coachTurns.count == 10_000)
  #expect(roundTripPhotos == allOriginalPhotos)
  #expect(exportedSnapshot.revision == ticket.head.revision)
  #expect(obsoleteAcknowledgement == nil)
  #expect(deletedProfileRecreated == false)
  #expect(incompleteOwnedTemporaryFiles.isEmpty)
  #expect(liveSourceAfterFailure == liveSourceBeforeFailure)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/DiaryExportConcurrencyTests`.
- [ ] **3. Implement SQLite online-backup cloning, not raw file copy.** A background coordinator owns a read-only source connection and bounded backup steps into an isolated protected temporary database; DiaryStore remains the only live writer. Validate identity/epoch before/after steps and before final handoff; cleanup on cancellation. Read the actual consistent clone head, even if backup restarts on concurrent writes. Capture FolderBackup generation before scheduling, preserve deletion/high-water/lineage checks, and acknowledge only eligible actual clone revision. Serialization/Files calls never occupy the live writer for their duration. The version-1 complete assembler must accept ordinal gaps left by targeted deletion and emit correctly ordered complete arrays without renumbering live rows; use immutable sequence for chat. Restore validates complete input and builds/migrates a replacement database before the existing protected replacement boundary; new timeline generation rejects stale work. Keep current archive versions and size limits.
- [ ] **4. Run GREEN:** new suite and all `ArchiveTests`; prove a capture can commit while export/provider work is deliberately suspended. Inject clone/serialization/provider/replacement ENOSPC/cancellation, preserve valid source/output and confirm cleanup/stale-ack rules from the recovery policy.
- [ ] **5. Commit:** `feat: export consistent profiles without blocking capture`.

## Task 8: Activate storage and remove complete-graph hot paths

**Files:** Modify `DiaryDatabase.swift`, `DiaryStore.swift`, `DiaryViewModel.swift`, normal diary/progress readers from the file map, `CoachView.swift`, `CoachViewModel.swift`, `CoachEngine.swift`, `CompanionRuntime.swift`, and any `Connection/ChatGPTConnection.swift` snapshot caller found by inventory; create `ios/MivuTests/DiaryProjectionIntegrationTests.swift`.

**Interfaces:** Shipping `profiles() -> [DiaryProfile]` reads metadata only; `selectProfile(_ id: UUID) throws -> DiaryReadModel` and current refresh return projections. Expose Task 2/4/6 query wrappers through DiaryStore and `changes(expectedProfileID: UUID) -> AsyncStream<DiaryChanges>` with epoch-bound cancellation. Rename complete snapshot access to `snapshotForExport` and restrict to explicit interchange/testing callers.

- [ ] **1. Write failing integration tests:** `productionStartupCaptureAndWorkerRemainBounded`, `allMutationFamiliesPreserveUnloadedHistory`, `newLegacyWriterRefusesMigratedDatabase`, `productionProfileListingSelectionAndCorrectionAvoidCompleteReads`, `postActivationFailurePreservesMigratedDataForCompatibleRecovery`. Measure actual view-model/store/worker call paths on 100 and 10,000 valid exchanges:
  ```swift
  #expect(metrics.completeReads == 0 && metrics.completeReconciles == 0)
  #expect(startupMetrics.turnPayloadsDecoded <= 20)
  #expect(startupMetrics.originalPhotoBytes == 0)
  #expect(legacyWriterError == .invalidData)
  #expect(allUntouchedIDsAfter == allUntouchedIDsBefore)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/DiaryProjectionIntegrationTests`.
- [ ] **3. Perform the coordinated cutover only after its activation gate passes.** Rehearse the complete candidate wiring on migrated synthetic profiles through actual startup/listing/selection/send/correction/worker entry points before enabling automatic profile migration in the same integration commit. Require Task 1–7 migration/replay/quota/archive results and Task 11A renderer decision; inspect the snapshot-caller inventory, not just query counters. Replace cached graph with head/epoch and all targeted adapters/read projections, including progress and editors. Fence version-1 storage in the revised legacy writer; explicitly document older binary access as unsupported, not protected by that test. Preserve migrated data on post-activation failure and follow compatible-build/validated-archive recovery. Derive canSend/pending/companion/linked summaries from bounded metadata. Adapt current Coach rows to latest-page summaries pending Task 12. No fake complete snapshots or shipped alternate writer flag.
- [ ] **4. Run GREEN:** integration plus all affected unit suites; run the full `MivuTests` target once after cutover. Inspect diagnostics on real startup/send/worker paths and profile listing across multiple large profiles.
- [ ] **5. Commit:** `refactor: activate projection-based diary storage`. This is the first integrated storage candidate; camera/timeline UI is still pending.

## Task 9: Owned, lazy, bounded photo display

**Files:** Create `DiaryPhotoLoader.swift`, `ios/MivuTests/DiaryPhotoLoaderTests.swift`; adapt photo consumers in Coach, meal detail and progress in Task 12/13. Task 5 owns shared-progress deletion, this task owns cache/reference correctness across those consumers.

**Interfaces:** `DiaryPhotoLoader.thumbnail(for: DiaryPhotoReference, pixelSize: Int) async throws ->` an immutable Sendable image result, with MainActor adaptation. Define result here; original viewer uses Task 4 content API. One shared `PhotoWorkLimiter` actor limits total import/decode operations to two; Task 8 injects the same instance into display/import and existing worker image-preparation closure, rather than separate per-view limits. Inject reader/decoder for deterministic tests.

- [ ] **1. Write failing tests:** `cacheIncludesOwnerProfileContentAndSize`, `cancelledOffscreenDecodeDoesNotPublish`, `memoryPressurePurgesAndCostIsBounded`, `progressConsumerResolvesActualOwnerAndSurvivesSiblingDeletion`, `restoreInvalidatesContentTokensAndLateImages`:
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

## Task 10: Camera-first capture, composer ownership and durable submission

**Files:** Create camera/session/draft files from map and `ios/MivuTests/CoachCameraTests.swift`, `CoachAttachmentDraftTests.swift`; extract PhotoPreparation to its own file; modify PhotoCapture only for shared normalization, preserving MealComposer behavior.

**Interfaces:** `CoachCameraSession` owns authorization, start/stop/capture and interrupted/unavailable/retry state on a serial non-main executor. Define a narrow preview adapter to attach its private session to AVCaptureVideoPreviewLayer on MainActor, following the linked AVCam ownership pattern. `CoachAttachmentDraft` owns stable attachment IDs, ordering, text, submissionID, capacity reservations, profile/presentation generation and the original `uncertainAttempt` manifest in memory until reconciled; `importSelections`, `retake`, `remove`, `cancelPendingImports` are async/event operations with injected dependencies. Retake/edit never alters an already accepted payload.

- [ ] **1. Write failing tests:** `cameraIsFirstDestinationAndLibraryCancelResumesIt`, `draftImportsAreOrderedBoundedAndPartiallyRecoverable`, `lateProfileRestoreOrPresentationResultIsDiscarded`, `failedSaveRetainsDraftAndOperationIdentity`, `uncertainSaveThenEditedDraftReconcilesBeforeNewSubmission`, `relaunchLosesUnsentDraftButRecoversAcceptedSubmission`, `normalizedPhotoDropsLocationMetadataAndPreservesOrientation`, `lowStorageCaptureFailureRetainsTextAttachmentsAndSubmissionIdentity`:
  ```swift
  #expect(firstDestination == .camera)
  #expect(draft.attachments.count + reservedAttachmentCount <= 8)
  #expect(maximumConcurrentPhotoJobs <= 2)
  #expect(retrySubmissionID == originalSubmissionID)
  #expect(mealsCreatedBeforeSend == 0)
  #expect(relaunchedDraft.text.isEmpty && relaunchedDraft.attachments.isEmpty)
  #expect(acceptedSubmissionStillExists)
  #expect(normalizedGPSMetadata == nil && normalizedEXIFLocation == nil)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/CoachCameraTests MivuTests/CoachAttachmentDraftTests`.
- [ ] **3. Implement full-screen native camera with shutter/Close/Choose photos.** Camera permission only; no broad library access/latest-photo scan. Retain library/Close when camera denied/unavailable; pause covered/background session, resume on library cancel, release on dismissal and recover interruption visibly. Return selected/captured images to composer, no send. Retake replaces one stable attachment; retain successful partial imports/text. Freeze attachment identities and Task 3 manifest before send; reconcile uncertain capture before retry/new-ID edited submission, clear only matching draft. Draft retention covers this running session, not process restart. Reuse PhotoImport off MainActor under shared limiter; verify EXIF/GPS absence and orientation with tagged synthetic fixtures, check cancellation between expensive stages and owner/generation before publish. Synchronous ImageIO need not be instantly interruptible. Existing Data-based import has no app-owned photo tempfiles: keep it that way, clean task-owned export temporaries through Task 7, and handle capture/normalization/storage failures without false save acknowledgement. Restore focus without feedback replay; no unsafe session transfer/frame upload.
- [ ] **4. Run GREEN:** both suites, existing `CoachPhotoTests`/capture-options tests. Include oversize transfer rejection without publishing an attachment; current `loadTransferable(Data.self)` allocates selected bytes before the 40 MB check, so this does **not** prove bounded transfer peak memory. Task 15 must measure that separately, not count the thumbnail cache budget as an import guarantee. Hardware permission/preview/interruption remains a gate; injected tests do not claim it.
- [ ] **5. Commit:** `feat: add camera-first coaching drafts`.

## Task 11: Bounded timeline state and asynchronous paging

**Files:** Replace existing `CoachHistoryWindow.swift`; create `CoachTimelineViewModel.swift`, `ios/MivuTests/CoachTimelineTests.swift`; replace/extend existing `CoachHistoryWindowTests.swift`. Root owns early subtask 11A's temporary test-only view, launch-fixture wiring in `CoachUITestInference.swift`/`DiaryViewModel.swift`, `CoachScrollSpikeUITests.swift` and renderer-decision entry in the verification file. Coordinate those shared files before parallel work.

### Early subtask 11A: scrolling feasibility, after Tasks 1/2 and before Task 8

This is **planned future native work**, not an instruction to run it during this documentation revision. Use synthetic variable-height exchanges and an injected page source; no production store or completed mutation layer is needed. Adopt the same row/page/viewport contract below, not a parallel timeline state design.

- [ ] **A1. Write failing native spike cases:** `spikePrependPreservesStationaryAnchorWithinTwoPoints`, `spikeBidirectionalEvictionAndBackgroundReplyPreserveReader`, `spikeDynamicTypePreservesSemanticPosition`, `spikePagingPreservesAccessibilityFocus`. The anchor is the first visible stable exchange ID plus its measured top offset relative to the scroll viewport (not screen coordinates). Establish baseline after user dragging/deceleration ends, pause intentional scrolling during prepend/settle, and assert `abs(afterOffset - beforeOffset) <= 2` for that same ID. Test user scrolling separately; do not count its intended displacement as drift.
- [ ] **A2. Run RED:** `mivu_test MivuUITests/CoachScrollSpikeUITests`; confirm the intended anchor/focus assertion is exercised with the injected source, no real storage reads.
- [ ] **A3. Build the isolated SwiftUI prototype:** variable text heights, delayed thumbnail completion, six-plus pages with both-direction reloading/eviction, new replies while reading and pinned focused rows. Reuse page reservations/IDs; begin the eventual pure state component here as needed, with Task 11 completing it. Dynamic Type tests change font size intentionally and assert semantic exchange retention/reachability, **not identical pixel geometry**; accessibility tests assert focused exchange survives loads separately. If native APIs fail the measured stationary-anchor gate, investigate/test the narrow UIScrollView bridge fallback under the same state contract; do not build two production renderers speculatively.
- [ ] **A4. Run GREEN and record decision:** name the selected renderer, tested environment, named cases/results, measured worst displacement and remaining hardware validation. Native SwiftUI passes or the measured bridge is required; if neither meets the gate, Task 8 activation and Task 12 renderer commitment remain blocked. Simulator feasibility does not satisfy final physical scrolling/memory/latency acceptance.
- [ ] **A5. Commit reviewed spike/evidence:** `test: establish chat scrolling feasibility`. Keep temporary UI accessible only by synthetic test launch; Task 12 removes it and adopts the single measured renderer.

### Task 11 completion, after 11A

**Interfaces (also used by 11A):** Define `CoachViewportAnchor(rowID: UUID, offset: Double, focusedExchangeID: UUID?)`, viewport mode and explicit restoration instructions; offset has the viewport-relative meaning above. `CoachTimelineViewModel` injects `@Sendable (CoachPageRequest, UUID) async throws -> CoachPage`; methods `loadLatest()`, `loadEarlier(anchor:)`, `loadLater(anchor:)`, `seek(_:)`, `apply(_ changes: DiaryChanges)`, `setViewport(_:)`, `jumpToLatest()`, `invalidate(identity:)`. The pure window owns loaded/reserved pages and edge state; view model owns cancellation/generation.

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

**Files:** Modify CoachView/ViewModel/ActivityView; create CoachTimelineView/CoachReceiptView and `ios/MivuUITests/CoachHistoryUITests.swift`; extend receipt/activity unit suites. Adopt Task 11A's selected renderer, remove the temporary spike view/launch path and preserve its measurement regression coverage.

**Interfaces:** `CoachTimelineView` binds Task 11 state and reports measured viewport anchor; `CoachReceiptView` consumes typed committed receipt plus current record summary/revision and opens existing review/editor. Reuse existing draft/send/activity owners; connect Task 10 camera directly to camera icon.

- [ ] **1. Write failing UI tests:** `prependAndThumbnailArrivalPreserveMeasuredOffset`, `historySendKeepsViewportAndUsesCurrentDay`, `receiptShowsCommittedDateAndUnknownEstimates`, `cameraDraftDoesNotAutoSubmit`:
  ```swift
  XCTAssertLessThanOrEqual(abs(afterAnchorY - beforeAnchorY), 2)
  XCTAssertEqual(sourceTurnIDAfterCorrection, sourceTurnIDBeforeCorrection)
  XCTAssertTrue(app.buttons["Jump to latest"].exists)
  XCTAssertFalse(unknownNutritionWasRenderedAsZero)
  ```
- [ ] **2. Run RED:** `mivu_test MivuUITests/CoachHistoryUITests` with synthetic launch fixtures.
- [ ] **3. Implement the single renderer selected by Task 11A.** Stable exchange rows/dividers use LazyVStack if SwiftUI met the gate, otherwise the measured narrow UIKit bridge; retain one state contract and virtualization budget. Recheck stationary row-plus-offset restoration with production data rather than assume `scrollTo(id:)` is sufficient. Keep edge indicators fixed, thumbnails sized and insertion unanimated. Copy/select text, show active logging day near composer, retain draft and position while history open. Receipt uses committed target date, typed estimate/status and native Review/Edit, never prose-inferred success. Distinguish input durability, analysis, retry/review and backup. Background reply/history send offers latest action. Remove test-only spike launch/view after adopting its retained anchor/focus regression tests.
- [ ] **4. Run GREEN:** new UI suite plus existing Coach UI/activity/receipt suites, light/dark and late image/reply scenarios. Record anchor measurements in native tests.
- [ ] **5. Commit:** `feat: present continuous chat with stable scrolling`.

## Task 13: History sheet and Diary-to-chat navigation

**Files:** Create CoachHistoryView and `ios/MivuTests/CoachNavigationTests.swift`; modify DiaryRootView inside TodayView.swift, HistoryView, MealDetailView, CoachView/ViewModel; extend CoachHistoryUITests.

**Interfaces:** Root owns one optional identity-bound `CoachNavigationRequest` routed to the existing Coach instance. History row uses `.turn(firstExchangeID)`, including nil-day legacy segments. Calendar uses Task 2 `coachSegments(displayLocalDate:before:expectedIdentity:)`, presenting repeated matching segment choices without creating a day; zero matches is no-chat. Diary Open chat uses `.day(id)` across every assigned segment; meal link remains exact source turn. Keep local epoch/seek-generation validation and consume only matching requestID.

- [ ] **1. Write failing tests:** `oldestDiaryDayAndBackdatedMealOpenExactWindow`, `missingDayAndLegacyMealHaveHonestEmptyStates`, `profileChangedBeforeRouteCannotOpenForeignChat`, `legacyHistoryRowAndDatePickerOpenFirstTurnWithoutDay`, `repeatedDateChoicesRemainDistinct`, `restoredTimelineRejectsQueuedNavigation`, `profileRoundTripRejectsOldSelectionResponse`, `consumingOldRequestDoesNotClearNewRequest`:
  ```swift
  #expect(openedTurnID == backdatedMealSourceTurnID)
  #expect(routeIdentity == selectedTimelineIdentity)
  #expect(noChatDidNotOpenNearestDay)
  #expect(draftAfterNavigation == draftBeforeNavigation)
  #expect(staleNavigationPublications == 0 && newerRequestStillQueued)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/CoachNavigationTests MivuUITests/CoachHistoryUITests`.
- [ ] **3. Implement recent-first 30-segment preview paging, exact date-label lookup and Diary links.** Date labels do not collapse segments or fabricate day IDs. Selecting one of several date matches uses its persisted first turn; Diary day selects first sequence across its exact assigned segments, source link selects exact turn. No nearest-date fallback/intermediate transcript walk. Validate profile/timeline plus local epoch/request generation before query and before applying; A→B→A profile selection cannot revive old work, restore invalidates routes, consuming an old request cannot clear a newer one. Preserve distinct no-chat/missing/deleted/removed states, draft and scroll mode; highlight statically under Reduce Motion.
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

**Files:** Add `ios/MivuTests/CoachPerformanceTests.swift`, extend `DiaryQuotaAccountingTests.swift`, synthetic UI fixtures in `CoachUITestInference.swift` and history tests; update `docs/development/coach-chat-behavior.md`, complete the verification evidence file first created by Task 11A.

**Interfaces:** Reuse diagnostics/fixtures from Task 1, actual production call paths from Task 8 and anchor measurement from Task 12. Record exact source SHA, environment, dataset, command, named cases/counts/result bundle and blocked gates; no new runtime analytics dependency.

- [ ] **1. Write failing performance/regression gates:** `historyLengthDoesNotIncreaseDecodedStartupOrWorkingSet`, `seekAndPagingStayWithinDeclaredBounds`, `seededMutationSequencesMatchPortableAccountingAfterEveryCommit`, `quotaJustUnderAtAndOverLimitPreservesRollbackCounters`; add deterministic assertions before timing measurements:
  ```swift
  #expect(largeStartup.turnPayloadsDecoded <= 20)
  #expect(largeStartup.originalPhotoBytes == 0)
  #expect(residentAndReservedExchanges <= 100)
  #expect(decodedCacheCost <= 16 * 1024 * 1024)
  #expect(completeHotPathReads == 0)
  #expect(incrementalBytes == (try JSONEncoder().encode(referenceSnapshot)).count)
  #expect(rejectedStoredData == beforeRejectedStoredData && rejectedCounters == beforeRejectedCounters)
  ```
- [ ] **2. Run RED:** `mivu_test MivuTests/CoachPerformanceTests MivuTests/DiaryQuotaAccountingTests`; confirm deliberate unbounded-read/counter-drift injections are detected by the instrumentation/oracle, not silently excluded.
- [ ] **3a. Repeat/extend Task 1's seeded differential oracle after integration.** Run every seed across at least 100 mixed valid commands spanning all Task 3–5 families, optional/Unicode/escaped fields, finite numeric/date edges, base64 remainders, separators and receipt growth. Keep per-success reference-byte equality, per-failure data/counter equality and N+1/N/N−1 boundary cases; record seed/index/command on failure. These relevant checks were prerequisites to Task 8, not deferred until here. Production instrumentation still shows zero complete reference reads/encodes. Verify physical ENOSPC separately, including migration/export/archive cleanup.
- [ ] **3b. Complete measurement fixtures and repair any failing path.** Compare 100/10,000 exchanges holding non-chat contents constant, bounded valid synthetic photos and limits respected. Append from 9,999 to 10,000; assert over-limit failure preserves draft/data. On a physical iPhone measure cold/warm latest page, oldest seek, edge fetch/apply p95, stationary anchor drift, main-thread stalls, image work and resident memory. Separate Dynamic Type semantic/focus tests from unchanged-font pixel-offset tests. Measure large selected-photo transfer/normalization peak memory and cancellation, explicit exports and one-time migration separately, with repeated trials/device/thermal state. Retain ≤2 s/≤500 ms/≤200 ms/≤2 pt and all resource budgets; do not weaken them to pass. Hardware camera permission/denial/capture/library/retake/interruption/background and VoiceOver need observations. Record unavailable hardware or unmet memory/latency/scrolling gates as blockers, never simulator-proven acceptance.
- [ ] **4. Run final verification.** `mivu_test` for full native unit/UI scheme, serially, after final source changes; preserve nonzero named-test/count evidence. Run `rtk proxy python3 -m unittest discover -s scripts/ci -p 'test_*.py'` and shell syntax checks from CI contract. Have a fresh reviewer perform Ponytail Review and whole-spec/data-safety review; fix blocking findings and rerun affected checks. Recheck current commit, clean inputs and hook results. No 60/120-fps or device acceptance claim from simulator alone.
- [ ] **5. Commit docs/remaining reviewed changes:** `test: verify chat performance and migration safety`. Push with normal hooks, open a draft PR describing final behavior, migrations, native evidence and any device gates. Attach its URL to the task. This plan authorizes no merge, release publication or iPhone installation; those follow the owner's subsequent request.

## Verified repository findings used in this revision

Inspected against the unchanged product source at `73ae129`; these are source observations, not newly executed native tests.

| Concern | Evidence and resulting decision |
|---|---|
| Nil-day and repeated-label navigation | `ios/Mivu/Coach/CoachModels.swift:22–35`, `ios/Mivu/Diary/DiaryStore.swift:518–545`: captured activeDayID may be nil; a day may be reactivated. `.turn(firstExchangeID)` already expresses a segment destination; add indexed date-label resolution, not another seek variant. |
| Capture uncertainty / draft restart | `ios/Mivu/Coach/CoachViewModel.swift:63–80`, `ios/Mivu/Diary/DiaryStore.swift:642–659`: commit precedes refresh, and existing capture returns by ID alone. `DiaryViewModel.swift:4–9` draft is memory only. Add manifest reconciliation without promising persistent drafts. |
| Atomic receipts and live revisions | `ios/Mivu/Diary/DiaryStore.swift:930–1024`, `ios/Mivu/Coach/CoachEngine.swift:90–130`: whole-batch validation/commit already exists and must survive the refactor. Current record reads are live; test edits during inference, not historical snapshot reconstruction. |
| Missing progress photo owner | Disproved: `ios/Mivu/Diary/DiaryModels.swift:110–176`, `DiaryDatabase.swift:37–38,112–124`, `DiaryStore.swift:795–809,1332–1341`; weights/workouts do not own BLOBs, and food can transfer turn bytes into a linked meal. `CoachStoreTests.swift:564–576` covers shared weight/workout deletion. A genuine gap remains at `DiaryStore.swift:266–278`: meal deletion clears photo links without checking surviving progress receipts. Task 4 adds the corresponding evidence-preservation case using existing owners, while explicit photo removal keeps its deletion semantics. |
| Normalization / temporary files | `ios/Mivu/Diary/PhotoCapture.swift:31–60,125–148`, `DiaryViewModel.swift:327–345`, `ios/Mivu/Analysis/ResponsesClient.swift:132–186`: bounded JPEG/vision copies, generation checks, size guards and memory-based request serialization exist; no app-managed photo tempfile pipeline was found. Metadata absence, off-main normalization, transfer peak memory and cross-profile/restore cancellation need evidence. Export clone temporaries are new and explicitly owned in Task 7. |
| Older binary honors fence | Disproved: `ios/Mivu/Diary/DiaryDatabase.swift:9–41,134–175` never checks user_version today. The revised writer fence is necessary but cannot retroactively protect access by that binary; use the compatible-build recovery policy. |

## Compact risk register

| Failure mode | Potential impact | Owner | Mitigation | Required evidence |
|---|---|---|---|---|
| Label used as identity or stale route applied | Wrong historical conversation/profile | 1/2/13 | Distinct segment/day identities, exact turn route, generation/epoch fences | Named nil-day, repeated-date, date-picker, restore and A→B→A tests |
| Capture/reply acknowledgement lost | Duplicate intake or lost edited draft | 3/5/6/10 | Immutable accepted payload, reconcile uncertainty, semantic receipt replay | Fault injection before/after capture and record/receipt commit; one business application/key |
| Referenced meal changes during inference | Newer corrections overwritten | 5/6 | Current grounded reads, touched-record revision revalidation | Suspended inference with referenced edit/delete and unrelated-edit control |
| Incremental quota drift or real disk shortage | Invalid growth, failed save, partial artifacts | 1/3–5/7/15 | Seeded reference oracle, exact boundaries, atomic rollback, owned cleanup | Every-commit byte equality, failed-counter equality, ENOSPC clone/migration/archive tests |
| Unstable virtualized scroll / large image transfer | Jumps, focus loss, memory/latency failures | 9/10/11A/11/12/15 | Early measured renderer decision, bounded reservations/decodes, transfer profiling | ≤2 pt stationary prepend, Dynamic Type/focus tests, physical memory/latency/scroll traces |
| Shared content deleted or late image published | Missing progress evidence or foreign image | 1/4/5/9/10 | Verified two-owner graph, surviving-link deletion rules, content/identity tokens | Shared weight/workout, parent collisions, replace/restore/profile callback and EXIF tests |
| Cutover/export recovered with stale data or old binary | Lost post-migration captures, stale indexes, resurrected deletions | 7/8/15 | Activation checklist, complete consistent export, stale-ack fences, compatible-build recovery | Actual hot-path inventory/metrics, archive roundtrip/race tests; older-build access explicitly unsupported |

## Plan review and handoff

Two subagents inspected navigation/storage compatibility, submission recovery and photo evidence; the author integrated the findings and self-reviewed the approved spec, shared types, dependencies, test/file ownership, all five Review Focus cases and scope. This revision changes only this plan. It preserves the 15 primary tasks, selected execution method, one writer/cutover/fence, archive formats, budgets and delivery restrictions. New 11A is an early owned subtask, not a second production renderer. Documentation validation covers structure, links, recipe and whitespace; no planned migration, spike, native test, deployment or installation has run for this revision.

The owner already chose subagent-driven execution. Stop at this updated plan for review. No unresolved product choice requires a new feature or storage architecture; the renderer selection and all fault-injection/native/device acceptance remain future verification gates. Hardware unavailable during execution is a recorded blocker. No product/test code, migration activation, simulator spike, deployment, installation, merge or release is authorized by this documentation revision.
