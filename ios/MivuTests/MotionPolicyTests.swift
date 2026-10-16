import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct MotionPolicyTests {
    @Test(arguments: 0..<4)
    func hiddenAlwaysStopsPlayback(reason: Int) {
        #expect(MotionPolicy.playback(
            reduceMotion: false, lowPower: false, thermalState: .nominal,
            sceneActive: reason != 0, selected: reason != 1,
            visible: reason != 2, covered: reason == 3
        ) == .hidden)
    }

    @Test(arguments: [true, false])
    func reducedMotionAndLowPowerUseStaticPoses(reduceMotion: Bool) {
        #expect(MotionPolicy.playback(
            reduceMotion: reduceMotion, lowPower: !reduceMotion, thermalState: .nominal,
            sceneActive: true, selected: true, visible: true, covered: false
        ) == .staticPose)
    }

    @Test(arguments: [ProcessInfo.ThermalState.serious, .critical])
    func seriousAndCriticalThermalUseStaticPoses(thermalState: ProcessInfo.ThermalState) {
        #expect(MotionPolicy.playback(
            reduceMotion: false, lowPower: false, thermalState: thermalState,
            sceneActive: true, selected: true, visible: true, covered: false
        ) == .staticPose)
    }

    @Test(arguments: [ProcessInfo.ThermalState.nominal, .fair])
    func nominalVisibleRootAllowsMotion(thermalState: ProcessInfo.ThermalState) {
        #expect(MotionPolicy.playback(
            reduceMotion: false, lowPower: false, thermalState: thermalState,
            sceneActive: true, selected: true, visible: true, covered: false
        ) == .animated)
    }
}
