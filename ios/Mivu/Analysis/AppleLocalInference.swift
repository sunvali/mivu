import Foundation
import FoundationModels

/// On-device fallback. The full Coach request (~16K tokens) exceeds the on-device window (4K on iPhone 15 Pro),
/// so one guided generation either logs a new meal or corrects a portion in the latest meal.
@available(iOS 27.0, *)
extension AppleInference {
    @Generable struct LocalTurn {
        @Generable enum Intent { case log, edit, other }
        // Measured on-device: serving totals are reliable for countable servings, per-100 g values for weighed amounts.
        @Generable struct Food {
            @Guide(description: "The food as the message names it.") var name: String
            @Guide(description: "A plain generic name for a nutrition database search, such as diet cola for coke zero.") var searchName: String
            @Guide(description: "The amount the message states; 1 when it states none.") var quantity: Double
            @Guide(description: "g or ml when the message gives a weight or volume, otherwise the serving unit such as can, slice or piece.") var unit: String
            @Guide(description: "Total for the whole serving.") var kcal: Double
            @Guide(description: "Total grams for the whole serving.") var carbs: Double
            @Guide(description: "Total grams for the whole serving.") var protein: Double
            @Guide(description: "Total grams for the whole serving.") var fat: Double
            @Guide(description: "Per 100 g, or per 100 ml for drinks.") var kcalPer100g: Double
            var carbsPer100g: Double
            var proteinPer100g: Double
            var fatPer100g: Double
        }
        @Guide(description: "log: the message says or implies the person ate or drank something; a message that only names food, like coke zero or 200g chicken, is log. edit: it corrects the amount of something already logged, like make it 3. other: questions, thanks, greetings and anything else.")
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


    static func respondLocally(_ input: [CoachInferenceInput], namespace: Data?, table: NutritionTable = .bundled,
                               pick: (String, [NutritionTable.Food]) async throws -> Int = pickOnDevice,
                               generate: (LocalPrompt) async throws -> LocalTurn = generateOnDevice) async throws -> CoachInferenceResult {
        // Only Coach turns run on-device; onboarding targets use the formula estimate instead.
        guard namespace != nil else { throw ResponsesClient.Failure.invalidInput }
        // Once the save step has run, CoachEngine words the reply from its own receipts.
        if input.contains(where: { if case .functionOutput = $0 { true } else { false } }) { return try result(text: "Done.", calls: []) }

        var context: CoachContext?
        var texts: [String] = [], images: [Data] = []
        for item in input {
            guard case let .message(role, text, attached) = item else { continue }
            // The first marker is CoachEngine's; later ones can be food names inside the context itself.
            if role == .developer, let range = text.range(of: "Context: ") {
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
        let words = NutritionTable.words
        let messageWords = words(message)
        // Without a photo, a food counts only when the message names it.
        let foods = turn.foods.filter { !images.isEmpty || !words($0.name).isDisjoint(with: messageWords) }

        // "It" is the meal the conversation last changed; date-only meal times tie, so eatenAt is only the fallback.
        let complete = context.meals.filter { $0.omittedItemCount == 0 }
        let latest = context.focus?.lastChanged.flatMap { changed in complete.first { $0.id == changed.mealID } }
            ?? complete.max { $0.eatenAt < $1.eatenAt }
        // A named food must match a saved one; "make it three" names none and is safe only for a single-item meal.
        // Only words the message says count: on-device the model invents names ("chocolate" for "make it three").
        let named = words(turn.editFood ?? "").intersection(messageWords)
        let target = named.isEmpty ? (latest?.items.count == 1 ? latest?.items.first : nil)
            : latest?.items.max { words($0.name).intersection(named).count < words($1.name).intersection(named).count }
                .flatMap { words($0.name).isDisjoint(with: named) ? nil : $0 }
        if turn.intent == .edit, let latest, let item = target, let quantity = turn.editQuantity, quantity > 0 {
            return try result(text: "", calls: [try call("correct_item", ["meal_id": latest.id.uuidString, "item_id": item.id.uuidString,
                                                                          "expected_revision": latest.revision, "quantity": quantity])])
        }
        // An edit that names no saved food is usually a bare food mention such as "coke zero".
        if turn.intent != .other, !foods.isEmpty {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: context.captureTimeZoneID); formatter.dateFormat = "yyyy-MM-dd"
            let date = context.days.first { $0.id == context.activeDayID }?.localDate ?? formatter.string(from: context.capturedAt)
            var items: [[String: Any]] = []
            for food in foods {
                let weighed = ["g", "gram", "grams", "ml", "milliliter", "milliliters"].contains(food.unit.lowercased())
                func rounded(_ value: Double?) -> Double { (min(max(value ?? 0, 0), 100_000) * 10).rounded() / 10 }
                // Numbers come from the USDA table when the on-device model confirms a match and a portion weight exists.
                if let (match, grams) = try await tableMatch(food, weighed: weighed, table: table, pick: pick) {
                    let nutrition = match.per100Grams.scaled(by: grams / 100)
                    items.append(["name": food.name, "quantity": food.quantity, "unit": food.unit, "kcal": rounded(nutrition.kcal),
                                  "carbs": rounded(nutrition.carbs), "protein": rounded(nutrition.protein), "fat": rounded(nutrition.fat)])
                    continue
                }
                func value(_ total: Double, _ per100: Double) -> Double {
                    (min(max(weighed ? per100 * food.quantity / 100 : total, 0), 100_000) * 10).rounded() / 10
                }
                let carbs = value(food.carbs, food.carbsPer100g), protein = value(food.protein, food.proteinPer100g)
                let fat = value(food.fat, food.fatPer100g), fromMacros = (4 * (carbs + protein) + 9 * fat).rounded()
                // Calories cannot sit far below what the macros imply; alcohol only raises them, so no upper bound.
                var kcal = value(food.kcal, food.kcalPer100g)
                if kcal < 0.7 * fromMacros { kcal = fromMacros }
                items.append(["name": food.name, "quantity": food.quantity, "unit": food.unit, "kcal": kcal, "carbs": carbs, "protein": protein, "fat": fat])
            }
            return try result(text: "", calls: [try call("log_food", ["target_local_date": date, "items": items])])
        }
        // CoachEngine replaces text-only replies with its recorded summary; Coach shows the Apple limits under the input.
        return try result(text: "Nothing to change.", calls: [])
    }

    /// The matched table entry and total grams, or nil to keep the model's estimate.
    private static func tableMatch(_ food: LocalTurn.Food, weighed: Bool, table: NutritionTable,
                                   pick: (String, [NutritionTable.Food]) async throws -> Int) async throws -> (NutritionTable.Food, Double)? {
        var options = (try? table.search(food.searchName)) ?? []
        if options.isEmpty { options = (try? table.search(food.name)) ?? [] }
        guard !options.isEmpty else { return nil }
        let choice: Int
        do { choice = try await pick("\(food.quantity.formatted()) \(food.unit) \(food.name)", options) }
        catch is CancellationError { throw CancellationError() }
        catch { return nil } // A failed pick keeps the estimate rather than failing the turn.
        guard options.indices.contains(choice - 1) else { return nil }
        let match = options[choice - 1]
        // shortcut: ml counts as grams, close for drinks; use FNDDS "fl oz" portions if density matters.
        // Only a weighed amount or a portion naming the person's own unit is trusted; synonyms and default servings
        // measured worse than the model's estimate (e.g. a 60 g default "cookie" serving).
        let portion = (try? table.portionGrams(code: match.code, unit: food.unit)).flatMap { $0 }.map { $0 * food.quantity }
        guard let grams = weighed ? food.quantity : portion, grams > 0 else { return nil }
        return (match, grams)
    }

    @Generable struct Pick {
        @Guide(description: "The number of the option that is the same food, or 0 when none is.", .range(0...5)) var option: Int
    }

    static func pickOnDevice(_ phrase: String, _ options: [NutritionTable.Food]) async throws -> Int {
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: """
            Match a food to a nutrition database entry. Choose the plainest entry that is the same food and preparation.
            """)
        let list = options.enumerated().map { "\($0.offset + 1). \($0.element.description)" }.joined(separator: "\n")
        return try await session.respond(generating: Pick.self, options: GenerationOptions(sampling: .greedy)) {
            "Food: \(phrase)\nOptions:\n\(list)"
        }.content.option
    }

    static func generateOnDevice(_ prompt: LocalPrompt) async throws -> LocalTurn {
        // Apple's guidance for the ~3B model: one task, a few examples, greedy sampling for extraction.
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: """
            Read one food diary message and fill in the result. A question is other, even when it mentions food. \
            When an amount is missing, estimate a typical serving. \
            Zero, diet and sugar-free drinks, water, black coffee and plain tea have almost no calories or carbs.
            """)
        let images = try prompt.images.map { try attachment($0).cgImage }
        return try await session.respond(generating: LocalTurn.self, options: GenerationOptions(sampling: .greedy)) {
            prompt.text
            for image in images { Attachment(image) }
        }.content
    }



    private static func call(_ name: String, _ arguments: [String: Any]) throws -> Transcript.ToolCall {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self)
        return Transcript.ToolCall(id: UUID().uuidString, toolName: name, arguments: try GeneratedContent(json: json))
    }
}
