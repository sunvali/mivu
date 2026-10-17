import Foundation
import Observation

enum CompanionPose: Int, CaseIterable {
    case resting = 0, attentive = 1, thinking = 2, saved = 3
    case reviewed = 4, recovery = 5, greeting = 6
}

enum CompanionSurface: Hashable {
    case today, coach
}

struct CompanionEvent: Equatable {
    enum Kind: Hashable {
        case saved, reviewed
    }

    let profileID: UUID
    let operationID: UUID
    let kind: Kind
    let committedAt: Date

    fileprivate struct Key: Hashable {
        let profileID: UUID
        let operationID: UUID
        let kind: Kind
    }

    fileprivate var key: Key {
        Key(profileID: profileID, operationID: operationID, kind: kind)
    }
}

struct CompanionContext {
    var surface: CompanionSurface?
    var isTyping: Bool
    var isProcessing: Bool
    var needsRecovery: Bool
    var playback: MotionPolicy.Playback
}

struct CompanionOutput: Equatable {
    let pose: CompanionPose
    let playback: MotionPolicy.Playback
    let reactionID: UUID?
    let nextDeadline: Date?
}

@MainActor @Observable final class CompanionPresentation {
    private struct Reaction {
        let pose: CompanionPose
        let id = UUID()
        let deadline: Date
    }

    private var profileID: UUID?
    private var attachedAt: Date?
    private var received: Set<CompanionEvent.Key> = []
    private var pending: CompanionEvent?
    private var latestCommit: Date?
    private var active: Reaction?
    private var greetingAvailable = true
    private var showRestAfterCharacterChange = false

    init() {}

    func attach(profileID: UUID?, existingEvents: [CompanionEvent], now: Date) {
        if self.profileID != profileID {
            clearReactions()
            attachedAt = profileID == nil ? nil : now
            latestCommit = nil
            showRestAfterCharacterChange = false
        }
        self.profileID = profileID
        for event in existingEvents where event.profileID == profileID {
            received.insert(event.key)
        }
        if profileID == nil { clearReactions() }
    }

    func receive(_ event: CompanionEvent, now: Date) {
        guard event.profileID == profileID, received.insert(event.key).inserted else { return }
        let age = now.timeIntervalSince(event.committedAt)
        guard age >= 0, age < MivuMotion.feedbackLifetime else { return }
        if let attachedAt, event.committedAt < attachedAt { return }
        if let latestCommit, event.committedAt < latestCommit { return }
        latestCommit = event.committedAt
        pending = event
        showRestAfterCharacterChange = false
    }

    func resolve(context: CompanionContext, now: Date) -> CompanionOutput {
        if let pending, now.timeIntervalSince(pending.committedAt) >= MivuMotion.feedbackLifetime {
            self.pending = nil
        }
        let semanticPose: CompanionPose = context.needsRecovery ? .recovery
            : context.isTyping ? .attentive : context.isProcessing ? .thinking : .resting
        let playback: MotionPolicy.Playback = profileID == nil || context.surface == nil
            ? .hidden : context.playback

        if context.needsRecovery || context.isTyping {
            clearReactions()
            greetingAvailable = false
        }

        guard playback != .hidden else {
            active = nil
            return output(pose: semanticPose, playback: .hidden)
        }

        if showRestAfterCharacterChange {
            showRestAfterCharacterChange = false
            return output(pose: .resting, playback: playback)
        }

        guard playback == .animated else {
            clearReactions()
            greetingAvailable = false
            return output(pose: semanticPose, playback: .staticPose)
        }

        if context.needsRecovery || context.isTyping {
            return output(pose: semanticPose, playback: playback)
        }

        if let pending {
            self.pending = nil
            greetingAvailable = false
            let pose: CompanionPose = pending.kind == .saved ? .saved : .reviewed
            let duration = pending.kind == .saved ? MivuMotion.saved : MivuMotion.reviewed
            active = Reaction(pose: pose, deadline: now.addingTimeInterval(duration))
        }

        if context.isProcessing, let active, active.pose == .greeting || active.pose == .resting {
            self.active = nil
        }

        if let active {
            if now < active.deadline {
                return output(pose: active.pose, playback: playback, reaction: active)
            }
            self.active = nil
        }

        if context.isProcessing {
            greetingAvailable = false
            return output(pose: .thinking, playback: playback)
        }

        if greetingAvailable {
            greetingAvailable = false
            let greeting = Reaction(pose: .greeting, deadline: now.addingTimeInterval(MivuMotion.greeting))
            active = greeting
            return output(pose: .greeting, playback: playback, reaction: greeting)
        }

        return output(pose: .resting, playback: playback)
    }

    func enterBackground() {
        profileID = nil
        attachedAt = nil
        received.removeAll()
        latestCommit = nil
        clearReactions()
        greetingAvailable = true
        showRestAfterCharacterChange = false
    }

    func characterChanged(now: Date) {
        clearReactions()
        greetingAvailable = false
        showRestAfterCharacterChange = true
    }

    private func clearReactions() {
        pending = nil
        active = nil
    }

    private func output(
        pose: CompanionPose, playback: MotionPolicy.Playback,
        reaction: Reaction? = nil, deadline: Date? = nil
    ) -> CompanionOutput {
        CompanionOutput(pose: pose, playback: playback, reactionID: reaction?.id,
                        nextDeadline: reaction?.deadline ?? deadline)
    }
}
