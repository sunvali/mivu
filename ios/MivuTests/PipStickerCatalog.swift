import CoreGraphics
import UIKit
@testable import Mivu

/// One chat sticker: a held pose or a looping run of frames, posed with the app's own helpers and gestures.
struct PipSticker {
    enum Kind { case still(PipPose), animated(frames: [PipPose], fps: Double) }
    let id: String
    let emoji: [String]
    let kind: Kind
    /// Rig layers hidden after the pose is applied, e.g. the food in an empty bowl.
    var hidden: [String] = []
}

/// The approved first pack (docs/superpowers/specs/2026-11-15-pip-stickers-design.md), in lineup order.
enum PipStickerCatalog {
    static let all: [PipSticker] = [
        PipSticker(id: "hi", emoji: ["👋", "😊"], kind: .animated(frames: [.rest], fps: 20)),
        PipSticker(id: "thanks", emoji: ["🙏", "😊"], kind: .still(upright(PipBeat().turn(0)
            .reach(.left, x: 298, y: 330, paw: 150).reach(.right, x: 334, y: 330, paw: -150)
            .stance(drop: 4).nod(10).eyes(.closedHappy).blushing().earPerk(-8)))),
        PipSticker(id: "love-it", emoji: ["❤️", "😍"], kind: .still(key("idle-hug-tail", 1).hearts(3))),
        PipSticker(id: "lol", emoji: ["😂", "🤣"], kind: .still(key("tap-giggle", 0).mouth(.bigOpen).tilt(-3))),
        PipSticker(id: "ok", emoji: ["👍", "😉"], kind: .still(key("tap-wink", 1).pawUp(.right, -45, elbow: -85))),
        PipSticker(id: "oops", emoji: ["😅", "🙈"], kind: .still(key("welcome-back", 0).blushing().look(-0.6, 0.3).tilt(-2))),
        PipSticker(id: "good-night", emoji: ["😴", "🌙"], kind: .animated(frames: [.rest], fps: 20)),
        PipSticker(id: "yum", emoji: ["😋", "🥗"], kind: .still(upright(PipBeat().holding(.bowl)
            .reach(.left, x: 292, y: 366, paw: 180).reach(.right, x: 364, y: 332, paw: -160)
            .stance(drop: 4).eyes(.closedHappy).mouth(.smallOpen).blushing().hearts(1)))),
        // The bowl comes up empty; no spoon in the paw that rubs the tummy.
        PipSticker(id: "hungry", emoji: ["🤤", "🍽️"], kind: .still(upright(PipBeat().holding(.bowl)
            .reach(.left, x: 292, y: 366, paw: 180).reach(.right, x: 330, y: 372, paw: -90)
            .nod(6).look(-0.3, 1).mouth(.concerned).earPerk(-10).brow(4))),
            hidden: ["prop-bowl.food@upright", "prop-bowl-spoon@upright"]),
        PipSticker(id: "hydrate", emoji: ["💧", "🥤"], kind: .still(upright(PipBeat().holding(.cup)
            .reach(.right, x: 364, y: 286, paw: 150).reach(.left, x: 300, y: 340, paw: 120)
            .spine(bend: -7, stretch: 0.03).nod(-12).mouth(.o).eyes(.closedHappy)))),
        PipSticker(id: "snack", emoji: ["🍎", "😄"], kind: .still(upright(PipBeat().holding(.apple)
            .reach(.right, x: 396, y: 262, paw: 180).reach(.left, x: 300, y: 340, paw: 120)
            .spine(stretch: 0.03).eyes(.closedHappy).mouth(.bigOpen).earPerk(12).brow(5)))),
        PipSticker(id: "you-got-it", emoji: ["💪", "🎉"], kind: .animated(frames: [.rest], fps: 20)),
    ]

    /// A key of an app gesture, as the app plays it.
    static func key(_ gesture: String, _ index: Int) -> PipPose { PipGestureLibrary.named(gesture).keys[index].pose }

    /// A beat on the two-legged body, the way `PipRigView.play` mounts it.
    static func upright(_ beat: PipBeat) -> PipPose {
        var pose = beat.pose
        pose.set = .upright
        return pose
    }
}

/// The pose on the app's rig at 512 × 512, light fills, transparent background.
@MainActor func renderSticker(_ pose: PipPose, hidden: [String]) throws -> UIImage {
    let view = PipRigView(asset: try PipRigAsset.load(PipRigAssetTests.bundledData()), set: pose.set)
    view.frame = CGRect(x: 0, y: 0, width: 512, height: 512)
    view.layoutIfNeeded()
    view.apply(pose, animated: false)
    for id in hidden { view.layer(named: id)?.isHidden = true }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { view.layer.render(in: $0.cgContext) }
}
