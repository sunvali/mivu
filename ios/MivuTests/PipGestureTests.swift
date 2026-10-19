import CoreGraphics
import Testing
@testable import Mivu

@Suite struct PipGestureTests {
    private static let moments: [PipMoment] = [
        .greeting(hour: 8), .greeting(hour: 14), .greeting(hour: 22), .welcomeBack, .attentive, .submitted, .thinking,
        .saved, .reviewed, .recovery, .firstMealToday, .dayComplete, .curious,
        .tapped(level: 0), .tapped(level: 1), .tapped(level: 2), .tapped(level: 3), .tapped(level: 4),
        .patted, .earTwitch,
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
    private static let setChangers: Set<String> = ["curl-up", "wake"]

    private static func expectedEnd(of gesture: PipGesture) -> PipPose {
        var end = PipPose.rest
        end.set = gesture.endSet ?? .standing
        if gesture.name == "curl-up" || gesture.name == "curled-ear-flick" { end.eyes = .closedSleepy }
        return end
    }

    @Test func onlyCurlUpAndWakeChangeTheBodySet() {
        #expect(Set(PipGestureLibrary.all.filter { $0.endSet != nil }.map(\.name)) == Self.setChangers)
        #expect(PipGestureLibrary.wake.endSet == .standing && PipGesture.forIdle(.curlUp)?.endSet == .curled)
        for gesture in PipGestureLibrary.all where !Self.setChangers.contains(gesture.name) {
            #expect(gesture.keys.allSatisfy { $0.pose.set == .standing }, "\(gesture.name)")
        }
    }

    @Test func idleBeatsMapToSmallGestures() {
        let beats: [PipIdleScheduler.Beat] = [.earFlick, .weightShift, .yawn, .stretch, .hugTail, .curlUp]
        for beat in beats { #expect(PipGesture.forIdle(beat).map { PipGestureLibrary.all.map(\.name).contains($0.name) } == true, "\(beat)") }
        #expect(PipGesture.forIdle(.yawn)?.keys.contains { $0.pose.mouth == .yawn } == true)
        #expect(PipGesture.forIdle(.earFlick, curled: true)?.name == "curled-ear-flick")
        #expect(PipGesture.forIdle(.earFlick, curled: true)?.keys.allSatisfy { $0.pose.eyes == .closedSleepy } == true)
        for beat in [PipIdleScheduler.Beat.blink, .doubleBlink, .glance(.zero)] { #expect(PipGesture.forIdle(beat) == nil) }
    }

    @Test func everyMomentMapsToALibraryGesture() {
        let names = Set(PipGestureLibrary.all.map(\.name))
        for moment in Self.moments {
            #expect(names.contains(PipGesture.for(moment).name), "\(moment)")
        }
        #expect(PipGesture.loopFor(.thinking)?.loops == true)
        #expect(PipGesture.loopFor(.attentive)?.loops == true)
        #expect(PipGesture.loopFor(.saved) == nil)
    }

    @Test func spokenTimingsMatchSpec() {
        func gesture(_ moment: PipMoment) -> PipGesture { PipGesture.for(moment) }
        #expect(abs(gesture(.greeting(hour: 14)).duration - 0.70) <= 0.01)
        #expect(abs(gesture(.saved).duration - 0.45) <= 0.01)
        #expect(abs(gesture(.reviewed).duration - 0.65) <= 0.01)
        #expect(gesture(.submitted).keys[0].at <= 0.1)
        #expect(gesture(.submitted).duration <= 0.8)
        #expect(abs(PipGesture.loopFor(.thinking)!.duration - 1.4) <= 0.01)
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

    @Test func recoveryIsNeverCheerful() {
        for key in PipGesture.for(.recovery).keys {
            #expect(key.pose.eyes != .closedHappy && key.pose.eyes != .heart)
            #expect(key.pose.mouth != .bigOpen && key.pose.mouth != .smallOpen)
            #expect(key.pose.hearts == 0 && !key.pose.blush)
        }
    }

    @Test func affectionGesturesShowHeartsAndBlush() {
        #expect(PipGesture.for(.patted).keys.contains { $0.pose.blush && $0.pose.hearts == 1 && $0.pose.eyes == .closedHappy })
        #expect(PipGesture.for(.firstMealToday).keys.contains { $0.pose.hearts == 1 && $0.pose.eyes == .heart })
        #expect(PipGesture.for(.dayComplete).keys.contains { $0.pose.hearts == 2 && $0.pose.blush })
    }

    @Test func everyJointNameExistsInTheStandingSet() throws {
        let asset = try PipRigAsset.load(PipRigAssetTests.bundledData())
        let standing = Set(asset.parts.filter { $0.set == nil || $0.set == "standing" }.map(\.name))
        for gesture in PipGestureLibrary.all {
            for key in gesture.keys {
                for name in key.pose.joints.keys { #expect(standing.contains(name), "\(gesture.name) moves unknown joint \(name)") }
            }
        }
    }
}
