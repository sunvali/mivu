#if DEBUG
import Foundation

enum DiaryHistoryUITestFixture {
    static var isEnabled: Bool { DiaryLaunch.isUITest && ProcessInfo.processInfo.arguments.contains("--diary-history-fixture") }
    static func snapshot() -> DiarySnapshot {
        let at = Date(timeIntervalSince1970: 1_792_368_000)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let days = (0..<75).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: at)!
            return TrackingDay(localDate: diaryDateLabel(date, zone: "UTC"), timeZoneID: "UTC", startAt: date)
        }
        let meals = days.map { day in
            DiaryMeal(dayID: day.id, capturedAt: day.startAt, eatenAt: day.startAt, revision: 1, timePrecision: .dateOnly,
                items: [FoodItem(name: "Synthetic history food", unit: "serving", nutrition: NutritionValues(kcal: 100),
                    provenance: .user, reference: "Entered manually", uncertain: false, nutrientSources: ["kcal": .user])])
        }
        return DiarySnapshot(revision: 1, profile: DiaryProfile(name: "Synthetic history", timeZoneID: "UTC"),
            days: days, meals: meals, activeDayID: days.last!.id, previousDayConfirmedAt: at)
    }
}
#endif
