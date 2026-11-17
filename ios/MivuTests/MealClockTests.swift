import Foundation
import Testing
@testable import Mivu

@Suite struct MealClockTests {
    @Test func tagOnlyWhenTheClockDiffers() {
        let at = ISO8601DateFormatter().date(from: "2026-11-17T05:40:00Z")!
        let away = MealClock.label(at, mealZone: "Asia/Jerusalem", deviceZone: "America/New_York")
        #expect(away.tag == "Jerusalem" && away.spoken.hasSuffix(", Jerusalem time"))
        #expect(MealClock.label(at, mealZone: "Europe/Paris", deviceZone: "Europe/Berlin").tag == nil)
    }
    @Test func olderMealsShowThePhoneClockWithoutATag() {
        let at = ISO8601DateFormatter().date(from: "2026-11-17T20:24:00Z")!
        var meal = MealReadModel(id: UUID(), dayID: UUID(), capturedAt: at, eatenAt: at, revision: 1, timePrecision: nil, timeZoneID: nil,
                                 items: [], submissions: [], photos: [], sourceTurnID: nil)
        let older = MealClock.label(meal, deviceZone: "America/New_York")
        #expect(older.tag == nil && older.time == MealClock.label(at, mealZone: "America/New_York", deviceZone: "America/New_York").time)
        meal.timeZoneID = "Asia/Jerusalem"
        #expect(MealClock.label(meal, deviceZone: "America/New_York").tag == "Jerusalem")
    }
    @Test func olderMealsFallBackToTheDayZone() {
        #expect(MealClock.zone(meal: nil, day: "Asia/Tokyo") == "Asia/Tokyo")
        #expect(MealClock.zone(meal: "America/New_York", day: "Asia/Tokyo") == "America/New_York")
    }
}
