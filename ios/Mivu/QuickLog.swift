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
        AppShortcut(intent: LogFoodIntent(), phrases: ["Log food with \(.applicationName)", "Log a meal in \(.applicationName)"],
                    shortTitle: "Log Food", systemImageName: "camera")
        AppShortcut(intent: OpenCoachIntent(), phrases: ["Ask \(.applicationName) Coach", "Open \(.applicationName) Coach"],
                    shortTitle: "Coach", systemImageName: "bubble.left.fill")
        AppShortcut(intent: TellCoachIntent(), phrases: ["Tell \(.applicationName)", "Tell \(.applicationName) Coach", "Message \(.applicationName) Coach"],
                    shortTitle: "Tell Coach", systemImageName: "bubble.left.and.text.bubble.right")
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
        if let id = MealNotification.mealID(from: response.notification.request.content.userInfo) { MealNotification.shared.openedMealID = id }
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
