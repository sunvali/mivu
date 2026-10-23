import Foundation
import Testing
@testable import Mivu

@Suite struct ProgressInsightsTests {
    @Test func bandsByDistanceFromTarget() {
        #expect(ProgressBand.of(kcal: 2310, target: 2100) == .near)
        #expect(ProgressBand.of(kcal: 1680, target: 2100) == .bitOff)
        #expect(ProgressBand.of(kcal: 2835, target: 2100) == .off)
        #expect(ProgressBand.of(kcal: 2836, target: 2100) == .farOff)
    }

    @Test func unknownKcalHasNoBand() {
        #expect(ProgressBand.of(kcal: nil, target: 2100) == nil)
        #expect(ProgressBand.of(kcal: 1800, target: nil) == nil)
        #expect(ProgressBand.of(kcal: 1800, target: 0) == nil)
    }

    @Test func bandUsesEachDaysOwnGoal() {
        #expect(ProgressBand.of(kcal: 2000, target: 2000) == .near)
        #expect(ProgressBand.of(kcal: 2000, target: 1500) == .off)
    }
}
