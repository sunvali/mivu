import Foundation
import Testing
import UIKit
@preconcurrency import RiveRuntime
@testable import Mivu

@Suite(.serialized) @MainActor struct CompanionAssetTests {
    @Test func bundledAssetLoadsNamedArtboardMachineAndTypedBindings() async throws {
        let runtime = CompanionRuntime()
        await runtime.select(CharacterCatalog.bundled.resolve("pip"))
        await runtime.attach(eligible: true)
        #expect(runtime.isReady)
        #expect(!runtime.loadFailed)
        let rive = try #require(runtime.player)
        #expect(rive.artboardNames() == ["MivuCompanion"])
        #expect(rive.riveModel?.artboard.stateMachineNames() == ["Companion"])
        let binding = try #require(runtime.binding)
        #expect(rive.riveModel?.riveFile.viewModelNamed("CompanionModel")?.name == "CompanionModel")
        #expect(binding.numberProperty(fromPath: "pose")?.value == 0)
        #expect(binding.booleanProperty(fromPath: "darkMode")?.value == false)
    }
}

extension CompanionAssetTests {
    private var pip: CharacterDescriptor { CharacterCatalog.bundled.resolve("pip") }
    private var second: CharacterDescriptor {
        CharacterDescriptor(id: "test-second", displayName: "Test Second", schemaVersion: 1,
                            riveResourcePath: pip.riveResourcePath, fallbackAssetPrefix: "Second",
                            previewAssetName: "TestPreview")
    }

    private func bytes() throws -> Data {
        let url = try #require(Bundle.main.url(forResource: pip.riveResourcePath, withExtension: nil))
        let data = try Data(contentsOf: url)
        #expect(data.count > 32 && data.count <= 1_048_576)
        #expect(data.starts(with: [0x52, 0x49, 0x56, 0x45]))
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

    private func mount(_ player: RiveViewModel) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        let controller = UIViewController()
        let view = player.createRiveView()
        view.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        window.rootViewController = controller
        controller.view.addSubview(view)
        window.makeKeyAndVisible()
        return window
    }

    @Test func allSevenPosesAndRepeatedReactCanBeApplied() async throws {
        let runtime = try await ready()
        let binding = try #require(runtime.binding)
        for pose in CompanionPose.allCases {
            let reaction = [.saved, .reviewed, .greeting].contains(pose) ? UUID() : nil
            await runtime.apply(output(pose, reaction: reaction), darkMode: true)
            #expect(binding.numberProperty(fromPath: "pose")?.value == Float(pose.rawValue))
            #expect(binding.booleanProperty(fromPath: "darkMode")?.value == true)
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
        let nameRange = try #require(wrongBindings.range(of: Data("darkMode".utf8)))
        wrongBindings.replaceSubrange(nameRange, with: Data("darkMood".utf8))
        let wrongModel = CompanionRuntime(load: { _ in wrongBindings })
        await wrongModel.select(pip)
        await wrongModel.attach(eligible: true)
        #expect(wrongModel.loadFailed && wrongModel.player == nil)

        var calls = 0
        let runtime = CompanionRuntime(load: { _ in calls += 1; return try bytes() })
        let incompatible = CharacterDescriptor(id: "bad-schema", displayName: "Bad Schema", schemaVersion: 2,
                                             riveResourcePath: pip.riveResourcePath,
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
        let binding = try #require(runtime.binding)
        #expect(binding.numberProperty(fromPath: "pose")?.value == 0)
        await runtime.apply(output(.thinking, playback: .hidden), darkMode: false)
        #expect(runtime.binding === binding, "Repeated hidden output must preserve the already reset binding")
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
        #expect(runtime.player == nil && runtime.binding == nil && runtime.isPaused)
        #expect(oldPlayer == nil)
        await runtime.attach(eligible: true)
        #expect(runtime.triggerCount == 0)
        let binding = try #require(runtime.binding)
        #expect(binding.numberProperty(fromPath: "pose")?.value == 0)
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

    @Test func oneShotsSettleAtRestWithoutHostCompletionCallback() async throws {
        let runtime = try await ready()
        let player = try #require(runtime.player)
        let window = try mount(player)
        defer { player.pause(); player.deregisterView(); window.isHidden = true }
        player.play()
        try await Task.sleep(for: .milliseconds(200))
        #expect(!player.isPlaying)
        let binding = try #require(runtime.binding)
        let trigger = try #require(binding.triggerProperty(fromPath: "react"))
        let triggerProbe = SettleProbe()
        let observation = trigger.addListener { triggerProbe.count += 1 }
        defer { trigger.removeListener(observation) }
        for (index, pose) in [CompanionPose.saved, .saved, .reviewed, .greeting, .resting].enumerated() {
            let started = ContinuousClock.now
            let duration: Double = pose == .saved ? MivuMotion.saved : pose == .reviewed
                ? MivuMotion.reviewed : pose == .greeting ? MivuMotion.greeting : MivuMotion.blink
            await runtime.apply(output(pose, reaction: UUID()), darkMode: false)
            #expect(player.isPlaying)
            try await Task.sleep(for: .milliseconds(50))
            #expect(player.isPlaying, "Real gesture must still be advancing after 50ms")
            let deadline = started.advanced(by: .seconds(2))
            while player.isPlaying, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let elapsed = started.duration(to: .now)
            print("Real gesture \(index) \(pose) stopped after \(elapsed)")
            #expect(!player.isPlaying, "Authored reaction must naturally stop without a host callback")
            #expect(elapsed >= .seconds(duration - 0.04))
            #expect(triggerProbe.count == index + 1)
        }
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
        let binding = try #require(runtime.binding)
        #expect(binding.numberProperty(fromPath: "pose")?.value == 0)
        let player = try #require(runtime.player)
        let window = try mount(player)
        defer { player.pause(); player.deregisterView(); window.isHidden = true }
        player.play()
        try await Task.sleep(for: .milliseconds(80))
        #expect(!player.isPlaying, "Reattachment must not play a queued old reaction or blink")
    }

    @Test func appearanceChangeDoesNotRetriggerActiveAction() async throws {
        let runtime = try await ready()
        let action = output(.reviewed, reaction: UUID())
        await runtime.apply(action, darkMode: false)
        await runtime.apply(action, darkMode: true)
        #expect(runtime.triggerCount == 1)
        let binding = try #require(runtime.binding)
        #expect(binding.numberProperty(fromPath: "pose")?.value == 4)
        #expect(binding.booleanProperty(fromPath: "darkMode")?.value == true)
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
