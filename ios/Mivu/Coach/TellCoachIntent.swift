import AppIntents
import UIKit

enum TellCoachOutcome: Equatable {
    case sent, savedLocked, savedNeedsConnection, needsSetup, failed
    var dialog: String {
        switch self {
        case .sent: "Sent to the Coach."
        case .savedLocked: "Saved. Open Mivu after you unlock to see the Coach's reply."
        case .savedNeedsConnection: "Saved. Open Mivu to connect the Coach."
        case .needsSetup: "Open Mivu to finish setup first."
        case .failed: "I couldn't save that. Please try again."
        }
    }
}

/// Saves a spoken message before Siri answers: into Coach history when the diary can open,
/// otherwise into the lock-safe inbox for the next unlock.
@MainActor enum TellCoach {
    static func run(_ text: String, services: MivuServices, defaults: UserDefaults, protectedDataAvailable: Bool,
                    appActive: Bool, now: Date = Date(), onBackgroundCapture: @MainActor (UUID) -> Void) async -> TellCoachOutcome {
        // The Coach composer's limit; a longer locked entry could never be captured and would block the inbox.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 20_000 else { return .failed }
        guard protectedDataAvailable else {
            // The diary file is locked; the selected profile is remembered in defaults, which stay readable.
            guard !defaults.bool(forKey: "diarySignedOut"),
                  let profileID = defaults.string(forKey: "diarySelectedProfile").flatMap(UUID.init(uuidString:)) else { return .needsSetup }
            guard defaults.bool(forKey: AdultEligibility.lockedKey(profileID)) else { return .needsSetup }
            do { try services.inbox.add(CoachInbox.Entry(id: UUID(), profileID: profileID, text: text, capturedAt: now)) } catch { return .failed }
            return .savedLocked
        }
        // Save first; restoring the connection can wait on the network.
        await services.loadDiary(createDefaultProfile: false)
        guard let profileID = services.diary.selection?.identity.profileID else { return .needsSetup }
        guard services.diary.isAdultEligible else { return .needsSetup }
        await services.coach.drainInbox(services.inbox)
        let id = UUID()
        func capture() async throws { try await services.coach.captureExternal(profileID: profileID, text, submissionID: id, capturedAt: now) }
        do { try await capture() } catch {
            // A throw can follow a committed save; the same ID reconciles instead of saving twice.
            do { try await capture() } catch { return .failed }
        }
        if !appActive { onBackgroundCapture(id) }
        await services.start(createDefaultProfile: false)
        return services.connection.canInfer ? .sent : .savedNeedsConnection
    }
}

struct TellCoachIntent: AppIntent {
    static let title: LocalizedStringResource = "Tell Coach"
    static let description = IntentDescription("Sends a message to Mivu Coach without opening the app.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Message", requestValueDialog: "What should I tell the Coach?")
    var message: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = MivuServices.shared
        let outcome = await TellCoach.run(message, services: services, defaults: DiaryLaunch.defaults,
                                          protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable,
                                          // Siri over an open Mivu leaves it inactive, not backgrounded.
                                          appActive: UIApplication.shared.applicationState != .background,
                                          onBackgroundCapture: { CoachReplyNotification.follow($0, services: services) })
        // Not awaited: Siri answers now, and a prompt that cannot show in the background must not hold the reply.
        if outcome == .sent || outcome == .savedNeedsConnection { Task { await MealNotification.requestPermissionIfNeeded() } }
        return .result(dialog: IntentDialog(stringLiteral: outcome.dialog))
    }
}
