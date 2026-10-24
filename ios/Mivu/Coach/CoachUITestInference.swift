import Foundation
#if DEBUG
import UIKit
#endif

// Explicit UI-test isolation is required by the caller; no provider request is made.
enum CoachUITestInference {
    static func respond(_ input: [CoachInferenceInput], _: Data) async throws -> CoachInferenceResult {
        if input.last(where: { if case .message(role: .user, _, _) = $0 { return true }; return false }).map({
            if case .message(_, let text, _) = $0 { return text == "Synthetic delayed weekly report" }
            return false
        }) == true {
            try await Task.sleep(for: .seconds(8))
        }
        guard let developer = input.compactMap({ entry -> String? in
            if case .message(role: .developer, let text, _) = entry { return text }; return nil
        }).last, let range = developer.range(of: "Context: "),
        let data = String(developer[range.upperBound...]).data(using: .utf8) else { throw CoachError.invalidArguments }
        let context = try JSONDecoder().decode(CoachContext.self, from: data)
        // History exchanges precede the tail developer message; only the current capture follows it.
        let tail = input.lastIndex { if case .message(role: .developer, _, _) = $0 { return true }; return false } ?? 0
        let text = input[tail...].compactMap { entry -> String? in
            if case .message(role: .user, let text, _) = entry { return text }; return nil
        }.joined(separator: " ").lowercased()
        if text.contains("edit yesterday’s lunch"), text.contains("one more chicken") {
            let result = try correction(input, context: context)
            #if DEBUG
            if CoachCorrectionUITestFixture.isEnabled {
                return try await CoachCorrectionUITestFixture.intercept(input: input, context: context, result: result)
            }
            #endif
            return result
        }
        let hasOutput = input.contains(where: { if case .functionOutput = $0 { return true }; return false })
        if text.contains("synthetic partial"), context.replyTo == nil, hasOutput {
            // Saved food followed by a failed round: the turn must still report what saved.
            let id = UUID().uuidString
            return CoachInferenceResult(model: "native-test-fixture", text: "", calls: [CoachToolCall(id: id, callID: id, name: "no_such_tool", namespace: "mivu", arguments: "{}")], outputItems: [])
        }
        if !hasOutput, let result = try clarification(input, context: context) { return result }
        if hasOutput || (text.contains("synthetic partial") && context.replyTo != nil) {
            // Progress questions get an invented number so UI tests see the app's fact-line fallback.
            let reply = text.contains("remaining budget") || text.contains("weekly report") ? "You have 9999 kcal left." : "All set."
            return CoachInferenceResult(model: "native-test-fixture", text: reply, calls: [], outputItems: [])
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: context.captureTimeZoneID) ?? .gmt
        let date = text.contains("yesterday") ? calendar.date(byAdding: .day, value: -1, to: context.capturedAt)! : context.capturedAt
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let localDate = formatter.string(from: date)
        let name: String, arguments: [String: Any]
        if text == "open backup settings" {
            name = "open_settings"; arguments = ["destination": "backup"]
        } else if text.contains("morning"), text.contains("70 kg") {
            name = "log_weight"; arguments = ["local_date": localDate, "value": 70, "unit": "kg"]
        } else if text.contains("30 minutes of strength") {
            name = "log_workout"
            arguments = ["local_date": localDate, "kind": "strength", "duration_minutes": 30,
                         "exercises": [["name": "Squat", "sets": [["repetitions": 8, "load_kg": 40]]]],
                         "estimated_burn_kcal": 200, "burn_source": "userEstimate"]
        } else if text.contains("remaining budget") || text.contains("weekly report") {
            name = "get_progress"; arguments = ["ending_on": localDate, "days": text.contains("weekly report") ? 7 : 1]
        } else if text.contains("half bread") {
            guard let meal = context.meals.last(where: { $0.items.contains(where: { $0.name == "Bread" }) }),
                  let bread = meal.items.first(where: { $0.name == "Bread" }) else { throw CoachError.invalidArguments }
            name = "correct_item"
            arguments = ["meal_id": meal.id.uuidString, "item_id": bread.id.uuidString,
                         "expected_revision": meal.revision, "quantity": bread.quantity / 2]
        } else {
            let items: [[String: Any]]
            var reviewFirst = false
            if text.contains("yesterday") {
                items = [["name":"Dessert", "quantity":1, "unit":"serving", "kcal":100, "carbs":15, "protein":2, "fat":4]]
            } else if text.contains("review") {
                reviewFirst = text.contains("fixture review")
                items = [["name":"Snack", "quantity":1, "unit":"serving", "kcal":80, "carbs":15, "protein":2, "fat":1]]
            } else {
                items = [["name":"Eggs", "quantity":2, "unit":"egg", "kcal":140, "carbs":1, "protein":12, "fat":10],
                         ["name":"Bread", "quantity":3, "unit":"slice", "kcal":240, "carbs":45, "protein":9, "fat":3],
                         ["name":"Salad", "quantity":1, "unit":"bowl", "kcal":40, "carbs":8, "protein":1, "fat":0]]
            }
            name = "log_food"; arguments = ["target_local_date": localDate, "items": items, "review_first": reviewFirst]
        }
        let argumentsJSON = String(data: try JSONSerialization.data(withJSONObject: arguments, options: .sortedKeys), encoding: .utf8)!
        let id = UUID().uuidString
        return CoachInferenceResult(model: "native-test-fixture", text: "", calls: [CoachToolCall(id: id, callID: id, name: name, namespace: "mivu", arguments: argumentsJSON)], outputItems: [])
    }
    /// Scenarios "clarify-candidates" / "clarify-confirm": ask on the first turn, resolve against pendingQuestion on the next.
    private static func clarification(_ input: [CoachInferenceInput], context: CoachContext) throws -> CoachInferenceResult? {
        let last = input.reversed().compactMap { entry -> String? in
            if case .message(role: .user, let text, _) = entry { return text.lowercased() }; return nil
        }.first ?? ""
        func call(_ name: String, _ args: [String: Any]) throws -> CoachInferenceResult {
            let id = UUID().uuidString
            let json = String(decoding: try JSONSerialization.data(withJSONObject: args, options: .sortedKeys), as: UTF8.self)
            return CoachInferenceResult(model: "native-test-fixture", text: "", calls: [CoachToolCall(id: id, callID: id, name: name, namespace: "mivu", arguments: json)], outputItems: [])
        }
        if let pending = context.focus?.pendingQuestion {
            let original = pending.originalText.lowercased()
            guard original.contains("clarify-candidates") || original.contains("clarify-confirm") else { return nil }
            guard let meal = context.replyTo?.meal else { throw CoachError.invalidArguments }
            if pending.kind == .confirm {
                if last.contains("keep") { return CoachInferenceResult(model: "native-test-fixture", text: "Kept it.", calls: [], outputItems: []) }
                return try call("delete_meal", ["meal_id": meal.id.uuidString, "expected_revision": meal.revision])
            }
            guard let item = meal.items.first else { throw CoachError.invalidArguments }
            return try call("correct_item", ["meal_id": meal.id.uuidString, "item_id": item.id.uuidString, "expected_revision": meal.revision, "quantity": item.quantity + 1])
        }
        if last.contains("clarify-candidates") {
            return try call("ask_clarification", ["kind": "meal", "candidates": context.meals.suffix(2).map { ["meal_id": $0.id.uuidString] }])
        }
        if last.contains("clarify-confirm"), let meal = context.meals.last {
            return try call("ask_clarification", ["kind": "confirm", "candidates": [["meal_id": meal.id.uuidString]]])
        }
        return nil
    }
    private static func correction(_ input: [CoachInferenceInput], context: CoachContext) throws -> CoachInferenceResult {
        func reply(_ name: String? = nil, _ args: [String: Any] = [:]) throws -> CoachInferenceResult {
            let id = UUID().uuidString
            let calls = try name.map { [CoachToolCall(id: id, callID: id, name: $0, namespace: "mivu",
                arguments: String(decoding: try JSONSerialization.data(withJSONObject: args, options: .sortedKeys), as: UTF8.self))] } ?? []
            return CoachInferenceResult(model: "native-test-fixture", text: "All set.", calls: calls, outputItems: [])
        }
        // A prior committed increment is a result, never a new serving calculation.
        if !(context.committedReceipts ?? []).isEmpty || (context.omittedReceiptCount ?? 0) > 0 { return try reply() }
        let outputs = input.compactMap { value -> String? in if case .functionOutput(_, let text) = value { return text }; return nil }
        if outputs.isEmpty {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: context.captureTimeZoneID)!
            let date = calendar.date(byAdding: .day, value: -1, to: context.capturedAt)!
            return try reply("get_meals_for_date", ["target_local_date": diaryDateLabel(date, zone: context.captureTimeZoneID)])
        }
        if outputs.count == 1 {
            let page = try JSONDecoder().decode(CoachMealCandidatePage.self, from: Data(outputs[0].utf8))
            let lunches = page.meals.filter { $0.capturedDescription.lowercased().contains("lunch") }
            guard !page.hasMore, !page.meals.contains(where: { $0.descriptionTruncated }), lunches.count == 1 else {
                return try reply("ask_clarification", ["kind": "meal"])
            }
            return try reply("get_meal", ["meal_id": lunches[0].id.uuidString])
        }
        if outputs.count == 2 {
            let meal = try JSONDecoder().decode(CoachContext.Meal.self, from: Data(outputs[1].utf8))
            let chicken = meal.items.filter { $0.name.lowercased() == "chicken" }
            guard meal.omittedItemCount == 0, chicken.count == 1 else { return try reply("ask_clarification", ["kind": "food"]) }
            guard chicken[0].unit == "piece", chicken[0].quantity > 0 else { return try reply("ask_clarification", ["kind": "portion"]) }
            return try reply("correct_item", ["meal_id": meal.id.uuidString, "item_id": chicken[0].id.uuidString,
                "expected_revision": meal.revision, "quantity": chicken[0].quantity + 1])
        }
        return try reply()
    }

}

#if DEBUG
extension CoachUITestInference {
    static let historyCaptureInstant = ISO8601DateFormatter().date(from: "2027-01-16T10:00:00Z")!
    static func historyID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }
    /// Called only for an absent isolated fixture profile. Reopen always uses its real database.
    @MainActor static func historySnapshot() throws -> DiarySnapshot {
        let instant = historyCaptureInstant
        let lunch = TrackingDay(id: historyID(901), localDate: "2027-01-15", timeZoneID: "UTC", startAt: instant.addingTimeInterval(-86_400))
        let repeated = TrackingDay(id: historyID(902), localDate: lunch.localDate, timeZoneID: "Pacific/Honolulu", startAt: lunch.startAt)
        let newer = TrackingDay(id: historyID(903), localDate: "2027-01-20", timeZoneID: "UTC", startAt: instant.addingTimeInterval(4 * 86_400))
        let empty = TrackingDay(id: historyID(904), localDate: "2027-01-21", timeZoneID: "UTC", startAt: instant.addingTimeInterval(5 * 86_400))
        let basis = NutritionValues(kcal: 100, carbs: nil, protein: 20, fat: 3)
        let items = [FoodItem(id: historyID(920), name: "Chicken", quantity: 2, unit: "piece", nutrition: basis.scaled(by: 2),
                            provenance: .estimate, reference: "Synthetic committed portion", uncertain: true,
                            nutrientSources: ["kcal": .estimate, "protein": .estimate], nutritionBasis: basis),
                     FoodItem(id: historyID(921), name: "Rice", quantity: 1, unit: "cup", nutrition: NutritionValues(kcal: 200),
                              provenance: .estimate, reference: "Synthetic rice serving"),
                     FoodItem(id: historyID(922), name: "Salad", quantity: 1, unit: "bowl", nutrition: NutritionValues(kcal: 50),
                              provenance: .estimate, reference: "Synthetic salad serving")]
        let bytes = try syntheticPhotoBytes()
        let photo = MealPhoto(id: historyID(930), data: bytes, createdAt: lunch.startAt)
        let meal = DiaryMeal(id: historyID(910), dayID: lunch.id, capturedAt: lunch.startAt, eatenAt: lunch.startAt,
            revision: 1, timePrecision: .dateOnly, items: items, photos: [photo],
            submissions: [MealSubmission(id: historyID(1), baseRevision: 0, text: "Synthetic lunch: chicken, rice and salad.", photoIDs: [photo.id], reviewFirst: false, state: .saved)])
        var dinner = meal; dinner.id = historyID(911); dinner.dayID = repeated.id; dinner.photos = []
        dinner.items = dinner.items.enumerated().map { index, item in var item = item; item.id = historyID(940 + index); return item }
        dinner.submissions = [MealSubmission(id: historyID(912), baseRevision: 0, text: "Synthetic dinner", photoIDs: [], reviewFirst: false, state: .saved)]
        var value = DiarySnapshot(revision: 9, profile: DiaryProfile(id: historyID(900), name: "Synthetic conversation", timeZoneID: "UTC"),
            days: [lunch, repeated, newer, empty], meals: [meal, dinner], activeDayID: empty.id, previousDayConfirmedAt: instant,
            activeConversationSegmentID: historyID(4000))
        value.coachTurns = (1...140).map { index in
            let day = index == 1 ? newer : index.isMultiple(of: 5) ? lunch : index.isMultiple(of: 2) ? repeated : newer
            let phrase = index.isMultiple(of: 3) ? "Apricot breakfast with a measured serving. " : "Cedar lunch. "
            let text = index == 1 ? "Synthetic lunch: chicken, rice and salad." : "Exchange \(index). " + String(repeating: phrase, count: index % 6 + 1)
            var turn = CoachTurn(id: historyID(index), capturedAt: day.startAt,
                text: text, state: .completed,
                assistantText: index.isMultiple(of: 2) ? String(repeating: "Recorded serving details. ", count: index % 5 + 1) : nil,
                captureTimeZoneID: "UTC", activeDayID: index.isMultiple(of: 11) ? nil : day.id,
                captureSegmentID: historyID(1000 + index))
            if index == 1 {
                turn.photoIDs = [photo.id]
                turn.receipts = [CoachReceipt(operationKey: "\(turn.id)/food/\(lunch.localDate)", turnID: turn.id,
                    dayID: lunch.id, mealID: meal.id, committedRevision: 1,
                    resultJSON: String(decoding: try! JSONEncoder().encode(CoachContext.Meal(id: meal.id, dayID: meal.dayID, revision: meal.revision, eatenAt: meal.eatenAt, timePrecision: meal.timePrecision, items: meal.items, state: .saved)), as: UTF8.self))]
            } else if index.isMultiple(of: 4) {
                let photo = MealPhoto(id: historyID(5000 + index), data: bytes, createdAt: turn.capturedAt)
                turn.photos = [photo]; turn.photoIDs = [photo.id]
            }
            if index == 80 {
                turn.receipts = [CoachReceipt(operationKey: "\(turn.id)/reference/\(meal.id)", turnID: turn.id,
                    dayID: lunch.id, mealID: meal.id, committedRevision: 1, resultJSON: "{}")]
            }
            return turn
        }
        if ProcessInfo.processInfo.arguments.contains("--history-short-paging") {
            value.coachTurns = Array(value.coachTurns.prefix(43))
            for index in value.coachTurns.indices {
                value.coachTurns[index].text = "Exchange \(index + 1)."
                value.coachTurns[index].assistantText = nil; value.coachTurns[index].photos = []; value.coachTurns[index].photoIDs = []
                value.coachTurns[index].receipts = []; value.coachTurns[index].activeDayID = empty.id
                value.coachTurns[index].capturedAt = empty.startAt; value.coachTurns[index].captureSegmentID = historyID(4001)
            }
        }
        if CoachCorrectionUITestFixture.isEnabled { try CoachCorrectionUITestFixture.prepare(snapshot: &value) }
        return value
    }
    @MainActor static func syntheticPhotoBytes() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let image = renderer.image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        guard let data = image.jpegData(compressionQuality: 0.8) else { throw DiaryError.invalidData }; return data
    }
}
#endif
