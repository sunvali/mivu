import CoreGraphics
import Testing
@testable import Mivu

@Suite struct PipGestureTests {
    private static let moments: [PipMoment] = [
        .greeting(hour: 8), .greeting(hour: 14), .greeting(hour: 22), .welcomeBack, .attentive, .submitted, .thinking,
        .saved, .reviewed, .recovery, .firstMealToday, .dayComplete, .curious,
        .tapped(level: 0), .tapped(level: 1), .tapped(level: 2), .tapped(level: 3), .tapped(level: 4),
        .patted, .earTwitch, .presenting(cheer: true), .presenting(cheer: false),
        .progressEntrance(cheer: true), .progressEntrance(cheer: false), .progressRange,
        .progressTap(level: 0), .progressTap(level: 1), .progressTap(level: 2), .progressTap(level: 3), .progressTap(level: 4), .progressTap(level: 5),
        .workoutSaved(activity: "strength"), .workoutSaved(activity: "run"), .workoutSaved(activity: "yoga"), .workoutSaved(activity: "stretching"),
        .workoutDone(hard: true), .workoutDone(hard: false),
    ]

    @Test func everyLibraryGestureEndsAtRestWithinTwoSeconds() {
        let all = PipGestureLibrary.all
        #expect(Set(all.map(\.name)).count == all.count)
        for gesture in all { #expect(!gesture.keys.isEmpty, "\(gesture.name) has no keys") }
        for gesture in all where !gesture.loops && !gesture.keys.isEmpty {
            #expect(gesture.keys.last?.pose == Self.expectedEnd(of: gesture), "\(gesture.name) must end at rest")
            #expect(gesture.duration <= 2.0, "\(gesture.name) lasts \(gesture.duration)")
            #expect(gesture.keys.map(\.at) == gesture.keys.map(\.at).sorted(), "\(gesture.name) keys out of order")
        }
    }

    /// Named exception: only these change the body set on purpose, so only they end somewhere other than standing rest.
    private static let setChangers: Set<String> = ["curl-up", "wake", "rise-up", "drop-down"]

    private static func expectedEnd(of gesture: PipGesture) -> PipPose {
        var end = PipPose.rest
        end.set = gesture.endSet ?? .standing
        if gesture.name == "curl-up" || gesture.name == "curled-ear-flick" { end.eyes = .closedSleepy }
        return end
    }

    @Test func onlyCurlUpAndWakeChangeTheBodySet() {
        #expect(Set(PipGestureLibrary.all.filter { $0.endSet != nil }.map(\.name)) == Self.setChangers)
        #expect(PipGestureLibrary.wake.endSet == .standing && PipGestureLibrary.gesture(forIdle: .curlUp)?.endSet == .curled)
        #expect(PipGestureLibrary.riseUp.endSet == .upright && PipGestureLibrary.dropDown(endingIn: .seated).endSet == .seated)
        for gesture in PipGestureLibrary.all where !Self.setChangers.contains(gesture.name) {
            #expect(gesture.keys.allSatisfy { $0.pose.set == .standing }, "\(gesture.name)")
        }
    }

    @Test func idleBeatsMapToSmallGestures() {
        let beats: [PipIdleScheduler.Beat] = [.earFlick, .weightShift, .yawn, .stretch, .hugTail, .curlUp]
        for beat in beats { #expect(PipGestureLibrary.gesture(forIdle: beat).map { PipGestureLibrary.all.map(\.name).contains($0.name) } == true, "\(beat)") }
        #expect(PipGestureLibrary.gesture(forIdle: .yawn)?.keys.contains { $0.pose.mouth == .yawn } == true)
        #expect(PipGestureLibrary.gesture(forIdle: .earFlick, curled: true)?.name == "curled-ear-flick")
        #expect(PipGestureLibrary.gesture(forIdle: .earFlick, curled: true)?.keys.allSatisfy { $0.pose.eyes == .closedSleepy } == true)
        for beat in [PipIdleScheduler.Beat.blink, .doubleBlink, .glance(.zero)] { #expect(PipGestureLibrary.gesture(forIdle: beat) == nil) }
    }

    @Test func everyMomentMapsToALibraryGesture() {
        let names = Set(PipGestureLibrary.all.map(\.name))
        for moment in Self.moments {
            #expect(names.contains(PipGestureLibrary.gesture(for: moment).name), "\(moment)")
        }
        #expect(PipGestureLibrary.loop(for: .thinking)?.loops == true)
        #expect(PipGestureLibrary.loop(for: .attentive)?.loops == true)
        #expect(PipGestureLibrary.loop(for: .saved) == nil)
    }

    /// Progress keeps Pip by the chart sign, eyes down on the bars, a paw on the sign; never a sad face.
    @MainActor @Test func presentingHoldsAKindLookAtTheChart() throws {
        for cheer in [true, false] {
            let loop = try #require(PipGestureLibrary.loop(for: .presenting(cheer: cheer)))
            let held = try #require(loop.keys.first?.pose)
            #expect(held.gaze.y > 0.5, "Looks down at the chart")
            #expect(held.mouth != .concerned)
            #expect(CompanionRuntime.moment(for: cheer ? .presentingCheer : .presentingCalm, tapLevel: 0, hour: 12) == .presenting(cheer: cheer))
        }
    }

    /// Entrance and range switch are one-shots that settle by the sign; the cheer is a happy face, never hearts or points.
    @MainActor @Test func progressMomentsShowTheChartKindly() throws {
        let cases: [(CompanionPose, PipMoment)] = [(.progressEntrance, .progressEntrance(cheer: false)), (.progressEntranceCheer, .progressEntrance(cheer: true)),
                                                   (.progressRange, .progressRange)]
        for (pose, moment) in cases {
            #expect(CompanionRuntime.moment(for: pose, tapLevel: 0, hour: 12) == moment)
            let gesture = PipGestureLibrary.gesture(for: moment)
            #expect(!gesture.loops && gesture.keys.last?.pose == .rest, "\(moment) is a one-shot")
            #expect(gesture.keys.allSatisfy { $0.pose.hearts == 0 && $0.pose.mouth != .concerned }, "\(moment)")
        }
        #expect(PipGestureLibrary.gesture(for: .progressEntrance(cheer: true)).keys.contains { $0.pose.eyes == .closedHappy })
    }

    /// The chart card rides the upper arm, drawn for the held elbow, so no Progress key may bend the forearm or paw away from it.
    @MainActor @Test func progressMomentsKeepTheCardElbowStill() {
        let moments: [PipMoment] = [.presenting(cheer: true), .presenting(cheer: false), .progressEntrance(cheer: true),
                                    .progressEntrance(cheer: false), .progressRange] + (0...5).map { .progressTap(level: $0) }
        for moment in moments {
            for key in PipGestureLibrary.gesture(for: moment).keys {
                for part in ["forearm-r", "paw-r"] {
                    let joint = key.pose.joints[part]
                    #expect(joint == nil || joint == PipGestureLibrary.progressHeldArm[part], "\(moment) \(key.at) \(part)")
                }
            }
        }
    }

    /// Each tap on Progress Pip plays the next of six silly one-shots, then wraps around.
    @MainActor @Test func tapsCycleThroughFunnyGestures() {
        let names = (0..<6).map { PipGestureLibrary.gesture(for: .progressTap(level: $0)).name }
        #expect(Set(names).count == 6, "\(names)")
        #expect(PipGestureLibrary.gesture(for: .progressTap(level: 6)).name == names[0])
        #expect(CompanionRuntime.moment(for: .progressTap, tapLevel: 3, hour: 12) == .progressTap(level: 3))
        for level in 0..<6 {
            let gesture = PipGestureLibrary.gesture(for: .progressTap(level: level))
            #expect(!gesture.loops && gesture.keys.last?.pose == .rest && gesture.duration <= MivuMotion.progressTap, "\(gesture.name)")
        }
    }

    @Test func spokenTimingsMatchSpec() {
        func gesture(_ moment: PipMoment) -> PipGesture { PipGestureLibrary.gesture(for: moment) }
        #expect(abs(gesture(.greeting(hour: 14)).duration - 0.70) <= 0.01)
        #expect(abs(gesture(.saved).duration - 0.45) <= 0.01)
        #expect(abs(gesture(.reviewed).duration - 0.65) <= 0.01)
        #expect(gesture(.submitted).keys[0].at <= 0.1)
        #expect(gesture(.submitted).duration <= 0.8)
        #expect(abs(PipGestureLibrary.loop(for: .thinking)!.duration - 1.4) <= 0.01)
    }

    @Test func squashAndFeetStayInCaps() {
        for gesture in PipGestureLibrary.all {
            for key in gesture.keys {
                for (name, joint) in key.pose.joints {
                    #expect((0.9...1.1).contains(joint.scale.width) && (0.9...1.1).contains(joint.scale.height), "\(gesture.name) \(name)")
                    if name.hasPrefix("foot-") { #expect(joint.offset.y <= 0, "\(gesture.name) \(name) below ground") }
                }
            }
            for name in gesture.keys.last?.pose.joints.keys.filter({ $0.hasPrefix("foot-") }) ?? [] {
                #expect(gesture.keys.last?.pose.joints[name]?.offset.y == 0)
            }
        }
    }

    /// Eating and workout gestures play on the upright body; the debug preview and any later trainer rise into it first.
    @Test func eatingAndWorkoutsPlayUpright() {
        let names = ["eat-apple", "eat-bowl", "eat-yum", "sip-water", "workout-squat", "workout-jumping-jack", "workout-side-bend",
                     "workout-breather", "stretch-reach", "yoga-tree"]
        for name in names { #expect(PipGestureLibrary.named(name).stance == .upright, "\(name)") }
        for name in ["workout-squat", "workout-jumping-jack", "workout-side-bend"] { #expect(PipGestureLibrary.named(name).loops, "\(name)") }
        #expect(PipGestureLibrary.named("eat-apple").keys.contains { $0.pose.prop == .apple && $0.pose.bites == 2 })
        for gesture in PipGestureLibrary.all where gesture.stance == nil { #expect(gesture.keys.allSatisfy { $0.pose.prop == nil }, "\(gesture.name)") }
    }

    @Test func uprightLimbsMatchTheRig() throws {
        let asset = try PipRigAsset.load(PipRigAssetTests.bundledData())
        func pivot(_ name: String) throws -> CGPoint {
            let part = try #require(asset.parts.first { $0.id == "\(name)@upright" })
            return CGPoint(x: part.pivot[0], y: part.pivot[1])
        }
        #expect(try pivot("body") == PipUpright.body && pivot("torso") == PipUpright.waist)
        for side in [PipPose.Side.left, .right] {
            let s = side == .left ? "l" : "r"
            #expect(try [pivot("arm-\(s)"), pivot("forearm-\(s)"), pivot("paw-\(s)")] == PipUpright.arm(side).points)
            #expect(try [pivot("leg-\(s)"), pivot("shin-\(s)"), pivot("foot-\(s)")] == PipUpright.leg(side).points)
        }
    }

    private func turned(_ point: CGPoint, by angle: CGFloat) -> CGPoint {
        CGPoint(x: point.x * cos(angle) - point.y * sin(angle), y: point.x * sin(angle) + point.y * cos(angle))
    }

    /// Where the limb's end lands in the body's own space, from the joints a pose set.
    private func end(of chain: PipUpright.Chain, _ upper: CGFloat, _ lower: CGFloat) -> CGPoint {
        let knee = turned(CGPoint(x: chain.joint.x - chain.root.x, y: chain.joint.y - chain.root.y), by: upper)
        let ankle = turned(CGPoint(x: chain.end.x - chain.joint.x, y: chain.end.y - chain.joint.y), by: upper + lower)
        return CGPoint(x: chain.root.x + knee.x + ankle.x, y: chain.root.y + knee.y + ankle.y)
    }

    @Test(arguments: [(drop: CGFloat(22), spread: CGFloat(0), lean: CGFloat(0), sway: CGFloat(0)), (14, 30, 0, 0), (6, 0, -10, 0), (4, 0, 1.5, -12)])
    func stanceKeepsBothFeetPlantedAndFlat(drop: CGFloat, spread: CGFloat, lean: CGFloat, sway: CGFloat) {
        let pose = PipPose.rest.stance(drop: drop, spread: spread, lean: lean, sway: sway)
        let body = pose.joints["body"]!
        for (side, s, out) in [(PipPose.Side.left, "l", -spread), (.right, "r", spread)] {
            let chain = PipUpright.leg(side)
            let upper = pose.joints["leg-\(s)"]!.rotation, lower = pose.joints["shin-\(s)@upright"]!.rotation
            let local = end(of: chain, upper, lower)
            let centred = turned(CGPoint(x: local.x - PipUpright.body.x, y: local.y - PipUpright.body.y), by: body.rotation)
            #expect(abs(centred.x + PipUpright.body.x + body.offset.x - (chain.end.x + out)) < 0.5, "\(s) ankle stays put")
            #expect(abs(centred.y + PipUpright.body.y + body.offset.y - chain.end.y) < 0.5, "\(s) ankle stays down")
            #expect(abs(upper + lower + pose.joints["foot-\(s)"]!.rotation + body.rotation) < 0.001, "\(s) foot stays flat")
        }
    }

    private static let upright = PipGestureLibrary.all.filter { !$0.beats.isEmpty }

    @Test func everyUprightGestureIsBaked() {
        #expect(Self.upright.count == PipGestureLibrary.all.filter { $0.stance == .upright }.count && Self.upright.count == 12)
    }

    /// The whole point of solving limbs on every frame: a foot on the ground never skates, between beats as well as on them.
    @Test(arguments: ["workout-squat", "workout-side-bend", "workout-breather", "stretch-reach"])
    func feetStayPlantedOnEveryBakedFrame(name: String) {
        let gesture = PipGestureLibrary.named(name)
        for beat in PipBake.frames(of: gesture.beats, loops: gesture.loops) {
            let pose = beat.pose, body = pose.joints["body"]!
            for (side, s) in [(PipPose.Side.left, "l"), (.right, "r")] {
                let chain = PipUpright.leg(side)
                let local = end(of: chain, pose.joints["leg-\(s)"]!.rotation, pose.joints["shin-\(s)@upright"]!.rotation)
                let centred = turned(CGPoint(x: local.x - PipUpright.body.x, y: local.y - PipUpright.body.y), by: body.rotation)
                #expect(abs(centred.x + PipUpright.body.x + body.offset.x - chain.end.x) < 0.5, "\(name) \(s) slid")
                #expect(abs(centred.y + PipUpright.body.y + body.offset.y - chain.end.y) < 0.5, "\(name) \(s) left the ground")
            }
        }
    }

    /// Fluency, measured: no joint jumps between two frames. Only the frame that swaps bodies may, and that swap is masked.
    @Test func bakedMotionNeverJumps() {
        for gesture in Self.upright + Self.workoutMoments.map({ PipGestureLibrary.gesture(for: $0.0) }) {
            let frames = PipBake.frames(of: gesture.beats, loops: gesture.loops)
            for (a, b) in zip(frames, frames.dropFirst()) where a.grounded == b.grounded {
                let before = a.pose, after = b.pose
                for (name, joint) in after.joints where !name.hasPrefix("fx-") {
                    let turn = abs(PipUpright.wrapped(joint.rotation - (before.joints[name]?.rotation ?? 0)))
                    #expect(turn < (name.hasPrefix("paw-") ? 0.5 : 0.3), "\(gesture.name): \(name) turns \(turn) in a frame")
                }
            }
        }
    }

    @Test func loopsCloseAndOneShotsLandOnTheirLastBeat() {
        for gesture in Self.upright {
            let frames = PipBake.frames(of: gesture.beats, loops: gesture.loops)
            let first = frames[0], last = frames[frames.count - 1]
            if gesture.loops {
                #expect(abs(gesture.beats[0].drop) + abs(gesture.beats[0].lift) + abs(gesture.beats[0].bend) == 0, "\(gesture.name) starts upright")
                for (a, b) in [(first.drop, last.drop), (first.nod, last.nod), (first.earLeft, last.earLeft), (first.tail4, last.tail4)] {
                    #expect(abs(a - b) < 0.5, "\(gesture.name) does not close")
                }
            } else {
                #expect(last.earLeft == 0 && last.tail4 == 0 && last.scarfRight == 0 && last.headSink == 0, "\(gesture.name)")
                #expect(last.grounded == (gesture.name == "drop-down"), "\(gesture.name)")
            }
        }
    }

    /// A soft part's root stays put, its tip turns the full angle, and no element is lost, or the render server could not blend bends.
    @Test func curlingBendsAPathWithoutChangingItsShapeOfElements() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 50))
        path.addCurve(to: CGPoint(x: 0, y: 100), control1: CGPoint(x: 10, y: 60), control2: CGPoint(x: 10, y: 90))
        let bent = PipBake.curled(path, root: .zero, tip: CGPoint(x: 0, y: 100), angle: .pi / 2) { $0 * $0 }
        var points: [CGPoint] = []
        bent.applyWithBlock { element in
            points.append(element.pointee.points[element.pointee.type == .addCurveToPoint ? 2 : 0])
        }
        #expect(points.count == 3 && points[0] == .zero)
        #expect(abs(points[2].x + 100) < 0.001 && abs(points[2].y) < 0.001, "The tip takes the whole turn")
        #expect(abs(points[1].x + 50 * sin(.pi / 8)) < 0.001, "The middle takes a quarter of it")
    }

    /// A burst hides on every frame it is not flying, so a loop never leaves a crumb hanging in the air.
    @Test func burstsFlyOnceAndHideBetweenThrows() throws {
        let gesture = PipGestureLibrary.named("eat-apple")
        let frames = PipBake.frames(of: gesture.beats, loops: false)
        let joints = try frames.map { try #require($0.effects["fx-crumb-1@upright"]) }
        #expect(joints.first?.scale == .zero && joints.last?.scale == .zero)
        #expect(joints.contains { $0.scale.width > 0.8 }, "It shows")
        #expect(Set(joints.filter { $0.scale.width > 0 }.map(\.offset.y)).count > 10, "It flies")
    }

    @Test func aRaisedPawLiftsItsShoulder() {
        let raised = PipBeat().reach(.right, x: 406, y: 216, paw: -145).pose, down = PipBeat().pose
        #expect((raised.joints["arm-r"]?.offset.y ?? 0) < -5 && down.joints["arm-r"]?.offset.y == 0)
    }

    /// Two drawings with different point counts still blend, because both are redrawn with the same points in the same order.
    @Test func matchedOutlinesHaveTheSameShapeOfElements() throws {
        let square = CGPath(rect: CGRect(x: 0, y: 0, width: 100, height: 100), transform: nil)
        let circle = CGPath(ellipseIn: CGRect(x: 40, y: 20, width: 80, height: 80), transform: nil)
        let match = try #require(PipMorph.matched(square, circle))
        let start = PipMorph.contours(of: match.from), end = PipMorph.contours(of: match.to)
        #expect(start.count == 1 && end.count == 1 && start[0].count == PipMorph.samples && end[0].count == PipMorph.samples)
        #expect(match.from.boundingBox.insetBy(dx: -1, dy: -1).contains(square.boundingBox.insetBy(dx: 1, dy: 1)))
        #expect(abs(match.to.boundingBox.midX - circle.boundingBox.midX) < 2)
    }

    /// A shape drawn in two pieces in one view and one in the other keeps its largest piece through the turn.
    @Test func outlinesPairOffBySize() throws {
        let two = CGMutablePath()
        two.addRect(CGRect(x: 0, y: 0, width: 4, height: 4))
        two.addRect(CGRect(x: 50, y: 50, width: 60, height: 60))
        let one = CGPath(rect: CGRect(x: 50, y: 50, width: 50, height: 50), transform: nil)
        let match = try #require(PipMorph.matched(two, one))
        #expect(PipMorph.contours(of: match.from).count == 1)
        #expect(match.from.boundingBox.minX >= 49, "The small piece sits the turn out")
    }

    /// The head views are drawn rolled for the four-legged body; on a straight spine Pip's head sits level, and it stays
    /// mostly level while the spine tips under it.
    @Test func theHeadStaysLevelOverTheSpine() throws {
        let still = PipBake.frames(of: PipGestureLibrary.named("stretch-reach").beats, loops: false)
        #expect(abs(still[0].nod - PipUpright.level(turn: 0)) < 0.01)
        let bend = PipGestureLibrary.named("workout-side-bend")
        let frames = PipBake.frames(of: bend.beats, loops: true)
        let deepest = try #require(frames.max { abs($0.bend) < abs($1.bend) })
        #expect(abs(deepest.bend) > 10)
        #expect((deepest.nod - PipUpright.level(turn: 0)) * deepest.bend < 0, "The head counters the bend")
    }

    /// Ears and tail are never keyed on a jump: they lag the body on the way up and overshoot on the way down.
    @Test func looseEndsTrailTheBody() {
        let jack = PipGestureLibrary.named("workout-jumping-jack")
        let frames = PipBake.frames(of: jack.beats, loops: true)
        #expect(Set(frames.map(\.earLeft)).count > 20 && frames.contains { $0.earLeft != $0.earRight })
        #expect(frames.contains { $0.tail1 != $0.tail4 }, "The wave runs down the tail")
        #expect(frames.contains { $0.stretch > 0.05 } && frames.contains { $0.stretch < -0.05 }, "It stretches rising and squashes landing")
    }

    @Test func reachPutsTheWristOnItsTargetAndLevelsThePaw() {
        let pose = PipPose.rest.reach(.right, x: 386, y: 292, paw: 180)
        let arm = pose.joints["arm-r"]!.rotation, forearm = pose.joints["forearm-r"]!.rotation
        let wrist = end(of: PipUpright.arm(.right), arm, forearm)
        #expect(abs(wrist.x - 386) < 0.5 && abs(wrist.y - 292) < 0.5)
        #expect(abs(sin(arm + forearm + pose.joints["paw-r"]!.rotation)) < 0.001, "The paw points straight up")
    }

    private static let workoutMoments: [(PipMoment, String)] =
        ["strength", "hiit", "crossfit"].map { (.workoutSaved(activity: $0), "workout-squat") }
        + ["yoga", "pilates"].map { (.workoutSaved(activity: $0), "yoga-tree") }
        + ["stretching", "mobility"].map { (.workoutSaved(activity: $0), "stretch-reach") }
        + ["run", "walk", "cycle", "swim", ""].map { (.workoutSaved(activity: $0), "workout-jumping-jack") }
        + [(.workoutDone(hard: true), "workout-breather"), (.workoutDone(hard: false), "stretch-reach")]

    /// A workout moment stands Pip up, plays the move (a loop twice) and drops him back to rest, as one baked one-shot.
    @Test func workoutMomentsRiseMoveAndDropBack() {
        let rise = PipGestureLibrary.riseUp.duration, drop = PipGestureLibrary.dropDown(endingIn: .standing).duration
        for (moment, name) in Self.workoutMoments {
            let gesture = PipGestureLibrary.gesture(for: moment), move = PipGestureLibrary.named(name)
            #expect(gesture.name == name, "\(moment)")
            #expect(!gesture.loops && PipGestureLibrary.loop(for: moment) == nil, "\(moment) is a one-shot")
            // Each of the (up to three) joins may wait for the next frame.
            #expect(abs(gesture.duration - (rise + move.duration * (move.loops ? 2 : 1) + drop)) < 3 / PipBake.rate, "\(moment) lasts \(gesture.duration)")
            #expect(gesture.keys.last?.pose == .rest && gesture.beats.first?.grounded == true && gesture.beats.last?.grounded == true, "\(moment)")
            #expect(PipBake.frames(of: gesture.beats, loops: false).last?.grounded == true, "\(moment) ends on four legs")
        }
    }

    @Test func recoveryIsNeverCheerful() {
        for key in PipGestureLibrary.gesture(for: .recovery).keys {
            #expect(key.pose.eyes != .closedHappy && key.pose.eyes != .heart)
            #expect(key.pose.mouth != .bigOpen && key.pose.mouth != .smallOpen)
            #expect(key.pose.hearts == 0 && !key.pose.blush)
        }
    }

    @Test func affectionGesturesShowHeartsAndBlush() {
        #expect(PipGestureLibrary.gesture(for: .patted).keys.contains { $0.pose.blush && $0.pose.hearts == 1 && $0.pose.eyes == .closedHappy })
        #expect(PipGestureLibrary.gesture(for: .firstMealToday).keys.contains { $0.pose.hearts == 1 && $0.pose.eyes == .heart })
        #expect(PipGestureLibrary.gesture(for: .dayComplete).keys.contains { $0.pose.hearts == 2 && $0.pose.blush })
    }

    @Test func everyJointNameExistsInTheStandingSet() throws {
        let asset = try PipRigAsset.load(PipRigAssetTests.bundledData())
        // Plain names address the standing (and shared) parts; a full id like `arm-r@seated` addresses one set's part.
        let standing = Set(asset.parts.filter { $0.set == nil || $0.set == "standing" }.map(\.name)).union(asset.parts.map(\.id))
        for gesture in PipGestureLibrary.all {
            for key in gesture.keys {
                for name in key.pose.joints.keys { #expect(standing.contains(name), "\(gesture.name) moves unknown joint \(name)") }
            }
        }
    }
}
