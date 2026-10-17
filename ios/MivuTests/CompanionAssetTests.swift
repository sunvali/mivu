import Foundation
import Testing
import UIKit
import Lottie
@testable import Mivu

@Suite(.serialized) @MainActor struct CompanionAssetTests {
    @Test func bundledAssetLoadsSupportedCoreAnimationAndApprovedSegments() async throws {
        let runtime = try await ready()
        let player = try #require(runtime.player)
        #expect(player.animation != nil)
        #expect(runtime.displayedPose == .resting)
        #expect(player.currentRenderingEngine == .coreAnimation)
        for name in ["resting", "blink", "attentive", "thinking", "saved", "reviewed", "recovery", "greeting"] {
            #expect(player.animation?.frameTime(forMarker: name) != nil)
        }
    }
}

extension CompanionAssetTests {
    private var pip: CharacterDescriptor { CharacterCatalog.bundled.resolve("pip") }
    private var second: CharacterDescriptor {
        CharacterDescriptor(id: "test-second", displayName: "Test Second", schemaVersion: 1,
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

    private func mount(_ player: LottieAnimationView) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        let controller = UIViewController()
        let view = UIView()
        CompanionLottieView.install(player, in: view)
        view.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        window.rootViewController = controller
        controller.view.addSubview(view)
        window.isHidden = false
        controller.view.layoutIfNeeded()
        return window
    }

    @Test func allSevenPosesAndRepeatedReactCanBeApplied() async throws {
        let runtime = try await ready()
        for pose in CompanionPose.allCases {
            let reaction = [.saved, .reviewed, .greeting].contains(pose) ? UUID() : nil
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
            #expect(runtime.player == nil)
            #expect(runtime.fallbackAssetName(for: .recovery) == "PipRecovery")
        }
        var wrongBindings = try bytes()
        let nameRange = try #require(wrongBindings.range(of: Data("\"cm\":\"saved\"".utf8)))
        wrongBindings.replaceSubrange(nameRange, with: Data("\"cm\":\"wrong\"".utf8))
        let wrongModel = CompanionRuntime(load: { _ in wrongBindings })
        await wrongModel.select(pip)
        await wrongModel.attach(eligible: true)
        #expect(wrongModel.loadFailed && wrongModel.player == nil)

        var calls = 0
        let runtime = CompanionRuntime(load: { _ in calls += 1; return try bytes() })
        let incompatible = CharacterDescriptor(id: "bad-schema", displayName: "Bad Schema", schemaVersion: 2,
                                             animationResourcePath: pip.animationResourcePath,
                                             fallbackAssetPrefix: "Bad", previewAssetName: "BadPreview")
        await runtime.select(incompatible)
        await runtime.attach(eligible: true)
        #expect(runtime.loadFailed && calls == 0)
        #expect(runtime.fallbackAssetName(for: .resting) == "BadResting")
    }

    @Test func hiddenOutputPausesAndCancelsReaction() async throws {
        let runtime = try await ready()
        await runtime.apply(output(.saved, reaction: UUID()), darkMode: false)
        await runtime.apply(output(.thinking, playback: .hidden), darkMode: false)
        #expect(runtime.isPaused)
        #expect(runtime.displayedPose == .resting)
        await runtime.apply(output(.thinking, playback: .hidden), darkMode: false)
        #expect(runtime.player?.isAnimationPlaying == false)
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
        let player = try #require(runtime.player)
        gate.complete(0, with: data)
        await old.value
        #expect(runtime.player === player)
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
        #expect(runtime.player == nil && !runtime.isReady)
        let latest = Task { await runtime.attach(eligible: true) }
        try await gate.waitForCalls(2)
        gate.complete(1, with: data)
        await latest.value
        let player = try #require(runtime.player)
        gate.complete(0, with: data)
        await old.value
        #expect(runtime.character.id == second.id && runtime.player === player)
    }

    @Test func switchClearsOldReactionAndStartsNewResting() async throws {
        let runtime = try await ready()
        await runtime.apply(output(.reviewed, reaction: UUID()), darkMode: false)
        weak let oldPlayer = runtime.player
        await runtime.select(second)
        #expect(runtime.player == nil && runtime.isPaused)
        #expect(oldPlayer == nil)
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
        #expect(runtime.loadFailed && runtime.player == nil)
        #expect(runtime.fallbackAssetName(for: .thinking) == "SecondThinking")
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
        #expect(runtime.player == nil && !runtime.isReady && runtime.isPaused)
    }

    @Test func actualRepeatedGesturesAdvanceAndSettleWithoutHostTimer() async throws {
        let runtime = try await ready()
        let player = try #require(runtime.player)
        let window = try mount(player)
        defer { runtime.stop(); window.isHidden = true }
        for pose in [CompanionPose.saved, .saved, .reviewed, .greeting, .resting] {
            let duration: Double = pose == .saved ? MivuMotion.saved : pose == .reviewed
                ? MivuMotion.reviewed : pose == .greeting ? MivuMotion.greeting : MivuMotion.blink
            let began = ContinuousClock.now
            await runtime.apply(output(pose, reaction: UUID()), darkMode: false)
            #expect(player.isAnimationPlaying)
            let frame = player.realtimeAnimationFrame
            try await Task.sleep(for: .milliseconds(50))
            #expect(player.isAnimationPlaying)
            #expect(player.realtimeAnimationFrame != frame)
            while player.isAnimationPlaying, began.duration(to: .now) < .seconds(2) {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(!player.isAnimationPlaying)
            #expect(began.duration(to: .now) >= .seconds(duration - 0.04))
            #expect(runtime.displayedPose == .resting)
        }
        #expect(runtime.triggerCount == 5)
    }

    @Test func restUpdatesDoNotFireReactBeforeFreshBlinkDeadline() async throws {
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
        let player = try #require(runtime.player)
        let window = try mount(player)
        defer { runtime.stop(); window.isHidden = true }
        try await Task.sleep(for: .milliseconds(80))
        #expect(!player.isAnimationPlaying, "Reattachment must not play a queued old reaction or blink")
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
        let player = try #require(runtime.player)
        let oldWindow = try mount(player)
        let oldContainer = try #require(player.superview)
        let newWindow = try mount(player)
        let newContainer = try #require(player.superview)
        #expect(oldContainer !== newContainer)
        defer { runtime.stop(); oldWindow.isHidden = true; newWindow.isHidden = true }
        CompanionLottieView.dismantleUIView(oldContainer, coordinator: player)
        #expect(player.superview === newContainer)
        await runtime.apply(output(.saved, reaction: UUID()), darkMode: false)
        try await Task.sleep(for: .milliseconds(50))
        #expect(player.isAnimationPlaying)
        #expect(player.superview === newContainer)
    }

    @Test func interruptionBeforeFirstFrameDropsTheCanceledReaction() async throws {
        let runtime = try await ready()
        await runtime.apply(output(.saved, reaction: UUID()), darkMode: false)
        await runtime.apply(output(.attentive), darkMode: false)
        let player = try #require(runtime.player)
        let window = try mount(player)
        defer { runtime.stop(); window.isHidden = true }
        try await Task.sleep(for: .milliseconds(500))
        #expect(runtime.displayedPose == .attentive)
        #expect(!player.isAnimationPlaying)
    }

    @Test func allFallbacksHaveBothAppearanceVariantsWithIdenticalBounds() throws {
        let runtime = CompanionRuntime()
        var size: CGSize?
        for pose in CompanionPose.allCases {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let image = try #require(UIImage(named: runtime.fallbackAssetName(for: pose), in: .main,
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

@MainActor private final class SettleProbe { var count = 0 }
