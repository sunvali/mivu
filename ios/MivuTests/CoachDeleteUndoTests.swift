import Foundation
import Testing
@testable import Mivu

private actor DeleteUndoReplies {
    private var replies: [CoachInferenceResult]
    init(_ replies: [CoachInferenceResult]) { self.replies = replies }
    func next() throws -> CoachInferenceResult {
        guard !replies.isEmpty else { throw CoachError.limitExceeded }
        return replies.removeFirst()
    }
}

private final class TestClock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_800_000_000) }

/// Coach deletes stay instant but keep a short-lived, unexported copy for Undo.
@Suite @MainActor struct CoachDeleteUndoTests {
    private let clock = TestClock()
    private let photoBytes = Data([1, 2, 3])

    private func fixture() async throws -> (DiaryStore, DiaryProfile, DiaryMeal, URL) {
        let root = URL.temporaryDirectory.appending(path: "CoachDeleteUndo-" + UUID().uuidString)
        let clock = clock
        let store = DiaryStore(directory: root, currentTime: { clock.now })
        let profile = DiaryProfile(name: "Synthetic owner")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay(at: clock.now)
        let meal = try await capturedMeal(store, text: "Synthetic lunch", photos: [], reviewFirst: false, dayID: day.id, at: clock.now)
        let items = [FoodItem(name: "Rice", quantity: 1, unit: "cup", nutrition: NutritionValues(kcal: 200), provenance: .estimate, reference: "Synthetic"),
                     FoodItem(name: "Beans", quantity: 1, unit: "cup", nutrition: NutritionValues(kcal: 220), provenance: .estimate, reference: "Synthetic")]
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id, submissionID: meal.submissions[0].id, baseRevision: 0, items: items), expectedProfileID: profile.id)
        try await store.addPhotos(mealID: meal.id, photos: [MealPhoto(data: photoBytes)], expectedProfileID: profile.id)
        return (store, profile, try #require(await store.snapshotForExport().meals.first), root)
    }

    /// Captures a fresh turn and applies `writes` the way the Coach engine does.
    private func coach(_ store: DiaryStore, _ profile: DiaryProfile, _ writes: [CoachWrite], text: String = "Synthetic request") async throws -> [CoachReceipt] {
        let turn = try await capturedTurn(store, text: text, photos: [], at: clock.now, expectedProfileID: profile.id)
        let epoch = try await store.selectionEpoch(expectedProfileID: profile.id)
        return try await store.applyCoachWrites(writes, turnID: turn.id, epoch: epoch, expectedProfileID: profile.id)
    }

    private func available(_ store: DiaryStore, _ profile: DiaryProfile, _ receipt: CoachReceipt) async throws -> Bool {
        try await store.coachUndoAvailable(operationKey: receipt.operationKey, expectedProfileID: profile.id)
    }

    @Test func deleteMealHoldsSnapshotWithPhotos() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try #require(try await coach(store, profile, [.manual(.deleteMeal(mealID: meal.id, revision: meal.revision))]).first)
        #expect(try await available(store, profile, receipt))
        let exported = try await store.snapshotForExport()
        #expect(!exported.meals.contains { $0.id == meal.id })
        // The held photo never travels with an export or backup.
        let archive = try JSONEncoder().encode(exported)
        #expect(!String(decoding: archive, as: UTF8.self).contains(photoBytes.base64EncodedString()))
    }

    @Test func deleteWeightAndWorkoutHoldSnapshots() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let weight = try await store.setWeight(dayID: meal.dayID, value: 70, expectedRevision: nil, expectedProfileID: profile.id)
        let draft = WorkoutDraft(kind: .cardio, durationMinutes: 30, exercises: [], estimatedBurnKcal: nil, burnSource: nil)
        let workout = try await store.createWorkout(dayID: meal.dayID, draft: draft, expectedProfileID: profile.id)
        let receipts = try await coach(store, profile, [.deleteWeight(id: weight.id, revision: weight.revision), .deleteWorkout(id: workout.id, revision: workout.revision)])
        #expect(receipts.count == 2)
        for receipt in receipts { #expect(try await available(store, profile, receipt)) }
    }

    private func heldCount(_ root: URL, _ profile: DiaryProfile) throws -> Int {
        try DiaryDatabase(url: root.appending(path: profile.id.uuidString + ".sqlite/diary.sqlite")).mutationInteger("SELECT COUNT(*) FROM coach_undo_deleted")
    }
    private func deletedMeal(_ store: DiaryStore, _ profile: DiaryProfile, _ meal: DiaryMeal) async throws -> CoachReceipt {
        try #require(try await coach(store, profile, [.manual(.deleteMeal(mealID: meal.id, revision: meal.revision))]).first)
    }

    @Test func undoExpiresAfterTenMinutes() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try await deletedMeal(store, profile, meal)
        clock.now += 601
        #expect(try await available(store, profile, receipt) == false)
        let reopened = DiaryStore(directory: root, currentTime: { [clock] in clock.now })
        _ = try await reopened.selectPagedProfile(profile.id)
        #expect(try heldCount(root, profile) == 0)
    }

    @Test func lateUndoSaysItIsNoLongerAvailable() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try await deletedMeal(store, profile, meal)
        clock.now += 601
        await #expect(throws: DiaryError.undoExpired) { try await undo(store, profile, receipt) }
        #expect(DiaryError.undoExpired.errorDescription == "Undo is no longer available.")
        // The same tap, once the held copy has already gone.
        _ = try await store.expireCoachUndo(expectedProfileID: profile.id)
        #expect(try heldCount(root, profile) == 0)
        await #expect(throws: DiaryError.undoExpired) { try await undo(store, profile, receipt) }
    }

    @Test func expiringReportsTheTimeLeftAndKeepsTheUndoneCard() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(try await store.expireCoachUndo(expectedProfileID: profile.id) == nil)
        let receipt = try await deletedMeal(store, profile, meal)
        clock.now += 100
        #expect(try await store.expireCoachUndo(expectedProfileID: profile.id) == 500)
        try await undo(store, profile, receipt)
        #expect(try await store.expireCoachUndo(expectedProfileID: profile.id) == nil)
        clock.now += 501
        _ = try await store.expireCoachUndo(expectedProfileID: profile.id)
        #expect(try await store.coachUndoStates(keys: [receipt.operationKey], expectedProfileID: profile.id)[receipt.operationKey] == .undone)
        let held = try DiaryDatabase(url: root.appending(path: profile.id.uuidString + ".sqlite/diary.sqlite"))
            .mutationInteger("SELECT COALESCE(SUM(LENGTH(payload)), 0) FROM coach_undo_deleted")
        #expect(held == 0)
    }

    @Test func openCoachDropsUndoAndHeldBytesAtTheTenMinuteMark() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = DiaryDatabase.coachCommittedReceipt(try await deletedMeal(store, profile, meal))
        let diary = DiaryViewModel(store: store); await diary.load(createDefaultProfile: false)
        let clock = clock, deadline = clock.now + 600
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), sleep: { _ in
            while clock.now <= deadline { try await Task.sleep(for: .milliseconds(5)) }
        })
        let connected = Task { await coach.connectTimeline() }; defer { connected.cancel() }
        func waitUntil(_ done: () -> Bool) async throws {
            for _ in 0..<2_000 where !done() { try await Task.sleep(for: .milliseconds(5)) }
            #expect(done())
        }
        try await waitUntil { coach.undoState(receipt) == .available }
        clock.now += 601
        try await waitUntil { coach.undoState(receipt) == nil }
        #expect(try heldCount(root, profile) == 0)
        await coach.undo(receipt)
        #expect(diary.errorMessage == "Undo is no longer available.")
    }

    @Test func buttonHidesAfterNextMessageButRowSurvivesOneTurn() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try await deletedMeal(store, profile, meal)
        _ = try await capturedTurn(store, text: "Next message", photos: [], at: clock.now, expectedProfileID: profile.id)
        #expect(try await available(store, profile, receipt) == false)
        #expect(try heldCount(root, profile) == 1)
        _ = try await capturedTurn(store, text: "Message after that", photos: [], at: clock.now, expectedProfileID: profile.id)
        #expect(try heldCount(root, profile) == 0)
    }

    @Test func deletingProfileRemovesHeldBytes() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await deletedMeal(store, profile, meal)
        let other = DiaryProfile(name: "Synthetic second")
        _ = try await store.createProfile(other)
        let file = root.appending(path: profile.id.uuidString + ".sqlite")
        try await store.deleteProfile(profile.id)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func undoOfLoggedMealHoldsSnapshot() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await capturedTurn(store, text: "Synthetic apple", photos: [], at: clock.now, expectedProfileID: profile.id)
        let apple = FoodItem(name: "Apple", quantity: 1, unit: "piece", nutrition: NutritionValues(kcal: 95), provenance: .estimate, reference: "Synthetic")
        let logged = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: diaryDateLabel(turn.capturedAt, zone: turn.captureTimeZoneID), items: [apple], expectedProfileID: profile.id)
        let undo = try #require(try await coach(store, profile, [.manual(.undo(operationKey: logged.operationKey))]).first)
        #expect(try await available(store, profile, undo))
    }

    private func undo(_ store: DiaryStore, _ profile: DiaryProfile, _ receipt: CoachReceipt) async throws {
        try await store.undoCoachChange(operationKey: receipt.operationKey, expectedProfileID: profile.id)
    }
    private func tombstoned(_ root: URL, _ profile: DiaryProfile, _ id: UUID) throws -> Bool {
        try DiaryDatabase(url: root.appending(path: profile.id.uuidString + ".sqlite/diary.sqlite")).mutationInteger("SELECT COUNT(*) FROM tombstone WHERE id = ?", [.text(id.uuidString)]) == 1
    }
    private func voiceUndo(_ store: DiaryStore, _ profile: DiaryProfile, _ key: String) async throws -> CoachTurnResult {
        let turn = try await capturedTurn(store, text: "Undo that", photos: [], at: clock.now, expectedProfileID: profile.id)
        let call = CoachToolCall(id: "u", callID: "u", name: "undo_change", namespace: "mivu",
            arguments: String(decoding: try JSONSerialization.data(withJSONObject: ["operation_key": key]), as: UTF8.self))
        let replies = DeleteUndoReplies([CoachInferenceResult(model: "fixture", text: "Undone", calls: [call], outputItems: []), CoachInferenceResult(model: "fixture", text: "Undone", calls: [], outputItems: [])])
        return try await CoachEngine(store: store, infer: { _, _ in try await replies.next() }).run(turnID: turn.id, expectedProfileID: profile.id)
    }

    @Test func undoRestoresMealUnderNewIDWithPhotos() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try await deletedMeal(store, profile, meal)
        try await undo(store, profile, receipt)
        let restored = try #require(try await store.snapshotForExport().meals.first)
        #expect(restored.id != meal.id && restored.dayID == meal.dayID && restored.state == meal.state)
        #expect(restored.items.map(\.name) == ["Rice", "Beans"] && restored.items.map(\.nutrition.kcal) == [200, 220])
        #expect(restored.photos.map(\.data) == [photoBytes])
        #expect(try tombstoned(root, profile, meal.id))
        #expect(try await store.coachUndoStates(keys: [receipt.operationKey], expectedProfileID: profile.id)[receipt.operationKey] == .undone)
    }

    @Test func undoRestoresPhotoToExistingMeal() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let photo = try #require(meal.photos.first)
        let receipt = try #require(try await coach(store, profile, [.manual(.deletePhoto(mealID: meal.id, photoID: photo.id, revision: meal.revision))]).first)
        #expect(try await store.snapshotForExport().meals.first?.photos.isEmpty == true)
        try await undo(store, profile, receipt)
        #expect(try await store.snapshotForExport().meals.first?.photos.map(\.data) == [photoBytes])
    }

    @Test func undonePhotoComesBackUnderANewIDSoItsDeleteStillReplays() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let photo = try #require(meal.photos.first)
        let delete = CoachWrite.manual(.deletePhoto(mealID: meal.id, photoID: photo.id, revision: meal.revision))
        let receipt = try #require(try await coach(store, profile, [delete]).first)
        try await undo(store, profile, receipt)
        #expect(try await store.snapshotForExport().meals.first?.photos.map(\.id).contains(photo.id) == false)
        let turnID = try #require(UUID(uuidString: String(receipt.operationKey.prefix(36))))
        try await store.validateCoachWrites([delete], turnID: turnID, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id, mode: .replayOnly)
    }

    @Test func photoUndoRefusedWhenMealGone() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let photo = try #require(meal.photos.first)
        let receipt = try #require(try await coach(store, profile, [.manual(.deletePhoto(mealID: meal.id, photoID: photo.id, revision: meal.revision))]).first)
        try await store.deleteMeal(meal.id, expectedProfileID: profile.id)
        await #expect(throws: DiaryError.notFound) { try await undo(store, profile, receipt) }
    }

    @Test func weightUndoRefusedWhenDayHasWeight() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let weight = try await store.setWeight(dayID: meal.dayID, value: 70, expectedRevision: nil, expectedProfileID: profile.id)
        let receipt = try #require(try await coach(store, profile, [.deleteWeight(id: weight.id, revision: weight.revision)]).first)
        _ = try await store.setWeight(dayID: meal.dayID, value: 71, expectedRevision: nil, expectedProfileID: profile.id)
        await #expect(throws: DiaryError.staleRevision) { try await undo(store, profile, receipt) }
    }

    @Test func weightAndWorkoutUndoRestore() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let weight = try await store.setWeight(dayID: meal.dayID, value: 70, expectedRevision: nil, expectedProfileID: profile.id)
        let draft = WorkoutDraft(kind: .cardio, durationMinutes: 30, exercises: [], estimatedBurnKcal: nil, burnSource: nil)
        let workout = try await store.createWorkout(dayID: meal.dayID, draft: draft, expectedProfileID: profile.id)
        let receipts = try await coach(store, profile, [.deleteWeight(id: weight.id, revision: weight.revision), .deleteWorkout(id: workout.id, revision: workout.revision)])
        for receipt in receipts { try await undo(store, profile, receipt) }
        let exported = try await store.snapshotForExport()
        #expect(exported.weights.map(\.value) == [70] && exported.weights.first?.id != weight.id)
        #expect(exported.workouts.map(\.durationMinutes) == [30] && exported.workouts.first?.id != workout.id)
    }

    @Test func secondUndoIsStale() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try await deletedMeal(store, profile, meal)
        try await undo(store, profile, receipt)
        await #expect(throws: DiaryError.staleRevision) { try await undo(store, profile, receipt) }
        #expect(try await store.snapshotForExport().meals.count == 1)
    }

    @Test func voiceUndoWorksInTheNextMessage() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try await deletedMeal(store, profile, meal)
        let done = try await voiceUndo(store, profile, receipt.operationKey)
        #expect(done.receipts.count == 1)
        #expect(try await store.snapshotForExport().meals.count == 1)
    }

    @Test func voiceUndoRefusedTwoMessagesLater() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try await deletedMeal(store, profile, meal)
        _ = try await capturedTurn(store, text: "Something else", photos: [], at: clock.now, expectedProfileID: profile.id)
        let done = try? await voiceUndo(store, profile, receipt.operationKey)
        #expect(done?.receipts.isEmpty ?? true)
        #expect(try await store.snapshotForExport().meals.isEmpty)
    }

    @Test func undoOfUndoRecreatesLoggedMeal() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await store.deleteMeal(meal.id, expectedProfileID: profile.id)
        let turn = try await capturedTurn(store, text: "Synthetic apple", photos: [], at: clock.now, expectedProfileID: profile.id)
        let apple = FoodItem(name: "Apple", quantity: 1, unit: "piece", nutrition: NutritionValues(kcal: 95), provenance: .estimate, reference: "Synthetic")
        let logged = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: diaryDateLabel(turn.capturedAt, zone: turn.captureTimeZoneID), items: [apple], expectedProfileID: profile.id)
        let removal = try #require(try await coach(store, profile, [.manual(.undo(operationKey: logged.operationKey))]).first)
        #expect(try await store.snapshotForExport().meals.isEmpty)
        try await undo(store, profile, removal)
        #expect(try await store.snapshotForExport().meals.flatMap(\.items).map(\.name) == ["Apple"])
    }

    @Test func undoChangeAcceptsDeleteKeysOnly() throws {
        func parse(_ key: String) throws -> CoachCommand {
            let call = CoachToolCall(id: "u", callID: "u", name: "undo_change", namespace: "mivu",
                arguments: String(decoding: try JSONSerialization.data(withJSONObject: ["operation_key": key]), as: UTF8.self))
            return try CoachTools.parse(call, meals: [], evidence: [:], receipts: [])
        }
        let turn = UUID().uuidString, id = UUID().uuidString
        for kind in ["delete_meal/\(id)", "delete_photo/\(id)/\(id)", "delete_weight/\(id)", "delete_workout/\(id)", "undo/\(turn)/food/2027-01-01"] {
            #expect(throws: Never.self) { try parse("\(turn)/\(kind)") }
        }
        #expect(throws: CoachError.invalidArguments) { try parse("\(turn)/open_settings/x") }
    }

    @Test func undoChangeToolOffersDeletes() throws {
        let root = try #require(JSONSerialization.jsonObject(with: CoachTools.declarations()) as? [String: Any])
        let tools = try #require(root["tools"] as? [[String: Any]])
        let text = try #require(tools.first { $0["name"] as? String == "undo_change" }?["description"] as? String)
        for tool in ["delete_meal", "delete_photo", "delete_weight", "delete_workout"] { #expect(text.contains(tool)) }
        #expect(!text.contains("Not for whole-meal"))
    }

    @Test func deleteResultTellsTheModelHowToUndo() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try await deletedMeal(store, profile, meal)
        #expect(receipt.resultJSON.contains("\"undo_key\"") && receipt.resultJSON.contains("next message"))
    }

    @Test func voiceUndoReceiptIsNotLabelledRemoved() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let deleted = DiaryDatabase.coachCommittedReceipt(try await deletedMeal(store, profile, meal))
        let undone = DiaryDatabase.coachCommittedReceipt(try #require(try await voiceUndo(store, profile, deleted.operationKey).receipts.first))
        #expect(CoachReceiptPresentation(receipt: deleted, target: .unavailable).committedStatus == "Removed")
        #expect(CoachReceiptPresentation(receipt: undone, target: .loading).committedStatus != "Removed")
        #expect(!CoachReceiptPresentation(receipt: undone, target: .loading).isRemoval)
    }

    @Test func removalCardsShowFromTheReceiptAlone() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let weight = try await store.setWeight(dayID: meal.dayID, value: 70, expectedRevision: nil, expectedProfileID: profile.id)
        let receipt = DiaryDatabase.coachCommittedReceipt(try #require(try await coach(store, profile, [.deleteWeight(id: weight.id, revision: weight.revision)]).first))
        #expect(CoachReceiptPresentation.showsCard(receipt))
    }

    @Test func captureSurvivesAFailedUndoPurge() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await deletedMeal(store, profile, meal)
        try DiaryDatabase(url: root.appending(path: profile.id.uuidString + ".sqlite/diary.sqlite"))
            .execute("CREATE TRIGGER block_purge BEFORE DELETE ON coach_undo_deleted BEGIN SELECT RAISE(ABORT, 'synthetic purge failure'); END")
        clock.now += 601
        _ = try await capturedTurn(store, text: "Next message", photos: [], at: clock.now, expectedProfileID: profile.id)
        let reopened = DiaryStore(directory: root, currentTime: { [clock] in clock.now })
        _ = try await reopened.selectPagedProfile(profile.id)
    }

    @Test func historyMarksMealsDeletedSince() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await capturedTurn(store, text: "Synthetic apple", photos: [], at: clock.now, expectedProfileID: profile.id)
        let apple = FoodItem(name: "Apple", quantity: 1, unit: "piece", nutrition: NutritionValues(kcal: 95), provenance: .estimate, reference: "Synthetic")
        let logged = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: diaryDateLabel(turn.capturedAt, zone: turn.captureTimeZoneID), items: [apple], expectedProfileID: profile.id)
        let appleID = try #require(logged.mealID)
        try await store.deleteMeal(appleID, expectedProfileID: profile.id)
        let next = try await capturedTurn(store, text: "Make it bigger", photos: [], at: clock.now, expectedProfileID: profile.id)
        let line = try #require(try await store.coachContext(turnID: next.id, expectedProfileID: profile.id).recentTurns.compactMap(\.receipts).first { $0.contains(appleID.uuidString) })
        #expect(line.contains("meal=\(appleID.uuidString) deleted"))
        #expect(meal.id != appleID)
    }

    @Test func historyLeavesLiveMealsUnmarked() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await capturedTurn(store, text: "Synthetic apple", photos: [], at: clock.now, expectedProfileID: profile.id)
        let apple = FoodItem(name: "Apple", quantity: 1, unit: "piece", nutrition: NutritionValues(kcal: 95), provenance: .estimate, reference: "Synthetic")
        _ = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: diaryDateLabel(turn.capturedAt, zone: turn.captureTimeZoneID), items: [apple], expectedProfileID: profile.id)
        let next = try await capturedTurn(store, text: "Make it bigger", photos: [], at: clock.now, expectedProfileID: profile.id)
        let lines = try await store.coachContext(turnID: next.id, expectedProfileID: profile.id).recentTurns.compactMap(\.receipts)
        #expect(!lines.isEmpty && lines.allSatisfy { !$0.contains("deleted") })
    }
}
