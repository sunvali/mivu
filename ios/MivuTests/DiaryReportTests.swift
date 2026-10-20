import Foundation
import PDFKit
import Testing
@testable import Mivu

struct DiaryReportTests {
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func snapshot() -> DiarySnapshot {
        let monday = TrackingDay(localDate: "2026-09-01", timeZoneID: "UTC", startAt: date("2026-09-01T06:00:00Z"))
        let tuesday = TrackingDay(localDate: "2026-09-02", timeZoneID: "UTC", startAt: date("2026-09-02T06:00:00Z"))
        let earlier = TrackingDay(localDate: "2026-08-20", timeZoneID: "UTC", startAt: date("2026-08-20T06:00:00Z"))
        func meal(_ day: TrackingDay, _ at: String, _ name: String, kcal: Double?, protein: Double, revision: Int = 1) -> DiaryMeal {
            DiaryMeal(dayID: day.id, capturedAt: date(at), eatenAt: date(at), revision: revision,
                      items: [FoodItem(name: name, nutrition: NutritionValues(kcal: kcal, carbs: 10, protein: protein, fat: 5), provenance: .user)])
        }
        return DiarySnapshot(profile: DiaryProfile(name: "Synthetic", timeZoneID: "UTC"),
            days: [earlier, monday, tuesday],
            meals: [meal(monday, "2026-09-01T08:10:00Z", "Yogurt, \"berries\"", kcal: 310, protein: 24),
                    meal(monday, "2026-09-01T13:00:00Z", "=HYPERLINK(1)", kcal: 520, protein: 42),
                    meal(tuesday, "2026-09-02T12:30:00Z", "Burrito bowl", kcal: 2100, protein: 40),
                    meal(tuesday, "2026-09-02T20:00:00Z", "Still analyzing", kcal: 900, protein: 30, revision: 0),
                    meal(earlier, "2026-08-20T09:00:00Z", "Out of range", kcal: 400, protein: 20)],
            weights: [WeightEntry(dayID: monday.id, measuredAt: date("2026-09-01T07:00:00Z"), value: 82.4),
                      WeightEntry(dayID: tuesday.id, measuredAt: date("2026-09-02T07:00:00Z"), value: 81.8)],
            goals: [GoalRecord(effectiveLocalDate: "2026-08-01", timeZoneID: "UTC", targets: NutritionValues(kcal: 1800, protein: 110), goalWeightKg: nil, exerciseCreditEnabled: false),
                    GoalRecord(effectiveLocalDate: "2026-09-02", timeZoneID: "UTC", targets: NutritionValues(kcal: 1900, protein: 120), goalWeightKg: nil, exerciseCreditEnabled: false)])
    }
    static let range = DiaryReport(snapshot(), from: "2026-09-01", through: "2026-09-02")

    @Test func mealsCSVKeepsSavedMealsInRangeAndEscapesText() {
        let lines = Self.range.mealsCSV.components(separatedBy: "\r\n")
        #expect(lines[0] == "Date,Time,Meal,Calories (kcal),Protein (g),Carbs (g),Fat (g)")
        #expect(lines[1] == "2026-09-01,08:10,\"Yogurt, \"\"berries\"\"\",310,24,10,5")
        #expect(lines[2] == "2026-09-01,13:00,'=HYPERLINK(1),520,42,10,5")
        #expect(lines[3] == "2026-09-02,12:30,Burrito bowl,2100,40,10,5")
        #expect(!Self.range.mealsCSV.contains("Still analyzing") && !Self.range.mealsCSV.contains("Out of range"))
    }
    @Test func daysCSVComparesEachDayWithTheTargetInEffectThatDay() {
        let lines = Self.range.daysCSV.components(separatedBy: "\r\n")
        #expect(lines[0] == "Date,Calories (kcal),Calorie target (kcal),Protein (g),Protein target (g),Carbs (g),Fat (g),Weight")
        #expect(lines[1] == "2026-09-01,830,1800,66,110,20,10,82.4 kg")
        #expect(lines[2] == "2026-09-02,2100,1900,40,120,10,5,81.8 kg")
    }
    @Test func weightsCSVListsWeighInsInRange() {
        #expect(Self.range.weightsCSV == "Date,Time,Weight,Unit\r\n2026-09-01,07:00,82.4,kg\r\n2026-09-02,07:00,81.8,kg\r\n")
    }
    @Test func allTimeIncludesEveryDayAndUnknownValuesStayBlank() {
        var snapshot = Self.snapshot()
        snapshot.meals[0].items[0].nutrition.kcal = nil
        let report = DiaryReport(snapshot, from: nil, through: nil)
        #expect(report.days.map(\.localDate) == ["2026-08-20", "2026-09-01", "2026-09-02"])
        #expect(report.mealsCSV.contains("2026-09-01,08:10,\"Yogurt, \"\"berries\"\"\",,24,10,5"))
    }
    @Test func pdfHasASummaryPageAndMealPages() throws {
        let document = try #require(PDFDocument(data: Self.range.pdfData()))
        #expect(document.pageCount >= 2)
        let summary = document.page(at: 0)?.string ?? "", meals = document.page(at: 1)?.string ?? ""
        #expect(summary.contains("Synthetic") && summary.contains("Days logged") && summary.contains("−0.6 kg"))
        #expect(meals.contains("Burrito bowl") && !meals.contains("Still analyzing"))
        #expect(summary.contains("MIVU") && summary.contains("Made with Mivu") && summary.contains("Page 1 of \(document.pageCount)"))
        #expect(meals.contains("Page 2 of \(document.pageCount)"))
    }
    @Test func lastDaysFollowTheWakingDayAcrossMidnight() {
        #expect(DiaryReport.lastDays(7, now: Self.date("2026-10-11T01:30:00Z"), zone: "UTC", cutoffHour: 4) == ("2026-10-04", "2026-10-10"))
        #expect(DiaryReport.lastDays(30, now: Self.date("2026-10-11T09:00:00Z"), zone: "UTC", cutoffHour: 4) == ("2026-09-12", "2026-10-11"))
    }
    @Test func summaryCountsEveryCalendarDayInTheRequestedRange() throws {
        let report = DiaryReport(Self.snapshot(), from: "2026-08-30", through: "2026-09-02")
        let summary = try #require(PDFDocument(data: report.pdfData())?.page(at: 0)?.string)
        #expect(summary.contains("2 / 4") && summary.contains("30 Aug 2026"))
    }
    @Test func filesAreWrittenForTheChosenFormat() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let csv = try Self.range.write(.csv, to: directory)
        #expect(csv.map(\.lastPathComponent) == ["Mivu meals 2026-09-01 to 2026-09-02.csv", "Mivu days 2026-09-01 to 2026-09-02.csv", "Mivu weights 2026-09-01 to 2026-09-02.csv"])
        let pdf = try Self.range.write(.pdf, to: directory)
        #expect(pdf.map(\.lastPathComponent) == ["Mivu report 2026-09-01 to 2026-09-02.pdf"])
    }
}
