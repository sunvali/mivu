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
        let trend = [point(label(0), 80), point(label(7), 79.75), point(label(14), 79.5), point(label(28), 79)]
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

    // MARK: Review fixes

    @Test func partialAndPendingDaysGetNoBandAndStayOutOfTheHeadline() {
        let complete = day("2026-10-21", kcal: 2100)
        var partial = day("2026-10-22", kcal: 400)
        partial = DailyProgress(localDate: partial.localDate, completeness: .partial, hasPending: false, foodTotals: partial.foodTotals, goal: partial.goal,
                                remainingFromRecorded: NutritionValues(), workoutCount: 0, estimatedBurnKcal: nil, exerciseAdjustedKcalRemaining: nil)
        var pending = day("2026-10-23", kcal: 300)
        pending = DailyProgress(localDate: pending.localDate, completeness: .complete, hasPending: true, foodTotals: pending.foodTotals, goal: pending.goal,
                                remainingFromRecorded: NutritionValues(), workoutCount: 0, estimatedBurnKcal: nil, exerciseAdjustedKcalRemaining: nil)
        #expect(ProgressInsights.band(complete) == .near)
        #expect(ProgressInsights.band(partial) == nil && ProgressInsights.band(pending) == nil)
        #expect(ProgressInsights.headline(trend: [], goalWeightKg: nil, startKg: nil, days: [complete, partial, pending]) == .caloriesOnTrack(near: 1, logged: 1))
        let buckets = ProgressInsights.buckets([partial], range: .week, zone: "UTC")
        #expect(buckets.first?.averageKcal == 400 && buckets.first?.band == nil && buckets.first?.complete == false)
    }

    @Test func steadyLossReadsOnTrackDespiteTheSmoothedLag() {
        // 0.25 kg a week, weighed daily: the lagging EMA alone would read "holding steady".
        let weights = (0...7).map { weight(label($0), 80 - 0.25 / 7 * Double($0)) }
        #expect(ProgressInsights.headline(trend: WeightTrend.points(weights), goalWeightKg: 75, startKg: 80, days: []) == .onTrack)
    }

    @Test func burnUsesTheWeighInSlopeNotTheLaggingTrend() throws {
        // 0.5 kg a week over 14 complete days at 2,100 kcal → ~2,650 kcal burn.
        let weights = (0...14).map { weight(label($0), 80 - 0.5 / 7 * Double($0)) }
        guard case let .estimate(estimate) = ProgressInsights.burn(days: loggedDays(14), trend: WeightTrend.points(weights)) else { Issue.record("Expected an estimate"); return }
        #expect(abs(estimate.kcalPerDay - (2100 + 0.5 / 7 * 7700)) < 5)
    }

    @Test func proteinStreakIgnoresTodayWhileItIsUnfinished() {
        var days = (0..<5).map { day(label($0), kcal: 2000, protein: 150, proteinTarget: 140) }
        days.append(day(label(5), kcal: 600, protein: 30, proteinTarget: 140))
        #expect(ProgressInsights.wins(days: days, weighIns: 0, today: label(5)).first?.title == "Protein goal 5 days running")
    }

    @Test func weekShowsSevenDaysButJudgesBurnAndWeightOnTheLoadedMonth() {
        let days = loggedDays(30)
        let weights = (0..<30).filter { $0.isMultiple(of: 2) }.map { weight(label($0), 80 - 0.5 / 7 * Double($0)) }
        let weekly = WeightProgress(endLocalDate: label(29), currentSevenDayAverageKg: nil, currentSevenDayObservedCount: 0,
                                    changeFromSevenDaysAgoKg: nil, changeFromThirtyDaysAgoKg: nil, plateau: .insufficientData)
        let progress = CoachProgress(startLocalDate: label(0), endLocalDate: label(29), daily: days[29], period: nil, weight: weekly,
                                     weights: [], workouts: [], omittedWeightCount: 0, omittedWorkoutCount: 0, truncated: false,
                                     dailyReports: days, displayWeights: weights)
        let snapshot = ProgressSnapshot(progress: progress, range: .week, zone: "UTC", today: label(29))
        #expect(snapshot.days.count == 7 && snapshot.days.first?.localDate == label(23))
        guard case .estimate = snapshot.burn else { Issue.record("A week view with a logged month shows a burn"); return }
    }

    @Test func weekEvidenceQuotesTheSameWindowAsTheVerdict() {
        let goal = GoalRecord(effectiveLocalDate: label(0), timeZoneID: "UTC", targets: NutritionValues(kcal: 2100), goalWeightKg: 75, exerciseCreditEnabled: false)
        let days = loggedDays(30).map { DailyProgress(localDate: $0.localDate, completeness: .complete, hasPending: false, foodTotals: $0.foodTotals, goal: goal,
                                                      remainingFromRecorded: NutritionValues(), workoutCount: 0, estimatedBurnKcal: nil, exerciseAdjustedKcalRemaining: nil) }
        // Down over the month, up a little in the last week.
        let weights = (0..<30).filter { $0.isMultiple(of: 2) }.map { weight(label($0), $0 < 24 ? 80 - 0.06 * Double($0) : 78.9) }
        let weekly = WeightProgress(endLocalDate: label(29), currentSevenDayAverageKg: nil, currentSevenDayObservedCount: 0,
                                    changeFromSevenDaysAgoKg: nil, changeFromThirtyDaysAgoKg: nil, plateau: .insufficientData)
        let progress = CoachProgress(startLocalDate: label(0), endLocalDate: label(29), daily: days[29], period: nil, weight: weekly, weights: [], workouts: [],
                                     omittedWeightCount: 0, omittedWorkoutCount: 0, truncated: false, dailyReports: days, displayWeights: weights)
        let snapshot = ProgressSnapshot(progress: progress, range: .week, zone: "UTC", today: label(29))
        #expect(snapshot.headline == .onTrack)
        #expect(snapshot.shortEvidence.hasPrefix("Down") && snapshot.shortEvidence.hasSuffix("kg in 30 days"), "\(snapshot.shortEvidence)")
    }

    // MARK: Plain language

    @Test func dayResultsReadInPlainWords() {
        #expect(ProgressInsights.plainResult(day("2026-10-20", kcal: 2100)) == "2,100 kcal · on target")
        #expect(ProgressInsights.plainResult(day("2026-10-20", kcal: 2420)) == "2,420 kcal · 320 over")
        #expect(ProgressInsights.plainResult(day("2026-10-20", kcal: 1550)) == "1,550 kcal · 550 under")
        #expect(ProgressInsights.plainResult(day("2026-10-20", kcal: nil)) == "No log")
        #expect(ProgressInsights.plainResult(day("2026-10-20", kcal: 1800, target: nil)) == "1,800 kcal")
    }

    @Test func goalGapReadsInPlainWords() {
        #expect(ProgressInsights.plainGap(2296, goal: 2100) == "on target")
        #expect(ProgressInsights.plainGap(2500, goal: 2100) == "400 over")
        #expect(ProgressInsights.plainGap(1700, goal: 2100) == "400 under")
    }

    @Test func shortEvidenceIsOneShortLine() {
        let days = [day("2026-10-21", kcal: 2100), day("2026-10-22", kcal: 2150), day("2026-10-23", kcal: 3000)]
        let weekly = WeightProgress(endLocalDate: "2026-10-23", currentSevenDayAverageKg: nil, currentSevenDayObservedCount: 0,
                                    changeFromSevenDaysAgoKg: nil, changeFromThirtyDaysAgoKg: nil, plateau: .insufficientData)
        let progress = CoachProgress(startLocalDate: "2026-10-21", endLocalDate: "2026-10-23", daily: days[2], period: nil, weight: weekly, weights: [], workouts: [],
                                     omittedWeightCount: 0, omittedWorkoutCount: 0, truncated: false, dailyReports: days, displayWeights: [])
        #expect(ProgressSnapshot(progress: progress, range: .week, zone: "UTC", today: "2026-10-23").shortEvidence == "2 of 3 days near your target")
    }

    @Test func macroLinesReadInPlainWords() {
        #expect(ProgressInsights.plainMacro(215, goal: 140) == "215 g a day · 75 g over goal")
        #expect(ProgressInsights.plainMacro(100, goal: 140) == "100 g a day · 40 g under goal")
        #expect(ProgressInsights.plainMacro(145, goal: 140) == "145 g a day · on goal")
        #expect(ProgressInsights.plainMacro(nil, goal: 140) == "No complete days")
        #expect(ProgressInsights.plainMacro(80, goal: nil) == "80 g a day")
    }

    @Test func calendarRowsAreWeeksOfDotsThenMonthsOfCounts() {
        // Thu 2026-10-15 … Wed 2026-10-21: one partial week and the start of the next, newest first.
        let days = range(endingOn: "2026-10-21", days: 7) { $0 == 2 ? nil : 2100 }
        let weeks = ProgressInsights.calendarRows(days, range: .week, zone: "UTC")
        #expect(weeks.map(\.title) == ["Oct 19 – 25", "Oct 12 – 18"])
        #expect(weeks[1].dots == [.outside, .outside, .outside, .logged(.near), .logged(.near), .logged(.near), .logged(.near)])
        #expect(weeks[0].dots?.prefix(3) == [.noLog, .logged(.near), .logged(.near)] && weeks[0].logged == 2 && weeks[0].total == 3)
        let months = ProgressInsights.calendarRows(range(endingOn: "2026-10-21", days: 91), range: .quarter, zone: "UTC")
        #expect(months.first?.title == "October 2026" && months.first?.dots == nil && months.first?.total == 21)
    }

    @Test func headlineNotEnoughDataWithNothingLogged() {
        #expect(ProgressInsights.headline(trend: [], goalWeightKg: 75, startKg: nil, days: [day("2026-10-23", kcal: nil)]) == .notEnoughData)
    }
}
