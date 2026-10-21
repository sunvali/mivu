import Foundation
import Testing
@testable import Mivu

@Suite struct CoachIndexedContextTests {
    @Test func contextExcludesFutureQueuedTurnsAndIgnoresViewport() async throws {
        var source = ChatHistoryFixture.lunchCorrectionSnapshot()
        let processed = 60
        source.coachTurns[processed].state = .captured
        for index in 1..<source.coachTurns.count {
            source.coachTurns[index].text = String(repeating: "Synthetic prior text 🍎 ", count: 180)
            source.coachTurns[index].assistantText = String(repeating: "Bounded reply. ", count: 100)
        }
        source.coachTurns[processed + 1].state = .captured
        let f = try CaptureFixture(snapshot: source); defer { f.remove() }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: f.root, diagnostics: metrics)
        _ = try await store.selectPagedProfile(f.profileID)
        let database = try DiaryDatabase(url: f.url, diagnostics: metrics)
        let turn = source.coachTurns[processed]
        metrics.reset()
        let before = try await store.coachContext(turnID: turn.id, expectedProfileID: f.profileID)
        _ = try database.coachPage(.aroundTurn(source.coachTurns[0].id), expectedProfileID: f.profileID)
        _ = try database.coachPage(.latest, expectedProfileID: f.profileID)
        let after = try await store.coachContext(turnID: turn.id, expectedProfileID: f.profileID)
        #expect(before == after && before.recentTurns.count <= 12 && !before.recentTurns.isEmpty)
        let sequences = Dictionary(uniqueKeysWithValues: source.coachTurns.enumerated().map { ($0.element.id, $0.offset + 1) })
        #expect(before.recentTurns.allSatisfy { sequences[$0.id]! < processed + 1 })
        #expect(try JSONEncoder().encode(before.recentTurns).count <= 8192)
        #expect(try JSONEncoder().encode(before.meals).count <= 24_000)
        #expect(try JSONEncoder().encode(before).count <= 60_000)
        #expect(metrics.counters.completeReads == 0 && metrics.counters.originalPhotoBytes == 0)
        #expect(metrics.counters.decodedTurnPayloads <= 90)
    }

    @Test func pendingWorkSurvivesEviction() async throws {
        var source = ChatHistoryFixture.lunchCorrectionSnapshot()
        let id = source.coachTurns[1].id
        source.coachTurns[1].state = .captured
        let photo = MealPhoto(data: SyntheticConnectionProbe.image, createdAt: source.coachTurns[1].capturedAt)
        source.coachTurns[1].photos = [photo]; source.coachTurns[1].photoIDs = [photo.id]
        let f = try CaptureFixture(snapshot: source); defer { f.remove() }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: f.root, diagnostics: metrics)
        _ = try await store.selectPagedProfile(f.profileID)
        let latest = try DiaryDatabase(url: f.url).coachPage(.latest, expectedProfileID: f.profileID)
        #expect(!latest.exchanges.contains { $0.id == id })
        metrics.reset()
        let work = try #require(try await store.nextPendingCoachTurn(includeWaitingForConnection: false, expectedProfileID: f.profileID))
        #expect(work.id == id && work.sequence == 2 && work.photos.map(\.photoID) == [photo.id])
        #expect(work.photos[0].owner == .coachTurn(id) && work.receipts.isEmpty)
        #expect(metrics.counters.decodedTurnPayloads <= 2 && metrics.counters.originalPhotoBytes == 0 && metrics.counters.completeReads == 0)
        #expect(metrics.counters.queryPlans.contains { $0.contains("INDEX") && $0.contains("coach") })
    }

    @Test func historicalDateReadAndRelativeRetryStayGrounded() async throws {
        let f = try CoachLunchFixture(); defer { f.remove() }
        let store = try await f.store(), accepted = try await f.accept(store)
        f.metrics.reset()
        let first = try await store.coachMeals(on: "2027-01-15", expectedProfileID: f.owner)
        #expect(first.localDate == "2027-01-15" && first.meals.count == 2 && !first.hasMore)
        #expect(Set(first.meals.map(\.dayID)) == Set(f.source.days.prefix(2).map(\.id)))
        #expect(first.meals.map(\.id.uuidString) == first.meals.map(\.id.uuidString).sorted())
        #expect(first.meals.allSatisfy { $0.capturedDescription.utf8.count <= 512 })
        #expect(first.meals.first { $0.id == f.mealID }?.capturedDescription.contains("lunch") == true)
        #expect(first.meals.first { $0.id == f.mealID }?.items.first?.quantity == 2)
        try await store.setCoachTurnState(turnID: accepted.id, state: .waitingForNetwork, expectedProfileID: f.owner)
        let reopened = try await f.store()
        let retry = try #require(try await reopened.nextPendingCoachTurn(includeWaitingForConnection: false, expectedProfileID: f.owner))
        #expect(retry.capturedAt == accepted.capturedAt && retry.captureTimeZoneID == accepted.captureTimeZoneID)
        #expect(try await reopened.coachMeals(on: "2027-01-15", expectedProfileID: f.owner) == first)
        await #expect(throws: DiaryError.invalidData) { try await reopened.coachMeals(on: "2027-02-30", expectedProfileID: f.owner) }
        await #expect(throws: DiaryError.wrongOwner) { try await reopened.coachMeals(on: "2027-01-15", expectedProfileID: UUID()) }
        await #expect(throws: DiaryError.invalidData) { try await reopened.coachMeals(on: "2027-01-16", afterMealID: f.mealID, expectedProfileID: f.owner) }
        f.assertOrdinaryReads()
    }

    @Test func legacyRecoveryUsesIndexedUnlinkedSubmissions() async throws {
        var source = ChatHistoryFixture.lunchCorrectionSnapshot()
        let eligible = MealSubmission(baseRevision: 1, text: "Synthetic unlinked pending correction", photoIDs: source.meals[0].photos.map(\.id), reviewFirst: false)
        source.meals[0].submissions.append(eligible)
        source.meals[1].submissions.append(MealSubmission(baseRevision: 1, text: "Cancelled", photoIDs: [], reviewFirst: false, state: .cancelled))
        let f = try CaptureFixture(snapshot: source); defer { f.remove() }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: f.root, diagnostics: metrics)
        _ = try await store.selectPagedProfile(f.profileID); metrics.reset()
        let pending = try #require(try await store.nextUnlinkedPendingSubmission(expectedProfileID: f.profileID))
        #expect(pending.submissionID == eligible.id && pending.mealID == source.meals[0].id)
        #expect(pending.photos.map(\.photoID) == eligible.photoIDs && pending.baseRevision == 1)
        _ = try await store.preparePendingCoachTurn(turnID: pending.submissionID, expectedProfileID: f.profileID)
        #expect(try await store.nextUnlinkedPendingSubmission(expectedProfileID: f.profileID) == nil)
        let recovered = try #require(try await store.nextPendingCoachTurn(includeWaitingForConnection: false, expectedProfileID: f.profileID))
        #expect(recovered.id == eligible.id && recovered.pendingMealID == pending.mealID && recovered.pendingMealRevision == 1)
        #expect(metrics.counters.completeReads == 0 && metrics.counters.completeReconciles == 0 && metrics.counters.originalPhotoBytes == 0)
        #expect(metrics.counters.queryPlans.contains { $0.contains("INDEX") && $0.contains("submission") })
    }

    @Test(arguments: [CoachTurnState.captured, .analyzing, .waitingForNetwork, .waitingForConnection, .needsRetry, .needsClarification, .completed], [false, true])
    func restartRecoversEveryEligibleWorkState(state: CoachTurnState, authorized: Bool) async throws {
        var source = ChatHistoryFixture.lunchCorrectionSnapshot()
        source.coachTurns[1].state = state
        let f = try CaptureFixture(snapshot: source); defer { f.remove() }
        let fresh = DiaryStore(directory: f.root); _ = try await fresh.selectPagedProfile(f.profileID)
        let work = try await fresh.nextPendingCoachTurn(includeWaitingForConnection: authorized, expectedProfileID: f.profileID)
        let eligible = [.captured, .analyzing, .waitingForNetwork].contains(state) || (state == .waitingForConnection && authorized)
        #expect((work != nil) == eligible)
        if eligible { #expect(work?.id == source.coachTurns[1].id && work?.state == state) }
    }

    @Test func committedReceiptsSurviveLostWorkerNotification() async throws {
        let f = try CoachLunchFixture(); defer { f.remove() }
        let store = try await f.store(), accepted = try await f.accept(store)
        await #expect(throws: CoachJourneyTransport.Interruption.afterCommit) {
            try await f.run(store, accepted.id, CoachJourneyTransport(interruptAfterCommit: true))
        }
        let fresh = try await f.store()
        let work = try await fresh.coachWorkItem(turnID: accepted.id, expectedProfileID: f.owner)
        #expect(work.receipts.count == 1)
        let receipt = try #require(work.receipts.first)
        #expect(receipt.commandFingerprint?.count == 64)
        try await fresh.setCoachTurnState(turnID: accepted.id, state: .captured, expectedProfileID: f.owner)
        let pending = try #require(try await fresh.nextPendingCoachTurn(includeWaitingForConnection: false, expectedProfileID: f.owner))
        #expect(pending.id == accepted.id && pending.receipts == [receipt])
        _ = try await f.run(fresh, pending.id, CoachJourneyTransport())
        #expect(try await fresh.coachWorkItem(turnID: pending.id, expectedProfileID: f.owner).receipts == [receipt])
        #expect(try f.applications() == 1)
        f.assertOrdinaryReads()
    }

    @Test func referencedMealEditedDuringInferenceRejectsStaleBatch() async throws {
        let f = try CoachLunchFixture(); defer { f.remove() }
        let store = try await f.store(), accepted = try await f.accept(store)
        let transport = CoachJourneyTransport(mixedWrite: true, beforeCorrection: {
            var item = try await store.meal(id: f.mealID, expectedProfileID: f.owner).items[1]; item.name = "Manually edited rice"
            try await store.editItem(mealID: f.mealID, item: item, explicitNutrients: [], expectedRevision: 1, expectedProfileID: f.owner)
            try f.clearApplications()
        })
        await #expect(throws: DiaryError.staleRevision) { try await f.run(store, accepted.id, transport) }
        let meal = try await store.meal(id: f.mealID, expectedProfileID: f.owner)
        #expect(meal.items[1].name == "Manually edited rice" && meal.items[0].quantity == 2)
        #expect(try await store.coachWorkItem(turnID: accepted.id, expectedProfileID: f.owner).receipts.isEmpty)
        #expect(try f.applications() == 0)
        #expect(try f.rows("SELECT COUNT(*) FROM weight") == [["0"]])
    }

    @Test func referencedMealDeletedDuringInferencePreservesTombstone() async throws {
        let f = try CoachLunchFixture(); defer { f.remove() }
        let store = try await f.store(), accepted = try await f.accept(store)
        let transport = CoachJourneyTransport(beforeCorrection: { try await store.deleteMeal(f.mealID, expectedProfileID: f.owner) })
        await #expect(throws: DiaryError.notFound) { try await f.run(store, accepted.id, transport) }
        #expect(try f.rows("SELECT COUNT(*) FROM tombstone WHERE id = '\(f.mealID)' ") == [["1"]])
        #expect(try f.rows("SELECT COUNT(*) FROM meal WHERE id = '\(f.mealID)' ") == [["0"]])
        #expect(try await store.coachWorkItem(turnID: accepted.id, expectedProfileID: f.owner).receipts.isEmpty)
        #expect(try f.applications() == 0)
    }

    @Test func unrelatedEditDuringInferenceAllowsValidTouchedRecords() async throws {
        let f = try CoachLunchFixture(); defer { f.remove() }
        let store = try await f.store(), accepted = try await f.accept(store)
        let otherID = f.source.meals[1].id
        let transport = CoachJourneyTransport(beforeCorrection: {
            var item = try await store.meal(id: otherID, expectedProfileID: f.owner).items[1]; item.name = "Independent rice edit"
            try await store.editItem(mealID: otherID, item: item, explicitNutrients: [], expectedRevision: 1, expectedProfileID: f.owner)
        })
        _ = try await f.run(store, accepted.id, transport)
        #expect(try await store.meal(id: f.mealID, expectedProfileID: f.owner).items[0].quantity == 3)
        #expect(try await store.meal(id: otherID, expectedProfileID: f.owner).items[1].name == "Independent rice edit")
        #expect(try f.applications() == 1)
        f.assertOrdinaryReads()
    }

    @Test func datedCandidatesAreBoundedAndCannotHideAmbiguity() async throws {
        let f = try CoachLunchFixture(ambiguity: "page"); defer { f.remove() }
        let store = try await f.store()
        let first = try await store.coachMeals(on: "2027-01-15", expectedProfileID: f.owner)
        #expect(first.meals.count == 20 && first.hasMore && first.nextAfterMealID == first.meals.last?.id)
        let next = try await store.coachMeals(on: "2027-01-15", afterMealID: first.nextAfterMealID, expectedProfileID: f.owner)
        #expect(next.meals.count == 3 && !next.hasMore && Set(first.meals.map(\.id)).isDisjoint(with: Set(next.meals.map(\.id))))
        #expect(try JSONEncoder().encode(first).count <= 65_536)
        f.assertOrdinaryReads()
    }

    @Test(arguments: ["description", "itemsOmitted"]) func datedCandidateOmissionsRemainExplicit(variant: String) async throws {
        let f = try CoachLunchFixture(ambiguity: variant); defer { f.remove() }
        let store = try await f.store()
        let page = try await store.coachMeals(on: "2027-01-15", expectedProfileID: f.owner)
        let lunch = try #require(page.meals.first { $0.id == f.mealID })
        #expect(lunch.capturedDescription.utf8.count <= 512)
        if variant == "description" { #expect(lunch.descriptionTruncated && !lunch.capturedDescription.contains("lunch")) }
        else { #expect(lunch.omittedItemCount > 0 && lunch.items.count < f.source.meals[0].items.count) }
        #expect(try JSONEncoder().encode(page).count <= 65_536)
        f.assertOrdinaryReads()
    }

    @Test func historicalDateToolUsesActualDateAndCursorArguments() throws {
        let id = UUID(), args: [String: Any] = ["target_local_date": "2027-01-15", "after_meal_id": id.uuidString]
        let call = CoachToolCall(id: "date", callID: "date", name: "get_meals_for_date", namespace: "mivu",
            arguments: String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self))
        guard case .meals(let date, let cursor) = try CoachTools.parse(call, meals: [], evidence: [:], receipts: []) else {
            Issue.record("Historical date read must dispatch through the existing tool pipeline"); return
        }
        #expect(date == "2027-01-15" && cursor == id)
        let declaration = String(decoding: try CoachTools.declarations(), as: UTF8.self)
        #expect(declaration.contains("get_meals_for_date"))
    }

    @Test(arguments: ["unknown", "changed", "mixed", "newPatch"])
    func receiptRecoveryRejectsRegeneratedIntentAcrossEngineRounds(variant: String) async throws {
        let f = try CoachLunchFixture(); defer { f.remove() }
        let store = try await f.store(), accepted = try await f.accept(store)
        try await interruptAfterWrite(store, f.owner, accepted.id) {
            try await f.run(store, accepted.id, CoachJourneyTransport(interruptAfterCommit: true))
        }
        let before = try f.businessRows(), work = try await store.coachWorkItem(turnID: accepted.id, expectedProfileID: f.owner)
        try await store.setCoachTurnState(turnID: accepted.id, state: .captured, expectedProfileID: f.owner)
        let script = CoachRecoveryScript(variant: variant)
        try await interruptAfterWrite(store, f.owner, accepted.id) {
            try await CoachEngine(store: store, infer: { try await script.infer($0, $1) }).run(turnID: accepted.id, expectedProfileID: f.owner)
        }
        #expect(try f.businessRows() == before && f.applications() == 1)
        #expect(try await store.coachWorkItem(turnID: accepted.id, expectedProfileID: f.owner).receipts == work.receipts)
        #expect(await script.rounds >= 2)
    }

    @Test func uninterruptedEntryPermitsLegitimateWritesInLaterRounds() async throws {
        let f = try CoachLunchFixture(); defer { f.remove() }
        let store = try await f.store(), accepted = try await f.accept(store, text: "Synthetic explicit weight and workout across rounds")
        let script = CoachRecoveryScript(variant: "uninterrupted")
        _ = try await CoachEngine(store: store, infer: { try await script.infer($0, $1) }).run(turnID: accepted.id, expectedProfileID: f.owner)
        let work = try await store.coachWorkItem(turnID: accepted.id, expectedProfileID: f.owner)
        #expect(work.state == .completed && work.receipts.count == 2)
        #expect(try f.rows("SELECT COUNT(*) FROM weight") == [["1"]] && f.rows("SELECT COUNT(*) FROM workout") == [["1"]])
        #expect(await script.rounds == 3)
        f.assertOrdinaryReads()
    }

    @Test(arguments: [false, true]) func legacyNilFingerprintRecoveryKeepsPriorResultAuthority(newOperation: Bool) async throws {
        let f = try CoachLunchFixture(); defer { f.remove() }
        let store = try await f.store(), accepted = try await f.accept(store)
        try await interruptAfterWrite(store, f.owner, accepted.id) {
            try await f.run(store, accepted.id, CoachJourneyTransport(interruptAfterCommit: true))
        }
        let database = try f.database
        _ = try database.transaction(expected: database.readHead(expectedProfileID: f.owner), maximumBytes: ChatHistoryFixture.maximumBytes) { transaction in
            let existing = try transaction.turn(id: accepted.id)
            var turn = try #require(existing)
            _ = try #require(turn.receipts.first)
            turn.receipts[0].commandFingerprint = nil
            try transaction.saveTurn(turn)
        }
        let fresh = try await f.store()
        try await fresh.setCoachTurnState(turnID: accepted.id, state: .captured, expectedProfileID: f.owner)
        let before = try await fresh.coachWorkItem(turnID: accepted.id, expectedProfileID: f.owner)
        let script = CoachRecoveryScript(variant: newOperation ? "unknown" : "matched")
        if newOperation {
            try await interruptAfterWrite(fresh, f.owner, accepted.id) {
                try await CoachEngine(store: fresh, infer: { try await script.infer($0, $1) }).run(turnID: accepted.id, expectedProfileID: f.owner)
            }
        } else {
            _ = try await CoachEngine(store: fresh, infer: { try await script.infer($0, $1) }).run(turnID: accepted.id, expectedProfileID: f.owner)
        }
        #expect(try await fresh.coachWorkItem(turnID: accepted.id, expectedProfileID: f.owner).receipts == before.receipts)
        #expect(try f.applications() == 1 && f.rows("SELECT COUNT(*) FROM weight") == [["0"]])
    }

    @Test(arguments: [false, true]) func workerPhotoReferencesUseExactConsumerOwnerWithCollidingUUIDs(recovery: Bool) async throws {
        let f = try CoachPhotoWorkFixture(recovery: recovery); defer { f.capture.remove() }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: f.capture.root, diagnostics: metrics)
        _ = try await store.selectPagedProfile(f.capture.profileID)
        let expected = try DiaryDatabase(url: f.capture.url).coachExchangeSummary(turnID: f.turnID, expectedProfileID: f.capture.profileID).photos
        #expect(expected.count == 1 && expected.first?.owner == .meal(f.mealID))
        metrics.reset()
        let work = try await store.coachWorkItem(turnID: f.turnID, expectedProfileID: f.capture.profileID)
        #expect(work.photos == expected)
        #expect(metrics.counters.originalPhotoBytes == 0)
        let originals = try await store.coachInferencePhotos(turnID: work.id, expectedProfileID: f.capture.profileID)
        #expect(originals == (recovery ? [] : [f.original]))
        #expect(!originals.contains(f.unconsumedOriginal))
        #expect(metrics.counters.originalPhotoBytes == (recovery ? 0 : f.original.count))
    }

    @Test func oversizedWorkReferenceMetadataRemainsValidAndRecoverySkipsOriginals() async throws {
        let f = try CoachPhotoWorkFixture(recovery: true, many: true); defer { f.capture.remove() }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: f.capture.root, diagnostics: metrics)
        _ = try await store.selectPagedProfile(f.capture.profileID)
        let expected = try DiaryDatabase(url: f.capture.url).coachExchangeSummary(turnID: f.turnID, expectedProfileID: f.capture.profileID).photos
        #expect(expected.count == 60 && Set(expected.map(\.photoID)).count == 30)
        metrics.reset()
        let work = try await store.coachWorkItem(turnID: f.turnID, expectedProfileID: f.capture.profileID)
        #expect(work.photos == expected && work.photos.count == 60)
        #expect(try await store.coachInferencePhotos(turnID: f.turnID, expectedProfileID: f.capture.profileID).isEmpty)
        #expect(metrics.counters.originalPhotoBytes == 0 && metrics.counters.completeReads == 0)
    }
}

private struct CoachPhotoWorkFixture {
    let capture: CaptureFixture
    let turnID: UUID
    let mealID: UUID
    let original = Data([1, 2, 3, 4])
    let unconsumedOriginal = Data([9, 8, 7, 6, 5])
    init(recovery: Bool, many: Bool = false) throws {
        let original = Data([1, 2, 3, 4]), unconsumedOriginal = Data([9, 8, 7, 6, 5])
        var source = ChatHistoryFixture.lunchCorrectionSnapshot()
        turnID = source.coachTurns[0].id; mealID = source.meals[0].id
        let ids = (0..<(many ? 30 : 1)).map { _ in UUID() }
        for index in 0...1 {
            let instant = source.meals[index].capturedAt
            source.meals[index].photos = ids.map { MealPhoto(id: $0, data: index == 0 ? original : unconsumedOriginal, createdAt: instant) }
            source.meals[index].submissions[0].photoIDs = ids
        }
        source.coachTurns[0].state = .captured; source.coachTurns[0].photoIDs = ids
        source.coachTurns[0].assistantText = nil
        if recovery {
            source.coachTurns[0].receipts.append(CoachReceipt(operationKey: "\(turnID)/attach_photos/\(source.meals[1].id)", turnID: turnID,
                dayID: source.meals[1].dayID, mealID: source.meals[1].id, committedRevision: 1, resultJSON: "{}"))
        } else {
            source.coachTurns[0].receipts = []; source.coachTurns[0].pendingMealID = mealID; source.coachTurns[0].pendingMealRevision = 1
        }
        // Retained bytes with the same UUID are not evidence of a live consumer link.
        if !many { source.coachTurns[0].photos = [MealPhoto(id: ids[0], data: unconsumedOriginal, createdAt: source.coachTurns[0].capturedAt)] }
        capture = try CaptureFixture(snapshot: source)
        if !many {
            try capture.execute("DELETE FROM photo_consumer WHERE turnID = '\(turnID)'")
            try capture.execute("INSERT INTO photo_consumer(ownerKind,parentID,photoID,turnID) VALUES ('meal','\(mealID)','\(ids[0])','\(turnID)')")
        }
    }
}

/// Uses real tool outputs for every correction target; only transport is synthetic.
private actor CoachRecoveryScript {
    let variant: String
    private(set) var rounds = 0
    init(variant: String) { self.variant = variant }
    func infer(_ input: [CoachInferenceInput], _ tools: Data) async throws -> CoachInferenceResult {
        rounds += 1
        if variant == "matched", rounds >= 4 { return try response([]) }
        if variant == "uninterrupted" {
            if rounds == 1 { return try response([("log_weight", ["local_date": "2027-01-15", "value": 70, "unit": "kg"])]) }
            if rounds == 2 { return try response([("log_workout", ["local_date": "2027-01-15", "kind": "cardio", "duration_minutes": 30, "exercises": []])]) }
            return try response([])
        }
        if rounds == 1 { return try response([("get_meals_for_date", ["target_local_date": "2027-01-15"])]) }
        let outputs = input.compactMap { entry -> String? in if case .functionOutput(_, let output) = entry { return output }; return nil }
        if rounds == 2 {
            let page = try JSONDecoder().decode(CoachMealCandidatePage.self, from: Data(try #require(outputs.last).utf8))
            let lunch = try #require(page.meals.first { $0.capturedDescription.contains("lunch") })
            return try response([("get_meal", ["meal_id": lunch.id.uuidString])])
        }
        let meal = try JSONDecoder().decode(CoachContext.Meal.self, from: Data(try #require(outputs.last).utf8))
        let item = try #require(meal.items.first { $0.name == "Chicken" })
        let correction: [String: Any] = ["meal_id": meal.id.uuidString, "item_id": item.id.uuidString, "expected_revision": 1, "quantity": variant == "changed" ? 4 : 3]
        let unknown: (String, [String: Any]) = ("log_weight", ["local_date": "2027-01-15", "value": 70, "unit": "kg"])
        if variant == "mixed" { return try response([("correct_item", correction), unknown]) }
        if variant == "changed" || variant == "matched" { return try response([("correct_item", correction)]) }
        if variant == "newPatch" { return try response([("edit_item", ["meal_id": meal.id.uuidString, "item_id": item.id.uuidString, "expected_revision": meal.revision, "quantity": 4])]) }
        return try response([unknown])
    }
    private func response(_ calls: [(String, [String: Any])]) throws -> CoachInferenceResult {
        let parsed = try calls.map { name, args in
            let id = UUID().uuidString
            return CoachToolCall(id: id, callID: id, name: name, namespace: "mivu",
                arguments: String(decoding: try JSONSerialization.data(withJSONObject: args, options: .sortedKeys), as: UTF8.self))
        }
        return CoachInferenceResult(model: "synthetic-recovery", text: "Read complete.", calls: parsed, outputItems: [])
    }
}
