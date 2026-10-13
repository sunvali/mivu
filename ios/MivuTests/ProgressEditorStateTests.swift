import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct ProgressEditorStateTests {
    @Test func savedWorkoutBoundsRemainEditable() {
        let savedSet = WorkoutSet(repetitions: 5_000, loadKg: 0)
        var fields = WorkoutEditorView.SetFields(savedSet)
        #expect(fields.valid)
        #expect(fields.record?.repetitions == 5_000)
        #expect(fields.record?.loadKg == 0)

        fields.repetitions = "10001"
        #expect(!fields.valid)
        fields.repetitions = "10000"
        #expect(fields.valid)
        fields.repetitions = "0"
        #expect(!fields.valid)
        fields.repetitions = "5000"
        fields.load = "100000"
        #expect(fields.valid)
        fields.load = "100000.1"
        #expect(!fields.valid)
        fields.load = "-1"
        #expect(!fields.valid)
        fields.load = ""
        #expect(fields.valid)
        #expect(fields.record?.loadKg == nil)

        #expect(ProgressDate.validOptionalNonnegative("0"))
        #expect(ProgressDate.validOptionalNonnegative("100000"))
        #expect(ProgressDate.validOptionalNonnegative(""))
        #expect(!ProgressDate.validOptionalNonnegative("-0.1"))
        #expect(!ProgressDate.validOptionalNonnegative("100000.1"))
        #expect(!ProgressDate.validOptionalNonnegative("inf"))
        #expect(!ProgressDate.validOptional("0"))
    }

    @Test func clearingLastGoalAndLaterUnsetPreserveEarlierTargets() async throws {
        let root = URL.temporaryDirectory.appending(path: "ProgressEditorClear-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root)
        let profile = DiaryProfile(name: "Synthetic clear goals")
        _ = try await store.createProfile(profile)
        for (date, target) in [("2026-01-01", 1800.0), ("2026-02-01", 2000.0)] {
            _ = try await store.setGoals(GoalRecord(effectiveLocalDate: date, timeZoneID: profile.timeZoneID,
                                                  targets: NutritionValues(kcal: target), goalWeightKg: nil,
                                                  exerciseCreditEnabled: false), expectedRevision: nil, expectedProfileID: profile.id)
        }
        var values = GoalEditorValues(snapshot: try await store.snapshot(), localDate: "2026-02-01")
        values.kcal = ""
        #expect(values.valid)
        let cleared = try await store.setGoals(values.record(zone: profile.timeZoneID), expectedRevision: values.expectedRevision, expectedProfileID: profile.id)
        var snapshot = try await store.snapshot()
        #expect(ProgressAnalytics.daily(snapshot: snapshot, localDate: "2026-01-15").goal?.targets.kcal == 1800)
        #expect(ProgressAnalytics.daily(snapshot: snapshot, localDate: "2026-02-15").goal?.targets.kcal == nil)
        #expect(ProgressAnalytics.daily(snapshot: snapshot, localDate: "2026-02-15").remainingFromRecorded.kcal == nil)
        values.kcal = "2000"
        _ = try await store.setGoals(values.record(zone: profile.timeZoneID), expectedRevision: cleared.revision, expectedProfileID: profile.id)
        let later = GoalEditorValues(snapshot: try await store.snapshot(), localDate: "2026-03-01")
        #expect(later.valid)
        _ = try await store.setGoals(later.record(zone: profile.timeZoneID), expectedRevision: later.expectedRevision, expectedProfileID: profile.id)
        snapshot = try await store.snapshot()
        #expect(ProgressAnalytics.daily(snapshot: snapshot, localDate: "2026-02-15").goal?.targets.kcal == 2000)
        #expect(ProgressAnalytics.daily(snapshot: snapshot, localDate: "2026-03-15").goal?.targets.kcal == nil)
        for invalid in ["0", "-1", "inf", "nan", "invalid"] {
            values.kcal = invalid
            #expect(!values.valid)
        }
    }

    @Test func chosenGoalDateLoadsExactRecordAndKeepsItsRevision() async throws {
        let root = URL.temporaryDirectory.appending(path: "ProgressEditor-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root)
        let profile = DiaryProfile(name: "Synthetic goal editor")
        _ = try await store.createProfile(profile)
        let older = try await store.setGoals(GoalRecord(effectiveLocalDate: "2026-01-01", timeZoneID: profile.timeZoneID,
                                                       targets: NutritionValues(kcal: 1_800), goalWeightKg: nil,
                                                       exerciseCreditEnabled: false),
                                             expectedRevision: nil, expectedProfileID: profile.id)
        _ = try await store.setGoals(GoalRecord(effectiveLocalDate: "2026-10-12", timeZoneID: profile.timeZoneID,
                                                targets: NutritionValues(kcal: 2_000), goalWeightKg: nil,
                                                exerciseCreditEnabled: false),
                                      expectedRevision: nil, expectedProfileID: profile.id)
        let snapshot = try await store.snapshot()
        let historical = GoalEditorValues(snapshot: snapshot, localDate: "2026-01-01")
        #expect(historical.kcal == "1800.0")
        #expect(historical.original?.id == older.id)
        #expect(historical.expectedRevision == older.revision)

        let newDate = GoalEditorValues(snapshot: snapshot, localDate: "2026-02-01")
        #expect(newDate.kcal.isEmpty)
        #expect(newDate.original == nil)
        #expect(newDate.expectedRevision == nil)

        var concurrent = older
        concurrent.targets.kcal = 1_900
        _ = try await store.setGoals(concurrent, expectedRevision: older.revision, expectedProfileID: profile.id)
        let attempted = historical.record(zone: profile.timeZoneID)
        await #expect(throws: DiaryError.staleRevision) {
            try await store.setGoals(attempted, expectedRevision: historical.expectedRevision, expectedProfileID: profile.id)
        }
        #expect(try await store.snapshot().goals.first { $0.id == older.id }?.targets.kcal == 1_900)
    }
}
