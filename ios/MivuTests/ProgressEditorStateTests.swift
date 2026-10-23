import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct ProgressEditorStateTests {
    @Test(arguments: ["2026-03-08", "2026-11-01"])
    func intakeChartDomainContainsWholeDaysAcrossDaylightSaving(endingOn: String) async throws {
        let zone = "America/Los_Angeles"
        let day = TrackingDay(localDate: endingOn, timeZoneID: zone, startAt: try #require(ProgressDate.date(endingOn, zone: zone)), completeness: .unknown)
        var snapshot = DiarySnapshot(profile: DiaryProfile(name: "Synthetic chart range", timeZoneID: zone))
        snapshot.days = [day]; snapshot.activeDayID = day.id
        let directory = URL.temporaryDirectory.appending(path: "ChartRange-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiaryStore(directory: directory)
        _ = try await store.importProfile(snapshot)
        let model = DiaryViewModel(store: store)
        await model.load(createDefaultProfile: false)
        let report = try await DiaryProgressView.loadProgress(model: model, endingOn: endingOn, days: ProgressRange.week.days)
        let buckets = ProgressInsights.buckets(report.dailyReports ?? [], range: .week, zone: zone)
        let spring = endingOn == "2026-03-08"
        let formatter = ISO8601DateFormatter()
        // Seven whole local days, each bar starting at its own local midnight across the clock change.
        #expect(buckets.count == 7)
        #expect(buckets.first?.start == formatter.date(from: spring ? "2026-03-02T08:00:00Z" : "2026-10-26T07:00:00Z"))
        #expect(buckets.last?.start == formatter.date(from: spring ? "2026-03-08T08:00:00Z" : "2026-11-01T07:00:00Z"))
    }

    @Test(arguments: [false, true], [false, true])
    func chartAndReportSelectHighestRevisionOnTiedMeasurementTime(legacy: Bool, reverse: Bool) async throws {
        var snapshot = tiedWeightSnapshot()
        let measured = ISO8601DateFormatter().date(from: "2026-01-08T00:30:00Z")!
        let higher = WeightEntry(dayID: legacy ? nil : snapshot.days[0].id, measuredAt: measured, value: 70, revision: 2)
        let lower = WeightEntry(dayID: legacy ? nil : snapshot.days[1].id, measuredAt: measured, value: 80, revision: 1)
        snapshot.weights = reverse ? [lower, higher] : [higher, lower]
        try snapshot.validate()
        try await assertChartAndReport(snapshot, expectedKg: 70)
    }

    @Test(arguments: [false, true], [false, true])
    func equalRevisionTieKeepsFirstEntryInChartAndReport(legacy: Bool, reverse: Bool) async throws {
        var snapshot = tiedWeightSnapshot()
        let measured = ISO8601DateFormatter().date(from: "2026-01-08T00:30:00Z")!
        let first = WeightEntry(dayID: legacy ? nil : snapshot.days[0].id, measuredAt: measured, value: 70, revision: 2)
        let second = WeightEntry(dayID: legacy ? nil : snapshot.days[1].id, measuredAt: measured, value: 80, revision: 2)
        snapshot.weights = reverse ? [second, first] : [first, second]
        try snapshot.validate()
        try await assertChartAndReport(snapshot, expectedKg: reverse ? 80 : 70)
    }

    private func tiedWeightSnapshot() -> DiarySnapshot {
        let measured = ISO8601DateFormatter().date(from: "2026-01-08T00:30:00Z")!
        var snapshot = DiarySnapshot(profile: DiaryProfile(name: "Synthetic tied weights", timeZoneID: "America/Los_Angeles"))
        // The linked travel date stays authoritative; legacy nil-day entries use the profile zone.
        snapshot.days = [
            TrackingDay(localDate: "2026-01-07", timeZoneID: "Asia/Jerusalem", startAt: measured, completeness: .unknown),
            TrackingDay(localDate: "2026-01-07", timeZoneID: "America/Los_Angeles", startAt: measured, completeness: .unknown)
        ]
        snapshot.activeDayID = snapshot.days[1].id
        return snapshot
    }

    private func assertChartAndReport(_ snapshot: DiarySnapshot, expectedKg: Double) async throws {
        let directory = URL.temporaryDirectory.appending(path: "ProgressTie-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiaryStore(directory: directory)
        _ = try await store.importProfile(snapshot)
        let model = DiaryViewModel(store: store)
        await model.load(createDefaultProfile: false)
        let bounded = try await DiaryProgressView.loadProgress(model: model, endingOn: "2026-01-07", days: 30)
        let year = try await DiaryProgressView.loadProgress(model: model, endingOn: "2026-01-07", days: ProgressRange.year.days)
        #expect(year.dailyReports?.count == 365 && year.displayWeights == bounded.displayWeights)
        let chart = DiaryProgressView.weightObservations(progress: bounded, zone: snapshot.profile.timeZoneID)
        let report = bounded.weight
        #expect(chart.count == 1)
        #expect(chart.first?.label == "2026-01-07")
        #expect(chart.first?.value == expectedKg)
        #expect(report.currentSevenDayAverageKg == expectedKg)
        #expect(report.currentSevenDayObservedCount == 1)
        #expect(report.changeFromSevenDaysAgoKg == nil)
    }

    /// Switching range keeps the last report on screen until the new one loads; another profile's or day's report is never shown.
    @Test func rangeSwitchKeepsTheLastReportWhileLoading() {
        let owner = DiarySelectionOwnership(identity: CoachTimelineIdentity(profileID: UUID(), timelineGeneration: UUID()), selectionEpoch: 1)
        let other = DiarySelectionOwnership(identity: CoachTimelineIdentity(profileID: UUID(), timelineGeneration: UUID()), selectionEpoch: 1)
        let week = DiaryProgressView.ReportRequest(ownership: owner, generation: 1, date: "2026-10-23", range: .week)
        #expect(DiaryProgressView.shows(loaded: week, for: DiaryProgressView.ReportRequest(ownership: owner, generation: 1, date: "2026-10-23", range: .month)))
        #expect(!DiaryProgressView.shows(loaded: nil, for: week))
        #expect(!DiaryProgressView.shows(loaded: week, for: DiaryProgressView.ReportRequest(ownership: other, generation: 1, date: "2026-10-23", range: .week)))
        #expect(!DiaryProgressView.shows(loaded: week, for: DiaryProgressView.ReportRequest(ownership: owner, generation: 1, date: "2026-10-24", range: .week)))
    }

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

    @Test func editedGoalFieldsRequireConfirmationBeforeLoadingAnotherDate() {
        var snapshot = DiarySnapshot(profile: DiaryProfile(name: "Synthetic goal date draft"))
        snapshot.goals = [GoalRecord(effectiveLocalDate: "2026-01-01", timeZoneID: snapshot.profile.timeZoneID, targets: NutritionValues(kcal: 1800), goalWeightKg: nil, exerciseCreditEnabled: false)]
        var saved = GoalEditorValues(snapshot: snapshot, localDate: "2026-01-01")
        #expect(!saved.hasEditedTargets)
        saved.kcal = "1900"
        #expect(saved.hasEditedTargets)
        var blank = GoalEditorValues(snapshot: snapshot, localDate: "2026-02-01")
        #expect(!blank.hasEditedTargets)
        blank.protein = "100"
        #expect(blank.hasEditedTargets)
        blank.protein = ""
        blank.exerciseCredit = true
        #expect(blank.hasEditedTargets)
        #expect(saved.kcal == "1900" && saved.localDate == "2026-01-01")
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
        var values = GoalEditorValues(snapshot: try await store.snapshotForExport(), localDate: "2026-02-01")
        values.kcal = ""
        #expect(values.valid)
        let cleared = try await store.setGoals(values.record(zone: profile.timeZoneID), expectedRevision: values.expectedRevision, expectedProfileID: profile.id)
        var snapshot = try await store.snapshotForExport()
        #expect(ProgressAnalytics.daily(snapshot: snapshot, localDate: "2026-01-15").goal?.targets.kcal == 1800)
        #expect(ProgressAnalytics.daily(snapshot: snapshot, localDate: "2026-02-15").goal?.targets.kcal == nil)
        #expect(ProgressAnalytics.daily(snapshot: snapshot, localDate: "2026-02-15").remainingFromRecorded.kcal == nil)
        values.kcal = "2000"
        _ = try await store.setGoals(values.record(zone: profile.timeZoneID), expectedRevision: cleared.revision, expectedProfileID: profile.id)
        let later = GoalEditorValues(snapshot: try await store.snapshotForExport(), localDate: "2026-03-01")
        #expect(later.valid)
        _ = try await store.setGoals(later.record(zone: profile.timeZoneID), expectedRevision: later.expectedRevision, expectedProfileID: profile.id)
        snapshot = try await store.snapshotForExport()
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
        let snapshot = try await store.snapshotForExport()
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
        #expect(try await store.snapshotForExport().goals.first { $0.id == older.id }?.targets.kcal == 1_900)
    }
}
