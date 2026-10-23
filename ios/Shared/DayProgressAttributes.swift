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

        var isOver: Bool { kcalEaten.flatMap { eaten in kcalTarget.map { eaten > $0 } } ?? false }
        var figure: String {
            guard let kcalEaten else { return "–" }
            return Self.number(kcalTarget.map { abs($0 - kcalEaten) } ?? kcalEaten)
        }
        var word: String { kcalTarget == nil ? "eaten" : isOver ? "over" : "left" }
        var compact: String { isOver ? "\(figure) over" : figure }

        var spoken: String {
            let macros = [("Protein", protein, proteinTarget), ("Carbs", carbs, carbsTarget), ("Fat", fat, fatTarget)]
                .compactMap { name, value, target in
                    value.map { v in target.map { "\(name) \(Self.number(v)) of \(Self.number($0)) grams." } ?? "\(name) \(Self.number(v)) grams." }
                }
            let calories = kcalEaten == nil ? "Calories not known yet." : "\(figure) calories \(word)."
            return ([calories] + macros).joined(separator: " ")
        }

        static func macroLabel(_ letter: String, _ value: Double?, _ target: Double?) -> String {
            "\(letter) \(macroAmount(value, target))"
        }

        /// "80/120g"; an unknown amount shows a dash, never a zero that looks recorded.
        static func macroAmount(_ value: Double?, _ target: Double?) -> String {
            let eaten = value.map(number) ?? "–"
            return target.map { "\(eaten)/\(number($0))g" } ?? (value == nil ? eaten : "\(eaten)g")
        }

        static func fraction(_ value: Double?, _ target: Double?) -> Double? {
            guard let value, let target, target > 0 else { return nil }
            return min(max(value / target, 0), 1)
        }

        static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
    }
}
