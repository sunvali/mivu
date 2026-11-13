import ActivityKit
import Foundation

/// A running live workout on the Lock Screen and in the Dynamic Island; the app sends every value.
struct WorkoutActivityAttributes: ActivityAttributes {
    let title: String

    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var restEndsAt: Date?
        /// The exercise being lifted, "Bench press".
        var exercise: String?
        /// Its next set, "set 3"; nil once every set is ticked.
        var nextSet: String?
        var hideWhenLocked: Bool

        /// "Bench press · set 3".
        var line: String? { exercise.map { name in nextSet.map { "\(name) · \($0)" } ?? name } }
        func isResting(at date: Date) -> Bool { restEndsAt.map { $0 > date } ?? false }
    }
}
