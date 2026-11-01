import CoreGraphics
import Foundation

/// One upright pose in the numbers an animator moves: hips, spine, head and wrists, not joint angles. All of them
/// blend, so `PipBake` can draw a curve through a gesture's beats and solve the limbs again on every frame, which
/// keeps feet planted and swings paws on arcs. Chain the helpers: `$0.stance(drop: 30).spine(bend: 4).nod(6)`.
struct PipBeat {
    /// A wrist around its shoulder. Blending these moves the paw on an arc, where blending x and y would cut a straight
    /// line. Authored positions stay below the shoulder or to its own side, so `angle` never crosses straight up.
    struct Wrist {
        var angle, length, paw: CGFloat

        init(_ side: PipPose.Side, x: CGFloat, y: CGFloat, paw: CGFloat) {
            let shoulder = PipUpright.arm(side).root
            angle = atan2(x - shoulder.x, y - shoulder.y)
            length = hypot(x - shoulder.x, y - shoulder.y)
            self.paw = paw
        }

        func point(from shoulder: CGPoint) -> CGPoint {
            CGPoint(x: shoulder.x + length * sin(angle), y: shoulder.y + length * cos(angle))
        }

        /// Which way the forearm points, in degrees, with the wrist here.
        func forearm(_ side: PipPose.Side) -> CGFloat {
            let chain = PipUpright.arm(side)
            let arm = chain.solve(to: point(from: chain.root), bend: side == .left ? 1 : -1)
            return (arm.upper + arm.lower) * 180 / .pi
        }
    }

    var at: TimeInterval = 0
    /// Still on the surface's resting body. The rise and the drop swap bodies between a grounded beat and the next.
    var grounded = false

    var drop: CGFloat = 0, spread: CGFloat = 0, lean: CGFloat = 0, sway: CGFloat = 0, lift: CGFloat = 0
    var squash: CGFloat = 0
    var bend: CGFloat = 0, stretch: CGFloat = 0
    var nod: CGFloat = 0, chewing: CGFloat = 0, headTurn: CGFloat = 1
    var ears: CGFloat = 0, tail: CGFloat = 0, scarf: CGFloat = 0
    var left = Wrist(.left, x: PipUpright.arm(.left).end.x, y: PipUpright.arm(.left).end.y, paw: 0)
    var right = Wrist(.right, x: PipUpright.arm(.right).end.x, y: PipUpright.arm(.right).end.y, paw: 0)
    /// The right ankle's move off the ground, for standing on one leg.
    var tuckX: CGFloat = 0, tuckY: CGFloat = 0, tuckFoot: CGFloat = 0
    var heartDrift: CGFloat = 0

    /// Held from this beat until the next one.
    var eyes = PipPose.EyeShape.open, mouth = PipPose.MouthShape.closedSmile
    var gazeX: CGFloat = 0, gazeY: CGFloat = 0
    var blush = false, hearts = 0, prop: PipPose.Prop?, bites = 0

    /// Follow-through `PipBake` works out from the motion above; never authored.
    var earLeft: CGFloat = 0, earRight: CGFloat = 0
    var tail1: CGFloat = 0, tail2: CGFloat = 0, tail3: CGFloat = 0, tail4: CGFloat = 0
    var scarfLeft: CGFloat = 0, scarfRight: CGFloat = 0
    var headSink: CGFloat = 0, fluff: CGFloat = 0

    private func with(_ change: (inout PipBeat) -> Void) -> PipBeat { var copy = self; change(&copy); return copy }

    func down() -> PipBeat { with { $0.grounded = true } }
    func stance(drop: CGFloat = 0, spread: CGFloat = 0, lean: CGFloat = 0, sway: CGFloat = 0, lift: CGFloat = 0) -> PipBeat {
        with { $0.drop = drop; $0.spread = spread; $0.lean = lean; $0.sway = sway; $0.lift = lift }
    }
    /// `bend` folds the upper body at the waist; `stretch` lengthens it, negative squashes.
    func spine(bend: CGFloat = 0, stretch: CGFloat = 0) -> PipBeat { with { $0.bend = bend; $0.stretch = stretch } }
    func squash(_ amount: CGFloat) -> PipBeat { with { $0.squash = amount } }
    func reach(_ side: PipPose.Side, x: CGFloat, y: CGFloat, paw: CGFloat) -> PipBeat {
        with { if side == .left { $0.left = Wrist(.left, x: x, y: y, paw: paw) } else { $0.right = Wrist(.right, x: x, y: y, paw: paw) } }
    }
    /// Moves the right ankle by (`x`, `y`) from where it stands, with that foot at `foot` degrees on screen.
    func tuck(x: CGFloat, y: CGFloat, foot: CGFloat) -> PipBeat { with { $0.tuckX = x; $0.tuckY = y; $0.tuckFoot = foot } }
    func nod(_ degrees: CGFloat) -> PipBeat { with { $0.nod = degrees } }
    func chew(_ amount: CGFloat) -> PipBeat { with { $0.chewing = amount; $0.mouth = amount > 0 ? .closedSmile : .smallOpen } }
    func turn(_ headTurn: CGFloat) -> PipBeat { with { $0.headTurn = headTurn } }
    func earPerk(_ degrees: CGFloat) -> PipBeat { with { $0.ears = degrees } }
    func tailWag(_ degrees: CGFloat) -> PipBeat { with { $0.tail = degrees } }
    func scarf(_ degrees: CGFloat) -> PipBeat { with { $0.scarf = degrees } }
    func eyes(_ shape: PipPose.EyeShape) -> PipBeat { with { $0.eyes = shape } }
    func mouth(_ shape: PipPose.MouthShape) -> PipBeat { with { $0.mouth = shape } }
    func look(_ x: CGFloat, _ y: CGFloat = 0) -> PipBeat { with { $0.gazeX = x; $0.gazeY = y } }
    func blushing() -> PipBeat { with { $0.blush = true } }
    func hearts(_ count: Int, drift: CGFloat = 0) -> PipBeat { with { $0.hearts = count; $0.heartDrift = drift } }
    func holding(_ prop: PipPose.Prop?, bites: Int = 0) -> PipBeat { with { $0.prop = prop; $0.bites = bites } }

    var pose: PipPose {
        var pose = PipPose.rest
        if grounded {
            pose = pose.squash(squash)
        } else {
            let leftWrist = left.point(from: PipUpright.arm(.left).root), rightWrist = right.point(from: PipUpright.arm(.right).root)
            pose = pose.stance(drop: drop, spread: spread, lean: lean, sway: sway, lift: lift, foot: lift * 0.5,
                               tuck: CGVector(dx: tuckX, dy: tuckY), tuckFoot: tuckFoot)
                .reach(.left, x: leftWrist.x, y: leftWrist.y, paw: left.paw)
                .reach(.right, x: rightWrist.x, y: rightWrist.y, paw: right.paw)
            pose.joints["torso@upright"] = PipPose.Joint(rotation: bend * .pi / 180, scale: CGSize(width: 1 - stretch * 0.6, height: 1 + stretch))
            pose.joints["chest-fluff@upright"] = PipPose.Joint(offset: CGPoint(x: 0, y: fluff))
            let shadow = 1 - lift / 350
            pose.joints["shadow"] = PipPose.Joint(offset: CGPoint(x: sway * 0.6, y: 0), scale: CGSize(width: shadow, height: shadow))
        }
        pose = pose.nod(nod).earPerk(earLeft, .left).earPerk(earRight, .right)
        pose.joints["head"]?.offset.y = headSink
        pose.joints["head"]?.scale = CGSize(width: 1 + chewing, height: 1 - chewing)
        for (n, angle) in [tail1, tail2, tail3, tail4].enumerated() {
            pose.joints["tail-\(n + 1)"] = PipPose.Joint(rotation: angle * .pi / 180)
        }
        pose.joints["scarf-end-l"] = PipPose.Joint(rotation: scarfLeft * .pi / 180)
        pose.joints["scarf-end-r"] = PipPose.Joint(rotation: scarfRight * .pi / 180)
        pose = pose.hearts(hearts, drift: heartDrift).holding(prop, bites: bites)
        pose.eyes = eyes
        pose.mouth = mouth
        pose.gaze = CGPoint(x: gazeX, y: gazeY)
        pose.blush = blush
        pose.headTurn = headTurn
        return pose
    }
}

/// Turns beats into 60 fps frames: a smooth curve through every beat, then follow-through. Each loose part is a damped
/// spring trailing whatever carries it, so the hips lead, the spine and head arrive a moment later, and ears, tail and
/// scarf drag behind and overshoot. Nothing here is hand-keyed; change the beats and the follow-through comes along.
enum PipBake {
    static let rate = 60.0

    /// Curves through the beats.
    private static var curved: [WritableKeyPath<PipBeat, CGFloat>] {
        [\.drop, \.spread, \.lean, \.sway, \.lift, \.squash, \.bend, \.stretch, \.nod, \.chewing, \.headTurn, \.ears, \.tail, \.scarf,
         \.left.angle, \.left.length, \.left.paw, \.right.angle, \.right.length, \.right.paw,
         \.tuckX, \.tuckY, \.tuckFoot, \.heartDrift]
    }
    /// What the follow-through writes, on top of `curved`: a one-shot lands exactly on its last beat through all of these.
    private static var settled: [WritableKeyPath<PipBeat, CGFloat>] {
        curved + [\.earLeft, \.earRight, \.tail1, \.tail2, \.tail3, \.tail4, \.scarfLeft, \.scarfRight, \.headSink, \.fluff, \.gazeX, \.gazeY]
    }

    static func frames(of beats: [PipBeat], loops: Bool) -> [PipBeat] {
        let beats = prepared(beats)
        let times = (0...Int((beats[beats.count - 1].at * rate).rounded())).map { Double($0) / rate }
        var frames = times.map { time in beats.last { $0.at <= time } ?? beats[0] }
        for path in curved {
            let values = curve(through: beats, path, at: times, loops: loops)
            for i in frames.indices { frames[i][keyPath: path] = values[i] }
        }

        func trail(_ drive: [CGFloat], _ omega: CGFloat, _ damping: CGFloat) -> [CGFloat] { spring(drive, omega: omega, damping: damping, loops: loops) }
        func put(_ path: WritableKeyPath<PipBeat, CGFloat>, _ values: [CGFloat]) { for i in frames.indices { frames[i][keyPath: path] = values[i] } }
        func read(_ path: KeyPath<PipBeat, CGFloat>) -> [CGFloat] { frames.map { $0[keyPath: path] } }
        func plus(_ a: [CGFloat], _ b: [CGFloat], by gain: CGFloat = 1) -> [CGFloat] { zip(a, b).map { $0 + $1 * gain } }

        // How far the mass of the body runs behind the hips: positive falling, negative rising; `swing` is the same sideways.
        let height = zip(read(\.lift), read(\.drop)).map(-)
        let sink = zip(trail(height, 15, 0.5), height).map(-)
        let side = plus(plus(read(\.sway), read(\.lean), by: 1.2), read(\.bend), by: 1.6)
        let swing = zip(trail(side, 11, 0.5), side).map(-)

        let bent = trail(read(\.bend), 28, 0.72)
        // The head keeps most of itself level while the spine tips under it.
        let level = plus(plus(read(\.nod), read(\.lean), by: -0.7), read(\.bend), by: -0.7)
        put(\.bend, bent)
        put(\.nod, trail(level, 19, 0.55))
        // Automatic squash and stretch: long on the way up, short as the body lands.
        // A breath on top means no hold is ever dead still; a whole number of them, so a loop closes.
        let length = beats[beats.count - 1].at, breaths = max(1, (length / 1.4).rounded())
        let breath = times.map { 0.006 * sin(2 * .pi * CGFloat($0 / length * breaths)) }
        put(\.stretch, plus(plus(read(\.stretch), sink.map { max(-0.09, min(0.11, -$0 * 0.0055)) }), breath))
        put(\.headSink, sink.map { max(-9, min(9, $0 * 0.3)) })
        put(\.fluff, trail(sink, 13, 0.3).map { max(-7, min(7, $0 * 0.35)) })

        let earDrive = plus(plus(read(\.ears), sink, by: 1.5), swing, by: 0.7)
        put(\.earLeft, trail(earDrive, 16, 0.3))
        put(\.earRight, trail(earDrive, 13, 0.28))
        // The wave runs down the tail: each segment follows the one before it.
        let tail1 = trail(plus(plus(read(\.tail), swing, by: 1.4), sink, by: -0.4).map { $0 / 4 }, 10, 0.42)
        let tail2 = trail(tail1, 12, 0.42), tail3 = trail(tail2, 12, 0.42), tail4 = trail(tail3, 12, 0.42)
        put(\.tail1, tail1); put(\.tail2, tail2); put(\.tail3, tail3); put(\.tail4, tail4)
        let scarfDrive = plus(plus(read(\.scarf), swing, by: 0.9), sink, by: 0.5)
        put(\.scarfLeft, trail(scarfDrive, 12, 0.28))
        put(\.scarfRight, trail(scarfDrive, 10, 0.26))

        for (angle, length, paw) in [(\PipBeat.left.angle, \PipBeat.left.length, \PipBeat.left.paw), (\.right.angle, \.right.length, \.right.paw)] {
            put(angle, trail(read(angle), 25, 0.6))
            put(length, trail(read(length), 34, 0.75))
            put(paw, trail(read(paw), 17, 0.5))
        }
        // Eyes jump to a new look, they do not drift.
        put(\.gazeX, trail(read(\.gazeX), 55, 0.7))
        put(\.gazeY, trail(read(\.gazeY), 55, 0.7))

        if !loops { landOn(beats[beats.count - 1], &frames) }
        for i in frames.indices {
            frames[i].left.paw += frames[i].left.forearm(.left)
            frames[i].right.paw += frames[i].right.forearm(.right)
        }
        return frames
    }

    /// Starts a joint's track from `now` and joins the authored motion within 0.2 s, so a gesture never pops on arrival.
    static func easedIn(_ track: [CGFloat], from now: CGFloat) -> [CGFloat] {
        let span = min(Int(rate * 0.2), track.count - 1), gap = now - track[0]
        return track.enumerated().map { i, value in
            guard i < span else { return value }
            let t = CGFloat(i) / CGFloat(span)
            return value + gap * (1 - t * t * (3 - 2 * t))
        }
    }

    private static func prepared(_ beats: [PipBeat]) -> [PipBeat] {
        var beats = beats
        for i in beats.indices {
            if !beats[i].grounded { beats[i].nod += PipUpright.level(turn: beats[i].headTurn) }
            // Paws blend against their forearms, the short way: on screen a paw would whirl as a swinging arm carried it.
            beats[i].left.paw = nearest(beats[i].left.paw - beats[i].left.forearm(.left))
            beats[i].right.paw = nearest(beats[i].right.paw - beats[i].right.forearm(.right))
            guard i > 0 else { continue }
            beats[i].left.paw = beats[i - 1].left.paw + nearest(beats[i].left.paw - beats[i - 1].left.paw)
            beats[i].right.paw = beats[i - 1].right.paw + nearest(beats[i].right.paw - beats[i - 1].right.paw)
        }
        return beats
    }

    private static func nearest(_ degrees: CGFloat) -> CGFloat { PipUpright.wrapped(degrees * .pi / 180) * 180 / .pi }

    /// Eases the last moments onto the final beat, so a spring still ringing never pops when the gesture hands over.
    private static func landOn(_ last: PipBeat, _ frames: inout [PipBeat]) {
        let span = min(Int(rate * 0.2), frames.count - 1)
        guard span > 0 else { return }
        for offset in 0...span {
            let t = CGFloat(offset) / CGFloat(span), ease = t * t * (3 - 2 * t)
            let i = frames.count - 1 - span + offset
            for path in settled { frames[i][keyPath: path] += (last[keyPath: path] - frames[i][keyPath: path]) * ease }
        }
    }

    /// A monotone cubic: passes through every beat, moves smoothly between them, and never overshoots a hold.
    private static func curve(through beats: [PipBeat], _ path: KeyPath<PipBeat, CGFloat>, at times: [Double], loops: Bool) -> [CGFloat] {
        let values = beats.map { $0[keyPath: path] }
        guard beats.count > 1 else { return times.map { _ in values[0] } }
        let slopes = beats.indices.dropLast().map { (values[$0 + 1] - values[$0]) / CGFloat(max(beats[$0 + 1].at - beats[$0].at, 0.001)) }
        func tangent(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a * b <= 0 ? 0 : 2 * a * b / (a + b) }
        var tangents = [CGFloat](repeating: 0, count: beats.count)
        for i in beats.indices.dropFirst().dropLast() { tangents[i] = tangent(slopes[i - 1], slopes[i]) }
        if loops {
            tangents[0] = tangent(slopes[slopes.count - 1], slopes[0])
            tangents[beats.count - 1] = tangents[0]
        }
        var segment = 0
        return times.map { time in
            while segment < beats.count - 2 && time >= beats[segment + 1].at { segment += 1 }
            let span = CGFloat(max(beats[segment + 1].at - beats[segment].at, 0.001))
            let u = max(0, min(1, CGFloat(time - beats[segment].at) / span)), uu = u * u, uuu = uu * u
            return (2 * uuu - 3 * uu + 1) * values[segment] + (uuu - 2 * uu + u) * span * tangents[segment]
                + (3 * uu - 2 * uuu) * values[segment + 1] + (uuu - uu) * span * tangents[segment + 1]
        }
    }

    /// A damped spring chasing `drive`. A loop's first and last frames are the same moment, so it integrates one period
    /// three times over and closes exactly: the motion carries through the seam with no pop.
    private static func spring(_ drive: [CGFloat], omega: CGFloat, damping: CGFloat, loops: Bool) -> [CGFloat] {
        var position = drive[0], velocity: CGFloat = 0
        var out = drive
        let step = CGFloat(1 / rate), period = loops ? drive.count - 1 : drive.count
        for pass in 0..<(loops ? 3 : 1) {
            for i in 0..<period {
                velocity += (omega * omega * (drive[i] - position) - 2 * damping * omega * velocity) * step
                position += velocity * step
                if pass == (loops ? 2 : 0) { out[i] = position }
            }
        }
        if loops { out[drive.count - 1] = out[0] }
        return out
    }
}
