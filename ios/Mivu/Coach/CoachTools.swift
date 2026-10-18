import Foundation
import CoreFoundation

enum CoachWriteMode: Equatable, Sendable { case uninterrupted, replayOnly }

enum CoachWrite: Sendable {
    case manual(CoachManualEdit, patchKey: String? = nil)
    case food(date: String, items: [FoodItem], eatenAt: Date?, reviewFirst: Bool = false)
    case correction(mealID: UUID, item: FoodItem, revision: Int)
    case close(date: String, completeness: DayCompleteness)
    case weight(date: String, value: Double, unit: String, revision: Int?)
    case correctWeight(id: UUID, value: Double, unit: String, revision: Int)
    case workout(date: String, draft: WorkoutDraft)
    case editWorkout(id: UUID, draft: WorkoutDraft, revision: Int)
    case deleteWeight(id: UUID, revision: Int)
    case deleteWorkout(id: UUID, revision: Int)
    var target: String {
        switch self {
        case .manual(let edit, let patchKey): edit.target + (patchKey.map { "/" + $0 } ?? "")
        case .food(let date, _, _, _): "food/\(date)"
        case .correction(let meal, let item, _): "correct/\(meal.uuidString)/\(item.id.uuidString)"
        case .close(let date, _): "close/\(date)"
        case .weight(let date, _, _, _): "weight/\(date)"
        case .correctWeight(let id, _, _, _): "correct_weight/\(id.uuidString)"
        case .workout(let date, _): "workout/\(date)"
        case .editWorkout(let id, _, _): "edit_workout/\(id.uuidString)"
        case .deleteWeight(let id, _): "delete_weight/\(id.uuidString)"
        case .deleteWorkout(let id, _): "delete_workout/\(id.uuidString)"
        }
    }
}

enum CoachClarification: String, CaseIterable, Sendable {
    case portion, food, day, meal, workout
    var question: String {
        switch self {
        case .portion: "How much did you eat? Give grams, a serving size, or a container size."
        case .food: "What food did you eat?"
        case .day: "Which day should this be recorded on?"
        case .meal: "Which meal do you mean?"
        case .workout: "Which workout do you mean?"
        }
    }
}

enum CoachCommand: Sendable {
    case clarification(CoachClarification)
    case goals(String)
    case preferences
    case context
    case meal(UUID)
    case lookup(String)
    case progress(endingOn: String, days: Int)
    case workout(UUID)
    case write(CoachWrite)
}

/// Only declared operations cross the model-to-diary boundary.
enum CoachTools {
    static let namespace = "mivu"
    static func object(_ properties: [String: Any], required: [String]) -> [String: Any] {
            var normalized = properties
            for (key, value) in properties where !required.contains(key) {
                guard var field = value as? [String: Any] else { continue }
                let types = (field["type"] as? [String]) ?? (field["type"] as? String).map { [$0] } ?? []
                field["type"] = types.contains("null") ? types : types + ["null"]
                normalized[key] = field
            }
            return ["type": "object", "properties": normalized, "required": properties.keys.sorted(), "additionalProperties": false]
    }
    static func declarations() throws -> Data {
        let string: [String: Any] = ["type": "string"]
        let number: [String: Any] = ["type": ["number", "null"]]
        let food = object(["name": string, "quantity": ["type":"number"], "unit": string,
            "kcal": number, "carbs": number, "protein": number, "fat": number,
            "evidence_id": ["type":["integer", "null"]]], required: ["name", "quantity", "unit", "kcal", "carbs", "protein", "fat"])
        let integer: [String: Any] = ["type": "integer"]
        let unconfirmedTime: [String: Any] = ["type": "string", "description": "Use null when no time was supplied. A valid local date or ISO 8601 string is accepted for compatibility but ignored; it cannot change the requested tracking day or establish an exact time."]
        let exercise = object(["name": string, "sets": ["type": "array", "items": object(["repetitions": integer, "load_kg": number], required: ["repetitions", "load_kg"])]], required: ["name", "sets"])
        let workout: [String: Any] = ["kind": ["type": "string", "enum": ["strength", "cardio", "other"]], "duration_minutes": integer, "exercises": ["type": "array", "items": exercise], "estimated_burn_kcal": number, "burn_source": ["type": ["string", "null"], "enum": ["userEstimate", "modelEstimate", NSNull()]], "performed_at": unconfirmedTime]
        let schemas: [(String, String, [String: Any])] = [
            ("ask_clarification", "Ask before logging only when food, serving, day or an existing record is genuinely ambiguous. Unknown exact grams or milliliters alone do not block a clearly labelled estimate from text, photos or a clear matching committed portion. Choose portion for an ambiguous serving, food for food identity, day for the recording date, meal or workout for an ambiguous existing record. Use this tool alone, before any writes in this turn. The app displays its own question; the user answers in a new turn.", object(["kind": ["type": "string", "enum": CoachClarification.allCases.map(\.rawValue)]], required: ["kind"])),
            ("get_progress", "Read actual progress for an inclusive 1, 7 or 30 calendar-day window. Real record IDs/revisions and omitted counts support historical corrections. Food remaining and estimated burn are separate; adherence means Within 10% of target.", object(["ending_on": string, "days": ["type": "integer", "enum": [1, 7, 30]]], required: ["ending_on", "days"])),
            ("get_workout", "Read a complete owned workout before replacement/edit. Oversized records are refused; never replace unseen sets.", object(["workout_id": string], required: ["workout_id"])),
            ("log_weight", "Log one weight per date. Corrections require expected_revision; historical correction after travel must use retrieved weight_id, preserving day and measured time. Model measured_at cannot confirm exact time. Current morning weight explicitly starts that waking day.", object(["local_date": string, "value": ["type": "number"], "unit": ["type": "string", "enum": ["kg", "lb"]], "weight_id": string, "expected_revision": integer, "measured_at": unconfirmedTime], required: ["local_date", "value", "unit"])),
            ("log_workout", "Log one new session per turn/date; another session needs another turn. Timestamps are unconfirmed date-only. Estimated burn stays separate from food.", object(workout.merging(["local_date": string]) { _, new in new }, required: ["local_date", "kind", "duration_minutes", "exercises"])),
            ("edit_workout", "Replace a complete retrieved workout using its real ID/revision. Preserve its day/time; include all existing sets that should remain.", object(workout.merging(["workout_id": string, "expected_revision": integer]) { _, new in new }, required: ["workout_id", "expected_revision", "kind", "duration_minutes", "exercises"])),
            ("delete_workout", "Delete an owned workout with its actual revision.", object(["workout_id": string, "expected_revision": integer], required: ["workout_id", "expected_revision"])),
            ("delete_weight", "Delete an owned weight with its actual revision.", object(["weight_id": string, "expected_revision": integer], required: ["weight_id", "expected_revision"])),
            ("get_context", "Read actual bounded diary and capture clock. truncated and omittedMeals explicitly mark details not included.", object([:], required: [])),
            ("get_meal", "Retrieve actual owner-scoped meal by UUID before correction. omittedItemCount marks unavailable details requiring manual review.", object(["meal_id": string], required: ["meal_id"])),
            ("lookup_nutrition", "Search retrieved nutrition evidence; unavailable means use clearly uncertain estimates.", object(["query":string], required: ["query"])),
            ("log_food", "Log all new foods for this turn/date once, keeping new intake distinct from earlier reviews. For a clear repeat, reuse the most recent matching committed quantity/unit as an uncertain estimate, never an unaccepted proposal. Explicit current amounts or labels and visible changed food or serving override history; a same-food photo without a measurable amount keeps a clear matching committed portion. Interpret photos with their description. For photo-only intake, estimate the visible serving first, then a labelled typical serving when identified but unmeasurable, without claiming unseen mixture ratios are verified. On a saved manual meal append only newly named foods, preserving every existing item; correct existing foods with correct_item. Nutrition numbers are portion totals; only retrieved evidence_id with grams replaces estimates. Direct chat remains date-only; exact time requires a manual UI capture. Set review_first true when the user wants a proposal before totals. Optional eaten_at is accepted for compatibility but cannot establish a confirmed time.", object(["target_local_date":string, "items":["type":"array", "items":food], "eaten_at":unconfirmedTime, "review_first":["type":"boolean"]], required: ["target_local_date", "items"])),
            ("correct_item", "Correct only quantity on a retrieved actual item, preserving its nutrition basis and sources.", object(["meal_id":string,"item_id":string,"expected_revision":["type":"integer"],"quantity":["type":"number"]], required: ["meal_id","item_id","expected_revision","quantity"])),
            ("close_day", "Explicitly close a local date as complete, partial, untracked or unknown; retain existing food.", object(["local_date":string,"completeness":["type":"string","enum":DayCompleteness.allCases.map(\.rawValue)]], required: ["local_date","completeness"]))
        ] + manualSchemas(food: food)
        let tools = schemas.map { ["type":"function", "name":$0.0, "description":$0.1, "parameters":$0.2, "strict":true] as [String: Any] }
        return try JSONSerialization.data(withJSONObject: ["type":"namespace", "name":namespace, "description":"Private local diary and progress operations", "tools":tools])
    }
    static func parse(_ call: CoachToolCall, meals: [CoachContext.Meal], evidence: [Int: FoodEvidenceRecord], receipts: [CoachReceipt], workouts: [WorkoutSession] = []) throws -> CoachCommand {
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
        func date(_ name: String) throws -> String {
            let value = try string(name); guard validLocalDate(value) else { throw CoachError.invalidArguments }; return value
        }
        func integer(_ name: String, _ range: ClosedRange<Int>) throws -> Int {
            guard let value = number(args[name]), value.rounded() == value, value >= Double(range.lowerBound), value <= Double(range.upperBound) else { throw CoachError.invalidArguments }; return Int(value)
        }
        func revision() throws -> Int { try integer("expected_revision", 1...999_999) }
        func unconfirmedTime(_ name: String) throws {
            guard let raw = args[name], !(raw is NSNull) else { return }
            guard let value = raw as? String else { throw CoachError.invalidArguments }
            let formatter = ISO8601DateFormatter()
            if validLocalDate(value) || formatter.date(from: value) != nil { return }
            formatter.formatOptions.insert(.withFractionalSeconds)
            guard formatter.date(from: value) != nil else { throw CoachError.invalidArguments }
        }
        func draft() throws -> WorkoutDraft {
            guard let kind = WorkoutKind(rawValue: try string("kind")), let rows = args["exercises"] as? [[String: Any]], rows.count <= 100 else { throw CoachError.invalidArguments }
            let exercises = try rows.map { row -> WorkoutExercise in
                guard Set(row.keys) == ["name", "sets"], let name = row["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200,
                      let sets = row["sets"] as? [[String: Any]], sets.count <= 100 else { throw CoachError.invalidArguments }
                return WorkoutExercise(name: name, sets: try sets.map { set in
                    guard Set(set.keys).isSubset(of: ["repetitions", "load_kg"]), let reps = number(set["repetitions"]), reps.rounded() == reps, (1...10_000).contains(reps) else { throw CoachError.invalidArguments }
                    var load: Double?
                    if let raw = set["load_kg"], !(raw is NSNull) { guard let value = number(raw), (0...100_000).contains(value) else { throw CoachError.invalidArguments }; load = value }
                    return WorkoutSet(repetitions: Int(reps), loadKg: load)
                })
            }
            var burn: Double?, source: WorkoutBurnSource?
            if let raw = args["estimated_burn_kcal"], !(raw is NSNull) { guard let value = number(raw), (0...100_000).contains(value) else { throw CoachError.invalidArguments }; burn = value }
            if let raw = args["burn_source"], !(raw is NSNull) { guard let value = raw as? String, let parsed = WorkoutBurnSource(rawValue: value), burn != nil else { throw CoachError.invalidArguments }; source = parsed }
            try unconfirmedTime("performed_at")
            return WorkoutDraft(kind: kind, durationMinutes: try integer("duration_minutes", 1...1440), exercises: exercises, estimatedBurnKcal: burn, burnSource: source)
        }
        switch call.name {
        case "ask_clarification":
            try keys(["kind"], ["kind"])
            guard let kind = CoachClarification(rawValue: try string("kind")) else { throw CoachError.invalidArguments }
            return .clarification(kind)
        case "get_progress":
            try keys(["ending_on", "days"], ["ending_on", "days"])
            let days = try integer("days", 1...30); guard [1, 7, 30].contains(days) else { throw CoachError.invalidArguments }
            return .progress(endingOn: try date("ending_on"), days: days)
        case "get_workout": try keys(["workout_id"], ["workout_id"]); return .workout(try uuid("workout_id"))
        case "log_weight":
            try keys(["local_date", "value", "unit", "weight_id", "expected_revision", "measured_at"], ["local_date", "value", "unit"])
            let label = try date("local_date"), unit = try string("unit")
            guard let value = number(args["value"]), value > 0, value <= 1500, ["kg", "lb"].contains(unit) else { throw CoachError.invalidArguments }
            try unconfirmedTime("measured_at")
            if let id = args["weight_id"], !(id is NSNull) { return .write(.correctWeight(id: try uuid("weight_id"), value: value, unit: unit, revision: try revision())) }
            let expectedRevision = args["expected_revision"]
            return .write(.weight(date: label, value: value, unit: unit, revision: expectedRevision == nil || expectedRevision is NSNull ? nil : try revision()))
        case "log_workout", "edit_workout":
            let fields: Set<String> = ["kind", "duration_minutes", "exercises", "estimated_burn_kcal", "burn_source", "performed_at"]
            if call.name == "log_workout" {
                try keys(fields.union(["local_date"]), ["local_date", "kind", "duration_minutes", "exercises"])
                return .write(.workout(date: try date("local_date"), draft: try draft()))
            }
            try keys(fields.union(["workout_id", "expected_revision"]), ["workout_id", "expected_revision", "kind", "duration_minutes", "exercises"])
            let id = try uuid("workout_id"), expectedRevision = try revision()
            guard workouts.contains(where: { $0.id == id && $0.revision == expectedRevision }) || receipts.contains(where: { $0.workoutID == id && $0.operationKey.hasSuffix("/edit_workout/" + id.uuidString) }) else { throw CoachError.invalidArguments }
            return .write(.editWorkout(id: id, draft: try draft(), revision: expectedRevision))
        case "delete_weight":
            try keys(["weight_id", "expected_revision"], ["weight_id", "expected_revision"])
            return .write(.deleteWeight(id: try uuid("weight_id"), revision: try revision()))
        case "delete_workout":
            try keys(["workout_id", "expected_revision"], ["workout_id", "expected_revision"])
            return .write(.deleteWorkout(id: try uuid("workout_id"), revision: try revision()))
        case "get_context": try keys([], []); return .context
        case "get_meal": try keys(["meal_id"], ["meal_id"]); return .meal(try uuid("meal_id"))
        case "lookup_nutrition":
            try keys(["query"], ["query"]); let query = try string("query")
            guard query.utf8.count <= 200 else { throw CoachError.invalidArguments }; return .lookup(query)
        case "log_food":
            try keys(["target_local_date", "items", "eaten_at", "review_first"], ["target_local_date", "items"])
            let items = try foodItems(args["items"], evidence: evidence)
            // Validate legacy syntax without treating model output as owner-confirmed time.
            try unconfirmedTime("eaten_at")
            var reviewFirst = false
            if let raw = args["review_first"], !(raw is NSNull) {
                guard let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { throw CoachError.invalidArguments }
                reviewFirst = value.boolValue
            }
            return .write(.food(date: try string("target_local_date"), items: items, eatenAt: nil, reviewFirst: reviewFirst))
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
        default: return try parseManual(call, args: args, meals: meals, evidence: evidence, receipts: receipts)
        }
    }

    static func foodItems(_ raw: Any?, evidence: [Int: FoodEvidenceRecord]) throws -> [FoodItem] {
            guard let rows = raw as? [[String: Any]], !rows.isEmpty, rows.count <= 200 else { throw CoachError.invalidArguments }
            return try rows.map { row -> FoodItem in
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
    }
    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
}
