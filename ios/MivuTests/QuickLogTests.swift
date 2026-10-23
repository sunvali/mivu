import Foundation
import Testing
import UIKit
import AVFoundation
@testable import Mivu

@Suite(.serialized) @MainActor struct QuickLogTests {
    @Test func logFoodIntentRequestsCamera() async throws {
        QuickLogRequest.shared.pending = false
        defer { QuickLogRequest.shared.pending = false }
        _ = try await LogFoodIntent().perform()
        #expect(QuickLogRequest.shared.pending)
    }

    @Test func logMealPlaceholderOpensTheSameCamera() async throws {
        QuickLogRequest.shared.pending = false
        defer { QuickLogRequest.shared.pending = false }
        _ = try await LogMealIntent().perform()
        #expect(QuickLogRequest.shared.pending)
        #expect(MivuShortcuts.appShortcuts.count == 4)
    }

    @Test func openCoachIntentRequestsCoach() async throws {
        QuickLogRequest.shared.openCoach = false
        defer { QuickLogRequest.shared.openCoach = false }
        _ = try await OpenCoachIntent().perform()
        #expect(QuickLogRequest.shared.openCoach)
    }

    @Test func homeScreenQuickActionIsDeclaredAndHandled() throws {
        let items = try #require(Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: Any]])
        #expect(items.compactMap { $0["UIApplicationShortcutItemType"] as? String } == [QuickLogRequest.shortcutType])
        QuickLogRequest.shared.pending = false
        defer { QuickLogRequest.shared.pending = false }
        #expect(!QuickLogRequest.shared.handle(UIApplicationShortcutItem(type: "other", localizedTitle: "Other")))
        #expect(!QuickLogRequest.shared.pending)
        #expect(QuickLogRequest.shared.handle(UIApplicationShortcutItem(type: QuickLogRequest.shortcutType, localizedTitle: "Snap It")))
        #expect(QuickLogRequest.shared.pending)
    }
}

@Suite struct CoachCameraFlashTests {
    @Test func requestedFlashIsUsedOnlyWhenTheCameraSupportsIt() {
        #expect(CoachCameraSession.photoSettings(flash: .on, supported: [.off, .auto, .on]).flashMode == .on)
        #expect(CoachCameraSession.photoSettings(flash: .auto, supported: [.off, .auto, .on]).flashMode == .auto)
        // AVFoundation raises an exception for an unsupported mode, so it must fall back to off.
        #expect(CoachCameraSession.photoSettings(flash: .on, supported: []).flashMode == .off)
    }
}
