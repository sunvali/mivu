import Foundation
import Observation
import OSLog
import UIKit

@MainActor @Observable final class CompanionRuntime {
    private(set) var isReady = false
    private(set) var loadFailed = false
    private(set) var isPaused = true
    private(set) var character = CharacterCatalog.bundled.resolve("pip")
    private(set) var rig: PipRigView?
    private(set) var displayedPose: CompanionPose = .resting
    private(set) var triggerCount = 0
    /// Observable by tests: the last gesture handed to the rig, the idle beats started, and where the eyes point.
    @ObservationIgnored private(set) var lastGestureName: String?
    @ObservationIgnored private(set) var idleBeatCount = 0
    @ObservationIgnored private(set) var gestureStarts = 0
    @ObservationIgnored private(set) var playedGestures: [String] = []
    @ObservationIgnored private(set) var gaze = CGPoint.zero
    @ObservationIgnored var isIdleScheduled: Bool { idleTask != nil }
    @ObservationIgnored private var asset: PipRigAsset?
    @ObservationIgnored private var latestSurface: CompanionSurface = .today
    @ObservationIgnored private var displayedSurface: CompanionSurface = .today
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var playbackGeneration = 0
    @ObservationIgnored private var gestureToken = 0
    @ObservationIgnored private var gestureActive = false
    @ObservationIgnored private var live = false
    @ObservationIgnored private(set) var curled = false
    @ObservationIgnored private var eligible = false
    @ObservationIgnored private var selected = false
    @ObservationIgnored private var latestDark = false
    @ObservationIgnored private var consumedReaction: UUID?
    @ObservationIgnored private var latestOutput: CompanionOutput?
    @ObservationIgnored private var scheduler: PipIdleScheduler
    @ObservationIgnored private var lastInput: Date
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let sleep: (TimeInterval) async throws -> Void
    @ObservationIgnored private let load: @MainActor (CharacterDescriptor) async throws -> Data

    private static let logger = Logger(subsystem: "com.yakov103.mivu", category: "Companion")
    private static let restGesture = PipGesture(name: "rest", keys: [(0.3, .rest)])

    convenience init(bundle: Bundle = .main, clock: @escaping () -> Date = Date.init,
         sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
         random: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.init(clock: clock, sleep: sleep, random: random) { character in
            guard let url = bundle.url(forResource: character.animationResourcePath, withExtension: nil) else {
                throw AssetError.missing
            }
            return try await Task.detached(priority: .utility) {
                try Data(contentsOf: url, options: .mappedIfSafe)
            }.value
        }
    }

    init(clock: @escaping () -> Date = Date.init,
         sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
         random: any RandomNumberGenerator = SystemRandomNumberGenerator(),
         load: @escaping @MainActor (CharacterDescriptor) async throws -> Data) {
        self.clock = clock
        self.sleep = sleep
        scheduler = PipIdleScheduler(random: random)
        lastInput = clock()
        self.load = load
    }

    func select(_ character: CharacterDescriptor) async {
        guard !selected || self.character.id != character.id else { return }
        stop()
        rig = nil
        asset = nil
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
        latestDark = darkMode
        guard eligible, output.playback == .animated else {
            if let reaction = output.reactionID { consumedReaction = reaction }
            pauseAndReset()
            if eligible, output.playback == .staticPose { showStill(output) }
            return
        }
        guard let rig else { isPaused = true; return }
        rig.isDark = darkMode
        let freshReaction = output.reactionID != nil && output.reactionID != consumedReaction
        let oneShot = Self.isOneShot(output.pose)
        let pose = oneShot && !freshReaction && (displayedPose != output.pose || !gestureActive) ? .resting : output.pose
        let surfaceChanged = surface != displayedSurface
        if pose != .attentive { gaze = .zero }
        let typingGaze = pose == .attentive ? Self.typingGaze(output.typingProgress) : nil
        let changed = pose != displayedPose || surfaceChanged
        isPaused = false
        if surfaceChanged { show(surface) }
        startIdle()
        if !(changed || freshReaction || !live), let typingGaze, typingGaze != gaze {
            gaze = typingGaze // same pose: only the eyes follow the text, never a restart
            rig.look(at: typingGaze)
        } else if changed || freshReaction || !live {
            playbackGeneration += 1
            let token = playbackGeneration
            live = true
            displayedPose = pose
            displayedSurface = surface
            rig.setBreathing(true)
            if freshReaction && (oneShot || pose == .resting) { triggerCount += 1 }
            if pose != .resting || freshReaction { lastInput = clock() }
            if let moment = Self.moment(for: pose, tapLevel: output.tapLevel, hour: Calendar.current.component(.hour, from: clock())) {
                var gesture = PipGestureLibrary.loop(for: moment) ?? PipGestureLibrary.gesture(for: moment)
                if let typingGaze { gesture = Self.looking(gesture, at: typingGaze) }
                play(gesture) { [weak self] _ in
                    guard let self, token == self.playbackGeneration else { return }
                    if oneShot { self.displayedPose = .resting }
                }
                if let typingGaze { gaze = typingGaze }
            } else if curled {
                // A quiet re-render does not wake a sleeping Pip.
            } else {
                if freshReaction { rig.blink() }
                play(Self.restGesture) { _ in }
            }
        }
        if let reaction = output.reactionID { consumedReaction = reaction }
    }

    func reconcileMount(_ mounted: PipRigView) async {
        guard rig === mounted, eligible, let latestOutput else { return }
        await apply(latestOutput, darkMode: latestDark, surface: latestSurface)
        resumeBreathing()
    }

    /// Core Animation drops a layer's animations when it leaves a window, so a remounted rig needs its breath again.
    func resumeBreathing() {
        if live { rig?.setBreathing(true) }
    }

    /// The small acknowledgement for a touch that cannot start a reaction. Never interrupts anything.
    func earTwitch() {
        guard eligible, live, !gestureActive, displayedPose == .resting, !curled else { return }
        play(PipGestureLibrary.gesture(for: .earTwitch), wakes: false) { _ in }
    }

    func stop() {
        eligible = false
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        pauseAndReset()
    }

    /// Width over height of the artboard crop each surface shows (the asset's frames), with the shipped values until loaded.
    func cropAspect(for surface: CompanionSurface) -> CGFloat {
        let frame = asset?.frames[surface == .coach ? "coach" : "today"]
        return frame.map { $0.width / $0.height } ?? (surface == .coach ? 281.0 / 288.8 : 399.8 / 455.5)
    }

    func fallbackAssetName(for surface: CompanionSurface = .today) -> String {
        character.fallbackAssetPrefix + (surface == .coach ? "Coach" : "Resting")
    }

    /// The one place app output becomes a moment. Resting has no moment.
    static func moment(for pose: CompanionPose, tapLevel: Int, hour: Int) -> PipMoment? {
        switch pose {
        case .resting: nil
        case .attentive: .attentive
        case .thinking: .thinking
        case .saved: .saved
        case .reviewed: .reviewed
        case .recovery: .recovery
        case .greeting: .greeting(hour: hour)
        case .submitted: .submitted
        case .firstMealToday: .firstMealToday
        case .dayComplete: .dayComplete
        case .curious: .curious
        case .tapped: .tapped(level: tapLevel)
        case .patted: .patted
        case .welcomeBack: .welcomeBack
        case .presentingCheer: .presenting(cheer: true)
        case .presentingCalm: .presenting(cheer: false)
        case .progressEntrance: .progressEntrance(cheer: false)
        case .progressEntranceCheer: .progressEntrance(cheer: true)
        case .progressRange: .progressRange
        case .progressTap: .progressTap(level: tapLevel)
        }
    }

    private static func isOneShot(_ pose: CompanionPose) -> Bool {
        ![.resting, .attentive, .thinking, .recovery, .presentingCheer, .presentingCalm].contains(pose)
    }

    /// Looks down at the field below Pip's paws and follows the caret left to right as the draft grows.
    private static func typingGaze(_ progress: Double) -> CGPoint {
        CGPoint(x: -0.3 + 1.3 * min(max(progress, 0), 1), y: 0.8)
    }

    /// Typing holds the attentive loop's first pose, head bowed 14 degrees toward the text and turned with it: a loop's
    /// later glances would pull the eyes off the text.
    private static func looking(_ gesture: PipGesture, at point: CGPoint) -> PipGesture {
        PipGesture(name: gesture.name, keys: gesture.keys.prefix(1).map { key in
            var pose = key.pose.nod(14)
            pose.gaze = point
            pose.headTurn = 1 + 0.35 * point.x
            return (key.at, pose)
        }, loops: false, endSet: gesture.endSet)
    }

    private func restPose(_ surface: CompanionSurface) -> PipPose {
        var pose = PipPose.rest
        pose.set = surface == .coach ? .seated : .standing
        return pose
    }

    /// Reduce Motion and friends: the rig holds the semantic pose with no animation and no timers.
    private func showStill(_ output: CompanionOutput) {
        guard let rig else { return }
        rig.isDark = latestDark
        let hour = Calendar.current.component(.hour, from: clock())
        var pose = Self.moment(for: output.pose, tapLevel: output.tapLevel, hour: hour).map(PipGestureLibrary.stillPose(for:)) ?? .rest
        pose.set = restPose(latestSurface).set
        if output.pose == .attentive { pose.gaze = Self.typingGaze(output.typingProgress) }
        rig.apply(pose, animated: false)
    }

    private func show(_ surface: CompanionSurface) {
        curled = false
        displayedSurface = surface
        if let asset { rig?.visibleRect = asset.frames[surface == .coach ? "coach" : "today"] ?? rig?.visibleRect ?? .zero }
        rig?.apply(restPose(surface), animated: false)
    }

    /// Plays `gesture`; `done(finished)` reports false when anything else takes the rig. A sleeping Pip wakes first.
    private func play(_ gesture: PipGesture, wakes: Bool = true, done: @escaping (Bool) -> Void) {
        guard let rig else { done(false); return }
        gestureToken += 1
        let token = gestureToken
        gestureActive = true
        gestureStarts += 1
        lastGestureName = gesture.name
        if curled && wakes { playedGestures.append(PipGestureLibrary.wake.name) }
        playedGestures.append(gesture.name)
        playedGestures = Array(playedGestures.suffix(8)) // a test probe; never grows for the session
        let finish: (Bool) -> Void = { [weak self] finished in
            if let self, token == self.gestureToken {
                self.gestureActive = false // an interrupted gesture must not leave the idle loop waiting
                if finished, let end = gesture.endSet { self.curled = end == .curled }
            }
            done(finished)
        }
        if curled && wakes {
            rig.play(PipGestureLibrary.wake(endingIn: restPose(displayedSurface).set)) { [weak self, weak rig] finished in
                guard finished, let self, token == self.gestureToken else { finish(false); return }
                self.curled = false
                rig?.play(gesture, completion: finish)
            }
        } else {
            rig.play(gesture, completion: finish)
        }
    }

    private func startIdle() {
        guard idleTask == nil else { return }
        idleTask = Task { @MainActor [weak self] in await self?.idleLoop() }
    }

    private func idleLoop() async {
        while !Task.isCancelled {
            // Wait out feedback and gestures first, so the scheduler's hug-then-curl memory never advances unseen.
            guard live, displayedPose == .resting, !gestureActive else {
                do { try await sleep(0.5) } catch { return }
                continue
            }
            let now = clock()
            let surface = displayedSurface
            let next = scheduler.next(after: lastInput, now: now, surface: surface)
            do { try await sleep(max(0, next.at.timeIntervalSince(now))) } catch { return }
            // The wait can outlast a touch, a reaction or a surface change; a beat chosen before them is stale.
            guard !Task.isCancelled, let rig, live, displayedPose == .resting, !gestureActive,
                  lastInput <= now, displayedSurface == surface else { continue }
            idleBeatCount += 1
            switch next.beat {
            case .blink: rig.blink()
            case .doubleBlink: rig.blink(double: true)
            case .glance(let point):
                rig.look(at: point)
                do { try await sleep(0.9) } catch { return }
                if live, !gestureActive, displayedPose == .resting { rig.look(at: .zero) }
            default:
                guard let gesture = PipGestureLibrary.gesture(forIdle: next.beat, curled: curled) else { continue }
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    play(gesture, wakes: false) { _ in done.resume() }
                }
            }
        }
    }

    private func pauseAndReset() {
        playbackGeneration += 1
        gestureToken += 1
        gestureActive = false
        live = false
        curled = false
        isPaused = true
        idleTask?.cancel()
        idleTask = nil
        rig?.removeAllMotion()
        rig?.setBreathing(false)
        gaze = .zero
        show(latestSurface)
        displayedPose = .resting
        if let reaction = latestOutput?.reactionID { consumedReaction = reaction }
    }

    private func check(_ descriptor: CharacterDescriptor, _ token: Int) throws {
        guard !Task.isCancelled, eligible, token == generation, descriptor.id == character.id else { throw CancellationError() }
    }

    private func loadCharacter(_ descriptor: CharacterDescriptor, generation token: Int) async {
        do {
            guard descriptor.schemaVersion == 2 else { throw AssetError.schema }
            let data = try await load(descriptor)
            try check(descriptor, token)
            let loaded = try await Task.detached(priority: .utility) { try PipRigAsset.load(data) }.value
            try check(descriptor, token)
            let rig = PipRigView(asset: loaded, set: latestSurface == .coach ? .seated : .standing)
            rig.visibleRect = loaded.frames[latestSurface == .coach ? "coach" : "today"] ?? rig.visibleRect
            asset = loaded
            self.rig = rig
            displayedPose = .resting
            displayedSurface = latestSurface
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

    private enum AssetError: Error { case missing, schema }
}
