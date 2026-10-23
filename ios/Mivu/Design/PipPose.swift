import CoreGraphics

/// A resting-or-moving description of Pip. Joint names address rig parts without their `@view` suffix.
struct PipPose: Equatable {
    struct Joint: Equatable {
        var rotation: CGFloat = 0
        var offset: CGPoint = .zero
        var scale = CGSize(width: 1, height: 1)
    }

    enum EyeShape: String { case open, half, closedHappy, closedSleepy, wide, heart }
    enum MouthShape: String { case closedSmile, smallOpen, bigOpen, o, concerned, yawn }
    enum BodySet: String { case standing, seated, curled }

    var joints: [String: Joint] = [:]
    var eyes = EyeShape.open
    var mouth = MouthShape.closedSmile
    /// Unit-disc pupil direction; +y looks down.
    var gaze = CGPoint.zero
    var blush = false
    /// How many of the rig's `heart-1…3` parts are visible.
    var hearts = 0
    /// Shows the `prop-chart` card on the standing right paw (Progress).
    var chart = false
    /// Today rests standing; Coach chooses `.seated` explicitly.
    var set = BodySet.standing
    /// -1 left, 0 front, +1 right. Small moves around a view slide features; larger ones swap views.
    var headTurn: CGFloat = 1

    static let rest = PipPose()
}
