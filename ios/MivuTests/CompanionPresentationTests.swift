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
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(10)).pose != .saved)
    }

    @Test func freshHiddenSuccessPlaysOnceJustBeforeExpiry() {
        let presentation = attached()
        presentation.receive(event(), now: t)
        _ = presentation.resolve(context: context(playback: .hidden), now: t)
        let start = t.addingTimeInterval(9.999)
        let success = presentation.resolve(context: context(), now: start)
        #expect(success.pose == .saved)
        #expect(success.reactionID != nil)
        #expect(success.nextDeadline == start.addingTimeInterval(0.45))
        #expect(presentation.resolve(context: context(), now: start.addingTimeInterval(0.45)).pose != .saved)
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
        _ = presentation.resolve(context: context(), now: t.addingTimeInterval(0.45))
        presentation.receive(CompanionEvent(profileID: owner, operationID: receipt.operationID,
            kind: .saved, committedAt: t.addingTimeInterval(1)), now: t.addingTimeInterval(1))
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(1)).pose != .saved)
        presentation.receive(event(at: t.addingTimeInterval(2)), now: t.addingTimeInterval(2))
        let second = presentation.resolve(context: context(), now: t.addingTimeInterval(2))
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

    @Test func savedFinishesAt450MillisecondsAndProcessingResumes() {
        let presentation = attached()
        presentation.receive(event(), now: t)
        #expect(presentation.resolve(context: context(processing: true), now: t).pose == .saved)
        #expect(presentation.resolve(context: context(processing: true), now: t.addingTimeInterval(0.449)).pose == .saved)
        let resumed = presentation.resolve(context: context(processing: true), now: t.addingTimeInterval(0.45))
        #expect(resumed.pose == .thinking)
        #expect(resumed.nextDeadline == nil)
    }

    @Test func reviewedFinishesAt650Milliseconds() {
        let presentation = attached()
        presentation.receive(event(kind: .reviewed), now: t)
        #expect(presentation.resolve(context: context(), now: t).pose == .reviewed)
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(0.649)).pose == .reviewed)
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(0.65)).pose == .resting)
    }

    @Test func foregroundGreetingIsSharedAcrossRoots() {
        let presentation = attached()
        let greeting = presentation.resolve(context: context(), now: t)
        #expect(greeting.pose == .greeting)
        #expect(greeting.reactionID != nil)
        #expect(greeting.nextDeadline == t.addingTimeInterval(0.7))
        #expect(presentation.resolve(context: context(surface: .coach), now: t.addingTimeInterval(0.3)) == greeting)
        #expect(presentation.resolve(context: context(surface: .coach), now: t.addingTimeInterval(0.7)).pose == .resting)
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(1)).pose == .resting)
        presentation.enterBackground()
        presentation.attach(profileID: owner, existingEvents: [], now: t.addingTimeInterval(2))
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(2)).pose == .greeting)
    }

    @Test(arguments: [true, false])
    func repeatResolutionKeepsReactionIdentityAndDeadline(success: Bool) {
        let presentation = attached()
        if success { presentation.receive(event(), now: t) }
        let first = presentation.resolve(context: context(), now: t)
        #expect(first.reactionID != nil)
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(0.1)) == first)
    }

    @Test func restBlinkUsesTwelveSecondDeadlineAndLasts150Milliseconds() {
        let presentation = resting()
        let rest = presentation.resolve(context: context(), now: t)
        #expect(rest.nextDeadline == t.addingTimeInterval(12))
        #expect(rest.reactionID == nil)
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(11.999)).reactionID == nil)
        let blink = presentation.resolve(context: context(), now: t.addingTimeInterval(12))
        #expect(blink.pose == .resting)
        #expect(blink.reactionID != nil)
        #expect(blink.nextDeadline == t.addingTimeInterval(12.15))
        #expect(presentation.resolve(context: context(), now: t.addingTimeInterval(12.1)) == blink)
        let settled = presentation.resolve(context: context(), now: t.addingTimeInterval(12.15))
        #expect(settled.reactionID == nil)
        #expect(settled.nextDeadline == t.addingTimeInterval(24.15))
    }

    @Test(arguments: ["focus", "processing", "hidden", "covered", "background", "reducedMotion", "lowPower", "thermal", "character"])
    func interruptedRestStartsNewFullBlinkIntervalWithoutCatchUp(interruption: String) {
        let presentation = resting()
        let interruptedAt = t.addingTimeInterval(11.9)
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
        #expect(renewed.nextDeadline == renewedAt.addingTimeInterval(12))
        #expect(presentation.resolve(context: context(), now: renewedAt.addingTimeInterval(11.999)).reactionID == nil)
        #expect(presentation.resolve(context: context(), now: renewedAt.addingTimeInterval(12)).reactionID != nil)
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
    @Test(arguments: [true, false])
    func processingInterruptsGreetingOrBlink(greeting: Bool) {
        let presentation = greeting ? attached() : resting()
        let start = greeting ? t : t.addingTimeInterval(12)
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

    @Test func missedBlinkDeadlineDoesNotCatchUp() {
        let presentation = resting()
        let late = t.addingTimeInterval(30)
        let output = presentation.resolve(context: context(), now: late)
        #expect(output.pose == .resting)
        #expect(output.reactionID == nil)
        #expect(output.nextDeadline == late.addingTimeInterval(12))
    }

}
