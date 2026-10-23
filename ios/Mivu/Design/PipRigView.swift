import QuartzCore
import UIKit

/// Draws a `PipRigAsset` as one CALayer per part. A part's container carries its transform and
/// holds its own shape plus its children, so every layer sits in artboard coordinates.
final class PipRigView: UIView {
    private let asset: PipRigAsset
    private let root = CALayer()
    /// Carries the head views onto the active set's body at its mount.
    private let headMount = CALayer()
    private var containers: [String: CALayer] = [:]
    private var shapes: [String: CAShapeLayer] = [:]
    private var slots: [String: String] = [:]
    private var pupilReach: [String: (lo: CGPoint, hi: CGPoint)] = [:]
    /// Iris part id -> how far the whole iris group may travel inside the eye white at full gaze.
    private var irisReach: [String: CGSize] = [:]
    /// Glint part id -> its iris; the glint counter-shifts so the light seems fixed.
    private var glintIris: [String: String] = [:]
    private var playback: Playback?
    private var lookFollow: DispatchWorkItem?
    private var playbackTick = 0

    /// Timers still waiting for the current gesture; bounded by one pass of its keys, even for a loop.
    var pendingWorkCount: Int { playback?.work.count ?? 0 }

    private final class Playback {
        let token: Int
        let completion: (Bool) -> Void
        var work: [DispatchWorkItem] = []
        init(token: Int, completion: @escaping (Bool) -> Void) { self.token = token; self.completion = completion }
    }

    /// Artboard rectangle to fit in the view (defaults to the whole artboard).
    var visibleRect = CGRect(x: 0, y: 0, width: 512, height: 512) { didSet { setNeedsLayout() } }
    var isDark = false { didSet { if isDark != oldValue { applyFills() } } }
    private(set) var visibleViews: Set<String> = []
    private var pose = PipPose.rest
    /// Progress dresses Pip with the chart card and reading glasses. They belong to the screen, not a pose, so
    /// gestures never blink them; head parts only show in the active view.
    var showsProgressProps = false {
        didSet {
            guard showsProgressProps != oldValue else { return }
            apply(pose, animated: false)
        }
    }
    private static func isProgressProp(_ part: PipRigAsset.Part) -> Bool {
        part.name.hasPrefix("prop-chart") || part.name.hasPrefix("glasses")
    }
    private let bottomCrop = CALayer()

    init(asset: PipRigAsset, set: PipPose.BodySet) {
        self.asset = asset
        super.init(frame: .zero)
        // Only the bottom edge crops (Pip peeks over the bar); head turns and tilts may spill past the others.
        bottomCrop.backgroundColor = UIColor.black.cgColor
        layer.mask = bottomCrop
        isAccessibilityElement = false
        build()
        isDark = traitCollection.userInterfaceStyle == .dark
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in
            view.isDark = view.traitCollection.userInterfaceStyle == .dark
        }
        pose.set = set
        apply(pose, animated: false)
    }

    deinit { MainActor.assumeIsolated { stopPlayback() } }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func layer(named id: String) -> CALayer? { containers[id] }

    func removeAllMotion() {
        stopPlayback()
        lookFollow?.cancel()
        root.removeAllAnimations()
        containers.values.forEach { $0.removeAllAnimations() }
        shapes.values.forEach { $0.removeAllAnimations() }
    }

    func apply(_ pose: PipPose, animated: Bool) {
        self.pose = pose
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated { CATransaction.setAnimationDuration(0.2) }
        let (view, local) = Self.view(for: pose.headTurn)
        let wanted: Set<String> = ["eye-l.\(pose.eyes.rawValue)", "eye-r.\(pose.eyes.rawValue)", "mouth.\(pose.mouth.rawValue)"]
        var views: Set<String> = []
        for part in asset.parts {
            guard let container = containers[part.id] else { continue }
            container.isHidden = !isShown(part, view: view, wanted: wanted, pose: pose)
            if !container.isHidden, let partView = part.view { views.insert(partView) }
            if let opacity = opacity(of: part, in: pose) { container.opacity = opacity }
            container.transform = Self.transform(joint(of: part, in: pose, slide: local))
        }
        visibleViews = views
        mountHead(on: pose.set)
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = min(bounds.width / visibleRect.width, bounds.height / visibleRect.height)
        let tx = (bounds.width - visibleRect.width * s) / 2 - visibleRect.minX * s
        let ty = (bounds.height - visibleRect.height * s) / 2 - visibleRect.minY * s
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.setAffineTransform(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: tx, ty: ty))
        bottomCrop.frame = CGRect(x: -bounds.width, y: -bounds.height, width: bounds.width * 3, height: bounds.height * 2)
        CATransaction.commit()
    }

    /// Shared parts on `body` (the head views, hearts) follow whichever set's body is active.
    private static func ridesHeadMount(_ part: PipRigAsset.Part) -> Bool { part.parent == "body" && part.set == nil }

    private func mountHead(on set: PipPose.BodySet) {
        let body = asset.parts.first { $0.name == "body" && $0.set == set.rawValue }
        let host = body.flatMap { containers[$0.id] } ?? root
        if headMount.superlayer !== host { host.addSublayer(headMount) }
        let m = body?.mount ?? [1, 0, 0]
        headMount.setAffineTransform(CGAffineTransform(a: m[0], b: 0, c: 0, d: m[0], tx: m[1], ty: m[2]))
    }

    // MARK: - Pose resolution

    private func joint(of part: PipRigAsset.Part, in pose: PipPose, slide local: CGFloat) -> PipPose.Joint {
        // A joint keyed by the full id (`arm-r@seated`) moves only that set's part; a plain name moves every set's.
        var joint = pose.joints[part.id] ?? pose.joints[part.name] ?? PipPose.Joint()
        let gaze = Self.clamped(pose.gaze)
        if let reach = pupilReach[part.id] {
            joint.offset.x += gaze.x * (gaze.x < 0 ? -reach.lo.x : reach.hi.x)
            joint.offset.y += gaze.y * (gaze.y < 0 ? -reach.lo.y : reach.hi.y)
        }
        if let reach = irisReach[part.id] {
            joint.offset.x += gaze.x * reach.width
            joint.offset.y += gaze.y * reach.height
        } else if let iris = glintIris[part.id], let reach = irisReach[iris] {
            joint.offset.x -= 0.3 * gaze.x * reach.width
            joint.offset.y -= 0.3 * gaze.y * reach.height
        }
        joint.offset.x += (part.parallax ?? 0) * local * asset.parallaxScale
        return joint
    }

    private static func transform(_ joint: PipPose.Joint) -> CATransform3D {
        var t = CATransform3DMakeScale(joint.scale.width, joint.scale.height, 1)
        t = CATransform3DRotate(t, joint.rotation, 0, 0, 1)
        return t.translated(x: joint.offset.x, y: joint.offset.y)
    }

    /// Blush and hearts fade in and out instead of popping; the chart card and glasses follow `showsProgressProps`.
    private func opacity(of part: PipRigAsset.Part, in pose: PipPose) -> Float? {
        if part.name.hasPrefix("cheek-blush") { return pose.blush ? 1 : 0 }
        // The card's own parts start hidden too, so every `prop-chart…` part follows the flag.
        if Self.isProgressProp(part) { return showsProgressProps ? 1 : nil }  // nil: not shown at all, like any hidden part
        if part.name.hasPrefix("heart-"), let n = Int(part.name.dropFirst(6)) { return n <= pose.hearts ? 1 : 0 }
        return nil
    }

    /// Which head view to show and how far (-1...1) to slide features inside it.
    private static func view(for turn: CGFloat) -> (String, CGFloat) {
        let (name, centre, span): (String, CGFloat, CGFloat) =
            turn > 0.35 ? ("right", 1, 0.65) : turn < -0.35 ? ("left", -1, 0.65) : ("front", 0, 0.35)
        return (name, max(-1, min(1, (turn - centre) / span)))
    }

    private static func clamped(_ gaze: CGPoint) -> CGPoint {
        let length = hypot(gaze.x, gaze.y)
        return length > 1 ? CGPoint(x: gaze.x / length, y: gaze.y / length) : gaze
    }

    private func isShown(_ part: PipRigAsset.Part, view: String, wanted: Set<String>, pose: PipPose) -> Bool {
        guard part.view == nil || part.view == view, part.set == nil || part.set == pose.set.rawValue else { return false }
        if let slot = slots[part.id] { return wanted.contains(slot) }
        return part.visible || opacity(of: part, in: pose) != nil
    }

    // MARK: - Layer tree

    private func build() {
        root.anchorPoint = .zero
        root.bounds = CGRect(x: 0, y: 0, width: asset.artboard, height: asset.artboard)
        layer.addSublayer(root)
        headMount.anchorPoint = .zero
        headMount.bounds = root.bounds
        headMount.zPosition = CGFloat(asset.parts.filter(Self.ridesHeadMount).map(\.z).min() ?? 0)
        let byID = Dictionary(uniqueKeysWithValues: asset.parts.map { ($0.id, $0) })
        for part in asset.parts {
            let container = CALayer()
            container.bounds = root.bounds
            container.anchorPoint = CGPoint(x: part.pivot[0] / asset.artboard, y: part.pivot[1] / asset.artboard)
            container.position = CGPoint(x: part.pivot[0], y: part.pivot[1])
            container.zPosition = CGFloat(part.z)
            container.actions = ["hidden": NSNull()] // views and slots swap instantly; a crossfade shows both heads see-through
            let shape = CAShapeLayer()
            shape.frame = root.bounds
            shape.zPosition = CGFloat(part.z)
            shape.path = try? PipRigAsset.cgPath(part.path)
            container.addSublayer(shape)
            containers[part.id] = container
            shapes[part.id] = shape
        }
        for part in asset.parts {
            // Shared parts on `body` ride the head mount; a missing parent means root.
            let parent = Self.ridesHeadMount(part) ? headMount : part.parent.flatMap { containers[$0] } ?? root
            if let white = irisWhite(of: part), let box = shapes[white.id]?.path?.boundingBoxOfPath {
                // The iris group travels freely; this fixed wrapper clips it to the eye white.
                let wrapper = CALayer()
                wrapper.anchorPoint = .zero
                wrapper.bounds = root.bounds
                wrapper.zPosition = CGFloat(part.z)
                let mask = CAShapeLayer()
                mask.frame = root.bounds
                mask.path = shapes[white.id]?.path
                wrapper.mask = mask
                wrapper.addSublayer(containers[part.id]!)
                parent.addSublayer(wrapper)
                irisReach[part.id] = CGSize(width: 0.3 * box.width, height: 0.4 * box.height) // enough to read as looking down at the text
            } else {
                parent.addSublayer(containers[part.id]!)
            }
            if part.name.contains("glint"), let iris = part.parent, byID[iris]?.name.contains("iris") == true { glintIris[part.id] = iris }
            var ancestor: PipRigAsset.Part? = part
            while let current = ancestor, current.shape == nil { ancestor = current.parent.flatMap { byID[$0] } }
            slots[part.id] = ancestor?.shape
            if part.name.contains("pupil"), let iris = part.parent.flatMap({ shapes[$0]?.path?.boundingBoxOfPath }),
               let pupil = shapes[part.id]?.path?.boundingBoxOfPath {
                // Up to 35% of the iris radius, never past the iris edge.
                let reach = 0.35 * iris.width / 2
                pupilReach[part.id] = (
                    lo: CGPoint(x: min(0, max(-reach, iris.minX - pupil.minX)), y: min(0, max(-reach, iris.minY - pupil.minY))),
                    hi: CGPoint(x: max(0, min(reach, iris.maxX - pupil.maxX)), y: max(0, min(reach, iris.maxY - pupil.maxY))))
            }
        }
        applyFills()
    }

    /// The eye-white part beside an iris (`eye-l`, or `eye-l.wide.white` for the other shapes).
    private func irisWhite(of part: PipRigAsset.Part) -> PipRigAsset.Part? {
        guard part.name.contains("iris") else { return nil }
        return asset.parts.first { $0.parent == part.parent && ($0.name.hasSuffix(".white") || $0.name == "eye-l" || $0.name == "eye-r") }
    }

    private func applyFills() {
        for part in asset.parts {
            shapes[part.id]?.fillColor = Self.color(isDark ? part.fillDark ?? part.fill : part.fill)
        }
    }

    private static func color(_ hex: String) -> CGColor {
        let v = Int(hex.dropFirst(), radix: 16) ?? 0
        return CGColor(red: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}

// MARK: - Springs, gestures and living eyes

extension PipRigView {
    /// Eyes snap to a new gaze in about 60 ms with a little overshoot.
    private static let saccadeOmega: CGFloat = 110
    /// Eyes reach a head turn's direction this long before the head finishes turning.
    private static let eyesLead: TimeInterval = 0.08

    /// Plays the gesture's keys as springs. `completion(false)` if another play, `removeAllMotion()` or deallocation ends it first.
    func play(_ gesture: PipGesture, completion: @escaping (Bool) -> Void) {
        stopPlayback()
        playbackTick += 1
        let run = Playback(token: playbackTick, completion: completion)
        playback = run
        schedule(gesture, run: run)
    }

    private func schedule(_ gesture: PipGesture, run: Playback) {
        for (i, key) in gesture.keys.enumerated() {
            let launch = i == 0 ? 0 : gesture.keys[i - 1].at
            let changesSet = i == gesture.keys.count - 1 ? gesture.endSet : nil
            after(launch, run) { [unowned self] in step(to: key.pose, set: changesSet, period: key.at - launch) }
        }
        after(gesture.duration, run) { [unowned self] in
            if gesture.loops && gesture.duration > 0 { // a zero-length loop would recurse forever
                run.work.removeAll()
                schedule(gesture, run: run)
                return
            }
            run.work.removeAll() // the items capture `run`; dropping them breaks the cycle so the playback can free
            playback = nil
            run.completion(true)
        }
    }

    /// Runs `work` now when `delay` is zero, else on the main queue unless the playback was stopped.
    private func after(_ delay: TimeInterval, _ run: Playback, _ work: @escaping () -> Void) {
        guard delay > 0 else { work(); return }
        let item = DispatchWorkItem { [weak self] in
            guard let self, playback === run else { return }
            work()
        }
        run.work.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func stopPlayback() {
        guard let run = playback else { return }
        playback = nil
        run.work.forEach { $0.cancel() }
        run.work.removeAll()
        run.completion(false)
    }

    /// One key: eyes go first when the head turns, then the head follows.
    private func step(to key: PipPose, set: PipPose.BodySet?, period: TimeInterval) {
        var target = key
        target.set = set ?? pose.set // gestures are authored on `.rest`; only a declared `endSet` changes the body set
        guard target.headTurn != pose.headTurn, period > Self.eyesLead, let run = playback else {
            transition(to: target, period: period)
            return
        }
        var glance = pose
        glance.gaze = CGPoint(x: target.headTurn > pose.headTurn ? 1 : -1, y: target.gaze.y)
        transition(to: glance, period: period)
        // A view swap lands while the eyes are shut (40-110 ms into the blink), so it reads as a quick turn, not a cut.
        if Self.view(for: target.headTurn).0 != Self.view(for: pose.headTurn).0 { blink() }
        after(Self.eyesLead, run) { [unowned self] in transition(to: target, period: period - Self.eyesLead) }
    }

    /// Chest and head swell 2% over 4.5 s and back. Additive, so it rides on top of gesture springs instead of fighting them.
    func setBreathing(_ on: Bool) {
        let breath = CABasicAnimation(keyPath: "transform.scale.y")
        breath.fromValue = 0
        breath.toValue = 0.02
        breath.duration = 4.5
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.isAdditive = true
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        for part in asset.parts where part.name == "head" || part.name == "chest" {
            guard let container = containers[part.id] else { continue }
            if !on { container.removeAnimation(forKey: "breath") }
            else if container.animation(forKey: "breath") == nil { container.add(breath, forKey: "breath") } // keep the phase running
        }
    }

    /// Saccade to `point` (unit disc, +y down) for idle glances and typing. With no gesture playing the head follows a
    /// beat later and slower: the face slides toward the look inside the current view (never a view swap, which reads as
    /// a pop) and nods up to 3 degrees, as the character sheet's "tiny gaze changes" ask.
    func look(at point: CGPoint, animated: Bool = true) {
        var next = pose
        next.gaze = point
        guard animated else { apply(next, animated: false); return }
        transition(to: next, period: 0.06)
        lookFollow?.cancel()
        guard playback == nil else { return }
        var follow = next
        follow.headTurn = 1 + 0.35 * point.x // 0.65...1.35 stays in the right view
        // A pose that already bows the head (typing looks down at the text) keeps its nod.
        if (follow.joints["head"]?.rotation ?? 0) == 0 { follow.joints["head", default: PipPose.Joint()].rotation = 3 * .pi / 180 * point.y }
        let item = DispatchWorkItem { [weak self] in
            guard let self, playback == nil, pose == next else { return }
            transition(to: follow, period: 0.45)
        }
        lookFollow = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    /// A drawn cartoon blink: half-shut (40 ms), shut (70 ms), half-shut (40 ms), open. It swaps the painted eye
    /// shapes instead of squashing the open eye, which read as a glitch. The model never changes. `double` blinks twice.
    func blink(double: Bool = false) {
        guard pose.eyes == .open else { return }
        let view = Self.view(for: pose.headTurn).0
        // Which shape shows in each phase: half, shut, half, then open again for the last 5%.
        let phases: [(shape: String, shown: [Bool])] = [
            ("open", [false, false, false, true]), ("half", [true, false, true, false]), ("closedSleepy", [false, true, false, false]),
        ]
        for side in ["l", "r"] {
            for (shape, shown) in phases {
                for part in asset.parts where part.view == view && slots[part.id] == "eye-\(side).\(shape)" {
                    guard let layer = containers[part.id] else { continue }
                    for (i, offset) in (double ? [0, 0.3] : [0]).enumerated() {
                        let blink = CAKeyframeAnimation(keyPath: "hidden")
                        blink.calculationMode = .discrete
                        blink.values = shown.map { NSNumber(value: !$0) }
                        blink.keyTimes = [0, 0.25, 0.7, 0.95, 1]
                        blink.duration = Self.blinkDuration
                        if offset > 0 { blink.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + offset }
                        layer.add(blink, forKey: i == 0 ? "blink" : "blink2")
                    }
                }
            }
        }
    }

    static let blinkDuration: TimeInterval = 0.16

    /// Moves to `target` with one spring per changed joint component, each starting from what is on screen now.
    private func transition(to target: PipPose, period: TimeInterval) {
        var before: [String: [Float]] = [:]
        var model: [String: [Float]] = [:]
        // A layer that was hidden has no meaningful presentation value: it snaps to its pose instead of springing.
        let wasHidden = Set(containers.filter { $0.value.isHidden }.keys)
        for (id, container) in containers {
            let live = container.presentation() ?? container
            before[id] = Self.components.map { Float((live.value(forKeyPath: $0.path) as? NSNumber)?.floatValue ?? 0) } + [live.opacity]
            model[id] = Self.components.map { Float((container.value(forKeyPath: $0.path) as? NSNumber)?.floatValue ?? 0) } + [container.opacity]
        }
        apply(target, animated: false)
        for part in asset.parts {
            guard let container = containers[part.id], !container.isHidden, !wasHidden.contains(part.id), let from = before[part.id] else { continue }
            // Lower legs and paws trail the upper leg, like ears, tail and scarf trail the body (overlapping action).
            let follower = ["ear-", "tail-2", "tail-3", "tail-4", "scarf-end-", "forearm-", "paw-"].contains { part.name.hasPrefix($0) }
            let gazePart = irisReach[part.id] != nil || pupilReach[part.id] != nil || glintIris[part.id] != nil
            for (i, component) in Self.components.enumerated() {
                let to = Float((container.value(forKeyPath: component.path) as? NSNumber)?.floatValue ?? 0)
                // Only a changed target springs; a running spring, and the additive breath on top of it, are left alone.
                guard let old = model[part.id]?[i], abs(old - to) > 0.0005 else { continue }
                guard abs(from[i] - to) > 0.0005 else { container.removeAnimation(forKey: component.key); continue }
                container.add(spring(from: from[i], to: to, period: period, follower: follower, saccade: gazePart, on: container, path: component.path), forKey: component.key)
            }
            guard opacity(of: part, in: pose) != nil, model[part.id]?[Self.components.count] != container.opacity else { continue }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = from[Self.components.count]
            fade.toValue = container.opacity
            fade.duration = 0.18
            container.add(fade, forKey: "pip.fade")
            if part.name.hasPrefix("heart-"), from[Self.components.count] < 0.5, container.opacity == 1 {
                let pop = CASpringAnimation(keyPath: "transform.scale")
                pop.fromValue = 0.2
                pop.toValue = 1
                pop.stiffness = 260; pop.damping = 9
                pop.duration = pop.settlingDuration
                container.add(pop, forKey: "pip.pop")
            }
        }
    }

    private static let components: [(path: String, key: String)] = [
        ("transform.rotation.z", "pip.rotation"), ("transform.translation.x", "pip.x"), ("transform.translation.y", "pip.y"),
        ("transform.scale.x", "pip.scaleX"), ("transform.scale.y", "pip.scaleY"),
    ]

    /// Natural frequency is chosen so the first overshoot lands near the key time, capped so short keys ease instead of snap.
    /// The body settles with little wobble; followers are 40% softer, bouncier and 60 ms late, which reads as follow-through.
    private func spring(from: Float, to: Float, period: TimeInterval, follower: Bool, saccade: Bool, on layer: CALayer, path: String) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: path)
        animation.fromValue = from
        animation.toValue = to
        var omega = saccade ? Self.saccadeOmega : min(max(3.76 / CGFloat(max(period, 0.05)), 14), 60)
        if follower { omega *= 0.6.squareRoot() }
        animation.mass = 1
        animation.stiffness = omega * omega
        animation.damping = 2 * (saccade ? 0.6 : follower ? 0.5 : 0.68) * omega
        animation.duration = animation.settlingDuration
        if follower {
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + 0.06
            animation.fillMode = .backwards
        }
        return animation
    }
}

private extension CATransform3D {
    func translated(x: CGFloat, y: CGFloat) -> CATransform3D {
        CATransform3DConcat(self, CATransform3DMakeTranslation(x, y, 0))
    }
}
