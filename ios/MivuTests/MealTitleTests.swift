import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct MealTitleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func food(_ name: String, _ calories: Double = 100) -> FoodItem {
        FoodItem(name: name, quantity: 1, unit: "portion", nutrition: NutritionValues(kcal: calories), provenance: .estimate, reference: "Synthetic estimate")
    }

    @Test func titleNamesTheMealOnlyWhileItsFoodsStillMatch() {
        let rice = food("Rice"), chicken = food("Chicken"), title = MealTitle(text: "Chicken and rice", foods: ["Rice", "Chicken"])
        #expect(mealTitle(items: [rice], title: nil, note: "") == "Rice")
        #expect(mealTitle(items: [chicken, rice], title: title, note: "") == "Chicken and rice")
        #expect(mealTitle(items: [rice, chicken], title: nil, note: "") == "Rice, Chicken")
        #expect(mealTitle(items: [rice, chicken, food("Salad"), food("Tea")], title: nil, note: "") == "Rice, Chicken +2")
        #expect(mealTitle(items: [rice, food("Salad")], title: title, note: "") == "Rice, Salad")
        #expect(mealTitle(items: [], title: nil, note: "  rice and chicken ") == "rice and chicken")
    }

    @Test func logFoodParsesAnOptionalMealTitle() throws {
        let args: [String: Any] = ["target_local_date": "2027-01-15", "eaten_at": NSNull(), "review_first": NSNull(), "meal_title": "Chicken and rice",
            "items": [["name": "Rice", "quantity": 1, "unit": "cup", "kcal": 200, "carbs": NSNull(), "protein": NSNull(), "fat": NSNull(), "evidence_id": NSNull(), "from_label": false]]]
        let call = CoachToolCall(id: "log", callID: "log", name: "log_food", namespace: "mivu", arguments: String(data: try JSONSerialization.data(withJSONObject: args), encoding: .utf8)!)
        guard case .write(.food(_, _, _, _, let title)) = try CoachTools.parse(call, meals: [], evidence: [:], receipts: []) else { Issue.record("not a food write"); return }
        #expect(title == "Chicken and rice")
    }

    @Test func coachTitlesMealsAndManualFoodChangesFallBackToNames() async throws {
        let root = URL.temporaryDirectory.appending(path: "MealTitle-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let clock = now, store = DiaryStore(directory: root, currentTime: { clock }), profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay(at: now)
        let epoch = try await store.selectionEpoch(expectedProfileID: profile.id)
        let first = try await capturedTurn(store, text: "Rice and chicken", photos: [], at: now, expectedProfileID: profile.id)
        let receipt = try await store.applyCoachWrites([.food(date: "2027-01-15", items: [food("Rice"), food("Chicken")], eatenAt: nil, title: "Chicken and rice")],
            turnID: first.id, epoch: epoch, expectedProfileID: profile.id)[0]
        let id = try #require(receipt.mealID)
        var meal = try await store.meal(id: id, expectedProfileID: profile.id)
        #expect(meal.displayTitle == "Chicken and rice")

        var rice = meal.items[0]; rice.quantity = 2
        try await store.editItem(mealID: id, item: rice, explicitNutrients: [], expectedRevision: meal.revision, expectedProfileID: profile.id)
        meal = try await store.meal(id: id, expectedProfileID: profile.id)
        #expect(meal.displayTitle == "Chicken and rice")

        let add = try await capturedTurn(store, text: "Also a salad", photos: [], at: now, expectedProfileID: profile.id)
        _ = try await store.applyCoachWrites([.manual(.append(mealID: id, items: [food("Salad")], revision: meal.revision, title: "Chicken, rice and salad"))],
            turnID: add.id, epoch: epoch, expectedProfileID: profile.id)
        meal = try await store.meal(id: id, expectedProfileID: profile.id)
        #expect(meal.displayTitle == "Chicken, rice and salad")

        try await store.deleteItem(mealID: id, itemID: meal.items[1].id, expectedRevision: meal.revision, expectedProfileID: profile.id)
        meal = try await store.meal(id: id, expectedProfileID: profile.id)
        #expect(meal.displayTitle == "Rice, Salad")
    }
}
