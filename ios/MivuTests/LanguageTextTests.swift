import Foundation
import Testing
@testable import Mivu

/// English output that sentence-building code must keep after it moved to whole translatable strings.
struct LanguageTextTests {
    @Test func removeWholeMealQuestionIsOneSentence() {
        #expect(CoachEngine.removeMealQuestion(names: "Rice, Beans") == "Remove the whole Rice, Beans meal?")
        #expect(CoachEngine.removeMealQuestion(names: "") == "Remove the whole meal?")
    }

    @Test func dayChipKeepsItsEnglishShape() {
        let partial = coachDayChip(localDate: "2026-10-19", today: "2026-10-19", kcal: 1240, kcalPartial: true, mealsLogged: true, goal: 2000)
        #expect(partial.text == "Today · 1,240+ / 2,000 kcal")
        #expect(partial.spoken == "Logging to today, at least 1,240 of 2,000 kcal")
        let open = coachDayChip(localDate: "2026-10-18", today: "2026-10-19", kcal: nil, kcalPartial: false, mealsLogged: true, goal: nil)
        #expect(open.text == "Yesterday · — kcal")
        #expect(open.spoken == "Logging to yesterday, unknown kcal")
    }

    @Test func coachDatesStayGregorian() {
        #expect(CoachReplyLines.shortDate("2026-10-19", locale: Locale(identifier: "en_US@calendar=buddhist")) == "Oct 19")
        #expect(CoachReplyLines.dayLabel("2025-10-19", today: "2026-10-19", locale: Locale(identifier: "en_US@calendar=hebrew")).contains("2025"))
    }

    @Test func countsUsePluralForms() {
        #expect(String(localized: "Down \("1.0") kg in \(1) days") == "Down 1.0 kg in 1 day")
        #expect(String(localized: "Added \(1) photos.") == "Added 1 photo.")
        #expect(String(localized: "\(1) of \(1) days logged") == "1 of 1 day logged")
        #expect(String(localized: "\(3) of \(7) days logged") == "3 of 7 days logged")
        #expect(String(localized: "Weight chart: \(2) measured dates.") == "Weight chart: 2 measured dates.")
    }

    @Test func weightUnitIsShownNotStored() {
        #expect(WeightEntry(measuredAt: Date(), value: 70, unit: "lb").shownUnit == "lb")
        #expect(WeightEntry(measuredAt: Date(), value: 70).shownUnit == "kg")
    }

    @Test func mealCountsReadCorrectly() {
        let day = TrackingDay(localDate: "2027-01-12", timeZoneID: "UTC", startAt: Date(), completeness: .partial)
        func label(_ meals: Int) -> String {
            DiaryWeek.pillLabel("2027-01-12", summaries: [DiaryDaySummary(mealCount: meals, day: day, totals: nutritionTotals([]), savedMealCount: meals, pendingMealCount: 0)])
        }
        #expect(label(0).hasSuffix(", 0 meals"))
        #expect(label(1).hasSuffix(", 1 meal"))
        #expect(label(2).hasSuffix(", 2 meals"))
    }

    @Test func datePatternsKeepTheirEnglishShape() {
        #expect(DiaryWeek.format("2026-10-19", "EEEE d MMMM") == "Monday 19 October")
        #expect(DiaryWeek.format("2026-10-19", "EEEE, d MMM") == "Monday, 19 Oct")
        #expect(DiaryWeek.format("2026-10-19", "MMM d, yyyy") == "Oct 19, 2026")
        #expect(DiaryWeek.format("2026-10-19", "EEEEE") == "M")
    }

    @Test func burnHintCountsReadCorrectly() {
        #expect(ProgressBurnCard.burnPlaceholder(days: 1, weighIns: 2) == "Log 1 more complete day and weigh in 2 more times to see your burn.")
        #expect(ProgressBurnCard.burnPlaceholder(days: 2, weighIns: 1) == "Log 2 more complete days and weigh in 1 more time to see your burn.")
        #expect(ProgressBurnCard.burnPlaceholder(days: 2, weighIns: 0) == "Log 2 more complete days to see your burn.")
        #expect(ProgressBurnCard.burnPlaceholder(days: 0, weighIns: 1) == "Weigh in 1 more time to see your burn.")
    }

    @Test func dayResultsKeepTheirEnglishShape() {
        #expect(ProgressInsights.plainGap(2500, goal: 2000) == "500 over")
        #expect(ProgressInsights.plainGap(2050, goal: 2000) == "on target")
        #expect(ProgressInsights.plainMacro(80, goal: 120) == "80 g a day · 40 g under goal")
        #expect(ProgressInsights.plainMacro(nil, goal: 120) == "No complete days")
    }

    /// A phone set to another calendar or digit system still shows Gregorian dates with 0–9.
    @Test func datesStayGregorianWithLatinDigits() {
        let hebrewCalendar = Locale(identifier: "en_US@calendar=hebrew;numbers=arab")
        #expect(DiaryWeek.format("2026-10-19", "EEEE d MMMM", locale: hebrewCalendar) == "Monday 19 October")
        #expect(DiaryWeek.format("2026-10-19", "MMM d, yyyy", locale: Locale(identifier: "en_US@calendar=buddhist")) == "Oct 19, 2026")
    }

    @Test func oneWeighInReadsSingular() {
        #expect(String(localized: "\(1) weigh-ins. Trend \("72.4") kg on \("2026-10-19").") == "1 weigh-in. Trend 72.4 kg on 2026-10-19.")
        #expect(String(localized: "\(3) weigh-ins. Trend \("72.4") kg on \("2026-10-19").") == "3 weigh-ins. Trend 72.4 kg on 2026-10-19.")
    }

    @Test func convertedCountsKeepTheirEnglish() {
        #expect(String(localized: "Last \(7) days: about \("2,100") kcal a day on \(1) tracked days.") == "Last 7 days: about 2,100 kcal a day on 1 tracked day.")
        #expect(String(localized: "Last \(7) days: about \("2,100") kcal a day on \(5) tracked days.") == "Last 7 days: about 2,100 kcal a day on 5 tracked days.")
        #expect(String(localized: "\(1) photos added") == "1 photo added")
        #expect(String(localized: "\(3) photos added") == "3 photos added")
        #expect(String(localized: "\(1) minutes") == "1 minute")
    }

    /// Each workout kind is its own whole sentence, so a language can inflect the kind word.
    @Test func workoutLinesAreWholePerKind() {
        #expect(WorkoutKind.strength.savedLine(minutes: 45) == "Workout saved: strength, 45 minutes.")
        #expect(WorkoutKind.cardio.factLine(minutes: 1) == "Cardio, 1 minute.")
        #expect(WorkoutKind.other.deletionTitle(on: "2026-10-19") == "Delete other workout on 2026-10-19?")
        #expect(WorkoutKind.strength.deletionTitle(on: nil) == "Delete strength workout on its recorded day?")
    }

    @Test func setLinesReadCorrectly() {
        #expect(WorkoutSet(repetitions: 8, loadKg: 60.5).line(number: 1) == "Set 1: 8 repetitions · 60.5 kg")
        #expect(WorkoutSet(repetitions: 1, loadKg: nil).line(number: 2) == "Set 2: 1 repetition · bodyweight")
    }

    @Test func bandWordsReadMidSentence() {
        #expect(ProgressBand.allCases.map(\.spoken) == ["near", "a bit off", "off", "far off"])
    }
}
