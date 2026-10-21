import Foundation
import Testing
@testable import Mivu

private actor ScaleReplies {
    private var replies: [CoachInferenceResult]
    init(_ replies: [CoachInferenceResult]) { self.replies = replies }
    func next() throws -> CoachInferenceResult {
        guard !replies.isEmpty else { throw CoachError.limitExceeded }
        return replies.removeFirst()
    }
}

@Suite @MainActor struct CoachScaleMealTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture(_ items: [FoodItem]) async throws -> (DiaryStore, DiaryProfile, DiaryMeal, URL) {
        let root = URL.temporaryDirectory.appending(path: "ScaleMeal-" + UUID().uuidString)
        let clock = now
        let store = DiaryStore(directory: root, currentTime: { clock })
        let profile = DiaryProfile(name: "Synthetic owner")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay(at: now)
        let meal = try await capturedMeal(store, text: "Synthetic dinner", photos: [], reviewFirst: false, dayID: day.id, at: now)
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id, submissionID: meal.submissions[0].id, baseRevision: 0, items: items), expectedProfileID: profile.id)
        return (store, profile, try #require(await store.snapshotForExport().meals.first), root)
    }
    private func item(_ name: String, _ quantity: Double, kcal: Double?) -> FoodItem {
        FoodItem(name: name, quantity: quantity, unit: "piece", nutrition: NutritionValues(kcal: kcal, protein: kcal.map { $0 / 10 }), provenance: .estimate, reference: "Synthetic")
    }
    private var pair: [FoodItem] { [item("Pasta", 3, kcal: 600), item("Sauce", 2, kcal: 245)] }

    @Test func scalesTwoItemsTo650() async throws {
        let (store, profile, meal, root) = try await fixture(pair); defer { try? FileManager.default.removeItem(at: root) }
        try await store.scaleMeal(mealID: meal.id, targetKcal: 650, expectedRevision: meal.revision, expectedProfileID: profile.id)
        let after = try #require(await store.snapshotForExport().meals.first)
        let total = try #require(after.totals.kcal)
        #expect((640...660).contains(total))
        #expect(after.revision == meal.revision + 1)
        for (new, old) in zip(after.items, meal.items) { #expect(abs(new.quantity / old.quantity - 0.769) < 0.01) }
        #expect(after.items.allSatisfy { ($0.quantity * 100).rounded() == $0.quantity * 100 })
    }
    @Test func refusesPendingReview() async throws {
        let (store, profile, meal, root) = try await fixture(pair); defer { try? FileManager.default.removeItem(at: root) }
        let pending = try await capturedMeal(store, text: "Synthetic snack", photos: [], reviewFirst: true, dayID: meal.dayID, at: now)
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: pending.id, submissionID: pending.submissions[0].id, baseRevision: 0, items: [item("Nuts", 1, kcal: 200)]), expectedProfileID: profile.id)
        let review = try #require(await store.snapshotForExport().meals.first { $0.id == pending.id })
        #expect(review.state != .saved)
        await #expect(throws: DiaryError.invalidData) { try await store.scaleMeal(mealID: review.id, targetKcal: 100, expectedRevision: review.revision, expectedProfileID: profile.id) }
    }
    @Test func refusesZeroKcal() async throws {
        let (store, profile, meal, root) = try await fixture([item("Water", 1, kcal: 0), item("Ice", 1, kcal: nil)]); defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: DiaryError.invalidData) { try await store.scaleMeal(mealID: meal.id, targetKcal: 100, expectedRevision: meal.revision, expectedProfileID: profile.id) }
    }
    @Test func refusesRatioAbove3AndBelowTenth() async throws {
        let (store, profile, meal, root) = try await fixture(pair); defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: DiaryError.invalidData) { try await store.scaleMeal(mealID: meal.id, targetKcal: 2600, expectedRevision: meal.revision, expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.invalidData) { try await store.scaleMeal(mealID: meal.id, targetKcal: 80, expectedRevision: meal.revision, expectedProfileID: profile.id) }
        #expect(try await store.snapshotForExport().meals.first?.revision == meal.revision)
    }
    @Test func refusesStaleRevision() async throws {
        let (store, profile, meal, root) = try await fixture(pair); defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: DiaryError.staleRevision) { try await store.scaleMeal(mealID: meal.id, targetKcal: 650, expectedRevision: meal.revision + 1, expectedProfileID: profile.id) }
    }
    @Test func unknownKcalItemScalesQuantityOnly() async throws {
        let (store, profile, meal, root) = try await fixture([item("Rice", 2, kcal: 400), item("Herbs", 4, kcal: nil)]); defer { try? FileManager.default.removeItem(at: root) }
        try await store.scaleMeal(mealID: meal.id, targetKcal: 200, expectedRevision: meal.revision, expectedProfileID: profile.id)
        let after = try #require(await store.snapshotForExport().meals.first)
        #expect(after.items.map(\.quantity) == [1, 2])
        #expect(after.items[0].nutrition.kcal == 200 && after.items[1].nutrition.kcal == nil)
    }
    @Test func parseRejectsBadArguments() throws {
        let meal = CoachContext.Meal(id: UUID(), dayID: UUID(), revision: 1, eatenAt: Date(), timePrecision: .dateOnly, items: pair)
        func parse(_ args: [String: Any]) throws -> CoachCommand {
            let call = CoachToolCall(id: "s", callID: "s", name: "scale_meal", namespace: "mivu", arguments: String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self))
            return try CoachTools.parse(call, meals: [meal], evidence: [:], receipts: [])
        }
        _ = try parse(["meal_id": meal.id.uuidString, "target_kcal": 650, "expected_revision": 1])
        #expect(throws: CoachError.invalidArguments) { try parse(["meal_id": meal.id.uuidString, "target_kcal": 0, "expected_revision": 1]) }
        #expect(throws: CoachError.invalidArguments) { try parse(["meal_id": UUID().uuidString, "target_kcal": 650, "expected_revision": 1]) }
    }
    @Test func coachMatchesManualResultAndReplaysOnce() async throws {
        let (manualStore, manualProfile, manualMeal, manualRoot) = try await fixture(pair); defer { try? FileManager.default.removeItem(at: manualRoot) }
        try await manualStore.scaleMeal(mealID: manualMeal.id, targetKcal: 650, expectedRevision: manualMeal.revision, expectedProfileID: manualProfile.id)
        let manual = try #require(await manualStore.snapshotForExport().meals.first)

        let (store, profile, meal, root) = try await fixture(pair); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await capturedTurn(store, text: "Make dinner 650", photos: [], at: now, expectedProfileID: profile.id)
        func call(_ name: String, _ args: [String: Any]) throws -> CoachToolCall {
            CoachToolCall(id: name, callID: name, name: name, namespace: "mivu", arguments: String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self))
        }
        let read = try call("get_meal", ["meal_id": meal.id.uuidString])
        let scale = try call("scale_meal", ["meal_id": meal.id.uuidString, "target_kcal": 650, "expected_revision": meal.revision])
        func result(_ calls: [CoachToolCall]) -> CoachInferenceResult { CoachInferenceResult(model: "fixture", text: "Done", calls: calls, outputItems: []) }
        let replies = ScaleReplies([result([read]), result([scale]), result([])])
        let done = try await CoachEngine(store: store, infer: { _, _ in try await replies.next() }).run(turnID: turn.id, expectedProfileID: profile.id)
        let coach = try #require(await store.snapshotForExport().meals.first)
        #expect(coach.items.map(\.quantity) == manual.items.map(\.quantity))
        #expect(coach.items.map(\.nutrition) == manual.items.map(\.nutrition))
        let receipt = try #require(done.receipts.first)
        #expect(receipt.mealID == meal.id && receipt.dayID == meal.dayID)
        #expect(coach.revision == meal.revision + 1)
    }
}
