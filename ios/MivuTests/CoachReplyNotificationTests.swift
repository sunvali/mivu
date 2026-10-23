import Foundation
import Testing
@testable import Mivu

struct CoachReplyNotificationTests {
    private func turn(_ state: CoachTurnState, reply: String? = nil, mealID: UUID? = nil) -> CoachTurnResult {
        CoachTurnResult(CoachTurn(capturedAt: Date(), text: "Synthetic question", state: state, assistantText: reply,
                                  captureTimeZoneID: "UTC", pendingMealID: mealID))
    }
    private let saved = "Your message is saved. Open Mivu for the Coach's reply."

    @Test func completedTurnShowsReplyExcerpt() throws {
        let text = try #require(CoachReplyNotification.text(for: turn(.completed, reply: "Synthetic reply")))
        #expect(text.title == "Coach" && text.body == "Synthetic reply")
        let long = try #require(CoachReplyNotification.text(for: turn(.completed, reply: String(repeating: "a", count: 500))))
        #expect(long.body.count <= 180 && long.body.hasSuffix("…"))
    }
    @Test func clarificationTurnAsksForAnswer() {
        #expect(CoachReplyNotification.text(for: turn(.needsClarification, reply: "Which bread?"))?.body == "The Coach needs a quick answer.")
    }
    @Test func retryStatesSaySaved() {
        for state in [CoachTurnState.needsRetry, .waitingForNetwork, .waitingForConnection] {
            #expect(CoachReplyNotification.text(for: turn(state))?.body == saved)
        }
    }
    @Test func inFlightTurnHasNoContent() {
        #expect(CoachReplyNotification.text(for: turn(.captured)) == nil)
        #expect(CoachReplyNotification.text(for: turn(.analyzing)) == nil)
    }
    @Test func mealTurnDefersToMealNotification() {
        #expect(CoachReplyNotification.text(for: turn(.completed, reply: "Logged eggs", mealID: UUID())) == nil)
    }
    @Test func turnIDRoundTrips() {
        let id = UUID()
        #expect(CoachReplyNotification.turnID(from: [CoachReplyNotification.turnKey: id.uuidString]) == id)
        #expect(CoachReplyNotification.identifier(for: id) == "coach-reply-" + id.uuidString)
    }
}
