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
    var duration: TimeInterval { keys.last?.at ?? 0 }

    init(name: String, keys: [(at: TimeInterval, pose: PipPose)], loops: Bool = false, endSet: PipPose.BodySet? = nil) {
        self.name = name
        self.keys = keys
        self.loops = loops
        self.endSet = endSet
    }

    /// `PipGesture("saved") { $0.at(0.07) { $0.nod(6) }; $0.settle(at: 0.45) }`
    init(_ name: String, loops: Bool = false, _ build: (inout Builder) -> Void) {
        var builder = Builder()
        build(&builder)
        self.init(name: name, keys: builder.keys, loops: loops, endSet: builder.endSet)
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
    func holdingCard() -> PipPose { var copy = self; copy.card = true; return copy }
    /// Shows `count` hearts that have drifted `drift` points upward.
    func hearts(_ count: Int, drift: CGFloat = 0) -> PipPose {
        var copy = self
        copy.hearts = count
        for n in 1...max(count, 1) where count > 0 { copy.joints["heart-\(n)", default: Joint()].offset.y = -drift }
        return copy
    }
}
