import Foundation
import UserNotifications

/// The Coach's answer to a Siri message, sent once the background run finishes.
/// iOS does not show it while Mivu is open, where the Coach tab already shows the reply.
enum CoachReplyNotification {
    nonisolated static let turnKey = "coachTurnID"
    nonisolated static func identifier(for turnID: UUID) -> String { "coach-reply-" + turnID.uuidString }
    nonisolated static func turnID(from userInfo: [AnyHashable: Any]) -> UUID? {
        (userInfo[turnKey] as? String).flatMap(UUID.init(uuidString:))
    }

    /// Nil while the turn is still running, and for turns that saved a meal: the worker's MealNotification covers those.
    nonisolated static func text(for turn: CoachTurnResult) -> (title: String, body: String)? {
        guard turn.pendingMealID == nil else { return nil }
        switch turn.state {
        case .captured, .analyzing: return nil
        case .completed:
            let reply = CoachReplyLines.plain(turn.assistantText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty else { return nil }
            return ("Coach", reply.count <= 180 ? reply : String(reply.prefix(179)) + "…")
        case .needsClarification: return ("Coach", "The Coach needs a quick answer.")
        case .needsRetry, .waitingForNetwork, .waitingForConnection: return ("Coach", savedBody)
        }
    }
    private nonisolated static let savedBody = "Your message is saved. Open Mivu for the Coach's reply."

    nonisolated static func post(_ turn: CoachTurnResult) {
        guard let text = text(for: turn) else { return }
        add(turnID: turn.id, title: text.title, body: text.body)
    }
    /// Keyed like the reply, so a reply that still arrives replaces this one.
    nonisolated static func postSaved(turnID: UUID) { add(turnID: turnID, title: "Coach", body: savedBody) }

    /// Keeps the turn processing in the background; posts its reply when the worker drains, the saved note if iOS ends the time first.
    @MainActor static func follow(_ turnID: UUID, services: MivuServices) {
        services.continueCoachInBackground(onExpire: { postSaved(turnID: turnID) })
        Task {
            await services.coach.waitForBackgroundCompletion()
            guard let owner = services.diary.selection?.identity.profileID,
                  let turn = try? await services.diary.store.coachResult(turnID: turnID, expectedProfileID: owner) else { return }
            post(turn)
        }
    }

    private nonisolated static func add(turnID: UUID, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body
        content.userInfo = [turnKey: turnID.uuidString]; content.threadIdentifier = "coach"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier(for: turnID), content: content, trigger: nil))
    }
}
