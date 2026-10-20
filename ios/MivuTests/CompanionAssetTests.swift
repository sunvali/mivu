import Foundation
import Testing
import UIKit
@testable import Mivu

@Suite(.serialized) @MainActor struct CompanionAssetTests {
    @Test func bundledRigLoadsWithTheTodayCrop() async throws {
        let runtime = try await ready()
        let rig = try #require(runtime.rig)
        let asset = try PipRigAsset.load(PipRigAssetTests.bundledData())
        #expect(rig.visibleRect == asset.frames["today"])
        #expect(runtime.displayedPose == .resting)
    }
}

extension CompanionAssetTests {
    private var pip: CharacterDescriptor { CharacterCatalog.bundled.resolve("pip") }
    private var second: CharacterDescriptor {
        CharacterDescriptor(id: "test-second", displayName: "Test Second", schemaVersion: 2,
                            animationResourcePath: pip.animationResourcePath, fallbackAssetPrefix: "Second",
                            previewAssetName: "TestPreview")
    }

    private func bytes() throws -> Data {
        let url = try #require(Bundle.main.url(forResource: pip.animationResourcePath, withExtension: nil))
        let data = try Data(contentsOf: url)
        #expect(data.count > 32 && data.count <= 1_048_576)
        #expect(data.first == Character("{").asciiValue)
        return data
    }

    private func output(_ pose: CompanionPose = .resting, reaction: UUID? = nil,
                        playback: MotionPolicy.Playback = .animated) -> CompanionOutput {
        CompanionOutput(pose: pose, playback: playback, reactionID: reaction, nextDeadline: nil)
    }

    private func ready() async throws -> CompanionRuntime {
        _ = try bytes()
        let runtime = CompanionRuntime()
        await runtime.select(pip)
        await runtime.attach(eligible: true)
        #expect(runtime.isReady)
        return runtime
    }

    private func mount(_ player: PipRigView) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        let controller = UIViewController()
        let view = UIView()
        CompanionRigHost.install(player, in: view)
        view.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        window.rootViewController = controller
        controller.view.addSubview(view)
        window.isHidden = false
        controller.view.layoutIfNeeded()
        return window
    }

    @Test func allPosesAndRepeatedReactCanBeApplied() async throws {
        let runtime = try await ready()
        for pose in CompanionPose.allCases {
            let reaction = ![.resting, .attentive, .thinking, .recovery].contains(pose) ? UUID() : nil
            await runtime.apply(output(pose, reaction: reaction), darkMode: true)
            #expect(runtime.displayedPose == pose)
        }
        let before = runtime.triggerCount
        await runtime.apply(output(.saved, reaction: UUID()), darkMode: false)
        await runtime.apply(output(.saved, reaction: UUID()), darkMode: false)
        #expect(runtime.triggerCount == before + 2)
    }

    @Test func corruptAssetAndWrongSchemaSelectFallback() async throws {
        for data in [Data(), Data("RIVEinvalid".utf8), Data([1, 2, 3])] {
            let runtime = CompanionRuntime(load: { _ in data })
            await runtime.select(pip)
            await runtime.attach(eligible: true)
            #expect(runtime.loadFailed && !runtime.isReady)
            #expect(runtime.rig == nil)
            #expect(runtime.fallbackAssetName(for: .today) == "PipResting" && runtime.fallbackAssetName(for: .coach) == "PipCoach")
        }
        let wrongVersion = Data(try #require(String(data: bytes(), encoding: .utf8))
            .replacingOccurrences(of: "\"version\":2", with: "\"version\":1").utf8)
        let wrongModel = CompanionRuntime(load: { _ in wrongVersion })
        await wrongModel.select(pip)
        await wrongModel.attach(eligible: true)
        #expect(wrongModel.loadFailed && wrongModel.rig == nil)

        var calls = 0
        let runtime = CompanionRuntime(load: { _ in calls += 1; return try bytes() })
        let incompatible = CharacterDescriptor(id: "bad-schema", displayName: "Bad Schema", schemaVersion: 1,
                                             animationResourcePath: pip.animationResourcePath,
                                             fallbackAssetPrefix: "Bad", previewAssetName: "BadPreview")
        await runtime.select(incompatible)
        await runtime.attach(eligible: true)
        #expect(runtime.loadFailed && calls == 0)
        #expect(runtime.fallbackAssetName(for: .today) == "BadResting")
    }

    @Test func hiddenOutputPausesAndCancelsReaction() async throws {
        let runtime = try await ready()
        await runtime.apply(output(.saved, reaction: UUID()), darkMode: false)
        await runtime.apply(output(.thinking, playback: .hidden), darkMode: false)
        #expect(runtime.isPaused)
        #expect(runtime.displayedPose == .resting)
        await runtime.apply(output(.thinking, playback: .hidden), darkMode: false)
        #expect(runtime.rig.map { animationKeys(in: $0.layer).isEmpty } == true && !runtime.isIdleScheduled)
    }

    @Test func rapidLoadCancellationCannotAttachStalePlayer() async throws {
        let data = try bytes()
        let gate = SuspendedAssetLoad()
        let runtime = CompanionRuntime(load: { _ in try await gate.load() })
        await runtime.select(pip)
        let old = Task { await runtime.attach(eligible: true) }
        try await gate.waitForCalls(1)
        await runtime.attach(eligible: false)
        let latest = Task { await runtime.attach(eligible: true) }
        try await gate.waitForCalls(2)
        gate.complete(1, with: data)
        await latest.value
        let rig = try #require(runtime.rig)
        gate.complete(0, with: data)
        await old.value
        #expect(runtime.rig === rig)
        #expect(runtime.isReady && !runtime.isPaused)
    }

    @Test func switchReleasesOldPlayerAndDropsLateLoad() async throws {
        let data = try bytes()
        let gate = SuspendedAssetLoad()
        let runtime = CompanionRuntime(load: { _ in try await gate.load() })
        await runtime.select(pip)
        let old = Task { await runtime.attach(eligible: true) }
        try await gate.waitForCalls(1)
        await runtime.select(second)
        #expect(runtime.rig == nil && !runtime.isReady)
        let latest = Task { await runtime.attach(eligible: true) }
        try await gate.waitForCalls(2)
        gate.complete(1, with: data)
        await latest.value
        let rig = try #require(runtime.rig)
        gate.complete(0, with: data)
        await old.value
        #expect(runtime.character.id == second.id && runtime.rig === rig)
    }

    @Test func switchClearsOldReactionAndStartsNewResting() async throws {
        let runtime = try await ready()
        await runtime.apply(output(.reviewed, reaction: UUID()), darkMode: false)
        weak let oldRig = runtime.rig
        await runtime.select(second)
        #expect(runtime.rig == nil && runtime.isPaused)
        #expect(oldRig == nil)
        await runtime.attach(eligible: true)
        #expect(runtime.triggerCount == 0)
        #expect(runtime.displayedPose == .resting)
    }

    @Test func failedSecondFixtureUsesSelectedStaticFallbackWithoutResurrectingOldPlayer() async throws {
        let data = try bytes()
        let runtime = CompanionRuntime(load: { character in
            character.id == "pip" ? data : Data("broken".utf8)
        })
        await runtime.select(pip)
        await runtime.attach(eligible: true)
        #expect(runtime.isReady)
        await runtime.select(second)
        await runtime.attach(eligible: true)
        #expect(runtime.loadFailed && runtime.rig == nil)
        #expect(runtime.fallbackAssetName(for: .coach) == "SecondCoach")
    }

    @Test func failedLoadRetriesOnceOnNextEligibleAttachmentOnly() async throws {
        let data = try bytes()
        var calls = 0
        let runtime = CompanionRuntime(load: { _ in
            calls += 1
            if calls == 1 { throw TestAssetError.missing }
            return data
        })
        await runtime.select(pip)
        await runtime.attach(eligible: true)
        for _ in 0..<3 {
            await runtime.attach(eligible: true)
            await runtime.apply(output(.thinking), darkMode: false)
            await runtime.select(pip)
        }
        #expect(calls == 1 && runtime.loadFailed)
        await runtime.attach(eligible: false)
        await runtime.attach(eligible: true)
        #expect(calls == 2 && runtime.isReady)
        await runtime.attach(eligible: true)
        await runtime.attach(eligible: false)
        await runtime.attach(eligible: true)
        #expect(calls == 2)
    }

    @Test func repeatedTrueAttachmentAndSameIDSelectionNeverRetry() async {
        var calls = 0
        let runtime = CompanionRuntime(load: { _ in calls += 1; throw TestAssetError.missing })
        await runtime.select(pip)
        await runtime.attach(eligible: true)
        for _ in 0..<4 {
            await runtime.select(pip)
            await runtime.attach(eligible: true)
            await runtime.apply(output(), darkMode: true)
        }
        #expect(calls == 1)
    }

    @Test func hiddenLoadCompletionCannotAttachOrPlay() async throws {
        let data = try bytes()
        let gate = SuspendedAssetLoad()
        let runtime = CompanionRuntime(load: { _ in try await gate.load() })
        await runtime.select(pip)
        let pending = Task { await runtime.attach(eligible: true) }
        try await gate.waitForCalls(1)
        await runtime.attach(eligible: false)
        gate.complete(0, with: data)
        await pending.value
        #expect(runtime.rig == nil && !runtime.isReady && runtime.isPaused)
    }

    @Test func actualRepeatedGesturesAdvanceAndSettleWithoutHostTimer() async throws {
        let runtime = try await ready()
        let rig = try #require(runtime.rig)
        let window = try mount(rig)
        defer { runtime.stop(); window.isHidden = true }
        let hour = Calendar.current.component(.hour, from: Date())
        let moments: [(CompanionPose, PipMoment)] = [(.submitted, .submitted), (.saved, .saved), (.saved, .saved),
                                                     (.reviewed, .reviewed), (.greeting, .greeting(hour: hour))]
        for (pose, moment) in moments {
            let duration = PipGestureLibrary.gesture(for: moment).duration
            let began = ContinuousClock.now
            await runtime.apply(output(pose, reaction: UUID()), darkMode: false)
            #expect(runtime.displayedPose == pose)
            #expect(!animationKeys(in: rig.layer).isEmpty)
            while runtime.displayedPose != .resting, began.duration(to: .now) < .seconds(3.5) {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(runtime.displayedPose == .resting)
            #expect(began.duration(to: .now) >= .seconds(duration - 0.04))
            #expect(animationKeys(in: rig.layer).contains("breath"), "Completed gestures settle into gentle breathing")
        }
        #expect(runtime.triggerCount == 5)
    }

    @Test func ordinaryPoseUpdatesDoNotCreateReactions() async throws {
        let runtime = try await ready()
        for _ in 0..<5 {
            await runtime.apply(output(), darkMode: false)
            await runtime.apply(output(.attentive), darkMode: false)
            await runtime.apply(output(.thinking), darkMode: false)
            await runtime.apply(output(.recovery), darkMode: false)
        }
        #expect(runtime.triggerCount == 0)
        let blink = output(reaction: UUID())
        await runtime.apply(blink, darkMode: false)
        await runtime.apply(blink, darkMode: false)
        #expect(runtime.triggerCount == 1)
    }

    @Test func reattachmentDoesNotReplayStaleActionTrigger() async throws {
        let runtime = try await ready()
        let action = output(.saved, reaction: UUID())
        await runtime.apply(action, darkMode: false)
        await runtime.attach(eligible: false)
        await runtime.attach(eligible: true)
        await runtime.apply(action, darkMode: false)
        #expect(runtime.triggerCount == 1)
        #expect(runtime.displayedPose == .resting)
        let rig = try #require(runtime.rig)
        let window = try mount(rig)
        defer { runtime.stop(); window.isHidden = true }
        try await Task.sleep(for: .milliseconds(80))
        #expect(animationKeys(in: rig.layer).contains("breath"), "Reattachment resumes breathing without replaying the consumed reaction")
        #expect(runtime.displayedPose == .resting)
    }

    @Test func appearanceChangeDoesNotRetriggerActiveAction() async throws {
        let runtime = try await ready()
        let action = output(.reviewed, reaction: UUID())
        await runtime.apply(action, darkMode: false)
        await runtime.apply(action, darkMode: true)
        #expect(runtime.triggerCount == 1)
        #expect(runtime.displayedPose == .reviewed)
    }

    @Test func obsoleteViewTeardownPreservesReplacementAndFreshGesture() async throws {
        let runtime = try await ready()
        let rig = try #require(runtime.rig)
        let oldWindow = try mount(rig)
        let oldContainer = try #require(rig.superview)
        let newWindow = try mount(rig)
        let newContainer = try #require(rig.superview)
        #expect(oldContainer !== newContainer)
        defer { runtime.stop(); oldWindow.isHidden = true; newWindow.isHidden = true }
        CompanionRigHost.dismantleUIView(oldContainer, coordinator: rig)
        #expect(rig.superview === newContainer)
        await runtime.apply(output(.saved, reaction: UUID()), darkMode: false)
        try await Task.sleep(for: .milliseconds(50))
        #expect(!animationKeys(in: rig.layer).isEmpty)
        #expect(rig.superview === newContainer)
    }

    @Test func interruptionBeforeFirstFrameDropsTheCanceledReaction() async throws {
        let runtime = try await ready()
        await runtime.apply(output(.saved, reaction: UUID()), darkMode: false)
        await runtime.apply(output(.attentive), darkMode: false)
        let rig = try #require(runtime.rig)
        let window = try mount(rig)
        defer { runtime.stop(); window.isHidden = true }
        try await Task.sleep(for: .milliseconds(500))
        #expect(runtime.displayedPose == .attentive)
        await runtime.reconcileMount(rig)
        #expect(animationKeys(in: rig.layer).contains("breath"), "Quiet typing keeps gentle breathing instead of freezing")
    }

    @Test func allFallbacksHaveBothAppearanceVariantsWithIdenticalBounds() throws {
        let runtime = CompanionRuntime()
        var size: CGSize?
        for surface in [CompanionSurface.today, .coach] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let image = try #require(UIImage(named: runtime.fallbackAssetName(for: surface), in: .main,
                                               compatibleWith: UITraitCollection(userInterfaceStyle: style)))
                if let size { #expect(image.size == size) } else { size = image.size }
                #expect(image.size.width == image.size.height)
            }
        }
        #expect(UIImage(named: "PipPreview") != nil)
    }
}

private enum TestAssetError: Error { case missing }

@MainActor private final class SuspendedAssetLoad {
    private var continuations: [CheckedContinuation<Data, Error>] = []
    func load() async throws -> Data {
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func waitForCalls(_ count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while continuations.count < count, ContinuousClock.now < deadline { await Task.yield() }
        try #require(continuations.count >= count)
    }
    func complete(_ index: Int, with data: Data) { continuations[index].resume(returning: data) }
}
