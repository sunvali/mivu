import Foundation
import Testing
@testable import Mivu

/// Synthetic exports only, written by hand in each app's column layout.
@MainActor @Suite struct WorkoutCSVTests {
    private let zone = TimeZone(identifier: "Asia/Jerusalem")!

    private let strong = """
        Date;Workout Name;Duration;Exercise Name;Set Order;Weight;Reps;Distance;Seconds;Notes;Workout Notes;RPE
        2027-03-01 18:30:00;Push day;1h 5m;Bench Press (Barbell);W;40;10;0;0;;Felt strong;
        2027-03-01 18:30:00;Push day;1h 5m;Bench Press (Barbell);1;62,5;8;0;0;;Felt strong;8
        2027-03-01 18:30:00;Push day;1h 5m;Synthetic Sled Push;1;0;0;20;30;;Felt strong;
        2027-03-03 07:00:00;Core;12m;Plank;1;0;0;0;60;;;
        """

    private let hevy = """
        title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_lbs,reps,distance_miles,duration_seconds,rpe
        "Pull, heavy",5 Mar 2027 18:00,5 Mar 2027 19:00,,Barbell Row,1,,0,warmup,95,10,,,
        "Pull, heavy",5 Mar 2027 18:00,5 Mar 2027 19:00,,Barbell Row,1,,1,normal,135,8,,,9
        "Pull, heavy",5 Mar 2027 18:00,5 Mar 2027 19:00,,Face Pull,1,"rope, high",0,normal,40,15,,,
        "Pull, heavy",5 Mar 2027 18:00,5 Mar 2027 19:00,,Lat Pulldown,,,0,dropset,100,12,,,
        """

    @Test func detectStrongAndHevy() {
        #expect(WorkoutCSV.detect(header: String(strong.split(separator: "\n")[0])) == .strong)
        #expect(WorkoutCSV.detect(header: String(hevy.split(separator: "\n")[0])) == .hevy)
        #expect(WorkoutCSV.detect(header: "name,calories") == nil)
    }

    @Test func strongDecimalComma() throws {
        let result = try WorkoutCSV.parse(strong, format: .strong, defaultUnit: "kg", zone: zone)
        #expect(result.skipped == 0 && result.workouts.count == 2)
        let push = result.workouts[0]
        #expect(push.draft.title == "Push day" && push.draft.source == .importStrong && push.draft.note == "Felt strong")
        let bench = try #require(push.draft.exercises.first)
        #expect(bench.exerciseID == "barbell-bench-press")
        #expect(bench.sets == [WorkoutSet(repetitions: 10, loadKg: 40, type: .warmup, done: true), WorkoutSet(repetitions: 8, loadKg: 62.5, effort: 8, done: true)])
        // An unknown name stays the person's own exercise, measured by what its sets hold.
        #expect(push.draft.exercises[1].exerciseID == nil && push.draft.exercises[1].measure == .distanceTime)
        #expect(push.draft.exercises[1].sets == [WorkoutSet(repetitions: 0, seconds: 30, distanceMeters: 20_000, done: true)])
        #expect(result.workouts[1].draft.exercises[0].sets == [WorkoutSet(repetitions: 0, seconds: 60, done: true)])
    }

    @Test func strongDurationText() throws {
        let result = try WorkoutCSV.parse(strong, format: .strong, defaultUnit: "kg", zone: zone)
        #expect(result.workouts[0].draft.durationSeconds == 3900 && result.workouts[0].draft.durationMinutes == 65)
        #expect(result.workouts[1].draft.durationSeconds == 720)
        var components = DateComponents(); components.timeZone = zone
        components.year = 2027; components.month = 3; components.day = 1; components.hour = 18; components.minute = 30
        #expect(result.workouts[0].startedAt == Calendar(identifier: .gregorian).date(from: components))
    }

    @Test func hevyLbColumns() throws {
        let result = try WorkoutCSV.parse(hevy, format: .hevy, defaultUnit: "kg", zone: zone)
        let pull = try #require(result.workouts.first)
        #expect(pull.draft.title == "Pull, heavy" && pull.draft.source == .importHevy && pull.draft.durationSeconds == 3600)
        let row = pull.draft.exercises[0]
        #expect(abs((row.sets[1].loadKg ?? 0) - 61.235) < 0.001)
        #expect(row.sets[0].type == .warmup && row.sets[1].effort == 9)
        #expect(pull.draft.exercises[1].note == "rope, high")
        #expect(pull.draft.exercises[2].sets[0].type == .drop)
    }

    @Test func hevySupersetGroups() throws {
        let pull = try #require(try WorkoutCSV.parse(hevy, format: .hevy, defaultUnit: "kg", zone: zone).workouts.first)
        #expect(pull.draft.exercises[0].groupID != nil)
        #expect(pull.draft.exercises[0].groupID == pull.draft.exercises[1].groupID)
        #expect(pull.draft.exercises[2].groupID == nil)
    }

    @Test func brokenWorkoutSkipped() throws {
        let broken = strong + "\n2027-03-04 09:00:00;Legs;40m;Squat (Barbell);1;heavy;5;0;0;;;"
            + "\nnot a date;Arms;20m;Curl;1;10;10;0;0;;;"
        let result = try WorkoutCSV.parse(broken, format: .strong, defaultUnit: "kg", zone: zone)
        #expect(result.workouts.count == 2 && result.skipped == 2)
        #expect(throws: (any Error).self) { try WorkoutCSV.parse("Date;Workout Name\n", format: .hevy, defaultUnit: "kg", zone: zone) }
    }

    @Test func reimportNoDuplicates() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let rows = try WorkoutCSV.parse(strong, format: .strong, defaultUnit: "kg", zone: zone).workouts
        let first = try await store.importWorkouts(rows, source: .importStrong, expectedProfileID: profile.id)
        #expect(first.added == 2 && first.duplicates == 0)
        let again = try await store.importWorkouts(rows, source: .importStrong, expectedProfileID: profile.id)
        #expect(again.added == 0 && again.duplicates == 2)
        #expect(try await store.workoutHistory(expectedProfileID: profile.id).values.count == 2)
    }

    @Test func importedDaysNotSkipped() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let rows = try WorkoutCSV.parse(strong, format: .strong, defaultUnit: "kg", zone: zone).workouts
        _ = try await store.importWorkouts(rows, source: .importStrong, expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.days.map(\.localDate).sorted() == ["2027-03-01", "2027-03-03"])
        let week = ProgressAnalytics.period(snapshot: snapshot, endingOn: "2027-03-07", days: 7)
        #expect(week.skippedDayCount == 0)
    }

    @Test func exportRoundTripsThroughHevyParser() throws {
        let original = try WorkoutCSV.parse(hevy, format: .hevy, defaultUnit: "kg", zone: zone).workouts[0]
        let session = WorkoutSession(dayID: UUID(), performedAt: original.startedAt, timePrecision: .exact, revision: 1, kind: .strength,
                                     durationMinutes: 60, exercises: original.draft.exercises, title: original.draft.title,
                                     durationSeconds: 3600, note: "Synthetic")
        let csv = WorkoutCSV.export([session], zone: zone)
        #expect(csv.hasPrefix("title,start_time,end_time,exercise_title,superset_id,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,effort,note\n"))
        #expect(WorkoutCSV.detect(header: String(csv.split(separator: "\n")[0])) == .hevy)
        let back = try #require(try WorkoutCSV.parse(csv, format: .hevy, defaultUnit: "lb", zone: zone).workouts.first)
        #expect(back.startedAt == original.startedAt && back.draft.title == "Pull, heavy" && back.draft.durationSeconds == 3600)
        #expect(back.draft.exercises.map(\.name) == original.draft.exercises.map(\.name))
        #expect(back.draft.exercises.map(\.sets) == original.draft.exercises.map(\.sets))
        #expect(back.draft.exercises[0].groupID != nil && back.draft.exercises[0].groupID == back.draft.exercises[1].groupID)
    }

    private func fixture() async throws -> (DiaryStore, DiaryProfile, URL) {
        let root = URL.temporaryDirectory.appending(path: "WorkoutCSV-" + UUID().uuidString)
        let profile = DiaryProfile(name: "Synthetic importer", timeZoneID: "Asia/Jerusalem")
        let store = DiaryStore(directory: root)
        _ = try await store.createProfile(profile)
        return (store, profile, root)
    }
}

extension WorkoutCSVTests {
    /// A workout the diary would refuse is skipped and counted, not fatal to the whole file; empty template sets are dropped.
    @Test func unsavableWorkoutSkippedNotFatal() throws {
        let note = String(repeating: "x", count: 2_500)
        let text = strong + "\n2027-03-04 09:00:00;Legs;40m;Squat (Barbell);1;0;0;0;0;;;"
            + "\n2027-03-04 09:00:00;Legs;40m;Squat (Barbell);2;100;5;0;0;;;"
            + "\n2027-03-05 09:00:00;Long note;40m;Squat (Barbell);1;100;5;0;0;;\(note);"
        let result = try WorkoutCSV.parse(text, format: .strong, defaultUnit: "kg", zone: zone)
        #expect(result.workouts.count == 3 && result.skipped == 1)
        #expect(result.workouts[2].draft.exercises[0].sets == [WorkoutSet(repetitions: 5, loadKg: 100, done: true)])
    }

    /// The same workout twice in one file is stored once.
    @Test func duplicatesInsideOneFileCounted() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let rows = try WorkoutCSV.parse(strong, format: .strong, defaultUnit: "kg", zone: zone).workouts
        let result = try await store.importWorkouts(rows + rows, source: .importStrong, expectedProfileID: profile.id)
        #expect(result.added == 2 && result.duplicates == 2)
    }

    /// Exporting a run keeps its distance and time, and reading it back gives a run again.
    @Test func exportKeepsCardio() throws {
        let run = WorkoutSession(dayID: UUID(), performedAt: Date(timeIntervalSince1970: 1_800_000_000), timePrecision: .exact, revision: 1,
                                 kind: .cardio, durationMinutes: 28, exercises: [], activity: "run", durationSeconds: 1680, distanceMeters: 5000)
        let csv = WorkoutCSV.export([run], zone: zone)
        let back = try #require(try WorkoutCSV.parse(csv, format: .hevy, defaultUnit: "kg", zone: zone).workouts.first)
        #expect(back.draft.activity == "run" && back.draft.kind == .cardio)
        #expect(back.draft.distanceMeters == 5000 && back.draft.durationSeconds == 1680 && back.draft.exercises.isEmpty)
    }
}
