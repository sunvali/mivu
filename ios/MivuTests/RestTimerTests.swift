import Foundation
import Testing
import UserNotifications
@testable import Mivu

/// Records what the rest timer asks of the notification center, without touching the real one.
@MainActor final class FakeNotificationCenter: RestNotificationCenter {
    var pending: [String: UNNotificationRequest] = [:]
    var added: [UNNotificationRequest] = []
    var asked = 0

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { asked += 1; return true }
    func add(_ request: UNNotificationRequest) async throws { added.append(request); pending[request.identifier] = request }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) { identifiers.forEach { pending[$0] = nil } }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { Array(pending.values) }
}

@MainActor @Suite struct RestTimerTests {
    private let now = Date(timeIntervalSinceReferenceDate: 820_000_000)
    private let workout = WorkoutSession(dayID: UUID(), performedAt: Date(timeIntervalSinceReferenceDate: 819_999_000), timePrecision: .exact,
                                         revision: 1, kind: .strength, durationMinutes: 0, exercises: [], title: "Push day")

    private func timer(_ center: FakeNotificationCenter = FakeNotificationCenter(), now: Date? = nil) -> (RestTimer, FakeNotificationCenter) {
        let defaults = UserDefaults(suiteName: "RestTimerTests-" + UUID().uuidString)!
        let clock = now ?? self.now
        return (RestTimer(center: center, defaults: defaults, now: { clock }), center)
    }

    private func interval(_ request: UNNotificationRequest?) -> TimeInterval? {
        (request?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval
    }

    @Test func schedulesAtEnd() async {
        let (rest, center) = timer()
        await rest.start(seconds: 90, next: "Bench press · set 3", workout: workout)
        #expect(rest.endsAt == now.addingTimeInterval(90))
        #expect(center.added.count == 1 && center.pending.count == 1)
        let request = center.pending[RestTimer.requestID]
        #expect(interval(request) == 90 && request?.content.sound == .default)
        #expect(request?.content.body == "Rest done. Next: Bench press · set 3.")
        await rest.start(seconds: 90, next: "Bench press · set 3", workout: workout)
        #expect(center.asked == 1, "permission is asked the first time only")
    }

    @Test func adjustReplaces() async {
        let (rest, center) = timer()
        await rest.start(seconds: 90, next: "Bench press · set 3", workout: workout)
        await rest.adjust(by: 15)
        #expect(rest.endsAt == now.addingTimeInterval(105))
        #expect(center.pending.count == 1 && interval(center.pending[RestTimer.requestID]) == 105)
        await rest.adjust(by: -15); await rest.adjust(by: -15)
        #expect(interval(center.pending[RestTimer.requestID]) == 75)
        await rest.adjust(by: -90)
        #expect(rest.endsAt == nil && center.pending.isEmpty, "taking off more than is left ends the rest")
    }

    @Test func skipRemoves() async {
        let (rest, center) = timer()
        await rest.start(seconds: 90, next: "Bench press · set 3", workout: workout)
        rest.skip()
        #expect(rest.endsAt == nil && center.pending.isEmpty)
    }

    @Test func restoresAfterRelaunch() async {
        let (rest, center) = timer()
        await rest.start(seconds: 90, next: "Bench press · set 3", workout: workout)
        // Mivu killed mid-rest: a fresh timer finds the end in the pending sound.
        let (relaunched, _) = timer(center, now: now.addingTimeInterval(30))
        await relaunched.restore()
        #expect(relaunched.endsAt == now.addingTimeInterval(90) && relaunched.next == "Bench press · set 3")
        let (late, _) = timer(center, now: now.addingTimeInterval(91))
        await late.restore()
        #expect(late.endsAt == nil, "a rest already over is not brought back")
    }
}
