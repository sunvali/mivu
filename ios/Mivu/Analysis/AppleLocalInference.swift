import Foundation
import FoundationModels

/// On-device fallback. The full Coach request (~16K tokens) exceeds the on-device window (4K on iPhone 15 Pro),
/// so one guided generation either logs a new meal or corrects a portion in the latest meal.
@available(iOS 27.0, *)
extension AppleInference {
    @Generable struct LocalTurn {
        @Generable enum Intent { case log, edit, other }
        @Generable struct Food {
            var name: String
            var quantity: Double
            var unit: String
            var kcal: Double
            @Guide(description: "grams") var carbs: Double
            @Guide(description: "grams") var protein: Double
            @Guide(description: "grams") var fat: Double
        }
        @Guide(description: "log: the message says the person ate or drank something. edit: it corrects the amount of something already logged. other: questions, thanks, greetings and anything else.")
        var intent: Intent
        @Guide(description: "For log: each food or drink named in the message with a realistic estimated serving and the total nutrition of that serving. Empty otherwise.")
        var foods: [Food]
        @Guide(description: "For edit: the food whose amount changes, as named in the message.")
        var editFood: String?
        @Guide(description: "For edit: the new total amount.")
        var editQuantity: Double?
    }

    struct LocalPrompt: Sendable {
        let text: String
        let images: [Data]
    }

    static let localLimits = "On-device Apple Intelligence can log new meals and change an amount in your latest meal. For anything else, choose ChatGPT in Settings → Coach AI."

    static func respondLocally(_ input: [CoachInferenceInput], namespace: Data?,
                               generate: (LocalPrompt) async throws -> LocalTurn = generateOnDevice) async throws -> CoachInferenceResult {
        // Onboarding asks for plain text without tools, and its prompt already fits on-device.
        guard namespace != nil else { return try await respond(input, namespace: nil, model: SystemLanguageModel.default) }
        // Once the save step has run, CoachEngine words the reply from its own receipts.
        if input.contains(where: { if case .functionOutput = $0 { true } else { false } }) { return try result(text: "Done.", calls: []) }

        var context: CoachContext?
        var texts: [String] = [], images: [Data] = []
        for item in input {
            guard case let .message(role, text, attached) = item else { continue }
            if role == .developer, let range = text.range(of: "Context: ", options: .backwards) {
                context = try JSONDecoder().decode(CoachContext.self, from: Data(text[range.upperBound...].utf8))
                texts = []; images = [] // Earlier user messages are history, not this capture.
            } else if role == .user {
                texts.append(text); images += attached
            }
        }
        guard let context else { throw ResponsesClient.Failure.invalidInput }
        let message = texts.joined(separator: "\n")
        // The small model sees only the message: shown saved foods, it logs them again.
        let turn = try await generate(LocalPrompt(text: message, images: images))
        let messageWords = words(message)
        // Without a photo, a food counts only when the message names it.
        let foods = turn.foods.filter { !images.isEmpty || !words($0.name).isDisjoint(with: messageWords) }

        if turn.intent == .log, !foods.isEmpty {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: context.captureTimeZoneID); formatter.dateFormat = "yyyy-MM-dd"
            let date = context.days.first { $0.id == context.activeDayID }?.localDate ?? formatter.string(from: context.capturedAt)
            let items = foods.map { ["name": $0.name, "quantity": $0.quantity, "unit": $0.unit, "kcal": $0.kcal,
                                          "carbs": $0.carbs, "protein": $0.protein, "fat": $0.fat] as [String: Any] }
            return try result(text: "", calls: [try call("log_food", ["target_local_date": date, "items": items])])
        }
        let latest = context.meals.filter { $0.omittedItemCount == 0 }.max { $0.eatenAt < $1.eatenAt }
        if turn.intent == .edit, let latest, let name = turn.editFood, let quantity = turn.editQuantity, quantity > 0,
           let item = latest.items.max(by: { words($0.name).intersection(words(name)).count < words($1.name).intersection(words(name)).count }),
           !words(item.name).isDisjoint(with: words(name)) {
            return try result(text: "", calls: [try call("correct_item", ["meal_id": latest.id.uuidString, "item_id": item.id.uuidString,
                                                                          "expected_revision": latest.revision, "quantity": quantity])])
        }
        return try result(text: localLimits, calls: [])
    }

    static func generateOnDevice(_ prompt: LocalPrompt) async throws -> LocalTurn {
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: """
            You read one food diary message. A question is other, even when it mentions food. \
            When an amount is missing, estimate a typical serving. Nutrition values are totals for the serving.
            """)
        let images = try prompt.images.map { try attachment($0).cgImage }
        return try await session.respond(generating: LocalTurn.self) {
            prompt.text
            for image in images { Attachment(image) }
        }.content
    }

    /// Lowercased words of three or more letters, with a plural "s" dropped, so "eggs" names "Boiled egg".
    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.filter { $0.count >= 3 }.map { $0.hasSuffix("s") ? String($0.dropLast()) : String($0) })
    }

    private static func call(_ name: String, _ arguments: [String: Any]) throws -> Transcript.ToolCall {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self)
        return Transcript.ToolCall(id: UUID().uuidString, toolName: name, arguments: try GeneratedContent(json: json))
    }
}
