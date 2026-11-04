import Foundation

/// A saved workout to start again; the sets in `exercises` are targets, not results.
struct WorkoutRoutine: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var revision = 1
    var name: String
    var exercises: [WorkoutExercise]
    var lastUsedAt: Date?
}

func validateRoutineFields(_ routine: WorkoutRoutine) throws {
    guard routine.revision > 0, routine.revision < 1_000_000,
          !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, routine.name.count <= 100,
          routine.exercises.count <= 50, routine.lastUsedAt?.timeIntervalSince1970.isFinite ?? true else { throw DiaryError.invalidData }
    try validateWorkoutExercises(routine.exercises)
}
