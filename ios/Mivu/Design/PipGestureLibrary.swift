import CoreGraphics

/// Every gesture Pip knows. To add one, append an entry to `all` (and, for an app event, a case in
/// `gesture(for:)`); the validation tests and the debug preview pick it up automatically.
/// Each `at` key is the full pose Pip arrives at by that time; unlisted joints rest.
enum PipGestureLibrary {
    static let all: [PipGesture] = [
        // MARK: Greetings
        PipGesture("greeting") {
            $0.at(0.10) { $0.squash(0.06).earPerk(-6).nod(3) }
            $0.at(0.26) { $0.hop(12).earPerk(14).pawUp(.right).mouth(.smallOpen).tailWag(16).scarf(-6) }
            $0.at(0.35) { $0.pawUp(.right, -45, elbow: -85).earPerk(8).mouth(.smallOpen).tailWag(-16).nod(-3) }
            $0.at(0.44) { $0.pawUp(.right, -45, elbow: -35).earPerk(10).mouth(.smallOpen).tailWag(16).nod(-2) }
            $0.settle(at: 0.70)
        },
        PipGesture("greeting-morning") {
            $0.at(0.10) { $0.squash(0.06).earPerk(-6).nod(3) }
            $0.at(0.28) { $0.squash(-0.05).pawUp(.both, -60, elbow: -75).nod(-8).earPerk(14).mouth(.yawn).eyes(.closedHappy) }
            $0.at(0.48) { $0.pawUp(.right, -100, elbow: -50).earPerk(10).mouth(.smallOpen).tailWag(16).hop(6) }
            $0.at(0.60) { $0.pawUp(.right, -45, elbow: -35).earPerk(8).mouth(.smallOpen).tailWag(-12) }
            $0.settle(at: 0.90)
        },
        PipGesture("greeting-evening") {
            $0.at(0.12) { $0.nod(2).earPerk(-4) }
            $0.at(0.34) { $0.earPerk(8).pawUp(.right, -35, elbow: -70).eyes(.half).mouth(.closedSmile).nod(-2) }
            $0.at(0.52) { $0.pawUp(.right, -35, elbow: -35).earPerk(6).eyes(.half).nod(-2) }
            $0.settle(at: 0.90)
        },
        PipGesture("welcome-back") {
            $0.at(0.12) { $0.earPerk(-24).nod(8).eyes(.wide).mouth(.concerned).tailWag(-12) }
            $0.at(0.40) { $0.earPerk(-24).nod(8).eyes(.wide).mouth(.concerned).look(0, -0.4) }
            $0.at(0.58) { $0.squash(0.07).earPerk(-8) }
            $0.at(0.78) { $0.hop(14).earPerk(18).pawUp(.right).mouth(.bigOpen).tailWag(24).blushing().scarf(-8) }
            $0.at(0.92) { $0.pawUp(.right, -45, elbow: -85).mouth(.bigOpen).tailWag(-24).earPerk(10).blushing() }
            $0.at(1.04) { $0.pawUp(.right, -45, elbow: -35).mouth(.smallOpen).tailWag(20).earPerk(12).blushing() }
            $0.settle(at: 1.40)
        },

        // MARK: Loops
        // Progress: eyes down on the chart below, a paw lifted toward it, tail going; the first key is the still pose.
        PipGesture("presenting-cheer", loops: true) {
            $0.at(0.35) { $0.pawUp(.right, -35, elbow: -70).look(0.3, 1).nod(8).mouth(.smallOpen).earPerk(12).tailWag(14) }
            $0.at(0.95) { $0.pawUp(.right, -38, elbow: -74).look(0.4, 0.9).nod(9).mouth(.smallOpen).earPerk(14).tailWag(-14) }
            $0.at(1.55) { $0.pawUp(.right, -35, elbow: -70).look(0.3, 1).nod(8).mouth(.smallOpen).earPerk(12).tailWag(14) }
        },
        PipGesture("presenting-calm", loops: true) {
            $0.at(0.40) { $0.pawUp(.right, -30, elbow: -62).look(0.3, 0.9).nod(7).mouth(.closedSmile).earPerk(8).tailWag(8) }
            $0.at(1.20) { $0.pawUp(.right, -32, elbow: -66).look(0.4, 0.85).nod(8).mouth(.closedSmile).earPerk(10).tailWag(-8) }
            $0.at(2.00) { $0.pawUp(.right, -30, elbow: -62).look(0.3, 0.9).nod(7).mouth(.closedSmile).earPerk(8).tailWag(8) }
        },
        PipGesture("attentive", loops: true) {
            $0.at(0.5) { $0.nod(3).earPerk(10).tilt(1.5).look(0.5, 0.2) }
            $0.at(1.0) { $0.nod(-1).earPerk(6).look(0.8, 0.1) }
            $0.settle(at: 1.6)
        },
        PipGesture("thinking", loops: true) {
            $0.at(0.35) { $0.nod(-5).pawUp(.right, -30, elbow: -110).look(0.7, -0.6).eyes(.half).tailWag(12) }
            $0.at(0.7) { $0.nod(-3).pawUp(.right, -30, elbow: -110).look(-0.7, -0.5).eyes(.half).tailWag(-12) }
            $0.at(1.05) { $0.nod(-5).pawUp(.right, -30, elbow: -110).look(0.7, -0.6).eyes(.half).tailWag(12) }
            $0.settle(at: 1.4)
        },

        // MARK: Feedback
        PipGesture("submitted") {
            $0.at(0.08) { $0.squash(0.07).nod(5).earPerk(-5) }
            $0.at(0.26) { $0.nod(-4).pawUp(.right, -40, elbow: -30).earPerk(10).squash(-0.03) }
            $0.settle(at: 0.60)
        },
        PipGesture("saved") {
            $0.at(0.07) { $0.nod(5).eyes(.closedHappy).squash(0.05) }
            $0.at(0.19) { $0.pawUp(.right, -40, elbow: -40).eyes(.closedHappy).mouth(.smallOpen).hop(8).earPerk(10).tailWag(16) }
            $0.at(0.28) { $0.pawUp(.right, -40, elbow: -40).eyes(.closedHappy).mouth(.smallOpen).squash(0.05).scarf(8) }
            $0.settle(at: 0.45)
        },
        PipGesture("reviewed") {
            $0.at(0.09) { $0.squash(0.05).nod(3) }
            $0.at(0.26) { $0.squash(-0.06).pawUp(.both, -55, elbow: -75).nod(-6).earPerk(10).mouth(.smallOpen) }
            $0.at(0.38) { $0.squash(-0.04).pawUp(.both, -55, elbow: -75).nod(-5).earPerk(12).mouth(.smallOpen).eyes(.closedHappy) }
            $0.settle(at: 0.65)
        },
        PipGesture("recovery") {
            $0.at(0.20) { $0.earPerk(-28).nod(8).mouth(.concerned).eyes(.wide).tilt(1.5) }
            $0.at(0.60) { $0.earPerk(-26).nod(6).mouth(.concerned).eyes(.wide).pawUp(.right, -20, elbow: -85).tilt(1.5) }
            // Stays at the supportive pose, then eases back to rest.
            $0.at(1.40) { $0.earPerk(-20).nod(4).mouth(.concerned).pawUp(.right, -20, elbow: -85) }
            $0.settle(at: 1.80)
        },

        // MARK: Affection and habits
        PipGesture("first-meal-today") {
            $0.at(0.12) { $0.squash(0.07).eyes(.heart) }
            $0.at(0.30) { $0.hop(12).eyes(.heart).earPerk(14).mouth(.smallOpen).hearts(1).tailWag(20).scarf(-8) }
            $0.at(0.42) { $0.tilt(-2.5).eyes(.heart).mouth(.smallOpen).hearts(1, drift: 6).tailWag(-20).earPerk(10) }
            $0.at(0.54) { $0.tilt(2.5).eyes(.heart).mouth(.smallOpen).hearts(1, drift: 12).tailWag(20).earPerk(12) }
            $0.at(0.66) { $0.tilt(-2).eyes(.heart).hearts(1, drift: 18).tailWag(-16) }
            $0.settle(at: 1.00)
        },
        PipGesture("day-complete") {
            $0.at(0.12) { $0.squash(0.08).earPerk(-6) }
            $0.at(0.34) { $0.hop(14).pawUp(.both, -60, elbow: -75).earPerk(16).mouth(.bigOpen).blushing().hearts(2).tailWag(24).scarf(-10) }
            $0.at(0.56) { $0.squash(0.06).pawUp(.both, -55, elbow: -75).mouth(.bigOpen).blushing().hearts(2, drift: 8) }
            $0.at(0.76) { $0.hop(10).pawUp(.both, -60, elbow: -75).earPerk(14).mouth(.bigOpen).blushing().hearts(2, drift: 16).tailWag(-24) }
            $0.at(0.92) { $0.pawUp(.both, -55, elbow: -75).mouth(.smallOpen).blushing().hearts(2, drift: 22).eyes(.closedHappy) }
            $0.settle(at: 1.30)
        },
        PipGesture("curious") {
            $0.at(0.15) { $0.nod(4).earPerk(16).look(-1, 0.1).turn(0.6).eyes(.wide) }
            $0.at(0.55) { $0.tilt(2).nod(5).earPerk(18, .right).look(-1, 0.2).turn(0.6).eyes(.wide).mouth(.o) }
            $0.settle(at: 0.95)
        },
        PipGesture("patted") {
            $0.at(0.14) { $0.tilt(3).nod(8).eyes(.closedHappy).blushing().earPerk(-10) }
            $0.at(0.34) { $0.tilt(3.5).nod(9).eyes(.closedHappy).blushing().earPerk(-12).hearts(1, drift: 4).tailWag(28).mouth(.smallOpen) }
            $0.at(0.54) { $0.tilt(3).nod(8).eyes(.closedHappy).blushing().earPerk(-10).hearts(1, drift: 12).tailWag(-28).mouth(.smallOpen) }
            $0.at(0.74) { $0.tilt(3.5).nod(9).eyes(.closedHappy).blushing().earPerk(-12).hearts(1, drift: 20).tailWag(28).mouth(.smallOpen) }
            $0.at(0.94) { $0.tilt(3).nod(8).eyes(.closedHappy).blushing().hearts(1, drift: 28).tailWag(-20) }
            $0.settle(at: 1.30)
        },

        // MARK: Taps
        PipGesture("tap-giggle") {
            $0.at(0.06) { $0.nod(4).squash(0.08).mouth(.smallOpen).eyes(.closedHappy) }
            $0.at(0.16) { $0.nod(-3).squash(-0.04).mouth(.smallOpen).eyes(.closedHappy).earPerk(10) }
            $0.at(0.26) { $0.nod(3).squash(0.06).mouth(.smallOpen).eyes(.closedHappy) }
            $0.at(0.36) { $0.squash(-0.02).earPerk(6) }
            $0.settle(at: 0.55)
        },
        PipGesture("tap-ear-wiggle") {
            $0.at(0.07) { $0.nod(3).earPerk(20, .left).earPerk(-10, .right).look(-0.4) }
            $0.at(0.15) { $0.earPerk(-12, .left).earPerk(20, .right).look(-0.4) }
            $0.at(0.23) { $0.earPerk(18, .left).earPerk(-8, .right) }
            $0.at(0.31) { $0.earPerk(-8, .left).earPerk(14, .right) }
            $0.settle(at: 0.55)
        },
        PipGesture("tap-wink") {
            $0.at(0.10) { $0.nod(-3).turn(0.6).look(-1, 0.1).earPerk(10) }
            $0.at(0.22) { $0.nod(-2).turn(0.6).look(-1, 0.1).eyes(.closedHappy).mouth(.smallOpen).tilt(1.5).earPerk(12) }
            $0.at(0.50) { $0.nod(-2).turn(0.6).look(-1, 0.1).mouth(.smallOpen).earPerk(8) }
            $0.settle(at: 0.80)
        },
        PipGesture("tap-tail-flick") {
            $0.at(0.08) { $0.tailWag(-32).tilt(-1.5).look(0.6, 0.2) }
            $0.at(0.18) { $0.tailWag(48).tilt(1.5).look(0.6, 0.2).earPerk(8) }
            $0.at(0.30) { $0.tailWag(-24).look(0.6, 0.2) }
            $0.at(0.42) { $0.tailWag(16) }
            $0.settle(at: 0.65)
        },
        PipGesture("shake-off") {
            $0.at(0.06) { $0.nod(-2).tilt(-3).squash(0.04).earPerk(-6) }
            $0.at(0.14) { $0.nod(4).tilt(3).earPerk(14).scarf(10) }
            $0.at(0.22) { $0.nod(-4).tilt(-3).earPerk(-10).scarf(-10) }
            $0.at(0.30) { $0.nod(3).tilt(2).earPerk(10).scarf(6) }
            $0.at(0.38) { $0.nod(-2).tilt(-1.5).earPerk(-4) }
            $0.settle(at: 0.65)
        },
        PipGesture("ear-twitch") {
            $0.at(0.05) { $0.earPerk(18, .right) }
            $0.at(0.11) { $0.earPerk(-6, .right) }
            $0.settle(at: 0.22)
        },

        // MARK: Idle beats (see PipIdleScheduler); blinks and glances use the rig's own blink and look
        PipGesture("idle-ear-flick") {
            $0.at(0.06) { $0.earPerk(16, .left) }
            $0.at(0.12) { $0.earPerk(-5, .left).nod(1) }
            $0.settle(at: 0.26)
        },
        // The ear flick for a sleeping Pip: the eyes never open.
        PipGesture("curled-ear-flick") {
            $0.at(0.06) { $0.earPerk(16, .left).eyes(.closedSleepy) }
            $0.at(0.12) { $0.earPerk(-5, .left).eyes(.closedSleepy) }
            $0.at(0.26) { $0.eyes(.closedSleepy) }
        },
        PipGesture("idle-weight-shift") {
            $0.at(0.45) { $0.tilt(1.5).tailWag(8).nod(1) }
            $0.at(0.95) { $0.tilt(1.5).tailWag(8) }
            $0.settle(at: 1.50)
        },
        PipGesture("idle-yawn") {
            $0.at(0.45) { $0.nod(-6).earPerk(-6).mouth(.yawn).eyes(.closedSleepy) }
            $0.at(1.15) { $0.nod(-5).earPerk(-6).mouth(.yawn).eyes(.closedSleepy) }
            $0.at(1.50) { $0.nod(3).eyes(.closedSleepy).mouth(.smallOpen) }
            $0.settle(at: 1.90)
        },
        PipGesture("idle-stretch") {
            $0.at(0.50) { $0.squash(-0.05).pawUp(.both, -55, elbow: -10).nod(-7).earPerk(-8).tailWag(14).eyes(.closedHappy) }
            $0.at(1.15) { $0.squash(-0.05).pawUp(.both, -55, elbow: -10).nod(-7).earPerk(-8).tailWag(14).eyes(.closedHappy) }
            $0.at(1.45) { $0.squash(0.03).nod(2).eyes(.closedHappy) }
            $0.settle(at: 1.90)
        },
        PipGesture("idle-hug-tail") {
            $0.at(0.45) { $0.nod(8).tilt(2).tailWag(-34).eyes(.closedHappy).blushing().earPerk(-8) }
            $0.at(1.25) { $0.nod(8).tilt(2.5).tailWag(-36).eyes(.closedHappy).blushing().earPerk(-10) }
            $0.settle(at: 1.80)
        },
        // Changes set on purpose: ends curled and asleep, and `wake` stands Pip back up.
        PipGesture("curl-up") {
            $0.at(0.45) { $0.squash(0.05).nod(10).earPerk(-16).eyes(.half).tailWag(-12) }
            $0.at(0.95) { $0.squash(0.06).nod(12).earPerk(-20).eyes(.closedSleepy) }
            $0.end(in: .curled, at: 1.40) { $0.eyes(.closedSleepy) }
        },
        PipGesture("wake") {
            $0.at(0.30) { $0.nod(5).earPerk(-8).eyes(.half) }
            $0.at(0.80) { $0.nod(-3).earPerk(8).eyes(.open).mouth(.smallOpen) }
            $0.end(in: .standing, at: 1.20)
        },
    ]

    static var wake: PipGesture { named("wake") }

    /// Stands (or seats) Pip back up: the wake ends in the surface's resting body set.
    static func wake(endingIn set: PipPose.BodySet) -> PipGesture {
        var wake = self.wake
        wake.endSet = set
        return wake
    }

    /// The held pose a static Pip shows for a moment (Reduce Motion, Low Power, thermal): the key before the final settle.
    static func stillPose(for moment: PipMoment) -> PipPose {
        let keys = gesture(for: moment).keys
        return keys.count > 1 ? keys[keys.count - 2].pose : .rest
    }

    /// The idle beats that need body motion; blinks and glances use `blink(double:)` and `look(at:)` instead.
    static func gesture(forIdle beat: PipIdleScheduler.Beat, curled: Bool = false) -> PipGesture? {
        switch beat {
        case .blink, .doubleBlink, .glance: return nil
        case .earFlick: return named(curled ? "curled-ear-flick" : "idle-ear-flick")
        case .weightShift: return named("idle-weight-shift")
        case .yawn: return named("idle-yawn")
        case .stretch: return named("idle-stretch")
        case .hugTail: return named("idle-hug-tail")
        case .curlUp: return named("curl-up")
        }
    }

    /// The only mapping from app moments to gestures. Variants (hour of day, tap level) are picked here.
    static func gesture(for moment: PipMoment) -> PipGesture {
        switch moment {
        case .greeting(let hour):
            return named(5...11 ~= hour ? "greeting-morning" : hour >= 19 || hour <= 4 ? "greeting-evening" : "greeting")
        case .welcomeBack: return named("welcome-back")
        case .attentive: return named("attentive")
        case .submitted: return named("submitted")
        case .thinking: return named("thinking")
        case .saved: return named("saved")
        case .reviewed: return named("reviewed")
        case .recovery: return named("recovery")
        case .firstMealToday: return named("first-meal-today")
        case .dayComplete: return named("day-complete")
        case .curious: return named("curious")
        case .tapped(let level):
            let rotation = ["tap-giggle", "tap-ear-wiggle", "tap-wink", "tap-tail-flick"]
            return named(level >= 4 ? "shake-off" : rotation[max(level, 0)])
        case .patted: return named("patted")
        case .earTwitch: return named("ear-twitch")
        case .presenting(let cheer): return named(cheer ? "presenting-cheer" : "presenting-calm")
        }
    }

    static func loop(for moment: PipMoment) -> PipGesture? {
        let gesture = gesture(for: moment)
        return gesture.loops ? gesture : nil
    }

    static func named(_ name: String) -> PipGesture { all.first { $0.name == name }! }
}
