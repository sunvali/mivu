import Foundation

// Explicit UI-test isolation is required by the caller; no provider request is made.
enum CoachUITestInference {
    static func respond(_ input: [CoachInferenceInput], _: Data) async throws -> CoachInferenceResult {
        if input.contains(where: {
            if case .message(role: .user, let text, _) = $0 { return text == "Synthetic delayed weekly report" }
            return false
        }) {
            try await Task.sleep(for: .seconds(8))
        }
        guard let developer = input.compactMap({ entry -> String? in
            if case .message(role: .developer, let text, _) = entry { return text }; return nil
        }).first, let range = developer.range(of: "Context: "),
        let data = String(developer[range.upperBound...]).data(using: .utf8) else { throw CoachError.invalidArguments }
        let context = try JSONDecoder().decode(CoachContext.self, from: data)
        let text = input.compactMap { entry -> String? in
            if case .message(role: .user, let text, _) = entry { return text }; return nil
        }.joined(separator: " ").lowercased()
        if text.contains("edit yesterday’s lunch"), text.contains("one more chicken") {
            return try correction(input, context: context)
        }
        if input.contains(where: { if case .functionOutput = $0 { return true }; return false }) {
            return CoachInferenceResult(model: "native-test-fixture", text: "Fixture finished.", calls: [], outputItems: [])
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
    private static func correction(_ input: [CoachInferenceInput], context: CoachContext) throws -> CoachInferenceResult {
        func reply(_ name: String? = nil, _ args: [String: Any] = [:]) throws -> CoachInferenceResult {
            let id = UUID().uuidString
            let calls = try name.map { [CoachToolCall(id: id, callID: id, name: $0, namespace: "mivu",
                arguments: String(decoding: try JSONSerialization.data(withJSONObject: args, options: .sortedKeys), as: UTF8.self))] } ?? []
            return CoachInferenceResult(model: "native-test-fixture", text: "Fixture finished.", calls: calls, outputItems: [])
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
/// Generates bounded pages without opening a profile or constructing DiaryRootView.
actor CoachScrollSpikeSource {
    static let identity = CoachTimelineIdentity(profileID: id(900), timelineGeneration: id(901))
    private var held: [CoachPageDirection: CheckedContinuation<Void, Never>] = [:]
    private var armed: Set<CoachPageDirection> = []
    private var released: Set<CoachPageDirection> = []
    private var replyCompleted = false

    static func id(_ sequence: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", sequence))!
    }

    func arm(_ direction: CoachPageDirection) { armed.insert(direction) }
    func release(_ direction: CoachPageDirection) {
        if let continuation = held.removeValue(forKey: direction) { continuation.resume() }
        else if armed.contains(direction) { released.insert(direction) }
    }
    func completeReply() { replyCompleted = true }

    func page(_ request: CoachPageRequest, _: UUID) async -> CoachPage {
        let upper: Int
        switch request {
        case .latest: upper = 140
        case .before(let cursor):
            await barrier(.earlier)
            upper = Int(cursor.sequence) - 1
        case .after(let cursor):
            await barrier(.later)
            upper = min(140, Int(cursor.sequence) + 20)
        case .aroundTurn(let id): upper = min(140, (1...140).first { Self.id($0) == id }.map { $0 + 10 } ?? 140)
        case .atDay: upper = 140
        }
        let lower = max(1, upper - 19)
        var rows = upper >= lower ? (lower...upper).map(Self.exchange) : []
        if replyCompleted, let index = rows.firstIndex(where: { $0.sequence == 140 }) {
            rows[index].assistantText = "Off-viewport asynchronous reply completed."
        }
        return CoachPage(identity: Self.identity, exchanges: rows,
                         before: rows.first.map(Self.cursor), after: rows.last.map(Self.cursor),
                         hasEarlier: lower > 1, hasLater: upper < 140,
                         earlierSegment: nil, laterSegment: nil)
    }

    private func barrier(_ direction: CoachPageDirection) async {
        if armed.remove(direction) != nil, released.remove(direction) == nil {
            await withCheckedContinuation { held[direction] = $0 }
        }
    }

    private static func cursor(_ row: CoachExchangeSummary) -> CoachCursor {
        CoachCursor(identity: identity, sequence: row.sequence, turnID: row.id)
    }

    private static func exchange(_ sequence: Int) -> CoachExchangeSummary {
        let phrase = sequence.isMultiple(of: 3) ? "Apricot breakfast with a measured serving. " : "Cedar lunch. "
        return CoachExchangeSummary(id: id(sequence), sequence: Int64(sequence),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000), captureTimeZoneID: "UTC",
            segmentID: id(800 + sequence / 20), trackingDayID: nil,
            displayLocalDate: (sequence / 20).isMultiple(of: 2) ? "2026-10-17" : "2026-10-18", displayTimeZoneID: "UTC",
            text: "Exchange \(sequence). " + String(repeating: phrase, count: sequence % 6 + 1),
            assistantText: sequence.isMultiple(of: 2) ? String(repeating: "Recorded serving details. ", count: sequence % 5 + 1) : nil,
            state: .completed, photos: [], receipts: [])
    }
}
#endif
