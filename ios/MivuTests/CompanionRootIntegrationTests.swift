import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Mivu

@MainActor private final class CompanionRootLoadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var waiting = false
    func pause() async {
        guard !released else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            waiting = true
        }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

@MainActor private final class CompanionBackgroundRefreshGate {
    var armed = false
    private(set) var waiting = false
    private var continuation: CheckedContinuation<Void, Never>?

    func pauseIfArmed() async {
        guard armed else { return }
        armed = false
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            waiting = true
        }
        waiting = false
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

    @Test func pagingAndPhotoLoadsEmitNoCompanionFeedback() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        let bytes = try #require(renderer.image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }.pngData())
        var source = ChatHistoryFixture.pagingSnapshot(exchanges: 140)
        for index in source.coachTurns.indices {
            source.coachTurns[index].state = .completed
            for photo in source.coachTurns[index].photos.indices { source.coachTurns[index].photos[photo].data = bytes }
        }
        for index in source.meals.indices {
            for photo in source.meals[index].photos.indices { source.meals[index].photos[photo].data = bytes }
        }
        let fixture = try CaptureFixture(snapshot: source)
        defer { fixture.remove() }
        let store = DiaryStore(directory: fixture.root)
        _ = try await store.selectProfile(fixture.profileID)
        let diary = DiaryViewModel(store: store)
        await diary.load(createDefaultProfile: false)
        let suite = "PipPaging-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(auth: AuthSession(store: CredentialStore(service: suite))))
        let runtime = CompanionRuntime()
        var outputs: [CompanionOutput] = []
        let root = DiaryRootView(testDiary: diary, testCoach: coach, testRuntime: runtime,
            testTab: "coach", testDefaults: defaults, observeCompanionOutput: { outputs.append($0) })
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: root.environment(\.scenePhase, .active))
        window.isHidden = false
        let timelineTask = Task { await coach.connectTimeline() }
        defer {
            timelineTask.cancel(); coach.enterBackground(); runtime.stop(); window.isHidden = true
            defaults.removePersistentDomain(forName: suite)
        }
        try #require(await eventually {
            runtime.isReady && !coach.isWorking && !diary.isSaving && coach.timeline?.exchanges.count == 20
                && outputs.last?.pose == .resting && outputs.last?.playback == .animated
        })
        let timeline = try #require(coach.timeline)
        let submission = coach.companionSubmission, saved = coach.companionCaptureEvent
        let capture = coach.captureReceipt, reviewed = diary.companionReviewEvent
        let triggers = runtime.triggerCount
        let firstOutput = outputs.count
        for _ in 0..<5 {
            let exchange = try #require(timeline.exchanges.first)
            let anchor = CoachViewportAnchor(rowID: exchange.id, offset: 12, focusedExchangeID: nil)
            timeline.setViewport(.history(anchor), visibleIDs: [anchor.rowID])
            let earlier = try #require(timeline.loadEarlier(anchor: anchor))
            await earlier.value
        }
        #expect(timeline.window.residentCount <= 100)
        await timeline.seek(.turn(source.coachTurns[0].id))
        let first = try #require(timeline.exchanges.first)
        let anchor = CoachViewportAnchor(rowID: first.id, offset: 0)
        timeline.setViewport(.history(anchor), visibleIDs: [first.id])
        let later = try #require(timeline.loadLater(anchor: anchor))
        await later.value
        let reference = try #require(timeline.exchanges.flatMap(\.photos).first)
        let loader = try #require(diary.photoLoader)
        _ = try await loader.thumbnail(for: reference, pixelSize: 64)
        _ = try await loader.thumbnail(for: reference, pixelSize: 64)
        await loader.purgeForMemoryPressure()
        _ = try await loader.thumbnail(for: reference, pixelSize: 64)
        let beforeImport = outputs.count, triggersBeforeImport = runtime.triggerCount
        #expect(triggersBeforeImport == triggers)
        #expect(outputs[firstOutput..<beforeImport].allSatisfy {
            $0.pose == .resting && $0.reactionID == nil && $0.playback == .animated
        }, "Paging, eviction, seek and thumbnail delivery must remain quiet at the real root")
        let presentation = try coach.attachmentDraft.beginPresentation()
        let draftID = coach.attachmentDraft.submissionID
        let photoID = UUID()
        let failed = try await coach.attachmentDraft.importSelections([.init(id: photoID, load: { bytes })], presentationID: presentation)
        try await coach.attachmentDraft.endPresentation(presentation)
        #expect(failed.isEmpty && coach.attachmentDraft.attachments.map(\.id) == [photoID])
        #expect(coach.attachmentDraft.submissionID == draftID)
        await timeline.jumpToLatest()
        #expect(coach.companionSubmission == submission && coach.companionCaptureEvent == saved)
        #expect(coach.captureReceipt == capture && diary.companionReviewEvent == reviewed)
        // An accepted unsent photo is the one decorative moment: a curious look, never a saved or reviewed reaction.
        #expect(coach.companionPhotoEvent?.kind == .photoAdded)
        #expect(outputs.dropFirst(beforeImport).allSatisfy {
            ($0.pose == .resting || $0.pose == .curious) && $0.playback == .animated
        })
        #expect(try fixture.rows("SELECT COUNT(*) FROM coach_turn") == [["140"]])
    }

    @Test func offPageActiveOperationKeepsProcessingThroughHistoryAndLateCancellation() async throws {
        var source = ChatHistoryFixture.pagingSnapshot(exchanges: 140)
        for index in source.coachTurns.indices { source.coachTurns[index].state = .completed }
        source.coachTurns[0].state = .captured
        source.coachTurns[0].photos = []; source.coachTurns[0].photoIDs = []
        source.coachTurns[0].receipts = []; source.coachTurns[0].assistantText = nil
        source.coachTurns[139].state = .needsRetry
        let operation = source.coachTurns[0].id
        let fixture = try CaptureFixture(snapshot: source)
        defer { fixture.remove() }
        let store = DiaryStore(directory: fixture.root)
        _ = try await store.selectProfile(fixture.profileID)
        let diary = DiaryViewModel(store: store)
        await diary.load(createDefaultProfile: false)
        let gate = CompanionRootLoadGate()
        let suite = "PipOffPage-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let connection = ChatGPTConnection(auth: AuthSession(store: CredentialStore(service: suite)))
        let coach = CoachViewModel(diary: diary, connection: connection, inference: { { _, _ in
            await gate.pause()
            return CoachInferenceResult(model: "fixture", text: "Synthetic guidance", calls: [], outputItems: [])
        } })
        let runtime = CompanionRuntime()
        var outputs: [CompanionOutput] = []
        let root = DiaryRootView(testDiary: diary, testCoach: coach, testRuntime: runtime,
            testTab: "coach", testDefaults: defaults, observeCompanionOutput: { outputs.append($0) })
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: root.environment(\.scenePhase, .active))
        window.isHidden = false
        let timelineTask = Task { await coach.connectTimeline() }
        defer {
            coach.cancel(); gate.release(); timelineTask.cancel(); runtime.stop(); window.isHidden = true
            defaults.removePersistentDomain(forName: suite)
        }
        // The real root starts the worker after initialization; its profile reload cancels earlier work.
        try #require(await eventually {
            gate.waiting && runtime.isReady && coach.timeline?.exchanges.count == 20
                && outputs.last?.pose == .thinking
        })
        #expect(coach.activityTurnID == operation && coach.activity == .thinking)
        #expect(!coach.exchanges.contains { $0.id == operation }, "The current operation is outside the single resident transcript")
        #expect(!coach.turns.contains { $0.id == operation }, "The current operation is outside the resident page")
        #expect(!coach.companionNeedsRecovery && coach.companionIsProcessing,
                "A newer historical needsRetry row cannot replace the actual inference operation")
        let firstOutput = outputs.count, triggers = runtime.triggerCount
        let timeline = try #require(coach.timeline)
        await timeline.seek(.turn(operation))
        await timeline.jumpToLatest()
        #expect(!coach.turns.contains { $0.id == operation })
        #expect(coach.activityTurnID == operation && coach.companionIsProcessing && !coach.companionNeedsRecovery)
        #expect(coach.companionSubmission == nil && coach.companionCaptureEvent == nil && coach.captureReceipt == nil)
        #expect(runtime.triggerCount == triggers)
        #expect(outputs.dropFirst(firstOutput).allSatisfy { $0.pose == .thinking && $0.reactionID == nil })
        coach.cancel()
        #expect(coach.activity == nil && coach.activityTurnID == nil)
        gate.release()
        await coach.waitForWorker()
        #expect(coach.activity == nil && coach.activityTurnID == nil,
                "Late inference completion must not restore canceled activity")
    }

    @Test func latestRecoveryPoseIsAppliedWhenInitialRootLoadFinishes() async throws {
        let path = URL.temporaryDirectory.appending(path: "CompanionRoot-" + UUID().uuidString)
        let store = DiaryStore(directory: path)
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic root", timeZoneID: "UTC"))
        _ = try await store.startDay()
        let diary = DiaryViewModel(store: store)
        await diary.load(createDefaultProfile: false)
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
        await diary.load(createDefaultProfile: false)
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
        try #require(await eventually { latest?.pose == .firstMealToday })
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
            #expect(runtime.displayedPose == .firstMealToday)
        }
        #expect(diary.readModel?.meals.count == 1, "Character loading must not duplicate or lose the saved record")
    }

    @Test func firstRunTodayShowsPipWithoutInventingDiaryRecords() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("PipEmptyToday-" + UUID().uuidString)
        let store = DiaryStore(directory: directory)
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic empty", timeZoneID: "UTC"))
        let diary = DiaryViewModel(store: store)
        await diary.load(createDefaultProfile: false)
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
        #expect(diary.readModel?.meals.isEmpty == true)
        #expect((try? await diary.store.snapshotForExport())?.days.isEmpty == true, "Showing the companion must not create a recorded day")
    }

    @Test func untouchedTodayKeepsBreathingDuringAnEmptyBackgroundCoachRefresh() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("PipQuietToday-" + UUID().uuidString)
        let store = DiaryStore(directory: directory)
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic quiet Today", timeZoneID: "UTC"))
        let gate = CompanionBackgroundRefreshGate()
        let diary = DiaryViewModel(store: store, actionReadModelLoading: { id in
            await gate.pauseIfArmed()
            return try await store.diaryReadModel(expectedProfileID: id)
        })
        await diary.load(createDefaultProfile: false)
        let suite = "PipQuietToday-" + UUID().uuidString
        let connection = ChatGPTConnection(auth: AuthSession(store: CredentialStore(service: suite)))
        let coach = CoachViewModel(diary: diary, connection: connection)
        let runtime = CompanionRuntime()
        let defaults = try #require(UserDefaults(suiteName: suite))
        var outputs: [CompanionOutput] = []
        let root = DiaryRootView(testDiary: diary, testCoach: coach, testRuntime: runtime,
            testTab: "today", testDefaults: defaults, observeCompanionOutput: { outputs.append($0) })
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: root.environment(\.scenePhase, .active))
        window.isHidden = false
        defer {
            gate.release(); coach.enterBackground(); runtime.stop(); window.isHidden = true
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        // Startup recovery and the initial greeting must finish before the passive check is armed.
        try #require(await eventually {
            runtime.isReady && !coach.isWorking && !diary.isSaving
                && outputs.last?.pose == .resting && outputs.last?.playback == .animated
                && outputs.last?.reactionID == nil && runtime.displayedPose == .resting
        })
        let rig = try #require(runtime.rig)
        let triggers = runtime.triggerCount
        let firstOutput = outputs.count
        gate.armed = true
        coach.resume()
        try #require(await eventually { gate.waiting }, "Exercise the real worker's legacy-capture refresh")
        try #require(diary.isSaving && coach.isWorking,
                     "The shared save lock must be held while the empty background refresh is suspended")
        #expect(coach.turns.isEmpty && diary.readModel?.meals.isEmpty == true)

        // Hold the real await point across several SwiftUI updates. A transient thinking output
        // is still a failure even if a later render returns to idle before this check finishes.
        let changedPose = await eventually({
            outputs.dropFirst(firstOutput).contains {
                $0.pose != .resting || $0.playback != .animated || $0.reactionID != nil
            } || runtime.displayedPose != .resting || runtime.triggerCount != triggers
        }, timeout: 0.25)
        #expect(!changedPose, "A background check with no input must not make untouched Today flash another pose")
        #expect(outputs.last?.pose == .resting && outputs.last?.reactionID == nil)
        #expect(animationKeys(in: rig.layer).contains("breath"), "The warm production rig must keep breathing")

        gate.release()
        await coach.waitForWorker()
        #expect(!diary.isSaving && !coach.isWorking)
        #expect(coach.turns.isEmpty && diary.readModel?.meals.isEmpty == true)
    }

    @Test(arguments: [false, true])
    func acceptedSendSurvivesFastSaveAndColdLoading(cold: Bool) async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("PipSubmit-" + UUID().uuidString)
        let store = DiaryStore(directory: directory)
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic submit", timeZoneID: "UTC"))
        let diary = DiaryViewModel(store: store)
        await diary.load(createDefaultProfile: false)
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
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.map(\.id) == [operation])
        #expect(diary.readModel?.meals.isEmpty == true)
    }

}
