import Foundation

enum MotionPolicy {
    enum Playback: Equatable {
        case hidden, staticPose, animated
    }

    static func playback(
        reduceMotion: Bool, lowPower: Bool, thermalState: ProcessInfo.ThermalState,
        sceneActive: Bool, selected: Bool, visible: Bool, covered: Bool
    ) -> Playback {
        guard sceneActive, selected, visible, !covered else { return .hidden }
        guard !reduceMotion, !lowPower, thermalState != .serious, thermalState != .critical else {
            return .staticPose
        }
        return .animated
    }
}
