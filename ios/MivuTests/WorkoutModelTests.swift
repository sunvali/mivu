import Foundation
import Testing
@testable import Mivu

@Suite struct WorkoutModelTests {
    private func session(_ edit: (inout WorkoutSession) -> Void = { _ in }) -> WorkoutSession {
        var value = WorkoutSession(dayID: UUID(), performedAt: Date(timeIntervalSince1970: 1_800_000_000), timePrecision: .exact, revision: 1,
                                   kind: .strength, durationMinutes: 30, exercises: [WorkoutExercise(name: "Squat", sets: [WorkoutSet(repetitions: 5, loadKg: 60)])])
        edit(&value); return value
    }

    @Test func oldPayloadDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","dayID":"\(UUID().uuidString)","performedAt":0,"timePrecision":"exact","revision":1,
         "kind":"strength","durationMinutes":30,"exercises":[{"name":"Squat","sets":[{"repetitions":5,"loadKg":60}]}]}
        """
        let value = try JSONDecoder().decode(WorkoutSession.self, from: Data(json.utf8))
        #expect(value.state == nil); #expect(value.isFinished); #expect(value.title == nil)
    }

    @Test func newFieldsRoundTrip() throws {
        let value = session {
            $0.title = "Legs"; $0.activity = "run"; $0.state = .finished; $0.durationSeconds = 1_800; $0.distanceMeters = 5_000
            $0.avgHeartRate = 140; $0.effort = 7; $0.indoor = false; $0.note = "Felt good"; $0.routineID = UUID()
            $0.source = .importStrong; $0.externalID = "x1"
            $0.exercises = [WorkoutExercise(name: "Row", sets: [WorkoutSet(repetitions: 0, loadKg: nil, type: .drop, effort: 8, seconds: 60, distanceMeters: 500, done: true)],
                                            exerciseID: "row", measure: .distanceTime, groupID: UUID(), restSeconds: 90, note: "slow")]
        }
        #expect(try JSONDecoder().decode(WorkoutSession.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test func validationBounds() throws {
        func rejects(_ edit: @escaping (inout WorkoutSession) -> Void) {
            #expect(throws: DiaryError.invalidData) { try validateWorkoutFields(session(edit)) }
        }
        rejects { $0.effort = 0 }; rejects { $0.effort = 11 }
        rejects { $0.avgHeartRate = 19 }; rejects { $0.avgHeartRate = 251 }
        rejects { $0.distanceMeters = -1 }; rejects { $0.distanceMeters = 1_000_001 }
        rejects { $0.durationSeconds = 0 }; rejects { $0.durationSeconds = 86_401 }
        rejects { $0.title = String(repeating: "a", count: 201) }
        rejects { $0.note = String(repeating: "a", count: 2_001) }
        rejects { $0.exercises[0].sets[0].effort = 11 }
        rejects { $0.exercises[0].sets[0].repetitions = 0 }
        try validateWorkoutFields(session { $0.exercises[0].sets[0] = WorkoutSet(repetitions: 0, seconds: 60) })
        try validateWorkoutFields(session { $0.title = String(repeating: "a", count: 200); $0.effort = 10; $0.durationSeconds = 86_400 })
    }

    @Test func activeMayHaveZeroDuration() throws {
        try validateWorkoutFields(session { $0.state = .active; $0.durationMinutes = 0 })
        #expect(throws: DiaryError.invalidData) { try validateWorkoutFields(session { $0.state = .finished; $0.durationMinutes = 0 }) }
    }

    @MainActor @Test func durationSecondsKeepsMinutesInSync() async throws {
        let root = URL.temporaryDirectory.appending(path: "WorkoutModel-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = DiaryProfile(name: "Synthetic workout", timeZoneID: "Asia/Jerusalem")
        let store = DiaryStore(directory: root)
        _ = try await store.createProfile(profile)
        let day = try await store.startDay(at: Date(timeIntervalSince1970: 1_800_000_000), expectedProfileID: profile.id)
        var draft = WorkoutDraft(kind: .cardio, durationMinutes: 99, exercises: [], estimatedBurnKcal: nil, burnSource: nil)
        draft.durationSeconds = 20; draft.title = "Walk"
        var created = try await store.createWorkout(dayID: day.id, draft: draft, expectedProfileID: profile.id)
        #expect(created.durationMinutes == 1 && created.durationSeconds == 20 && created.title == "Walk")
        created.durationSeconds = 5_400
        let updated = try await store.updateWorkout(created, expectedRevision: created.revision, expectedProfileID: profile.id)
        #expect(updated.durationMinutes == 90)
    }

    @MainActor @Test func minuteEditWinsOverStoredSeconds() async throws {
        let root = URL.temporaryDirectory.appending(path: "WorkoutModel-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = DiaryProfile(name: "Synthetic workout", timeZoneID: "Asia/Jerusalem")
        let store = DiaryStore(directory: root)
        _ = try await store.createProfile(profile)
        let day = try await store.startDay(at: Date(timeIntervalSince1970: 1_800_000_000), expectedProfileID: profile.id)
        var draft = WorkoutDraft(kind: .cardio, durationMinutes: 50, exercises: [], estimatedBurnKcal: nil, burnSource: nil)
        draft.durationSeconds = 3_000
        var created = try await store.createWorkout(dayID: day.id, draft: draft, expectedProfileID: profile.id)
        created.durationMinutes = 45
        let edited = try await store.updateWorkout(created, expectedRevision: created.revision, expectedProfileID: profile.id)
        #expect(edited.durationMinutes == 45 && edited.durationSeconds == nil)
        var other = edited; other.note = "Easy"
        let untouched = try await store.updateWorkout(other, expectedRevision: edited.revision, expectedProfileID: profile.id)
        #expect(untouched.durationMinutes == 45 && untouched.note == "Easy")
    }

    @Test func applyKeepsUnsetFieldsAndLetsSecondsWin() {
        var record = session { $0.title = "Legs"; $0.distanceMeters = 800; $0.durationSeconds = 1_800 }
        var draft = WorkoutDraft(kind: .strength, durationMinutes: 30, exercises: record.exercises, estimatedBurnKcal: nil, burnSource: nil)
        record.apply(draft)
        #expect(record.title == "Legs" && record.distanceMeters == 800 && record.durationSeconds == 1_800)
        draft.durationMinutes = 45; record.apply(draft)
        #expect(record.durationSeconds == nil && record.durationMinutes == 45)
        draft.durationMinutes = 10; draft.durationSeconds = 3_600; record.apply(draft)
        #expect(record.durationSeconds == 3_600 && record.syncedMinutes.durationMinutes == 60)
    }
}
