import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct DiaryDeleteItemTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture(foods: [String]) async throws -> (DiaryStore, DiaryProfile, DiaryMeal, URL) {
        let root = URL.temporaryDirectory.appending(path: "DeleteItem-" + UUID().uuidString)
        let clock = now
        let store = DiaryStore(directory: root, currentTime: { clock })
        let profile = DiaryProfile(name: "Synthetic owner")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay(at: now)
        let meal = try await capturedMeal(store, text: "Synthetic breakfast", photos: [], reviewFirst: false, dayID: day.id, at: now)
        let kcal = ["Toast": 120.0, "Egg": 80.0]
        let items = foods.map { FoodItem(name: $0, quantity: 1, unit: "piece", nutrition: NutritionValues(kcal: kcal[$0]), provenance: .estimate, reference: "Synthetic") }
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id, submissionID: meal.submissions[0].id, baseRevision: 0, items: items), expectedProfileID: profile.id)
        return (store, profile, try #require(await store.snapshotForExport().meals.first), root)
    }

    @Test func deletesOneFoodAndBumpsRevision() async throws {
        let (store, profile, meal, root) = try await fixture(foods: ["Toast", "Egg"]); defer { try? FileManager.default.removeItem(at: root) }
        try await store.deleteItem(mealID: meal.id, itemID: meal.items[0].id, expectedRevision: meal.revision, expectedProfileID: profile.id)
        let after = try #require(await store.snapshotForExport().meals.first)
        #expect(after.items.map(\.name) == ["Egg"])
        #expect(after.revision == meal.revision + 1)
        #expect(after.totals.kcal == 80)
        #expect(after.submissions.last?.text == "Direct item delete" && after.submissions.last?.state == .saved)
    }

    @Test func staleRevisionDeletesNothing() async throws {
        let (store, profile, meal, root) = try await fixture(foods: ["Toast", "Egg"]); defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: DiaryError.staleRevision) {
            try await store.deleteItem(mealID: meal.id, itemID: meal.items[0].id, expectedRevision: meal.revision - 1, expectedProfileID: profile.id)
        }
        #expect(try await store.snapshotForExport().meals.first?.items.map(\.name) == ["Toast", "Egg"])
    }

    @Test func lastFoodCannotBeDeleted() async throws {
        let (store, profile, meal, root) = try await fixture(foods: ["Toast"]); defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: DiaryError.invalidData) {
            try await store.deleteItem(mealID: meal.id, itemID: meal.items[0].id, expectedRevision: meal.revision, expectedProfileID: profile.id)
        }
        #expect(try await store.snapshotForExport().meals.first?.items.count == 1)
    }

    // A pending correction is based on the current revision; deleting would strand it.
    @Test func mealWithPendingCorrectionCannotLoseAFood() async throws {
        let (store, profile, meal, root) = try await fixture(foods: ["Toast", "Egg"]); defer { try? FileManager.default.removeItem(at: root) }
        let owner = try await store.selectionOwnership(expectedProfileID: profile.id)
        let pending = try await store.correctMealProjection(mealID: meal.id, text: "Synthetic review", reviewFirst: true, expectedSelection: owner, expectedProfileID: profile.id)
        await #expect(throws: DiaryError.invalidData) {
            try await store.deleteItem(mealID: meal.id, itemID: meal.items[0].id, expectedRevision: pending.revision, expectedProfileID: profile.id)
        }
        #expect(try await store.snapshotForExport().meals.first?.items.count == 2)
    }

    @Test func unknownItemThrowsNotFound() async throws {
        let (store, profile, meal, root) = try await fixture(foods: ["Toast", "Egg"]); defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: DiaryError.notFound) {
            try await store.deleteItem(mealID: meal.id, itemID: UUID(), expectedRevision: meal.revision, expectedProfileID: profile.id)
        }
    }
}
