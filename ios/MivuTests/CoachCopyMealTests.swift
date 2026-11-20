import Foundation
import Testing
@testable import Mivu

@Suite struct CoachCopyMealTests {
    private let source = CoachContext.Meal(id: UUID(), dayID: UUID(), revision: 3, eatenAt: Date(), timePrecision: nil, items: [
        FoodItem(name: "Oats", quantity: 1, unit: "bowl", nutrition: NutritionValues(kcal: 250, carbs: 40, protein: 8, fat: 5), provenance: .estimate, reference: "Synthetic oats"),
        FoodItem(name: "Coffee", quantity: 1, unit: "cup", nutrition: NutritionValues(kcal: 70, carbs: 6, protein: 4, fat: 3), provenance: .estimate, reference: "Synthetic coffee")])

    private func call(_ args: [String: Any]) -> CoachToolCall {
        CoachToolCall(id: "copy", callID: "copy", name: "copy_meal", namespace: "mivu",
                      arguments: String(decoding: try! JSONSerialization.data(withJSONObject: args), as: UTF8.self))
    }
    private func args(revision: Int = 3, mealID: UUID? = nil, eatenAt: Any = NSNull()) -> [String: Any] {
        ["source_meal_id": (mealID ?? source.id).uuidString, "expected_revision": revision, "target_local_date": "2027-03-02", "eaten_at": eatenAt]
    }

    @Test func copyMealCopiesItemsWithNewIDs() throws {
        guard case .write(.food(let date, let items, let eatenAt, let reviewFirst, _)) = try CoachTools.parse(call(args()), meals: [source], evidence: [:], receipts: [])
        else { Issue.record("copy_meal must write food"); return }
        #expect(date == "2027-03-02" && eatenAt == nil && !reviewFirst)
        #expect(items.map(\.name) == ["Oats", "Coffee"] && items.map(\.quantity) == [1, 1] && items.map(\.unit) == ["bowl", "cup"])
        #expect(items.map(\.nutrition) == source.items.map(\.nutrition))
        #expect(Set(items.map(\.id)).isDisjoint(with: source.items.map(\.id)))
    }

    @Test func copyMealRefusesAStaleRevisionOrUnknownMeal() {
        #expect(throws: CoachError.invalidArguments) { try CoachTools.parse(call(args(revision: 2)), meals: [source], evidence: [:], receipts: []) }
        #expect(throws: CoachError.invalidArguments) { try CoachTools.parse(call(args(mealID: UUID())), meals: [source], evidence: [:], receipts: []) }
    }

    @Test func copyMealKeepsEatenAtRules() throws {
        guard case .write(.food(_, _, let other, _, _)) = try CoachTools.parse(call(args(eatenAt: "2027-02-20 08:00")), meals: [source], evidence: [:], receipts: [], zone: "UTC"),
              case .write(.food(_, _, let same, _, _)) = try CoachTools.parse(call(args(eatenAt: "2027-03-02 08:00")), meals: [source], evidence: [:], receipts: [], zone: "UTC")
        else { Issue.record("copy_meal must write food"); return }
        #expect(other == nil)
        #expect(same == diaryLocalInstant("2027-03-02 08:00", zone: "UTC"))
    }

    @Test func copyMealIsDeclared() throws {
        let object = try #require(JSONSerialization.jsonObject(with: CoachTools.declarations()) as? [String: Any])
        let names = (object["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        #expect(names.contains("copy_meal"))
    }
}
