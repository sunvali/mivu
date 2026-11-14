import Foundation

/// Decides whether the model's prose may be shown: every number must come from this turn's facts.
/// Independent of the store and UI so a server worker can run the same check.
enum CoachReplyCheck {
    static func allowedNumbers(in sources: [String], receipts: [CoachCommittedReceipt]) -> Set<Decimal> {
        // IDs are digit soup: their fragments would ground almost any number.
        var values = sources.map { $0.replacing(/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/, with: "") }.flatMap(numbers(in:))
        for receipt in receipts {
            for item in receipt.items {
                values.append(decimal(item.quantity))
                if let nutrition = item.nutrition {
                    values += [nutrition.kcal, nutrition.carbs, nutrition.protein, nutrition.fat].compactMap { $0.map(decimal) }
                }
            }
            for nutrient in [\NutritionValues.kcal, \.carbs, \.protein, \.fat] {
                let parts = receipt.items.compactMap { $0.nutrition?[keyPath: nutrient] }
                if !parts.isEmpty { values.append(decimal(parts.reduce(0, +))) }
            }
            values += [receipt.weightValue.map(decimal), receipt.workoutMinutes.map { Decimal($0) }].compactMap { $0 }
        }
        var allowed = Set<Decimal>()
        // Sign is phrasing ("down 0.4 kg"), so compare magnitudes.
        for value in values.map({ abs($0) }) {
            allowed.insert(value)
            allowed.insert(rounded(value, to: 1))
            allowed.insert(rounded(value, to: 10))
        }
        return allowed
    }

    static func numbers(in text: String) -> [Decimal] {
        let pattern = /-?\d{1,3}(?:,\d{3})+(?:\.\d+)?|-?\d+(?:\.\d+)?/
        return text.matches(of: pattern).compactMap { match in
            var token = String(match.output).replacingOccurrences(of: ",", with: "")
            // A hyphen joining date parts or a range is not a minus sign.
            if token.hasPrefix("-"), match.range.lowerBound > text.startIndex, text[text.index(before: match.range.lowerBound)].isNumber { token.removeFirst() }
            return Decimal(string: token, locale: Locale(identifier: "en_US_POSIX"))
        }
    }

    /// `generalFacts` lets a read-only answer use typical food values in hedged sentences that do not describe the diary.
    static func passes(_ prose: String, allowed: Set<Decimal>, receipts: [CoachCommittedReceipt], generalFacts: Bool = false) -> Bool {
        guard !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if receipts.contains(where: { $0.mealID != nil && $0.submissionState == .awaitingReview }) {
            let lowered = prose.lowercased()
            if lowered.contains("logged") || lowered.contains("saved") { return false }
        }
        func grounded(_ text: some StringProtocol) -> Bool { numbers(in: String(text)).allSatisfy { allowed.contains(abs($0)) } }
        guard generalFacts, receipts.isEmpty else { return grounded(prose) }
        let hedge = /~|\b(?i:about|around|roughly|approximately|typically|usually|nearly)\b/
        let diaryWords = /\b(?i:left|remaining|to go|so far|today|yesterday|this week|goal|target|budget|average|you're|you are|you've|you have|you had|you ate|your)\b/
        return prose.split(separator: /[.!?]\s+|\n+/).allSatisfy { sentence in
            let plain = sentence.replacingOccurrences(of: "’", with: "'")
            return grounded(plain) || (plain.contains(hedge) && !plain.contains(diaryWords))
        }
    }

    // Decimal(Double) keeps binary noise (73.6 → 73.59999…); the shortest description does not.
    private static func decimal(_ value: Double) -> Decimal { Decimal(string: "\(value)") ?? Decimal(value) }

    private static func rounded(_ value: Decimal, to step: Decimal) -> Decimal {
        var scaled = value / step, result = Decimal()
        NSDecimalRound(&result, &scaled, 0, .plain)
        return result * step
    }
}
