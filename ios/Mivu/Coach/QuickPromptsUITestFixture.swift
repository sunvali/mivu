#if DEBUG
import Foundation

/// UI tests pin the quick-prompt hour and seed yesterday's 13:00 lunch with a kcal goal, relative to the real clock.
enum QuickPromptsUITestFixture {
    static var isEnabled: Bool { DiaryLaunch.isUITest && ProcessInfo.processInfo.arguments.contains("--quick-prompts-fixture") }
    static var hour: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard DiaryLaunch.isUITest, let index = arguments.firstIndex(of: "--quick-prompts-hour"), index + 1 < arguments.count else { return nil }
        return Int(arguments[index + 1])
    }

    static func snapshot(now: Date = Date()) -> DiarySnapshot {
        let zone = TimeZone.current.identifier
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        let todayStart = calendar.startOfDay(for: now), yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let yesterday = TrackingDay(localDate: diaryDateLabel(yesterdayStart, zone: zone), timeZoneID: zone, startAt: yesterdayStart, completeness: .complete)
        let today = TrackingDay(localDate: diaryDateLabel(todayStart, zone: zone), timeZoneID: zone, startAt: todayStart)
        let lunchAt = calendar.date(byAdding: .hour, value: 13, to: yesterdayStart)!
        func food(_ name: String, _ quantity: Double, _ unit: String, _ kcal: Double) -> FoodItem {
            FoodItem(name: name, quantity: quantity, unit: unit, nutrition: NutritionValues(kcal: kcal, carbs: 0, protein: 0, fat: 0),
                     provenance: .estimate, reference: "Synthetic \(name.lowercased())")
        }
        let lunch = DiaryMeal(dayID: yesterday.id, capturedAt: lunchAt, eatenAt: lunchAt, revision: 1, timePrecision: nil,
            items: [food("Eggs", 2, "egg", 140), food("Bread", 3, "slice", 240), food("Salad", 1, "bowl", 40)],
            submissions: [MealSubmission(baseRevision: 0, text: "Synthetic lunch", photoIDs: [], reviewFirst: false, state: .saved)])
        let goal = GoalRecord(effectiveLocalDate: yesterday.localDate, timeZoneID: zone,
                              targets: NutritionValues(kcal: 1600, carbs: 180, protein: 100, fat: 55), goalWeightKg: nil, exerciseCreditEnabled: false)
        return DiarySnapshot(revision: 1, profile: DiaryProfile(name: "Synthetic quick prompts", timeZoneID: zone),
            days: [yesterday, today], meals: [lunch], goals: [goal], activeDayID: today.id, previousDayConfirmedAt: now)
    }
}
#endif
