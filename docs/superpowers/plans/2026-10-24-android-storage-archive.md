# Android Storage, Durable Capture and Archive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Android Mivu the iOS diary data model, a durable local store,
crash-safe capture, the iOS rules for applying analysis results, and archive
import/export that is proven compatible in both directions.

**Architecture:** Kotlin data classes mirror the iOS `DiarySnapshot` types at
`dd5e8c34`. JSON is produced by kotlinx.serialization configured to read and
write the iOS `JSONEncoder` defaults. One SQLite database per profile, built on
the platform `SQLiteDatabase` (no Room). It keeps rows the way iOS does
(`id, ordinal, parent, payload JSON, bytes`), plus a single `head` row for
revision and lineage. Every write goes through one
`transaction(expectedRevision)` that bumps the revision. Package
`com.yakov103.mivu.diary`. Analysis stays separate from meal calculations
(AGENTS.md).

**Tech Stack:**
- Kotlin and kotlinx.serialization-json. Justification: about 30 Codable
  types would otherwise be hand-written org.json, and this is the Kotlin
  standard serializer.
- Android `SQLiteDatabase` and `AtomicFile`.
- JUnit 4 (JVM tests for codec, model and validation; instrumented tests for
  storage).
- One iOS test-only addition (swift-testing) for golden fixtures.

**Spec:** [`docs/superpowers/specs/2026-10-23-android-app-design.md`](../specs/2026-10-23-android-app-design.md),
sections "Archive compatibility", "Durable capture and analysis" and "Backup
and restore".

## Global Constraints

- iOS baseline `dd5e8c34` is the authority for every field, rule and limit.
  The iOS sources are `ios/Mivu/Diary/DiaryModels.swift`,
  `ManualNutrition.swift`, `ios/Mivu/Coach/CoachModels.swift`,
  `DiaryArchive.swift`, `DiaryDatabase*.swift`; read them with
  `git show dd5e8c34:<path>`.
- JSON wire format (iOS `JSONEncoder` and `JSONDecoder` defaults):
  - `Date` is a Double, seconds since 2001-01-01T00:00:00Z.
  - `UUID` is written as an uppercase hyphenated string and read
    case-insensitively.
  - `Data` is standard base64 with padding.
  - Enums use their raw strings.
  - Nil optionals are omitted on write and absent on read.
  - Non-optional properties with defaults are always written.
  - Enums with labelled associated values are written as
    `{"case":{"label":value,…}}`, omitting nil labels.
  - Reading needs semantic equality with iOS, not byte equality.
- Archive envelope `{"format":"mivu-diary","version":4,"profileID":…,"snapshot":…}`.
  - Read versions 1–4; write version 4.
  - Maximum size is 350,000,000 bytes.
  - For versions below 4, a `manualAcceptance` is rejected.
  - Absent `goals`, `workouts`, `coachTurns`, `deletedWeightIDs`,
    `deletedWorkoutIDs`, `WeightEntry.revision` and
    `WeightEntry.timePrecision` decode to their iOS defaults.
- Every validation limit is copied from iOS `DiarySnapshot.validate` and
  `DiaryArchive.validate`.
- Save acknowledgement happens only after the database commit; photo bytes
  are stored in the same transaction. A capture is identified by its
  client-generated `submissionID`; a retry with the same manifest returns the
  existing capture, and a different manifest is rejected.
- Never restore stale data over deletions. Tombstoned IDs never come back.
- Synthetic inputs only, in tests and in fixtures.
- Local builds only. Commit as the owner; no tool or assistant names.

## Review Focus

1. **An archive that uses lowercase UUIDs, or a date with fractional
   seconds** → it imports, and every value is preserved exactly. (Task 2)
2. **A 300 MB archive** → imports without an out-of-memory error, because the
   file is streamed, not read into one string. (Task 5)
3. **The app is killed between saving a photo and committing its row** → no
   capture is acknowledged without its photo, and no orphan bytes are left.
   (Task 7)
4. **Analysis finishes after the meal was edited or deleted** → the edit
   stays, and the deleted meal stays deleted. (Task 8)
5. **Restoring an older archive over a newer diary** → refused as stale,
   with nothing changed. (Task 9)

---

### Task 1: iOS golden archive fixtures (iOS test-only)

**Files:**
- Create: `ios/MivuTests/ArchiveFixtureTests.swift`
- Create: `fixtures/archive/ios-v4-full.json`, `fixtures/archive/ios-v1.json`, `fixtures/archive/ios-v2.json`, `fixtures/archive/ios-v3.json`
- Create: `fixtures/archive/README.md` (3 lines: synthetic, how to regenerate)

**Interfaces:**
- Produces: `func syntheticFullSnapshot() -> DiarySnapshot`, a deterministic
  snapshot with fixed UUIDs and dates. It contains at least one of every
  type and enum case, including:
  - every `ManualNutritionTarget` case and every `CoachReply.Target` case;
  - photos of 3 bytes and a coach photo;
  - meal, weight and workout tombstones;
  - a goal, a weight from before revision 1, and a workout with sets;
  - a coach turn with a receipt, a manifest and a question;
  - a `nil` `about` on one profile field and a filled one elsewhere.

  These fixtures are the Android golden inputs.

- [ ] **Step 1: Write the test `fixturesMatchSyntheticSnapshot`.** For each
  fixture file:
  - `DiaryArchive.decode` gives `syntheticFullSnapshot()` for v4;
  - each of v1–v3 decodes to the v1–v3 projection: no `manualAcceptance`;
    v1 and v2 omit the progress keys.

  When the environment variable `MIVU_WRITE_FIXTURES=1` is set, the test
  first writes the files to the repo path, using `#filePath` to find the
  repo root.
- [ ] **Step 2: Generate the fixtures.** Run
  `MIVU_WRITE_FIXTURES=1 xcodebuild test -project ios/Mivu.xcodeproj -scheme Mivu -destination 'platform=iOS Simulator,name=<booted iOS 26+ device>' -only-testing:MivuTests/ArchiveFixtureTests`.
  Expected: PASS, and the four files are written.
- [ ] **Step 3: Check the fixtures without writing.** Re-run without the
  variable. Expected: PASS.
- [ ] **Step 4: Commit** `test(archive): add synthetic iOS golden archives`
  with Parity `archive` notes, and record the SHA, simulator and counts in
  `docs/verification/2026-10-24-android-archive.md`.

### Task 2: Swift-compatible JSON codec

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/SwiftJson.kt`
- Test: `android/app/src/test/java/com/yakov103/mivu/diary/SwiftJsonTest.kt`
- Modify: the version catalog and `app/build.gradle.kts` (kotlinx-serialization plugin and json)

**Interfaces:**
- Produces:
  - `val SwiftJson: Json` with `explicitNulls = false`,
    `encodeDefaults = true` and `ignoreUnknownKeys = false`;
  - `object SwiftDate : KSerializer<Instant>` (`java.time.Instant`; the
    2001 reference offset is 978307200 s, with sub-second precision kept);
  - `object SwiftUUID : KSerializer<UUID>` (writes uppercase);
  - `object SwiftData : KSerializer<ByteArray>`.

- [ ] **Step 1: Failing tests.**
  - `SwiftDate` decodes `0.0` as `2001-01-01T00:00:00Z` and `-978307200.0`
    as the Unix epoch;
  - `SwiftDate` round-trips `750000000.123456` within 1 µs;
  - `SwiftUUID` reads a lowercase id and writes it uppercase;
  - `SwiftData` round-trips the bytes `[0, 255, 47]` and accepts input
    containing `\/`;
  - a nil optional is omitted on write.
- [ ] **Step 2: Run** `./gradlew :app:testDebugUnitTest --tests '*SwiftJsonTest'`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): read and write the iOS JSON wire format`.

### Task 3: Diary domain model

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/DiaryModels.kt`, `CoachModels.kt`
- Test: `DiaryModelsTest.kt`, which reads the iOS fixtures from `fixtures/archive/` (test resources srcDir already includes `../../fixtures`)

**Interfaces:**
- Produces `@Serializable` Kotlin types with the same names and fields as
  iOS.
  - Diary types: `DiaryProfile`, `ProfileAbout`, `NutritionValues`,
    `FoodItem`, `MealPhoto`, `TrackingDay`, `MealSubmission`,
    `AnalysisOutput`, `ManualNutritionAcceptance`, `ManualNutritionTarget`
    (sealed, custom serializer), `DiaryMeal`, `WeightEntry`, `GoalRecord`,
    `WorkoutSession`, `WorkoutExercise`, `WorkoutSet`.
  - Coach types: `CoachTurn`, `CoachReceipt`, `CoachSubmissionManifest`,
    `CoachCaptureContext`, `CoachReply` (with a sealed `Target`),
    `CoachQuestion`.
  - The snapshot: `DiarySnapshot`.
  - Every enum with its iOS raw values, including `CoachClarification`;
    read its cases from iOS.
  - Defaults and absent-key tolerance exactly as iOS: only `WeightEntry` and
    `DiarySnapshot` tolerate missing keys.
  - Computed iOS properties are not serialized. Port only `totals` and
    `isSaved` if they are needed by Task 8; nothing else.

- [ ] **Step 1: Failing test** `decodesIosFullFixture`. Decode
  `snapshot` from `ios-v4-full.json` and assert one representative field per
  type, written out in the test. The values must include the enum
  associated-value cases and the photo bytes `[1,2,3]`.
- [ ] **Step 2: Failing test** `reEncodeIsSemanticallyEqual`. Encode the
  decoded snapshot, parse both JSON documents into `JsonElement`, and assert
  they are equal after normalizing UUID case and number representation.
- [ ] **Step 3: Run.** Expected: FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run.** Expected: PASS.
- [ ] **Step 6: Commit** `feat(android): port the diary data model`.

### Task 4: Snapshot and archive validation

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/DiaryValidation.kt`
- Test: `DiaryValidationTest.kt`

**Interfaces:**
- Produces:
  - `fun DiarySnapshot.validate()`, which throws
    `DiaryError.InvalidData(reason: String)`;
  - `fun validateArchiveManifests(snapshot)`;
  - `sealed class DiaryError : Exception` with `InvalidData`, `WrongOwner`,
    `StaleRevision`, `StaleArchive`, `NotFound`, `EmptyCapture`,
    `QuotaExceeded`.

- [ ] **Step 1: Failing tests.** One test per iOS rule family, each built
  from a valid fixture snapshot with one field broken. Every rule listed in
  the iOS `DiarySnapshot.validate` (`DiaryModels.swift:285-351`) and
  `DiaryArchive.validate` (`:84-106`) gets a test, named after the rule:
  - `schemaVersionMustBe1`;
  - `revisionRange`;
  - `profileNameLength`;
  - `languageEnOrHe`;
  - `liveIdsDisjointFromTombstones`;
  - `oneWeightPerDay`;
  - `photoBytesRange`;
  - `itemQuantityRange`;
  - `awaitingReviewNeedsProposal`;
  - `manualAcceptanceNeedsNewerRevision`;
  - `receiptCommittedRevisionRange`;
  - `manifestTextFingerprint`;
  - `attachmentsAtMost8`.

  Also test that the valid fixture passes.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** by porting the iOS rules one to one, with the same
  numeric limits.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): validate diaries like iOS`.

### Task 5: Archive envelope

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/DiaryArchive.kt`
- Test: `DiaryArchiveTest.kt`

**Interfaces:**
- Produces:
  - `object DiaryArchive` with
    `fun encode(snapshot: DiarySnapshot, out: OutputStream)`;
  - `fun decode(input: InputStream, expectedProfileID: UUID? = null): DiarySnapshot`.
    It streams with kotlinx `decodeFromStream`, enforces the byte cap with a
    counting stream, and the envelope and owner checks.

- [ ] **Step 1: Failing tests.**
  - All four iOS fixtures decode.
  - v1–v3 fixtures with a `manualAcceptance` injected → `InvalidData`.
  - `format` other than `mivu-diary`, or version 5 → `InvalidData`.
  - `profileID` not matching the snapshot, or the expected owner → `WrongOwner`.
  - A stream over the cap → `InvalidData`, without reading past the cap.
  - Encode then decode round-trips the full fixture.
  - Encoding writes `"version":4`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): read and write Mivu diary archives`.

### Task 6: SQLite diary store

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/DiaryDatabase.kt`
- Test: `android/app/src/androidTest/java/com/yakov103/mivu/diary/DiaryDatabaseTest.kt`

**Interfaces:**
- Produces: `class DiaryDatabase private constructor(...) : Closeable` with:
  - `companion fun open(context, profileID: UUID): DiaryDatabase`. The file
    is `filesDir/profiles/<PROFILEID>/diary.sqlite`, opened with
    `foreign_keys=ON` and `synchronous=FULL`.
  - `fun head(): Head` (`revision`, `lineage`, `profile`, `activeDayID`,
    `previousDayConfirmedAt`, `activeConversationSegmentID`).
  - `fun snapshot(): DiarySnapshot`.
  - `fun <T> transaction(expectedRevision: Long, body: (Tx) -> T): T`. It
    runs `BEGIN IMMEDIATE` and checks `revision == expected`, otherwise
    throws `StaleRevision`. It runs the body, then increments `revision`,
    appends a random UUID to `lineage` (keeping the last 255), and commits.
    Any throw rolls back.
  - `fun replaceAll(snapshot)`, used for import, which runs inside one
    transaction.

  Tables mirror iOS `id TEXT PRIMARY KEY, ordinal INTEGER, parent TEXT, payload BLOB, bytes BLOB`
  for `day`, `meal`, `submission`, `item`, `photo`, `weight`, `goal`,
  `workout`, `coach_turn`, `coach_photo`, `tombstone_meal`,
  `tombstone_weight` and `tombstone_workout`, plus a single-row `head`.
  Photo bytes live in `bytes`, and the JSON payload has empty `data`.

- [ ] **Step 1: Failing instrumented tests:**
  - `replaceAllThenSnapshotRoundTripsFixture`, using the iOS v4 fixture;
  - `transactionBumpsRevisionAndLineage`;
  - `staleExpectedRevisionThrowsAndChangesNothing`;
  - `bodyThrowRollsBack`;
  - `databaseFileIsInFilesDirIncludedInDeviceTransfer`, which checks the
    path against `data_extraction_rules` (database lives under `file`, so
    include `file` in device-transfer, as Task 2 of Plan 1 did).
- [ ] **Step 2: Run** `./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.diary.DiaryDatabaseTest`. Expected: FAIL.
- [ ] **Step 3: Implement.** Payloads are encoded with `SwiftJson`.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): store diaries in SQLite with revisioned transactions`.

### Task 7: Durable Coach capture and recovery

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/DiaryCapture.kt`
- Test: `android/app/src/androidTest/java/com/yakov103/mivu/diary/DiaryCaptureTest.kt`

**Interfaces:**
- Consumes: `DiaryDatabase.transaction`, `CoachTurn` and
  `CoachSubmissionManifest`.
- Produces:
  - `data class CoachSubmissionPayload(submissionID, text, attachments: List<MealPhoto>, context: CoachCaptureContext, pendingMealID: UUID?, pendingMealRevision: Int?, reply: CoachReply?)`,
    whose `init` validates exactly as iOS: at most 8 attachments, text at
    most 20,000 characters, non-empty text or at least one photo, photos of
    1 byte to 10 MB, and the pending pair either both set or both absent. It
    builds the manifest with SHA-256 fingerprints.
  - `fun DiaryDatabase.captureCoachSubmission(payload, expectedRevision): CoachTurn`.
    It is one transaction. An existing turn with an equal manifest is
    returned; an unequal one throws `StaleRevision`. The capture context
    must match the head.
  - `fun DiaryDatabase.reconcileCoachCapture(payload): Reconciliation`, one
    of `Absent`, `Accepted(turn)` or `ConflictingPayload`.
  - `fun DiaryDatabase.pendingCoachTurns(): List<UUID>` returns turns in
    the states `captured`, `waitingForConnection`, `waitingForNetwork`,
    `analyzing` or `needsRetry`, oldest first. This is the startup recovery
    scan.

- [ ] **Step 1: Failing tests:**
  - `captureIsAcknowledgedOnlyAfterCommit`, where a transaction failure
    injected after the photo insert leaves no turn and no photo row;
  - `retryWithSameManifestReturnsSameTurn`;
  - `retryWithDifferentTextIsRejected`;
  - `reconcileAfterUncertainFailure`;
  - `pendingScanFindsCapturedTurnsAfterReopen`, which closes and reopens
    the database to simulate process death;
  - `emptyCaptureRejected`;
  - `nineAttachmentsRejected`.
- [ ] **Step 2: Run** the instrumented class. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Add a real process-kill check.**
  - Write `scripts/android/kill_capture_check.sh`. It installs the debug
    app, starts a debug-only `CaptureProbeActivity`, which saves a synthetic
    capture and then sleeps. The script runs `adb shell am kill` during the
    sleep, relaunches the activity with the extra `verify=true`, and
    asserts that the logcat line `CAPTURE_PRESENT=1` contains no user data.
  - Put the activity in `src/debug`.
  - Run the script. Expected: `CAPTURE_PRESENT=1`.
- [ ] **Step 6: Commit** `feat(android): save Coach captures durably before analysis`.

### Task 8: Applying meal analysis without stale overwrites

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/MealAnalysis.kt`
- Test: `android/app/src/androidTest/java/com/yakov103/mivu/diary/MealAnalysisTest.kt`

**Interfaces:**
- Produces functions on `DiaryDatabase`, each mirroring the iOS function of
  the same name in `DiaryDatabaseMealMutations.swift` and
  `DiaryTransaction`:
  - `nextPendingMealSubmission(): Pair<UUID, UUID>?`;
  - `prepareAnalysis(mealID, submissionID)`;
  - `applyAnalysis(output: AnalysisOutput)`;
  - `acceptReview(mealID, submissionID, expectedMealRevision)`;
  - `deleteMeal(mealID, expectedRevision)`, which writes a tombstone;
  - `editMealItems(mealID, items, expectedMealRevision)`, which bumps
    `meal.revision`.

- [ ] **Step 1: Failing tests:**
  - `applyIsIdempotentWhenAlreadySaved`;
  - `cancelledSubmissionIsNotFound`;
  - `staleBaseRevisionAfterEditIsRejectedAndEditKept`;
  - `deletedMealStaysDeletedWhenLateResultArrives`;
  - `reviewFirstStoresProposal`;
  - `acceptReviewIdempotent`;
  - `tombstonedIdCannotBeInsertedAgain`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): apply analysis without overwriting edits or deletions`.

### Task 9: Archive export, import and restore rules, both directions

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/DiaryRestore.kt`
- Create: `fixtures/archive/android-v4-full.json`, produced by an Android test from the same synthetic content as Task 1
- Modify: `ios/MivuTests/ArchiveFixtureTests.swift` (add the import of `android-v4-full.json`)
- Test: `DiaryRestoreTest.kt` (JVM) and `ArchiveRoundTripTest.kt` (instrumented)

**Interfaces:**
- Produces:
  - `fun replacement(incoming: DiarySnapshot, original: DiarySnapshot): DiarySnapshot`,
    which follows iOS `DiaryArchive.replacement` and `isVerifiedSuccessor`:
    - the same owner, otherwise `WrongOwner`;
    - `incoming.revision >= original.revision`;
    - either equal, or a verified successor through the lineage;
    - no tombstoned ID returns, otherwise `StaleArchive`;
    - tombstones are unioned;
    - `revision = max + 1`;
    - a new lineage ID is appended.
  - `fun DiaryDatabase.exportArchive(out: OutputStream)`.
  - `fun DiaryDatabase.importArchive(input: InputStream)`, which uses
    `replacement` and then `replaceAll`.

- [ ] **Step 1: Failing JVM tests:**
  - `olderArchiveIsStale`;
  - `unrelatedLineageIsStale`;
  - `tombstoneResurrectionIsStale`;
  - `verifiedSuccessorMerges`;
  - `wrongOwner`.
- [ ] **Step 2: Failing instrumented test**
  `androidExportImportsOnAndroidAndMatchesIosFixture`: import the iOS
  fixture, export it, import the export into a fresh profile, and compare
  the snapshots. Every photo's bytes must be equal by SHA-256.
- [ ] **Step 3: Implement.** Then add the generator test
  `writeAndroidFixture`, which writes `fixtures/archive/android-v4-full.json`
  from the synthetic snapshot built in Kotlin, mirroring
  `syntheticFullSnapshot()`. It is gated by the instrumentation argument
  `writeFixtures=true` and copied out with `adb pull`.
- [ ] **Step 4: Run** the JVM and instrumented tests. Expected: PASS.
  Generate and commit `android-v4-full.json`.
- [ ] **Step 5: Add the iOS test** `androidFixtureDecodesToSyntheticSnapshot`
  to `ArchiveFixtureTests.swift`, and run it with `xcodebuild` as in Task 1.
  Expected: PASS.
- [ ] **Step 6: Commit** `feat(android): restore archives safely and prove iOS ↔ Android compatibility`.
- [ ] **Step 7: Record evidence.**
  - Update `docs/verification/2026-10-24-android-archive.md` with the SHA,
    emulator, simulator and counts for Tasks 1–9.
  - Set the `docs/parity.md` `archive` row Android status to `done` (only if
    both directions passed), with evidence and test names.
  - Commit `docs(verification): record Android archive compatibility`.
