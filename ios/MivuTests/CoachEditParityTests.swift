import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct CoachEditParityTests {
    @Test func manualEditsHaveDeclaredCoachOperations() throws {
        let object = try #require(JSONSerialization.jsonObject(with: CoachTools.declarations()) as? [String: Any])
        let declarations = try #require(object["tools"] as? [[String: Any]])
        let names = Set(declarations.compactMap { $0["name"] as? String })
        for name in ["edit_item", "append_food", "accept_review", "move_meal", "delete_meal", "attach_photos", "delete_photo", "get_goals", "set_goals", "update_preferences", "start_day", "set_day_coverage", "open_settings"] {
            #expect(names.contains(name), "Missing manual-edit operation: \(name)")
        }
    }

    @Test func coachCanEditOneNutrientWithoutReplacingOtherFoodFields() throws {
        let item = FoodItem(name: "Bread", quantity: 2, unit: "slice", nutrition: NutritionValues(kcal: 160, carbs: 30, protein: 6, fat: 2), provenance: .estimate, reference: "Synthetic")
        let meal = CoachContext.Meal(id: UUID(), dayID: UUID(), revision: 1, eatenAt: Date(), timePrecision: .dateOnly, items: [item])
        let args: [String: Any] = ["meal_id": meal.id.uuidString, "item_id": item.id.uuidString, "expected_revision": 1,
                                 "nutrients": [["nutrient": "kcal", "value": 150]]]
        let call = CoachToolCall(id: "edit", callID: "edit", name: "edit_item", namespace: "mivu", arguments: String(data: try JSONSerialization.data(withJSONObject: args), encoding: .utf8)!)
        _ = try CoachTools.parse(call, meals: [meal], evidence: [:], receipts: [])
    }
}
