import Foundation

enum MotionPolicy {
    enum Playback: Equatable {
        case hidden, staticPose, animated
    }

    static func playback(
        reduceMotion: Bool, thermalState: ProcessInfo.ThermalState,
        sceneActive: Bool, selected: Bool, visible: Bool, covered: Bool
    ) -> Playback {
        guard sceneActive, selected, visible, !covered else { return .hidden }
        // Low Power Mode keeps Pip moving on every tab; only Reduce Motion and serious heat hold him still.
        guard !reduceMotion, thermalState != .serious, thermalState != .critical else {
            return .staticPose
        }
        return .animated
    }
}
