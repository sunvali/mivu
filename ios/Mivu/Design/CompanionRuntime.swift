import Foundation
import Observation
import OSLog
@preconcurrency import RiveRuntime

@MainActor @Observable final class CompanionRuntime {
    private(set) var isReady = false
    private(set) var loadFailed = false
    private(set) var isPaused = true
    private(set) var character = CharacterCatalog.bundled.resolve("pip")
    private(set) var player: RiveViewModel?
    @ObservationIgnored private(set) var binding: RiveDataBindingViewModel.Instance?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var eligible = false
    @ObservationIgnored private var selected = false
    @ObservationIgnored private var consumedReaction: UUID?
    @ObservationIgnored private var latestOutput: CompanionOutput?
    @ObservationIgnored private var currentPose: CompanionPose = .resting
    @ObservationIgnored private var appearance = false
    @ObservationIgnored private let load: @MainActor (CharacterDescriptor) async throws -> Data
    private(set) var triggerCount = 0

    private static let logger = Logger(subsystem: "com.yakov103.mivu", category: "Companion")

    init(bundle: Bundle = .main) {
        load = { character in
            guard let url = bundle.url(forResource: character.riveResourcePath, withExtension: nil) else {
                throw AssetError.missing
            }
            return try await Task.detached(priority: .utility) {
                try Data(contentsOf: url, options: .mappedIfSafe)
            }.value
        }
    }

    init(load: @escaping @MainActor (CharacterDescriptor) async throws -> Data) {
        self.load = load
    }

    func select(_ character: CharacterDescriptor) async {
        guard !selected || self.character.id != character.id else { return }
        stop()
        player = nil
        binding = nil
        isReady = false
        loadFailed = false
        self.character = character
        selected = true
        latestOutput = nil
        consumedReaction = nil
        currentPose = .resting
        triggerCount = 0
    }

    func attach(eligible: Bool) async {
        guard self.eligible != eligible else { return }
        self.eligible = eligible
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        guard eligible else {
            pauseAndReset()
            return
        }
        if let reaction = latestOutput?.reactionID { consumedReaction = reaction }
        if isReady {
            resetToRest()
            isPaused = false
            player?.play()
            return
        }
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

    func apply(_ output: CompanionOutput, darkMode: Bool) async {
        latestOutput = output
        let appearanceChanged = appearance != darkMode
        appearance = darkMode
        guard let binding else { return }
        binding.booleanProperty(fromPath: "darkMode")?.value = darkMode
        guard eligible, output.playback == .animated else {
            if let reaction = output.reactionID { consumedReaction = reaction }
            pauseAndReset()
            return
        }
        let freshReaction = output.reactionID != nil && output.reactionID != consumedReaction
        let oneShot = [.saved, .reviewed, .greeting].contains(output.pose)
        let pose = oneShot && !freshReaction && currentPose != output.pose ? .resting : output.pose
        let poseChanged = pose != currentPose
        if poseChanged || freshReaction && (oneShot || pose == .resting) {
            binding.numberProperty(fromPath: "pose")?.value = Float(pose.rawValue)
            currentPose = pose
        }
        if freshReaction && (oneShot || output.pose == .resting) {
            binding.triggerProperty(fromPath: "react")?.trigger()
            triggerCount += 1
        }
        if let reaction = output.reactionID { consumedReaction = reaction }
        isPaused = false
        if poseChanged || freshReaction || appearanceChanged { player?.play() }
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
        let needsReset = !isPaused
        isPaused = true
        player?.pause()
        if let reaction = latestOutput?.reactionID { consumedReaction = reaction }
        guard needsReset, let player else { return }
        do {
            // A fresh bound instance drops a trigger canceled before its first rendered frame.
            try player.configureModel(artboardName: "MivuCompanion", stateMachineName: "Companion")
            guard let binding = player.riveModel?.riveFile.viewModelNamed("CompanionModel")?.createDefaultInstance()
            else { throw AssetError.schema }
            binding.booleanProperty(fromPath: "darkMode")?.value = appearance
            player.riveModel?.stateMachine?.bind(viewModelInstance: binding)
            self.binding = binding
            currentPose = .resting
        } catch {
            self.player = nil
            binding = nil
            isReady = false
            loadFailed = true
            Self.logger.error("Companion asset unavailable: reset failed")
        }
    }

    private func resetToRest() {
        binding?.numberProperty(fromPath: "pose")?.value = 0
        currentPose = .resting
    }

    private func check(_ descriptor: CharacterDescriptor, _ token: Int) throws {
        guard !Task.isCancelled, eligible, token == generation, descriptor.id == character.id else {
            throw CancellationError()
        }
    }

    private func loadCharacter(_ descriptor: CharacterDescriptor, generation token: Int) async {
        do {
            guard descriptor.schemaVersion == 1 else { throw AssetError.schema }
            let data = try await load(descriptor)
            try check(descriptor, token)
            guard data.count <= 1_048_576, data.starts(with: [0x52, 0x49, 0x56, 0x45]) else {
                throw AssetError.corrupt
            }
            let file = try RiveFile(data: data, loadCdn: false)
            let model = RiveModel(riveFile: file)
            try model.setArtboard("MivuCompanion")
            try model.setStateMachine("Companion")
            guard let viewModel = file.viewModelNamed("CompanionModel"),
                  file.defaultViewModel(for: model.artboard)?.name == "CompanionModel" else {
                throw AssetError.schema
            }
            let properties = viewModel.properties
            guard properties.count == 3,
                  properties.contains(where: { $0.name == "pose" && $0.type == .number }),
                  properties.contains(where: { $0.name == "darkMode" && $0.type == .boolean }),
                  properties.contains(where: { $0.name == "react" && $0.type == .trigger }),
                  let binding = viewModel.createDefaultInstance(),
                  let pose = binding.numberProperty(fromPath: "pose"), pose.value == 0,
                  let darkMode = binding.booleanProperty(fromPath: "darkMode"), !darkMode.value,
                  binding.triggerProperty(fromPath: "react") != nil else { throw AssetError.schema }
            // The supported synchronous renderer avoids stale asynchronous settled callbacks.
            let player = RiveViewModel(model, stateMachineName: "Companion", autoPlay: false,
                                       artboardName: "MivuCompanion")
            player.riveModel?.stateMachine?.bind(viewModelInstance: binding)
            darkMode.value = appearance
            pose.value = 0
            self.binding = binding
            self.player = player
            if let reaction = latestOutput?.reactionID { consumedReaction = reaction }
            currentPose = .resting
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

    private enum AssetError: Error { case missing, corrupt, schema }
}
