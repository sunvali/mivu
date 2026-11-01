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
        #expect(try pivot("body") == PipUpright.body)
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

    @Test func reachPutsTheWristOnItsTargetAndLevelsThePaw() {
        let pose = PipPose.rest.reach(.right, x: 386, y: 292, paw: 180)
        let arm = pose.joints["arm-r"]!.rotation, forearm = pose.joints["forearm-r"]!.rotation
        let wrist = end(of: PipUpright.arm(.right), arm, forearm)
        #expect(abs(wrist.x - 386) < 0.5 && abs(wrist.y - 292) < 0.5)
        #expect(abs(sin(arm + forearm + pose.joints["paw-r"]!.rotation)) < 0.001, "The paw points straight up")
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
