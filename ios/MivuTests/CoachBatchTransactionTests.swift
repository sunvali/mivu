import Foundation
import SQLite3
import Testing
@testable import Mivu

@Suite struct CoachBatchTransactionTests {
    @Test func invalidUnitConversionRollsBackWholeBatch() throws {
        let f = try BatchFixture(); defer { f.remove() }
        let original = f.source.meals[0].items[0]
        var edited = original; edited.unit = "g"; edited.quantity = 150
        let invalid = CoachWrite.manual(.item(mealID: f.mealID, item: edited, revision: 1, submissionID: nil, explicitNutrients: [], original: original))
        let before = try f.durableState()
        #expect(throws: DiaryError.invalidAmountUnitChange) { try f.batch([f.foodWrite(), invalid]) }
        #expect(try f.durableState() == before && f.receipts().isEmpty)
    }

    @Test func legacyCorrectionReceiptReplaysWithoutRecalculation() throws {
        var source = BatchFixture.snapshot()
        let turnID = source.coachTurns[0].id, meal = source.meals[0], item = meal.items[0]
        let originalReceipt = CoachReceipt(operationKey: "\(turnID)/correct/\(meal.id)/\(item.id)", turnID: turnID, dayID: meal.dayID, mealID: meal.id, itemID: item.id, committedRevision: 1, resultJSON: "{}")
        source.coachTurns[0].receipts = [originalReceipt]
        let f = try BatchFixture(source: source); defer { f.remove() }
        let beforeRevision = try f.head().revision
        // This payload would fail conversion validation if replay recalculated it.
        var invalid = item; invalid.unit = "g"; invalid.quantity = 150
        let replayed = try #require(f.batch([.correction(mealID: meal.id, item: invalid, revision: 1)], mode: .replayOnly).value.first)
        let afterRevision = try f.head().revision
        #expect(replayed == originalReceipt)
        #expect(afterRevision == beforeRevision)
    }

    @Test func mixedBatchIncrementsHeadOnceOrRollsBackEverything() throws {
        let f = try BatchFixture(attachments: true, history: 120); defer { f.remove() }
        let beforeHead = try f.head(), unloaded = try f.rows("SELECT id, hex(payload) FROM coach_turn WHERE id != '\(f.turnID)' ORDER BY ordinal")
        let writes = f.mixedWrites(revision: beforeHead.revision)
        let commit = try f.batch(writes)
        #expect(commit.head.revision == beforeHead.revision + 1)
        #expect(commit.value.count == writes.count && commit.value.allSatisfy { $0.committedRevision == commit.head.revision })
        #expect(commit.changes.turnIDs.contains(f.turnID) && commit.changes.weightIDs.count == 1 && commit.changes.workoutIDs.count == 1)
        #expect(commit.head.activeDayID == beforeHead.activeDayID && commit.head.activeConversationSegmentID == beforeHead.activeConversationSegmentID)
        #expect(try f.rows("SELECT id, hex(payload) FROM coach_turn WHERE id != '\(f.turnID)' ORDER BY ordinal") == unloaded)
        try f.assertApplications(commit.value, writes: writes)
        try f.assertOrdinaryMetrics(); try f.assertAccounting()
        let failed = try BatchFixture(attachments: true); defer { failed.remove() }
        let original = try failed.durableState()
        try failed.execute("CREATE TRIGGER reject_receipt BEFORE UPDATE ON coach_turn WHEN json_array_length(json_extract(CAST(NEW.payload AS TEXT), '$.receipts')) > json_array_length(json_extract(CAST(OLD.payload AS TEXT), '$.receipts')) BEGIN SELECT RAISE(ABORT, 'synthetic receipt failure'); END")
        #expect(throws: DiaryError.persistenceFailed) { try failed.batch(failed.mixedWrites(revision: failed.head().revision)) }
        #expect(try failed.durableState() == original)
        #expect(try failed.rows("SELECT COUNT(*) FROM business_audit") == [["0"]])
        let fresh = try DiaryDatabase(url: failed.url)
        #expect(try fresh.readHead(expectedProfileID: failed.owner) == failed.head())
        try failed.assertAccounting()
    }

    @Test func replayedDeletedRecordIsNotResurrected() throws {
        let f = try BatchFixture(); defer { f.remove() }
        let writes: [CoachWrite] = [f.foodWrite(), .weight(date: "2027-01-13", value: 71, unit: "kg", revision: nil), .workout(date: "2027-01-13", draft: f.draft)]
        let first = try f.batch(writes)
        let mealID = try #require(first.value[0].mealID), weightID = try #require(first.value[1].weightID), workoutID = try #require(first.value[2].workoutID)
        _ = try f.database.deleteMeal(mealID, expected: f.head(), maximumBytes: f.maximum)
        _ = try f.database.deleteWeight(id: weightID, expectedRevision: 1, expected: f.head(), maximumBytes: f.maximum)
        _ = try f.database.deleteWorkout(id: workoutID, expectedRevision: 1, expected: f.head(), maximumBytes: f.maximum)
        let deleted = try f.durableState(), fresh = try DiaryDatabase(url: f.url)
        for write in writes {
            #expect(throws: DiaryError.notFound) { try fresh.applyCoachWrites([write], turnID: f.turnID, mode: .replayOnly, at: f.instant, expected: f.head(), maximumBytes: f.maximum) }
        }
        #expect(try f.receipts() == first.value && f.durableState() == deleted)
        #expect(try f.rows("SELECT COUNT(*) FROM meal WHERE id = '\(mealID)'") == [["0"]])
        #expect(try f.rows("SELECT id FROM weight_tombstone WHERE id = '\(weightID)'") == [[weightID.uuidString]])
        #expect(try f.rows("SELECT id FROM workout_tombstone WHERE id = '\(workoutID)'") == [[workoutID.uuidString]])
        try f.assertAccounting()
    }

    @Test func staleOrForeignProgressRejectsWholeBatch() throws {
        let f = try BatchFixture(); defer { f.remove() }
        _ = try f.batch([.correctWeight(id: f.source.weights[0].id, value: 72, unit: "kg", revision: 1)])
        let original = try f.durableState()
        let bad: [(CoachWrite, DiaryError)] = [
            (.correctWeight(id: f.source.weights[0].id, value: 73, unit: "kg", revision: 1), .staleRevision),
            (.editWorkout(id: UUID(), draft: f.draft, revision: 1), .notFound),
            (.manual(.goals(date: "2027-01-15", targets: [CoachNutrientEdit(nutrient: "kcal", value: 1800)], weight: nil, clearWeight: false, exerciseCredit: nil, revision: 999)), .staleRevision),
            (.manual(.preferences(timezone: nil, text: "stale", revision: 0)), .staleRevision)
        ]
        for (write, error) in bad {
            let turn = try f.capture(text: "new synthetic invalid batch")
            let before = try f.durableState()
            #expect(throws: error) { try f.batch([f.foodWrite(), write], turnID: turn) }
            #expect(try f.durableState() == before)
        }
        #expect(try f.rows("SELECT COUNT(*) FROM meal") == [["1"]])
        #expect(!original.isEmpty)
        let duplicate = try f.capture(text: "duplicate target")
        let head = try f.head(), state = try f.durableState()
        #expect(throws: CoachError.invalidArguments) { try f.batch([.weight(date: "2027-01-15", value: 74, unit: "kg", revision: 2), .deleteWeight(id: f.source.weights[0].id, revision: 2)], turnID: duplicate) }
        #expect(try f.head() == head && f.durableState() == state)
    }

    @Test func crashAfterInferenceBeforeCommitLeavesNoPartialFood() async throws {
        let f = try BatchFixture(attachments: true); defer { f.remove() }
        let original = try f.durableState(), inferred = try f.mixedWrites(revision: f.head().revision)
        #expect(try ChatHistoryFixture.completeReference(databaseURL: f.url) == f.source)
        let probe = BatchCommitProbe()
        sqlite3_commit_hook(f.database.connection, { context in
            Unmanaged<BatchCommitProbe>.fromOpaque(context!).takeUnretainedValue().attempted = true
            return 1
        }, Unmanaged.passUnretained(probe).toOpaque())
        defer { sqlite3_commit_hook(f.database.connection, nil, nil) }
        var acknowledgements = 0
        do { _ = try f.batch(inferred); acknowledgements += 1 } catch { }
        #expect(probe.attempted && acknowledgements == 0)
        #expect(try f.durableState() == original)
        let reopened = DiaryStore(directory: f.root)
        #expect(try await reopened.selectPagedProfile(f.owner) == f.head())
        #expect(try f.receipts().isEmpty)
        try f.assertAccounting()
    }

    @Test func crashAfterReceiptCommitBeforeAcknowledgementReplaysOnce() async throws {
        let f = try BatchFixture(attachments: true); defer { f.remove() }
        let writes = [f.foodWrite(), CoachWrite.weight(date: "2027-01-13", value: 71, unit: "kg", revision: nil)]
        let committed = try f.batch(writes)
        let fresh = DiaryStore(directory: f.root, diagnostics: f.metrics), before = try f.durableState()
        _ = try await fresh.selectPagedProfile(f.owner)
        let epoch = try await fresh.selectionEpoch(expectedProfileID: f.owner)
        let replay = try await fresh.applyCoachWrites(writes, turnID: f.turnID, epoch: epoch, expectedProfileID: f.owner, mode: .replayOnly)
        let replayHead = try await fresh.diaryHead(expectedProfileID: f.owner)
        #expect(replay == committed.value && replayHead == committed.head)
        #expect(try f.durableState() == before)
        try f.assertApplications(replay, writes: writes); try f.assertOrdinaryMetrics(); try f.assertAccounting()
    }

    @Test func regeneratedTransportIDsCannotChangeCommittedOperation() throws {
        let f = try BatchFixture(); defer { f.remove() }
        let original = try f.parsedFood(callID: "transport-a"), regenerated = try f.parsedFood(callID: "transport-b")
        let committed = try f.batch([original])
        let before = try f.durableState()
        #expect(try f.batch([regenerated], mode: .replayOnly).value == committed.value)
        let changed: [CoachWrite] = [f.foodWrite(quantity: 4), .food(date: "2027-01-12", items: [f.food()], eatenAt: nil)]
        for write in changed { #expect(throws: CoachError.invalidArguments) { try f.batch([write], mode: .replayOnly) } }
        #expect(throws: CoachError.invalidArguments) { try f.batch([regenerated, .workout(date: "2027-01-13", draft: f.draft)], mode: .replayOnly) }
        #expect(try f.durableState() == before && f.receipts() == committed.value)
        #expect(committed.value[0].commandFingerprint?.count == 64)
        let second = try f.capture(text: "manual uninterrupted patches")
        let one = try f.parsedPreferences("first", revision: f.head().revision, callID: "one")
        let firstPatch = try f.batch([one], turnID: second)
        let two = try f.parsedPreferences("second", revision: f.head().revision, callID: "two")
        #expect(one.target != two.target)
        let state = try f.durableState()
        #expect(throws: CoachError.invalidArguments) { try f.batch([two], turnID: second, mode: .replayOnly) }
        #expect(try f.durableState() == state)
        let laterPatch = try f.batch([two], turnID: second, mode: .uninterrupted)
        #expect(laterPatch.value[0].operationKey != firstPatch.value[0].operationKey)
        #expect(try f.head().profile.preferences == "second")
        try f.assertAccounting()
    }

    @Test func additiveCorrectionUpdatesSameItemAndPreservesUnrelatedItems() throws {
        let f = try BatchFixture(); defer { f.remove() }
        let original = f.source.meals[0], beforeIDs = try f.rows("SELECT id FROM meal ORDER BY id")
        let first = try f.batch([f.correction(quantity: 3)])
        let corrected = try f.database.meal(id: original.id, expectedProfileID: f.owner)
        #expect(corrected.id == original.id && corrected.items[0].id == original.items[0].id)
        #expect(corrected.items[0].quantity == 3 && corrected.items[0].unit == "piece")
        #expect(corrected.items[0].nutrition.kcal == 300 && corrected.items[0].nutrition.carbs == nil)
        #expect(corrected.items[0].nutritionBasis == original.items[0].nutritionBasis && corrected.items[0].reference == original.items[0].reference)
        #expect(corrected.items[0].uncertain && Array(corrected.items.dropFirst()) == Array(original.items.dropFirst()))
        #expect(corrected.dayID == original.dayID && corrected.eatenAt == original.eatenAt && corrected.capturedAt == original.capturedAt)
        #expect(try corrected.photos.map(\.photoID) == original.photos.map(\.id) && f.rows("SELECT id FROM meal ORDER BY id") == beforeIDs)
        let facts = try f.database.coachExchangeSummary(turnID: f.turnID, expectedProfileID: f.owner).receipts
        #expect(facts[0].targetLocalDate == "2027-01-14" && facts[0].items.first?.quantity == 3 && facts[0].items.first?.unit == "piece")
        let result = try JSONSerialization.jsonObject(with: Data(first.value[0].resultJSON.utf8)) as? [String: Any]
        #expect(result?["targetLocalDate"] as? String == "2027-01-14")
        try f.assertApplications(first.value, writes: [f.correction(quantity: 3)]); try f.assertOrdinaryMetrics(); try f.assertAccounting()
    }

    @Test func additiveCorrectionCrashRetryDoesNotIncrementTwice() throws {
        let f = try BatchFixture(); defer { f.remove() }
        let write = f.correction(quantity: 3), first = try f.batch([write])
        let firstFacts = try f.database.coachExchangeSummary(turnID: f.turnID, expectedProfileID: f.owner).receipts
        let fresh = try DiaryDatabase(url: f.url)
        #expect(try fresh.applyCoachWrites([write], turnID: f.turnID, mode: .replayOnly, at: f.instant, expected: f.head(), maximumBytes: f.maximum).value == first.value)
        #expect(try f.database.meal(id: f.mealID, expectedProfileID: f.owner).items[0].quantity == 3)
        var manual = try f.database.meal(id: f.mealID, expectedProfileID: f.owner).items[0]; manual.quantity = 5
        _ = try f.database.editItem(mealID: f.mealID, item: manual, explicitNutrients: [], expectedRevision: 2, expected: f.head(), maximumBytes: f.maximum)
        _ = try f.database.moveMeal(f.mealID, to: f.source.days[0].id, expectedRevision: 3, expected: f.head(), maximumBytes: f.maximum)
        let preserved = try f.durableState()
        #expect(try f.batch([write], mode: .replayOnly).value == first.value)
        let current = try f.database.meal(id: f.mealID, expectedProfileID: f.owner)
        let grounded = CoachContext.Meal(id: current.id, dayID: current.dayID, revision: current.revision, eatenAt: current.eatenAt, timePrecision: current.timePrecision, items: current.items)
        let call = CoachToolCall(id: "regenerated-correction", callID: "regenerated-correction", name: "correct_item", namespace: "mivu", arguments: "{\"meal_id\":\"\(f.mealID)\",\"item_id\":\"\(manual.id)\",\"expected_revision\":1,\"quantity\":3}")
        guard case .write(let regenerated) = try CoachTools.parse(call, meals: [grounded], evidence: [:], receipts: first.value) else { throw DiaryError.invalidData }
        #expect(try f.batch([regenerated], mode: .replayOnly).value == first.value)
        #expect(try f.database.meal(id: f.mealID, expectedProfileID: f.owner).items[0].quantity == 5)
        #expect(try f.database.coachExchangeSummary(turnID: f.turnID, expectedProfileID: f.owner).receipts == firstFacts)
        #expect(try f.durableState() == preserved)
        #expect(throws: CoachError.invalidArguments) { try f.batch([f.correction(quantity: 4)], mode: .replayOnly) }
        _ = try f.database.transaction(expected: f.head(), maximumBytes: f.maximum) { transaction in
            try transaction.replaceItems(Array(f.source.meals[0].items.dropFirst()), mealID: f.mealID)
            var meal = try transaction.mealRecord(id: f.mealID); meal.revision += 1; try transaction.saveMeal(meal)
        }
        #expect(throws: DiaryError.notFound) { try f.batch([write], mode: .replayOnly) }
        #expect(try f.receipts() == first.value)
        #expect(try f.rows("SELECT COUNT(*) FROM item WHERE parent = '\(f.mealID)'") == [["2"]])
        try f.assertAccounting()
    }

    @Test(arguments: [false, true]) func sharedProgressPhotoSurvivesOneRecordDeletion(weightSurvives: Bool) throws {
        let f = try BatchFixture(attachments: true); defer { f.remove() }
        var writes: [CoachWrite] = [f.foodWrite(), .workout(date: "2027-01-13", draft: f.draft)]
        writes.append(weightSurvives ? .weight(date: "2027-01-13", value: 71, unit: "kg", revision: nil) : .workout(date: "2027-01-12", draft: f.draft))
        let saved = try f.batch(writes), mealID = try #require(saved.value[0].mealID), workoutID = try #require(saved.value[1].workoutID)
        let shared = try #require(f.database.coachExchangeSummary(turnID: f.turnID, expectedProfileID: f.owner).photos.first)
        #expect(shared.owner == .meal(mealID))
        _ = try f.database.deleteWorkout(id: workoutID, expectedRevision: 1, expected: f.head(), maximumBytes: f.maximum)
        #expect(try f.database.coachExchangeSummary(turnID: f.turnID, expectedProfileID: f.owner).photos == [shared])
        _ = try f.database.deleteMeal(mealID, expected: f.head(), maximumBytes: f.maximum)
        let retained = try #require(f.database.coachExchangeSummary(turnID: f.turnID, expectedProfileID: f.owner).photos.first)
        #expect(retained.owner == .coachTurn(f.turnID) && retained.contentToken != shared.contentToken)
        try f.assertOrdinaryMetrics()
        #expect(try f.database.photoContent(retained, expectedProfileID: f.owner) == f.source.coachTurns.last?.photos.first?.data)
        #expect(throws: DiaryError.notFound) { try f.database.photoContent(shared, expectedProfileID: f.owner) }
        if !weightSurvives {
            let lastID = try #require(saved.value[2].workoutID)
            _ = try f.database.deleteWorkout(id: lastID, expectedRevision: 1, expected: f.head(), maximumBytes: f.maximum)
            #expect(try f.database.coachExchangeSummary(turnID: f.turnID, expectedProfileID: f.owner).photos.isEmpty)
            #expect(throws: DiaryError.notFound) { try f.database.photoContent(retained, expectedProfileID: f.owner) }
        }
        #expect(try f.receipts() == saved.value)
        try f.assertAccounting()
    }

    @Test(arguments: [UInt64(42), 20261018, 0xC0FFEE])
    func seededMixedBatchesAndReceiptGrowthMatchReferenceAccounting(seed: UInt64) throws {
        let f = try BatchFixture(); defer { f.remove() }
        var generator = ChatHistoryFixture.Generator(seed: seed)
        for index in 0..<36 {
            let turn = try f.capture(text: generator.encodingEdge()), head = try f.head()
            let date = String(format: "2027-02-%02d", index % 28 + 1)
            var writes: [CoachWrite] = [.food(date: date, items: [f.food(name: generator.encodingEdge(), quantity: Double(index + 1))], eatenAt: nil), .workout(date: date, draft: f.draft),
                .manual(.preferences(timezone: nil, text: generator.encodingEdge(), revision: head.revision))]
            if index < 28 { writes.append(.weight(date: date, value: 70 + Double(index) / 10, unit: "kg", revision: nil)) }
            let full = try ChatHistoryFixture.completeReference(databaseURL: f.url)
            let goal = full.goals.first { $0.effectiveLocalDate == date }
            writes.append(.manual(.goals(date: date, targets: [CoachNutrientEdit(nutrient: "kcal", value: Double(1800 + index))], weight: nil, clearWeight: false, exerciseCredit: index.isMultiple(of: 2), revision: goal?.revision)))
            let before = try f.durableState()
            if index.isMultiple(of: 6) {
                #expect(throws: DiaryError.invalidData) { try f.batch(writes, turnID: turn, maximumBytes: 1) }
                #expect(try f.durableState() == before, "seed=\(seed) index=\(index) quota rollback")
            }
            try f.execute("DELETE FROM business_audit")
            let saved = try f.batch(writes, turnID: turn)
            #expect(saved.head.revision == head.revision + 1, "seed=\(seed) index=\(index)")
            try f.assertApplications(saved.value, writes: writes, turnID: turn)
            let after = try f.durableState()
            #expect(try f.batch(writes, turnID: turn, mode: .replayOnly).value == saved.value)
            #expect(try f.durableState() == after, "seed=\(seed) index=\(index) replay")
            if index.isMultiple(of: 3), let id = saved.value.first(where: { $0.workoutID != nil })?.workoutID {
                _ = try f.database.deleteWorkout(id: id, expectedRevision: 1, expected: f.head(), maximumBytes: f.maximum)
            }
            try f.assertOrdinaryMetrics(); try f.assertAccounting()
        }
    }

    @Test func touchedRevisionRevalidationAllowsOnlyUnrelatedChanges() throws {
        let f = try BatchFixture(); defer { f.remove() }
        let grounded = f.correction(quantity: 3)
        let other = try f.database.captureProjection(text: "unrelated", photos: [], reviewFirst: false, dayID: f.source.days[0].id, at: f.instant, expected: f.head(), maximumBytes: f.maximum).value
        _ = try f.batch([grounded])
        #expect(try f.database.meal(id: f.mealID, expectedProfileID: f.owner).items[0].quantity == 3)
        let turn = try f.capture(text: "stale grounded correction"), stale = f.correction(quantity: 4, revision: 2)
        var item = try f.database.meal(id: f.mealID, expectedProfileID: f.owner).items[0]; item.quantity = 6
        _ = try f.database.editItem(mealID: f.mealID, item: item, explicitNutrients: [], expectedRevision: 2, expected: f.head(), maximumBytes: f.maximum)
        let before = try f.durableState()
        #expect(throws: DiaryError.staleRevision) { try f.batch([f.foodWrite(), stale], turnID: turn) }
        #expect(try f.durableState() == before && f.rows("SELECT COUNT(*) FROM meal WHERE id = '\(other.id)'") == [["1"]])
    }

    @Test func legacyReceiptRemainsAuthorityAndNewReceiptLimitRollsBack() throws {
        var source = BatchFixture.snapshot()
        let id = source.coachTurns[0].id
        source.coachTurns[0].receipts = [CoachReceipt(operationKey: "\(id)/correct/\(source.meals[0].id)/\(source.meals[0].items[0].id)", turnID: id, dayID: source.meals[0].dayID, mealID: source.meals[0].id, itemID: source.meals[0].items[0].id, committedRevision: 1, resultJSON: "{}")]
        let f = try BatchFixture(source: source); defer { f.remove() }
        let prior = try f.durableState()
        #expect(try f.batch([f.correction(quantity: 3)], mode: .replayOnly).value == source.coachTurns[0].receipts)
        #expect(try f.durableState() == prior && f.receipts()[0].commandFingerprint == nil)
        let turn = try f.capture(text: "sixteen operations")
        let writes: [CoachWrite] = (1...16).map { .close(date: String(format: "2027-03-%02d", $0), completeness: .partial) }
        let saved = try f.batch(writes, turnID: turn), before = try f.durableState()
        #expect(saved.value.count == 16)
        #expect(throws: CoachError.limitExceeded) { try f.batch([.close(date: "2027-03-17", completeness: .complete)], turnID: turn) }
        #expect(try f.durableState() == before)
        try f.assertAccounting()
    }

    @Test func directProgressGoalAndPreferenceAdaptersKeepIdentityAndGuards() throws {
        let f = try BatchFixture(); defer { f.remove() }
        let original = f.source.weights[0], goal = f.source.goals[0]
        let weight = try f.database.setWeight(dayID: f.source.days[0].id, value: 73, expectedRevision: 1, expected: f.head(), maximumBytes: f.maximum)
        #expect(weight.value.id == original.id && weight.value.revision == 2 && weight.value.measuredAt == original.measuredAt)
        let updated = try f.database.updateWeight(id: original.id, value: 74, expectedRevision: 2, expected: f.head(), maximumBytes: f.maximum)
        #expect(updated.value.value == 74 && updated.value.revision == 3)
        var changedGoal = goal; changedGoal.targets.kcal = 1800
        #expect(try f.database.setGoals(changedGoal, expectedRevision: 1, expected: f.head(), maximumBytes: f.maximum).value.revision == 2)
        let previous = try f.head().profile; var profile = previous; profile.preferences = "Synthetic no nuts"; profile.timeZoneID = "UTC"
        _ = try f.database.updateProfile(profile, expectedProfile: previous, expected: f.head(), maximumBytes: f.maximum)
        #expect(try f.head().profile == profile && f.head().previousDayConfirmedAt == nil)
        let session = try f.database.createWorkout(dayID: f.source.days[1].id, draft: f.draft, expected: f.head(), maximumBytes: f.maximum).value
        var edited = session; edited.durationMinutes = 35
        let saved = try f.database.updateWorkout(edited, expectedRevision: 1, expected: f.head(), maximumBytes: f.maximum).value
        #expect(saved.id == session.id && saved.performedAt == session.performedAt && saved.dayID == session.dayID && saved.revision == 2)
        let before = try f.durableState()
        #expect(throws: DiaryError.staleRevision) { try f.database.setGoals(changedGoal, expectedRevision: 1, expected: f.head(), maximumBytes: f.maximum) }
        #expect(throws: DiaryError.staleRevision) { try f.database.updateProfile(profile, expectedProfile: previous, expected: f.head(), maximumBytes: f.maximum) }
        #expect(try f.durableState() == before)
        try f.assertOrdinaryMetrics(); try f.assertAccounting()
    }

    /// Days `offsets` back from 2027-01-15 (UTC), each with one saved meal of `items`.
    private func progressSource(offsets: [Int], items: (Int) -> [FoodItem] = { _ in [FoodItem(name: "Synthetic oats", nutrition: NutritionValues(kcal: 300))] }) -> DiarySnapshot {
        var source = BatchFixture.snapshot()
        source.days = []; source.weights = []; source.meals = []; source.workouts = []; source.coachTurns = []; source.activeDayID = nil; source.previousDayConfirmedAt = nil
        source.profile.timeZoneID = "UTC"
        let end = Date(timeIntervalSince1970: 1_800_000_000.125)
        for offset in offsets {
            let at = end.addingTimeInterval(Double(-offset) * 86_400)
            let day = TrackingDay(localDate: diaryDateLabel(at, zone: "UTC"), timeZoneID: "UTC", startAt: at, completeness: .complete)
            source.days.append(day)
            source.meals.append(DiaryMeal(dayID: day.id, capturedAt: at, eatenAt: at, revision: 1, items: items(offset)))
        }
        return source
    }

    @Test func displayRangeAcceptsQuarterAndYear() throws {
        let f = try BatchFixture(source: progressSource(offsets: [1, 60, 300])); defer { f.remove() }
        let year = try f.database.progressRange(endingOn: "2027-01-15", days: 365, includeDailyReports: true, expectedProfileID: f.owner)
        #expect(year.dailyReports?.count == 365)
        #expect(year.savedFoodDates?.count == 3)
        let quarter = try f.database.progressRange(endingOn: "2027-01-15", days: 91, includeDailyReports: true, expectedProfileID: f.owner)
        #expect(quarter.dailyReports?.count == 91 && quarter.savedFoodDates?.count == 2)
    }

    @Test func coachRangeStillRejectsYear() throws {
        let f = try BatchFixture(source: progressSource(offsets: [1])); defer { f.remove() }
        #expect(throws: CoachError.invalidArguments) { try f.database.progressRange(endingOn: "2027-01-15", days: 365, expectedProfileID: f.owner) }
        #expect(throws: CoachError.invalidArguments) { try f.database.progressRange(endingOn: "2027-01-15", days: 91, expectedProfileID: f.owner) }
    }

    @Test func yearRangeLoadsUnderOneSecond() throws {
        let f = try BatchFixture(source: progressSource(offsets: Array(0..<365)) { _ in
            (0..<3).map { FoodItem(name: "Synthetic meal \($0)", nutrition: NutritionValues(kcal: 600, carbs: 60, protein: 40, fat: 20)) }
        }); defer { f.remove() }
        let elapsed = try ContinuousClock().measure {
            _ = try f.database.progressRange(endingOn: "2027-01-15", days: 365, includeDailyReports: true, expectedProfileID: f.owner)
        }
        #expect(elapsed < .seconds(1), "365-day progress took \(elapsed)")
    }

    @Test func topFoodsGroupsByNormalizedName() throws {
        let f = try BatchFixture(source: progressSource(offsets: [3, 2, 1]) { offset in
            switch offset {
            case 3: [FoodItem(name: " greek Yogurt ", nutrition: NutritionValues(kcal: 150))]
            case 2: [FoodItem(name: "Pizza", nutrition: NutritionValues(kcal: 721))]
            default: [FoodItem(name: "Greek yogurt", nutrition: NutritionValues(kcal: 150))]
            }
        }); defer { f.remove() }
        let foods = try f.database.topFoods(from: "2027-01-01", through: "2027-01-15", limit: 10, expectedProfileID: f.owner)
        #expect(foods == [TopFood(name: "Pizza", kcal: 721, count: 1), TopFood(name: "Greek yogurt", kcal: 300, count: 2)])
        #expect(throws: DiaryError.wrongOwner) { try f.database.topFoods(from: "2027-01-01", through: "2027-01-15", limit: 10, expectedProfileID: UUID()) }
    }

    @Test func topFoodsSkipsUnknownAndPending() throws {
        var source = progressSource(offsets: [2, 1]) { offset in
            offset == 2 ? [FoodItem(name: "Mystery stew", nutrition: NutritionValues(kcal: nil)), FoodItem(name: "Toast", nutrition: NutritionValues(kcal: 90))]
                        : [FoodItem(name: "Pending pie", nutrition: NutritionValues(kcal: 500))]
        }
        source.meals[1].revision = 0
        let f = try BatchFixture(source: source); defer { f.remove() }
        #expect(try f.database.topFoods(from: "2027-01-01", through: "2027-01-15", limit: 10, expectedProfileID: f.owner) == [TopFood(name: "Toast", kcal: 90, count: 1)])
    }

    @Test func boundedProgressRangePreservesAnalyticsAndHistoricalWeightHorizon() throws {
        var source = BatchFixture.snapshot(), calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        source.days = []; source.weights = []; source.meals = []; source.workouts = []; source.coachTurns = []; source.activeDayID = nil; source.previousDayConfirmedAt = nil
        let end = Date(timeIntervalSince1970: 1_800_000_000.125)
        for index in 0..<45 {
            let at = calendar.date(byAdding: .day, value: -index, to: end)!
            let day = TrackingDay(localDate: diaryDateLabel(at, zone: source.profile.timeZoneID), timeZoneID: source.profile.timeZoneID, startAt: at, completeness: .complete)
            source.days.append(day); source.weights.append(WeightEntry(dayID: day.id, measuredAt: at, value: Double(70 + index), unit: index.isMultiple(of: 2) ? "kg" : "lb"))
        }
        let f = try BatchFixture(source: source); defer { f.remove() }
        for days in [1, 7, 30] {
            let report = try f.database.progressRange(endingOn: "2027-01-15", days: days, expectedProfileID: f.owner)
            #expect(report.daily == ProgressAnalytics.daily(snapshot: source, localDate: "2027-01-15"))
            #expect(report.weight == ProgressAnalytics.weight(snapshot: source, endingOn: "2027-01-15"))
            #expect(report.period == (days == 1 ? nil : ProgressAnalytics.period(snapshot: source, endingOn: "2027-01-15", days: days)))
            #expect(report.weights.count == days && report.omittedWeightCount == 0)
        }
        #expect(throws: CoachError.invalidArguments) { try f.database.progressRange(endingOn: "2027-01-15", days: 31, expectedProfileID: f.owner) }
        #expect(throws: DiaryError.wrongOwner) { try f.database.progressRange(endingOn: "2027-01-15", days: 30, expectedProfileID: UUID()) }
        try f.assertOrdinaryMetrics()
        #expect(f.metrics.counters.queryPlans.contains { $0.contains("day_date_zone_ordinal") })
    }

    @Test func stagedStoreEnforcesEpochAndPublishesAtomicBatchOnly() async throws {
        let f = try BatchFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root, currentTime: { Date(timeIntervalSince1970: 1_800_000_000.125) }, diagnostics: f.metrics)
        _ = try await store.selectPagedProfile(f.owner)
        let epoch = try await store.selectionEpoch(expectedProfileID: f.owner)
        let writes = [f.foodWrite()]
        let receipts = try await store.applyCoachWrites(writes, turnID: f.turnID, epoch: epoch, expectedProfileID: f.owner)
        let committedHead = try await store.diaryHead(expectedProfileID: f.owner)
        #expect(receipts.count == 1 && receipts[0].committedRevision == committedHead.revision)
        _ = try await store.setWeight(dayID: f.source.days[0].id, value: 72, expectedRevision: 1, expectedProfileID: f.owner)
        _ = try await store.selectPagedProfile(f.owner)
        let state = try f.durableState()
        await #expect(throws: DiaryError.wrongOwner) { try await store.applyCoachWrites(writes, turnID: f.turnID, epoch: epoch, expectedProfileID: f.owner, mode: .replayOnly) }
        #expect(try f.durableState() == state)
        try f.assertOrdinaryMetrics(); try f.assertAccounting()
    }

    @Test func regeneratedMoveUsesOriginalCommandAfterGroundedDayChanges() throws {
        let f = try BatchFixture(); defer { f.remove() }
        func grounded() throws -> CoachContext.Meal {
            let meal = try f.database.meal(id: f.mealID, expectedProfileID: f.owner)
            return CoachContext.Meal(id: meal.id, dayID: meal.dayID, revision: meal.revision, eatenAt: meal.eatenAt, timePrecision: meal.timePrecision, items: meal.items)
        }
        let args: [String: Any] = ["meal_id": f.mealID.uuidString, "expected_revision": 1, "target_local_date": "2027-01-13"]
        let originalDay = try grounded().dayID
        let original = try f.parsed(name: "move_meal", args: args, callID: "original-move", meals: [grounded()])
        let committed = try f.batch([original]), moved = try grounded()
        #expect(moved.dayID != originalDay && moved.revision == 1)
        let regenerated = try f.parsed(name: "move_meal", args: args, callID: "regenerated-move", meals: [moved])
        #expect(original.target == regenerated.target)
        let before = try f.durableState()
        #expect(try f.batch([regenerated], mode: .replayOnly).value == committed.value)
        #expect(try f.durableState() == before)
        var changed = args; changed["target_local_date"] = "2027-01-12"
        let conflict = try f.parsed(name: "move_meal", args: changed, callID: "changed-move", meals: [moved])
        #expect(throws: CoachError.invalidArguments) { try f.batch([conflict], mode: .replayOnly) }
        #expect(try f.durableState() == before)
        try f.assertOrdinaryMetrics(); try f.assertAccounting()
    }

    @Test(arguments: [false, true]) func boundedPendingExistenceExcludesOnlyFinalizingTurn(unassigned: Bool) throws {
        var source = BatchFixture.snapshot()
        source.meals = []; source.workouts = []; source.days[0].completeness = .complete
        if unassigned { source.coachTurns[0].activeDayID = nil }
        for _ in 0..<120 {
            source.coachTurns.insert(CoachTurn(capturedAt: source.days[1].startAt, text: String(repeating: "Synthetic historical pending ", count: 40), captureTimeZoneID: source.days[1].timeZoneID, activeDayID: source.days[1].id), at: 0)
        }
        let f = try BatchFixture(source: source); defer { f.remove() }
        let included = try f.database.progressRange(endingOn: "2027-01-15", days: 1, expectedProfileID: f.owner)
        #expect(included.daily.hasPending && included.daily.completeness == .partial && included.daily.foodTotals?.kcal == nil)
        let excluded = try f.database.progressRange(endingOn: "2027-01-15", days: 1, finalizingTurnID: f.turnID, expectedProfileID: f.owner)
        #expect(!excluded.daily.hasPending && excluded.daily.completeness == .complete && excluded.daily.foodTotals?.kcal == 0)
        let other = try f.capture(text: "Another accepted pending turn")
        #expect(try f.database.progressRange(endingOn: "2027-01-15", days: 1, finalizingTurnID: f.turnID, expectedProfileID: f.owner).daily.hasPending)
        _ = try f.database.updateCoachTurn(turnID: other, state: .completed, assistantText: "Synthetic completed", needsDayChoice: false, expected: f.head(), maximumBytes: f.maximum)
        #expect(try !f.database.progressRange(endingOn: "2027-01-15", days: 1, finalizingTurnID: f.turnID, expectedProfileID: f.owner).daily.hasPending)
        #expect(f.metrics.counters.queryPlans.contains { $0.contains("coach_turn_pending_day") })
        #expect(f.metrics.counters.queryPlans.contains { $0.contains("coach_index_display_date") })
        try f.assertOrdinaryMetrics(); try f.assertAccounting()
    }
}

private final class BatchCommitProbe { var attempted = false }

private struct BatchFixture {
    let capture: CaptureFixture
    let metrics = DiaryQueryDiagnostics()
    let database: DiaryDatabase
    var source: DiarySnapshot { capture.before }
    var owner: UUID { source.profile.id }
    var root: URL { capture.root }
    var url: URL { capture.url }
    var mealID: UUID { source.meals[0].id }
    var turnID: UUID { source.coachTurns.last!.id }
    var instant: Date { Date(timeIntervalSince1970: 1_800_000_000.125) }
    let maximum = ChatHistoryFixture.maximumBytes
    var draft: WorkoutDraft { WorkoutDraft(kind: .strength, durationMinutes: 20, exercises: [WorkoutExercise(name: "Synthetic squat", sets: [WorkoutSet(repetitions: 8, loadKg: 30)])], estimatedBurnKcal: 70, burnSource: .userEstimate) }
    init(attachments: Bool = false, history: Int = 0) throws { try self.init(source: Self.snapshot(attachments: attachments, history: history)) }
    init(source: DiarySnapshot) throws {
        capture = try CaptureFixture(snapshot: source)
        database = try DiaryDatabase(url: capture.url, diagnostics: metrics)
        try execute("CREATE TABLE business_audit(kind TEXT, recordID TEXT, action TEXT)")
        for table in ["meal", "weight", "workout", "goal", "item"] {
            for (event, row) in [("INSERT", "NEW"), ("UPDATE", "NEW"), ("DELETE", "OLD")] {
                try execute("CREATE TRIGGER audit_\(table)_\(event) AFTER \(event) ON \(table) BEGIN INSERT INTO business_audit VALUES ('\(table)', \(row).id, '\(event)'); END")
            }
        }
        try execute("CREATE TRIGGER audit_profile AFTER UPDATE ON storage_head WHEN NEW.profilePayload != OLD.profilePayload BEGIN INSERT INTO business_audit VALUES ('profile', NEW.profileID, 'UPDATE'); END")
        try execute("CREATE TRIGGER audit_coverage AFTER UPDATE ON day WHEN json_extract(CAST(NEW.payload AS TEXT), '$.completeness') != json_extract(CAST(OLD.payload AS TEXT), '$.completeness') BEGIN INSERT INTO business_audit VALUES ('coverage', NEW.id, 'UPDATE'); END")
        metrics.reset()
    }
    static func snapshot(attachments: Bool = false, history: Int = 0) -> DiarySnapshot {
        var value = ChatHistoryFixture.snapshot(exchanges: history)
        for index in value.coachTurns.indices { value.coachTurns[index].state = .completed; value.coachTurns[index].receipts = []; value.coachTurns[index].photos = []; value.coachTurns[index].photoIDs = [] }
        let basis = NutritionValues(kcal: 100, carbs: nil, protein: 20, fat: 3)
        value.meals[0].items = [FoodItem(name: "Chicken", quantity: 2, unit: "piece", nutrition: basis.scaled(by: 2), provenance: .estimate, reference: "Synthetic chicken piece", uncertain: true, nutrientSources: ["kcal": .estimate, "protein": .estimate], nutritionBasis: basis),
            FoodItem(name: "Rice", quantity: 1, unit: "cup", nutrition: NutritionValues(kcal: 200)), FoodItem(name: "Salad", quantity: 1, unit: "bowl", nutrition: NutritionValues(kcal: 50))]
        let photos = attachments ? [MealPhoto(data: Data([255, 0, 255, 1]), createdAt: value.days[0].startAt)] : []
        value.coachTurns.append(CoachTurn(capturedAt: value.days[0].startAt, text: "Synthetic batch", photos: photos, captureTimeZoneID: value.profile.timeZoneID, activeDayID: value.activeDayID, photoIDs: photos.map(\.id)))
        return value
    }
    func remove() { capture.remove() }
    func head() throws -> DiaryHead { try database.readHead(expectedProfileID: owner) }
    func rows(_ sql: String) throws -> [[String]] { try capture.rows(sql) }
    func execute(_ sql: String) throws { try capture.execute(sql) }
    func food(name: String = "Synthetic apple", quantity: Double = 1) -> FoodItem { FoodItem(name: name, quantity: quantity, unit: "piece", nutrition: NutritionValues(kcal: 90, carbs: 20)) }
    func foodWrite(quantity: Double = 1) -> CoachWrite { .food(date: "2027-01-13", items: [food(quantity: quantity)], eatenAt: nil) }
    func correction(quantity: Double, revision: Int = 1) -> CoachWrite { var item = source.meals[0].items[0]; item.quantity = quantity; return .correction(mealID: mealID, item: item, revision: revision) }
    func mixedWrites(revision: Int) -> [CoachWrite] {
        [foodWrite(), .weight(date: "2027-01-13", value: 71, unit: "kg", revision: nil), .workout(date: "2027-01-14", draft: draft), .close(date: "2027-01-13", completeness: .complete),
         .manual(.goals(date: "2027-01-16", targets: [CoachNutrientEdit(nutrient: "kcal", value: 1800)], weight: nil, clearWeight: false, exerciseCredit: true, revision: nil)),
         .manual(.preferences(timezone: nil, text: "Synthetic preferences", revision: revision))]
    }
    func batch(_ writes: [CoachWrite], turnID: UUID? = nil, mode: CoachWriteMode = .uninterrupted, maximumBytes: Int? = nil) throws -> DiaryCommit<[CoachReceipt]> {
        try database.applyCoachWrites(writes, turnID: turnID ?? self.turnID, mode: mode, at: instant, expected: head(), maximumBytes: maximumBytes ?? maximum)
    }
    func receipts() throws -> [CoachReceipt] { try ChatHistoryFixture.completeReference(databaseURL: url).coachTurns.first { $0.id == turnID }!.receipts }
    func capture(text: String) throws -> UUID {
        let payload = try capture.payload(head: head(), text: text)
        _ = try database.captureCoachSubmission(payload, expected: head(), maximumBytes: maximum); return payload.submissionID
    }
    func parsedFood(callID: String) throws -> CoachWrite {
        try parsed(name: "log_food", args: ["target_local_date": "2027-01-13", "items": [["name": "Synthetic apple", "quantity": 1, "unit": "piece", "kcal": 90, "carbs": 20, "protein": NSNull(), "fat": NSNull()]]], callID: callID)
    }
    func parsedPreferences(_ text: String, revision: Int, callID: String) throws -> CoachWrite { try parsed(name: "update_preferences", args: ["expected_diary_revision": revision, "preferences": text], callID: callID) }
    func parsed(name: String, args: [String: Any], callID: String, meals: [CoachContext.Meal] = []) throws -> CoachWrite {
        let call = CoachToolCall(id: callID, callID: callID, name: name, namespace: "mivu", arguments: String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self))
        guard case .write(let write) = try CoachTools.parse(call, meals: meals, evidence: [:], receipts: []) else { throw DiaryError.invalidData }; return write
    }
    func durableState() throws -> [[[String]]] {
        try capture.durableState() + ["day", "meal", "submission", "item", "weight", "workout", "goal", "weight_tombstone", "workout_tombstone", "tombstone", "record_source", "business_audit"].map { try rows("SELECT * FROM \($0) ORDER BY rowid") }
    }
    func assertApplications(_ receipts: [CoachReceipt], writes: [CoachWrite], turnID: UUID? = nil) throws {
        var applications: [String: Int] = [:]
        let intended = Set(writes.map { "\(turnID ?? self.turnID)/\($0.target)" })
        #expect(Set(receipts.map(\.operationKey)) == intended && receipts.count == intended.count)
        for receipt in receipts {
            let kind: String, id: String, action: String
            if let item = receipt.itemID, let meal = receipt.mealID { kind = "item"; id = "\(meal)/\(item)"; action = "UPDATE" }
            else if let meal = receipt.mealID { kind = "meal"; id = meal.uuidString; action = "INSERT" }
            else if let weight = receipt.weightID { kind = "weight"; id = weight.uuidString; action = "INSERT" }
            else if let workout = receipt.workoutID { kind = "workout"; id = workout.uuidString; action = "INSERT" }
            else if let goal = receipt.goalID { kind = "goal"; id = goal.uuidString; action = "" }
            else if receipt.operationKey.contains("/update_preferences") { kind = "profile"; id = owner.uuidString; action = "UPDATE" }
            else if let day = receipt.dayID { kind = "coverage"; id = day.uuidString; action = "UPDATE" }
            else { Issue.record("No independently observed record for \(receipt.operationKey)"); continue }
            let count = try rows("SELECT COUNT(*) FROM business_audit WHERE kind = '\(kind)' AND recordID = '\(id)' \(action.isEmpty ? "" : "AND action = '\(action)'")")
            applications[receipt.operationKey] = Int(count[0][0])
        }
        #expect(Set(applications.keys) == intended)
        #expect(applications.values.allSatisfy { $0 == 1 })
    }
    func assertOrdinaryMetrics() throws {
        #expect(metrics.counters.completeReads == 0 && metrics.counters.completeReconciles == 0 && metrics.counters.originalPhotoBytes == 0)
    }
    func assertAccounting() throws {
        let full = try ChatHistoryFixture.completeReference(databaseURL: url); try full.validate()
        #expect(try rows("SELECT portableBytes FROM storage_quota") == [[String(try JSONEncoder().encode(full).count)]])
        let originals = full.meals.flatMap(\.photos).reduce(0) { $0 + $1.data.count } + full.coachTurns.flatMap(\.photos).reduce(0) { $0 + $1.data.count }
        #expect(try rows("SELECT originalPhotoBytes FROM storage_quota") == [[String(originals)]])
        for table in ["day", "meal", "submission", "item", "photo", "weight", "workout", "coach_turn", "coach_photo", "goal", "tombstone", "weight_tombstone", "workout_tombstone"] {
            #expect(try rows("SELECT rowCount FROM storage_row_count WHERE tableName = '\(table)'") == rows("SELECT COUNT(*) FROM \(table)"))
        }
        #expect(try rows("SELECT COUNT(*) FROM pragma_foreign_key_check") == [["0"]])
    }
}
