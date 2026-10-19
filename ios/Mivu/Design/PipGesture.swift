import CoreGraphics
import Foundation

/// App moments Pip reacts to. `PipGestureLibrary.gesture(for:)` is the only place that maps them to gestures.
enum PipMoment: Hashable {
    case greeting(hour: Int), welcomeBack, attentive, submitted, thinking, saved, reviewed, recovery
    case firstMealToday, dayComplete, curious, tapped(level: Int), patted, earTwitch
}

/// Timed poses. Each key is the full pose Pip should *arrive at* by `at` seconds; the previous key's time is when
/// its spring is launched. The last key of a one-shot is `.rest`; a loop repeats from its first key.
struct PipGesture {
    let name: String
    let keys: [(at: TimeInterval, pose: PipPose)]
    var loops = false
    var duration: TimeInterval { keys.last!.at }

    init(name: String, keys: [(at: TimeInterval, pose: PipPose)], loops: Bool = false) {
        self.name = name
        self.keys = keys
        self.loops = loops
    }

    /// `PipGesture("saved") { $0.at(0.07) { $0.nod(6) }; $0.settle(at: 0.45) }`
    init(_ name: String, loops: Bool = false, _ build: (inout Builder) -> Void) {
        var builder = Builder()
        build(&builder)
        self.init(name: name, keys: builder.keys, loops: loops)
    }

    struct Builder {
        fileprivate(set) var keys: [(at: TimeInterval, pose: PipPose)] = []
        /// A key built from `.rest` by chaining the pose helpers.
        mutating func at(_ time: TimeInterval, _ pose: (PipPose) -> PipPose) { keys.append((time, pose(.rest))) }
        mutating func settle(at time: TimeInterval) { keys.append((time, .rest)) }
    }

    static func `for`(_ moment: PipMoment) -> PipGesture { PipGestureLibrary.gesture(for: moment) }
    static func loopFor(_ moment: PipMoment) -> PipGesture? { PipGestureLibrary.loop(for: moment) }
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
    /// Lifts a paw: negative `degrees` swings the arm forward from the shoulder, negative `elbow` folds the forearm up.
    func pawUp(_ side: Side = .both, _ degrees: CGFloat = -40, elbow: CGFloat = -60) -> PipPose {
        edited(sides(side).map { "arm-\($0)" }) { $0.rotation = Self.radians(degrees) }
            .edited(sides(side).map { "forearm-\($0)" }) { $0.rotation = Self.radians(elbow) }
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
}
