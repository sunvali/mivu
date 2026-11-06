import Foundation

/// Identifies "the same exercise" across workouts: catalog ID, else the normalized own name.
struct ExerciseKey: Hashable, Sendable {
    let raw: String

    init(_ exercise: WorkoutExercise) {
        raw = exercise.exerciseID ?? "own:" + WorkoutCatalog.normalized(exercise.name)
    }
}

struct ExerciseBests: Equatable, Sendable {
    var heaviestKg: Double?
    var mostReps: Int?
    var longestSeconds: Int?
}

/// Pure history lookups. Callers pass finished sessions newest first. A set with no
/// `done` flag (saved before live workouts) counts as done.
enum WorkoutHistory {
    static func lastTime(for key: ExerciseKey, position: Int, type: WorkoutSetType, in finished: [WorkoutSession]) -> WorkoutSet? {
        for session in finished where session.isFinished {
            let sets = session.exercises.filter { ExerciseKey($0) == key }.flatMap(\.sets)
            guard !sets.isEmpty else { continue }
            let matching = sets.filter { ($0.type ?? .normal) == type && $0.done != false }
            return matching.indices.contains(position - 1) ? matching[position - 1] : matching.last
        }
        return nil
    }

    static func isNewBest(_ set: WorkoutSet, measure: ExerciseMeasure, before: [WorkoutSet]) -> Bool {
        let before = before.filter { $0.type != .warmup && $0.done != false }
        guard set.type != .warmup, !before.isEmpty else { return false }
        switch measure {
        case .weightReps:
            let load = set.loadKg ?? 0
            if load > before.map({ $0.loadKg ?? 0 }).max()! { return true }
            return set.repetitions > before.filter { ($0.loadKg ?? 0) >= load }.map(\.repetitions).max()!
        case .reps:
            return set.repetitions > before.map(\.repetitions).max()!
        case .time:
            return (set.seconds ?? 0) > before.map { $0.seconds ?? 0 }.max()!
        case .distanceTime:
            return false
        }
    }

    static func bests(for key: ExerciseKey, in finished: [WorkoutSession]) -> ExerciseBests {
        let sets = finished.filter(\.isFinished).flatMap(\.exercises).filter { ExerciseKey($0) == key }
            .flatMap(\.sets).filter { $0.type != .warmup && $0.done != false }
        return ExerciseBests(heaviestKg: sets.compactMap(\.loadKg).max(), mostReps: sets.map(\.repetitions).max(),
                             longestSeconds: sets.compactMap(\.seconds).max())
    }
}
