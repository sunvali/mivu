import CoreGraphics
import Foundation

/// App moments Pip reacts to. `PipGestureLibrary.gesture(for:)` is the only place that maps them to gestures.
enum PipMoment: Hashable {
    case greeting(hour: Int), welcomeBack, attentive, submitted, thinking, saved, reviewed, recovery
    case firstMealToday, dayComplete, curious, tapped(level: Int), patted, earTwitch
    /// Progress: leaning in over the chart; `cheer` on a good period, a calm smile otherwise.
    case presenting(cheer: Bool)
    /// Progress one-shots: opening the tab (`cheer` on an on-track period), switching range, and taps on Pip (`level` picks the next silly one).
    case progressEntrance(cheer: Bool), progressRange, progressTap(level: Int)
}

/// Timed poses. Each key is the full pose Pip should *arrive at* by `at` seconds; the previous key's time is when
/// its spring is launched. The last key of a one-shot is `.rest`; a loop repeats from its first key.
struct PipGesture {
    let name: String
    let keys: [(at: TimeInterval, pose: PipPose)]
    var loops = false
    /// The body set Pip is in afterwards, for the few gestures that change it on purpose (`curl-up`, `wake`).
    var endSet: PipPose.BodySet?
    /// The body set the gesture is authored on, when that is not the resting one; play it between `riseUp` and `dropDown`.
    var stance: PipPose.BodySet?
    /// Upright gestures play these as one continuous curve (`PipBake`) instead of a spring per key.
    var beats: [PipBeat] = []
    var duration: TimeInterval { keys.last?.at ?? 0 }

    init(name: String, keys: [(at: TimeInterval, pose: PipPose)], loops: Bool = false, endSet: PipPose.BodySet? = nil, stance: PipPose.BodySet? = nil) {
        self.name = name
        self.keys = keys
        self.loops = loops
        self.endSet = endSet
        self.stance = stance
    }

    /// `PipGesture("saved") { $0.at(0.07) { $0.nod(6) }; $0.settle(at: 0.45) }`
    init(_ name: String, loops: Bool = false, _ build: (inout Builder) -> Void) {
        var builder = Builder()
        build(&builder)
        self.init(name: name, keys: builder.keys, loops: loops, endSet: builder.endSet)
    }

    /// `PipGesture(beats: "workout-squat", loops: true) { $0.at(0); $0.at(0.6) { $0.stance(drop: 30) }; $0.at(1.2) }`
    init(beats name: String, loops: Bool = false, _ build: (inout BeatBuilder) -> Void) {
        var builder = BeatBuilder()
        build(&builder)
        self.init(name: name, keys: builder.keys, loops: loops, endSet: builder.endSet, stance: .upright)
        beats = builder.beats
    }

    struct Builder {
        fileprivate(set) var keys: [(at: TimeInterval, pose: PipPose)] = []
        /// A key built from `.rest` by chaining the pose helpers.
        mutating func at(_ time: TimeInterval, _ pose: (PipPose) -> PipPose) { keys.append((time, pose(.rest))) }
        mutating func settle(at time: TimeInterval) { keys.append((time, .rest)) }
        fileprivate(set) var endSet: PipPose.BodySet?
        /// Ends in another body set (the final key changes it), e.g. Pip curling up.
        mutating func end(in set: PipPose.BodySet, at time: TimeInterval, _ pose: (PipPose) -> PipPose = { $0 }) {
            var end = pose(.rest)
            end.set = set
            keys.append((time, end))
            endSet = set
        }
    }

    struct BeatBuilder {
        fileprivate(set) var beats: [PipBeat] = []
        fileprivate(set) var keys: [(at: TimeInterval, pose: PipPose)] = []
        fileprivate(set) var endSet: PipPose.BodySet?

        mutating func at(_ time: TimeInterval, _ beat: (PipBeat) -> PipBeat = { $0 }) {
            var next = beat(PipBeat())
            next.at = time
            beats.append(next)
            keys.append((time, next.pose))
        }
        mutating func settle(at time: TimeInterval) {
            at(time)
            keys[keys.count - 1].pose = .rest
        }
        /// Ends on another body set: upright after the rise, the surface's resting one after the drop.
        mutating func end(in set: PipPose.BodySet, at time: TimeInterval) {
            at(time) { set == .upright ? $0 : $0.down() }
            keys[keys.count - 1].pose = .rest
            keys[keys.count - 1].pose.set = set
            endSet = set
        }
    }
}

/// The upright set's limbs in artboard points. `uprightLimbsMatchTheRig` keeps them equal to `pip.svg`.
enum PipUpright {
    struct Chain {
        let root, joint, end: CGPoint
        var points: [CGPoint] { [root, joint, end] }

        /// The two rotations that put `end` on `target`; `bend` picks which way the middle joint folds.
        /// Out-of-reach targets stop at full extension.
        func solve(to target: CGPoint, bend: CGFloat) -> (upper: CGFloat, lower: CGFloat) {
            let a = hypot(joint.x - root.x, joint.y - root.y), b = hypot(end.x - joint.x, end.y - joint.y)
            let d = max(abs(a - b) + 0.1, min(a + b - 0.1, hypot(target.x - root.x, target.y - root.y)))
            let direction = atan2(target.y - root.y, target.x - root.x) + bend * acos((a * a + d * d - b * b) / (2 * a * d))
            let middle = CGPoint(x: root.x + a * cos(direction), y: root.y + a * sin(direction))
            let upper = wrapped(direction - atan2(joint.y - root.y, joint.x - root.x))
            let lower = wrapped(atan2(target.y - middle.y, target.x - middle.x) - atan2(end.y - joint.y, end.x - joint.x) - upper)
            return (upper, lower)
        }
    }

    static let body = CGPoint(x: 316, y: 400)
    static let waist = CGPoint(x: 316, y: 352)
    /// The head views are drawn rolled toward the snout for the four-legged body; this many degrees sets them level on a
    /// straight spine. The turned view is rolled most.
    static func level(turn: CGFloat) -> CGFloat { 5.5 + 3.5 * max(0, min(1, turn)) }
    static func arm(_ side: PipPose.Side) -> Chain {
        side == .left
            ? Chain(root: CGPoint(x: 274, y: 292), joint: CGPoint(x: 258, y: 340), end: CGPoint(x: 260, y: 384))
            : Chain(root: CGPoint(x: 358, y: 292), joint: CGPoint(x: 374, y: 340), end: CGPoint(x: 372, y: 384))
    }
    static func leg(_ side: PipPose.Side) -> Chain {
        side == .left
            ? Chain(root: CGPoint(x: 290, y: 394), joint: CGPoint(x: 282, y: 428), end: CGPoint(x: 280, y: 458))
            : Chain(root: CGPoint(x: 342, y: 394), joint: CGPoint(x: 350, y: 428), end: CGPoint(x: 352, y: 458))
    }

    /// Keeps rotations short, so a spring never swings the long way round.
    static func wrapped(_ angle: CGFloat) -> CGFloat { atan2(sin(angle), cos(angle)) }
}

/// Named joint helpers. Angles are degrees; +nod is down, +tilt leans toward the snout, +earPerk lifts the tip.
/// Each returns a changed copy, so they chain: `$0.nod(6).eyes(.closedHappy).hearts(1)`.
extension PipPose {
    enum Side { case left, right, both }

    private func sides(_ side: Side) -> [String] { side == .left ? ["l"] : side == .right ? ["r"] : ["l", "r"] }

    private func edited(_ names: [String], _ change: (inout Joint) -> Void) -> PipPose {
        var copy = self
        for name in names { change(&copy.joints[name, default: Joint()]) }
        return copy
    }

    private static func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

    func nod(_ degrees: CGFloat) -> PipPose { edited(["head"]) { $0.rotation = Self.radians(degrees) } }
    func tilt(_ degrees: CGFloat) -> PipPose { edited(["body"]) { $0.rotation = Self.radians(degrees) } }
    func earPerk(_ degrees: CGFloat, _ side: Side = .both) -> PipPose {
        edited(sides(side).map { "ear-\($0)" }) { $0.rotation = Self.radians(degrees) }
    }
    /// Lifts a paw: negative `degrees` swings the leg forward from the shoulder, `elbow` is how far the paw comes up.
    /// Standing, the lower leg hangs from the raised elbow and the paw curls under; the far (left) leg swings a third as
    /// much so it never lies across the chest. Seated (Coach, peeking over the composer) the paw rises off the bar.
    func pawUp(_ side: Side = .both, _ degrees: CGFloat = -40, elbow: CGFloat = -60) -> PipPose {
        var copy = self
        let lift = abs(elbow)
        for s in sides(side) {
            let reach: CGFloat = s == "l" ? 0.3 : 1
            copy = copy.edited(["arm-\(s)"]) { $0.rotation = Self.radians(max(degrees, -65) * reach) }
                .edited(["forearm-\(s)"]) { $0.rotation = Self.radians(lift * 0.85) }
                .edited(["paw-\(s)"]) { $0.rotation = Self.radians(lift * 0.25) }
                .edited(["arm-\(s)@seated", "forearm-\(s)@seated"]) { $0.rotation = 0 }
                .edited(["paw-\(s)@seated"]) { $0.offset.y = -lift * 0.35; $0.rotation = Self.radians(-lift * 0.15) }
        }
        // Lifting one paw shifts the weight back a touch; added, so a gesture's own tilt still applies.
        if side != .both { copy.joints["body", default: Joint()].rotation -= Self.radians(1.2) }
        return copy
    }
    func hop(_ height: CGFloat) -> PipPose {
        edited(["body"]) { $0.offset.y = -height }.edited(["shadow"]) { $0.scale = CGSize(width: 1 - height / 150, height: 1 - height / 150) }
    }
    func squash(_ amount: CGFloat) -> PipPose {
        edited(["body"]) { $0.scale = CGSize(width: 1 + amount, height: 1 - amount) }
    }
    /// The tip swings `degrees`, shared evenly by the four tail segments (each bends relative to the last).
    func tailWag(_ degrees: CGFloat) -> PipPose {
        edited(["tail-1", "tail-2", "tail-3", "tail-4"]) { $0.rotation = Self.radians(degrees / 4) }
    }
    func scarf(_ degrees: CGFloat) -> PipPose { edited(["scarf-end-l", "scarf-end-r"]) { $0.rotation = Self.radians(degrees) } }
    func eyes(_ shape: EyeShape) -> PipPose { var copy = self; copy.eyes = shape; return copy }
    func mouth(_ shape: MouthShape) -> PipPose { var copy = self; copy.mouth = shape; return copy }
    func look(_ x: CGFloat, _ y: CGFloat = 0) -> PipPose { var copy = self; copy.gaze = CGPoint(x: x, y: y); return copy }
    func turn(_ headTurn: CGFloat) -> PipPose { var copy = self; copy.headTurn = headTurn; return copy }
    func blushing() -> PipPose { var copy = self; copy.blush = true; return copy }
    /// Shows `count` hearts that have drifted `drift` points upward.
    func hearts(_ count: Int, drift: CGFloat = 0) -> PipPose {
        var copy = self
        copy.hearts = count
        for n in 1...max(count, 1) where count > 0 { copy.joints["heart-\(n)", default: Joint()].offset.y = -drift }
        return copy
    }

    // MARK: Upright body

    /// Puts the wrist on (`x`, `y`) in the torso's own artboard space, elbow outward. `paw` is the paw's angle in that
    /// space in degrees: 0 hangs, 180 points up (the pose food is drawn for); nil leaves it following the forearm.
    func reach(_ side: Side, x: CGFloat, y: CGFloat, paw: CGFloat? = nil) -> PipPose {
        let s = side == .left ? "l" : "r"
        let arm = PipUpright.arm(side).solve(to: CGPoint(x: x, y: y), bend: side == .left ? 1 : -1)
        var copy = edited(["arm-\(s)"]) { $0.rotation = arm.upper }.edited(["forearm-\(s)"]) { $0.rotation = arm.lower }
        if let paw { copy = copy.edited(["paw-\(s)"]) { $0.rotation = PipUpright.wrapped(Self.radians(paw) - arm.upper - arm.lower) } }
        return copy
    }

    /// Stands the upright body with both feet flat on the ground while it sinks `drop`, spreads each foot `spread`,
    /// leans `lean` degrees at the hips and shifts `sway`. `lift` then raises the whole of Pip, feet included, and `foot`
    /// splays the toes that far off flat. `tuck` moves the right ankle off the ground, its foot at `tuckFoot` on screen.
    /// A wide `spread` needs some `drop`: the legs are about 65 points long.
    func stance(drop: CGFloat = 0, spread: CGFloat = 0, lean: CGFloat = 0, sway: CGFloat = 0, lift: CGFloat = 0,
                foot: CGFloat = 0, tuck: CGVector = .zero, tuckFoot: CGFloat = 0) -> PipPose {
        var copy = edited(["body"]) { $0.offset = CGPoint(x: sway, y: drop - lift); $0.rotation = Self.radians(lean) }
        for side in [Side.left, .right] {
            let chain = PipUpright.leg(side)
            let raised = side == .right ? tuck : .zero
            // The ground stays still, so in the body's own space the ankle counter-moves.
            let target = CGPoint(x: chain.end.x + (side == .left ? -spread : spread) + raised.dx - sway - PipUpright.body.x,
                                 y: chain.end.y + raised.dy - drop - PipUpright.body.y)
            let back = -Self.radians(lean)
            copy = copy.leg(side, to: CGPoint(x: PipUpright.body.x + target.x * cos(back) - target.y * sin(back),
                                              y: PipUpright.body.y + target.x * sin(back) + target.y * cos(back)),
                            foot: (side == .left ? -foot : foot) + (side == .right ? tuckFoot : 0))
        }
        return copy
    }

    private func leg(_ side: Side, to ankle: CGPoint, foot: CGFloat) -> PipPose {
        let s = side == .left ? "l" : "r"
        let lean = joints["body"]?.rotation ?? 0
        let leg = PipUpright.leg(side).solve(to: ankle, bend: side == .left ? 1 : -1)
        return edited(["leg-\(s)"]) { $0.rotation = leg.upper }
            .edited(["shin-\(s)@upright"]) { $0.rotation = leg.lower }
            .edited(["foot-\(s)"]) { $0.rotation = PipUpright.wrapped(Self.radians(foot) - lean - leg.upper - leg.lower) }
    }

    func holding(_ prop: Prop?, bites: Int = 0) -> PipPose {
        var copy = self
        copy.prop = prop
        copy.bites = bites
        return copy
    }
}
