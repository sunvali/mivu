import CoreGraphics
import QuartzCore
import Testing
import UIKit
@testable import Mivu

@Suite @MainActor struct PipRigViewTests {
    private func rig(_ pose: PipPose = .rest) throws -> PipRigView {
        let view = PipRigView(asset: try PipRigAsset.load(PipRigAssetTests.bundledData()), set: .seated)
        view.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        view.apply(pose, animated: false)
        return view
    }

    @Test func restPoseShowsDefaultFaceShapesOnly() throws {
        let view = try rig()
        #expect(view.layer(named: "mouth.closedSmile@right")?.isHidden == false)
        #expect(view.layer(named: "mouth.bigOpen@right")?.isHidden == true)
        #expect(view.layer(named: "eye-l.open@right")?.isHidden == false)
    }

    @Test func headTurnSwapsViewsAndSlidesFeatures() throws {
        var pose = PipPose.rest
        for (turn, shown) in [(1.0, "right"), (-1.0, "left"), (0.0, "front")] {
            pose.headTurn = turn
            let view = try rig(pose)
            #expect(view.visibleViews == [shown])
        }
        let right = try rig(.rest)
        pose.headTurn = 0.8
        let near = try rig(pose)
        let dx = near.layer(named: "nose@right")!.transform.m41 - right.layer(named: "nose@right")!.transform.m41
        #expect(abs(dx - 0.4 * 20 * (-0.2 / 0.65)) < 0.01)
        #expect(near.layer(named: "head@right")!.transform.m41 == 0)
    }

    @Test func gazeMovesPupilsWithinIris() throws {
        let rest = try rig()
        var pose = PipPose.rest
        pose.gaze = CGPoint(x: 1, y: 0)
        let view = try rig(pose)
        func frame(_ v: PipRigView, _ id: String) -> CGRect {
            let layer = v.layer(named: id)!
            let box = (layer.sublayers!.first as! CAShapeLayer).path!.boundingBoxOfPath
            return box.offsetBy(dx: layer.transform.m41, dy: layer.transform.m42)
        }
        let pupil = frame(view, "pupil-l@right")
        #expect(pupil.minX > frame(rest, "pupil-l@right").minX)
        #expect(frame(view, "iris-l@right").contains(pupil))
    }
}
