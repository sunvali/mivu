import Foundation
import SwiftUI
import Testing
import UIKit
import Lottie
@testable import Mivu

@MainActor private final class CompanionRootLoadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var waiting = false
    func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            waiting = true
        }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@Suite(.serialized) @MainActor struct CompanionRootIntegrationTests {
    private func eventually(_ condition: () -> Bool, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
    @Test func latestRecoveryPoseIsAppliedWhenInitialRootLoadFinishes() async throws {
        let path = URL.temporaryDirectory.appending(path: "CompanionRoot-" + UUID().uuidString)
        let store = DiaryStore(directory: path)
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic root", timeZoneID: "UTC"))
        _ = try await store.startDay()
        let diary = DiaryViewModel(store: store)
        diary.snapshot = try await store.snapshot()
        let connection = ChatGPTConnection(auth: AuthSession(store: CredentialStore(service: "CompanionRoot-" + UUID().uuidString)))
        let coach = CoachViewModel(diary: diary, connection: connection)
        let pip = CharacterCatalog.bundled.resolve("pip")
        let url = try #require(Bundle.main.url(forResource: pip.animationResourcePath, withExtension: nil))
        let bytes = try Data(contentsOf: url)
        let suiteName = "CompanionRoot-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let gate = CompanionRootLoadGate()
        let runtime = CompanionRuntime(load: { _ in await gate.pause(); return bytes })
        var latest: CompanionOutput?
        var appliedWhileLoading = false
        let root = DiaryRootView(testDiary: diary, testCoach: coach, testRuntime: runtime, testTab: "coach", testDefaults: defaults,
            observeCompanionApplication: { output in
                print("Root companion apply pose=\(output.pose.rawValue) ready=\(runtime.isReady) canceled=\(Task.isCancelled)")
                if output.pose == .recovery && !runtime.isReady { appliedWhileLoading = true }
            }) { latest = $0 }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        let host = UIHostingController(rootView: root.environment(\.scenePhase, .active).environment(\.colorScheme, .light))
        window.rootViewController = host
        window.isHidden = false
        defer {
            gate.release(); runtime.stop(); coach.enterBackground()
            window.isHidden = true
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: path)
        }
        #expect(await eventually { gate.waiting }, "The real root must start its eligible delayed load")
        #expect(!runtime.isReady)
        coach.errorMessage = "Synthetic current operation error"
        try #require(await eventually { latest?.pose == .recovery && latest?.playback == .animated },
                "Real Coach displayed error state must replace the output while the first attachment is suspended")
        try #require(await eventually { appliedWhileLoading },
                "The replacement root task must actually apply while the original load is suspended")
        gate.release()
        #expect(await eventually { runtime.isReady })
        #expect(await eventually { runtime.displayedPose == .recovery },
                "Load completion must apply the latest recovery output even after the first root task was canceled")
        #expect(runtime.triggerCount == 0, "Canceled loading greetings must not replay on the recovery surface")
    }
    @Test func firstRunTodayShowsPipWithoutInventingDiaryRecords() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("PipEmptyToday-" + UUID().uuidString)
        let store = DiaryStore(directory: directory)
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic empty", timeZoneID: "UTC"))
        let diary = DiaryViewModel(store: store)
        diary.snapshot = try await store.snapshot()
        let connection = ChatGPTConnection(auth: AuthSession(store: CredentialStore(service: "PipEmpty-" + UUID().uuidString)))
        let coach = CoachViewModel(diary: diary, connection: connection)
        let runtime = CompanionRuntime()
        let suite = "PipEmptyToday-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = DiaryRootView(testDiary: diary, testCoach: coach, testRuntime: runtime,
            testTab: "today", testDefaults: defaults, observeCompanionOutput: { _ in })
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: root.environment(\.scenePhase, .active))
        window.isHidden = false
        defer {
            runtime.stop(); coach.enterBackground(); window.isHidden = true
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        #expect(await eventually { runtime.isReady }, "The real Today surface must load the companion before the first meal")
        #expect(diary.snapshot?.meals.isEmpty == true)
        #expect(diary.snapshot?.days.isEmpty == true, "Showing the companion must not create a recorded day")
    }

}
