import Foundation
import CoreFoundation

enum CoachWrite: Sendable {
    case food(date: String, items: [FoodItem], eatenAt: Date?)
    case correction(mealID: UUID, item: FoodItem, revision: Int)
    case close(date: String, completeness: DayCompleteness)
    var target: String {
        switch self {
        case .food(let date, _, _): "food/\(date)"
        case .correction(let meal, let item, _): "correct/\(meal.uuidString)/\(item.id.uuidString)"
        case .close(let date, _): "close/\(date)"
        }
    }
}

enum CoachCommand: Sendable {
    case context
    case meal(UUID)
    case lookup(String)
    case write(CoachWrite)
}

/// Only these six declared operations cross the model-to-diary boundary.
enum CoachTools {
    static let namespace = "mivu"
    static func declarations() throws -> Data {
        func object(_ properties: [String: Any], required: [String]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
        }
        let string: [String: Any] = ["type": "string"]
        let number: [String: Any] = ["type": ["number", "null"]]
        let food = object(["name": string, "quantity": ["type":"number"], "unit": string,
            "kcal": number, "carbs": number, "protein": number, "fat": number,
            "evidence_id": ["type":["integer", "null"]]], required: ["name", "quantity", "unit", "kcal", "carbs", "protein", "fat"])
        let schemas: [(String, String, [String: Any])] = [
            ("get_context", "Read actual bounded diary and capture clock. truncated and omittedMeals explicitly mark details not included.", object([:], required: [])),
            ("get_meal", "Retrieve actual owner-scoped meal by UUID before correction. omittedItemCount marks unavailable details requiring manual review.", object(["meal_id": string], required: ["meal_id"])),
            ("lookup_nutrition", "Search retrieved nutrition evidence; unavailable means use clearly uncertain estimates.", object(["query":string], required: ["query"])),
            ("log_food", "Log all new foods for this turn/date once. On a saved manual meal append only newly named foods, preserving every existing item; correct existing foods with correct_item. Nutrition numbers are portion totals; only retrieved evidence_id with grams replaces estimates. Direct chat remains date-only; exact time requires a manual UI capture. Optional eaten_at is accepted for compatibility but cannot establish a confirmed time.", object(["target_local_date":string, "items":["type":"array", "items":food], "eaten_at":string], required: ["target_local_date", "items"])),
            ("correct_item", "Correct only quantity on a retrieved actual item, preserving its nutrition basis and sources.", object(["meal_id":string,"item_id":string,"expected_revision":["type":"integer"],"quantity":["type":"number"]], required: ["meal_id","item_id","expected_revision","quantity"])),
            ("close_day", "Explicitly close a local date as complete, partial, untracked or unknown; retain existing food.", object(["local_date":string,"completeness":["type":"string","enum":DayCompleteness.allCases.map(\.rawValue)]], required: ["local_date","completeness"]))
        ]
        let tools = schemas.map { ["type":"function", "name":$0.0, "description":$0.1, "parameters":$0.2] as [String: Any] }
        return try JSONSerialization.data(withJSONObject: ["type":"namespace", "name":namespace, "description":"Private local food diary operations", "tools":tools])
    }
    static func parse(_ call: CoachToolCall, meals: [CoachContext.Meal], evidence: [Int: FoodEvidenceRecord], receipts: [CoachReceipt]) throws -> CoachCommand {
        guard call.namespace == namespace, call.arguments.utf8.count <= 65_536,
              let data = call.arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CoachError.invalidTool }
        func keys(_ allowed: Set<String>, _ required: Set<String>) throws {
            guard Set(args.keys).isSubset(of: allowed), required.isSubset(of: Set(args.keys)) else { throw CoachError.invalidArguments }
        }
        func string(_ name: String) throws -> String {
            guard let value = args[name] as? String, !value.isEmpty, value.utf8.count <= 500 else { throw CoachError.invalidArguments }; return value
        }
        func uuid(_ name: String) throws -> UUID { guard let id = UUID(uuidString: try string(name)) else { throw CoachError.invalidArguments }; return id }
        switch call.name {
        case "get_context": try keys([], []); return .context
        case "get_meal": try keys(["meal_id"], ["meal_id"]); return .meal(try uuid("meal_id"))
        case "lookup_nutrition":
            try keys(["query"], ["query"]); let query = try string("query")
            guard query.utf8.count <= 200 else { throw CoachError.invalidArguments }; return .lookup(query)
        case "log_food":
            try keys(["target_local_date", "items", "eaten_at"], ["target_local_date", "items"])
            guard let rows = args["items"] as? [[String: Any]], !rows.isEmpty, rows.count <= 200 else { throw CoachError.invalidArguments }
            let items = try rows.map { row -> FoodItem in
                guard Set(row.keys).isSubset(of: ["name","quantity","unit","kcal","carbs","protein","fat","evidence_id"]),
                      let name = row["name"] as? String, let quantity = number(row["quantity"]),
                      let unit = row["unit"] as? String else { throw CoachError.invalidArguments }
                func nutrient(_ key: String) throws -> Double? {
                    guard let value = row[key], !(value is NSNull) else { return nil }
                    guard let result = number(value) else { throw CoachError.invalidArguments }; return result
                }
                var item = FoodItem(name: name, quantity: quantity, unit: unit,
                    nutrition: try NutritionValues(kcal: nutrient("kcal"), carbs: nutrient("carbs"), protein: nutrient("protein"), fat: nutrient("fat")),
                    provenance: .estimate, reference: "Unverified portion estimate", uncertain: true)
                if let idValue = row["evidence_id"], !(idValue is NSNull) {
                    guard let value = number(idValue), value > 0, value.rounded() == value, value < Double(Int.max),
                          let record = evidence[Int(value)], ["g", "gram", "grams"].contains(unit.lowercased()) else { throw CoachError.invalidArguments }
                    item.name = record.name
                    item.nutritionBasis = record.per100Grams.scaled(by: 0.01)
                    item.nutrition = record.per100Grams.scaled(by: quantity / 100)
                    item.provenance = .identifiedSource; item.reference = record.reference
                    // A known food source does not verify its identification or portion.
                    item.uncertain = true
                }
                try validateItems([item]); return item
            }
            // Validate legacy syntax without treating model output as owner-confirmed time.
            if let value = args["eaten_at"] {
                guard let value = value as? String, ISO8601DateFormatter().date(from: value) != nil else { throw CoachError.invalidArguments }
            }
            return .write(.food(date: try string("target_local_date"), items: items, eatenAt: nil))
        case "correct_item":
            try keys(["meal_id", "item_id", "expected_revision", "quantity"], ["meal_id", "item_id", "expected_revision", "quantity"])
            let mealID = try uuid("meal_id"), itemID = try uuid("item_id")
            guard let revision = number(args["expected_revision"]), revision >= 0, revision < 1_000_000, revision.rounded() == revision,
                  let meal = meals.first(where: { $0.id == mealID }),
                  (meal.revision == Int(revision) || receipts.contains(where: { $0.mealID == mealID && $0.itemID == itemID })) ,
                  var item = meal.items.first(where: { $0.id == itemID }), let quantity = number(args["quantity"]) else { throw CoachError.invalidArguments }
            item.quantity = quantity; try validateItems([item])
            return .write(.correction(mealID: mealID, item: item, revision: Int(revision)))
        case "close_day":
            try keys(["local_date","completeness"], ["local_date","completeness"])
            guard let completeness = DayCompleteness(rawValue: try string("completeness")) else { throw CoachError.invalidArguments }
            return .write(.close(date: try string("local_date"), completeness: completeness))
        default: throw CoachError.invalidTool
        }
    }
    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
}
