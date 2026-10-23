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

    @Test func weeksAlwaysIncludeTheSelectedDate() {
        let calendar = calendar(firstWeekday: 2)
        let weeks = DiaryWeek.weekStarts(earliest: nil, selected: "2026-07-01", today: "2026-10-21", calendar: calendar)
        #expect(weeks.first == "2026-06-29" && weeks.last == "2026-10-19")
        #expect(DiaryWeek.weekStarts(earliest: "2026-10-14", selected: "2026-10-21", today: "2026-10-21", calendar: calendar) == ["2026-10-12", "2026-10-19"])
    }

    @Test func pillLabelDescribesStatusAndMeals() {
        let day = TrackingDay(localDate: "2027-01-12", timeZoneID: "UTC", startAt: Date(), completeness: .partial)
        let summary = DiaryDaySummary(mealCount: 3, day: day, totals: nutritionTotals([]), savedMealCount: 3, pendingMealCount: 0)
        #expect(DiaryWeek.pillLabel("2027-01-12", summaries: [summary]) == "Tuesday 12 January, closed, 3 meals")
        #expect(DiaryWeek.pillLabel("2027-01-12", summaries: [summary], activeDayID: day.id) == "Tuesday 12 January, open, 3 meals")
        #expect(DiaryWeek.pillLabel("2027-01-12", summaries: []) == "Tuesday 12 January, nothing logged")
    }
}
