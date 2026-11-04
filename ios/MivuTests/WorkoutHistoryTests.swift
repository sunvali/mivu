import Foundation
import Testing
@testable import Mivu

struct WorkoutHistoryTests {
    private func set(_ kg: Double?, _ reps: Int, _ type: WorkoutSetType? = nil, seconds: Int? = nil, done: Bool? = true) -> WorkoutSet {
        WorkoutSet(repetitions: reps, loadKg: kg, type: type, seconds: seconds, done: done)
    }

    private func session(_ name: String = "Bench Press", id: String? = "bench-press", sets: [WorkoutSet], state: WorkoutState? = nil) -> WorkoutSession {
        WorkoutSession(dayID: UUID(), performedAt: Date(), timePrecision: .exact, revision: 1, kind: .strength, durationMinutes: 30,
                       exercises: [WorkoutExercise(name: name, sets: sets, exerciseID: id)], state: state)
    }

    private let bench = ExerciseKey(WorkoutExercise(name: "Bench Press", sets: [], exerciseID: "bench-press"))

    @Test func keys() {
        #expect(bench.raw == "bench-press")
        #expect(ExerciseKey(WorkoutExercise(name: "Pull-Ups", sets: [])) == ExerciseKey(WorkoutExercise(name: "pull up", sets: [])))
        #expect(ExerciseKey(WorkoutExercise(name: "Pull-Ups", sets: [])).raw == "own:pullup")
    }

    @Test func lastTimeSamePosition() {
        let past = [session(sets: [set(60, 8), set(60, 8), set(60, 7)])]
        #expect(WorkoutHistory.lastTime(for: bench, position: 3, type: .normal, in: past) == set(60, 7))
        #expect(WorkoutHistory.lastTime(for: bench, position: 4, type: .normal, in: past) == set(60, 7))
    }

    @Test func warmupsMatchWarmups() {
        let past = [session(sets: [set(40, 10, .warmup), set(60, 8), set(60, 8)])]
        #expect(WorkoutHistory.lastTime(for: bench, position: 1, type: .warmup, in: past) == set(40, 10, .warmup))
        #expect(WorkoutHistory.lastTime(for: bench, position: 1, type: .normal, in: past) == set(60, 8))
    }

    @Test func lastTimeUsesNewestFinishedSessionWithTheExercise() {
        let past = [session(sets: [set(99, 1)], state: .active), session("Squat", id: "squat", sets: [set(100, 5)]),
                    session(sets: [set(60, 8)]), session(sets: [set(50, 8)])]
        #expect(WorkoutHistory.lastTime(for: bench, position: 1, type: .normal, in: past) == set(60, 8))
        #expect(WorkoutHistory.lastTime(for: bench, position: 1, type: .warmup, in: past) == nil)
    }

    @Test func newBestHeavier() {
        let before = [set(60, 8)]
        #expect(WorkoutHistory.isNewBest(set(62.5, 1), measure: .weightReps, before: before))
        #expect(!WorkoutHistory.isNewBest(set(60, 8), measure: .weightReps, before: before))
    }

    @Test func newBestMoreRepsAtOrAboveWeight() {
        let before = [set(60, 8), set(70, 3)]
        #expect(WorkoutHistory.isNewBest(set(65, 4), measure: .weightReps, before: before))
        #expect(!WorkoutHistory.isNewBest(set(60, 8), measure: .weightReps, before: before))
        #expect(WorkoutHistory.isNewBest(set(55, 9), measure: .weightReps, before: before))
    }

    @Test func firstSessionSilent() {
        #expect(!WorkoutHistory.isNewBest(set(60, 8), measure: .weightReps, before: []))
        #expect(!WorkoutHistory.isNewBest(set(60, 8), measure: .weightReps, before: [set(100, 5, .warmup)]))
    }

    @Test func warmupsIgnored() {
        #expect(!WorkoutHistory.isNewBest(set(100, 5, .warmup), measure: .weightReps, before: [set(60, 8)]))
        #expect(WorkoutHistory.isNewBest(set(62.5, 1), measure: .weightReps, before: [set(100, 5, .warmup), set(60, 8)]))
    }

    @Test func dropAndFailureCountLikeNormal() {
        #expect(WorkoutHistory.isNewBest(set(62.5, 1, .drop), measure: .weightReps, before: [set(60, 8)]))
        #expect(!WorkoutHistory.isNewBest(set(60, 8), measure: .weightReps, before: [set(70, 3, .failure), set(60, 8, .drop)]))
        #expect(WorkoutHistory.isNewBest(set(72, 1), measure: .weightReps, before: [set(70, 3, .failure)]))
    }

    @Test func untickedSetsDoNotRaiseTheBar() {
        let before = [set(60, 8), set(80, 5, done: false)]
        #expect(WorkoutHistory.isNewBest(set(62.5, 1), measure: .weightReps, before: before))
        #expect(!WorkoutHistory.isNewBest(set(62.5, 1), measure: .weightReps, before: [set(80, 5, done: false)]))
    }

    @Test func moreRepsAtTheHeaviestWeightIsBest() {
        #expect(WorkoutHistory.isNewBest(set(60, 9), measure: .weightReps, before: [set(60, 8)]))
    }

    @Test func distanceTimeHasNoBest() {
        #expect(!WorkoutHistory.isNewBest(set(nil, 0, seconds: 99), measure: .distanceTime, before: [set(nil, 0, seconds: 1)]))
    }

    @Test func bodyweightMostReps() {
        #expect(WorkoutHistory.isNewBest(set(nil, 11), measure: .reps, before: [set(nil, 10)]))
        #expect(!WorkoutHistory.isNewBest(set(nil, 10), measure: .reps, before: [set(nil, 10)]))
    }

    @Test func timeLongest() {
        #expect(WorkoutHistory.isNewBest(set(nil, 0, seconds: 61), measure: .time, before: [set(nil, 0, seconds: 60)]))
        #expect(!WorkoutHistory.isNewBest(set(nil, 0, seconds: 60), measure: .time, before: [set(nil, 0, seconds: 60)]))
    }

    @Test func bestsSkipWarmupsAndUntickedSets() {
        let past = [session(sets: [set(100, 5, .warmup), set(60, 8), set(90, 1, done: false)]),
                    session("Squat", id: "squat", sets: [set(200, 5)]), session(sets: [set(62.5, 6), set(nil, 0, seconds: 45)])]
        #expect(WorkoutHistory.bests(for: bench, in: past) == ExerciseBests(heaviestKg: 62.5, mostReps: 8, longestSeconds: 45))
        #expect(WorkoutHistory.bests(for: bench, in: []) == ExerciseBests())
    }
}
