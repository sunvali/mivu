# Reliable Food Entry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct shared quantity editing, preserve new-profile local dates, make Diary paging reversible, and support atomic offline numeric food creation/append with ongoing Coach/manual editing.

**Architecture:** Extend the existing owned SQLite transactions and shared ingredient correction helper. Keep one bounded history page in its own small view model, and persist immutable manual acceptance alongside the original saved submission; native forms and Coach use the same item mutation primitives.

**Tech Stack:** Swift 6, SwiftUI/UIKit, SQLite3, Foundation/CryptoKit, existing Lottie and subscription-backed connection; native iPhone app for iOS 26 and newer.

**Spec:** [Approved reliable-entry design](../specs/2026-10-19-reliable-entry-design.md), approved 2026-10-19; parent [roadmap](../specs/2026-10-19-diary-upgrades-roadmap.md).

## Global Constraints

- "Coach must be able to read and edit every resulting record through the same shared rules."
- "It preserves existing accepted capture, ownership, revision and receipt contracts."
- "Supported keys are exactly `kcal`, `protein`, `carbs`, `fat`; reject other keys at the boundary."
- "No density-based conversion between mass and volume, and no inferred conversion between a count/serving and mass/volume."
- "No connection, lookup key or model response is required."
- "A failed commit must not leave an invented empty day."
- "No fake conversation turn is created solely to supply a receipt."
- "Keep one resident page of at most 30 day summaries."
- "Write portable archive envelope version 4 and keep reading versions 1 through 3 as legacy submissions without verified manual acceptance."
- "This delivery introduces no new table and does not advance the physical SQLite version merely for an optional JSON field."
- "No third-party dependency, provider or billing change is needed."
- Preserve English LTR, Precision Glass, existing artwork, Dynamic Type, VoiceOver and 44-point targets. Native UI changes require full local unit/UI verification. All native jobs are serial and use XcodeBuildMCP.
- Never put credentials, personal food data or token responses into tests/evidence. Never mention codex or ai in commits or pull requests.

## Review Focus

1. Explicit totals equal to the previous value must still override scaling; zero-quantity edits must not invent a new basis. Task 2 owns arithmetic, parser and native-input regressions.
2. Retrying an accepted append after edits, moves, deletion or restoration must not reapply it or mistake today's revision for its original acceptance. Tasks 4–6 own hash, transaction and UI recovery regressions.
3. A stale profile/day decision or a quota failure must leave the diary, active day and conversation boundary unchanged. Tasks 1, 5 and 6 own these assertions.
4. A cancellation-insensitive history read must not replace a new filter/profile or create parallel paging reads. Task 3 owns continuation-controlled tests.
5. Native form dismissal, refresh failure and largest text must not lose a draft, obscure Save, or falsely acknowledge persistence. Tasks 6 and 7 own native journeys and result evidence.

## Workspace, ownership and test recipe

Planning checkout: `/Users/yaakovkhodorkovski/Documents/ChatGPT/AI food log app using chatgpt subscription/mivu-coach-work`, branch `feature/diary-upgrades`. Native baseline is `5a6342146d5e773f71a51b9e9da9eff35b5edb2f`; documentation commit `4e2f07d` does not change native inputs. Recheck branch/status before execution. Use the worktree skill at execution, preserve unrelated work, and do not depend on the enclosing empty repository for worktree creation.

The owner selected parallel subagents. Start Tasks 1 and 3 concurrently. Task 2 starts after Task 1 because both touch `DiaryModels.swift`; Task 4 starts after Task 2's shared-file integration. Task 5 follows Task 4 and Task 2. Task 6 follows Tasks 3 and 5, then Task 7. A free agent may inspect fixtures or review a completed independent task, but cannot edit another owner's files. Serialize integration into `DiaryStore.swift`, `DiaryModels.swift`, `DiaryDatabaseMealMutations.swift` and `HistoryView.swift`. No agent independently runs a build/test/simulator command; the integrator runs requested checks and shares results.

Before the first native check, call XcodeBuildMCP `session_show_defaults`, confirm this project/scheme/destination, and discover CLI arguments with `--help`. `iPhone 18 Pro` / iOS 27 is available on the planning host; confirm availability at execution. Use explicit paths and locked packages. The focused recipe is:

```sh
mkdir -p build/verification/2026-10-19-reliable-entry
rtk proxy xcodebuildmcp simulator test \
  --project-path "$PWD/ios/Mivu.xcodeproj" --scheme Mivu \
  --simulator-name 'iPhone 18 Pro' --use-latest-os \
  --derived-data-path "$PWD/build/verification/2026-10-19-reliable-entry/DerivedData" \
  --extra-args '-parallel-testing-enabled' 'NO' '-disableAutomaticPackageResolution' '-onlyUsePackageVersionsFromResolvedFile' '-only-testing:MivuTests/SUITE' \
  --output json
```

`SUITE` is replaced by the exact suite named in a task; this is the only command parameter the task supplies. For XCTest UI methods replace the selector with `-only-testing:MivuUITests/CLASS/METHOD`. Give each recorded run a distinct result-bundle path via `--extra-args '-resultBundlePath' ABSOLUTE_PATH` alongside the other arguments. A check passes only with nonzero discovered cases, zero failures and confirmed result status; warnings and skips are recorded separately. Compile errors from incomplete signatures do not count as the meaningful red regression. Do not overlap jobs or rerun an unchanged green suite without a new concern.

## Task 1: Device-derived profile timezone

**Files:** Modify `ios/Mivu/Diary/DiaryModels.swift`, `ios/Mivu/Diary/DiaryViewModel.swift`; create `ios/MivuTests/ProfileTimezoneTests.swift`; update time-sensitive fixture constructors in existing diary/day/progress/Coach suites only where they relied on the old default.

**Interfaces:** `DiaryProfile.timeZoneID` defaults to `TimeZone.current.identifier`. Add the trailing defaulted `deviceTimeZone: @Sendable () -> TimeZone = { .current }` initializer dependency and private property to `DiaryViewModel`; both production profile-creation paths read it once per new profile and pass its identifier. Existing init call sites remain valid. `DiaryPreferencesDraft` uses the current timezone only when no saved profile exists.

Test names and core assertions (the persisted profile is `saved`, and `zone` is each injected identifier):

| Test | Assertion |
| --- | --- |
| `namedAndDefaultProfilesCaptureInjectedTimezone` | `#expect(saved.timeZoneID == zone)` for Los Angeles and Tokyo |
| `profileDefaultUsesDeviceTimezone` | `#expect(DiaryProfile(name: "Synthetic").timeZoneID == TimeZone.current.identifier)` |
| `newProfileDoesNotRewriteExistingCalendarContext` | `#expect(reopened.timeZoneID == "Asia/Jerusalem")`; original day/turn values remain equal |

- [ ] Write `ProfileTimezoneTests` for injected `America/Los_Angeles` and `Asia/Tokyo`: named and default-profile creation persist the injected identifier. Assert plain `DiaryProfile(name:)` equals the current device zone. Export/reopen an explicitly Jerusalem-zoned existing profile and verify its zone, day labels and accepted capture context are unchanged after creating another profile in a different zone.
- [ ] Run `ProfileTimezoneTests` with the focused recipe; establish the old Jerusalem default failure before changing behavior. If an added initializer parameter is needed to compile the test, add only the injectable default seam first and observe the incorrect saved zone.
- [ ] Update the default/creation paths and nil-profile preference fallbacks. Do not migrate saved profiles or listen for travel to rewrite them. Pin calendar-dependent fixture zones explicitly instead of changing expected dates.
- [ ] Run `ProfileTimezoneTests`, `DiaryPreferencesDraftTests`, `DiaryFlowTests`, `DayTests`, `ProgressStoreTests`, then review results. Run other fixture suites only if their calendar expectation changes or the full final run identifies a failure.
- [ ] Commit the complete task: `fix: initialize new diaries in the device timezone`.

## Task 2: Correct quantity/unit semantics through every edit path

**Files:** Create `ios/MivuTests/DiaryAmountEditTests.swift`; modify `DiaryDatabaseMealMutations.swift`, `DiaryStore.swift`, `DiaryModels.swift`, `MealDetailView.swift`, `Coach/CoachManualEdits.swift`, `CoachTools.swift`, `CoachWriteFingerprint.swift`, `DiaryDatabaseCoachMutations.swift`, `CoachViewModel.swift`. Tests also touch existing `CoachManualEngineTests`, `CoachBatchTransactionTests`, `CoachEditParityTests` and the direct-caller suites listed below.

**Interfaces:** Make the mask required, without a compatibility inference fallback:

```swift
func diaryCorrectedItem(_ item: FoodItem, previous: FoodItem,
                        explicitNutrients: Set<String>) throws -> FoodItem
// Add required explicitNutrients: Set<String> to existing store/database/
// transaction editItem signatures, retaining defaults for unrelated arguments.
// Add the same associated value to CoachManualEdit.item before original.
// FoodItemEditor.save becomes (FoodItem, Set<String>) async -> Bool.
```

Add `DiaryError.invalidAmountUnitChange` with: “Enter or clear each known nutrient when changing to an unrelated unit.” Native errors use the existing LocalizedError path; Coach's error mapping must expose it too. A private `diaryUnitConversion(from:to:) -> Double?` returns previous units per edited unit: g→kg is 1,000; kg→g is 0.001. Use exactly the aliases and unit families in the spec; unchanged arbitrary labels remain ratio 1 without rewriting stored labels.

Core named regressions, with `result` returned by the shared helper for the inputs in the step matrix:

| Test | Assertion |
| --- | --- |
| `supportedMassConversionsUsePhysicalQuantity` | `#expect(result.nutrition.kcal == 2_000)` for100g/200→1kg |
| `equalExplicitTotalOverridesScaling` | `#expect(result.nutrition.kcal == 160 && result.nutrition.protein == 40)` |
| `explicitNullClearsWhileOtherNutrientsScale` | `#expect(result.nutrition.kcal == nil && result.nutrition.protein == 40)` |
| `zeroRetainsAndConvertsCompatibleBasis` | `#expect(result.nutrition.kcal == 200)` after the full zero/conversion sequence |
| `legacyCorrectionReceiptReplaysWithoutRecalculation` | `#expect(replayed == originalReceipt)` and `#expect(afterRevision == beforeRevision)` |

- [ ] Add the arithmetic regression first using the current helper: 100 g / 200 kcal → 1 kg must yield 2,000; observe the existing 2-kcal failure in `DiaryAmountEditTests`. Add the intent-aware signature and mechanically migrate callers only as needed to compile subsequent cases.
- [ ] Pin the full behavior matrix in `DiaryAmountEditTests`: 2 pieces / 160 kcal / 20 protein → 4 gives 320/40; explicit kcal160 gives160/40; explicit kcal nil givesnil/40. 250 ml /125 kcal →1 l gives500. Trimmed/case-folded aliases convert; unchanged “large bowl” scales. Serving→g with one of two known totals omitted fails; supplying kcal240 and clearing protein at150g gives240/nil and1.6 kcal/g. Mass→volume fails without all known keys. Reject unsupported intent keys and changed values whose keys are absent.
- [ ] Implement per-component scaling then explicit overlays. Retain source/reference/uncertainty for untouched values; explicit values/nulls use user provenance. At positive quantity derive final basis. At zero retain converted basis only for untouched components; explicit totals at zero clear their basis component. Pin 100g/200→0g→0kg→0.1kg restoring200, and a basisless known zero-quantity component requiring an explicit replacement before going positive. Incompatible unit changes discard all old-unit basis.
- [ ] Thread masks through both saved/review branches and Coach validation/application. `correct_item` passes `[]`; `edit_item` takes the supplied nutrient row keys, including equal-valued/null fields. Native nutrient Binding setters track touched keys; amount/unit edits and initialization do not touch them. Use shared item bounds (quantity≤100,000; known nutrients0...10,000,000) and remove the smaller native nutrient cap.
- [ ] Preserve existing fingerprint JSON shape: direct manual-item writes serialize explicit keys under existing nutrient keys, with nulls; no unconditional new version/mask field. Parsed writes retain their original patchKey path. Pin old quantity-only fingerprint/receipt replay, same-value-vs-omitted differences and whole-batch rollback on an invalid conversion. Never validate/recalculate a previously committed operation before receipt lookup.
- [ ] Migrate direct test callers in `DiaryTests`, `CoachStoreTests`, `CoachCorrectionJourneyTests`, `DiaryProjectionIntegrationTests`, `DiaryQuotaAccountingTests`, `CoachFlowTests`, `CoachBatchTransactionTests`, `DiaryProjectionMutationTests`, `CoachRecoveryReviewTests`, `CoachIndexedContextTests`: quantity-only uses `[]`, supplied nutrition uses exactly its keys. Do not replace assertions or weaken ownership/replay checks.
- [ ] Run `DiaryAmountEditTests`, `CoachManualEngineTests`, `CoachBatchTransactionTests`, `CoachEditParityTests`, `CoachCorrectionJourneyTests`, `DiaryTests`. Add a native editor case that changes2→4, re-enters kcal160, clears carbs and leaves protein untouched; assert160/nil/doubled protein after Save and relaunch. Commit: `fix: preserve nutrient intent during portion edits`.

## Task 3: Reversible bounded Diary paging

**Files:** Create `ios/Mivu/Diary/DiaryHistoryViewModel.swift`, `ios/MivuTests/DiaryHistoryViewModelTests.swift`; modify `HistoryView.swift`, `DiaryProjectionMutationTests.swift`. Task 6 owns the later manual-entry integration and UI fixture wiring in this view.

**Interfaces:** Define `DiaryHistoryScope(selection: DiarySelectionOwnership, localDate: String?, changeGeneration: UInt64)`, `DiaryHistoryPageStart` (`latest`, `before(DiaryHistoryCursor)`), `DiaryHistoryLoad(page: DiaryHistoryPage, coverage: [DayCompleteness:Int])` and `DiaryHistoryNavigation` (`earlier`, `newer`, `latest`). The main-actor observable owner injects:

```swift
init(load: @escaping @Sendable
     (DiaryHistoryScope, DiaryHistoryPageStart) async throws -> DiaryHistoryLoad)
func setScope(_ scope: DiaryHistoryScope?) async
func navigate(_ direction: DiaryHistoryNavigation) async
func retry() async
func invalidate()
```

Expose read-only `page`, `coverage`, `isLoading`, `errorMessage`, `canLoadEarlier`, `canLoadNewer`, `canLoadLatest`. Retain one page plus a stack of page-start cursors, one physical request slot, and the newest pending scope reload. Existing store/database keyset queries and limits are unchanged.

Name the principal tests `olderNewerAndLatestNavigateSeventyFiveDaysWithOneResidentPage`, `onlyOneRequestRunsAndRepeatedNavigationDoesNotAdvanceTwice`, `scopeChangeRejectsLatePageAndError`, `navigationFailurePreservesRowsAndRetryTarget`, and `exhaustedEdgesPerformNoQuery`. Assert `#expect(model.page!.days.count <= 30)`, `#expect(maxConcurrentLoads == 1)` and exact page IDs at each accepted transition; the fixture counters also assert `#expect(readCount == beforeReadCount)` for unavailable edges.

- [ ] Write continuation-controlled `DiaryHistoryViewModelTests` and confirm failure for the missing owner. Pin75 days as pages30/30/15; earlier/newer return exact IDs, Latest returns the first30 and resets navigation. Assert no more than30 resident days and no reads at exhausted Earlier/Newer or repeated Latest.
- [ ] Implement navigation state changes only after successful loads. Repeated input while loading is ignored. Failure keeps rows/start/cursor stack and retries the same target. Scope changes invalidate acceptance immediately; a cancellation-insensitive loader holds the physical slot until exit, then only the newest pending latest reload begins. Result/error acceptance requires request ID and the full scope to match.
- [ ] Pin late success and failure after selection, filter, timeline and generation changes; nil scope clears state. Different profile/filter/timeline clears visible rows; same-owner generation refresh can retain old rows as refreshing but disables their paging edges. Assert maximum concurrent loader count1 and that unchanged-scope detail return preserves filter/page with no read.
- [ ] Replace the two independent History tasks with one scope-driven task and the injected loader calling `diaryHistory(limit:30)` then `historyCoverage`. Add `earlierDiaryDays`, `newerDiaryDays`, `latestDiaryDays`, `retryDiaryHistory` identifiers, loading/retry feedback, native List semantics and focus. Add a real75-day keyset projection test with `completeReads == 0`, `completeReconciles == 0`, `originalPhotoBytes == 0`.
- [ ] Run `DiaryHistoryViewModelTests` and `DiaryProjectionMutationTests`; commit: `fix: make diary history navigation reversible`.

## Task 4: Portable manual acceptance and stable payload

**Files:** Create `ios/Mivu/Diary/ManualNutrition.swift`, `ios/MivuTests/ManualNutritionPayloadTests.swift`; modify `DiaryModels.swift`, `DiaryArchive.swift`, `ArchiveTests.swift` and quota tests for the added optional portable bytes. Depends on Tasks 1–2's shared-model integration.

**Interfaces:** Introduce `ManualNutritionOperation` (`create`, `append`). `ManualNutritionTarget` is Codable/Equatable/Sendable with cases `recorded(dayID:localDate:timeZoneID:)`, `active(dayID:localDate:timeZoneID:confirmPrevious:)`, and `newCurrent(dayID:localDate:timeZoneID:previousActiveDayID:)`. The new-current UUID is allocated when freezing the draft; active/recorded use the retrieved day UUID. Active verifies that it is still active; recorded never changes active-day state.

Define nonportable `ManualNutritionDayChoice` (`current`, `previous`, `newCurrent`, `recorded(UUID)`) for the user's day decision. Preparation is a bounded read: current requires the existing day assignment; previous requires its ambiguity choice; newCurrent reuses an already recorded matching current date/zone ID if one exists, otherwise allocates a UUID. This lookup is essential when a date has records but is not the active day. The resulting target, not the UI choice, is frozen into the payload.

`ManualNutritionPayload` is immutable Equatable/Sendable: `profileID`, `mealID`, `submissionID`, `operation`, `target`, `capturedAt`, `eatenAt`, `timePrecision`, `expectedMealRevision: Int?`, `items: [FoodItem]`. Create has nil expected revision; append has the retrieved positive revision. Native entry uses exactly one item; the shared item commit can handle the existing200-item bound.

`ManualNutritionAcceptance` is Codable/Equatable/Sendable: `schemaVersion` fixed1, `operation`, `payloadFingerprint`, `target`, `capturedAt`, `eatenAt`, `timePrecision`, `expectedMealRevision`, `enteredItemIDs`. Add `MealSubmission.manualAcceptance: ManualNutritionAcceptance? = nil`. Original `proposal.items` contains exactly the entered items/additions in entered-ID order; it is never rewritten to current meal values.

```swift
func validateManualNutritionPayload(_ payload: ManualNutritionPayload) throws
func manualNutritionFingerprint(_ payload: ManualNutritionPayload) throws -> String
func validateManualAcceptance(_ acceptance: ManualNutritionAcceptance,
    submission: MealSubmission, mealID: UUID, profileID: UUID) throws
```

Use named tests `canonicalFingerprintSeparatesUnknownAndZero`, `acceptanceReconstructsOriginalPayload`, `version4RoundTripRetainsManualAcceptance`, and `legacyEnvelopeCannotClaimVerifiedAcceptance`. Their core assertions are `#expect(try manualNutritionFingerprint(knownZero) != manualNutritionFingerprint(unknown))`, `#expect(decoded == originalSnapshot)`, and a thrown `DiaryError.invalidData` for a tampered/legacy-claimed acceptance. Construct the zero/unknown payloads from the same valid fixture, changing only that nutrient.

- [ ] Write `ManualNutritionPayloadTests`: valid create/append, missing known nutrient, known zero vs unknown, invalid IDs/association/revision/date/zone/nonfinite values and unchanged-payload hash stability. Freeze golden hashes for Unicode names, escaped units, fractional values and nil-vs-zero. Establish red tests before implementations.
- [ ] Implement validation using `validateItems`, positive native quantities and at least one known nutrient. Hash a versioned explicit object with sorted-key JSON and SHA-256: IDs, operation/target, clocks as reference-date seconds, precision, expected revision, and full original items. Canonicalize numeric negative zero to zero; encode unknown nutrient/expected revision as explicit null. Do not hash current meal state or infer source evidence. Pin schemaVersion and reconstruction from immutable proposal/metadata.
- [ ] Validate optional acceptance from `validateMealSubmissionFields`; require saved state, no photo IDs, matching submission/profile/meal/entered IDs and original base revision. Full snapshot validation checks the original target day/date/zone without comparing them to a later moved meal. Missing legacy acceptance stays readable and cannot prove a verified retry.
- [ ] Write archive envelope4, read1–3 without verified acceptance, and reject a legacy envelope claiming it. Test that tampered proposal/hash/association fails, old fixtures still decode, new data round-trips, and accounting includes acceptance bytes. Keep SQLite user_version1, export cloning, lineage and folder backup acknowledgement unchanged.
- [ ] Run `ManualNutritionPayloadTests`, `ArchiveTests`, `DiaryQuotaAccountingTests`; commit: `feat: preserve manual food acceptance evidence`.

## Task 5: Atomic manual create/append on existing transaction primitives

**Files:** Create `ios/Mivu/Diary/DiaryDatabaseManualNutrition.swift`, `ios/MivuTests/ManualNutritionTransactionTests.swift`; modify `DiaryStore.swift`, `DiaryDatabaseMealMutations.swift`, `DiaryDatabaseCoachMutations.swift`, and affected Coach/quota/archive tests. Depends on Tasks 2 and 4; no simultaneous edits to their shared owners.

**Interfaces:** `ManualNutritionSaveResult: Sendable` contains `acceptance: ManualNutritionAcceptance`, `submissionID: UUID`, `meal: MealReadModel`, `replayed: Bool`.

```swift
// DiaryDatabase extension, new focused file:
func saveManualNutrition(_ payload: ManualNutritionPayload,
    expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<ManualNutritionSaveResult>
// DiaryStore:
func prepareManualNutritionTarget(choice: ManualNutritionDayChoice, at: Date,
    expectedSelection: DiarySelectionOwnership,
    expectedProfileID: UUID) throws -> ManualNutritionTarget
func saveManualNutrition(_ payload: ManualNutritionPayload,
    expectedSelection: DiarySelectionOwnership,
    expectedProfileID: UUID) throws -> ManualNutritionSaveResult
func manualNutritionResult(for payload: ManualNutritionPayload,
    expectedSelection: DiarySelectionOwnership,
    expectedProfileID: UUID) throws -> ManualNutritionSaveResult?
// DiaryTransaction:
func commitSavedItems(mealID: UUID, items: [FoodItem],
    expectedRevision: Int) throws -> DiaryMeal
```

Extend `resolveDay(localDate:timeZoneID:at:newDayID: UUID? = nil)` to use a supplied planned UUID for insertion, and reject an existing conflicting UUID when one was supplied. Existing callers retain default behavior. Add `resolveManualNutritionDay(_:capturedAt:) throws -> TrackingDay` to the transaction extension; it validates the frozen decision and performs new-day activation/previous-day confirmation only inside the outer transaction. Recorded-day entry/append never activates a day.

The preparation and reconciliation store methods use matching bounded database reads in `DiaryDatabaseManualNutrition.swift`; they never call mutation-producing day resolution or load a complete snapshot. Reconciliation returns nil only when no acceptance/collision/tombstone exists; a legacy collision or deleted target throws. A matching verified acceptance returns original evidence plus current projection. Failed reconciliation leaves the draft frozen and retryable, rather than authorizing a new identity.

Name the first tests `createCommitsSavedMealAndOriginalEvidenceWithoutChatTurn`, `newDayAndMealRollbackTogetherOnQuotaFailure`, `appendPreservesExistingItemsAndIncrementsRevisionOnce`, `identicalAppendRetryAfterEditAndMoveReturnsCurrentProjection`, and `deletedTargetsCannotBeResurrected`. Assert `#expect(result.meal.revision == 1)` for create, `#expect(afterState == beforeState)` for rejected/rolled-back writes, and `#expect(replay.replayed && replay.meal.id == payload.mealID)` with no revision/count change for replay.

- [ ] Write transaction regressions using existing projection fixtures: create revision1 with saved original proposal/user provenance and no new Coach turn/index rows; append retains every existing item and increments revision once; blank macros remain nil while zero stays known. Observe the missing operation failures before implementation.
- [ ] Implement one `database.transaction` operation. Validate owner/payload, reject target tombstones, then resolve an existing submission before enforcing a new append's current revision/state. Matching verified acceptance/hash returns original acceptance plus current projection without mutation; changed payload, another parent or unverifiable legacy collision fails. A new append requires exact revision and no unresolved input.
- [ ] Resolve/freeze the accepted day within that transaction; insert a revision0 shell for create, commit complete resulting items through `commitSavedItems`, then save one `.saved`, `reviewFirst:false` original submission with immutable entered-only proposal/acceptance. Include quota/head/change publication in the same existing transaction. Do not call `captureProjection`, `applyAnalysis` or `appendManualCapture` as a separate phase or fabricate a source conversation.
- [ ] Route Coach's saved-food and manual-append item commits through `commitSavedItems`, preserving its outer review/photo/source/receipt logic and estimate provenance. Review-only branches remain proposals. Existing receipt lookup still precedes mutation validation/reapplication.
- [ ] Pin rollback of new day/meal/active segment/quotas on failure; preparation reusing an already recorded inactive current day without mutating it; stale selection and superseded active-day decision; stale/unresolved append; same-ID altered quantity/null/date/zone/item/operation/revision; tombstoned create/append; identical retries after reopen, later edit, move and restore. Replayed append returns current projection with unchanged revision and original evidence. Historical create leaves active day/segment unchanged. Reconciliation distinguishes absence, original acceptance, collision and deletion; assert bounded reads/no original photo decoding.
- [ ] Run `ManualNutritionTransactionTests`, `DiaryQuotaAccountingTests`, `ArchiveTests`, `CoachBatchTransactionTests`, `CoachCorrectionJourneyTests`, `DiaryProjectionIntegrationTests`; commit: `feat: save manual nutrition in one transaction`.

## Task 6: Native quick entry, shared edit parity and safe feedback

**Files:** Create `ios/Mivu/Diary/ManualNutritionView.swift`, `ios/MivuTests/ManualNutritionDraftTests.swift`, `ManualNutritionViewModelTests.swift`, `ios/MivuUITests/ManualNutritionUITests.swift`, and a DEBUG-only `ios/Mivu/Diary/DiaryHistoryUITestFixture.swift`; modify `DiaryViewModel.swift`, `MealComposerView.swift`, `HistoryView.swift`, `MealDetailView.swift`, `DiaryUITests.swift` and existing Coach parity fixtures/tests. Depends on Tasks 2–5. The project uses synchronized source groups; do not add manual pbxproj entries unless the build proves membership is excluded.

**Interfaces:** Define `ManualNutritionDraft` in the new native file, holding editable name/quantity/unit/nutrient strings and stable IDs; initialize quantity `1`, unit `serving`. `item() throws -> FoodItem` parses existing numeric conventions and applies Task4 validation; known native nutrient sources are `.user`, unknowns remain nil, reference “Entered manually”, uncertainty false for the supplied totals. This is user-entered evidence, not confirmed-label provenance.

```swift
// Native view, environment-owned model and source selection:
ManualNutritionView(model: DiaryViewModel, target: ManualNutritionTarget?,
    appendingTo: MealReadModel?, onSaved: @escaping (UUID) -> Void)
// DiaryViewModel:
func saveManualNutrition(_ payload: ManualNutritionPayload,
    expectedSelection: DiarySelectionOwnership) async -> ManualNutritionSaveResult?
```

The view resolves existing waking-day ambiguity using Task5 preparation before freezing payload/IDs. Recorded-day entry is date-only; append retains the existing meal's day/time/effective precision (`nil` legacy precision means exact without rewriting the original field). Freeze the planned new-day UUID, capture instant and acceptance only once. No edited draft may reuse a frozen accepted identity. Reconcile the original payload before allowing a changed draft to allocate new IDs after an uncertain outcome; failed reconciliation keeps that payload frozen. A known committed result followed by refresh failure is shown as saved-with-refresh-needed, not offered as another create.

Name draft/view-model tests `knownZeroAndBlankMacrosRemainDistinct`, `manualSaveFailureRetainsFrozenDraftAndEmitsNoFeedback`, `manualReplayDoesNotReplaySaveReaction`, and `obsoleteManualSaveCannotPublishOrDismissAnotherProfile`. After setting the draft name and kcal to0, assert `#expect(try draft.item().nutrition.kcal == 0)` and `#expect(try draft.item().nutrition.carbs == nil)`. For failed/replayed/obsolete operations assert the captured feedback and other profile's state remain equal to their pre-operation values.

- [ ] Add draft tests for required name/known nutrient/positive amount, zero-vs-blank, comma decimals, bounds and stable identities. Add view-model tests with injected store/read failures: no feedback on rollback, one feedback after fresh commit, none on replay, profile change cannot publish or dismiss, and a newer change generation cannot be overwritten by the returned older projection. Observe the intended failing assertions before behavior implementation.
- [ ] Implement the native form with Cancel/Save, existing typography/semantic surfaces, keyboard dismissal, dirty-draft confirmation and native error text. Saving disables repeated submission. Persist only via Task5; success uses its typed result and current owner. Post-commit refresh failure retains original acceptance for retry/load without reapplying food. Do not launch inference for direct manual nutrition.
- [ ] Add **Enter nutrition manually** within the existing composer and selected recorded-day experience, and **Add food manually** for a saved, resolved meal. Preserve a populated description/photo draft when opening or cancelling manual entry. On success show one saved-record link and never silently submit that other draft; retain the source sheet with an unsent-draft explanation if populated, otherwise use its existing onSaved/dismiss route.
- [ ] Emit existing capture/Pip save feedback only for a fresh durable commit and at most once per operation; replay does not react again. Current totals, pending count and source labels come from shared persisted projections. Do not mark a whole day complete or invent a weigh-in/conversation.
- [ ] Add paired behavioral tests: offline native create → Coach `get_meal`/edit/append → native edit → relaunch; assert same IDs, total/unknown values and preserved unrelated data. Reject a delayed stale correction. Native editable totals use user provenance while conversational estimates remain estimates. Reuse the Task2 native equal-value/clear regression.
- [ ] Add DEBUG-only75-day history fixture isolated by UI-test UUID/flag. `testDiaryOlderNewerLatestAndDateFilterRemainReversible` navigates all pages, returns Newer/Latest, filters a date, opens/returns from detail and retains the filter. Production launches never seed records. Add `ManualNutritionUITests` for offline Today create, historical date-only create without changing Today, append, invalid input/draft retention, light/dark and largest-text Save reachability/VoiceOver labels. Run focused new suites, then commit: `feat: add offline manual food entry`.

## Task 7: Diagnose the warning and verify the complete delivery

**Files:** Create `docs/verification/2026-10-19-reliable-entry.md`; modify only an evidence-identified layout owner and its regression if the warning is app-owned. Keep large artifacts under ignored `build/verification/2026-10-19-reliable-entry/`.

**Interfaces:** No new feature API. Consume the completed tasks and existing `scripts/ci/verify_results.py` evidence conventions; preserve source-bound results and unresolved gates.

- [ ] Inspect `/private/tmp/mivu-main-audit-tests.xcresult` and its captured summary-test log. The warning occurred when tapping `mealText` in both SummaryCards methods, before typing. Recover any existing emitting stack first. If absent, help-discover XcodeBuildMCP logging/debugging and reproduce once with runtime-issue capture on the same destination/appearance/keyboard sequence; do not guess private breakpoint names or add speculative layout changes.
- [ ] If a measured app-owned width/height or lifecycle violation is identified, write the smallest regression that fails at that owner, fix it, and rerun that case. If evidence cannot attribute it, record the warning as unresolved; absence of an app frame alone does not establish a system-only cause.
- [ ] Run all31 script checks with `rtk test python3 -m unittest discover -s scripts/ci -p 'test_*.py'`. Then run the native recipe without any `-only-testing` selector, retaining locked packages and serial execution, to cover the complete unit and UI suite. Confirm nonzero discovered counts and actual status, inspect failures at their owner, repair focused issues, and broaden again only when new changes justify it. Record intentional interactive-auth skips separately.
- [ ] Inspect native light/dark, largest-text/keyboard, historical/manual/Coach parity and history-navigation pixels. Confirm 44-point controls, VoiceOver names, preserved drafts and truthful unknown/source/receipt states. These checks do not establish real provider quality, physical camera/VoiceOver or hardware frame pacing.
- [ ] Run an independent whole-branch Ponytail Review after per-task reviews; resolve blocking findings and reverify changed owners. Record exact final SHA, environment, named runs/counts, artifact paths, warning attribution and remaining external/device gates in the verification record.
- [ ] Commit verification documentation, then use the finishing-development-branch workflow to prepare a reviewed draft PR with required Linux checks. Attach any created PR through the app tool. Do not merge, publish, sign, install to a physical phone or claim release acceptance from this plan alone. Commit/PR text must follow repository naming rules.

## Plan self-review and handoff

Coverage check: quantity/intents/conversions → Task2; timezone → Task1; manual immutable evidence/archive → Task4; atomic create/append/replay → Task5; native/Coach access and feedback → Task6; reversible bounded history → Task3; warnings, accessibility, full acceptance and exact provenance → Task7. All five Review Focus classes have owning regressions above.

This plan implements only the approved first delivery. Pip-led onboarding and personalized recommendations remain the next scoped design in the parent roadmap; no goal policy or onboarding-answer storage is smuggled into these tasks. The owner has already selected parallel subagent execution. Written-plan review is the remaining prerequisite before product implementation.
