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
        // Digits in any script (Arabic-Indic, Devanagari…) read as 0–9, with Arabic separators as "." and ",".
        let text = String(text.map { character -> Character in
            if character == "٫" { return "." }
            if character == "٬" { return "," }
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
                  scalar.properties.numericType == .decimal, let digit = character.wholeNumberValue else { return character }
            return Character(String(digit))
        })
        let pattern = /-?\d{1,3}(?:,\d{3})+(?:\.\d+)?|-?\d+(?:\.\d+)?/
        return text.matches(of: pattern).map { match in
            var token = String(match.output).replacingOccurrences(of: ",", with: "")
            // A hyphen joining date parts or a range is not a minus sign.
            if token.hasPrefix("-"), match.range.lowerBound > text.startIndex, text[text.index(before: match.range.lowerBound)].isNumber { token.removeFirst() }
            // An unreadable number fails closed: NaN is never in the allowed set.
            return Decimal(string: token, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
        }
    }

    /// The model ends a reply with this line when the reply says something was saved, in any language.
    static let saveMarker = "<saved/>"

    /// The prose without the marker, and whether the marker was present.
    static func splitSaveClaim(_ prose: String) -> (text: String, claimsSave: Bool) {
        (prose.replacingOccurrences(of: saveMarker, with: "").trimmingCharacters(in: .whitespacesAndNewlines), prose.contains(saveMarker))
    }

    static func passes(_ prose: String, allowed: Set<Decimal>, receipts: [CoachCommittedReceipt], claimsSave: Bool = false) -> Bool {
        guard !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if receipts.contains(where: { $0.mealID != nil && $0.submissionState == .awaitingReview }) {
            // shortcut: English-only net beside the marker, remove once a live evaluation shows the marker alone holds.
            let lowered = prose.lowercased()
            if claimsSave || lowered.contains("logged") || lowered.contains("saved") { return false }
        }
        return numbers(in: prose).allSatisfy { allowed.contains(abs($0)) }
    }

    // Decimal(Double) keeps binary noise (73.6 → 73.59999…); the shortest description does not.
    private static func decimal(_ value: Double) -> Decimal { Decimal(string: "\(value)") ?? Decimal(value) }

    private static func rounded(_ value: Decimal, to step: Decimal) -> Decimal {
        var scaled = value / step, result = Decimal()
        NSDecimalRound(&result, &scaled, 0, .plain)
        return result * step
    }
}
