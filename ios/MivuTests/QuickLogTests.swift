import Foundation
import Testing
import UIKit
@testable import Mivu

@Suite(.serialized) @MainActor struct QuickLogTests {
    @Test func logFoodIntentRequestsCamera() async throws {
        QuickLogRequest.shared.pending = false
        defer { QuickLogRequest.shared.pending = false }
        _ = try await LogFoodIntent().perform()
        #expect(QuickLogRequest.shared.pending)
    }

    @Test func homeScreenQuickActionIsDeclaredAndHandled() throws {
        let items = try #require(Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: Any]])
        #expect(items.compactMap { $0["UIApplicationShortcutItemType"] as? String } == [QuickLogRequest.shortcutType])
        QuickLogRequest.shared.pending = false
        defer { QuickLogRequest.shared.pending = false }
        #expect(!QuickLogRequest.shared.handle(UIApplicationShortcutItem(type: "other", localizedTitle: "Other")))
        #expect(!QuickLogRequest.shared.pending)
        #expect(QuickLogRequest.shared.handle(UIApplicationShortcutItem(type: QuickLogRequest.shortcutType, localizedTitle: "Log Food")))
        #expect(QuickLogRequest.shared.pending)
    }
}
