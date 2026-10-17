import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct CompanionPresentationTests {
    private let t = Date(timeIntervalSince1970: 1_800_000_000)
    private let owner = UUID()

    private func context(
        surface: CompanionSurface? = .today, typing: Bool = false,
        processing: Bool = false, recovery: Bool = false,
        playback: MotionPolicy.Playback = .animated
    ) -> CompanionContext {
        CompanionContext(surface: surface, isTyping: typing, isProcessing: processing,
                         needsRecovery: recovery, playback: playback)
    }

    private func event(kind: CompanionEvent.Kind = .saved, at: Date? = nil) -> CompanionEvent {
        CompanionEvent(profileID: owner, operationID: UUID(), kind: kind, committedAt: at ?? t)
    }

    private func attached() -> CompanionPresentation {
        let presentation = CompanionPresentation()
        presentation.attach(profileID: owner, existingEvents: [], now: t)
        return presentation
    }

    private func resting() -> CompanionPresentation {
        let presentation = attached()
        presentation.characterChanged(now: t)
        #expect(presentation.resolve(context: context(), now: t).pose == .resting)
        return presentation
    }

    @Test func coveredSuccessExpiresAtTenSecondsWithoutReplaying() {
        let presentation = attached()
        presentation.receive(event(), now: t)
        #expect(presentation.resolve(context: context(playback: .hidden), now: t).nextDeadline == nil)
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(MivuMotion.feedbackLifetime)).pose != .saved)
    }

    @Test func freshHiddenSuccessPlaysOnceJustBeforeExpiry() {
        let presentation = attached()
        presentation.receive(event(), now: t)
        _ = presentation.resolve(context: context(playback: .hidden), now: t)
        let start = t.addingTimeInterval(MivuMotion.feedbackLifetime - 0.001)
        let success = presentation.resolve(context: context(), now: start)
        #expect(success.pose == .saved)
        #expect(success.reactionID != nil)
        #expect(success.nextDeadline == start.addingTimeInterval(MivuMotion.saved))
        #expect(presentation.resolve(context: context(), now: start.addingTimeInterval(MivuMotion.saved)).pose != .saved)
    }

    @Test func initialAttachmentNeverReplaysExistingReceipts() {
        let presentation = CompanionPresentation()
        let receipt = event()
        presentation.attach(profileID: owner, existingEvents: [receipt], now: t)
        presentation.receive(receipt, now: t)
        #expect(presentation.resolve(context: context(), now: t).pose != .saved)
    }

    @Test func duplicateIdentityIgnoresChangedTimestampButNewOperationReacts() {
        let presentation = attached()
        let receipt = event()
        presentation.receive(receipt, now: t)
        let first = presentation.resolve(context: context(), now: t)
        let duplicateAt = t.addingTimeInterval(MivuMotion.saved + 0.1)
        _ = presentation.resolve(context: context(), now: duplicateAt)
        presentation.receive(CompanionEvent(profileID: owner, operationID: receipt.operationID,
            kind: .saved, committedAt: duplicateAt), now: duplicateAt)
        #expect(presentation.resolve(context: context(), now: duplicateAt).pose != .saved)
        let secondAt = duplicateAt.addingTimeInterval(1)
        presentation.receive(event(at: secondAt), now: secondAt)
        let second = presentation.resolve(context: context(), now: secondAt)
        #expect(second.pose == .saved)
        #expect(second.reactionID != nil)
        #expect(second.reactionID != first.reactionID)
    }

    @Test func newestPendingEventReplacesOlderAndOutOfOrderReceipts() {
        let presentation = attached()
        presentation.receive(event(), now: t)
        presentation.receive(event(kind: .reviewed, at: t.addingTimeInterval(1)), now: t.addingTimeInterval(1))
        presentation.receive(event(at: t), now: t.addingTimeInterval(2))
        let output = presentation.resolve(context: context(), now: t.addingTimeInterval(2))
        #expect(output.pose == .reviewed)
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(3)).pose != .saved)
    }

    @Test func unrelatedProfileEventIsIgnored() {
        let presentation = attached()
        presentation.receive(CompanionEvent(profileID: UUID(), operationID: UUID(), kind: .saved,
            committedAt: t), now: t)
        #expect(presentation.resolve(context: context(), now: t).pose != .saved)
    }

    @Test(arguments: [true, false])
    func backgroundOrNilProfileClearsFeedbackAndDeadlines(background: Bool) {
        let presentation = attached()
        let receipt = event()
        presentation.receive(receipt, now: t)
        _ = presentation.resolve(context: context(), now: t)
        if background { presentation.enterBackground() }
        else { presentation.attach(profileID: nil, existingEvents: [], now: t) }
        let hidden = presentation.resolve(context: context(), now: t)
        #expect(hidden.playback == .hidden)
        #expect(hidden.reactionID == nil)
        #expect(hidden.nextDeadline == nil)
        presentation.attach(profileID: owner, existingEvents: [receipt], now: t.addingTimeInterval(1))
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(1)).pose != .saved)
    }

    @Test func typingCancelsSuccessPermanently() {
        let presentation = attached()
        presentation.receive(event(), now: t)
        _ = presentation.resolve(context: context(), now: t)
        let focused = presentation.resolve(context: context(typing: true, processing: true), now: t.addingTimeInterval(0.1))
        #expect(focused.pose == .attentive)
        #expect(focused.reactionID == nil)
        #expect(focused.nextDeadline == nil)
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(0.2)).pose != .saved)
    }

    @Test func recoveryWinsAndCancelsFeedback() {
        let presentation = attached()
        presentation.receive(event(), now: t)
        let recovery = presentation.resolve(context: context(typing: true, processing: true, recovery: true), now: t)
        #expect(recovery.pose == .recovery)
        #expect(recovery.nextDeadline == nil)
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(0.1)).pose != .saved)
    }

    @Test func savedFinishesAtConfiguredDurationAndProcessingResumes() {
        let presentation = attached()
        presentation.receive(event(), now: t)
        #expect(presentation.resolve(context: context(processing: true), now: t).pose == .saved)
        #expect(presentation.resolve(context: context(processing: true), now: t.addingTimeInterval(MivuMotion.saved - 0.001)).pose == .saved)
        let resumed = presentation.resolve(context: context(processing: true), now: t.addingTimeInterval(MivuMotion.saved))
        #expect(resumed.pose == .thinking)
        #expect(resumed.nextDeadline == nil)
    }

    @Test func reviewedFinishesAtConfiguredDuration() {
        let presentation = attached()
        presentation.receive(event(kind: .reviewed), now: t)
        #expect(presentation.resolve(context: context(), now: t).pose == .reviewed)
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(MivuMotion.reviewed - 0.001)).pose == .reviewed)
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(MivuMotion.reviewed)).pose == .resting)
    }

    @Test func foregroundGreetingIsSharedAcrossRoots() {
        let presentation = attached()
        let greeting = presentation.resolve(context: context(), now: t)
        #expect(greeting.pose == .greeting)
        #expect(greeting.reactionID != nil)
        #expect(greeting.nextDeadline == t.addingTimeInterval(MivuMotion.greeting))
        #expect(presentation.resolve(context: context(surface: .coach), now: t.addingTimeInterval(0.3)) == greeting)
        #expect(presentation.resolve(context: context(surface: .coach), now: t.addingTimeInterval(MivuMotion.greeting)).pose == .resting)
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(MivuMotion.greeting + 0.1)).pose == .resting)
        presentation.enterBackground()
        let foregroundAt = t.addingTimeInterval(MivuMotion.greeting + 0.2)
        presentation.attach(profileID: owner, existingEvents: [], now: foregroundAt)
        #expect(presentation.resolve(context: context(), now: foregroundAt).pose == .greeting)
    }

    @Test(arguments: [true, false])
    func repeatResolutionKeepsReactionIdentityAndDeadline(success: Bool) {
        let presentation = attached()
        if success { presentation.receive(event(), now: t) }
        let first = presentation.resolve(context: context(), now: t)
        #expect(first.reactionID != nil)
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(0.1)) == first)
    }

    @Test func restingAndAttentiveOutputsHaveNoPresentationDeadline() {
        let presentation = resting()
        let rest = presentation.resolve(context: context(), now: t)
        #expect(rest.pose == .resting)
        #expect(rest.nextDeadline == nil)
        #expect(rest.reactionID == nil)
        let restingLater = presentation.resolve(context: context(), now: t.addingTimeInterval(120))
        #expect(restingLater.pose == .resting)
        #expect(restingLater.nextDeadline == nil)
        #expect(restingLater.reactionID == nil)
        let attentive = presentation.resolve(context: context(typing: true), now: t.addingTimeInterval(121))
        #expect(attentive.pose == .attentive)
        #expect(attentive.nextDeadline == nil)
        #expect(attentive.reactionID == nil)
        let resumed = presentation.resolve(context: context(), now: t.addingTimeInterval(130))
        #expect(resumed.pose == .resting)
        #expect(resumed.nextDeadline == nil)
        #expect(resumed.reactionID == nil)
    }

    @Test(arguments: ["focus", "processing", "hidden", "background", "reducedMotion", "lowPower", "thermal", "character"])
    func interruptedRestResumesWithoutDeadlineOrStaleReaction(interruption: String) {
        let presentation = resting()
        let interruptedAt = t.addingTimeInterval(1)
        switch interruption {
        case "focus": _ = presentation.resolve(context: context(typing: true), now: interruptedAt)
        case "processing": _ = presentation.resolve(context: context(processing: true), now: interruptedAt)
        case "background": presentation.enterBackground()
        case "character": presentation.characterChanged(now: interruptedAt)
        case "reducedMotion", "lowPower", "thermal":
            _ = presentation.resolve(context: context(playback: .staticPose), now: interruptedAt)
        default: _ = presentation.resolve(context: context(playback: .hidden), now: interruptedAt)
        }
        let renewedAt = t.addingTimeInterval(30)
        if interruption == "background" {
            presentation.attach(profileID: owner, existingEvents: [], now: renewedAt)
            _ = presentation.resolve(context: context(typing: true), now: renewedAt)
        }
        let renewed = presentation.resolve(context: context(), now: renewedAt)
        #expect(renewed.pose == .resting)
        #expect(renewed.reactionID == nil)
        #expect(renewed.nextDeadline == nil)
        #expect(presentation.resolve(context: context(), now: renewedAt.addingTimeInterval(120)) == renewed)
    }

    @Test func hidingActiveReactionCancelsItWithoutReplay() {
        let presentation = attached()
        presentation.receive(event(), now: t)
        _ = presentation.resolve(context: context(), now: t)
        let hidden = presentation.resolve(context: context(playback: .hidden), now: t.addingTimeInterval(0.1))
        #expect(hidden.nextDeadline == nil)
        #expect(hidden.reactionID == nil)
        #expect(presentation.resolve(context: context(processing: true), now: t.addingTimeInterval(0.2)).pose == .thinking)
    }

    @Test func constrainedMotionConsumesSuccessWithoutReplay() {
        let presentation = attached()
        presentation.receive(event(), now: t)
        let constrained = presentation.resolve(context: context(processing: true, playback: .staticPose), now: t)
        #expect(constrained.pose == .thinking)
        #expect(constrained.playback == .staticPose)
        #expect(constrained.nextDeadline == nil)
        #expect(constrained.reactionID == nil)
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(1)).pose == .resting)
    }

    @Test func characterChangeDropsReactionWithoutClearingReceiptDedup() {
        let presentation = attached()
        let receipt = event()
        presentation.receive(receipt, now: t)
        _ = presentation.resolve(context: context(), now: t)
        presentation.characterChanged(now: t.addingTimeInterval(0.1))
        let changed = presentation.resolve(context: context(processing: true), now: t.addingTimeInterval(0.1))
        #expect(changed.pose == .resting)
        #expect(changed.reactionID == nil)
        presentation.receive(receipt, now: t.addingTimeInterval(0.2))
        #expect(presentation.resolve(context: context(processing: true), now: t.addingTimeInterval(0.2)).pose == .thinking)
        presentation.receive(event(at: t.addingTimeInterval(1)), now: t.addingTimeInterval(1))
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(1)).pose == .saved)
    }

    @Test func profileChangePreservesNoPriorCompanionEvent() {
        let presentation = attached()
        let receipt = event()
        presentation.receive(receipt, now: t)
        presentation.attach(profileID: UUID(), existingEvents: [], now: t)
        presentation.receive(receipt, now: t)
        #expect(presentation.resolve(context: context(), now: t).pose != .saved)
        presentation.attach(profileID: owner, existingEvents: [receipt], now: t)
        presentation.receive(receipt, now: t)
        #expect(presentation.resolve(context: context(), now: t).pose != .saved)
    }

    @Test func missingRootHidesAndCancelsDeadlines() {
        let presentation = resting()
        let hidden = presentation.resolve(context: context(surface: nil), now: t.addingTimeInterval(12))
        #expect(hidden.playback == .hidden)
        #expect(hidden.nextDeadline == nil)
        #expect(hidden.reactionID == nil)
    }
    @Test func processingInterruptsGreetingWithoutDeadline() {
        let presentation = attached()
        let start = t
        #expect(presentation.resolve(context: context(), now: start).reactionID != nil)
        let interrupted = presentation.resolve(context: context(processing: true), now: start.addingTimeInterval(0.05))
        #expect(interrupted.pose == .thinking)
        #expect(interrupted.reactionID == nil)
        #expect(interrupted.nextDeadline == nil)
    }

    @Test(arguments: [true, false])
    func receiptPredatingAttachmentNeverReplays(afterBackground: Bool) {
        let presentation = attached()
        let receipt = event()
        let attachedAt = t.addingTimeInterval(1)
        if afterBackground {
            presentation.enterBackground()
        } else {
            presentation.attach(profileID: nil, existingEvents: [], now: t)
        }
        presentation.attach(profileID: owner, existingEvents: [], now: attachedAt)
        presentation.receive(receipt, now: attachedAt)
        #expect(presentation.resolve(context: context(), now: attachedAt).pose != .saved)
    }

    @Test(arguments: [CompanionEvent.Kind.saved, .reviewed])
    func hiddenTypingPermanentlyCancelsPendingSuccess(kind: CompanionEvent.Kind) {
        let presentation = attached()
        presentation.receive(event(kind: kind), now: t)
        let hidden = presentation.resolve(context: context(typing: true, playback: .hidden),
            now: t.addingTimeInterval(0.1))
        #expect(hidden.playback == .hidden)
        #expect(hidden.pose == .attentive)
        #expect(hidden.reactionID == nil)
        #expect(hidden.nextDeadline == nil)
        let visible = presentation.resolve(context: context(), now: t.addingTimeInterval(1))
        #expect(visible.pose != .saved)
        #expect(visible.pose != .reviewed)
    }

    @Test(arguments: [CompanionEvent.Kind.saved, .reviewed])
    func hiddenRecoveryPermanentlyCancelsPendingSuccess(kind: CompanionEvent.Kind) {
        let presentation = attached()
        presentation.receive(event(kind: kind), now: t)
        let hidden = presentation.resolve(context: context(recovery: true, playback: .hidden),
            now: t.addingTimeInterval(0.1))
        #expect(hidden.playback == .hidden)
        #expect(hidden.pose == .recovery)
        #expect(hidden.reactionID == nil)
        #expect(hidden.nextDeadline == nil)
        let visible = presentation.resolve(context: context(), now: t.addingTimeInterval(1))
        #expect(visible.pose != .saved)
        #expect(visible.pose != .reviewed)
    }

}
