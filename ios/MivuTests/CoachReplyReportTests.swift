import Foundation
import Testing
@testable import Mivu

@Suite struct CoachReplyReportTests {
    private let owner = DiarySelectionOwnership(identity: CoachTimelineIdentity(profileID: UUID(), timelineGeneration: UUID()), selectionEpoch: 7)
    private func reply() -> CoachExchangeSummary {
        var turn = CoachTimelineTestData.row(1)
        turn.assistantText = "Synthetic selected reply."
        return turn
    }

    @Test func payloadIncludesOnlySelectedReplyAndExplicitMetadata() throws {
        var turn = CoachTimelineTestData.row(1)
        turn.text = "PRIVATE_ORIGINATING_PROMPT"
        turn.assistantText = "Synthetic selected reply."
        let privatePhotoID = UUID(), privateMealID = UUID()
        turn.photos = [DiaryPhotoReference(profileID: owner.identity.profileID, owner: .coachTurn(turn.id),
            photoID: privatePhotoID, createdAt: Date(), role: .before, contentToken: UUID())]
        turn.reply = CoachReply(target: .meal(mealID: privateMealID), excerpt: "PRIVATE_QUOTED_MEAL")
        let report = try #require(CoachReplyReport(owner: owner, exchange: turn, appVersion: "1.1.1", appBuild: "42", provider: "Synthetic provider", model: "test-model"))
        let body = try report.body(reason: .unsafeAdvice, comment: "Please review this advice.")
        #expect(body.contains("Synthetic selected reply."))
        #expect(body.contains("Unsafe advice"))
        #expect(body.contains("Please review this advice."))
        #expect(body.contains("1.1.1 (42)"))
        #expect(body.contains("Synthetic provider") && body.contains("test-model"))
        #expect(body.contains(turn.id.uuidString))
        #expect(!body.contains("PRIVATE_ORIGINATING_PROMPT"))
        #expect(!body.contains(owner.identity.profileID.uuidString))
        #expect(!body.contains(owner.identity.timelineGeneration.uuidString))
        #expect(!body.contains("selectionEpoch"))
        #expect(!body.contains("PRIVATE_QUOTED_MEAL"))
        #expect(!body.contains(privatePhotoID.uuidString) && !body.contains(privateMealID.uuidString))
        #expect(CoachReplyReport.recipient == "support@mivuapp.com")
    }

    @Test func unknownHistoricalModelIsNotReplacedByCurrentSelection() throws {
        let report = try #require(CoachReplyReport(owner: owner, exchange: reply(), appVersion: "1.1.1", appBuild: "42"))
        let body = try report.body(reason: .other, comment: " \n ")
        #expect(body.contains("Provider: Unknown") && body.contains("Model: Unknown"))
        #expect(!body.contains("Comment:"))
    }

    @Test func missingEmptyAndOversizedRepliesCannotCreateReport() {
        var turn = CoachTimelineTestData.row(1)
        for text in [nil, " \n ", String(repeating: "🍎", count: 8_193)] as [String?] {
            turn.assistantText = text
            #expect(CoachReplyReport(owner: owner, exchange: turn, appVersion: "1", appBuild: "1") == nil)
        }
    }

    @Test func reportBoundsCommentsAndMetadataWithoutSilentlyChangingReply() throws {
        var turn = CoachTimelineTestData.row(1)
        turn.assistantText = String(repeating: "🍎", count: 8_192)
        let report = try #require(CoachReplyReport(owner: owner, exchange: turn, appVersion: String(repeating: "v", count: 1_000), appBuild: "42", model: String(repeating: "m", count: 1_000)))
        let body = try report.body(reason: .inaccurateAnswer, comment: String(repeating: "c", count: 1_000))
        #expect(body.contains(try #require(turn.assistantText)))
        #expect(body.utf8.count < 40_000)
        #expect(!body.contains(String(repeating: "v", count: 129)))
        #expect(!body.contains(String(repeating: "m", count: 129)))
        #expect(throws: CoachReplyReport.ValidationError.commentTooLong) {
            try report.body(reason: .other, comment: String(repeating: "c", count: 1_001))
        }
        #expect(throws: CoachReplyReport.ValidationError.commentTooLong) {
            try report.body(reason: .other, comment: "a" + String(repeating: "\u{301}", count: 2_000))
        }
    }

    @Test func ownershipIncludesSelectionEpochAndExactAvailableReply() throws {
        let turn = reply()
        let report = try #require(CoachReplyReport(owner: owner, exchange: turn, appVersion: "1", appBuild: "1"))
        #expect(report.isAvailable(selection: owner, exchange: turn))
        #expect(!report.isAvailable(selection: nil, exchange: turn))
        #expect(!report.isAvailable(selection: DiarySelectionOwnership(identity: owner.identity, selectionEpoch: 8), exchange: turn))
        #expect(!report.isAvailable(selection: DiarySelectionOwnership(identity: CoachTimelineIdentity(profileID: UUID(), timelineGeneration: owner.identity.timelineGeneration), selectionEpoch: 7), exchange: turn))
        #expect(!report.isAvailable(selection: DiarySelectionOwnership(identity: CoachTimelineIdentity(profileID: owner.identity.profileID, timelineGeneration: UUID()), selectionEpoch: 7), exchange: turn))
        #expect(!report.isAvailable(selection: owner, exchange: nil))
        #expect(!report.isAvailable(selection: owner, exchange: CoachTimelineTestData.row(2)))
        var changed = turn; changed.assistantText = "Replacement reply"
        #expect(!report.isAvailable(selection: owner, exchange: changed))
        changed.assistantText = nil
        #expect(!report.isAvailable(selection: owner, exchange: changed))
    }

    @Test(arguments: [
        (CoachReplyReport.Outcome.cancelled, "Report not sent."),
        (.savedDraft, "Draft saved in Mail. Report not sent."),
        (.queuedInMail, "Report queued in Mail. Delivery is not confirmed."),
        (.failed, "Mail could not send the report. Your review text is still available."),
        (.copied, "Report copied. Paste it into your email client and send it yourself. Copying does not send a report.")
    ])
    func mailAndCopyResultsNeverClaimReceipt(outcome: CoachReplyReport.Outcome, message: String) {
        #expect(outcome.message == message)
    }
    @Test func coachInstructionsEstablishDietaryAndContentSafetyBoundaries() {
        #expect(CoachEngine.stableRules.contains("dangerous dietary restriction"))
        #expect(CoachEngine.stableRules.contains("Do not diagnose"))
        #expect(CoachEngine.stableRules.contains("qualified professional help"))
    }

}
