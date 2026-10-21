import Foundation
import CoreFoundation
import CryptoKit

struct CoachNutrientEdit: Sendable {
    var nutrient: String
    var value: Double?
}

enum CoachManualEdit: Sendable {
    case item(mealID: UUID, item: FoodItem, revision: Int, submissionID: UUID?, explicitNutrients: Set<String>, original: FoodItem)
    case append(mealID: UUID, items: [FoodItem], revision: Int)
    case accept(mealID: UUID, submissionID: UUID, revision: Int)
    case move(mealID: UUID, date: String, revision: Int, originalDayID: UUID)
    case deleteMeal(mealID: UUID, revision: Int)
    case deleteItem(mealID: UUID, itemID: UUID, revision: Int)
    case scaleMeal(mealID: UUID, targetKcal: Double, revision: Int)
    case attach(mealID: UUID, photoIDs: [UUID], role: PhotoRole, revision: Int)
    case deletePhoto(mealID: UUID, photoID: UUID, revision: Int)
    case retry(mealID: UUID, revision: Int)
    case goals(date: String, targets: [CoachNutrientEdit], weight: Double?, clearWeight: Bool, exerciseCredit: Bool?, revision: Int?)
    case preferences(timezone: String?, text: String?, revision: Int)
    case startDay(revision: Int)
    case coverage(date: String, completeness: DayCompleteness)
    case open(CoachDestination)

    var mealID: UUID? {
        switch self {
        case .item(let id, _, _, _, _, _), .append(let id, _, _), .accept(let id, _, _), .move(let id, _, _, _),
             .deleteMeal(let id, _), .deleteItem(let id, _, _), .scaleMeal(let id, _, _), .attach(let id, _, _, _), .deletePhoto(let id, _, _), .retry(let id, _): id
        default: nil
        }
    }
    var target: String {
        switch self {
        case .item(let id, let item, _, let submission, _, _): "edit_item/\(id)/\(submission?.uuidString ?? "saved")/\(item.id)"
        case .append(let id, _, _): "append_food/\(id)"
        case .accept(let id, let submission, _): "accept_review/\(id)/\(submission)"
        case .move(let id, _, _, _): "move_meal/\(id)"
        case .deleteMeal(let id, _): "delete_meal/\(id)"
        case .deleteItem(let id, let item, _): "delete_item/\(id)/\(item)"
        case .scaleMeal(let id, _, _): "scale_meal/\(id)"
        case .attach(let id, _, _, _): "attach_photos/\(id)"
        case .deletePhoto(let id, let photo, _): "delete_photo/\(id)/\(photo)"
        case .retry(let id, _): "retry_meal/\(id)"
        case .goals(let date, _, _, _, _, _): "set_goals/\(date)"
        case .preferences: "update_preferences"
        case .startDay: "start_day"
        case .coverage(let date, _): "set_day_coverage/\(date)"
        case .open(let destination): "open_settings/\(destination.rawValue)"
        }
    }
}

extension CoachTools {
    static func manualSchemas(food: [String: Any]) -> [(String, String, [String: Any])] {
        let string: [String: Any] = ["type": "string"], integer: [String: Any] = ["type": "integer"]
        let number: [String: Any] = ["type": "number"], boolean: [String: Any] = ["type": "boolean"]
        let nutrients: [String: Any] = ["type": "array", "items": object([
            "nutrient": ["type": "string", "enum": ["kcal", "carbs", "protein", "fat"]],
            "value": ["type": ["number", "null"]]], required: ["nutrient", "value"])]
        let meal: [String: Any] = ["meal_id": string, "expected_revision": integer]
        func mealObject(_ extra: [String: Any], required: [String]) -> [String: Any] {
            object(meal.merging(extra) { _, new in new }, required: ["meal_id", "expected_revision"] + required)
        }
        return [
            ("edit_item", "Patch only named fields on a retrieved saved or review item. Null name/quantity/unit means unchanged. nutrients lists only changed nutrient totals; a null value clears that nutrient. Preserve other items. Use review_submission_id for an unaccepted proposal; this does not accept it.", mealObject(["item_id": string, "review_submission_id": string, "name": string, "quantity": number, "unit": string, "nutrients": nutrients], required: ["item_id"])),
            ("append_food", "Append only new foods to an explicitly retrieved existing saved meal; never repeat its current foods. Group all additions to this meal into one call per turn; retries replay that first addition. Returns the committed meal. Use log_food for a new meal.", mealObject(["items": ["type": "array", "items": food]], required: ["items"])),
            ("accept_review", "Save an explicitly accepted retrieved meal proposal into totals. Use its submission ID and current meal revision. Never accept an estimate just because the user requests an edit.", mealObject(["submission_id": string], required: ["submission_id"])),
            ("move_meal", "Move an existing retrieved meal's tracking date to target_local_date (yyyy-MM-dd), preserving active waking day and its original capture/eating time and precision. A 04:00 meal can belong to the previous waking day.", mealObject(["target_local_date": string], required: ["target_local_date"])),
            ("delete_meal", "Delete an explicitly requested retrieved meal and its photos. Use its real ID/revision; never delete to compensate for eating.", mealObject([:], required: [])),
            ("delete_item", "Delete one explicitly requested food from a retrieved saved meal using its real item ID and meal revision. If it is the meal's only food, do not call this; for the only food use ask_clarification kind confirm with that meal.", mealObject(["item_id": string], required: ["item_id"])),
            ("scale_meal", "Change the whole saved meal's portions proportionally so its known calories total target_kcal (ratio 0.1 to 3 of the current total). Use for requests like \"make this meal 650 kcal\" or \"I only ate about two thirds\"; use edit_item for one food. Needs a retrieved saved meal and its revision; refused for unaccepted estimates or meals with 0 known kcal.", mealObject(["target_kcal": number], required: ["target_kcal"])),
            ("attach_photos", "Attach current turn's actual attachedPhotoIDs to a retrieved meal, preserving the original photo bytes. Choose before/after only when supplied. Does not change food totals; pair with explicit food edits when needed.", mealObject(["photo_ids": ["type": "array", "items": string], "role": ["type": "string", "enum": PhotoRole.allCases.map(\.rawValue)]], required: ["photo_ids", "role"])),
            ("delete_photo", "Delete an explicitly requested photo using a retrieved meal's photo ID and revision. Removes retained copies, without deleting the food.", mealObject(["photo_id": string], required: ["photo_id"])),
            ("retry_meal", "Requeue an existing paused meal capture without creating a new meal or food record. Uses original saved input. Only the later successful analysis can confirm food saved.", mealObject([:], required: [])),
            ("get_goals", "Read exact dated goal settings and the goal effective on local_date (yyyy-MM-dd), plus diary revision. Exact goal null means use null expected_revision to create a setting for that date.", object(["local_date": string], required: ["local_date"])),
            ("get_preferences", "Read complete saved dietary preferences and timezone plus diary revision before editing. Context preferences may be truncated; do not replace omitted text.", object([:], required: [])),
            ("set_goals", "Apply only explicit user-requested target changes, never an inferred prescription. First get_goals for this effective_local_date. targets is a patch: omitted nutrients remain; null value unsets a target. Null goal_weight_kg keeps it; clear_goal_weight true unsets it. Unspecified exercise credit remains unchanged. Existing exact date requires expected_revision; new date uses null. Returns saved settings; creates no intake day.", object(["effective_local_date": string, "expected_revision": integer, "targets": nutrients, "goal_weight_kg": number, "clear_goal_weight": boolean, "exercise_credit_enabled": boolean], required: ["effective_local_date", "targets"])),
            ("update_preferences", "Update explicitly requested preferences/timezone after reading complete get_preferences. Null fields preserve saved values; empty preferences clears them. expected_diary_revision protects unseen concurrent changes. Does not change historical day labels, credentials, or language.", object(["expected_diary_revision": integer, "timezone": string, "preferences": string], required: ["expected_diary_revision"])),
            ("start_day", "Explicitly start the current waking day from the persisted capture clock. Read fresh context for expected_diary_revision. Delayed captures cannot reverse a newer waking-day choice.", object(["expected_diary_revision": integer], required: ["expected_diary_revision"])),
            ("set_day_coverage", "Set the requested local date's coverage without closing it or activating it. Missing intake remains unknown. Use close_day only when the user explicitly closes a day.", object(["local_date": string, "completeness": ["type": "string", "enum": DayCompleteness.allCases.map(\.rawValue)]], required: ["local_date", "completeness"])),
            ("open_settings", "Offer a native Settings link for accounts, local profiles, secrets or Files backup. The user must tap and complete the native action; this tool never authorizes, deletes a profile, restores a backup or claims those actions succeeded.", object(["destination": ["type": "string", "enum": CoachDestination.allCases.map(\.rawValue)]], required: ["destination"]))
        ]
    }
    static func parseManual(_ call: CoachToolCall, args: [String: Any], meals: [CoachContext.Meal], evidence: [Int: FoodEvidenceRecord], receipts: [CoachReceipt]) throws -> CoachCommand {
        func keys(_ allowed: Set<String>, _ required: Set<String>) throws {
            guard Set(args.keys).isSubset(of: allowed), required.isSubset(of: Set(args.keys)) else { throw CoachError.invalidArguments }
        }
        func string(_ key: String, maximum: Int = 500, allowEmpty: Bool = false) throws -> String {
            guard let text = args[key] as? String, text.count <= maximum, allowEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CoachError.invalidArguments }; return text
        }
        func id(_ key: String) throws -> UUID {
            guard let id = UUID(uuidString: try string(key)) else { throw CoachError.invalidArguments }; return id
        }
        func optional(_ key: String) -> Bool { args[key] != nil && !(args[key] is NSNull) }
        func revision(_ key: String = "expected_revision", allowZero: Bool = false) throws -> Int {
            guard let value = number(args[key]), value.rounded() == value, value >= (allowZero ? 0 : 1), value < 10_000_000 else { throw CoachError.invalidArguments }; return Int(value)
        }
        func date(_ key: String) throws -> String {
            let value = try string(key); guard validLocalDate(value) else { throw CoachError.invalidArguments }; return value
        }
        func bool(_ key: String) throws -> Bool? {
            guard optional(key) else { return nil }
            guard let value = args[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { throw CoachError.invalidArguments }
            return value.boolValue
        }
        func edits(_ key: String) throws -> [CoachNutrientEdit] {
            guard optional(key) else { return [] }
            guard let rows = args[key] as? [[String: Any]], rows.count <= 4 else { throw CoachError.invalidArguments }
            var names = Set<String>()
            return try rows.map { row in
                guard Set(row.keys) == ["nutrient", "value"], let name = row["nutrient"] as? String,
                      ["kcal", "carbs", "protein", "fat"].contains(name), names.insert(name).inserted else { throw CoachError.invalidArguments }
                if row["value"] is NSNull { return CoachNutrientEdit(nutrient: name, value: nil) }
                guard let value = number(row["value"]), (0...10_000_000).contains(value) else { throw CoachError.invalidArguments }
                return CoachNutrientEdit(nutrient: name, value: value)
            }
        }
        let mealFields: Set<String> = ["meal_id", "expected_revision"]
        let write: CoachManualEdit
        switch call.name {
        case "get_goals": try keys(["local_date"], ["local_date"]); return .goals(try date("local_date"))
        case "get_preferences": try keys([], []); return .preferences
        case "edit_item":
            try keys(mealFields.union(["item_id", "review_submission_id", "name", "quantity", "unit", "nutrients"]), mealFields.union(["item_id"]))
            let mealID = try id("meal_id"), itemID = try id("item_id"), expected = try revision(allowZero: true)
            let submission = optional("review_submission_id") ? try id("review_submission_id") : nil
            guard let meal = meals.first(where: { $0.id == mealID }) else { throw CoachError.invalidArguments }
            let source: [FoodItem]
            if let submission {
                guard let review = meal.review, review.submissionID == submission else { throw CoachError.invalidArguments }
                source = review.items
            } else { source = meal.items }
            guard var item = source.first(where: { $0.id == itemID }) else { throw CoachError.invalidArguments }
            let original = item
            if optional("name") { item.name = try string("name") }
            if optional("unit") { item.unit = try string("unit", maximum: 100) }
            if optional("quantity") { guard let value = number(args["quantity"]) else { throw CoachError.invalidArguments }; item.quantity = value }
            let nutrients = try edits("nutrients")
            guard ["name", "unit", "quantity"].contains(where: optional) || !nutrients.isEmpty else { throw CoachError.invalidArguments }
            for edit in nutrients { item.nutrition.set(edit) }
            try validateItems([item])
            write = .item(mealID: mealID, item: item, revision: expected, submissionID: submission, explicitNutrients: Set(nutrients.map(\.nutrient)), original: original)
        case "append_food":
            try keys(mealFields.union(["items"]), mealFields.union(["items"]))
            write = .append(mealID: try id("meal_id"), items: try foodItems(args["items"], evidence: evidence), revision: try revision(allowZero: true))
        case "accept_review":
            try keys(mealFields.union(["submission_id"]), mealFields.union(["submission_id"]))
            write = .accept(mealID: try id("meal_id"), submissionID: try id("submission_id"), revision: try revision(allowZero: true))
        case "move_meal":
            try keys(mealFields.union(["target_local_date"]), mealFields.union(["target_local_date"]))
            let mealID = try id("meal_id")
            guard let meal = meals.first(where: { $0.id == mealID }) else { throw CoachError.invalidArguments }
            write = .move(mealID: mealID, date: try date("target_local_date"), revision: try revision(allowZero: true), originalDayID: meal.dayID)
        case "delete_meal":
            try keys(mealFields, mealFields); write = .deleteMeal(mealID: try id("meal_id"), revision: try revision(allowZero: true))
        case "delete_item":
            try keys(mealFields.union(["item_id"]), mealFields.union(["item_id"]))
            let mealID = try id("meal_id"), itemID = try id("item_id")
            // A committed delete replays even though the food is already gone from context.
            let replay = receipts.contains { $0.operationKey.hasSuffix("/delete_item/\(mealID)/\(itemID)") }
            guard replay || meals.first(where: { $0.id == mealID }).map({ meal in meal.items.contains { $0.id == itemID } && meal.items.count > 1 }) == true else { throw CoachError.invalidArguments }
            write = .deleteItem(mealID: mealID, itemID: itemID, revision: try revision(allowZero: true))
        case "scale_meal":
            try keys(mealFields.union(["target_kcal"]), mealFields.union(["target_kcal"]))
            let mealID = try id("meal_id")
            guard meals.contains(where: { $0.id == mealID }), let target = number(args["target_kcal"]), target > 0, target <= 10_000_000 else { throw CoachError.invalidArguments }
            write = .scaleMeal(mealID: mealID, targetKcal: target, revision: try revision(allowZero: true))
        case "retry_meal":
            try keys(mealFields, mealFields); write = .retry(mealID: try id("meal_id"), revision: try revision(allowZero: true))
        case "attach_photos":
            try keys(mealFields.union(["photo_ids", "role"]), mealFields.union(["photo_ids", "role"]))
            guard let values = args["photo_ids"] as? [String], !values.isEmpty, values.count <= 30,
                  let role = PhotoRole(rawValue: try string("role")) else { throw CoachError.invalidArguments }
            let ids = try values.map { value in guard let id = UUID(uuidString: value) else { throw CoachError.invalidArguments }; return id }
            guard Set(ids).count == ids.count else { throw CoachError.invalidArguments }
            write = .attach(mealID: try id("meal_id"), photoIDs: ids, role: role, revision: try revision(allowZero: true))
        case "delete_photo":
            try keys(mealFields.union(["photo_id"]), mealFields.union(["photo_id"]))
            write = .deletePhoto(mealID: try id("meal_id"), photoID: try id("photo_id"), revision: try revision(allowZero: true))
        case "set_goals":
            try keys(["effective_local_date", "expected_revision", "targets", "goal_weight_kg", "clear_goal_weight", "exercise_credit_enabled"], ["effective_local_date", "targets"])
            let targets = try edits("targets"), clear = try bool("clear_goal_weight") ?? false
            var weight: Double?
            if optional("goal_weight_kg") { guard let value = number(args["goal_weight_kg"]), value > 0, value <= 10_000_000, !clear else { throw CoachError.invalidArguments }; weight = value }
            let credit = try bool("exercise_credit_enabled")
            guard !targets.isEmpty || weight != nil || clear || credit != nil else { throw CoachError.invalidArguments }
            write = .goals(date: try date("effective_local_date"), targets: targets, weight: weight, clearWeight: clear, exerciseCredit: credit, revision: optional("expected_revision") ? try revision() : nil)
        case "update_preferences":
            try keys(["expected_diary_revision", "timezone", "preferences"], ["expected_diary_revision"])
            let timezone = optional("timezone") ? try string("timezone") : nil
            if let timezone { guard TimeZone(identifier: timezone) != nil else { throw CoachError.invalidArguments } }
            let text = optional("preferences") ? try string("preferences", maximum: 10_000, allowEmpty: true) : nil
            guard timezone != nil || text != nil else { throw CoachError.invalidArguments }
            write = .preferences(timezone: timezone, text: text, revision: try revision("expected_diary_revision", allowZero: true))
        case "start_day":
            try keys(["expected_diary_revision"], ["expected_diary_revision"]); write = .startDay(revision: try revision("expected_diary_revision", allowZero: true))
        case "set_day_coverage":
            try keys(["local_date", "completeness"], ["local_date", "completeness"])
            guard let completeness = DayCompleteness(rawValue: try string("completeness")) else { throw CoachError.invalidArguments }
            write = .coverage(date: try date("local_date"), completeness: completeness)
        case "open_settings":
            try keys(["destination"], ["destination"])
            guard let destination = CoachDestination(rawValue: try string("destination")) else { throw CoachError.invalidArguments }; write = .open(destination)
        default: throw CoachError.invalidTool
        }
        let distinctPatches: Set<String> = ["edit_item", "set_goals", "update_preferences", "move_meal", "set_day_coverage", "attach_photos"]
        var patchKey: String?
        if distinctPatches.contains(call.name) {
            var patch = args.filter { !$0.key.hasPrefix("expected_") && !($0.value is NSNull) }
            for key in ["nutrients", "targets"] {
                if let rows = patch[key] as? [[String: Any]] {
                    patch[key] = rows.isEmpty ? nil : rows.sorted { ($0["nutrient"] as? String ?? "") < ($1["nutrient"] as? String ?? "") }
                }
            }
            if let ids = patch["photo_ids"] as? [String] { patch["photo_ids"] = ids.sorted() }
            if patch["clear_goal_weight"] as? Bool == false { patch.removeValue(forKey: "clear_goal_weight") }
            let data = try JSONSerialization.data(withJSONObject: patch, options: .sortedKeys)
            patchKey = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return .write(.manual(write, patchKey: patchKey))
    }
}

extension NutritionValues {
    mutating func set(_ edit: CoachNutrientEdit) {
        switch edit.nutrient {
        case "kcal": kcal = edit.value
        case "carbs": carbs = edit.value
        case "protein": protein = edit.value
        case "fat": fat = edit.value
        default: break
        }
    }
}
