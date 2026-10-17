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
    @Test(arguments: [false, true])
    func saveDuringInitialLoadPlaysOnlyWhileItsPresentationIsCurrent(expired: Bool) async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("PipColdSave-" + UUID().uuidString)
        let store = DiaryStore(directory: directory)
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic cold save", timeZoneID: "UTC"))
        _ = try await store.startDay()
        let diary = DiaryViewModel(store: store)
        diary.snapshot = try await store.snapshot()
        let connection = ChatGPTConnection(auth: AuthSession(store: CredentialStore(service: "PipColdSave-" + UUID().uuidString)))
        let coach = CoachViewModel(diary: diary, connection: connection)
        let pip = CharacterCatalog.bundled.resolve("pip")
        let url = try #require(Bundle.main.url(forResource: pip.animationResourcePath, withExtension: nil))
        let bytes = try Data(contentsOf: url)
        let gate = CompanionRootLoadGate()
        let runtime = CompanionRuntime(load: { _ in await gate.pause(); return bytes })
        let suite = "PipColdSave-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        var latest: CompanionOutput?
        let root = DiaryRootView(testDiary: diary, testCoach: coach, testRuntime: runtime,
            testTab: "today", testDefaults: defaults, observeCompanionOutput: { latest = $0 })
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: root.environment(\.scenePhase, .active))
        window.isHidden = false
        defer {
            gate.release(); runtime.stop(); coach.enterBackground(); window.isHidden = true
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try #require(await eventually { gate.waiting })
        var draft = MealDraft(); draft.text = "Synthetic meal saved during character loading"
        let day = try #require(diary.activeDay?.id)
        try #require(await eventually { !diary.isChangingProfile && !diary.isSaving })
        let captured = await diary.capture(draft, dayID: day)
        try #require(captured, "Synthetic capture failed: \(diary.errorMessage ?? "no error"); saving=\(diary.isSaving), changing=\(diary.isChangingProfile), canceled=\(Task.isCancelled)")
        try #require(await eventually { latest?.pose == .saved })
        #expect(runtime.triggerCount == 0)
        let deadline = try #require(latest?.nextDeadline)
        if expired { try #require(await eventually { latest?.pose == .resting }) }
        gate.release()
        try #require(await eventually { runtime.isReady })
        if expired || Date() >= deadline {
            #expect(runtime.triggerCount == 0, "Expired cold-load feedback must never replay")
            #expect(runtime.displayedPose == .resting)
        } else {
            #expect(await eventually { runtime.triggerCount == 1 }, "A still-current save must play when the first player becomes ready")
            #expect(runtime.displayedPose == .saved)
        }
        #expect(diary.snapshot?.meals.count == 1, "Character loading must not duplicate or lose the saved record")
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

    @Test(arguments: [false, true])
    func acceptedSendSurvivesFastSaveAndColdLoading(cold: Bool) async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("PipSubmit-" + UUID().uuidString)
        let store = DiaryStore(directory: directory)
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic submit", timeZoneID: "UTC"))
        let diary = DiaryViewModel(store: store)
        diary.snapshot = try await store.snapshot()
        let connection = ChatGPTConnection(auth: AuthSession(store: CredentialStore(service: "PipSubmit-" + UUID().uuidString)))
        let coach = CoachViewModel(diary: diary, connection: connection)
        let path = CharacterCatalog.bundled.resolve("pip").animationResourcePath
        let url = try #require(Bundle.main.url(forResource: path, withExtension: nil))
        let bytes = try Data(contentsOf: url)
        let gate = CompanionRootLoadGate()
        let runtime = CompanionRuntime(load: { _ in if cold { await gate.pause() }; return bytes })
        let suite = "PipSubmit-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        var outputs: [CompanionOutput] = []
        let root = DiaryRootView(testDiary: diary, testCoach: coach, testRuntime: runtime,
            testTab: "coach", testDefaults: defaults, observeCompanionOutput: { outputs.append($0) })
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: root.environment(\.scenePhase, .active))
        window.isHidden = false
        defer {
            gate.release(); runtime.stop(); coach.enterBackground(); window.isHidden = true
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try #require(await eventually { cold ? gate.waiting : runtime.isReady })
        try #require(await eventually { !diary.isChangingProfile && !diary.isSaving && !coach.isWorking })
        coach.enterBackground()
        coach.errorMessage = "Synthetic prior failure"
        try #require(await eventually { outputs.last?.pose == .recovery })
        outputs.removeAll()
        coach.draft.text = "Synthetic immediate submit"
        let operation = coach.draft.submissionID
        #expect(await coach.send(), "Capture must finish independently of the presentation gesture")
        #expect(coach.captureReceipt == operation)
        try #require(await eventually { outputs.last?.pose == .submitted }, "Even a fast durable receipt must preserve the accepted-submit gesture")
        #expect(!outputs.contains { $0.pose == .saved }, "Saved must queue behind acceptance")
        if cold {
            try #require(await eventually { outputs.last?.pose == .saved })
            try #require(await eventually { outputs.last?.pose == .resting })
            gate.release()
            try #require(await eventually { runtime.isReady })
            #expect(runtime.triggerCount == 0, "Cold loading must not replay an expired acceptance or durable receipt")
            #expect(runtime.displayedPose == .resting)
        } else {
            #expect(await eventually { runtime.displayedPose == .submitted })
            try #require(await eventually { outputs.last?.pose == .saved })
            #expect(await eventually { runtime.displayedPose == .saved })
        }
        #expect(diary.snapshot?.coachTurns.map(\.id) == [operation])
        #expect(diary.snapshot?.meals.isEmpty == true)
    }

}
