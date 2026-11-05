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
}
