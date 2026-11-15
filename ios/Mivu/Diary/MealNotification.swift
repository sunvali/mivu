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

    /// Nil for meals that will be retried or were stopped: they say nothing about what the food was.
    nonisolated static func text(for meal: MealReadModel) -> (title: String, body: String)? {
        let review = meal.state == .awaitingReview
        // An estimate awaiting review lives in the submission's proposal until it is accepted.
        let items = review ? meal.submissions.last?.proposal?.items ?? [] : meal.items
        guard !items.isEmpty else {
            return [.captured, .saved].contains(meal.state) ? (String(localized: "Couldn't recognize your meal"), String(localized: "Tap to add a note so Mivu can log it.")) : nil
        }
        let names = items.map(\.name)
        let name = switch names.count {
        case 1: names[0]
        case 2: String(localized: "\(names[0]) and \(names[1])")
        default: String(localized: "\(names[0]), \(names[1]) and \(names.count - 2) more")
        }
        // Foods without calories are left out of the sum, so the figure is a floor.
        let partial = items.contains { $0.nutrition.kcal == nil }
        // Plain digits, as before: an Int placeholder would add grouping.
        let kcal = nutritionTotals(items).kcal.map { String(Int($0.rounded())) }
        if review {
            guard let kcal else { return (String(localized: "\(name) is ready to review"), String(localized: "Tap to review")) }
            return (String(localized: "\(name) is ready to review"), partial ? String(localized: "At least \(kcal) kcal · Tap to review") : String(localized: "About \(kcal) kcal · Tap to review"))
        }
        let calories = kcal.map { partial ? String(localized: "At least \($0) kcal") : String(localized: "\($0) kcal") }
        return (String(localized: "\(name) logged"), calories ?? String(localized: "Calories not known yet"))
    }

    nonisolated static func post(_ meal: MealReadModel) {
        guard let text = text(for: meal) else { return }
        let content = UNMutableNotificationContent()
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
