#if DEBUG
import Foundation

/// 90 synthetic days ending today: meals near and off a 2,100 kcal goal, a few gaps, and a falling weight trend.
enum ProgressUITestFixture {
    static var isEnabled: Bool { DiaryLaunch.isUITest && ProcessInfo.processInfo.arguments.contains("--diary-progress-fixture") }
    static func snapshot(now: Date = Date()) -> DiarySnapshot {
        let zone = TimeZone.current
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let today = calendar.startOfDay(for: now)
        let foods: [(String, Double, Double, Double, Double)] = [
            ("Synthetic Greek yogurt", 180, 10, 18, 5), ("Synthetic chicken bowl", 650, 60, 50, 18), ("Synthetic pizza slice", 290, 33, 12, 11),
            ("Synthetic oat latte", 160, 22, 4, 6), ("Synthetic salmon rice", 620, 55, 40, 22), ("Synthetic banana", 105, 27, 1, 0)
        ]
        var days: [TrackingDay] = [], meals: [DiaryMeal] = [], weights: [WeightEntry] = []
        for offset in (0..<90).reversed() where offset % 9 != 4 {
            let start = calendar.date(byAdding: .day, value: -offset, to: today)!.addingTimeInterval(12 * 3_600)
            let day = TrackingDay(localDate: diaryDateLabel(start, zone: zone.identifier), timeZoneID: zone.identifier, startAt: start, completeness: .complete)
            days.append(day)
            // Mostly near target, some a bit off, an occasional big day.
            let scale = [1.0, 0.97, 1.04, 1.15, 0.92, 1.0, 1.4, 1.02, 0.78][offset % 9]
            let picks = (0..<4).map { foods[(offset + $0) % foods.count] }
            let factor = scale * 2_100 / picks.reduce(0) { $0 + $1.1 }
            let items = picks.map { food -> FoodItem in
                return FoodItem(name: food.0, unit: "serving", nutrition: NutritionValues(kcal: (food.1 * factor).rounded(), carbs: food.2 * factor, protein: food.3 * factor * 1.6, fat: food.4 * factor),
                                provenance: .estimate, reference: "Synthetic", uncertain: false, nutrientSources: [:])
            }
            meals.append(DiaryMeal(dayID: day.id, capturedAt: start, eatenAt: start, revision: 1, timePrecision: .dateOnly, items: items))
            if offset % 2 == 0 {
                let noise = [0.4, -0.3, 0.1, -0.5, 0.3][offset % 5]
                weights.append(WeightEntry(dayID: day.id, measuredAt: start, value: ((80 - Double(89 - offset) * 0.04 + noise) * 10).rounded() / 10))
            }
        }
        let goal = GoalRecord(effectiveLocalDate: days[0].localDate, timeZoneID: zone.identifier,
                              targets: NutritionValues(kcal: 2_100, carbs: 240, protein: 140, fat: 70), goalWeightKg: 75, exerciseCreditEnabled: false)
        return DiarySnapshot(revision: 1, profile: DiaryProfile(name: "Synthetic progress", timeZoneID: zone.identifier, adultConfirmed: true),
                             days: days, meals: meals, weights: weights, goals: [goal], activeDayID: days.last!.id, previousDayConfirmedAt: now)
    }
}
#endif
