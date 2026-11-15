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
        PipSticker(id: "hi", emoji: ["👋", "😊"], kind: .animated(frames: baked(hi), fps: fps)),
        PipSticker(id: "thanks", emoji: ["🙏", "😊"], kind: .still(upright(PipBeat().turn(0)
            .reach(.left, x: 298, y: 330, paw: 150).reach(.right, x: 334, y: 330, paw: -150)
            .stance(drop: 4).nod(10).eyes(.closedHappy).blushing().earPerk(-8)))),
        PipSticker(id: "love-it", emoji: ["❤️", "😍"], kind: .still(key("idle-hug-tail", 1).hearts(3))),
        PipSticker(id: "lol", emoji: ["😂", "🤣"], kind: .still(key("tap-giggle", 0).mouth(.bigOpen).tilt(-3))),
        PipSticker(id: "ok", emoji: ["👍", "😉"], kind: .still(key("tap-wink", 1).pawUp(.right, -45, elbow: -85))),
        PipSticker(id: "oops", emoji: ["😅", "🙈"], kind: .still(key("welcome-back", 0).blushing().look(-0.6, 0.3).tilt(-2))),
        PipSticker(id: "good-night", emoji: ["😴", "🌙"], kind: .animated(frames: goodNight, fps: fps)),
        PipSticker(id: "yum", emoji: ["😋", "🥗"], kind: .still(upright(PipBeat().holding(.bowl)
            .reach(.left, x: 292, y: 366, paw: 180).reach(.right, x: 364, y: 332, paw: -160)
            .stance(drop: 4).eyes(.closedHappy).mouth(.smallOpen).blushing().hearts(1)))),
        // The bowl comes up empty; no spoon in the paw that rubs the tummy.
        PipSticker(id: "hungry", emoji: ["🤤", "🍽️"], kind: .still(upright(PipBeat().holding(.bowl)
            .reach(.left, x: 292, y: 366, paw: 180).reach(.right, x: 330, y: 372, paw: -90)
            .nod(6).look(-0.3, 1).mouth(.concerned).earPerk(-10).brow(4))),
            hidden: ["prop-bowl.food@upright", "prop-bowl-spoon@upright"]),
        // The refreshed beat of `sip-water`: the cup held out in front, so it reads at chat size.
        PipSticker(id: "hydrate", emoji: ["💧", "🥤"], kind: .still(upright(PipBeat().holding(.cup)
            .reach(.right, x: 386, y: 330, paw: 180).reach(.left, x: 300, y: 340, paw: 120)
            .spine(stretch: 0.03).nod(-2).eyes(.closedHappy).mouth(.smallOpen).blushing().earPerk(10)))),
        PipSticker(id: "snack", emoji: ["🍎", "😄"], kind: .still(upright(PipBeat().holding(.apple)
            .reach(.right, x: 428, y: 300, paw: 180).reach(.left, x: 300, y: 340, paw: 120)
            .spine(stretch: 0.03).eyes(.closedHappy).mouth(.bigOpen).earPerk(12).brow(5)))),
        PipSticker(id: "you-got-it", emoji: ["💪", "🎉"], kind: .animated(frames: baked(cheer), fps: fps)),
    ]

    /// Animated stickers play at 20 fps: every third frame of the app's 60 fps bake keeps them small enough for WhatsApp.
    static let fps = PipBake.rate / 3

    /// Standing tall, the near paw waving overhead; starts and ends on the same beat so it loops.
    static let hi = PipGesture(beats: "sticker-hi", loops: true) {
        let wave: (PipBeat, CGFloat, CGFloat) -> PipBeat = { beat, x, paw in
            beat.turn(0).reach(.right, x: x, y: 214, paw: paw).reach(.left, x: 300, y: 340, paw: 120).mouth(.smallOpen).earPerk(10)
        }
        $0.at(0) { wave($0, 392, -165) }
        $0.at(0.30) { wave($0, 444, -95).nod(-3).tailWag(14) }
        $0.at(0.60) { wave($0, 392, -165).tailWag(-14) }
        $0.at(0.90) { wave($0, 444, -95).nod(-3).tailWag(14) }
        $0.at(1.20) { wave($0, 392, -165) }
    }

    /// Both paws up, crouch, hop and land, over and over.
    static let cheer = PipGesture(beats: "sticker-cheer", loops: true) {
        let up: (PipBeat, CGFloat) -> PipBeat = { beat, out in
            beat.turn(0).reach(.left, x: 226 - out, y: 216, paw: 145).reach(.right, x: 406 + out, y: 216, paw: -145)
                .eyes(.closedHappy).mouth(.bigOpen)
        }
        $0.at(0) { up($0, 0).stance(drop: 4) }
        $0.at(0.18) { up($0, -6).stance(drop: 14).spine(stretch: -0.04).earPerk(-6) }
        $0.at(0.40) { up($0, 8).stance(lift: 28).spine(stretch: 0.05).earPerk(14).tailWag(16) }
        $0.at(0.62) { up($0, 0).stance(drop: 12).spine(stretch: -0.03).tailWag(-12) }
        $0.at(0.90) { up($0, 0).stance(drop: 4) }
    }

    /// Curled asleep for three seconds: a slow breath while three z's swell, drift up and shrink away in turn.
    static let goodNight: [PipPose] = (0..<Int(3 * fps)).map { frame in
        let phase = Double(frame) / (3 * fps)
        var pose = PipPose.rest.eyes(.closedSleepy).squash(0.015 * sin(2 * .pi * phase))
        pose.set = .curled
        for n in 1...3 {
            let rise = (phase + Double(n - 1) / 3).truncatingRemainder(dividingBy: 1)
            let size = sin(.pi * rise)
            pose.joints["fx-z-\(n)@curled"] = PipPose.Joint(offset: CGPoint(x: -18 * rise, y: -26 * rise), scale: CGSize(width: size, height: size))
        }
        return pose
    }

    /// One loop of a beat gesture at `fps`, through the app's own curve and follow-through.
    static func baked(_ gesture: PipGesture) -> [PipPose] {
        let frames = PipBake.frames(of: gesture.beats, loops: true).dropLast() // the last frame is the first again
        return stride(from: 0, to: frames.count, by: 3).map { i in
            var pose = frames[i].pose
            pose.set = frames[i].grounded ? .standing : .upright
            return pose
        }
    }

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
    let asset = try PipRigAsset.load(PipRigAssetTests.bundledData())
    let view = PipRigView(asset: asset, set: pose.set)
    view.frame = CGRect(x: 0, y: 0, width: 512, height: 512)
    view.layoutIfNeeded()
    view.apply(pose, animated: false)
    // No ground shadow: the die-cut outline would turn it into a white bar under the feet.
    let shadows = asset.parts.filter { $0.name == "shadow" }.map(\.id)
    for id in hidden + shadows { view.layer(named: id)?.isHidden = true }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { view.layer.render(in: $0.cgContext) }
}
