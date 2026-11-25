import Foundation
import Testing
@testable import Mivu

/// Synthetic diaries around Thursday 2026-11-26. Offsets count days before today: 1 is yesterday.
struct PipNoticesTests {
    private let today = "2026-11-26"
    private func calendar(_ locale: String = "en_US", zone: String = "UTC") -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: zone)!; c.locale = Locale(identifier: locale); return c
    }
    private func label(_ offset: Int) -> String { ProgressAnalytics.window(endingOn: today, days: 1, offset: offset, zone: "UTC")[0] }
    /// Gregorian weekday of the day `offset` days back, 1 = Sunday.
    private func weekday(_ offset: Int) -> Int { calendar().component(.weekday, from: ProgressDate.date(label(offset), zone: "UTC")!) }

    private func day(_ offset: Int, kcal: Double? = 2000, target: Double? = 2000, protein: Double? = nil, proteinTarget: Double? = nil,
                     status: DayStatus? = .closed) -> DailyProgress {
        let goal = GoalRecord(effectiveLocalDate: "2026-01-01", timeZoneID: "UTC",
                              targets: NutritionValues(kcal: target, protein: proteinTarget), goalWeightKg: nil, exerciseCreditEnabled: false)
        return DailyProgress(localDate: label(offset), status: status,
                             foodTotals: status == nil ? nil : NutritionTotals(kcal: kcal, carbs: nil, protein: protein, fat: nil, unknownItemCount: 0),
                             goal: goal, remainingFromRecorded: NutritionValues(), workoutCount: 0, estimatedBurnKcal: nil, exerciseAdjustedKcalRemaining: nil)
    }
    private func missing(_ offset: Int) -> DailyProgress { day(offset, status: nil) }
    /// Thirty reports, oldest first; every day sits on target unless `change` says otherwise.
    private func reports(_ change: (Int) -> DailyProgress? = { _ in nil }) -> [DailyProgress] {
        (1...30).reversed().map { change($0) ?? day($0) }
    }
    /// Near on the first `near` days of each week (week 0 is offsets 1...7), a bit off (15% over) on the rest.
    private func weeks(_ near: [Int], _ offset: Int) -> DailyProgress? {
        let week = (offset - 1) / 7
        guard week < near.count else { return nil }
        return (offset - 1) % 7 < near[week] ? nil : day(offset, kcal: 2300)
    }
    private func meal(_ offset: Int, _ hour: Int, _ minute: Int = 0, nextDate: Bool = false, precision: MealTimePrecision? = .exact,
                      capturedAfter: TimeInterval = 0, zone: String? = nil) -> RecentMeal {
        // ProgressDate.date is noon; step back to midnight.
        let start = ProgressDate.date(label(offset - (nextDate ? 1 : 0)), zone: "UTC")!.addingTimeInterval(-12 * 3600)
        let eaten = start.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
        return RecentMeal(localDate: label(offset), meal: MealReadModel(
            id: UUID(), dayID: UUID(), capturedAt: eaten.addingTimeInterval(capturedAfter), eatenAt: eaten, revision: 1,
            timePrecision: precision, timeZoneID: zone, items: [], submissions: [], photos: [], sourceTurnID: nil))
    }
    private func found(_ reports: [DailyProgress]? = nil, meals: [RecentMeal] = [], loggedDays: Int = 30, locale: String = "en_US",
                       today: String? = nil) -> [PipNotice] {
        PipNotices.candidates(PipNoticeInput(today: today ?? self.today, reports: reports ?? self.reports(), meals: meals,
                                             loggedDays: loggedDays, calendar: calendar(locale)))
    }

    @Test func steadyDiaryHasNothingToSay() {
        #expect(found() == [])
    }

    @Test func silentBelowFourteenLoggedDays() {
        let best = reports { weeks([6, 3, 4, 2], $0) }
        #expect(found(best).first == .bestWeek(near: 6, days: 7))
        #expect(found(best, loggedDays: 13) == [])
    }

    @Test func welcomeBackAfterThreeDaysAway() {
        #expect(found(reports { $0 <= 3 ? missing($0) : nil }) == [.welcomeBack])
        #expect(!found(reports { $0 <= 2 ? missing($0) : nil }).contains(.welcomeBack))
        #expect(found(reports { missing($0) }) == [.welcomeBack])
    }

    @Test func bestWeekNeedsFourNearAndBeatsEarlierWeeks() {
        #expect(found(reports { weeks([6, 3, 4, 2], $0) }).first == .bestWeek(near: 6, days: 7))
        #expect(!found(reports { weeks([6, 6, 4, 2], $0) }).contains(.bestWeek(near: 6, days: 7)))
        #expect(found(reports { weeks([3, 2, 1, 0], $0) }) == [])
        // Only nine closed days in the three earlier weeks: too thin to call a best.
        let thin = reports { offset in offset > 7 && (offset - 8) % 7 >= 3 ? missing(offset) : weeks([6, 2, 2, 2], offset) }
        #expect(!found(thin).contains(.bestWeek(near: 6, days: 7)))
    }

    @Test func betterWeekNeedsTwoMore() {
        #expect(found(reports { weeks([5, 3, 7, 7], $0) }) == [.betterWeek(near: 5, before: 3)])
        #expect(found(reports { weeks([5, 4, 7, 7], $0) }) == [])
        // Last week too thin to compare against.
        #expect(found(reports { (8...14).contains($0) && $0 > 10 ? missing($0) : weeks([5, 0, 7, 7], $0) }) == [])
    }

    @Test func weekdayDriftAtThreeOfFour() {
        #expect(found(reports { [7, 14, 21].contains($0) ? day($0, kcal: 2600) : nil }) == [.weekdayDrift(weekday: 5, over: true)])
        #expect(found(reports { [7, 14, 21].contains($0) ? day($0, kcal: 1400) : nil }) == [.weekdayDrift(weekday: 5, over: false)])
        #expect(found(reports { [7, 14].contains($0) ? day($0, kcal: 2600) : nil }) == [])
        #expect(found(reports { [7, 14].contains($0) ? day($0, kcal: 2600) : $0 == 21 ? day($0, kcal: 1400) : nil }) == [])
        // A bit off (15%) is not drift.
        #expect(found(reports { [7, 14, 21, 28].contains($0) ? day($0, kcal: 2300) : nil }) == [])
    }

    @Test func weekendDriftFollowsTheCalendarRegion() {
        // Fridays and Saturdays run 30% over; tomorrow is Friday.
        let data = reports { [6, 7].contains(weekday($0)) ? day($0, kcal: 2600) : nil }
        #expect(found(data, locale: "he_IL") == [.weekendDrift(over: true)])
        #expect(found(data, locale: "en_US") == [])
    }

    @Test func weekendDriftShowsOnlyAroundTheWeekend() {
        // The same pattern seen from Wednesday 2026-11-25: neither today nor tomorrow is an Israeli weekend day.
        let wednesday = "2026-11-25"
        let data = ProgressAnalytics.window(endingOn: wednesday, days: 30, offset: 1, zone: "UTC").map { label -> DailyProgress in
            let offset = ProgressInsights.days(from: label, to: today)
            return [6, 7].contains(weekday(offset)) ? day(offset, kcal: 2600) : day(offset)
        }
        #expect(found(data, locale: "he_IL", today: wednesday) == [])
    }

    @Test func weekendDriftNeedsCalmWeekdays() {
        // Mondays and Wednesdays off as well: 8 of 20 weekdays.
        let data = reports { [6, 7].contains(weekday($0)) ? day($0, kcal: 2600) : [2, 4].contains(weekday($0)) ? day($0, kcal: 1400) : nil }
        #expect(found(data, locale: "he_IL") == [])
    }

    @Test func lateDinnersAtThree() {
        let late = [meal(1, 21, 30), meal(2, 22, 10), meal(3, 0, 40, nextDate: true), meal(4, 12, 0)]
        #expect(found(meals: late) == [.lateDinners(count: 3)])
        #expect(found(meals: [meal(1, 21, 29), meal(2, 22, 10), meal(3, 0, 40, nextDate: true)]) == [])
        // An earlier meal the same evening does not hide the late one.
        #expect(found(meals: late + [meal(1, 12, 0), meal(2, 12, 0), meal(3, 12, 0)]) == [.lateDinners(count: 3)])
    }

    @Test func lateFirstMealAtFour() {
        #expect(found(meals: (1...4).map { meal($0, 13, 0) }) == [.lateFirstMeal(count: 4)])
        #expect(found(meals: (1...3).map { meal($0, 13, 0) }) == [])
        #expect(found(meals: (1...4).map { meal($0, 13, 0) } + [meal(4, 8, 0)]) == [])
    }

    @Test func mealsOnDaysThatAreNotClosedDoNotCount() {
        #expect(found(reports { $0 == 1 ? missing($0) : nil }, meals: [meal(1, 22, 0), meal(2, 22, 0), meal(3, 22, 0)]) == [])
    }

    @Test func untimedMealsAreIgnored() {
        #expect(found(meals: (1...3).map { meal($0, 22, 0, precision: .dateOnly) }) == [])
        #expect(found(meals: (1...3).map { meal($0, 22, 0, precision: nil, capturedAfter: 3 * 3600) }) == [])
        // Older meals carry no precision; logged on the spot, their time is real.
        #expect(found(meals: (1...3).map { meal($0, 22, 0, precision: nil, capturedAfter: 600) }) == [.lateDinners(count: 3)])
    }

    @Test func mealClockUsesTheMealsZone() {
        // 13:00 UTC is 22:00 in Tokyo, where these were eaten.
        #expect(found(meals: (1...3).map { meal($0, 13, 0, zone: "Asia/Tokyo") }) == [.lateDinners(count: 3)])
        #expect(found(meals: (1...3).map { meal($0, 13, 0) }) == [])
    }

    @Test func proteinShortAtSixtyPercent() {
        func data(short: Int, known: Int) -> [DailyProgress] {
            reports { $0 <= known ? day($0, protein: $0 <= short ? 79 : 80, proteinTarget: 100) : nil }
        }
        #expect(found(data(short: 3, known: 5)) == [.proteinShort(short: 3, days: 5)])
        #expect(found(data(short: 2, known: 5)) == [])
        #expect(found(data(short: 4, known: 4)) == [])
        // Only the last 14 days are read.
        #expect(found(reports { $0 > 14 ? day($0, protein: 10, proteinTarget: 100) : nil }) == [])
    }

    @Test func daysWithoutTargetOrCaloriesAreNeutral() {
        #expect(found(reports { day($0, kcal: 2600, target: nil) }) == [])
        #expect(found(reports { day($0, kcal: nil) }) == [])
        #expect(found(reports { day($0, kcal: 2600, target: 0, protein: 10, proteinTarget: 0) }) == [])
    }

    @Test func preferenceOrder() {
        let data = reports { offset -> DailyProgress? in
            let protein: Double? = offset <= 5 ? (offset <= 3 ? 50 : 100) : nil
            if [7, 14, 21].contains(offset) { return day(offset, kcal: 2600, protein: protein, proteinTarget: 100) }
            let near = [6, 3, 3, 3], week = (offset - 1) / 7
            let kcal: Double = week < 4 && (offset - 1) % 7 >= near[week] ? 2300 : 2000
            return day(offset, kcal: kcal, protein: protein, proteinTarget: 100)
        }
        #expect(found(data) == [.bestWeek(near: 6, days: 7), .betterWeek(near: 6, before: 3),
                                .weekdayDrift(weekday: 5, over: true), .proteinShort(short: 3, days: 5)])
    }
}
