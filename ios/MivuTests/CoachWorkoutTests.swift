import Foundation
import SQLite3
import Testing
@testable import Mivu

private actor WorkoutCoachReplies {
    private var replies: [CoachInferenceResult]
    private(set) var inputs: [[CoachInferenceInput]] = []
    init(_ replies: [CoachInferenceResult]) { self.replies = replies }
    func next(_ input: [CoachInferenceInput], _ tools: Data) throws -> CoachInferenceResult {
        inputs.append(input)
        guard !replies.isEmpty else { throw CoachError.limitExceeded }
        return replies.removeFirst()
    }
}

@Suite @MainActor struct CoachWorkoutTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture() async throws -> (DiaryStore, DiaryProfile, CoachTurn, URL) {
        let root = URL.temporaryDirectory.appending(path: "CoachWorkout-" + UUID().uuidString)
        let clock = now
        let store = DiaryStore(directory: root, currentTime: { clock }); let profile = DiaryProfile(name: "Synthetic lifter")
        _ = try await store.createProfile(profile); _ = try await store.startDay(at: now)
        let turn = try await capturedTurn(store, text: "Synthetic workout message", photos: [], at: now, expectedProfileID: profile.id)
        return (store, profile, turn, root)
    }
    private func call(_ name: String, _ args: String, id: String = "call1") -> CoachToolCall {
        CoachToolCall(id: id, callID: id, name: name, namespace: "mivu", arguments: args)
    }
    private func result(_ calls: [CoachToolCall] = [], text: String = "") -> CoachInferenceResult {
        CoachInferenceResult(model: "fixture", text: text, calls: calls, outputItems: [])
    }
    private func run(_ store: DiaryStore, _ profile: DiaryProfile, _ turn: CoachTurn, _ calls: [CoachToolCall]) async throws -> CoachTurnResult {
        let replies = WorkoutCoachReplies([result(calls), result(text: "Done")])
        return try await CoachEngine(store: store, infer: { try await replies.next($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
    }
    private func apply(_ store: DiaryStore, _ profile: DiaryProfile, _ turn: CoachTurn, _ call: CoachToolCall, workouts: [WorkoutSession] = []) async throws -> [CoachReceipt] {
        guard case .write(let write) = try CoachTools.parse(call, meals: [], evidence: [:], receipts: [], workouts: workouts) else { throw CoachError.invalidTool }
        return try await store.applyCoachWrites([write], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
    }

    @Test func sentenceLogsStrength() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        // "bench 3x8 at 62.5"
        let set = #"{"repetitions":8,"load_kg":62.5}"#
        let args = #"{"local_date":"2027-01-15","kind":"strength","duration_minutes":40,"exercises":[{"name":"Bench","sets":[\#(set),\#(set),\#(set)]}]}"#
        let completed = try await run(store, profile, turn, [call("log_workout", args)])
        let workout = try #require(try await store.snapshotForExport().workouts.first)
        #expect(workout.exercises.map(\.exerciseID) == ["barbell-bench-press"])
        #expect(workout.exercises[0].name == "Barbell Bench Press" && workout.exercises[0].sets.count == 3)
        #expect(workout.exercises[0].sets.allSatisfy { $0.repetitions == 8 && $0.loadKg == 62.5 })
        #expect(workout.activity == "strength" && workout.source == .coach)
        #expect(completed.receipts.first?.workoutID == workout.id)
    }

    @Test func unknownNameBecomesOwn() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let args = #"{"local_date":"2027-01-15","kind":"strength","duration_minutes":30,"exercises":[{"name":"Synthetic cable twist","sets":[{"repetitions":12,"load_kg":10}]}]}"#
        let completed = try await run(store, profile, turn, [call("log_workout", args)])
        let workout = try #require(try await store.snapshotForExport().workouts.first)
        #expect(workout.exercises[0].exerciseID == nil && workout.exercises[0].name == "Synthetic cable twist")
        let receipt = DiaryDatabase.coachCommittedReceipt(try #require(completed.receipts.first))
        #expect(receipt.workoutNewExercises == ["Synthetic cable twist"])
        #expect(CoachReceiptPresentation(receipt: receipt, target: .loading).committedStatus == "Workout saved")
    }

    @Test func supersetSentenceGroupsNeighbours() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        // "superset bench and rows 3x10"
        let sets = Array(repeating: #"{"repetitions":10,"load_kg":40}"#, count: 3).joined(separator: ",")
        let args = #"{"local_date":"2027-01-15","kind":"strength","duration_minutes":30,"exercises":[{"name":"Bench press","group":"a","sets":[\#(sets)]},{"name":"Barbell row","group":"a","sets":[\#(sets)]}]}"#
        _ = try await run(store, profile, turn, [call("log_workout", args)])
        let workout = try #require(try await store.snapshotForExport().workouts.first)
        #expect(workout.exercises[0].groupID != nil && workout.exercises[0].groupID == workout.exercises[1].groupID)
        // A split superset is refused rather than saved in pieces.
        let split = #"{"local_date":"2027-01-15","kind":"strength","duration_minutes":30,"exercises":[{"name":"Bench press","group":"a","sets":[]},{"name":"Squat","sets":[]},{"name":"Barbell row","group":"a","sets":[]}]}"#
        #expect(throws: CoachError.invalidArguments) { try CoachTools.parse(call("log_workout", split), meals: [], evidence: [:], receipts: []) }
    }

    private func storedGymSession(_ store: DiaryStore, _ profile: DiaryProfile) async throws -> WorkoutSession {
        let group = UUID()
        let bench = WorkoutExercise(name: "Barbell Bench Press", sets: [WorkoutSet(repetitions: 10, loadKg: 40, type: .warmup), WorkoutSet(repetitions: 8, loadKg: 60, effort: 8)],
                                    exerciseID: "barbell-bench-press", measure: .weightReps, groupID: group, restSeconds: 90, note: "Synthetic grip")
        let row = WorkoutExercise(name: "Barbell Row", sets: [WorkoutSet(repetitions: 8, loadKg: 50)], exerciseID: "barbell-row", measure: .weightReps, groupID: group)
        let rower = WorkoutExercise(name: "Rowing Machine", sets: [WorkoutSet(repetitions: 0, seconds: 300, distanceMeters: 1_000)], exerciseID: "rowing-machine", measure: .distanceTime)
        let draft = WorkoutDraft(kind: .strength, durationMinutes: 45, exercises: [bench, row, rower], title: "Push day", activity: "strength",
                                 distanceMeters: 1_000, effort: 5, note: "Synthetic session note")
        return try await store.createWorkout(localDate: "2027-01-15", draft: draft, performedAt: nil, expectedProfileID: profile.id)
    }

    @Test func editKeepsUntouchedFields() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try await storedGymSession(store, profile)
        let args = #"{"workout_id":"\#(original.id)","expected_revision":1,"kind":null,"duration_minutes":50,"exercises":null,"title":null,"note":null}"#
        _ = try await apply(store, profile, turn, call("edit_workout", args), workouts: [original])
        var expected = original; expected.durationMinutes = 50; expected.revision = 2
        #expect(try await store.snapshotForExport().workouts == [expected])
    }

    @Test func editReachesEveryManualField() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try await storedGymSession(store, profile)
        // Move a day back, change time, distance, effort and note, clear the title; reorder, ungroup,
        // retype and re-rate sets, change rest, clear a note and remove the rower.
        let exercises = #"[{"name":"Barbell Row","group":"","sets":[{"repetitions":8,"load_kg":52.5}]},{"name":"Bench press","rest_seconds":120,"note":"","sets":[{"repetitions":10,"load_kg":40,"type":"normal"},{"repetitions":8,"load_kg":60,"effort":9}]}]"#
        let args = #"{"workout_id":"\#(original.id)","expected_revision":1,"local_date":"2027-01-14","duration_seconds":3000,"distance_meters":500,"effort":7,"title":"","note":"Synthetic felt good","exercises":\#(exercises)}"#
        _ = try await apply(store, profile, turn, call("edit_workout", args), workouts: [original])
        let edited = try #require(try await store.snapshotForExport().workouts.first)
        let day = try await store.trackingDay(id: edited.dayID, expectedProfileID: profile.id)
        #expect(day.localDate == "2027-01-14" && edited.timePrecision == .dateOnly)
        #expect(edited.durationSeconds == 3000 && edited.durationMinutes == 50 && edited.distanceMeters == 500 && edited.effort == 7)
        #expect(edited.title == nil && edited.note == "Synthetic felt good")
        #expect(edited.exercises.map(\.exerciseID) == ["barbell-row", "barbell-bench-press"])
        #expect(edited.exercises.allSatisfy { $0.groupID == nil })
        let bench = edited.exercises[1]
        #expect(bench.sets == [WorkoutSet(repetitions: 10, loadKg: 40), WorkoutSet(repetitions: 8, loadKg: 60, effort: 9)])
        #expect(bench.restSeconds == 120 && bench.note == nil && bench.measure == .weightReps)
        #expect(edited.exercises[0].sets == [WorkoutSet(repetitions: 8, loadKg: 52.5)])

        // Group them again as a superset, and change the activity.
        let regroup = #"{"workout_id":"\#(original.id)","expected_revision":2,"activity":"crossfit","exercises":[{"name":"Barbell Row","group":"s","sets":[{"repetitions":8,"load_kg":52.5}]},{"name":"Barbell Bench Press","group":"s","sets":[{"repetitions":10,"load_kg":40},{"repetitions":8,"load_kg":60,"effort":9}]}]}"#
        _ = try await apply(store, profile, try await capturedTurn(store, text: "Synthetic regroup", photos: [], at: now, expectedProfileID: profile.id),
                            call("edit_workout", regroup), workouts: [edited])
        let grouped = try #require(try await store.snapshotForExport().workouts.first)
        #expect(grouped.exercises[0].groupID != nil && grouped.exercises[0].groupID == grouped.exercises[1].groupID)
        #expect(grouped.activity == "crossfit" && grouped.kind == .cardio && grouped.exercises[1].sets == bench.sets)
    }

    @Test func deleteWarmupSetDoesNotShiftType() throws {
        let stored = [WorkoutExercise(name: "Barbell Bench Press", sets: [WorkoutSet(repetitions: 10, loadKg: 40, type: .warmup, done: true), WorkoutSet(repetitions: 8, loadKg: 60, effort: 8, done: true)],
                                      exerciseID: "barbell-bench-press", measure: .weightReps)]
        // The warm-up is gone: the working set keeps only what the call lists.
        let deleted = try WorkoutPatch.merged([.init(name: "Bench", sets: [WorkoutSet(repetitions: 8, loadKg: 60, effort: 8)])], into: stored)
        #expect(deleted[0].sets == [WorkoutSet(repetitions: 8, loadKg: 60, effort: 8, done: true)])
        // A set inserted between them carries nothing over from the set that used to sit there.
        let inserted = try WorkoutPatch.merged([.init(name: "Bench", sets: [WorkoutSet(repetitions: 10, loadKg: 40, type: .warmup), WorkoutSet(repetitions: 6, loadKg: 50), WorkoutSet(repetitions: 8, loadKg: 60, effort: 8)])], into: stored)
        #expect(inserted[0].sets.map(\.type) == [.warmup, nil, nil] && inserted[0].sets.map(\.effort) == [nil, nil, 8])
        #expect(inserted[0].sets.map(\.loadKg) == [40, 50, 60])
    }

    @Test func legacyNamedExerciseJoinsCatalogOnEdit() throws {
        let stored = [WorkoutExercise(name: "Squat", sets: [WorkoutSet(repetitions: 8, loadKg: 40)])]
        let merged = try WorkoutPatch.merged([.init(name: "Squat", sets: [WorkoutSet(repetitions: 8, loadKg: 45)])], into: stored)
        #expect(merged[0].exerciseID == "barbell-back-squat" && merged[0].name == "Barbell Back Squat" && merged[0].measure == .weightReps)
    }

    @Test func addToRunningWorkout() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bench = WorkoutExercise(name: "Barbell Bench Press", sets: [WorkoutSet(repetitions: 8, loadKg: 60, done: true)], exerciseID: "barbell-bench-press", measure: .weightReps)
        let running = try await store.startWorkout(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: [bench], title: "Push day", activity: "strength"),
                                                   at: now, expectedProfileID: profile.id)
        // "another set 60 × 8"
        let replies = WorkoutCoachReplies([result([call("add_to_workout", #"{"exercise":"bench press","sets":[{"repetitions":8,"load_kg":60}]}"#)]), result(text: "Done")])
        let completed = try await CoachEngine(store: store, infer: { try await replies.next($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        let active = try #require(try await store.activeWorkout(expectedProfileID: profile.id))
        #expect(active.id == running.id && active.exercises.count == 1)
        #expect(active.exercises[0].sets == [WorkoutSet(repetitions: 8, loadKg: 60, done: true), WorkoutSet(repetitions: 8, loadKg: 60, done: true)])
        #expect(try await store.snapshotForExport().workouts.count == 1)
        let receipt = DiaryDatabase.coachCommittedReceipt(try #require(completed.receipts.first))
        #expect(CoachReceiptPresentation(receipt: receipt, target: .loading).committedStatus == "Added to Push day")
        // The model saw the running workout in its context.
        let developer = await replies.inputs[0].compactMap { item -> String? in if case .message(role: .developer, text: let text, images: _) = item { text } else { nil } }.last
        #expect(developer?.contains(running.id.uuidString) == true)
    }

    @Test func coachAddWhileScreenOpenKeepsBoth() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bench = WorkoutExercise(name: "Barbell Bench Press", sets: [WorkoutSet(repetitions: 8, loadKg: 60, done: false)], exerciseID: "barbell-bench-press", measure: .weightReps)
        let running = try await store.startWorkout(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: [bench], activity: "strength"), at: now, expectedProfileID: profile.id)
        let model = LiveWorkoutModel(store: store, profileID: profile.id, session: running, unit: "kg", mode: .live)
        _ = try await apply(store, profile, turn, call("add_to_workout", #"{"exercise":"Barbell row","sets":[{"repetitions":10,"load_kg":50}]}"#))
        await model.tick(exercise: 0, set: 0)
        let stored = try #require(try await store.activeWorkout(expectedProfileID: profile.id))
        #expect(model.saveError == nil && model.session == stored)
        #expect(stored.exercises.map(\.exerciseID) == ["barbell-bench-press", "barbell-row"])
        #expect(stored.exercises[0].sets[0].done == true && stored.exercises[1].sets == [WorkoutSet(repetitions: 10, loadKg: 50, done: true)])
    }

    @Test func doneAfterCoachAddKeepsBoth() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bench = WorkoutExercise(name: "Barbell Bench Press", sets: [WorkoutSet(repetitions: 8, loadKg: 60, done: false)], exerciseID: "barbell-bench-press", measure: .weightReps)
        let running = try await store.startWorkout(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: [bench], activity: "strength"), at: now, expectedProfileID: profile.id)
        let model = LiveWorkoutModel(store: store, profileID: profile.id, session: running, unit: "kg", mode: .live)
        await model.tick(exercise: 0, set: 0)
        _ = try await apply(store, profile, turn, call("add_to_workout", #"{"exercise":"Barbell row","sets":[{"repetitions":10,"load_kg":50}]}"#))
        // Done with no edit in between.
        #expect(await model.finish(at: now.addingTimeInterval(1_800)))
        let finished = try #require(try await store.snapshotForExport().workouts.first)
        #expect(finished.isFinished && finished.exercises.map(\.exerciseID) == ["barbell-bench-press", "barbell-row"])
        #expect(try await store.activeWorkout(expectedProfileID: profile.id) == nil)
    }

    @Test func discardAfterCoachAddDiscards() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let running = try await store.startWorkout(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: [], activity: "strength"), at: now, expectedProfileID: profile.id)
        let model = LiveWorkoutModel(store: store, profileID: profile.id, session: running, unit: "kg", mode: .live)
        _ = try await apply(store, profile, turn, call("add_to_workout", #"{"exercise":"Barbell row","sets":[{"repetitions":10,"load_kg":50}]}"#))
        #expect(await model.discard())
        #expect(try await store.activeWorkout(expectedProfileID: profile.id) == nil)
    }

    @Test func failedEditSurvivesCoachAddAndNextEdit() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bench = WorkoutExercise(name: "Barbell Bench Press", sets: [WorkoutSet(repetitions: 8, loadKg: 60, done: false), WorkoutSet(repetitions: 8, loadKg: 60, done: false)],
                                    exerciseID: "barbell-bench-press", measure: .weightReps)
        let running = try await store.startWorkout(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: [bench], activity: "strength"), at: now, expectedProfileID: profile.id)
        let model = LiveWorkoutModel(store: store, profileID: profile.id, session: running, unit: "kg", mode: .live)
        let file = root.appendingPathComponent(profile.id.uuidString + ".sqlite").appendingPathComponent("diary.sqlite")
        func sql(_ statement: String) throws {
            var db: OpaquePointer?
            guard sqlite3_open(file.path, &db) == SQLITE_OK else { throw DiaryError.persistenceFailed }
            defer { sqlite3_close(db) }
            guard sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK else { throw DiaryError.persistenceFailed }
        }
        // The first tick fails to save and stays on screen with its error.
        try sql("CREATE TRIGGER reject_live BEFORE UPDATE OF revision ON storage_head BEGIN SELECT RAISE(ABORT, 'synthetic'); END")
        await model.tick(exercise: 0, set: 0)
        #expect(model.saveError != nil && model.isTicked(exercise: 0, set: 0) == false)
        try sql("DROP TRIGGER reject_live")
        _ = try await apply(store, profile, turn, call("add_to_workout", #"{"exercise":"Barbell row","sets":[{"repetitions":10,"load_kg":50}]}"#))
        // The next edit saves both screen edits onto Pip's copy.
        await model.update(exercise: 0, set: 1, kg: 62.5, reps: nil, seconds: nil)
        let stored = try #require(try await store.activeWorkout(expectedProfileID: profile.id))
        #expect(model.saveError == nil && model.session == stored)
        #expect(stored.exercises[0].sets[0].done == true && stored.exercises[0].sets[1].loadKg == 62.5)
        #expect(stored.exercises.map(\.exerciseID) == ["barbell-bench-press", "barbell-row"])
    }

    @Test func addWithoutRunningWorkoutIsCorrectable() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: CoachError.invalidArguments) {
            try await apply(store, profile, turn, call("add_to_workout", #"{"exercise":"Barbell row","sets":[{"repetitions":10,"load_kg":50}]}"#))
        }
    }

    @Test func bigRunningWorkoutStaysInsideContext() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let long = String(repeating: "n", count: 2_000)
        let exercises = (0..<100).map { WorkoutExercise(name: String(format: "Synthetic own lift %03d ", $0) + String(repeating: "x", count: 170), sets: [WorkoutSet(repetitions: 8, loadKg: 20)], note: long) }
        let running = try await store.startWorkout(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: exercises, title: "Synthetic big day", activity: "strength", note: long),
                                                   at: now, expectedProfileID: profile.id)
        let context = try await store.coachContext(turnID: turn.id, expectedProfileID: profile.id)
        let active = try #require(context.activeWorkout)
        #expect(active.id == running.id && active.title == "Synthetic big day" && !active.exercises.isEmpty)
        #expect(try JSONEncoder().encode(active).count <= 8192); #expect(context.truncated)
    }

    @Test func modelBurnIgnoredUnlessUser() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await store.recordWeight(value: 70, at: now)
        let run = #"{"local_date":"2027-01-15","kind":"cardio","activity":"run","duration_minutes":30,"exercises":[],"estimated_burn_kcal":999,"burn_source":"modelEstimate"}"#
        _ = try await apply(store, profile, turn, call("log_workout", run))
        let estimated = try #require(try await store.snapshotForExport().workouts.first)
        let mivu = try #require(WorkoutBurn.estimate(activity: "run", seconds: 1_800, distanceMeters: nil, effort: nil, bodyKg: 70))
        #expect(estimated.estimatedBurnKcal == mivu && estimated.burnSource == nil)

        let said = run.replacingOccurrences(of: "modelEstimate", with: "userEstimate").replacingOccurrences(of: "2027-01-15", with: "2027-01-14")
        _ = try await apply(store, profile, try await capturedTurn(store, text: "Synthetic 999", photos: [], at: now, expectedProfileID: profile.id), call("log_workout", said))
        let typed = try #require(try await store.snapshotForExport().workouts.first { $0.id != estimated.id })
        #expect(typed.estimatedBurnKcal == 999 && typed.burnSource == .userEstimate)
    }

    @Test func startRoutineOnlyCard() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let routine = try await store.saveRoutine(WorkoutRoutine(name: "Push day", exercises: [WorkoutExercise(name: "Barbell Bench Press", sets: [WorkoutSet(repetitions: 8, loadKg: 60)], exerciseID: "barbell-bench-press")]),
                                                  expectedRevision: nil, expectedProfileID: profile.id)
        let card = call("start_routine", #"{"routine_id":"\#(routine.id)"}"#)
        guard case .write(.routineCard(let id)) = try CoachTools.parse(card, meals: [], evidence: [:], receipts: []) else { Issue.record("not a routine card"); return }
        #expect(id == routine.id)
        let completed = try await run(store, profile, turn, [card])
        #expect(try await store.activeWorkout(expectedProfileID: profile.id) == nil)
        #expect(try await store.snapshotForExport().workouts.isEmpty)
        let receipt = DiaryDatabase.coachCommittedReceipt(try #require(completed.receipts.first))
        #expect(receipt.routineID == routine.id && receipt.routineName == "Push day")
    }

    @Test func rulesForbidSuggestions() {
        #expect(CoachEngine.stableRules.contains("Never suggest workouts, weights, sets or plans."))
        #expect(CoachEngine.stableRules.contains("Use start_routine only when the user asks to start a routine."))
    }

    @Test func historyBounded() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: CoachError.invalidArguments) { try CoachTools.parse(call("get_exercise_history", #"{"exercise":"Bench","limit":11}"#), meals: [], evidence: [:], receipts: []) }
        let bench = { (load: Double) in WorkoutExercise(name: "Barbell Bench Press", sets: [WorkoutSet(repetitions: 5, loadKg: load)], exerciseID: "barbell-bench-press") }
        for day in 1...12 {
            _ = try await store.createWorkout(localDate: String(format: "2027-01-%02d", day), draft: WorkoutDraft(kind: .strength, durationMinutes: 30, exercises: [bench(Double(40 + day))]),
                                              performedAt: nil, expectedProfileID: profile.id)
        }
        guard case .exerciseHistory(let name, let limit) = try CoachTools.parse(call("get_exercise_history", #"{"exercise":"Bench","limit":10}"#), meals: [], evidence: [:], receipts: []) else { Issue.record("not a history read"); return }
        let history = try await store.coachExerciseHistory(name, limit: limit, expectedProfileID: profile.id)
        #expect(history.sessions.count == 10 && history.totalSessions == 12)
        #expect(history.sessions.first?.localDate == "2027-01-12" && history.heaviestKg == 52)
    }

    @Test func oneRunningWorkoutAndNoActiveReplyRead() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let running = try await store.startWorkout(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: [], activity: "strength"), at: now, expectedProfileID: profile.id)
        await #expect(throws: DiaryError.conflict) {
            _ = try await store.createWorkout(localDate: "2027-01-15", draft: WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: [], state: .active), performedAt: nil, expectedProfileID: profile.id)
        }
        // Quoting the running workout gives Pip no record by ID; the running-workout context carries it instead.
        let prepared = try await store.coachCapturePreparation(at: now, expectedProfileID: profile.id), quoted = UUID()
        let payload = try CoachSubmissionPayload(submissionID: quoted, text: "Synthetic quote", attachments: [], context: prepared.context,
                                                 reply: CoachReply(target: .workout(workoutID: running.id), excerpt: "Gym"))
        _ = try await store.captureCoachSubmission(payload, expectedSelection: prepared.ownership, expectedProfileID: profile.id)
        let context = try await store.coachContext(turnID: quoted, expectedProfileID: profile.id)
        #expect(context.replyTo?.workout == nil && context.replyTo?.unavailable == true)
        #expect(context.activeWorkout?.id == running.id)
        // Seeing it in context does not let Coach edit or delete it; the gym screen owns it.
        let turn = try await capturedTurn(store, text: "Synthetic delete", photos: [], at: now, expectedProfileID: profile.id)
        await #expect(throws: DiaryError.invalidData) {
            try await store.applyCoachWrites([.deleteWorkout(id: running.id, revision: running.revision)], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        }
        await #expect(throws: DiaryError.invalidData) {
            try await store.applyCoachWrites([.editWorkout(id: running.id, patch: WorkoutPatch(note: "x"), revision: running.revision)], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        }
    }
}
