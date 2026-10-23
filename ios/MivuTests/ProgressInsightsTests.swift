import Foundation
import Testing
@testable import Mivu

@Suite struct ProgressInsightsTests {
    @Test func bandsByDistanceFromTarget() {
        #expect(ProgressBand.of(kcal: 2310, target: 2100) == .near)
        #expect(ProgressBand.of(kcal: 1680, target: 2100) == .bitOff)
        #expect(ProgressBand.of(kcal: 2835, target: 2100) == .off)
        #expect(ProgressBand.of(kcal: 2836, target: 2100) == .farOff)
    }

    @Test func unknownKcalHasNoBand() {
        #expect(ProgressBand.of(kcal: nil, target: 2100) == nil)
        #expect(ProgressBand.of(kcal: 1800, target: nil) == nil)
        #expect(ProgressBand.of(kcal: 1800, target: 0) == nil)
    }

    @Test func bandUsesEachDaysOwnGoal() {
        #expect(ProgressBand.of(kcal: 2000, target: 2000) == .near)
        #expect(ProgressBand.of(kcal: 2000, target: 1500) == .off)
    }

    // MARK: Weight trend and headline

    private func weight(_ label: String, _ value: Double, unit: String = "kg") -> CoachWeightReference {
        CoachWeightReference(localDate: label, record: WeightEntry(measuredAt: ProgressDate.date(label, zone: "UTC")!, value: value, unit: unit))
    }
    private func point(_ label: String, _ trend: Double) -> TrendPoint { TrendPoint(localDate: label, raw: trend, trend: trend) }
    private func day(_ label: String, kcal: Double?, target: Double? = 2100, protein: Double? = nil, proteinTarget: Double? = nil) -> DailyProgress {
        let goal = GoalRecord(effectiveLocalDate: "2026-01-01", timeZoneID: "UTC",
                              targets: NutritionValues(kcal: target, protein: proteinTarget), goalWeightKg: nil, exerciseCreditEnabled: false)
        return DailyProgress(localDate: label, completeness: kcal == nil ? nil : .complete, hasPending: false,
                             foodTotals: kcal.map { NutritionTotals(kcal: $0, carbs: nil, protein: protein, fat: nil, unknownItemCount: 0) },
                             goal: goal, remainingFromRecorded: NutritionValues(), workoutCount: 0, estimatedBurnKcal: nil, exerciseAdjustedKcalRemaining: nil)
    }
    private let weekTrend = ["2026-10-16", "2026-10-19", "2026-10-23"]

    @Test func trendWeightsByElapsedDays() throws {
        let points = WeightTrend.points([weight("2026-09-01", 80), weight("2026-09-22", 78)])
        let last = try #require(points.last)
        #expect(abs(last.trend - (80 + (78 - 80) * (1 - pow(0.9, 21)))) < 0.01)
        #expect(abs(last.trend - 78.22) < 0.01)
    }

    @Test func trendConvertsPounds() throws {
        let first = try #require(WeightTrend.points([weight("2026-09-01", 176.37, unit: "lb")]).first)
        #expect(abs(first.raw - 80.0) < 0.01)
    }

    @Test func headlineOnTrackWhenTrendMovesTowardGoal() {
        let trend = [point(weekTrend[0], 79.6), point(weekTrend[1], 79.3), point(weekTrend[2], 79.0)]
        #expect(ProgressInsights.headline(trend: trend, goalWeightKg: 75, startKg: 80, days: []) == .onTrack)
    }

    @Test func headlineHoldingWhenMoveUnderTenthKgPerWeek() {
        let trend = [point(weekTrend[0], 79.60), point(weekTrend[1], 79.58), point(weekTrend[2], 79.55)]
        #expect(ProgressInsights.headline(trend: trend, goalWeightKg: 75, startKg: 80, days: []) == .holdingSteady)
    }

    @Test func headlineDriftingWhenMovingAway() {
        let trend = [point(weekTrend[0], 79.0), point(weekTrend[1], 79.1), point(weekTrend[2], 79.3)]
        #expect(ProgressInsights.headline(trend: trend, goalWeightKg: 75, startKg: 80, days: []) == .drifting)
    }

    @Test func headlineAtGoalWithinOneKg() {
        let trend = [point(weekTrend[0], 76.2), point(weekTrend[1], 76.0), point(weekTrend[2], 75.8)]
        #expect(ProgressInsights.headline(trend: trend, goalWeightKg: 75, startKg: 80, days: []) == .atGoal)
    }

    @Test func headlineFallsBackToCaloriesWithoutGoalWeight() {
        let trend = [point(weekTrend[0], 79.6), point(weekTrend[1], 79.3), point(weekTrend[2], 79.0)]
        let days = [day("2026-10-17", kcal: 2050), day("2026-10-18", kcal: 2180), day("2026-10-19", kcal: 1890),
                    day("2026-10-20", kcal: 2420), day("2026-10-21", kcal: nil), day("2026-10-22", kcal: 1550), day("2026-10-23", kcal: 1980)]
        #expect(ProgressInsights.headline(trend: trend, goalWeightKg: nil, startKg: nil, days: days) == .caloriesOnTrack(near: 4, logged: 6))
    }

    @Test func headlineFallsBackWhenTooFewWeighIns() {
        let trend = [point("2026-10-16", 79.6), point("2026-10-23", 79.0)]
        let days = [day("2026-10-22", kcal: 3000), day("2026-10-23", kcal: 2100)]
        #expect(ProgressInsights.headline(trend: trend, goalWeightKg: 75, startKg: 80, days: days) == .caloriesOff(near: 1, logged: 2))
    }

    // MARK: Burn and wins

    private func label(_ offset: Int) -> String { ProgressDate.label(ProgressDate.date("2026-09-01", zone: "UTC")!.addingTimeInterval(Double(offset) * 86_400), zone: "UTC") }
    private func loggedDays(_ count: Int, kcal: Double = 2100) -> [DailyProgress] { (0..<count).map { day(label($0), kcal: kcal) } }

    @Test func burnNeedsFourteenCompleteDaysAndFourWeighIns() {
        let trend = [point(label(0), 80), point(label(10), 79.8), point(label(20), 79.6)]
        #expect(ProgressInsights.burn(days: loggedDays(10), trend: trend) == .needs(days: 4, weighIns: 1))
    }

    @Test func burnFromIntakeAndTrend() throws {
        let trend = [point(label(0), 80), point(label(9), 79.7), point(label(19), 79.3), point(label(28), 79)]
        guard case let .estimate(estimate) = ProgressInsights.burn(days: loggedDays(28), trend: trend) else { Issue.record("Expected an estimate"); return }
        #expect(abs(estimate.kcalPerDay - (2100 + 7700.0 / 28)) < 1)
    }

    @Test func burnBandNarrowsWithMoreDays() {
        let trend = [point(label(0), 80), point(label(10), 79.7), point(label(20), 79.3), point(label(30), 79)]
        guard case let .estimate(early) = ProgressInsights.burn(days: loggedDays(14), trend: trend),
              case let .estimate(late) = ProgressInsights.burn(days: loggedDays(30), trend: trend) else { Issue.record("Expected estimates"); return }
        #expect(early.band > late.band)
        #expect(late.band == 100)
    }

    @Test func winsPreferProteinRunThenLoggingThenWeighIns() {
        let days = (0..<6).map { day(label($0), kcal: 2000, protein: $0 >= 2 ? 150 : 80, proteinTarget: 140) }
        #expect(ProgressInsights.wins(days: days, weighIns: 5).map(\.id) == ["protein-run", "logged-days", "weigh-ins"])
        #expect(ProgressInsights.wins(days: days, weighIns: 5).first?.title == "Protein goal 4 days running")
    }

    @Test func noWinsWhenNothingQualifies() {
        #expect(ProgressInsights.wins(days: [day(label(0), kcal: 2000)], weighIns: 0).isEmpty)
    }

    // MARK: Buckets

    private func range(endingOn end: String, days: Int, kcal: (Int) -> Double? = { _ in 2000 }) -> [DailyProgress] {
        let last = ProgressDate.date(end, zone: "UTC")!
        return (0..<days).reversed().map { back in
            day(ProgressDate.label(last.addingTimeInterval(Double(-back) * 86_400), zone: "UTC"), kcal: kcal(back))
        }
    }

    @Test func weekAndMonthBucketPerDay() {
        #expect(ProgressInsights.buckets(range(endingOn: "2026-10-22", days: 7), range: .week, zone: "UTC").count == 7)
        #expect(ProgressInsights.buckets(range(endingOn: "2026-10-22", days: 30), range: .month, zone: "UTC").count == 30)
    }

    @Test func quarterBucketsByMondayWeek() throws {
        let buckets = ProgressInsights.buckets(range(endingOn: "2026-10-22", days: 91), range: .quarter, zone: "UTC")
        #expect(buckets.count == 14)
        #expect(ProgressDate.label(try #require(buckets.first).start, zone: "UTC") == "2026-07-20")
        #expect(buckets.first?.loggedDays == 3) // Fri 24 – Sun 26 July
    }

    @Test func yearBucketsByMonth() throws {
        let buckets = ProgressInsights.buckets(range(endingOn: "2026-10-22", days: 365), range: .year, zone: "UTC")
        #expect(buckets.count == 13)
        #expect(ProgressDate.label(try #require(buckets.first).start, zone: "UTC") == "2025-10-01")
    }

    @Test func bucketsSkipMissingDaysNotZero() {
        let days = range(endingOn: "2026-10-22", days: 14) { $0 >= 7 ? nil : 2100 }
        let buckets = ProgressInsights.buckets(days, range: .quarter, zone: "UTC")
        let empty = buckets.filter { $0.loggedDays == 0 }
        #expect(!empty.isEmpty && empty.allSatisfy { $0.averageKcal == nil && $0.band == nil })
        #expect(buckets.last?.averageKcal == 2100 && buckets.last?.band == .near)
    }

    @Test func headlineNotEnoughDataWithNothingLogged() {
        #expect(ProgressInsights.headline(trend: [], goalWeightKg: 75, startKg: nil, days: [day("2026-10-23", kcal: nil)]) == .notEnoughData)
    }
}
