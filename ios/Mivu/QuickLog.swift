import AppIntents
import Observation
import UIKit
import UserNotifications

/// A pending request to open the camera and log food, or to open Coach, from Shortcuts, Siri, the Action button or the Home Screen.
@MainActor @Observable final class QuickLogRequest {
    static let shared = QuickLogRequest()
    static let shortcutType = "com.yakov103.mivu.log-food"
    var pending = DiaryLaunch.isUITest && CommandLine.arguments.contains("--quick-log")
    var openCoach = DiaryLaunch.isUITest && CommandLine.arguments.contains("--open-coach")

    @discardableResult func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type == Self.shortcutType else { return false }
        pending = true
        return true
    }
}

struct MivuShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogFoodIntent(), phrases: ["Snap it with \(.applicationName)", "Snap a meal in \(.applicationName)"],
                    shortTitle: "Snap It", systemImageName: "camera")
        AppShortcut(intent: LogMealIntent(), phrases: ["Log a meal in \(.applicationName)", "Log food with \(.applicationName)"],
                    shortTitle: "Log Meal", systemImageName: "fork.knife")
        AppShortcut(intent: OpenCoachIntent(), phrases: ["Ask \(.applicationName) Coach", "Open \(.applicationName) Coach"],
                    shortTitle: "Coach", systemImageName: "bubble.left.fill")
        AppShortcut(intent: ExportDiaryIntent(), phrases: ["Export my diary from \(.applicationName)"],
                    shortTitle: "Export Diary", systemImageName: "square.and.arrow.up")
        AppShortcut(intent: TellCoachIntent(), phrases: ["Tell \(.applicationName)", "Tell \(.applicationName) Coach", "Message \(.applicationName) Coach"],
                    shortTitle: "Tell Coach", systemImageName: "bubble.left.and.text.bubble.right")
    }
}

// shortcut: Log Meal opens the same camera as Snap It for now; give it its own flow when that is designed.
struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Meal"
    static let description = IntentDescription("Opens the camera to log a meal.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        QuickLogRequest.shared.pending = true
        return .result()
    }
}

final class MivuAppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Set before launch finishes so a tap that cold-launches the app is still delivered.
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    // Main-actor completion form: the async form finished off the main thread and UIKit crashed the app on tap.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let id = MealNotification.mealID(from: userInfo) { MealNotification.shared.openedMealID = id }
        if CoachReplyNotification.turnID(from: userInfo) != nil { QuickLogRequest.shared.openCoach = true }
        completionHandler()
    }
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
