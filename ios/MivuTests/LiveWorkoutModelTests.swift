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

    @Test func summaryCounts() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await finished(store, profile, on: "2027-03-08", benchWith(WorkoutSet(repetitions: 8, loadKg: 60)))
        _ = try await store.setWeight(dayLocalDate: "2027-03-10", value: 80, unit: "kg", measuredAt: nil, expectedRevision: nil, expectedProfileID: profile.id)
        let model = try await live(store, profile, benchWith(WorkoutSet(repetitions: 8, loadKg: 62.5, done: false), WorkoutSet(repetitions: 8, loadKg: 60, done: false),
                                                            WorkoutSet(repetitions: 8, loadKg: 60, done: false)))
        await model.load()
        await model.tick(exercise: 0, set: 0)
        await model.tick(exercise: 0, set: 1)
        model.endedAt = start.addingTimeInterval(45 * 60)
        model.effort = 7
        let summary = model.summary
        #expect(summary.sets == 2 && summary.newBests == 1)
        #expect(summary.kcal == WorkoutBurn.estimate(activity: "strength", seconds: 45 * 60, distanceMeters: nil, effort: 7, bodyKg: 80))

        #expect(await model.finish(at: model.endedAt))
        let saved = try #require(try await store.workoutHistory(expectedProfileID: profile.id).values.first { $0.id == model.session.id })
        #expect(saved.effort == 7 && saved.estimatedBurnKcal == summary.kcal, "Save stores what the Done screen showed")
    }

    @Test func feelPrefillFromSetEfforts() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var session = WorkoutSession(dayID: UUID(), performedAt: start, timePrecision: .exact, revision: 1, kind: .strength, durationMinutes: 0, exercises: [])
        // Ticked efforts average 7.4; an unticked set's effort does not count.
        let sets: [WorkoutSet] = [7, 8, 7, 8, 7].map { WorkoutSet(repetitions: 8, effort: $0, done: true) }
        session.exercises = [WorkoutExercise(name: "Row", sets: sets + [WorkoutSet(repetitions: 8, effort: 3, done: false)])]
        let model = LiveWorkoutModel(store: store, profileID: profile.id, session: session, unit: "kg", mode: .past)
        #expect(model.feel == 7)
        #expect(EffortChips.efforts.first { $0.1 == model.feel }?.0 == "Hard")
        session.exercises[0].sets = [WorkoutSet(repetitions: 8, done: true)]
        #expect(LiveWorkoutModel(store: store, profileID: profile.id, session: session, unit: "kg", mode: .past).feel == nil, "no efforts, nothing chosen")
    }

    @Test func routineFromSession() {
        var session = WorkoutSession(dayID: UUID(), performedAt: start, timePrecision: .exact, revision: 1, kind: .strength, durationMinutes: 40, exercises: [])
        session.exercises = [benchWith(WorkoutSet(repetitions: 8, loadKg: 60, effort: 8, done: true), WorkoutSet(repetitions: 8, loadKg: 60, done: false)),
                             WorkoutExercise(name: "Squat", sets: [WorkoutSet(repetitions: 5, loadKg: 100, done: false)])]
        let routine = WorkoutRoutine(from: session, name: "Push day")
        #expect(routine.name == "Push day" && routine.lastUsedAt == start)
        #expect(routine.exercises == [benchWith(WorkoutSet(repetitions: 8, loadKg: 60))], "targets are the ticked sets, with done and effort cleared")
    }

    @Test func routineChangedDetectsAddedExercise() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let routine = try await store.saveRoutine(WorkoutRoutine(name: "Push day", exercises: [benchWith(WorkoutSet(repetitions: 8, loadKg: 60))]),
                                                  expectedRevision: nil, expectedProfileID: profile.id)
        let session = try await store.startWorkout(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: routine.exercises, title: routine.name,
                                                                activity: "strength", routineID: routine.id), at: start, expectedProfileID: profile.id)
        let model = LiveWorkoutModel(store: store, profileID: profile.id, session: session, unit: "kg", mode: .live)
        await model.load()
        #expect(model.routine?.id == routine.id)
        await model.tick(exercise: 0, set: 0)
        #expect(!model.routineChanged, "heavier or lighter sets alone are not a change")
        await model.addExercise(WorkoutExercise(name: "Dumbbell Curl", sets: [WorkoutSet(repetitions: 10, loadKg: 12, done: false)], exerciseID: "dumbbell-curl"))
        await model.tick(exercise: 1, set: 0)
        #expect(model.routineChanged)

        #expect(await model.finish(at: start.addingTimeInterval(1_800)))
        #expect(await model.updateRoutine())
        let updated = try #require(try await store.routines(expectedProfileID: profile.id).first)
        #expect(updated.id == routine.id && updated.name == "Push day" && updated.exercises.map(\.name) == ["Barbell Bench Press", "Dumbbell Curl"])
    }

    @Test func doneSavesNewRoutine() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let model = try await live(store, profile, benchWith(WorkoutSet(repetitions: 8, loadKg: 60, done: false)))
        await model.load()
        #expect(model.routine == nil && !model.routineChanged)
        await model.tick(exercise: 0, set: 0)
        #expect(await model.finish(at: start.addingTimeInterval(1_800)))
        #expect(await model.saveRoutine(name: "  Push day "))
        let saved = try await store.routines(expectedProfileID: profile.id)
        #expect(saved.map(\.name) == ["Push day"] && saved[0].exercises == [benchWith(WorkoutSet(repetitions: 8, loadKg: 60))])
    }

    @Test func startingRoutineSetsLastUsed() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let routine = try await store.saveRoutine(WorkoutRoutine(name: "Push day", exercises: [benchWith(WorkoutSet(repetitions: 8, loadKg: 60))]),
                                                  expectedRevision: nil, expectedProfileID: profile.id)
        let session = try await store.startWorkout(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: routine.exercises, title: routine.name,
                                                                activity: "strength", routineID: routine.id), at: start, expectedProfileID: profile.id)
        #expect(session.routineID == routine.id && session.exercises == routine.exercises)
        #expect(try await store.routines(expectedProfileID: profile.id).first?.lastUsedAt == start)

        // Logged afterwards for an earlier time: the routine keeps its latest use.
        var past = WorkoutSession(dayID: UUID(), performedAt: start.addingTimeInterval(-86_400), timePrecision: .exact, revision: 1, kind: .strength, durationMinutes: 0, exercises: [])
        past.apply(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: [benchWith(WorkoutSet(repetitions: 8, loadKg: 60, done: true))], routineID: routine.id))
        let model = LiveWorkoutModel(store: store, profileID: profile.id, session: past, unit: "kg", mode: .past)
        #expect(await model.finish())
        #expect(try await store.routines(expectedProfileID: profile.id).first?.lastUsedAt == start)
    }

    @Test func pastAfterMidnightCountsForWakingDay() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let late = ISO8601DateFormatter().date(from: "2027-03-10T01:30:00+02:00")!
        var past = WorkoutSession(dayID: UUID(), performedAt: late, timePrecision: .exact, revision: 1, kind: .strength, durationMinutes: 0, exercises: [])
        past.exercises = [benchWith(WorkoutSet(repetitions: 8, loadKg: 60, done: true), WorkoutSet(repetitions: 8, loadKg: 60, done: true))]
        let model = LiveWorkoutModel(store: store, profileID: profile.id, session: past, unit: "kg", mode: .past)
        #expect(model.summary.sets == 2 && model.pastMinutes == 6, "three minutes a set until corrected")
        model.pastMinutes = 50
        #expect(await model.finish())
        let saved = try #require(try await store.workoutHistory(expectedProfileID: profile.id).values.first)
        #expect(try await store.trackingDay(id: saved.dayID, expectedProfileID: profile.id).localDate == "2027-03-09")
        #expect(saved.durationSeconds == 3_000 && saved.performedAt == late)
    }

    private func restModel(_ store: DiaryStore, _ profile: DiaryProfile, _ exercises: WorkoutExercise...) async throws -> (LiveWorkoutModel, RestTimer) {
        let rest = RestTimer(center: FakeNotificationCenter(), defaults: UserDefaults(suiteName: "Rest-" + UUID().uuidString)!, now: { Date(timeIntervalSinceReferenceDate: 820_000_000) })
        let session = try await store.startWorkout(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: exercises, activity: "strength"),
                                                   at: start, expectedProfileID: profile.id)
        return (LiveWorkoutModel(store: store, profileID: profile.id, session: session, unit: "kg", mode: .live, rest: rest), rest)
    }

    private func lift(_ name: String, sets: Int) -> WorkoutExercise {
        WorkoutExercise(name: name, sets: Array(repeating: WorkoutSet(repetitions: 10, loadKg: 40, done: false), count: sets), measure: .weightReps)
    }

    @Test func supersetFocusOrder() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let (model, rest) = try await restModel(store, profile, lift("Row", sets: 2), lift("Curl", sets: 1), lift("Face pull", sets: 2))
        await model.group([0, 2])
        // Grouping brings the partner next to the first exercise and is saved.
        #expect(model.session.exercises.map(\.name) == ["Row", "Face pull", "Curl"])
        #expect(model.session.exercises[0].groupID != nil && model.session.exercises[0].groupID == model.session.exercises[1].groupID)
        #expect(model.session.exercises[2].groupID == nil)
        #expect(try await store.activeWorkout(expectedProfileID: profile.id) == model.session)

        #expect(model.nextFocus(after: (0, 0)) == (1, 0))
        await model.tick(exercise: 0, set: 0)
        #expect(model.focus.map { [$0.exercise, $0.set] } == [1, 0], "A1 → B1")
        #expect(rest.endsAt == nil, "no rest between the exercises of a round")
        await model.tick(exercise: 1, set: 0)
        #expect(model.focus.map { [$0.exercise, $0.set] } == [0, 1], "B1 → A2")
        #expect(rest.endsAt != nil, "rest after the round")
        #expect(model.nextFocus(after: (0, 1)) == (1, 1))
        // After the last round, focus moves on to the next exercise.
        #expect(model.nextFocus(after: (1, 1)) == (2, 0))
    }

    @Test func restOnlyAfterRound() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let (model, rest) = try await restModel(store, profile, lift("Squat", sets: 2), lift("Row", sets: 2), lift("Dip", sets: 2), lift("Plank", sets: 1))
        await model.group([1, 2])
        await model.group([1, 0])
        #expect(model.session.exercises.map(\.name) == ["Squat", "Row", "Dip", "Plank"], "three exercises make one circuit")
        #expect(Set(model.session.exercises.prefix(3).map(\.groupID)).count == 1)
        // Out of order: B before A still waits for the rest of the round.
        await model.tick(exercise: 1, set: 0)
        await model.tick(exercise: 0, set: 0)
        #expect(rest.endsAt == nil)
        await model.tick(exercise: 2, set: 0)
        #expect(rest.endsAt != nil)
        rest.skip()
        // An exercise on its own rests after every set.
        await model.tick(exercise: 3, set: 0)
        #expect(rest.endsAt != nil)
    }

    @Test func groupingFromTheMiddleKeepsSupersetsWhole() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let (model, _) = try await restModel(store, profile, lift("A", sets: 1), lift("B", sets: 1), lift("C", sets: 1), lift("D", sets: 1), lift("E", sets: 1), lift("F", sets: 1))
        await model.group([0, 1]); await model.group([0, 2]); await model.group([0, 3]); await model.group([0, 4])
        // From F, superset with C, the middle of the A–E circuit: A B | C F | D E, three separate supersets.
        await model.group([5, 2])
        let groups = model.session.exercises.map(\.groupID)
        #expect(model.session.exercises.map(\.name) == ["A", "B", "C", "F", "D", "E"])
        #expect(groups.allSatisfy { $0 != nil } && groups[0] == groups[1] && groups[2] == groups[3] && groups[4] == groups[5])
        #expect(Set(groups).count == 3)
        #expect(WorkoutSession.block(of: 4, in: model.session.exercises) == 4..<6)
        #expect(try await store.activeWorkout(expectedProfileID: profile.id) == model.session)

        // A circuit X Y Z with W after it: taking Y out leaves X and Z alone, not one group in two places.
        #expect(await model.discard(), "one running workout per profile")
        let (other, _) = try await restModel(store, profile, lift("V", sets: 1), lift("X", sets: 1), lift("Y", sets: 1), lift("Z", sets: 1), lift("U", sets: 1), lift("W", sets: 1))
        await other.group([1, 2]); await other.group([1, 3])
        await other.group([5, 2])
        #expect(other.session.exercises.map(\.name) == ["V", "X", "Y", "W", "Z", "U"])
        #expect(other.session.exercises.map { $0.groupID != nil } == [false, false, true, true, false, false])
    }

    @Test func unevenSupersetRounds() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let (model, rest) = try await restModel(store, profile, lift("Row", sets: 3), lift("Fly", sets: 2))
        await model.group([0, 1])
        #expect(model.round(of: 0..<2) == (1, 3))
        await model.tick(exercise: 0, set: 0)
        #expect(rest.endsAt == nil && model.focus.map { [$0.exercise, $0.set] } == [1, 0])
        #expect(model.session.nextSetLabel == "Fly · set 1", "the banner names the next set in lifting order too")
        await model.tick(exercise: 1, set: 0)
        #expect(rest.endsAt != nil && rest.next == "Row · set 2", "the rest names the next set in lifting order")
        rest.skip()
        await model.tick(exercise: 0, set: 1)
        await model.tick(exercise: 1, set: 1)
        #expect(rest.next == "Row · set 3" && model.round(of: 0..<2) == (3, 3))
        rest.skip()
        // The third round has only Row, so it rests after it.
        await model.tick(exercise: 0, set: 2)
        #expect(rest.endsAt != nil)
    }

    @Test func removingFromASuperset() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let (model, _) = try await restModel(store, profile, lift("A", sets: 1), lift("B", sets: 1), lift("C", sets: 1), lift("D", sets: 1))
        await model.group([0, 1]); await model.group([0, 2])
        model.expandedExercise = 3
        await model.removeExercise(1)
        #expect(model.session.exercises.map(\.name) == ["A", "C", "D"] && model.expandedExercise == 2, "the open card stays on D")
        #expect(model.session.exercises[0].groupID != nil && model.session.exercises[0].groupID == model.session.exercises[1].groupID)
        await model.removeExercise(0)
        #expect(model.session.exercises.allSatisfy { $0.groupID == nil }, "one exercise left is no superset")
        #expect(model.expandedExercise == 1)
        #expect(try await store.activeWorkout(expectedProfileID: profile.id) == model.session)
    }

    @Test func exerciseMenuEdits() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let (model, _) = try await restModel(store, profile, lift("Row", sets: 2), lift("Curl", sets: 1), lift("Dip", sets: 1))
        await model.setType(.warmup, exercise: 0, set: 0)
        await model.setEffort(8, exercise: 0, set: 1)
        await model.setNote("Seat 4", exercise: 1)
        #expect(model.session.exercises[0].sets.map(\.type) == [.warmup, nil] && model.session.exercises[0].sets[1].effort == 8)
        await model.setType(.normal, exercise: 0, set: 0)
        await model.setEffort(nil, exercise: 0, set: 1)
        #expect(model.session.exercises[0].sets.map(\.type) == [nil, nil] && model.session.exercises[0].sets[1].effort == nil)

        // A shared rest for the whole superset.
        await model.group([0, 1])
        await model.setRest(60, exercise: 1)
        #expect(model.session.exercises.prefix(2).map(\.restSeconds) == [60, 60] && model.session.exercises[2].restSeconds == nil)
        // Moving down from the bottom of a superset leaves it; a lone member is no longer a superset.
        model.expandedExercise = 1
        await model.moveExercise(1, up: false)
        #expect(model.session.exercises.map(\.name) == ["Row", "Curl", "Dip"] && model.session.exercises.allSatisfy { $0.groupID == nil })
        #expect(model.expandedExercise == 1)
        await model.moveExercise(1, up: false)
        #expect(model.session.exercises.map(\.name) == ["Row", "Dip", "Curl"] && model.expandedExercise == 2)
        #expect(model.session.exercises[2].note == "Seat 4")
        // A single exercise jumps over a whole superset.
        await model.group([0, 1])
        await model.moveExercise(2, up: true)
        #expect(model.session.exercises.map(\.name) == ["Curl", "Row", "Dip"])
        // Leaving a superset puts the exercise after the others.
        await model.ungroup(exercise: 1)
        #expect(model.session.exercises.map(\.name) == ["Curl", "Dip", "Row"] && model.session.exercises.allSatisfy { $0.groupID == nil })

        await model.replaceExercise(0, with: WorkoutExercise(name: "Hammer curl", sets: [], measure: .weightReps))
        #expect(model.session.exercises[0].name == "Hammer curl" && model.session.exercises[0].sets.count == 1)
        await model.removeExercise(0)
        #expect(model.session.exercises.map(\.name) == ["Dip", "Row"])
        #expect(try await store.activeWorkout(expectedProfileID: profile.id) == model.session)
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
