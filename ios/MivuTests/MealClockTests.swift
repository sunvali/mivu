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
    @Test func olderMealsFallBackToTheDayZone() {
        #expect(MealClock.zone(meal: nil, day: "Asia/Tokyo") == "Asia/Tokyo")
        #expect(MealClock.zone(meal: "America/New_York", day: "Asia/Tokyo") == "America/New_York")
    }
}
