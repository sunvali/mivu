import Foundation
import Testing
@testable import Mivu

@Suite struct ProgressAnalyticsTests {
    private func date(_ label: String, hour: String = "12:00:00") -> Date {
        ISO8601DateFormatter().date(from: "\(label)T\(hour)Z")!
    }

    private func snapshot(zone: String = "UTC") -> DiarySnapshot {
        DiarySnapshot(profile: DiaryProfile(name: "Synthetic progress", timeZoneID: zone))
    }

    private func day(_ label: String, _ coverage: DayCompleteness, zone: String = "UTC") -> TrackingDay {
        TrackingDay(localDate: label, timeZoneID: zone, startAt: date(label), completeness: coverage)
    }

    private func meal(_ day: TrackingDay, kcal: Double?, carbs: Double? = 10,
                      protein: Double? = 5, fat: Double? = 2) -> DiaryMeal {
        DiaryMeal(dayID: day.id, capturedAt: day.startAt, eatenAt: day.startAt, revision: 1,
                  items: [FoodItem(name: "Synthetic food", nutrition: NutritionValues(kcal: kcal, carbs: carbs,
                                                                                           protein: protein, fat: fat))])
    }

    private func goal(_ label: String, kcal: Double = 100, credit: Bool = false) -> GoalRecord {
        GoalRecord(effectiveLocalDate: label, timeZoneID: "UTC",
                   targets: NutritionValues(kcal: kcal, carbs: 20, protein: 10, fat: 5),
                   goalWeightKg: nil, exerciseCreditEnabled: credit)
    }

    private func workout(_ day: TrackingDay, burn: Double?) -> WorkoutSession {
        WorkoutSession(dayID: day.id, performedAt: day.startAt, timePrecision: .dateOnly,
                       revision: 1, kind: .cardio, durationMinutes: 30, exercises: [],
                       estimatedBurnKcal: burn, burnSource: burn == nil ? nil : .userEstimate)
    }

    private func weight(_ day: TrackingDay, value: Double, unit: String = "kg", hour: String = "12:00:00") -> WeightEntry {
        WeightEntry(dayID: day.id, measuredAt: date(day.localDate, hour: hour), value: value, unit: unit)
    }

    @Test func closedDaysCountWhileOpenAndSkippedDaysStayOutOfStatistics() {
        var data = snapshot()
        let closed = day("2026-01-02", .partial), skipped = day("2026-01-03", .untracked)
        let empty = day("2026-01-04", .complete), open = day("2026-01-05", .unknown)
        data.days = [closed, skipped, empty, open]
        data.activeDayID = open.id
        data.goals = [goal("2026-01-01", kcal: 500)]
        var analyzing = DiaryMeal(dayID: closed.id, capturedAt: closed.startAt, eatenAt: closed.startAt)
        analyzing.submissions = [MealSubmission(baseRevision: 0, text: "Synthetic capture", photoIDs: [], reviewFirst: false, state: .analyzing)]
        data.meals = [meal(closed, kcal: 500), analyzing, meal(skipped, kcal: 900), meal(open, kcal: 300)]
        let status = { ProgressAnalytics.daily(snapshot: data, localDate: $0).status }
        #expect(status(closed.localDate) == .closed)
        #expect(status(skipped.localDate) == .skipped)
        #expect(status(empty.localDate) == .skipped)
        #expect(status(open.localDate) == .open)
        #expect(status("2026-01-01") == nil)
        let period = ProgressAnalytics.period(snapshot: data, endingOn: open.localDate, days: 7)
        #expect(period.averageIntake.kcal == 500)
        #expect(period.closedDayCount == 1 && period.skippedDayCount == 2 && period.missingDayCount == 3)
        #expect(period.adherenceNumerator == 1 && period.adherenceDenominator == 1)
    }

    @Test func emptyClosedDayIsSkippedAndAbsentDayIsMissing() {
        var data = snapshot()
        let empty = day("2026-01-02", .complete)
        data.days = [empty]
        data.goals = [goal("2026-01-01")]
        var analyzing = DiaryMeal(dayID: empty.id, capturedAt: empty.startAt, eatenAt: empty.startAt)
        analyzing.submissions = [MealSubmission(baseRevision: 0, text: "Synthetic capture", photoIDs: [], reviewFirst: false, state: .captured)]
        data.meals = [analyzing]
        #expect(ProgressAnalytics.daily(snapshot: data, localDate: empty.localDate).status == .skipped)
        let missing = ProgressAnalytics.daily(snapshot: data, localDate: "2026-01-01")
        #expect(missing.status == nil && missing.foodTotals == nil && missing.remainingFromRecorded.kcal == nil)
        let period = ProgressAnalytics.period(snapshot: data, endingOn: empty.localDate, days: 7)
        #expect(period.knownIntakeSamples.kcal == 0 && period.adherenceDenominator == 0)
    }

    @Test func incompleteNutrientDoesNotEraseOtherKnownNutrientSamples() {
        var data = snapshot()
        let first = day("2026-01-06", .complete)
        let second = day("2026-01-07", .complete)
        data.days = [first, second]
        data.meals = [meal(first, kcal: nil, protein: 4), meal(second, kcal: 80, protein: nil)]
        let report = ProgressAnalytics.period(snapshot: data, endingOn: second.localDate, days: 7)
        #expect(report.knownIntakeSamples.kcal == 1)
        #expect(report.averageIntake.kcal == 80)
        #expect(report.knownIntakeSamples.protein == 1)
        #expect(report.averageIntake.protein == 4)
        #expect(report.knownIntakeSamples.carbs == 2)
        #expect(report.averageIntake.carbs == 10)
    }

    @Test func datedGoalsSetEachDayAdherenceDenominatorAndRemainingCanBeNegative() {
        var data = snapshot()
        let first = day("2026-01-06", .complete)
        let second = day("2026-01-07", .complete)
        data.days = [first, second]
        data.meals = [meal(first, kcal: 120), meal(second, kcal: 120)]
        data.goals = [goal("2026-01-01", kcal: 100), goal("2026-01-07", kcal: 125)]
        let report = ProgressAnalytics.period(snapshot: data, endingOn: second.localDate, days: 7)
        #expect(report.adherenceNumerator == 1)
        #expect(report.adherenceDenominator == 2)
        #expect(ProgressAnalytics.daily(snapshot: data, localDate: first.localDate).remainingFromRecorded.kcal == -20)
        #expect(ProgressAnalytics.daily(snapshot: data, localDate: second.localDate).remainingFromRecorded.kcal == 5)
    }

    @Test func allFourRemainingValuesRequireTheirOwnRecordedAndTargetValues() {
        var data = snapshot()
        let tracked = day("2026-01-07", .complete)
        data.days = [tracked]
        data.meals = [meal(tracked, kcal: 80, carbs: 5, protein: nil, fat: 8)]
        data.goals = [goal("2026-01-01")]
        let report = ProgressAnalytics.daily(snapshot: data, localDate: tracked.localDate)
        #expect(report.remainingFromRecorded.kcal == 20)
        #expect(report.remainingFromRecorded.carbs == 15)
        #expect(report.remainingFromRecorded.protein == nil)
        #expect(report.remainingFromRecorded.fat == -3)
    }

    @Test func workoutBurnIsSeparateAndCreditRequiresOptInAndKnownBurn() {
        var data = snapshot()
        let tracked = day("2026-01-07", .complete)
        data.days = [tracked]
        data.meals = [meal(tracked, kcal: 80)]
        data.workouts = [workout(tracked, burn: 40)]
        data.goals = [goal("2026-01-01")]
        #expect(ProgressAnalytics.daily(snapshot: data, localDate: tracked.localDate).exerciseAdjustedKcalRemaining == nil)
        data.goals = [goal("2026-01-01", credit: true)]
        let credited = ProgressAnalytics.daily(snapshot: data, localDate: tracked.localDate)
        #expect(credited.remainingFromRecorded.kcal == 20)
        #expect(credited.estimatedBurnKcal == 40)
        #expect(credited.exerciseAdjustedKcalRemaining == 60)
        data.workouts.append(workout(tracked, burn: nil))
        let unknown = ProgressAnalytics.daily(snapshot: data, localDate: tracked.localDate)
        #expect(unknown.workoutCount == 2)
        #expect(unknown.estimatedBurnKcal == nil)
        #expect(unknown.exerciseAdjustedKcalRemaining == nil)
    }

    @Test func sameStoredDateAcrossTravelCombinesAllDayIDs() {
        var data = snapshot(zone: "America/Los_Angeles")
        let first = day("2026-01-07", .complete, zone: "Asia/Jerusalem")
        let second = day("2026-01-07", .partial, zone: "America/Los_Angeles")
        data.days = [first, second]
        data.meals = [meal(first, kcal: 50, protein: 5), meal(second, kcal: 30, protein: nil)]
        data.workouts = [workout(first, burn: 40), workout(second, burn: 20)]
        let report = ProgressAnalytics.daily(snapshot: data, localDate: "2026-01-07")
        #expect(report.status == .closed)
        #expect(report.foodTotals?.kcal == 80)
        #expect(report.foodTotals?.protein == 5 && report.foodTotals?.unknownItemCount == 1)
        #expect(report.workoutCount == 2)
        #expect(report.estimatedBurnKcal == 60)
        let period = ProgressAnalytics.period(snapshot: data, endingOn: "2026-01-07", days: 7)
        #expect(period.closedDayCount == 1)
        #expect(period.knownIntakeSamples.kcal == 1)
        #expect(period.workoutCount == 2)
    }

    @Test func calendarWindowUsesLocalDatesAcrossDSTAndMonthBoundary() {
        var data = snapshot(zone: "America/New_York")
        let included = day("2026-10-26", .complete, zone: data.profile.timeZoneID)
        let excluded = day("2026-10-25", .complete, zone: data.profile.timeZoneID)
        let end = day("2026-11-01", .complete, zone: data.profile.timeZoneID)
        data.days = [included, excluded, end]
        let weekly = ProgressAnalytics.period(snapshot: data, endingOn: end.localDate, days: 7)
        #expect(weekly.startLocalDate == "2026-10-26")
        #expect(weekly.skippedDayCount == 2)
        #expect(weekly.missingDayCount == 5)
        let monthly = ProgressAnalytics.period(snapshot: data, endingOn: end.localDate, days: 30)
        #expect(monthly.startLocalDate == "2026-10-03")
        #expect(monthly.dayCount == 30)
    }

    @Test func weightUsesLatestLocalMeasurementAndMixedUnits() {
        var data = snapshot()
        let first = day("2026-01-06", .unknown)
        let second = day("2026-01-07", .unknown)
        data.days = [first, second]
        data.weights = [weight(first, value: 75, hour: "08:00:00"),
                        weight(first, value: 70, hour: "09:00:00"),
                        weight(second, value: 154.3235835, unit: "lb")]
        let report = ProgressAnalytics.weight(snapshot: data, endingOn: second.localDate)
        #expect(report.currentSevenDayObservedCount == 2)
        #expect(abs((report.currentSevenDayAverageKg ?? 0) - 70) < 0.0001)
        #expect(report.changeFromSevenDaysAgoKg == nil)
    }

    @Test func weightChangesRequireThreeDatesInBothComparedSevenDayWindows() {
        var data = snapshot()
        let current = ["2026-03-29", "2026-03-30", "2026-03-31"]
        let weekAgo = ["2026-03-22", "2026-03-23", "2026-03-24"]
        let monthAgo = ["2026-02-27", "2026-02-28", "2026-03-01"]
        for (labels, value) in [(current, 70.0), (weekAgo, 71.0), (monthAgo, 72.0)] {
            for label in labels {
                let tracked = day(label, .unknown)
                data.days.append(tracked)
                data.weights.append(weight(tracked, value: value))
            }
        }
        var report = ProgressAnalytics.weight(snapshot: data, endingOn: "2026-03-31")
        #expect(report.changeFromSevenDaysAgoKg == -1)
        #expect(report.changeFromThirtyDaysAgoKg == -2)
        data.weights.removeAll { $0.dayID == data.days.first(where: { $0.localDate == "2026-02-27" })?.id }
        report = ProgressAnalytics.weight(snapshot: data, endingOn: "2026-03-31")
        #expect(report.changeFromSevenDaysAgoKg == -1)
        #expect(report.changeFromThirtyDaysAgoKg == nil)
    }

    @Test func plateauNeedsThreeDatesInEachEdgeWeekAndFourteenClosedKcalDays() {
        var data = snapshot()
        let calendar = Calendar(identifier: .gregorian)
        let end = date("2026-03-31")
        for offset in 0..<28 {
            let instant = calendar.date(byAdding: .day, value: -offset, to: end)!
            let label = ISO8601DateFormatter().string(from: instant).prefix(10).description
            let tracked = day(label, offset < 14 ? .complete : .partial)
            data.days.append(tracked)
            if offset < 14 { data.meals.append(meal(tracked, kcal: 80)) }
            if [0, 1, 2, 25, 26, 27].contains(offset) { data.weights.append(weight(tracked, value: 70)) }
        }
        var report = ProgressAnalytics.weight(snapshot: data, endingOn: "2026-03-31")
        #expect(report.plateau == .stable)
        data.days[13].completeness = .untracked
        report = ProgressAnalytics.weight(snapshot: data, endingOn: "2026-03-31")
        #expect(report.plateau == .insufficientData)
        data.days[13].completeness = .complete
        data.weights.removeLast()
        report = ProgressAnalytics.weight(snapshot: data, endingOn: "2026-03-31")
        #expect(report.plateau == .insufficientData)
    }

    @Test func plateauThresholdDistinguishesObservedChangeFromStableTrend() {
        var data = snapshot()
        let calendar = Calendar(identifier: .gregorian)
        for offset in 0..<28 {
            let instant = calendar.date(byAdding: .day, value: -offset, to: date("2026-03-31"))!
            let label = ISO8601DateFormatter().string(from: instant).prefix(10).description
            let tracked = day(label, .complete)
            data.days.append(tracked)
            data.meals.append(meal(tracked, kcal: 80))
            if [0, 1, 2, 25, 26, 27].contains(offset) {
                data.weights.append(weight(tracked, value: offset < 7 ? 70.3 : 70))
            }
        }
        let report = ProgressAnalytics.weight(snapshot: data, endingOn: "2026-03-31")
        #expect(report.plateau == .changing)
    }
}
