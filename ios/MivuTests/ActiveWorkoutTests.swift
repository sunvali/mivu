import Foundation
import Testing
@testable import Mivu

@Suite struct ActiveWorkoutTests {
    private let start = ISO8601DateFormatter().date(from: "2027-03-10T10:00:00+02:00")!
    private let bench = WorkoutExercise(name: "Bench Press", sets: [], exerciseID: "barbell-bench-press")

    private func fixture(now: Date? = nil) async throws -> (DiaryStore, DiaryProfile, URL) {
        let root = URL.temporaryDirectory.appending(path: "ActiveWorkout-" + UUID().uuidString)
        let profile = DiaryProfile(name: "Synthetic gym", timeZoneID: "Asia/Jerusalem")
        let store = now.map { now in DiaryStore(directory: root, currentTime: { now }) } ?? DiaryStore(directory: root)
        _ = try await store.createProfile(profile)
        return (store, profile, root)
    }

    private func gym(_ ticks: Bool?...) -> WorkoutDraft {
        var exercise = bench
        exercise.sets = ticks.map { WorkoutSet(repetitions: 8, loadKg: 60, done: $0) }
        return WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: [exercise])
    }

    @Test func startThenReopen() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var active = try await store.startWorkout(gym(), at: start, expectedProfileID: profile.id)
        #expect(active.state == .active && active.source == .live && active.performedAt == start && active.durationMinutes == 0)
        active.exercises[0].sets = [WorkoutSet(repetitions: 8, loadKg: 60, done: true)]
        active = try await store.saveActive(active, expectedRevision: active.revision, expectedProfileID: profile.id)
        active.exercises[0].sets.append(WorkoutSet(repetitions: 8, loadKg: 62.5, done: true))
        active = try await store.saveActive(active, expectedRevision: active.revision, expectedProfileID: profile.id)

        let reopened = DiaryStore(directory: root)
        _ = try await reopened.selectProfile(profile.id)
        let restored = try #require(try await reopened.activeWorkout(expectedProfileID: profile.id))
        #expect(restored == active && restored.exercises[0].sets.map(\.done) == [true, true])
        await #expect(throws: DiaryError.staleRevision) { try await reopened.saveActive(active, expectedRevision: 1, expectedProfileID: profile.id) }
    }

    @Test func startAfterMidnightStaysOnWakingDay() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try await store.startDay(at: start, expectedProfileID: profile.id)
        // 01:30 the next calendar day, before the 04:00 cutoff: still the open day, as a meal captured now.
        let night = ISO8601DateFormatter().date(from: "2027-03-11T01:30:00+02:00")!
        var active = try await store.startWorkout(gym(true), at: night, expectedProfileID: profile.id)
        #expect(active.dayID == day.id && active.performedAt == night)
        active = try await store.saveActive(active, expectedRevision: active.revision, expectedProfileID: profile.id)
        let finished = try await store.finishWorkout(id: active.id, effort: nil, at: night.addingTimeInterval(1_800), expectedRevision: active.revision, expectedProfileID: profile.id)
        #expect(finished.dayID == day.id)
        #expect(try await store.diaryReadModel(expectedProfileID: profile.id).workouts.map(\.id) == [finished.id])

        // After the cutoff a new day starts, as for meals.
        let morning = ISO8601DateFormatter().date(from: "2027-03-11T09:00:00+02:00")!
        let next = try await store.startWorkout(gym(), at: morning, expectedProfileID: profile.id)
        #expect(next.dayID != day.id)
    }

    @Test func onlyOneActive() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try await store.startWorkout(gym(), at: start, expectedProfileID: profile.id)
        await #expect(throws: DiaryError.conflict) { try await store.startWorkout(gym(), at: start.addingTimeInterval(60), expectedProfileID: profile.id) }

        try await store.discardWorkout(id: first.id, expectedRevision: first.revision, expectedProfileID: profile.id)
        #expect(try await store.activeWorkout(expectedProfileID: profile.id) == nil)
        #expect(try await store.snapshotForExport().deletedWorkoutIDs == [first.id])
        let second = try await store.startWorkout(gym(), at: start.addingTimeInterval(60), expectedProfileID: profile.id)
        #expect(try await store.activeWorkout(expectedProfileID: profile.id) == second)
    }

    @Test func activeExcludedFromTotalsHistoryAndProgress() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await store.recordWeight(value: 80, at: start.addingTimeInterval(-3600), expectedProfileID: profile.id)
        let done = try await store.createWorkout(localDate: "2027-03-10", draft: WorkoutDraft(kind: .cardio, durationMinutes: 30, exercises: [], estimatedBurnKcal: 200),
                                                 performedAt: start.addingTimeInterval(-1800), expectedProfileID: profile.id)
        var active = try await store.startWorkout(gym(true), at: start, expectedProfileID: profile.id)
        active.estimatedBurnKcal = 999
        active = try await store.saveActive(active, expectedRevision: active.revision, expectedProfileID: profile.id)

        let read = try await store.diaryReadModel(expectedProfileID: profile.id)
        #expect(read.workouts == [done] && read.activeWorkout == active)
        #expect(try await store.workoutHistory(expectedProfileID: profile.id).values == [done])
        let progress = try await store.progressForDisplay(endingOn: "2027-03-10", days: 7, expectedProfileID: profile.id)
        #expect(progress.daily.workoutCount == 1 && progress.daily.estimatedBurnKcal == 200)
        #expect(progress.workouts.map(\.id) == [done.id] && progress.workoutTotal == 1)
        #expect(try await store.diaryWeek(from: "2027-03-10", through: "2027-03-10", expectedProfileID: profile.id).days.first?.workoutCount == 1)
        await #expect(throws: DiaryError.notFound) { try await store.coachWorkout(id: active.id, expectedProfileID: profile.id) }
        #expect(try await store.finishedWorkouts(containing: ExerciseKey(bench), limit: 10, expectedProfileID: profile.id).isEmpty)
    }

    @Test func finishComputesDurationAndBurn() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await store.recordWeight(value: 80, at: start.addingTimeInterval(-86_400), expectedProfileID: profile.id)
        _ = try await store.setWeight(dayLocalDate: "2027-03-11", value: 95, unit: "kg", measuredAt: nil, expectedRevision: nil, expectedProfileID: profile.id)
        let active = try await store.startWorkout(gym(true, true), at: start, expectedProfileID: profile.id)
        let finished = try await store.finishWorkout(id: active.id, effort: 5, at: start.addingTimeInterval(52 * 60), expectedRevision: active.revision, expectedProfileID: profile.id)
        #expect(finished.state == .finished && finished.durationSeconds == 3_120 && finished.durationMinutes == 52)
        // Strength at moderate effort: (3.5 − 1) × 80 kg × 52/60 h.
        #expect(finished.estimatedBurnKcal == 173 && finished.burnSource == nil && finished.effort == 5)
        #expect(try await store.activeWorkout(expectedProfileID: profile.id) == nil)
        #expect(try await store.finishedWorkouts(containing: ExerciseKey(bench), limit: 10, expectedProfileID: profile.id) == [finished])
    }

    @Test func finishDropsUntickedSets() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var draft = gym(true, false, nil)
        draft.exercises.append(WorkoutExercise(name: "Squat", sets: [WorkoutSet(repetitions: 5, loadKg: 100, done: false)]))
        let active = try await store.startWorkout(draft, at: start, expectedProfileID: profile.id)
        let finished = try await store.finishWorkout(id: active.id, effort: nil, at: start.addingTimeInterval(1_800), expectedRevision: active.revision, expectedProfileID: profile.id)
        #expect(finished.exercises.map(\.name) == ["Bench Press"] && finished.exercises[0].sets.map(\.done) == [true])
    }

    @Test func finishEmptyThrows() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let active = try await store.startWorkout(gym(false, nil), at: start, expectedProfileID: profile.id)
        await #expect(throws: DiaryError.invalidData) {
            try await store.finishWorkout(id: active.id, effort: nil, at: start.addingTimeInterval(600), expectedRevision: active.revision, expectedProfileID: profile.id)
        }
        #expect(try await store.activeWorkout(expectedProfileID: profile.id) == active)
    }

    @Test func staleActiveFlag() async throws {
        let touched = start.addingTimeInterval(3_600)
        let (store, profile, root) = try await fixture(now: touched); defer { try? FileManager.default.removeItem(at: root) }
        var active = try await store.startWorkout(gym(), at: start, expectedProfileID: profile.id)
        #expect(!active.isStale(now: start.addingTimeInterval(12 * 3_600 - 1)))
        #expect(active.isStale(now: start.addingTimeInterval(12 * 3_600)))
        active = try await store.saveActive(active, expectedRevision: active.revision, expectedProfileID: profile.id)
        #expect(active.updatedAt == touched)
        #expect(!active.isStale(now: start.addingTimeInterval(12 * 3_600)))
        #expect(active.isStale(now: touched.addingTimeInterval(12 * 3_600)))
    }

    @Test func finishedWorkoutsNewestFirstAndBounded() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var own = bench; own.exerciseID = nil; own.name = "My Press"; own.sets = [WorkoutSet(repetitions: 8, loadKg: 40)]
        var saved: [WorkoutSession] = []
        for (day, exercise) in [("2027-03-07", bench), ("2027-03-08", own), ("2027-03-09", bench), ("2027-03-10", bench)] {
            var exercise = exercise; if exercise.sets.isEmpty { exercise.sets = [WorkoutSet(repetitions: 8, loadKg: 60)] }
            saved.append(try await store.createWorkout(localDate: day, draft: WorkoutDraft(kind: .strength, durationMinutes: 40, exercises: [exercise]), performedAt: nil, expectedProfileID: profile.id))
        }
        #expect(try await store.finishedWorkouts(containing: ExerciseKey(bench), limit: 2, expectedProfileID: profile.id) == [saved[3], saved[2]])
        #expect(try await store.finishedWorkouts(containing: ExerciseKey(WorkoutExercise(name: "my press", sets: [])), limit: 5, expectedProfileID: profile.id) == [saved[1]])
    }
}
