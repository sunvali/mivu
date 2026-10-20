import Foundation
import Observation

enum CompanionPose: Int, CaseIterable {
    case resting = 0, attentive = 1, thinking = 2, saved = 3
    case reviewed = 4, recovery = 5, greeting = 6, submitted = 7
    case firstMealToday = 8, dayComplete = 9, curious = 10, tapped = 11, patted = 12, welcomeBack = 13
}

enum CompanionSurface: Hashable {
    case today, coach
}

struct CompanionEvent: Equatable {
    enum Kind: Hashable {
        case saved, reviewed, firstMealToday, dayComplete, photoAdded

        fileprivate var pose: CompanionPose {
            switch self {
            case .saved: .saved
            case .reviewed: .reviewed
            case .firstMealToday: .firstMealToday
            case .dayComplete: .dayComplete
            case .photoAdded: .curious
            }
        }

        fileprivate var duration: TimeInterval {
            switch self {
            case .saved: MivuMotion.saved
            case .reviewed: MivuMotion.reviewed
            case .firstMealToday: MivuMotion.firstMealToday
            case .dayComplete: MivuMotion.dayComplete
            case .photoAdded: MivuMotion.curious
            }
        }
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

struct CompanionSubmission: Equatable {
    let profileID: UUID
    let operationID: UUID
    let acceptedAt: Date
    let attemptID: UUID

    init(profileID: UUID, operationID: UUID, acceptedAt: Date, attemptID: UUID = UUID()) {
        self.profileID = profileID
        self.operationID = operationID
        self.acceptedAt = acceptedAt
        self.attemptID = attemptID
    }

    fileprivate struct Key: Hashable {
        let profileID: UUID
        let operationID: UUID
        let attemptID: UUID
    }
    fileprivate var key: Key { Key(profileID: profileID, operationID: operationID, attemptID: attemptID) }
}

struct CompanionContext {
    var surface: CompanionSurface?
    var isTyping: Bool
    var isProcessing: Bool
    var needsRecovery: Bool
    var playback: MotionPolicy.Playback
    var draftLength: Int = 0

    /// The gaze only follows the first 60 characters, so longer drafts need no further updates.
    static func draftSignal(_ length: Int) -> Int { min(max(length, 0), 60) }
}

enum CompanionTouch { case tap, pat }

struct CompanionOutput: Equatable {
    let pose: CompanionPose
    let playback: MotionPolicy.Playback
    let reactionID: UUID?
    let nextDeadline: Date?
    var tapLevel = 0
    var typingProgress = 0.0
}

@MainActor @Observable final class CompanionPresentation {
    private struct Reaction {
        let pose: CompanionPose
        let id = UUID()
        let deadline: Date
        var tapLevel = 0
    }

    private var profileID: UUID?
    private var attachedAt: Date?
    private var received: Set<CompanionEvent.Key> = []
    private var receivedSubmissions: Set<CompanionSubmission.Key> = []
    private var pendingSubmission: CompanionSubmission?
    private var pending: CompanionEvent?
    private var latestCommit: Date?
    private var active: Reaction?
    private var greetingAvailable = true
    private var welcomeBackDue = false
    private var lastContext: CompanionContext?
    private var typingProgress = 0.0
    private var lastTapAt: Date?
    private var tapCount = 0
    private var tapTurn = 0
    private let calendar: Calendar
    private var showRestAfterCharacterChange = false

    init(calendar: Calendar = .current) { self.calendar = calendar }

    func attach(profileID: UUID?, existingEvents: [CompanionEvent],
                existingSubmissions: [CompanionSubmission] = [], now: Date,
                lastActiveAt: Date? = nil) {
        if self.profileID != profileID {
            clearReactions()
            attachedAt = profileID == nil ? nil : now
            latestCommit = nil
            showRestAfterCharacterChange = false
            welcomeBackDue = false
            tapCount = 0
            tapTurn = 0
            lastTapAt = nil
        }
        self.profileID = profileID
        if let lastActiveAt {
            welcomeBackDue = calendar.startOfDay(for: lastActiveAt) < calendar.startOfDay(for: now)
        }
        for event in existingEvents where event.profileID == profileID {
            received.insert(event.key)
        }
        for submission in existingSubmissions where submission.profileID == profileID {
            receivedSubmissions.insert(submission.key)
        }
        if profileID == nil { clearReactions() }
    }

    @discardableResult func receive(_ submission: CompanionSubmission, now: Date) -> Bool {
        guard submission.profileID == profileID,
              receivedSubmissions.insert(submission.key).inserted else { return false }
        let age = now.timeIntervalSince(submission.acceptedAt)
        guard age >= 0, age < MivuMotion.feedbackLifetime else { return false }
        if let attachedAt, submission.acceptedAt < attachedAt { return false }
        if let latestCommit, submission.acceptedAt < latestCommit { return false }
        clearReactions()
        pendingSubmission = submission
        showRestAfterCharacterChange = false
        return true
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
        if let pendingSubmission, now.timeIntervalSince(pendingSubmission.acceptedAt) >= MivuMotion.feedbackLifetime {
            self.pendingSubmission = nil
        }
        if let pending, now.timeIntervalSince(pending.committedAt) >= MivuMotion.feedbackLifetime {
            self.pending = nil
        }
        lastContext = context
        typingProgress = Double(CompanionContext.draftSignal(context.draftLength)) / 60
        let semanticPose: CompanionPose = context.needsRecovery ? .recovery
            : context.isTyping ? .attentive : context.isProcessing ? .thinking : .resting
        let playback: MotionPolicy.Playback = profileID == nil || context.surface == nil
            ? .hidden : context.playback

        if context.needsRecovery || context.isTyping {
            clearReactions()
            greetingAvailable = false
        }

        guard playback != .hidden else {
            if pendingSubmission != nil || active?.pose == .submitted { clearReactions() }
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

        if pendingSubmission != nil {
            pendingSubmission = nil
            greetingAvailable = false
            active = Reaction(pose: .submitted, deadline: now.addingTimeInterval(MivuMotion.submitted))
        }

        if let active, active.pose == .submitted, now < active.deadline {
            return output(pose: .submitted, playback: playback, reaction: active)
        }

        if let pending {
            self.pending = nil
            greetingAvailable = false
            active = Reaction(pose: pending.kind.pose, deadline: now.addingTimeInterval(pending.kind.duration))
        }

        if context.isProcessing, let active, [.greeting, .welcomeBack, .resting, .tapped, .patted].contains(active.pose) {
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
            let pose: CompanionPose = welcomeBackDue ? .welcomeBack : .greeting
            welcomeBackDue = false
            let greeting = Reaction(pose: pose, deadline: now.addingTimeInterval(
                pose == .welcomeBack ? MivuMotion.welcomeBack : MivuMotion.greeting))
            active = greeting
            return output(pose: pose, playback: playback, reaction: greeting)
        }

        return output(pose: .resting, playback: playback)
    }

    /// False means the caller should only twitch an ear: no reaction is started or queued.
    @discardableResult func touch(_ kind: CompanionTouch, now: Date) -> Bool {
        guard let context = lastContext, context.playback == .animated, context.surface != nil, profileID != nil,
              !context.needsRecovery, !context.isTyping, !context.isProcessing,
              pending == nil, pendingSubmission == nil else { return false }
        if let active, now < active.deadline, ![.greeting, .welcomeBack, .tapped, .patted].contains(active.pose) {
            return false
        }
        greetingAvailable = false
        var reaction: Reaction
        switch kind {
        case .pat:
            reaction = Reaction(pose: .patted, deadline: now.addingTimeInterval(MivuMotion.patted))
        case .tap:
            let rapid = lastTapAt.map { now.timeIntervalSince($0) <= 1.5 } ?? false
            tapCount = rapid ? tapCount + 1 : 0
            let shakeOff = tapCount == 4 // a rapid burst ends in the shake-off; every other tap takes the next reaction in the set
            reaction = Reaction(pose: .tapped, deadline: now.addingTimeInterval(MivuMotion.tapped), tapLevel: shakeOff ? 4 : tapTurn % 4)
            if !shakeOff { tapTurn += 1 }
            lastTapAt = shakeOff ? nil : now // the shake-off resets the run
        }
        active = reaction
        return true
    }

    func enterBackground() {
        profileID = nil
        attachedAt = nil
        received.removeAll()
        receivedSubmissions.removeAll()
        latestCommit = nil
        clearReactions()
        greetingAvailable = true
        lastContext = nil
        lastTapAt = nil
        welcomeBackDue = false
        tapCount = 0
        tapTurn = 0
        showRestAfterCharacterChange = false
    }

    func characterChanged(now: Date) {
        clearReactions()
        greetingAvailable = false
        showRestAfterCharacterChange = true
    }

    private func clearReactions() {
        pendingSubmission = nil
        pending = nil
        active = nil
    }

    private func output(
        pose: CompanionPose, playback: MotionPolicy.Playback,
        reaction: Reaction? = nil, deadline: Date? = nil
    ) -> CompanionOutput {
        CompanionOutput(pose: pose, playback: playback, reactionID: reaction?.id,
                        nextDeadline: reaction?.deadline ?? deadline,
                        tapLevel: pose == .tapped ? reaction?.tapLevel ?? 0 : 0, typingProgress: typingProgress)
    }
}

/// Remembers when each profile last used the app, so Pip can welcome them back after a day away.
struct CompanionLastActive {
    let defaults: UserDefaults
    private func key(_ profileID: UUID) -> String { "companion.lastActive." + profileID.uuidString }
    func date(for profileID: UUID) -> Date? { defaults.object(forKey: key(profileID)) as? Date }
    func record(_ date: Date, for profileID: UUID) { defaults.set(date, forKey: key(profileID)) }
    func forget(_ profileID: UUID) { defaults.removeObject(forKey: key(profileID)) }

    /// Attaches the presentation with this profile's stored last-active date so a day away becomes a welcome back.
    @MainActor func attach(_ presentation: CompanionPresentation, profileID: UUID?, existingEvents: [CompanionEvent],
                           existingSubmissions: [CompanionSubmission], now: Date) {
        presentation.attach(profileID: profileID, existingEvents: existingEvents, existingSubmissions: existingSubmissions,
                            now: now, lastActiveAt: profileID.flatMap { date(for: $0) })
    }
}
