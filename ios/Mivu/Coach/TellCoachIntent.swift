import AppIntents
import UIKit

enum TellCoachOutcome: Equatable {
    case sent, savedLocked, savedNeedsConnection, needsSetup, failed
    var dialog: String {
        switch self {
        case .sent: "Sent to the Coach."
        case .savedLocked: "Saved. The Coach will reply after you unlock."
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
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failed }
        guard protectedDataAvailable else {
            // The diary file is locked; the selected profile is remembered in defaults, which stay readable.
            guard !defaults.bool(forKey: "diarySignedOut"),
                  let profileID = defaults.string(forKey: "diarySelectedProfile").flatMap(UUID.init(uuidString:)) else { return .needsSetup }
            do { try services.inbox.add(CoachInbox.Entry(id: UUID(), profileID: profileID, text: text, capturedAt: now)) } catch { return .failed }
            return .savedLocked
        }
        await services.start(createDefaultProfile: false)
        guard services.diary.selection != nil else { return .needsSetup }
        await services.coach.drainInbox(services.inbox)
        let id = UUID()
        do { try await services.coach.captureExternal(text, submissionID: id, capturedAt: now) } catch { return .failed }
        if !appActive { onBackgroundCapture(id) }
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
                                          appActive: UIApplication.shared.applicationState == .active,
                                          onBackgroundCapture: { _ in services.continueCoachInBackground() })
        return .result(dialog: IntentDialog(stringLiteral: outcome.dialog))
    }
}
