import Foundation
import Lottie
import Observation
import OSLog
import UIKit

@MainActor @Observable final class CompanionRuntime {
    private(set) var isReady = false
    private(set) var loadFailed = false
    private(set) var isPaused = true
    private(set) var character = CharacterCatalog.bundled.resolve("pip")
    private(set) var player: LottieAnimationView?
    private(set) var displayedPose: CompanionPose = .resting
    private(set) var triggerCount = 0
    @ObservationIgnored private var latestSurface: CompanionSurface = .today
    @ObservationIgnored private var displayedSurface: CompanionSurface = .today
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var playbackGeneration = 0
    @ObservationIgnored private var eligible = false
    @ObservationIgnored private var selected = false
    @ObservationIgnored private var consumedReaction: UUID?
    @ObservationIgnored private var latestOutput: CompanionOutput?
    @ObservationIgnored private let bundle: Bundle
    @ObservationIgnored private let load: @MainActor (CharacterDescriptor) async throws -> Data

    private static let logger = Logger(subsystem: "com.yakov103.mivu", category: "Companion")

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        load = { character in
            guard let url = bundle.url(forResource: character.animationResourcePath, withExtension: nil) else {
                throw AssetError.missing
            }
            return try await Task.detached(priority: .utility) {
                try Data(contentsOf: url, options: .mappedIfSafe)
            }.value
        }
    }

    init(load: @escaping @MainActor (CharacterDescriptor) async throws -> Data) {
        bundle = .main
        self.load = load
    }

    func select(_ character: CharacterDescriptor) async {
        guard !selected || self.character.id != character.id else { return }
        stop()
        player = nil
        isReady = false
        loadFailed = false
        self.character = character
        selected = true
        latestOutput = nil
        consumedReaction = nil
        displayedPose = .resting
        triggerCount = 0
        latestSurface = .today
        displayedSurface = .today
    }

    func attach(eligible: Bool) async {
        guard self.eligible != eligible else { return }
        self.eligible = eligible
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        guard eligible else { pauseAndReset(); return }
        if let reaction = latestOutput?.reactionID { consumedReaction = reaction }
        if isReady { pauseAndReset(); isPaused = false; return }
        let token = generation
        let descriptor = character
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadCharacter(descriptor, generation: token)
        }
        loadTask = task
        await task.value
        if generation == token { loadTask = nil }
    }

    func apply(_ output: CompanionOutput, darkMode: Bool, surface: CompanionSurface = .today) async {
        latestOutput = output
        latestSurface = surface
        guard eligible, output.playback == .animated, let player else {
            if let reaction = output.reactionID { consumedReaction = reaction }
            pauseAndReset()
            return
        }
        let freshReaction = output.reactionID != nil && output.reactionID != consumedReaction
        let oneShot = [.saved, .reviewed, .greeting].contains(output.pose)
        let pose = oneShot && !freshReaction && (displayedPose != output.pose || !player.isAnimationPlaying) ? .resting : output.pose
        let changed = pose != displayedPose || surface != displayedSurface
        isPaused = false
        if changed || freshReaction || !player.isAnimationPlaying {
            playbackGeneration += 1
            let token = playbackGeneration
            player.pause()
            displayedPose = pose
            displayedSurface = surface
            let marker = pose == .resting && freshReaction ? (surface == .coach ? "coach-blink" : "blink") : Self.marker(for: pose, surface: surface)
            if freshReaction && (oneShot || pose == .resting) { triggerCount += 1 }
            let render = { [self] in
                guard eligible, token == playbackGeneration else { return }
                let loops = [.resting, .attentive, .thinking, .recovery].contains(pose) && !freshReaction
                player.play(marker: marker, loopMode: loops ? .loop : .playOnce) { [weak self] finished in
                    guard let self, let player = self.player, finished, self.eligible, token == self.playbackGeneration else { return }
                    if oneShot || pose == .resting {
                        self.displayedPose = .resting
                        self.transition(player) {
                            player.play(marker: Self.marker(for: .resting, surface: self.latestSurface), loopMode: .loop)
                        }
                    }
                }
            }
            if changed { transition(player, render) } else { render() }
        }
        if let reaction = output.reactionID { consumedReaction = reaction }
    }

    func reconcileMount(_ mountedPlayer: LottieAnimationView) async {
        guard player === mountedPlayer, eligible, let latestOutput else { return }
        await apply(latestOutput, darkMode: false, surface: latestSurface)
    }

    func stop() {
        eligible = false
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        pauseAndReset()
    }

    func fallbackAssetName(for pose: CompanionPose) -> String {
        let names = ["Resting", "Attentive", "Thinking", "Saved", "Reviewed", "Recovery", "Greeting"]
        return character.fallbackAssetPrefix + names[pose.rawValue]
    }

    private func pauseAndReset() {
        playbackGeneration += 1
        isPaused = true
        player?.layer.removeAllAnimations()
        player?.pause()
        player?.currentFrame = player?.animation?.frameTime(forMarker: Self.marker(for: .resting, surface: latestSurface)) ?? 0
        displayedSurface = latestSurface
        displayedPose = .resting
        if let reaction = latestOutput?.reactionID { consumedReaction = reaction }
    }

    private func transition(_ player: LottieAnimationView, _ changes: @escaping () -> Void) {
        guard player.window != nil else { changes(); return }
        UIView.transition(with: player, duration: MivuMotion.companionTransition,
            options: [.transitionCrossDissolve, .beginFromCurrentState, .allowAnimatedContent], animations: changes)
    }

    private static func marker(for pose: CompanionPose, surface: CompanionSurface = .today) -> String {
        let name = ["resting", "attentive", "thinking", "saved", "reviewed", "recovery", "greeting"][pose.rawValue]
        return surface == .coach ? "coach-" + name : name
    }

    private func check(_ descriptor: CharacterDescriptor, _ token: Int) throws {
        guard !Task.isCancelled, eligible, token == generation, descriptor.id == character.id else { throw CancellationError() }
    }

    private func loadCharacter(_ descriptor: CharacterDescriptor, generation token: Int) async {
        do {
            guard descriptor.schemaVersion == 1 else { throw AssetError.schema }
            let data = try await load(descriptor)
            try check(descriptor, token)
            guard data.count <= 1_048_576 else { throw AssetError.corrupt }
            guard let url = bundle.url(forResource: descriptor.animationResourcePath, withExtension: nil) else { throw AssetError.missing }
            let directory = url.deletingLastPathComponent()
            let name = url.deletingPathExtension().lastPathComponent
            let prepared = try await Task.detached(priority: .utility) {
                let animation = try LottieAnimation.from(data: data)
                let images = try CompanionArtworkImageProvider(
                    artworkURL: directory.appendingPathComponent(name + "-artwork.png"),
                    matteURL: directory.appendingPathComponent(name + "-artwork-alpha.png"))
                return PreparedArtwork(animation: animation, images: images)
            }.value
            try check(descriptor, token)
            for marker in ["resting", "blink", "attentive", "thinking", "saved", "reviewed", "recovery", "greeting"].flatMap({ [$0, "coach-" + $0] }) {
                guard prepared.animation.frameTime(forMarker: marker) != nil,
                      let duration = prepared.animation.durationFrameTime(forMarker: marker), duration > 0 else { throw AssetError.schema }
            }
            let player = LottieAnimationView(animation: prepared.animation, imageProvider: prepared.images,
                configuration: LottieConfiguration(renderingEngine: .specific(.coreAnimation)))
            player.contentMode = .scaleAspectFit
            player.backgroundBehavior = .pause
            player.currentFrame = prepared.animation.frameTime(forMarker: "resting") ?? 0
            self.player = player
            if let reaction = latestOutput?.reactionID { consumedReaction = reaction }
            displayedPose = .resting
            displayedSurface = .today
            isReady = true
            loadFailed = false
            isPaused = false
        } catch is CancellationError {
            return
        } catch {
            guard token == generation, eligible, descriptor.id == character.id else { return }
            loadFailed = true
            isPaused = true
            Self.logger.error("Companion asset unavailable: validation or loading failed")
        }
    }

    private struct PreparedArtwork: @unchecked Sendable {
        let animation: LottieAnimation
        let images: CompanionArtworkImageProvider
    }
    private enum AssetError: Error { case missing, corrupt, schema }
}
