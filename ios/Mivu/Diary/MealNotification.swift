import Foundation
import Observation
import UserNotifications

/// A short notification once a logged meal is analyzed. iOS does not show it while Mivu is open, where Today already shows the result.
@MainActor @Observable final class MealNotification {
    static let shared = MealNotification()
    nonisolated static let mealKey = "mealID"
    /// The meal whose notification was tapped; the root opens it.
    var openedMealID: UUID?

    nonisolated static func identifier(for mealID: UUID) -> String { "meal-" + mealID.uuidString }
    nonisolated static func mealID(from userInfo: [AnyHashable: Any]) -> UUID? {
        (userInfo[mealKey] as? String).flatMap(UUID.init(uuidString:))
    }

    nonisolated static func text(for meal: MealReadModel) -> (title: String, body: String) {
        guard !meal.items.isEmpty else { return ("Couldn't recognize your meal", "Tap to add a note so Mivu can log it.") }
        let names = meal.items.map(\.name)
        let name = names.count <= 2 ? names.joined(separator: " and ") : names.prefix(2).joined(separator: ", ") + " and \(names.count - 2) more"
        let calories = meal.totals.kcal.map { "\(Int($0.rounded())) kcal" }
        if meal.state == .awaitingReview { return ("\(name) is ready to review", (calories.map { "About \($0) · " } ?? "") + "Tap to review") }
        return ("\(name) logged", calories ?? "Calories not known yet")
    }

    nonisolated static func post(_ meal: MealReadModel) {
        let text = text(for: meal), content = UNMutableNotificationContent()
        content.title = text.title; content.body = text.body
        content.userInfo = [mealKey: meal.id.uuidString]; content.threadIdentifier = "meals"
        // Keyed by meal, so a later analysis of the same meal replaces this one instead of stacking.
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier(for: meal.id), content: content, trigger: nil))
    }

    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
}
