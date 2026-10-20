import AppIntents
import Observation
import UIKit

/// A pending request to open the camera and log food, from Shortcuts, Siri, the Action button or the Home Screen.
@MainActor @Observable final class QuickLogRequest {
    static let shared = QuickLogRequest()
    static let shortcutType = "com.yakov103.mivu.log-food"
    var pending = DiaryLaunch.isUITest && CommandLine.arguments.contains("--quick-log")

    @discardableResult func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type == Self.shortcutType else { return false }
        pending = true
        return true
    }
}

struct LogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Food"
    static let description = IntentDescription("Opens the camera to photograph a meal and log it.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        QuickLogRequest.shared.pending = true
        return .result()
    }
}

struct MivuShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogFoodIntent(), phrases: ["Log food with \(.applicationName)", "Log a meal in \(.applicationName)"],
                    shortTitle: "Log Food", systemImageName: "camera")
    }
}

final class MivuAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // A cold launch from the Home Screen quick action delivers the item here, not to the scene delegate.
        if let item = options.shortcutItem { QuickLogRequest.shared.handle(item) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = QuickLogSceneDelegate.self
        return configuration
    }
}

final class QuickLogSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        QuickLogRequest.shared.handle(shortcutItem)
    }
}
