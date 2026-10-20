import Foundation
import Testing
@testable import Mivu

struct DiaryWeekStripTests {
    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    @Test func weekStartsOnCalendarFirstWeekday() {
        let week = DiaryWeek.dates(containing: "2027-01-14", calendar: calendar(firstWeekday: 2))
        #expect(week.count == 7 && week.first == "2027-01-11" && week.last == "2027-01-17")
    }

    @Test func weekCrossesYearBoundary() {
        let week = DiaryWeek.dates(containing: "2026-12-31", calendar: calendar(firstWeekday: 1))
        #expect(week.first == "2026-12-27" && week.contains("2027-01-02"))
    }

    @Test func pillLabelDescribesCoverageAndMeals() {
        let day = TrackingDay(localDate: "2027-01-12", timeZoneID: "UTC", startAt: Date(), completeness: .partial)
        let summary = DiaryDaySummary(mealCount: 3, day: day, totals: nutritionTotals([]), savedMealCount: 3, pendingMealCount: 0)
        #expect(DiaryWeek.pillLabel("2027-01-12", summaries: [summary]) == "Tuesday 12 January, partial, 3 meals")
        #expect(DiaryWeek.pillLabel("2027-01-12", summaries: []) == "Tuesday 12 January, nothing logged")
    }
}
