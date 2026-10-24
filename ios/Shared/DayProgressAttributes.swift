import ActivityKit
import Foundation

/// Today's calories and macros for the Live Activity; the app sends every value, the extension never opens the diary.
struct DayProgressAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Nil while any of today's items has no calories, so the island never shows a total it doesn't know.
        var kcalEaten: Double?
        var kcalTarget: Double?
        var protein: Double?
        var proteinTarget: Double?
        var carbs: Double?
        var carbsTarget: Double?
        var fat: Double?
        var fatTarget: Double?
        var hideWhenLocked: Bool
        /// Nutrients ("kcal", "protein", "carbs", "fat") some food lacks, so their amounts are only what is known.
        /// Optional so an older running activity still decodes.
        var partial: [String]? = nil

        func isPartial(_ nutrient: String) -> Bool { partial?.contains(nutrient) == true }
        var isOver: Bool { kcalEaten.flatMap { eaten in kcalTarget.map { eaten > $0 } } ?? false }
        private var kcalNumber: String? {
            kcalEaten.map { eaten in Self.number(kcalTarget.map { abs($0 - eaten) } ?? eaten) }
        }
        /// Unknown calories can only add intake, so a partial figure is at most what is left, or at least what is over or eaten.
        var figure: String {
            guard let kcalNumber else { return "–" }
            guard isPartial("kcal") else { return kcalNumber }
            return word == "left" ? "≤" + kcalNumber : kcalNumber + "+"
        }
        var word: String { kcalTarget == nil ? "eaten" : isOver ? "over" : "left" }
        var compact: String { isOver ? "\(figure) over" : figure }

        var spoken: String {
            let macros = [("Protein", protein, proteinTarget), ("Carbs", carbs, carbsTarget), ("Fat", fat, fatTarget)]
                .compactMap { name, value, target in
                    value.map { v in
                        let amount = (isPartial(name.lowercased()) ? "at least " : "") + Self.number(v)
                        return target.map { "\(name) \(amount) of \(Self.number($0)) grams." } ?? "\(name) \(amount) grams."
                    }
                }
            let bound = isPartial("kcal") ? (word == "left" ? "At most " : "At least ") : ""
            let calories = kcalNumber.map { "\(bound)\($0) calories \(word)." } ?? "Calories not known yet."
            return ([calories] + macros).joined(separator: " ")
        }

        static func macroLabel(_ letter: String, _ value: Double?, _ target: Double?) -> String {
            "\(letter) \(macroAmount(value, target))"
        }

        /// "80/120g"; an unknown amount shows a dash, never a zero that looks recorded, and a partial one reads "80+".
        static func macroAmount(_ value: Double?, _ target: Double?, partial: Bool = false) -> String {
            let eaten = value.map { number($0) + (partial ? "+" : "") } ?? "–"
            return target.map { "\(eaten)/\(number($0))g" } ?? (value == nil ? eaten : "\(eaten)g")
        }

        static func fraction(_ value: Double?, _ target: Double?) -> Double? {
            guard let value, let target, target > 0 else { return nil }
            return min(max(value / target, 0), 1)
        }

        static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
    }
}
