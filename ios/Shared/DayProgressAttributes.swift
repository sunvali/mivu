import ActivityKit
import Foundation

/// Today's calories and macros for the Live Activity; the app sends every value, the extension never opens the diary.
struct DayProgressAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var kcalEaten: Double
        var kcalTarget: Double?
        var protein: Double?
        var proteinTarget: Double?
        var carbs: Double?
        var carbsTarget: Double?
        var fat: Double?
        var fatTarget: Double?
        var hasPending: Bool
        var hideWhenLocked: Bool

        var isOver: Bool { kcalTarget.map { kcalEaten > $0 } ?? false }
        var figure: String { Self.number(kcalTarget.map { abs($0 - kcalEaten) } ?? kcalEaten) }
        var word: String { kcalTarget == nil ? "eaten" : isOver ? "over" : "left" }
        var compact: String { isOver ? "\(figure) over" : figure }

        var spoken: String {
            let macros = [("Protein", protein, proteinTarget), ("Carbs", carbs, carbsTarget), ("Fat", fat, fatTarget)]
                .compactMap { name, value, target in
                    value.map { v in target.map { "\(name) \(Self.number(v)) of \(Self.number($0)) grams." } ?? "\(name) \(Self.number(v)) grams." }
                }
            return (["\(figure) calories \(word)."] + macros).joined(separator: " ")
        }

        static func macroLabel(_ letter: String, _ value: Double?, _ target: Double?) -> String {
            let eaten = number(value ?? 0)
            return target.map { "\(letter) \(eaten)/\(number($0))g" } ?? "\(letter) \(eaten)g"
        }

        static func fraction(_ value: Double?, _ target: Double?) -> Double? {
            guard let target, target > 0 else { return nil }
            return min(max((value ?? 0) / target, 0), 1)
        }

        static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
    }
}
