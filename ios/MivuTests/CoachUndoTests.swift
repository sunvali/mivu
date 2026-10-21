import Foundation
import Testing
@testable import Mivu

private actor UndoReplies {
    private var replies: [CoachInferenceResult]
    init(_ replies: [CoachInferenceResult]) { self.replies = replies }
    func next() throws -> CoachInferenceResult {
        guard !replies.isEmpty else { throw CoachError.limitExceeded }
        return replies.removeFirst()
    }
}

@Suite @MainActor struct CoachUndoTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture() async throws -> (DiaryStore, DiaryProfile, DiaryMeal, URL) {
        let root = URL.temporaryDirectory.appending(path: "CoachUndo-" + UUID().uuidString)
        let clock = now
        let store = DiaryStore(directory: root, currentTime: { clock })
        let profile = DiaryProfile(name: "Synthetic owner")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay(at: now)
        let meal = try await capturedMeal(store, text: "Synthetic dinner", photos: [], reviewFirst: false, dayID: day.id, at: now)
        let items = [FoodItem(name: "Pasta", quantity: 3, unit: "piece", nutrition: NutritionValues(kcal: 600), provenance: .estimate, reference: "Synthetic"),
                     FoodItem(name: "Sauce", quantity: 2, unit: "piece", nutrition: NutritionValues(kcal: 245), provenance: .estimate, reference: "Synthetic")]
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id, submissionID: meal.submissions[0].id, baseRevision: 0, items: items), expectedProfileID: profile.id)
        return (store, profile, try #require(await store.snapshotForExport().meals.first), root)
    }
    private func correction(_ store: DiaryStore, _ profile: DiaryProfile, _ meal: DiaryMeal) async throws -> CoachReceipt {
        let turn = try await capturedTurn(store, text: "Only one pasta", photos: [], at: now, expectedProfileID: profile.id)
        var item = meal.items[0]; item.quantity = 1
        return try await store.applyCoachItemCorrection(turnID: turn.id, mealID: meal.id, item: item, expectedRevision: meal.revision, expectedProfileID: profile.id)
    }

    private func logged(_ store: DiaryStore, _ profile: DiaryProfile) async throws -> (CoachReceipt, DiaryMeal) {
        let turn = try await capturedTurn(store, text: "Synthetic apple", photos: [], at: now, expectedProfileID: profile.id)
        let apple = FoodItem(name: "Apple", quantity: 1, unit: "piece", nutrition: NutritionValues(kcal: 95), provenance: .estimate, reference: "Synthetic")
        let receipt = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: diaryDateLabel(turn.capturedAt, zone: turn.captureTimeZoneID), items: [apple], expectedProfileID: profile.id)
        let mealID = try #require(receipt.mealID)
        return (receipt, try #require(await store.snapshotForExport().meals.first { $0.id == mealID }))
    }
    private func expectStale(_ store: DiaryStore, _ profile: DiaryProfile, _ receipt: CoachReceipt) async throws {
        let before = try await store.snapshotForExport()
        #expect(try await store.coachUndoAvailable(operationKey: receipt.operationKey, expectedProfileID: profile.id) == false)
        await #expect(throws: DiaryError.staleRevision) { try await store.undoCoachChange(operationKey: receipt.operationKey, expectedProfileID: profile.id) }
        #expect(try await store.snapshotForExport() == before)
    }
    @Test func undoHiddenAfterTextCapture() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let (receipt, meal) = try await logged(store, profile)
        let corrected = try await correctedMeal(store, mealID: meal.id, text: "Also a coffee", expectedProfileID: profile.id)
        #expect(corrected.submissions.count == meal.submissions.count + 1)
        try await expectStale(store, profile, receipt)
    }
    @Test func undoHiddenAfterPhotoAdded() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let (receipt, meal) = try await logged(store, profile)
        try await store.addPhotos(mealID: meal.id, photos: [MealPhoto(data: Data([3, 4]))], expectedProfileID: profile.id)
        try await expectStale(store, profile, receipt)
        #expect(try await store.snapshotForExport().meals.first { $0.id == meal.id }?.photos.count == 1)
    }
    @Test func undoHiddenAfterMove() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let (receipt, meal) = try await logged(store, profile)
        let other = try await store.startDay(at: now.addingTimeInterval(86_400))
        try await store.moveMeal(meal.id, to: other.id, expectedProfileID: profile.id)
        try await expectStale(store, profile, receipt)
    }
    @Test func undoCorrectionRestoresItems() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try await correction(store, profile, meal)
        #expect(try await store.snapshotForExport().meals.first?.items[0].quantity == 1)
        #expect(try await store.coachUndoAvailable(operationKey: receipt.operationKey, expectedProfileID: profile.id))
        try await store.undoCoachChange(operationKey: receipt.operationKey, expectedProfileID: profile.id)
        let after = try #require(await store.snapshotForExport().meals.first)
        #expect(after.items == meal.items)
        #expect(try await store.coachUndoAvailable(operationKey: receipt.operationKey, expectedProfileID: profile.id) == false)
        #expect(try await store.coachUndoStates(keys: [receipt.operationKey], expectedProfileID: profile.id) == [receipt.operationKey: .undone])
    }
    @Test func undoLogDeletesMeal() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await capturedTurn(store, text: "Synthetic apple", photos: [], at: now, expectedProfileID: profile.id)
        let apple = FoodItem(name: "Apple", quantity: 1, unit: "piece", nutrition: NutritionValues(kcal: 95), provenance: .estimate, reference: "Synthetic")
        let receipt = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: diaryDateLabel(turn.capturedAt, zone: turn.captureTimeZoneID), items: [apple], expectedProfileID: profile.id)
        let mealID = try #require(receipt.mealID)
        #expect(try await store.snapshotForExport().meals.contains { $0.id == mealID })
        #expect(try await store.coachUndoAvailable(operationKey: receipt.operationKey, expectedProfileID: profile.id))
        try await store.undoCoachChange(operationKey: receipt.operationKey, expectedProfileID: profile.id)
        #expect(try await store.snapshotForExport().meals.contains { $0.id == mealID } == false)
        #expect(try await store.coachUndoAvailable(operationKey: receipt.operationKey, expectedProfileID: profile.id) == false)
    }
    @Test func undoHiddenAfterManualEdit() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try await correction(store, profile, meal)
        try await store.scaleMeal(mealID: meal.id, targetKcal: 400, expectedRevision: meal.revision + 1, expectedProfileID: profile.id)
        #expect(try await store.coachUndoAvailable(operationKey: receipt.operationKey, expectedProfileID: profile.id) == false)
        await #expect(throws: DiaryError.staleRevision) { try await store.undoCoachChange(operationKey: receipt.operationKey, expectedProfileID: profile.id) }
    }
    @Test func undoChangeToolUndoesLastReceipt() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try await correction(store, profile, meal)
        let turn = try await capturedTurn(store, text: "Undo that", photos: [], at: now, expectedProfileID: profile.id)
        let undo = CoachToolCall(id: "u", callID: "u", name: "undo_change", namespace: "mivu",
            arguments: String(decoding: try JSONSerialization.data(withJSONObject: ["operation_key": receipt.operationKey]), as: UTF8.self))
        func result(_ calls: [CoachToolCall]) -> CoachInferenceResult { CoachInferenceResult(model: "fixture", text: "Undone", calls: calls, outputItems: []) }
        let replies = UndoReplies([result([undo]), result([])])
        let done = try await CoachEngine(store: store, infer: { _, _ in try await replies.next() }).run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(done.receipts.map(\.operationKey) == ["\(turn.id)/undo/\(receipt.operationKey)"])
        #expect(try await store.snapshotForExport().meals.first?.items == meal.items)
        #expect(try await store.coachUndoAvailable(operationKey: receipt.operationKey, expectedProfileID: profile.id) == false)
    }
    @Test func weightReceiptHasNoUndo() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await capturedTurn(store, text: "Weighed 70 kg", photos: [], at: now, expectedProfileID: profile.id)
        let date = diaryDateLabel(turn.capturedAt, zone: turn.captureTimeZoneID)
        let receipt = try #require(await store.applyCoachWrites([.weight(date: date, value: 70, unit: "kg", revision: nil)], turnID: turn.id,
            epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id).first)
        #expect(try await store.coachUndoAvailable(operationKey: receipt.operationKey, expectedProfileID: profile.id) == false)
        await #expect(throws: DiaryError.notFound) { try await store.undoCoachChange(operationKey: receipt.operationKey, expectedProfileID: profile.id) }
        let call = CoachToolCall(id: "u", callID: "u", name: "undo_change", namespace: "mivu",
            arguments: String(decoding: try JSONSerialization.data(withJSONObject: ["operation_key": receipt.operationKey]), as: UTF8.self))
        #expect(throws: CoachError.invalidArguments) { try CoachTools.parse(call, meals: [], evidence: [:], receipts: []) }
    }
}
