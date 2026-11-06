import Foundation

#if DEBUG
/// UI tests only: "Push day" and "Leg day" routines and yesterday's bench, so a heavier bench is a new best.
/// With `--coach-workout-running`, Push day is already running with one bench set ticked.
enum CoachWorkoutUITestFixture {
    static var isEnabled: Bool { DiaryLaunch.isCoachUITest && ProcessInfo.processInfo.arguments.contains("--coach-workout-fixture") }

    static func seed(_ store: DiaryStore, profile: DiaryProfile) async throws {
        let bench = WorkoutExercise(name: "Barbell Bench Press", sets: [WorkoutSet(repetitions: 8, loadKg: 60)], exerciseID: "barbell-bench-press", measure: .weightReps)
        let squat = WorkoutExercise(name: "Barbell Back Squat", sets: [WorkoutSet(repetitions: 5, loadKg: 80)], exerciseID: "barbell-back-squat", measure: .weightReps)
        let push = try await store.saveRoutine(WorkoutRoutine(name: "Push day", exercises: [bench]), expectedRevision: nil, expectedProfileID: profile.id)
        _ = try await store.saveRoutine(WorkoutRoutine(name: "Leg day", exercises: [squat]), expectedRevision: nil, expectedProfileID: profile.id)
        let yesterday = diaryDateLabel(Date().addingTimeInterval(-86_400), zone: profile.timeZoneID)
        _ = try await store.createWorkout(localDate: yesterday, draft: WorkoutDraft(kind: .strength, durationMinutes: 40, exercises: [bench], activity: "strength"),
                                          performedAt: nil, expectedProfileID: profile.id)
        guard ProcessInfo.processInfo.arguments.contains("--coach-workout-running") else { return }
        var draft = push.draft
        draft.exercises[0].sets[0].done = true
        _ = try await store.startWorkout(draft, at: Date(), expectedProfileID: profile.id)
    }
}
#endif
