import Foundation
import Observation
import UserNotifications

/// The notification calls the rest timer makes; tests pass a fake.
@MainActor protocol RestNotificationCenter: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func pendingNotificationRequests() async -> [UNNotificationRequest]
}

extension UNUserNotificationCenter: RestNotificationCenter {}

/// The rest countdown after a ticked set. Its end is a scheduled notification with sound,
/// so it still sounds when the phone is locked or Mivu was closed.
@MainActor @Observable final class RestTimer {
    static let shared = RestTimer(center: UNUserNotificationCenter.current(), defaults: .standard)
    static let requestID = "mivu.rest", askedKey = "workoutNotificationAsked", secondsKey = "workoutRestSeconds"

    private(set) var endsAt: Date?
    /// The set after this rest, "Bench press · set 3".
    private(set) var next = ""
    @ObservationIgnored private let center: any RestNotificationCenter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var title = ""
    @ObservationIgnored private var expiry: Task<Void, Never>?

    init(center: any RestNotificationCenter, defaults: UserDefaults, now: @escaping () -> Date = Date.init) {
        self.center = center; self.defaults = defaults; self.now = now
    }

    /// The exercise's own rest, else the person's default (90 seconds).
    func seconds(for exercise: WorkoutExercise) -> Int {
        exercise.restSeconds ?? defaults.object(forKey: Self.secondsKey) as? Int ?? 90
    }

    func start(seconds: Int, next: String, workout: WorkoutSession) async {
        guard seconds > 0 else { return skip() }
        self.next = next; title = WorkoutRow.title(workout)
        await schedule(now().addingTimeInterval(TimeInterval(seconds)))
    }

    /// Moves the end; taking off more than is left ends the rest.
    func adjust(by seconds: Int) async {
        guard let endsAt else { return }
        let end = endsAt.addingTimeInterval(TimeInterval(seconds))
        if end > now() { await schedule(end) } else { skip() }
    }

    /// After Mivu was closed mid-rest, the countdown comes back from the pending sound's own record of its end.
    func restore() async {
        guard endsAt == nil, let info = await center.pendingNotificationRequests().first(where: { $0.identifier == Self.requestID })?.content.userInfo,
              let seconds = info["endsAt"] as? Double else { return }
        let end = Date(timeIntervalSince1970: seconds)
        guard end > now() else { return }
        next = info["next"] as? String ?? ""; endsAt = end
        expire(at: end)
    }

    func skip() {
        endsAt = nil; expiry?.cancel()
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
    }

    private func schedule(_ end: Date) async {
        endsAt = end; expiry?.cancel()
        // Asked the first time a rest starts, once; declined still counts down in the app. UI tests cannot answer the prompt.
        if !defaults.bool(forKey: Self.askedKey), !DiaryLaunch.isUITest {
            defaults.set(true, forKey: Self.askedKey)
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        // Skipped or moved while the prompt was up: the newer choice stands.
        guard endsAt == end else { return }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = next.isEmpty ? "Rest done." : "Rest done. Next: \(next)."
        content.sound = .default; content.threadIdentifier = "workout"
        content.userInfo = ["endsAt": end.timeIntervalSince1970, "next": next]
        // Same identifier, so a moved end replaces the earlier one.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(end.timeIntervalSince(now()), 1), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.requestID, content: content, trigger: trigger))
        expire(at: end)
    }

    /// Clears the countdown at its end, so the bar and banner go back to the workout's clock.
    private func expire(at end: Date) {
        expiry?.cancel()
        let remaining = end.timeIntervalSince(now())
        expiry = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(remaining))) != nil, self?.endsAt == end else { return }
            self?.endsAt = nil
        }
    }
}
