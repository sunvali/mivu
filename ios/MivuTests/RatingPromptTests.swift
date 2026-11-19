import Foundation
import Testing
@testable import Mivu

@Suite struct RatingPromptTests {
    private func prompt(_ version: String) -> RatingPrompt {
        RatingPrompt(defaults: UserDefaults(suiteName: "RatingPromptTests-" + UUID().uuidString)!, version: version)
    }

    @Test func firstAskNeedsThreeLoggedDays() {
        let rating = prompt("1.4.1")
        #expect(!rating.shouldAsk(loggedDays: 2))
        #expect(rating.shouldAsk(loggedDays: 3))
    }

    @Test func asksOncePerVersionAfterThirtyDaysOrSevenMoreLoggedDays() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = prompt("1.4.1")
        first.recordAsk(loggedDays: 3, now: start)
        #expect(!first.shouldAsk(loggedDays: 40, now: start.addingTimeInterval(90 * 86_400)))

        let next = RatingPrompt(defaults: first.defaults, version: "1.5.0")
        #expect(!next.shouldAsk(loggedDays: 9, now: start.addingTimeInterval(29 * 86_400)))
        #expect(next.shouldAsk(loggedDays: 10, now: start.addingTimeInterval(29 * 86_400)))
        #expect(next.shouldAsk(loggedDays: 4, now: start.addingTimeInterval(30 * 86_400)))
    }
}
