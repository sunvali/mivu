import Foundation

// Explicit UI-test isolation is required by the caller; no provider request is made.
enum CoachUITestInference {
    static func respond(_ input: [CoachInferenceInput], _: Data) throws -> CoachInferenceResult {
        if input.contains(where: { if case .functionOutput = $0 { return true }; return false }) {
            return CoachInferenceResult(model: "native-test-fixture", text: "Fixture finished.", calls: [], outputItems: [])
        }
        guard let developer = input.compactMap({ entry -> String? in
            if case .message(role: .developer, let text, _) = entry { return text }; return nil
        }).first, let range = developer.range(of: "Context: "),
        let data = String(developer[range.upperBound...]).data(using: .utf8) else { throw CoachError.invalidArguments }
        let context = try JSONDecoder().decode(CoachContext.self, from: data)
        let text = input.compactMap { entry -> String? in
            if case .message(role: .user, let text, _) = entry { return text }; return nil
        }.joined(separator: " ").lowercased()
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
            if text.contains("yesterday") {
                items = [["name":"Dessert", "quantity":1, "unit":"serving", "kcal":100, "carbs":15, "protein":2, "fat":4]]
            } else if text.contains("review") {
                items = [["name":"Snack", "quantity":1, "unit":"serving", "kcal":80, "carbs":15, "protein":2, "fat":1]]
            } else {
                items = [["name":"Eggs", "quantity":2, "unit":"egg", "kcal":140, "carbs":1, "protein":12, "fat":10],
                         ["name":"Bread", "quantity":3, "unit":"slice", "kcal":240, "carbs":45, "protein":9, "fat":3],
                         ["name":"Salad", "quantity":1, "unit":"bowl", "kcal":40, "carbs":8, "protein":1, "fat":0]]
            }
            name = "log_food"; arguments = ["target_local_date": localDate, "items": items]
        }
        let argumentsJSON = String(data: try JSONSerialization.data(withJSONObject: arguments, options: .sortedKeys), encoding: .utf8)!
        let id = UUID().uuidString
        return CoachInferenceResult(model: "native-test-fixture", text: "", calls: [CoachToolCall(id: id, callID: id, name: name, namespace: "mivu", arguments: argumentsJSON)], outputItems: [])
    }
}
