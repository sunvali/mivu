import Foundation
import Testing
@testable import Mivu

@MainActor @Suite struct LiveWorkoutModelTests {
    private let start = ISO8601DateFormatter().date(from: "2027-03-10T10:00:00+02:00")!
    private let bench = WorkoutExercise(name: "Barbell Bench Press", sets: [], exerciseID: "barbell-bench-press", measure: .weightReps)

    private func fixture() async throws -> (DiaryStore, DiaryProfile, URL) {
        let root = URL.temporaryDirectory.appending(path: "LiveWorkout-" + UUID().uuidString)
        let profile = DiaryProfile(name: "Synthetic lifter", timeZoneID: "Asia/Jerusalem")
        let store = DiaryStore(directory: root)
        _ = try await store.createProfile(profile)
        return (store, profile, root)
    }

    private func benchWith(_ sets: WorkoutSet...) -> WorkoutExercise { var exercise = bench; exercise.sets = sets; return exercise }

    private func live(_ store: DiaryStore, _ profile: DiaryProfile, _ exercises: WorkoutExercise...) async throws -> LiveWorkoutModel {
        let session = try await store.startWorkout(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: exercises, activity: "strength"),
                                                   at: start, expectedProfileID: profile.id)
        return LiveWorkoutModel(store: store, profileID: profile.id, session: session, unit: "kg", mode: .live)
    }

    private func finished(_ store: DiaryStore, _ profile: DiaryProfile, on date: String, _ exercise: WorkoutExercise) async throws {
        _ = try await store.createWorkout(localDate: date, draft: WorkoutDraft(kind: .strength, durationMinutes: 40, exercises: [exercise]),
                                          performedAt: nil, expectedProfileID: profile.id)
    }

    @Test func newSetCopiesRowAbove() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let model = try await live(store, profile, benchWith(WorkoutSet(repetitions: 8, loadKg: 62.5, done: true)))
        await model.addSet(exercise: 0)
        #expect(model.session.exercises[0].sets == [WorkoutSet(repetitions: 8, loadKg: 62.5, done: true), WorkoutSet(repetitions: 8, loadKg: 62.5, done: false)])
        #expect(try await store.activeWorkout(expectedProfileID: profile.id) == model.session)
    }

    @Test func newExercisePrefillsLastTime() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await finished(store, profile, on: "2027-03-08", benchWith(WorkoutSet(repetitions: 8, loadKg: 60), WorkoutSet(repetitions: 6, loadKg: 62.5)))
        let model = try await live(store, profile)
        await model.addExercise(bench)
        #expect(model.session.exercises[0].sets == [WorkoutSet(repetitions: 8, loadKg: 60, done: false), WorkoutSet(repetitions: 6, loadKg: 62.5, done: false)])
        #expect(model.lastTime(exercise: 0, set: 1)?.loadKg == 62.5)
        #expect(model.expandedExercise == 0)

        // No history: one set to start from.
        await model.addExercise(WorkoutExercise(name: "My Row", sets: [], measure: .weightReps))
        #expect(model.session.exercises[1].sets.count == 1 && model.expandedExercise == 1)
        #expect(model.lastTime(exercise: 1, set: 0) == nil)
    }

    @Test func tickPersistsBeforeState() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let model = try await live(store, profile, benchWith(WorkoutSet(repetitions: 8, loadKg: 60, done: false)))
        await model.tick(exercise: 0, set: 0)
        #expect(model.session.exercises[0].sets[0].done == true)

        let reopened = DiaryStore(directory: root)
        _ = try await reopened.selectProfile(profile.id)
        let restored = try #require(try await reopened.activeWorkout(expectedProfileID: profile.id))
        #expect(restored.exercises[0].sets[0].done == true && restored == model.session)
    }

    @Test func savedTickStartsRest() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSinceReferenceDate: 820_000_000)
        let rest = RestTimer(center: FakeNotificationCenter(), defaults: UserDefaults(suiteName: "Rest-" + UUID().uuidString)!, now: { now })
        var lift = benchWith(WorkoutSet(repetitions: 8, loadKg: 60, done: false), WorkoutSet(repetitions: 8, loadKg: 60, done: false))
        lift.restSeconds = 120
        let started = try await live(store, profile, lift)
        let model = LiveWorkoutModel(store: store, profileID: profile.id, session: started.session, unit: "kg", mode: .live, rest: rest)
        await model.tick(exercise: 0, set: 0)
        #expect(rest.endsAt == now.addingTimeInterval(120), "the exercise's own rest wins over the default")
        #expect(rest.next == "Barbell Bench Press · set 2")

        rest.skip()
        // Another profile selected underneath: the tick fails to save, so no rest starts.
        let other = DiaryProfile(name: "Synthetic other", timeZoneID: "Asia/Jerusalem")
        _ = try await store.createProfile(other); _ = try await store.selectProfile(other.id)
        await model.tick(exercise: 0, set: 1)
        #expect(model.saveError != nil && rest.endsAt == nil)
    }

    @Test func tickMarksNewBest() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await finished(store, profile, on: "2027-03-08", benchWith(WorkoutSet(repetitions: 8, loadKg: 60)))
        let model = try await live(store, profile, benchWith(WorkoutSet(repetitions: 8, loadKg: 60, done: false), WorkoutSet(repetitions: 8, loadKg: 62.5, done: false)))
        await model.load()
        await model.tick(exercise: 0, set: 0)
        #expect(model.newBests.isEmpty)
        await model.tick(exercise: 0, set: 1)
        #expect(model.newBests == [0])
        await model.tick(exercise: 0, set: 1)
        #expect(model.newBests.isEmpty, "un-ticking removes the best")
    }

    @Test func failedSaveKeepsValues() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let model = try await live(store, profile, benchWith(WorkoutSet(repetitions: 8, loadKg: 60, done: false)))
        // Removed behind the screen's back, so the next save fails.
        try await store.discardWorkout(id: model.session.id, expectedRevision: model.session.revision, expectedProfileID: profile.id)
        await model.update(exercise: 0, set: 0, kg: 70, reps: 6, seconds: nil)
        #expect(model.session.exercises[0].sets[0].loadKg == 70 && model.session.exercises[0].sets[0].repetitions == 6)
        #expect(model.saveError != nil)
    }

    @Test func failedTickIsNotShownDoneAndDoneSavesIt() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await finished(store, profile, on: "2027-03-08", benchWith(WorkoutSet(repetitions: 8, loadKg: 60)))
        let model = try await live(store, profile, benchWith(WorkoutSet(repetitions: 8, loadKg: 70, done: false)))
        await model.load()
        // Another profile selected underneath: saves fail until it is selected again.
        let other = DiaryProfile(name: "Synthetic other", timeZoneID: "Asia/Jerusalem")
        _ = try await store.createProfile(other); _ = try await store.selectProfile(other.id)
        await model.tick(exercise: 0, set: 0)
        #expect(model.saveError != nil)
        #expect(!model.isTicked(exercise: 0, set: 0) && model.newBests.isEmpty, "an unsaved tick is not shown done or as a best")

        _ = try await store.selectProfile(profile.id)
        #expect(await model.finish(at: start.addingTimeInterval(900)))
        let saved = try #require(try await store.workoutHistory(expectedProfileID: profile.id).values.first { $0.id == model.session.id })
        #expect(saved.exercises[0].sets == [WorkoutSet(repetitions: 8, loadKg: 70, done: true)])
    }

    @Test func newLiftsStartSensibly() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let model = try await live(store, profile)
        await model.addExercise(bench)
        #expect(model.session.exercises[0].sets[0].loadKg == 20, "a barbell starts at the bar")
        await model.addExercise(WorkoutExercise(name: "Dumbbell Curl", sets: [], exerciseID: "dumbbell-curl", measure: .weightReps))
        #expect(model.session.exercises[1].sets[0].loadKg == nil && model.needsWeight(exercise: 1, set: 0))
        #expect(!model.needsWeight(exercise: 0, set: 0))
        #expect(model.startingWeight(exercise: 0) == 20 && model.startingWeight(exercise: 1) == 10)

        let pounds = LiveWorkoutModel(store: store, profileID: profile.id, session: model.session, unit: "lb", mode: .live)
        await pounds.addExercise(WorkoutExercise(name: "Barbell Row", sets: [], exerciseID: "barbell-row", measure: .weightReps))
        #expect(WeightStep.display(kg: pounds.session.exercises[2].sets[0].loadKg!, unit: "lb") == 45)
        #expect(pounds.startingWeight(exercise: 1) == 20)
    }

    @Test func startChangedOverFiveMinutesIsPast() {
        #expect(LiveWorkoutModel.mode(start: nil, now: start) == .live)
        #expect(LiveWorkoutModel.mode(start: start.addingTimeInterval(-240), now: start) == .live)
        #expect(LiveWorkoutModel.mode(start: start.addingTimeInterval(-360), now: start) == .past)
    }

    @Test func pastSavesFinishedOnDone() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let yesterday = start.addingTimeInterval(-86_400)
        let draft = WorkoutSession(dayID: UUID(), performedAt: yesterday, timePrecision: .exact, revision: 1, kind: .strength, durationMinutes: 0, exercises: [])
        let model = LiveWorkoutModel(store: store, profileID: profile.id, session: draft, unit: "kg", mode: .past)
        await model.addExercise(bench)
        await model.addSet(exercise: 0)
        await model.tick(exercise: 0, set: 0)
        #expect(try await store.workoutHistory(expectedProfileID: profile.id).values.isEmpty, "nothing is stored before Done")

        #expect(await model.finish())
        let saved = try #require(try await store.workoutHistory(expectedProfileID: profile.id).values.first)
        #expect(saved.isFinished && saved.performedAt == yesterday && saved.exercises[0].sets.count == 1 && saved.source == .manual)
        #expect(try await store.activeWorkout(expectedProfileID: profile.id) == nil)
    }

    @Test func finishedExercisesBecomeRecent() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try await live(store, profile, benchWith(WorkoutSet(repetitions: 8, loadKg: 60, done: false)))
        await first.tick(exercise: 0, set: 0)
        #expect(await first.finish(at: start.addingTimeInterval(600)))
        let next = try await live(store, profile)
        await next.load()
        #expect(next.recent == [bench])
    }

    @Test func rowCountsTickedSets() {
        var session = WorkoutSession(dayID: UUID(), performedAt: start, timePrecision: .exact, revision: 1, kind: .strength, durationMinutes: 40, exercises: [])
        session.exercises = [benchWith(WorkoutSet(repetitions: 8, done: true), WorkoutSet(repetitions: 8, done: false), WorkoutSet(repetitions: 8))]
        #expect(WorkoutRow.detail(session) == "40 min · 2 sets", "an unticked set does not count; an older set without a tick does")
    }

    @Test func lbRoundTrip() throws {
        for shown in [135.0, 132.5, 225, 2.5] {
            let kg = WeightStep.kg(fromDisplay: shown, unit: "lb")
            let stored = try JSONDecoder().decode(WorkoutSet.self, from: JSONEncoder().encode(WorkoutSet(repetitions: 5, loadKg: kg)))
            #expect(WeightStep.display(kg: stored.loadKg!, unit: "lb") == shown)
        }
        #expect(WeightStep.display(kg: 62.5, unit: "kg") == 62.5 && WeightStep.kg(fromDisplay: 62.5, unit: "kg") == 62.5)
    }

    @Test func stepFollowsPlates() {
        // Two of the smallest plate, one per side.
        #expect(WeightStep.step(unit: "kg", plates: WeightStep.defaultPlatesKg) == 2.5)
        #expect(WeightStep.step(unit: "lb", plates: WeightStep.defaultPlatesLb) == 5)
        #expect(WeightStep.step(unit: "kg", plates: [20, 10, 5, 2.5, 0.5]) == 1)
        #expect(WeightStep.step(unit: "lb", plates: [45, 25, 10, 5]) == 10)
    }
}
