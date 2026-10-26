import Foundation
import Testing
@testable import Mivu

@Suite struct WidgetSnapshotTests {
    let sample = WidgetSnapshot(day: "2026-10-20", eaten: 1359.6, target: 2000, hasDiary: true,
                                rolloverAt: Date(timeIntervalSince1970: 1_000), writtenAt: Date(timeIntervalSince1970: 0))

    @Test func roundTripsThroughFile() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "widget-snapshot.json")
        for _ in 0..<2 { try sample.write(to: url) }
        #expect(WidgetSnapshot.read(from: url) == sample)
        #expect(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func missingOrCorruptFileReadsNil() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        #expect(WidgetSnapshot.read(from: url) == nil)
        try Data("{".utf8).write(to: url)
        #expect(WidgetSnapshot.read(from: url) == nil)
    }

    @Test func ringCapsWhenOverTargetAndIsEmptyWithoutTarget() {
        var snapshot = sample; snapshot.eaten = 2300
        #expect(snapshot.ringFraction == 1)
        snapshot.target = nil
        #expect(snapshot.ringFraction == 0)
    }

    @Test func afterRolloverKeepsTargetAndZeroesEaten() {
        let next = sample.afterRollover()
        #expect(next.eaten == 0 && next.target == 2000 && next.hasDiary)
    }

    @Test func rolloverUsesTheDaysTimeZone() throws {
        // 23:00 UTC on the 20th is 02:00 on the 21st in Jerusalem; the next 4 AM there is 01:00 UTC on the 21st.
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-20T23:00:00Z"))
        let next = WidgetSnapshot.nextRollover(after: now, timeZoneID: "Asia/Jerusalem", cutoffHour: 4)
        #expect(next == ISO8601DateFormatter().date(from: "2026-10-21T01:00:00Z"))
    }
}

@Suite struct WidgetSnapshotWriterTests {
    @Test func noSelectedDiaryMeansSetUp() {
        let snapshot = WidgetSnapshot(readModel: nil, now: .now, cutoffHour: 4)
        #expect(!snapshot.hasDiary && snapshot.eaten == 0 && snapshot.target == nil)
    }

    @Test func snapshotMatchesTodaysReport() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-20T05:00:00Z"))
        let day = TrackingDay(localDate: "2026-10-20", timeZoneID: "Asia/Jerusalem", startAt: start)
        let meal = MealReadModel(id: UUID(), dayID: day.id, capturedAt: start, eatenAt: start, revision: 1, timePrecision: nil,
                                 items: [FoodItem(name: "Synthetic bowl", nutrition: NutritionValues(kcal: 1360))],
                                 submissions: [], photos: [], sourceTurnID: nil)
        let goal = GoalRecord(effectiveLocalDate: "2026-10-01", timeZoneID: "Asia/Jerusalem", targets: NutritionValues(kcal: 2000),
                              goalWeightKg: nil, exerciseCreditEnabled: false)
        let head = DiaryHead(profile: adultProfile(name: "Synthetic widget", timeZoneID: "Asia/Jerusalem"), revision: 1,
                             lineage: nil, activeDayID: day.id, previousDayConfirmedAt: nil, timelineGeneration: UUID())
        let model = DiaryReadModel(head: head, activeDay: day, meals: [meal], weight: nil, workouts: [], activeGoal: goal, pendingAnalysisCount: 0)
        let snapshot = WidgetSnapshot(readModel: model, now: start, cutoffHour: 4)
        let report = ProgressAnalytics.daily(readModel: model)
        #expect(snapshot.hasDiary && snapshot.day == "2026-10-20")
        #expect(snapshot.eaten == 1360 && snapshot.eaten == report.foodTotals?.kcal)
        #expect(snapshot.target == 2000)
        #expect(snapshot.rolloverAt == WidgetSnapshot.nextRollover(after: start, timeZoneID: "Asia/Jerusalem", cutoffHour: 4))
    }

    @Test func dayStillOpenAfterTheCutoffRollsOverImmediately() throws {
        // Yesterday's day started at 05:00 UTC; a write at 06:00 UTC today must not keep it until tomorrow's cutoff.
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-20T05:00:00Z"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-21T06:00:00Z"))
        let day = TrackingDay(localDate: "2026-10-20", timeZoneID: "UTC", startAt: start)
        let head = DiaryHead(profile: adultProfile(name: "Synthetic widget", timeZoneID: "UTC"), revision: 1,
                             lineage: nil, activeDayID: day.id, previousDayConfirmedAt: nil, timelineGeneration: UUID())
        let model = DiaryReadModel(head: head, activeDay: day, meals: [], weight: nil, workouts: [], activeGoal: nil, pendingAnalysisCount: 0)
        let snapshot = WidgetSnapshot(readModel: model, now: now, cutoffHour: 4)
        #expect(snapshot.rolloverAt <= now)
    }
}
