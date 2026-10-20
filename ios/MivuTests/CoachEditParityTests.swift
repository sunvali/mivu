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

    @Test func parsedEqualAndNullTotalsKeepIntentThroughSharedCorrection() throws {
        let item = FoodItem(name: "Bread", quantity: 2, unit: "pieces", nutrition: NutritionValues(kcal: 160, carbs: 30, protein: 20))
        let meal = CoachContext.Meal(id: UUID(), dayID: UUID(), revision: 1, eatenAt: Date(), timePrecision: .dateOnly, items: [item])
        let args: [String: Any] = ["meal_id": meal.id.uuidString, "item_id": item.id.uuidString, "expected_revision": 1, "quantity": 4,
                                 "nutrients": [["nutrient": "kcal", "value": 160], ["nutrient": "carbs", "value": NSNull()]]]
        let call = CoachToolCall(id: "intent", callID: "intent", name: "edit_item", namespace: "mivu", arguments: String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self))
        guard case .write(.manual(.item(_, let edited, _, _, let explicit, let original), _)) = try CoachTools.parse(call, meals: [meal], evidence: [:], receipts: []) else { Issue.record("Expected item edit"); return }
        let result = try diaryCorrectedItem(edited, previous: original, explicitNutrients: explicit)
        #expect(result.nutrition.kcal == 160 && result.nutrition.carbs == nil && result.nutrition.protein == 40)
    }
    @Test func directFingerprintDistinguishesExplicitSameValueAndNullFromOmission() throws {
        let original = FoodItem(name: "Bread", quantity: 2, unit: "pieces", nutrition: NutritionValues(kcal: 160, protein: 20))
        var item = original; item.quantity = 4
        let mealID = UUID()
        func write(_ explicit: Set<String>) -> CoachWrite {
            .manual(.item(mealID: mealID, item: item, revision: 1, submissionID: nil, explicitNutrients: explicit, original: original))
        }
        let omitted = try write([]).commandFingerprint()
        #expect(try write(["kcal"]).commandFingerprint() != omitted)
        #expect(try write(["carbs"]).commandFingerprint() != omitted)
    }
    @Test func quantityOnlyCorrectionKeepsLegacyFingerprint() throws {
        var item = FoodItem(name: "Bread", quantity: 3, unit: "pieces", nutrition: NutritionValues(kcal: 200))
        item.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let write = CoachWrite.correction(mealID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, item: item, revision: 1)
        #expect(try write.commandFingerprint() == "0aa23f03418837b897250ff0bf14d07140f7eb50c10fff3487c2f80042aef3a0")
    }
}
