import Foundation

/// A saved workout to start again; the sets in `exercises` are targets, not results.
struct WorkoutRoutine: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var revision = 1
    var name: String
    var exercises: [WorkoutExercise]
    var lastUsedAt: Date?
}

extension WorkoutRoutine {
    /// A finished workout as a routine: its ticked sets become the targets.
    init(from session: WorkoutSession, name: String) {
        self.init(name: name, exercises: session.exercises.compactMap { exercise in
            var target = exercise
            target.sets = exercise.sets.filter { $0.done == true }.map { var set = $0; set.done = nil; set.effort = nil; return set }
            return target.sets.isEmpty ? nil : target
        }, lastUsedAt: session.performedAt)
    }
}

extension WorkoutRoutine {
    /// A live gym workout started from this routine.
    var draft: WorkoutDraft { WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: exercises, title: name, activity: "strength", routineID: id) }
}

func validateRoutineFields(_ routine: WorkoutRoutine) throws {
    guard routine.revision > 0, routine.revision < 1_000_000,
          !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, routine.name.count <= 100,
          routine.exercises.count <= 50, routine.lastUsedAt?.timeIntervalSince1970.isFinite ?? true else { throw DiaryError.invalidData }
    try validateWorkoutExercises(routine.exercises)
}
