import QuartzCore
import UIKit

/// Draws a `PipRigAsset` as one CALayer per part. A part's container carries its transform and
/// holds its own shape plus its children, so every layer sits in artboard coordinates.
final class PipRigView: UIView {
    private let asset: PipRigAsset
    private let root = CALayer()
    private var containers: [String: CALayer] = [:]
    private var shapes: [String: CAShapeLayer] = [:]
    private var slots: [String: String] = [:]
    private var pupilReach: [String: (lo: CGPoint, hi: CGPoint)] = [:]

    /// Artboard rectangle to fit in the view (defaults to the whole artboard).
    var visibleRect = CGRect(x: 0, y: 0, width: 512, height: 512) { didSet { setNeedsLayout() } }
    var isDark = false { didSet { if isDark != oldValue { applyFills() } } }
    private(set) var visibleViews: Set<String> = []
    private var pose = PipPose.rest

    init(asset: PipRigAsset, set: PipPose.BodySet) {
        self.asset = asset
        super.init(frame: .zero)
        clipsToBounds = true
        isAccessibilityElement = false
        build()
        isDark = traitCollection.userInterfaceStyle == .dark
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in
            view.isDark = view.traitCollection.userInterfaceStyle == .dark
        }
        pose.set = set
        apply(pose, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func layer(named id: String) -> CALayer? { containers[id] }

    func removeAllMotion() {
        root.removeAllAnimations()
        containers.values.forEach { $0.removeAllAnimations() }
        shapes.values.forEach { $0.removeAllAnimations() }
    }

    func apply(_ pose: PipPose, animated: Bool) {
        self.pose = pose
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated { CATransaction.setAnimationDuration(0.2) }
        let (view, local) = Self.view(for: pose.headTurn)
        let wanted: Set<String> = ["eye-l.\(pose.eyes.rawValue)", "eye-r.\(pose.eyes.rawValue)", "mouth.\(pose.mouth.rawValue)"]
        let gaze = Self.clamped(pose.gaze)
        var views: Set<String> = []
        for part in asset.parts {
            guard let container = containers[part.id] else { continue }
            container.isHidden = !isShown(part, view: view, wanted: wanted, pose: pose)
            if !container.isHidden, let partView = part.view { views.insert(partView) }
            var joint = pose.joints[part.name] ?? (part.name.hasPrefix("brow-") ? pose.brows : nil) ?? PipPose.Joint()
            if let reach = pupilReach[part.id] {
                joint.offset.x += gaze.x * (gaze.x < 0 ? -reach.lo.x : reach.hi.x)
                joint.offset.y += gaze.y * (gaze.y < 0 ? -reach.lo.y : reach.hi.y)
            }
            let slide = (part.parallax ?? 0) * local * asset.parallaxScale
            var t = CATransform3DMakeScale(joint.scale.width, joint.scale.height, 1)
            t = CATransform3DRotate(t, joint.rotation, 0, 0, 1)
            container.transform = t.translated(x: joint.offset.x + slide, y: joint.offset.y)
        }
        visibleViews = views
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = min(bounds.width / visibleRect.width, bounds.height / visibleRect.height)
        let tx = (bounds.width - visibleRect.width * s) / 2 - visibleRect.minX * s
        let ty = (bounds.height - visibleRect.height * s) / 2 - visibleRect.minY * s
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.setAffineTransform(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: tx, ty: ty))
        CATransaction.commit()
    }

    // MARK: - Pose resolution

    /// Which head view to show and how far (-1...1) to slide features inside it.
    private static func view(for turn: CGFloat) -> (String, CGFloat) {
        let (name, centre, span): (String, CGFloat, CGFloat) =
            turn > 0.35 ? ("right", 1, 0.65) : turn < -0.35 ? ("left", -1, 0.65) : ("front", 0, 0.35)
        return (name, max(-1, min(1, (turn - centre) / span)))
    }

    private static func clamped(_ gaze: CGPoint) -> CGPoint {
        let length = hypot(gaze.x, gaze.y)
        return length > 1 ? CGPoint(x: gaze.x / length, y: gaze.y / length) : gaze
    }

    private func isShown(_ part: PipRigAsset.Part, view: String, wanted: Set<String>, pose: PipPose) -> Bool {
        guard part.view == nil || part.view == view, part.set == nil || part.set == pose.set.rawValue else { return false }
        if let slot = slots[part.id] { return wanted.contains(slot) }
        return part.visible || (part.name.hasPrefix("cheek-blush") && pose.blush)
    }

    // MARK: - Layer tree

    private func build() {
        root.anchorPoint = .zero
        root.bounds = CGRect(x: 0, y: 0, width: asset.artboard, height: asset.artboard)
        layer.addSublayer(root)
        let byID = Dictionary(uniqueKeysWithValues: asset.parts.map { ($0.id, $0) })
        for part in asset.parts {
            let container = CALayer()
            container.bounds = root.bounds
            container.anchorPoint = CGPoint(x: part.pivot[0] / asset.artboard, y: part.pivot[1] / asset.artboard)
            container.position = CGPoint(x: part.pivot[0], y: part.pivot[1])
            container.zPosition = CGFloat(part.z)
            let shape = CAShapeLayer()
            shape.frame = root.bounds
            shape.zPosition = CGFloat(part.z)
            shape.path = try? PipRigAsset.cgPath(part.path)
            container.addSublayer(shape)
            containers[part.id] = container
            shapes[part.id] = shape
        }
        for part in asset.parts {
            // A missing parent (the body, until it exists) means root.
            (part.parent.flatMap { containers[$0] } ?? root).addSublayer(containers[part.id]!)
            var ancestor: PipRigAsset.Part? = part
            while let current = ancestor, current.shape == nil { ancestor = current.parent.flatMap { byID[$0] } }
            slots[part.id] = ancestor?.shape
            if part.name.contains("pupil"), let iris = part.parent.flatMap({ shapes[$0]?.path?.boundingBoxOfPath }),
               let pupil = shapes[part.id]?.path?.boundingBoxOfPath {
                // Up to 35% of the iris radius, never past the iris edge.
                let reach = 0.35 * iris.width / 2
                pupilReach[part.id] = (
                    lo: CGPoint(x: min(0, max(-reach, iris.minX - pupil.minX)), y: min(0, max(-reach, iris.minY - pupil.minY))),
                    hi: CGPoint(x: max(0, min(reach, iris.maxX - pupil.maxX)), y: max(0, min(reach, iris.maxY - pupil.maxY))))
            }
        }
        applyFills()
    }

    private func applyFills() {
        for part in asset.parts {
            shapes[part.id]?.fillColor = Self.color(isDark ? part.fillDark ?? part.fill : part.fill)
        }
    }

    private static func color(_ hex: String) -> CGColor {
        let v = Int(hex.dropFirst(), radix: 16) ?? 0
        return CGColor(red: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}

private extension CATransform3D {
    func translated(x: CGFloat, y: CGFloat) -> CATransform3D {
        CATransform3DConcat(self, CATransform3DMakeTranslation(x, y, 0))
    }
}
