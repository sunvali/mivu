import Foundation
import Testing
@testable import Mivu

@Suite struct WorkoutRoutineStoreTests {
    private func fixture() async throws -> (DiaryStore, DiaryProfile, URL) {
        let root = URL.temporaryDirectory.appending(path: "RoutineStore-" + UUID().uuidString)
        let profile = DiaryProfile(name: "Synthetic routines", timeZoneID: "Asia/Jerusalem")
        let store = DiaryStore(directory: root)
        _ = try await store.createProfile(profile)
        return (store, profile, root)
    }

    private func routine(_ name: String, lastUsedAt: Date? = nil) -> WorkoutRoutine {
        WorkoutRoutine(name: name, exercises: [WorkoutExercise(name: "Squat", sets: [WorkoutSet(repetitions: 5, loadKg: 60)])], lastUsedAt: lastUsedAt)
    }

    @Test func routineCreateEditDelete() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let old = try await store.saveRoutine(routine("Legs", lastUsedAt: Date(timeIntervalSince1970: 100)), expectedRevision: nil, expectedProfileID: profile.id)
        let recent = try await store.saveRoutine(routine("Push", lastUsedAt: Date(timeIntervalSince1970: 200)), expectedRevision: nil, expectedProfileID: profile.id)
        let unused = try await store.saveRoutine(routine("Arms"), expectedRevision: nil, expectedProfileID: profile.id)
        #expect(old.revision == 1)
        #expect(try await store.routines(expectedProfileID: profile.id) == [recent, old, unused])

        var edit = old; edit.name = "Leg day"
        let updated = try await store.saveRoutine(edit, expectedRevision: 1, expectedProfileID: profile.id)
        #expect(updated.id == old.id && updated.revision == 2 && updated.name == "Leg day")
        await #expect(throws: DiaryError.staleRevision) { try await store.saveRoutine(edit, expectedRevision: 1, expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.staleRevision) { try await store.saveRoutine(routine("Legs"), expectedRevision: 1, expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.staleRevision) { try await store.deleteRoutine(id: old.id, expectedRevision: 1, expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.wrongOwner) { try await store.routines(expectedProfileID: UUID()) }

        try await store.deleteRoutine(id: old.id, expectedRevision: 2, expectedProfileID: profile.id)
        #expect(try await store.routines(expectedProfileID: profile.id) == [recent, unused])
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.routines == [recent, unused] && snapshot.deletedRoutineIDs == [old.id])
        await #expect(throws: DiaryError.notFound) { try await store.deleteRoutine(id: old.id, expectedRevision: 2, expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.notFound) { try await store.saveRoutine(updated, expectedRevision: 2, expectedProfileID: profile.id) }
    }

    @Test func routineNameRules() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        func rejects(_ edit: (inout WorkoutRoutine) -> Void) async {
            var value = routine("Legs"); edit(&value)
            await #expect(throws: DiaryError.invalidData) { try await store.saveRoutine(value, expectedRevision: nil, expectedProfileID: profile.id) }
        }
        await rejects { $0.name = "" }
        await rejects { $0.name = "   " }
        await rejects { $0.name = String(repeating: "a", count: 101) }
        await rejects { $0.exercises = Array(repeating: WorkoutExercise(name: "Row", sets: []), count: 51) }
        await rejects { $0.exercises = [WorkoutExercise(name: " ", sets: [])] }
        await rejects { $0.exercises = [WorkoutExercise(name: "Row", sets: [WorkoutSet(repetitions: 10_001)])] }
        _ = try await store.saveRoutine(routine(String(repeating: "a", count: 100)), expectedRevision: nil, expectedProfileID: profile.id)
        var full = routine("Full"); full.exercises = Array(repeating: WorkoutExercise(name: "Row", sets: []), count: 50)
        _ = try await store.saveRoutine(full, expectedRevision: nil, expectedProfileID: profile.id)
        #expect(try await store.routines(expectedProfileID: profile.id).count == 2)
    }

    @Test func routineNamesTrimmedAndSortedNaturally() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let saved = try await store.saveRoutine(routine("  Day 10 \n"), expectedRevision: nil, expectedProfileID: profile.id)
        #expect(saved.name == "Day 10")
        for name in ["day 2", "Day 1"] { _ = try await store.saveRoutine(routine(name), expectedRevision: nil, expectedProfileID: profile.id) }
        #expect(try await store.routines(expectedProfileID: profile.id).map(\.name) == ["Day 1", "day 2", "Day 10"])
    }

    @Test func routinesSurviveReopen() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let saved = try await store.saveRoutine(routine("Legs"), expectedRevision: nil, expectedProfileID: profile.id)
        let reopened = DiaryStore(directory: root)
        _ = try await reopened.selectProfile(profile.id)
        #expect(try await reopened.routines(expectedProfileID: profile.id) == [saved])
    }

    @Test func profileMigratedBeforeRoutinesGainsThemOnOpen() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        // A pre-routine profile: no tables or counts, and a meta encoding without the two new snapshot keys.
        let old = try DiaryDatabase(url: root.appending(path: profile.id.uuidString + ".sqlite/diary.sqlite"))
        let newKeys = Data(#","routines":[],"deletedRoutineIDs":[]"#.utf8).count
        for statement in ["DROP TABLE routine", "DROP TABLE routine_tombstone", "DELETE FROM storage_row_count WHERE tableName LIKE 'routine%'",
                          "UPDATE storage_contribution SET encodedBytes = encodedBytes - \(newKeys) WHERE tableName = 'meta'",
                          "UPDATE storage_quota SET portableBytes = portableBytes - \(newKeys)"] { try old.execute(statement) }
        let upgraded = DiaryStore(directory: root)
        _ = try await upgraded.selectProfile(profile.id)
        // Export and restore work before any write.
        let before = try await upgraded.snapshotForExport()
        var next = before; next.revision += 1; next.lineage = (before.lineage ?? []) + [UUID()]
        try await upgraded.restore(next)
        let saved = try await upgraded.saveRoutine(routine("Legs"), expectedRevision: nil, expectedProfileID: profile.id)
        try await upgraded.deleteRoutine(id: saved.id, expectedRevision: 1, expectedProfileID: profile.id)
        let snapshot = try await upgraded.snapshotForExport()
        #expect(snapshot.routines.isEmpty && snapshot.deletedRoutineIDs == [saved.id])
        _ = try DiaryArchive.decode(DiaryArchive.encode(snapshot))
    }

    private func own(_ name: String) -> WorkoutExercise { WorkoutExercise(name: name, sets: [WorkoutSet(repetitions: 8, loadKg: 30)], measure: .reps) }

    private func workout(_ store: DiaryStore, _ profile: DiaryProfile, _ exercises: [WorkoutExercise]) async throws -> WorkoutSession {
        try await store.createWorkout(localDate: "2027-03-08", draft: WorkoutDraft(kind: .strength, durationMinutes: 30, exercises: exercises),
                                      performedAt: nil, expectedProfileID: profile.id)
    }

    @Test func renameOwnExerciseRewritesAll() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bench = WorkoutExercise(name: "Barbell Bench Press", sets: [WorkoutSet(repetitions: 5, loadKg: 60)], exerciseID: "barbell-bench-press")
        let first = try await workout(store, profile, [own("My Row"), bench])
        let second = try await workout(store, profile, [own("my rows"), own("Cable fly")])
        var plan = routine("Pull"); plan.exercises = [own("MY ROW")]
        let saved = try await store.saveRoutine(plan, expectedRevision: nil, expectedProfileID: profile.id)
        // A running workout is left alone: its screen saves its own copy.
        let running = try await store.startWorkout(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: [own("My Row")], activity: "strength"),
                                                   at: Date(), expectedProfileID: profile.id)
        #expect(try await store.ownExerciseNames(expectedProfileID: profile.id) == ["Cable fly", "My Row"])

        #expect(try await store.renameOwnExercise(from: "my row", to: "  Seated row ", expectedProfileID: profile.id) == 3)
        let history = try await store.workoutHistory(expectedProfileID: profile.id).values
        let renamedFirst = try #require(history.first { $0.id == first.id }), renamedSecond = try #require(history.first { $0.id == second.id })
        #expect(renamedFirst.exercises.map(\.name) == ["Seated row", "Barbell Bench Press"] && renamedFirst.revision == first.revision + 1)
        #expect(renamedSecond.exercises.map(\.name) == ["Seated row", "Cable fly"])
        #expect(renamedFirst.exercises[0].sets == own("x").sets && renamedFirst.exercises[0].measure == .reps)
        let routines = try await store.routines(expectedProfileID: profile.id)
        #expect(routines.map(\.exercises[0].name) == ["Seated row"] && routines[0].revision == saved.revision + 1)
        #expect(try await store.activeWorkout(expectedProfileID: profile.id) == running)
        #expect(try await store.ownExerciseNames(expectedProfileID: profile.id) == ["Cable fly", "Seated row"])

        await #expect(throws: DiaryError.invalidData) { try await store.renameOwnExercise(from: "Seated row", to: " ", expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.wrongOwner) { try await store.renameOwnExercise(from: "Seated row", to: "Row", expectedProfileID: UUID()) }
        #expect(try await store.renameOwnExercise(from: "Nothing", to: "Row", expectedProfileID: profile.id) == 0)
    }

    @Test func mergeIntoCatalog() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await workout(store, profile, [own("bench"), own("Dips")])
        var plan = routine("Push"); plan.exercises = [own("Bench")]
        _ = try await store.saveRoutine(plan, expectedRevision: nil, expectedProfileID: profile.id)
        let key = ExerciseKey(WorkoutExercise(name: "Barbell Bench Press", sets: [], exerciseID: "barbell-bench-press"))

        #expect(try await store.mergeOwnExercise("Bench", into: key, expectedProfileID: profile.id) == 2)
        let merged = try #require(try await store.workoutHistory(expectedProfileID: profile.id).values.first)
        #expect(merged.exercises[0] == WorkoutExercise(name: "Barbell Bench Press", sets: own("x").sets, exerciseID: "barbell-bench-press", measure: .weightReps))
        #expect(merged.exercises[1].name == "Dips" && merged.exercises[1].exerciseID == nil)
        #expect(try await store.routines(expectedProfileID: profile.id)[0].exercises[0].exerciseID == "barbell-bench-press")
        #expect(try await store.finishedWorkouts(containing: key, limit: 10, expectedProfileID: profile.id).count == 1)
        #expect(try await store.ownExerciseNames(expectedProfileID: profile.id) == ["Dips"])

        // Only a bundled exercise can absorb one.
        await #expect(throws: DiaryError.invalidData) { try await store.mergeOwnExercise("Dips", into: ExerciseKey(own("Row")), expectedProfileID: profile.id) }
    }

    @MainActor @Test func renameThatJoinsAnotherAsksAsAMerge() {
        let own = ["Band twist", "My Row"]
        #expect(MyExercisesView.mergeTarget(renaming: "My Row", to: "Garage row", own: own) == nil)
        #expect(MyExercisesView.mergeTarget(renaming: "My Row", to: "my rows", own: own) == nil, "the same exercise, only spelled differently")
        #expect(MyExercisesView.mergeTarget(renaming: "My Row", to: "band twists", own: own)?.name == "Band twist")
        let catalog = MyExercisesView.mergeTarget(renaming: "My Row", to: " bench press ", own: own)
        #expect(catalog?.exerciseID == "barbell-bench-press" && catalog?.name == "Barbell Bench Press")
    }
}
