import Foundation
import SQLite3
import Testing
@testable import Mivu

@Suite @MainActor struct ProgressStoreTests {
    private let morning = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture() async throws -> (DiaryStore, DiaryProfile, URL) {
        let root = URL.temporaryDirectory.appending(path: "ProgressStore-" + UUID().uuidString)
        let profile = DiaryProfile(name: "Synthetic progress", timeZoneID: "Asia/Jerusalem")
        let store = DiaryStore(directory: root)
        _ = try await store.createProfile(profile)
        return (store, profile, root)
    }

    private func goal(_ date: String, kcal: Double = 2_000) -> GoalRecord {
        GoalRecord(effectiveLocalDate: date, timeZoneID: "Asia/Jerusalem",
                   targets: NutritionValues(kcal: kcal, protein: 100), goalWeightKg: 70,
                   exerciseCreditEnabled: false)
    }

    @Test func datedGoalsSelectLatestCompleteSettingAndGuardEdits() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try await store.setGoals(goal("2027-01-01"), expectedRevision: nil, expectedProfileID: profile.id)
        let second = try await store.setGoals(goal("2027-01-15", kcal: 2_200), expectedRevision: nil, expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.goal(on: "2026-12-31") == nil)
        #expect(snapshot.goal(on: "2027-01-14") == first)
        #expect(snapshot.goal(on: "2027-01-15") == second)
        #expect(second.targets.protein == 100)
        var edit = first; edit.targets.protein = nil
        let updated = try await store.setGoals(edit, expectedRevision: 1, expectedProfileID: profile.id)
        #expect(updated.id == first.id && updated.revision == 2 && updated.targets.protein == nil)
        let before = try await store.snapshotForExport()
        await #expect(throws: DiaryError.staleRevision) { try await store.setGoals(edit, expectedRevision: 1, expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.staleRevision) { try await store.setGoals(goal("2027-01-15"), expectedRevision: nil, expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.wrongOwner) { try await store.setGoals(goal("2027-02-01"), expectedRevision: nil, expectedProfileID: UUID()) }
        #expect(try await store.snapshotForExport() == before)
    }

    @Test func goalDateLabelsSurviveProfileTimeZoneChange() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let saved = try await store.setGoals(goal("2027-01-15"), expectedRevision: nil, expectedProfileID: profile.id)
        var shifted = profile; shifted.timeZoneID = "America/Los_Angeles"
        try await store.updateProfile(shifted, expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.goals == [saved])
        #expect(snapshot.goal(on: "2027-01-15") == saved)
        #expect(snapshot.goal(on: "2027-01-14") == nil)
    }

    @Test func manualWeightRepeatKeepsIDAndIncrementsRevision() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try await store.recordWeight(value: 70, at: morning, expectedProfileID: profile.id)
        let second = try await store.recordWeight(value: 69.5, at: morning, expectedProfileID: profile.id)
        #expect(second.id == first.id && second.revision == first.revision + 1)
        #expect(second.timePrecision == .exact && second.measuredAt == morning)
        #expect(try await completeSelectedProfile(DiaryStore(directory: root), profile.id).weights == [second])
    }

    @Test func historicalWeightUsesDateOnlyAndRejectsStaleCorrection() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try await store.setWeight(dayLocalDate: "2027-01-14", value: 154, unit: "lb", measuredAt: nil, expectedRevision: nil, expectedProfileID: profile.id)
        #expect(first.timePrecision == .dateOnly && first.unit == "lb" && first.value == 154)
        let day = try #require(await store.snapshotForExport().days.first { $0.id == first.dayID })
        #expect(day.localDate == "2027-01-14")
        let updated = try await store.setWeight(dayLocalDate: "2027-01-14", value: 153, unit: "lb", measuredAt: nil, expectedRevision: 1, expectedProfileID: profile.id)
        #expect(updated.id == first.id && updated.revision == 2)
        let before = try await store.snapshotForExport()
        await #expect(throws: DiaryError.staleRevision) { try await store.setWeight(dayLocalDate: "2027-01-14", value: 152, unit: "lb", measuredAt: nil, expectedRevision: 1, expectedProfileID: profile.id) }
        #expect(try await store.snapshotForExport() == before)
    }

    @Test func correctedWeightUsesCurrentTimeZoneDayAfterProfileChange() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try await store.recordWeight(value: 70, at: morning, expectedProfileID: profile.id)
        var shifted = profile; shifted.timeZoneID = "America/Los_Angeles"
        try await store.updateProfile(shifted, expectedProfileID: profile.id)
        let lateLocal = try #require(ISO8601DateFormatter().date(from: "2027-01-16T07:00:00Z"))
        let local = try await store.recordWeight(value: 71, at: lateLocal, expectedProfileID: profile.id)
        let corrected = try await store.setWeight(dayLocalDate: "2027-01-15", value: 72, unit: "kg",
                                                  measuredAt: lateLocal, expectedRevision: local.revision,
                                                  expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport()
        #expect(corrected.id == local.id && corrected.revision == local.revision + 1)
        #expect(corrected.dayID != original.dayID && corrected.measuredAt == lateLocal)
        #expect(snapshot.weights.first { $0.id == original.id } == original)
        #expect(snapshot.days.first { $0.id == original.dayID }?.timeZoneID == "Asia/Jerusalem")
        #expect(snapshot.days.first { $0.id == corrected.dayID }?.timeZoneID == "America/Los_Angeles")
    }

    @Test(arguments: [false, true])
    func weightIDCorrectionPreservesHistoricalRecordWhenDateAndRevisionCollide(exactTime: Bool) async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let measured = try #require(ISO8601DateFormatter().date(from: "2027-01-14T10:00:00Z"))
        let original = try await store.setWeight(dayLocalDate: "2027-01-14", value: 70, unit: "kg", measuredAt: exactTime ? measured : nil, expectedRevision: nil, expectedProfileID: profile.id)
        var shifted = profile; shifted.timeZoneID = "America/Los_Angeles"
        try await store.updateProfile(shifted, expectedProfileID: profile.id)
        let sameDate = try await store.setWeight(dayLocalDate: "2027-01-14", value: 80, unit: "kg", measuredAt: nil, expectedRevision: nil, expectedProfileID: profile.id)
        #expect(original.revision == sameDate.revision && original.dayID != sameDate.dayID)
        let before = try await store.snapshotForExport()
        let corrected = try await store.updateWeight(id: original.id, value: 71, expectedRevision: original.revision, expectedProfileID: profile.id)
        var expected = original; expected.value = 71; expected.revision += 1
        #expect(corrected == expected)
        let saved = try await store.snapshotForExport()
        #expect(saved.weights.first { $0.id == sameDate.id } == sameDate)
        #expect(saved.days == before.days && saved.activeDayID == before.activeDayID)
        #expect(try await completeSelectedProfile(DiaryStore(directory: root), profile.id).weights.first { $0.id == original.id } == expected)
        await #expect(throws: DiaryError.staleRevision) { try await store.updateWeight(id: original.id, value: 72, expectedRevision: original.revision, expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.wrongOwner) { try await store.updateWeight(id: original.id, value: 72, expectedRevision: corrected.revision, expectedProfileID: UUID()) }
        await #expect(throws: DiaryError.notFound) { try await store.updateWeight(id: UUID(), value: 72, expectedRevision: corrected.revision, expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.invalidData) { try await store.updateWeight(id: original.id, value: .nan, expectedRevision: corrected.revision, expectedProfileID: profile.id) }
        #expect(try await store.snapshotForExport() == saved)
        try await store.deleteWeight(id: original.id, expectedRevision: corrected.revision, expectedProfileID: profile.id)
        let deleted = try await store.snapshotForExport()
        await #expect(throws: DiaryError.notFound) { try await store.updateWeight(id: original.id, value: 72, expectedRevision: corrected.revision, expectedProfileID: profile.id) }
        #expect(try await store.snapshotForExport() == deleted)
    }

    @Test func legacyWeightIDCorrectionKeepsUnlinkedMeasurement() async throws {
        let root = URL.temporaryDirectory.appending(path: "LegacyWeightCorrection-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var original = DiarySnapshot(profile: DiaryProfile(name: "Synthetic legacy weight"))
        let weight = WeightEntry(dayID: nil, measuredAt: morning, value: 154, unit: "lb")
        original.weights = [weight]
        let store = DiaryStore(directory: root)
        _ = try await store.importProfile(original)
        let corrected = try await store.updateWeight(id: weight.id, value: 153, expectedRevision: weight.revision, expectedProfileID: original.profile.id)
        var expected = weight; expected.value = 153; expected.revision += 1
        #expect(corrected == expected)
        let saved = try await store.snapshotForExport()
        #expect(saved.days.isEmpty && saved.activeDayID == nil)
        #expect(saved.weights == [expected])
    }

    @Test func selectedDayProgressWritesKeepStoredDayAndTimezoneAfterTravel() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let measured = try #require(ISO8601DateFormatter().date(from: "2027-01-14T10:00:00Z"))
        let historical = try await store.startDay(at: measured, expectedProfileID: profile.id)
        var shifted = profile; shifted.timeZoneID = "America/Los_Angeles"
        try await store.updateProfile(shifted, expectedProfileID: profile.id)
        let current = try await store.startDay(at: measured, expectedProfileID: profile.id)
        let currentWeight = try await store.recordWeight(value: 80, at: measured, expectedProfileID: profile.id)
        let before = try await store.snapshotForExport()
        #expect(historical.localDate == current.localDate && historical.id != current.id)
        let weight = try await store.setWeight(dayID: historical.id, value: 70, expectedRevision: nil, expectedProfileID: profile.id)
        let workout = try await store.createWorkout(dayID: historical.id, draft: WorkoutDraft(kind: .cardio, durationMinutes: 30, exercises: [], estimatedBurnKcal: nil, burnSource: nil), expectedProfileID: profile.id)
        #expect(weight.dayID == historical.id && workout.dayID == historical.id)
        #expect(weight.timePrecision == .dateOnly && workout.timePrecision == .dateOnly)
        #expect(weight.measuredAt == ProgressDate.date(historical.localDate, zone: historical.timeZoneID))
        #expect(workout.performedAt == weight.measuredAt)
        let corrected = try await store.setWeight(dayID: historical.id, value: 71, expectedRevision: weight.revision, expectedProfileID: profile.id)
        #expect(corrected.id == weight.id && corrected.measuredAt == weight.measuredAt && corrected.timePrecision == weight.timePrecision)
        let saved = try await store.snapshotForExport()
        #expect(saved.days == before.days && saved.activeDayID == current.id)
        #expect(saved.weights.first { $0.id == currentWeight.id } == currentWeight)
        await #expect(throws: DiaryError.staleRevision) { try await store.setWeight(dayID: historical.id, value: 72, expectedRevision: weight.revision, expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.notFound) { try await store.setWeight(dayID: UUID(), value: 72, expectedRevision: nil, expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.notFound) { try await store.createWorkout(dayID: UUID(), draft: WorkoutDraft(kind: .cardio, durationMinutes: 30, exercises: [], estimatedBurnKcal: nil, burnSource: nil), expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.wrongOwner) { try await store.setWeight(dayID: historical.id, value: 72, expectedRevision: corrected.revision, expectedProfileID: UUID()) }
        await #expect(throws: DiaryError.wrongOwner) { try await store.createWorkout(dayID: historical.id, draft: WorkoutDraft(kind: .cardio, durationMinutes: 30, exercises: [], estimatedBurnKcal: nil, burnSource: nil), expectedProfileID: UUID()) }
        #expect(try await store.snapshotForExport() == saved)
    }

    @Test func workoutsUseCurrentTimeZoneDayAfterProfileChange() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let originalDay = try await store.startDay(at: morning, expectedProfileID: profile.id)
        var shifted = profile; shifted.timeZoneID = "America/Los_Angeles"
        try await store.updateProfile(shifted, expectedProfileID: profile.id)
        let lateLocal = try #require(ISO8601DateFormatter().date(from: "2027-01-16T07:00:00Z"))
        let draft = WorkoutDraft(kind: .cardio, durationMinutes: 30, exercises: [], estimatedBurnKcal: nil, burnSource: nil)
        let recorded = try await store.createWorkout(localDate: "2027-01-15", draft: draft,
                                                      performedAt: lateLocal, expectedProfileID: profile.id)
        var edit = recorded; edit.durationMinutes = 35
        let corrected = try await store.updateWorkout(edit, expectedRevision: recorded.revision, expectedProfileID: profile.id)
        let dateOnly = try await store.createWorkout(localDate: "2027-01-15", draft: draft,
                                                      performedAt: nil, expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport()
        #expect(corrected.id == recorded.id && corrected.revision == 2 && corrected.performedAt == lateLocal)
        #expect(corrected.dayID == dateOnly.dayID && dateOnly.timePrecision == .dateOnly)
        #expect(corrected.dayID != originalDay.id)
        #expect(snapshot.days.first { $0.id == originalDay.id }?.timeZoneID == "Asia/Jerusalem")
        #expect(snapshot.days.first { $0.id == corrected.dayID }?.timeZoneID == "America/Los_Angeles")
    }

    @Test func separateWorkoutCallsCreateTwoSessionsForOneDay() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let draft = WorkoutDraft(kind: .strength, durationMinutes: 45,
            exercises: [WorkoutExercise(name: "Squat", sets: [WorkoutSet(repetitions: 5, loadKg: 40)])],
            estimatedBurnKcal: nil, burnSource: nil)
        let first = try await store.createWorkout(localDate: "2027-01-15", draft: draft, performedAt: nil, expectedProfileID: profile.id)
        let second = try await store.createWorkout(localDate: "2027-01-15", draft: draft, performedAt: nil, expectedProfileID: profile.id)
        #expect(first.id != second.id && first.dayID == second.dayID)
        #expect(first.timePrecision == .dateOnly && second.timePrecision == .dateOnly)
        #expect(try await completeSelectedProfile(DiaryStore(directory: root), profile.id).workouts.count == 2)
    }

    @Test func workoutEditAndDeleteRequireCurrentRevisionAndLeaveTombstone() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let draft = WorkoutDraft(kind: .cardio, durationMinutes: 30, exercises: [], estimatedBurnKcal: 200, burnSource: .userEstimate)
        let first = try await store.createWorkout(localDate: "2027-01-15", draft: draft, performedAt: morning, expectedProfileID: profile.id)
        var edit = first; edit.durationMinutes = 35
        let updated = try await store.updateWorkout(edit, expectedRevision: 1, expectedProfileID: profile.id)
        #expect(updated.id == first.id && updated.revision == 2 && updated.timePrecision == .exact)
        await #expect(throws: DiaryError.staleRevision) { try await store.deleteWorkout(id: first.id, expectedRevision: 1, expectedProfileID: profile.id) }
        try await store.deleteWorkout(id: first.id, expectedRevision: 2, expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.workouts.isEmpty && snapshot.deletedWorkoutIDs.contains(first.id))
        #expect(try await completeSelectedProfile(DiaryStore(directory: root), profile.id) == snapshot)
    }

    @Test func invalidNumbersAndForeignDayLeaveSnapshotUnchanged() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = try await store.snapshotForExport()
        await #expect(throws: DiaryError.invalidData) { try await store.setGoals(goal("2027-01-15", kcal: .infinity), expectedRevision: nil, expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.invalidData) { try await store.setWeight(dayLocalDate: "2027-02-30", value: 70, unit: "kg", measuredAt: nil, expectedRevision: nil, expectedProfileID: profile.id) }
        let badDuration = WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: [], estimatedBurnKcal: nil, burnSource: nil)
        await #expect(throws: DiaryError.invalidData) { try await store.createWorkout(localDate: "2027-01-15", draft: badDuration, performedAt: nil, expectedProfileID: profile.id) }
        let badLoad = WorkoutDraft(kind: .strength, durationMinutes: 30,
            exercises: [WorkoutExercise(name: "Squat", sets: [WorkoutSet(repetitions: 5, loadKg: -.infinity)])],
            estimatedBurnKcal: nil, burnSource: nil)
        await #expect(throws: DiaryError.invalidData) { try await store.createWorkout(localDate: "2027-01-15", draft: badLoad, performedAt: nil, expectedProfileID: profile.id) }
        let badBurn = WorkoutDraft(kind: .cardio, durationMinutes: 30, exercises: [], estimatedBurnKcal: -1, burnSource: .modelEstimate)
        await #expect(throws: DiaryError.invalidData) { try await store.createWorkout(localDate: "2027-01-15", draft: badBurn, performedAt: nil, expectedProfileID: profile.id) }
        let valid = WorkoutDraft(kind: .cardio, durationMinutes: 30, exercises: [], estimatedBurnKcal: nil, burnSource: nil)
        await #expect(throws: DiaryError.invalidData) { try await store.createWorkout(localDate: "2027-01-14", draft: valid, performedAt: morning, expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.invalidData) { try await store.setWeight(dayLocalDate: "2027-01-14", value: 70, unit: "kg", measuredAt: morning, expectedRevision: nil, expectedProfileID: profile.id) }
        #expect(try await store.snapshotForExport() == before)
    }

    @Test func sqliteCommitFailureChangesNoProgressRecord() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = try await store.snapshotForExport()
        let file = root.appendingPathComponent(profile.id.uuidString + ".sqlite").appendingPathComponent("diary.sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TRIGGER reject_progress BEFORE UPDATE ON storage_head BEGIN SELECT RAISE(ABORT, 'synthetic'); END", nil, nil, nil) == SQLITE_OK)
        await #expect(throws: DiaryError.persistenceFailed) { try await store.setGoals(goal("2027-01-15"), expectedRevision: nil, expectedProfileID: profile.id) }
        #expect(try await store.snapshotForExport() == before)
        #expect(try await completeSelectedProfile(DiaryStore(directory: root), profile.id) == before)
    }
}
