import Foundation

/// How one day's workouts earn back food budget: known calories count, and each overlap counts once with Health first.
struct ExerciseCredit: Equatable, Sendable {
    var creditedKcal: Double = 0
    /// The part of `creditedKcal` that came from Apple Health.
    var healthKcal: Double = 0
    /// Counted workouts whose calories are unknown.
    var uncountedCount = 0
    /// Diary workouts left out because an imported Health workout covers them, mapped to that Health workout.
    var coveredBy: [UUID: WorkoutSession] = [:]

    /// `workouts` is one day's workouts in saved order; among Health workouts the earliest saved wins.
    static func daily(_ workouts: [WorkoutSession]) -> ExerciseCredit {
        var credit = ExerciseCredit(), counted: [WorkoutSession] = []
        for workout in workouts.filter(\.isFromHealth) + workouts.filter({ !$0.isFromHealth }) {
            if let cover = counted.first(where: { covers($0, workout) }) {
                if !workout.isFromHealth { credit.coveredBy[workout.id] = cover }
                continue
            }
            counted.append(workout)
            guard let kcal = workout.estimatedBurnKcal else { credit.uncountedCount += 1; continue }
            credit.creditedKcal += kcal
            if workout.isFromHealth { credit.healthKcal += kcal }
        }
        return credit
    }

    /// Only an imported Health workout covers another; two diary workouts always both count.
    /// A diary workout saved without a time ("ran this morning") is covered by a Health workout of the same kind.
    /// A Health workout without calories never cancels one whose calories are known.
    static func covers(_ health: WorkoutSession, _ other: WorkoutSession) -> Bool {
        guard health.isFromHealth, health.estimatedBurnKcal != nil || other.estimatedBurnKcal == nil else { return false }
        guard health.timePrecision == .exact, other.timePrecision == .exact else { return health.kind == other.kind }
        func end(_ workout: WorkoutSession) -> Date { workout.performedAt.addingTimeInterval(Double(workout.durationMinutes) * 60) }
        return health.performedAt < end(other) && other.performedAt < end(health)
    }
}
