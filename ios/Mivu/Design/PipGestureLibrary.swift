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
        // Progress: Pip, in reading glasses, keeps the chart card in its near paw the whole time (`prop-chart` is part of
        // the paw). Keys that raise it to read use `atChart`; the first key of each loop is its still pose.
        PipGesture("presenting-cheer", loops: true) {
            $0.at(0.35) { atChart($0).look(0.3, 1).nod(8).mouth(.smallOpen).earPerk(12).tailWag(14) }
            $0.at(0.95) { atChart($0, lift: 4).look(0.4, 0.9).nod(9).mouth(.smallOpen).earPerk(14).tailWag(-14) }
            $0.at(1.55) { atChart($0).look(0.3, 1).nod(8).mouth(.smallOpen).earPerk(12).tailWag(14) }
        },
        PipGesture("presenting-calm", loops: true) {
            $0.at(0.40) { atChart($0).look(0.3, 0.9).nod(7).mouth(.closedSmile).earPerk(8).tailWag(8) }
            $0.at(1.20) { atChart($0, lift: 3).look(0.4, 0.85).nod(8).mouth(.closedSmile).earPerk(10).tailWag(-8) }
            $0.at(2.00) { atChart($0).look(0.3, 0.9).nod(7).mouth(.closedSmile).earPerk(8).tailWag(8) }
        },
        // Opening the tab: a small hop in, then the card comes up.
        PipGesture("progress-entrance") {
            $0.at(0.12) { $0.squash(0.06).earPerk(-6) }
            $0.at(0.34) { $0.hop(10).earPerk(14).look(0.3, 0.6).tailWag(14) }
            $0.at(0.62) { atChart($0).look(0.3, 0.9).nod(6).mouth(.smallOpen).earPerk(10) }
            $0.at(0.92) { atChart($0).look(0.3, 1).nod(8).mouth(.smallOpen).earPerk(12).tailWag(-12) }
            $0.settle(at: 1.20)
        },
        // On an on-track period: the same, with a second happy hop. No hearts or points: it is about the trend, not food.
        PipGesture("progress-entrance-cheer") {
            $0.at(0.12) { $0.squash(0.06).earPerk(-6) }
            $0.at(0.34) { $0.hop(12).earPerk(16).look(0.3, 0.6).tailWag(16) }
            $0.at(0.58) { atChart($0).eyes(.closedHappy).mouth(.bigOpen).earPerk(14).scarf(-6) }
            $0.at(0.78) { atChart($0).hop(8).eyes(.closedHappy).mouth(.smallOpen).tailWag(-16) }
            $0.at(1.02) { atChart($0).look(0.3, 1).nod(8).mouth(.smallOpen).earPerk(12) }
            $0.settle(at: 1.30)
        },
        // Switching Week / Month / 3M / Year: ears up, eyes follow the new bars.
        PipGesture("progress-range") {
            $0.at(0.15) { atChart($0, lift: 4).earPerk(18).look(0.7, 0.7).eyes(.wide) }
            $0.at(0.48) { atChart($0).look(0.2, 1).nod(7).earPerk(10).mouth(.smallOpen) }
            $0.settle(at: 0.80)
        },
        // Taps on Progress Pip: six silly one-shots, one per tap, in turn.
        PipGesture("progress-tap-boing") {
            $0.at(0.10) { $0.squash(0.07).earPerk(-14).eyes(.closedHappy) }
            $0.at(0.32) { $0.hop(14).earPerk(22).eyes(.wide).mouth(.bigOpen).tailWag(24).scarf(-10) }
            $0.at(0.55) { $0.squash(0.06).earPerk(-10).mouth(.o) }
            $0.at(0.78) { $0.hop(8).earPerk(16).eyes(.closedHappy).mouth(.smallOpen).tailWag(-20) }
            $0.settle(at: 1.05)
        },
        PipGesture("progress-tap-dizzy") {
            $0.at(0.15) { $0.tilt(8).eyes(.closedSleepy).mouth(.o).look(-0.6, -0.2) }
            $0.at(0.35) { $0.tilt(-8).eyes(.closedSleepy).mouth(.o).look(0.6, -0.2) }
            $0.at(0.55) { $0.tilt(7).eyes(.half).mouth(.o).look(-0.5, 0.2) }
            $0.at(0.75) { $0.tilt(-6).eyes(.half).mouth(.smallOpen) }
            $0.at(0.95) { $0.nod(-4).earPerk(16).eyes(.wide).mouth(.smallOpen) }
            $0.settle(at: 1.20)
        },
        PipGesture("progress-tap-tail-chase") {
            $0.at(0.18) { $0.turn(0).look(-1, 0.4).tilt(-5).earPerk(14).tailWag(30).eyes(.wide) }
            $0.at(0.40) { $0.turn(0).hop(6).look(-1, 0.5).tilt(5).tailWag(-30).mouth(.o) }
            $0.at(0.62) { $0.turn(0).look(-1, 0.4).tilt(-5).tailWag(30).eyes(.closedHappy).mouth(.bigOpen) }
            $0.at(0.86) { $0.turn(1).earPerk(10).tailWag(-12).mouth(.smallOpen) }
            $0.settle(at: 1.15)
        },
        PipGesture("progress-tap-heart-eyes") {
            $0.at(0.18) { $0.eyes(.heart).blushing().mouth(.bigOpen).earPerk(14).tailWag(16) }
            $0.at(0.48) { $0.nod(-4).tilt(4).eyes(.heart).blushing().mouth(.smallOpen).tailWag(-16) }
            $0.at(0.80) { $0.tilt(-3).eyes(.heart).blushing().mouth(.bigOpen).tailWag(16) }
            $0.settle(at: 1.10)
        },
        PipGesture("progress-tap-surprise") {
            $0.at(0.08) { $0.squash(0.05).earPerk(24).eyes(.wide).mouth(.o) }
            $0.at(0.24) { $0.hop(12).earPerk(24).eyes(.wide).mouth(.o) }
            $0.at(0.52) { $0.nod(6).look(0.3, 1).mouth(.smallOpen) }
            $0.at(0.78) { atChart($0, lift: 4).eyes(.closedHappy).mouth(.bigOpen).tailWag(18) }
            $0.settle(at: 1.05)
        },
        PipGesture("progress-tap-sign-tap") {
            $0.at(0.15) { atChart($0, lift: 4).look(0.3, 1).mouth(.smallOpen) }
            $0.at(0.30) { atChart($0).look(0.3, 1).nod(4) }
            $0.at(0.45) { atChart($0, lift: 4).look(0.3, 1).mouth(.smallOpen) }
            $0.at(0.62) { atChart($0).nod(6).eyes(.closedHappy).mouth(.bigOpen).tailWag(16) }
            $0.settle(at: 1.05)
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

        // MARK: Upright: food and workouts
        // Two-legged Pip: the standing body has four feet down, so these need the upright set, played between `riseUp` and
        // `dropDown`. Beats are the storytelling poses; `PipBake` adds the curves and the follow-through, so give each move
        // its anticipation and overshoot here and leave ears, tail and scarf to the physics.
        PipGesture(beats: "rise-up") {
            $0.at(0) { $0.down() }
            $0.at(0.10) { $0.down().squash(0.09).nod(5).earPerk(-10).brow(4) }
            $0.at(0.15) { $0.down().squash(0.10).nod(6).earPerk(-12) }
            // The same crouch on the new body, tipped so the head lands where the four-legged one left it.
            $0.at(0.16) { $0.stance(drop: 24, lean: 10).spine(bend: 5).nod(6).earPerk(-12) }
            $0.at(0.34) { $0.stance(lift: 9).spine(stretch: 0.06).nod(-3).earPerk(8).tailWag(14).brow(5) }
            $0.at(0.50) { $0.stance(drop: 6).spine(stretch: -0.02).nod(2).tailWag(-8).burst(.dust, x: 316, y: 468) }
            $0.end(in: .upright, at: 0.70)
        },
        PipGesture(beats: "drop-down") {
            $0.at(0)
            $0.at(0.14) { $0.stance(lift: 0).spine(stretch: 0.04).nod(-3).earPerk(6) }
            $0.at(0.38) { $0.stance(drop: 24, lean: 10).spine(bend: 5).nod(6).earPerk(-6) }
            $0.at(0.39) { $0.down().squash(0.10).nod(6).earPerk(-8).burst(.dust, x: 316, y: 468) }
            $0.at(0.56) { $0.down().squash(-0.03).nod(-1).earPerk(4).tailWag(10) }
            $0.end(in: .standing, at: 0.80)
        },
        PipGesture(beats: "eat-apple") {
            $0.at(0)
            $0.at(0.14) { holdApple($0, .apple, x: 376, y: 368).look(0.5, 0.4) }
            $0.at(0.28) { holdApple($0, .apple, x: 386, y: 328).stance(drop: 3).nod(2).look(0.5, 0.7).eyes(.wide).earPerk(10).brow(6) }
            $0.at(0.46) { holdApple($0, .apple, x: 388, y: 326).nod(-2).spine(stretch: 0.03).look(0.5, 0.8).eyes(.wide).mouth(.bigOpen).earPerk(12).brow(8) }
            $0.at(0.60) { holdApple($0, .apple, x: 366, y: 298).spine(bend: 4, stretch: -0.02).nod(11).eyes(.closedHappy).mouth(.bigOpen) }
            $0.at(0.66) { holdApple($0, .apple, bites: 1, x: 366, y: 298).spine(bend: 4, stretch: -0.03).nod(12).eyes(.closedHappy).burst(.crumbs, x: 356, y: 258) }
            $0.at(0.84) { holdApple($0, .apple, bites: 1, x: 384, y: 328).stance(drop: 4).chew(0.035).eyes(.closedHappy).tailWag(10) }
            $0.at(0.94) { holdApple($0, .apple, bites: 1, x: 384, y: 328).stance(drop: 1).chew(-0.02).eyes(.closedHappy).tailWag(-6) }
            $0.at(1.04) { holdApple($0, .apple, bites: 1, x: 384, y: 328).stance(drop: 4).chew(0.035).eyes(.closedHappy).tailWag(10) }
            $0.at(1.14) { holdApple($0, .apple, bites: 1, x: 386, y: 326).chew(-0.02).look(0.5, 0.8).earPerk(8).brow(5) }
            $0.at(1.26) { holdApple($0, .apple, bites: 1, x: 366, y: 298).spine(bend: 4, stretch: -0.02).nod(11).eyes(.closedHappy).mouth(.bigOpen) }
            $0.at(1.32) { holdApple($0, .apple, bites: 2, x: 366, y: 298).spine(bend: 4, stretch: -0.03).nod(12).eyes(.closedHappy).burst(.crumbs, x: 356, y: 258) }
            $0.at(1.48) { holdApple($0, .apple, bites: 2, x: 384, y: 332).stance(drop: 4).chew(0.035).eyes(.closedHappy).tailWag(12) }
            $0.at(1.58) { holdApple($0, .apple, bites: 2, x: 384, y: 332).stance(drop: 1).chew(-0.02).eyes(.closedHappy).tailWag(-8) }
            $0.at(1.70) { holdApple($0, .apple, bites: 2, x: 380, y: 338).spine(stretch: 0.03).nod(-3).eyes(.closedHappy).blushing().earPerk(12).tailWag(14).brow(4) }
            $0.at(1.76) { $0.reach(.right, x: 380, y: 346, paw: 90).reach(.left, x: 276, y: 366, paw: 60).eyes(.closedHappy).blushing() }
            $0.settle(at: 2.00)
        },
        PipGesture(beats: "eat-bowl") {
            $0.at(0)
            $0.at(0.14) { spoon($0, x: 372, y: 368, paw: -100).look(0, 0.6) }
            $0.at(0.30) { spoon($0, x: 336, y: 348, paw: -130).nod(5).look(0, 1).earPerk(8) }
            $0.at(0.38) { spoon($0, x: 332, y: 356, paw: -130).nod(6).look(0, 1).stance(drop: 3) }
            $0.at(0.56) { spoon($0, x: 356, y: 312, paw: 176).nod(1).look(0.4, 0.7).mouth(.bigOpen).earPerk(6) }
            $0.at(0.68) { spoon($0, x: 350, y: 300, paw: 176).spine(bend: 3, stretch: -0.02).nod(9).eyes(.closedHappy).mouth(.bigOpen) }
            $0.at(0.74) { spoon($0, x: 352, y: 304, paw: 176).spine(bend: 3, stretch: -0.02).nod(9).eyes(.closedHappy) }
            $0.at(0.90) { spoon($0, x: 364, y: 332, paw: -160).stance(drop: 4).chew(0.035).eyes(.closedHappy).tailWag(10) }
            $0.at(1.00) { spoon($0, x: 364, y: 332, paw: -160).stance(drop: 1).chew(-0.02).eyes(.closedHappy).tailWag(-6) }
            $0.at(1.10) { spoon($0, x: 364, y: 332, paw: -160).stance(drop: 4).chew(0.03).eyes(.closedHappy).tailWag(10) }
            $0.at(1.30) { spoon($0, x: 334, y: 354, paw: -130).nod(6).look(0, 1) }
            $0.at(1.52) { spoon($0, x: 356, y: 312, paw: 176).nod(1).look(0.4, 0.7).mouth(.bigOpen) }
            $0.at(1.62) { spoon($0, x: 350, y: 300, paw: 176).spine(bend: 3, stretch: -0.02).nod(9).eyes(.closedHappy).mouth(.bigOpen) }
            $0.at(1.68) { spoon($0, x: 352, y: 304, paw: 176).spine(bend: 3, stretch: -0.02).nod(9).eyes(.closedHappy) }
            $0.at(1.76) { $0.reach(.right, x: 380, y: 346, paw: 90).reach(.left, x: 268, y: 362, paw: 60).chew(0.03).eyes(.closedHappy) }
            $0.settle(at: 2.00)
        },
        PipGesture(beats: "sip-water") {
            $0.at(0)
            $0.at(0.14) { sip($0, x: 376, y: 368, paw: -160).look(0.5, 0.4) }
            $0.at(0.28) { sip($0, x: 388, y: 326, paw: 180).look(0.5, 0.7).earPerk(8).stance(drop: 3) }
            $0.at(0.48) { sip($0, x: 366, y: 292, paw: 160).spine(bend: -3, stretch: 0.02).nod(-7).mouth(.o).eyes(.closedHappy) }
            $0.at(0.80) { sip($0, x: 364, y: 286, paw: 150).spine(bend: -7, stretch: 0.03).nod(-12).mouth(.o).eyes(.closedHappy).tailWag(8).brow(4) }
            $0.at(1.10) { sip($0, x: 362, y: 282, paw: 140).spine(bend: -8, stretch: 0.03).nod(-13).mouth(.o).eyes(.closedHappy).tailWag(-6) }
            $0.at(1.32) { sip($0, x: 386, y: 326, paw: 180).stance(drop: 4).nod(4).mouth(.smallOpen).eyes(.closedHappy).burst(.drops, x: 348, y: 246) }
            $0.at(1.54) { sip($0, x: 386, y: 330, paw: 180).spine(stretch: 0.03).nod(-2).eyes(.closedHappy).blushing().earPerk(10).tailWag(12) }
            $0.at(1.70) { $0.reach(.right, x: 378, y: 362, paw: 40).reach(.left, x: 276, y: 366, paw: 60).eyes(.closedHappy).blushing() }
            $0.settle(at: 1.90)
        },
        // After a meal: full and content, paws patting the belly while the weight rocks from side to side.
        PipGesture(beats: "eat-yum") {
            $0.at(0)
            $0.at(0.30) { belly($0, y: 366).spine(bend: 3).stance(drop: 3, sway: 2).eyes(.closedHappy).mouth(.smallOpen).earPerk(8) }
            $0.at(0.50) { belly($0, y: 356).spine(bend: -3).stance(drop: 0, sway: -2).turn(0).eyes(.closedHappy).blushing().hearts(1).tailWag(14) }
            $0.at(0.70) { belly($0, y: 366).spine(bend: 3).stance(drop: 3, sway: 2).turn(0).eyes(.closedHappy).blushing().hearts(1, drift: 12).tailWag(-14) }
            $0.at(0.90) { belly($0, y: 356).spine(bend: -3).stance(drop: 0, sway: -2).turn(0).eyes(.closedHappy).blushing().hearts(1, drift: 24).tailWag(14) }
            $0.at(1.08) { belly($0, y: 364).spine(bend: 1).stance(drop: 2).eyes(.closedHappy).blushing().hearts(1, drift: 34) }
            $0.settle(at: 1.40)
        },
        // Each rep starts and ends on the plain upright pose, so a loop can begin from the rise and hand over to the drop.
        PipGesture(beats: "workout-squat", loops: true) {
            let top: (PipBeat) -> PipBeat = { $0.turn(0).reach(.left, x: 250, y: 376, paw: 8).reach(.right, x: 382, y: 376, paw: -8) }
            let bottom: (PipBeat) -> PipBeat = { $0.turn(0).reach(.left, x: 298, y: 326, paw: 150).reach(.right, x: 334, y: 326, paw: -150).mouth(.smallOpen) }
            $0.at(0) { $0.turn(0) }
            $0.at(0.20) { top($0).spine(stretch: 0.025).nod(-2).earPerk(6) }
            $0.at(0.72) { bottom($0).stance(drop: 30).spine(stretch: -0.02).nod(4).look(0, 0.3).brow(-4) }
            $0.at(0.90) { bottom($0).stance(drop: 33).spine(stretch: -0.03).nod(5).look(0, 0.3).brow(-5) }
            $0.at(1.26) { top($0).stance().spine(stretch: 0.045).nod(-3).earPerk(8).eyes(.closedHappy).tailWag(12).brow(4) }
            $0.at(1.46) { top($0).stance(drop: 3).eyes(.closedHappy) }
            $0.at(1.70) { $0.turn(0) }
        },
        PipGesture(beats: "workout-jumping-jack", loops: true) {
            let down: (PipBeat, CGFloat) -> PipBeat = { beat, out in
                beat.turn(0).reach(.left, x: 268 - out, y: 382, paw: 8).reach(.right, x: 364 + out, y: 382, paw: -8)
            }
            // Short of full reach: a straight arm's elbow snaps as it passes, a nearly straight one swings through.
            let wide: (PipBeat, CGFloat, CGFloat, CGFloat) -> PipBeat = { beat, out, height, paw in
                beat.turn(0).reach(.left, x: out, y: height, paw: paw).reach(.right, x: 632 - out, y: height, paw: -paw)
            }
            $0.at(0) { $0.turn(0) }
            $0.at(0.12) { down($0, 4).stance(drop: 13).spine(stretch: -0.04).look(0, 0.2).brow(-3) }
            $0.at(0.28) { wide($0, 192, 300, 90).stance(drop: 6, spread: 16, lift: 32).spine(stretch: 0.05).mouth(.smallOpen).brow(5) }
            $0.at(0.40) { wide($0, 212, 232, 130).stance(drop: 17, spread: 30).spine(stretch: -0.03).eyes(.closedHappy).mouth(.bigOpen).burst(.dust, x: 316, y: 468) }
            $0.at(0.50) { wide($0, 226, 216, 145).stance(drop: 20, spread: 30).spine(stretch: -0.05).eyes(.closedHappy).mouth(.bigOpen) }
            $0.at(0.66) { wide($0, 192, 300, 90).stance(drop: 6, spread: 15, lift: 28).spine(stretch: 0.05).mouth(.smallOpen) }
            $0.at(0.78) { down($0, 14).stance(drop: 12).spine(stretch: -0.03).mouth(.smallOpen).burst(.dust, x: 316, y: 468) }
            $0.at(0.92) { down($0, 2).stance(drop: 3) }
            $0.at(1.08) { $0.turn(0) }
        },
        PipGesture(beats: "workout-side-bend", loops: true) {
            let right: (PipBeat, CGFloat) -> PipBeat = { beat, amount in
                beat.turn(0).reach(.right, x: 414, y: 214, paw: -150).reach(.left, x: 264, y: 366, paw: 60)
                    .stance(drop: 5, lean: -3 * amount, sway: 7 * amount).spine(bend: -15 * amount).eyes(.closedHappy)
            }
            let left: (PipBeat, CGFloat) -> PipBeat = { beat, amount in
                beat.turn(0).reach(.left, x: 218, y: 214, paw: 150).reach(.right, x: 368, y: 366, paw: -60)
                    .stance(drop: 5, lean: 3 * amount, sway: -7 * amount).spine(bend: 15 * amount).eyes(.closedHappy)
            }
            $0.at(0) { $0.turn(0) }
            $0.at(0.58) { right($0, 1).tailWag(14) }
            $0.at(0.94) { right($0, 1.12).tailWag(16) }
            $0.at(1.40) { $0.turn(0).stance(drop: 3).look(0.2, 0) }
            $0.at(1.98) { left($0, 1).tailWag(-14) }
            $0.at(2.34) { left($0, 1.12).tailWag(-16) }
            $0.at(2.80) { $0.turn(0) }
        },
        // Paws on knees, panting, then the brow gets wiped and the breath comes back.
        PipGesture(beats: "workout-breather") {
            let knees: (PipBeat, CGFloat) -> PipBeat = { beat, puff in
                beat.turn(0).stance(drop: 15 - puff * 4).reach(.left, x: 262, y: 382, paw: 10).reach(.right, x: 370, y: 382, paw: -10)
                    .spine(stretch: puff * 0.03).nod(6).eyes(.closedHappy).earPerk(-10)
            }
            $0.at(0)
            $0.at(0.26) { knees($0, 0).mouth(.bigOpen) }
            $0.at(0.42) { knees($0, 1).mouth(.smallOpen).brow(-3).burst(.drops, x: 300, y: 160) }
            $0.at(0.58) { knees($0, 0).mouth(.bigOpen) }
            $0.at(0.74) { knees($0, 1).mouth(.smallOpen) }
            $0.at(1.04) { $0.turn(0).reach(.right, x: 402, y: 236, paw: -130).spine(stretch: 0.03).nod(-3).eyes(.closedHappy).mouth(.smallOpen).earPerk(4) }
            $0.at(1.24) { $0.turn(0).reach(.right, x: 372, y: 208, paw: -110).spine(bend: -3, stretch: 0.03).nod(-5).eyes(.closedHappy).earPerk(8).tailWag(10) }
            $0.at(1.42) { $0.turn(0).reach(.right, x: 392, y: 300, paw: -60).stance(drop: 5).nod(3).eyes(.closedHappy).mouth(.closedSmile).tailWag(-8).burst(.drops, x: 372, y: 230) }
            $0.settle(at: 1.80)
        },
        PipGesture(beats: "stretch-reach") {
            let overhead: (PipBeat, CGFloat, CGFloat) -> PipBeat = { beat, out, height in
                beat.turn(0).reach(.left, x: 216 - out, y: height, paw: 150).reach(.right, x: 416 + out, y: height, paw: -150)
            }
            $0.at(0) { $0.turn(0) }
            $0.at(0.30) { $0.turn(0).stance(drop: 10).spine(stretch: -0.03).nod(3).earPerk(-6).reach(.left, x: 276, y: 372, paw: 20).reach(.right, x: 356, y: 372, paw: -20) }
            $0.at(0.72) { overhead($0, 0, 222).stance(lift: 0).spine(stretch: 0.05).nod(-6).eyes(.closedHappy).mouth(.smallOpen).earPerk(10).tailWag(12) }
            $0.at(1.14) { overhead($0, 8, 216).spine(bend: 2, stretch: 0.07).nod(-7).eyes(.closedHappy).mouth(.smallOpen).earPerk(14).tailWag(16).brow(5) }
            $0.at(1.42) { overhead($0, 4, 222).spine(bend: -2, stretch: 0.06).nod(-6).eyes(.closedHappy).mouth(.smallOpen).earPerk(12).tailWag(-8) }
            $0.at(1.70) { $0.turn(0).stance(drop: 7).spine(stretch: -0.02).nod(3).eyes(.closedHappy) }
            $0.settle(at: 1.98)
        },
        // Weight onto the left foot, sole to the knee, paws at the heart; the arms and hips correct a wobble.
        PipGesture(beats: "yoga-tree") {
            let tree: (PipBeat, CGFloat) -> PipBeat = { beat, wobble in
                beat.turn(0).stance(drop: 4, lean: wobble * 0.5, sway: -13 + wobble).tuck(x: -36, y: -36, foot: -40).spine(bend: -wobble * 1.4)
                    .reach(.left, x: 298, y: 330, paw: 150).reach(.right, x: 334, y: 330, paw: -150)
            }
            $0.at(0) { $0.turn(0) }
            $0.at(0.34) { $0.turn(0).stance(drop: 5, sway: -13).look(-0.3, 0.2) }
            $0.at(0.62) { tree($0, -3).look(-0.2, 0.3) }
            $0.at(0.88) { tree($0, 2.5).eyes(.closedHappy) }
            $0.at(1.14) { tree($0, -1.5).eyes(.closedHappy).tailWag(8) }
            $0.at(1.40) { tree($0, 0.6).eyes(.closedHappy).tailWag(-8) }
            $0.at(1.62) { $0.turn(0).stance(drop: 5, sway: -7).eyes(.closedHappy) }
            $0.settle(at: 1.92)
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
    static var riseUp: PipGesture { named("rise-up") }

    /// Back down from the upright body onto the surface's resting set.
    static func dropDown(endingIn set: PipPose.BodySet) -> PipGesture {
        var drop = named("drop-down")
        drop.endSet = set
        return drop
    }

    /// The right paw holds the food; the other tucks to the chest so it never hangs dead.
    private static func holdApple(_ beat: PipBeat, _ prop: PipPose.Prop, bites: Int = 0, x: CGFloat, y: CGFloat) -> PipBeat {
        beat.holding(prop, bites: bites).reach(.right, x: x, y: y, paw: 180).reach(.left, x: 300, y: 340, paw: 120)
    }

    /// The bowl stays level in the far paw while the spoon travels.
    private static func spoon(_ beat: PipBeat, x: CGFloat, y: CGFloat, paw: CGFloat) -> PipBeat {
        beat.holding(.bowl).reach(.left, x: 292, y: 366, paw: 180).reach(.right, x: x, y: y, paw: paw)
    }

    private static func sip(_ beat: PipBeat, x: CGFloat, y: CGFloat, paw: CGFloat) -> PipBeat {
        beat.holding(.cup).reach(.right, x: x, y: y, paw: paw).reach(.left, x: 300, y: 340, paw: 120)
    }

    private static func belly(_ beat: PipBeat, y: CGFloat) -> PipBeat {
        beat.reach(.left, x: 304, y: y, paw: 90).reach(.right, x: 330, y: y + 6, paw: -90)
    }

    /// Stands (or seats) Pip back up: the wake ends in the surface's resting body set.
    static func wake(endingIn set: PipPose.BodySet) -> PipGesture {
        var wake = self.wake
        wake.endSet = set
        return wake
    }

    /// The card arm of the hold, which Progress keeps whenever a pose leaves that arm alone (`PipRigView.showsProgressProps`).
    static let progressHeldArm = atChart(.rest).joints.filter { ["arm-r", "forearm-r", "paw-r"].contains($0.key) }

    /// The near front paw raised so Pip can read the chart card in it; `lift` swings the shoulder a few degrees more.
    private static func atChart(_ pose: PipPose, lift: CGFloat = 0) -> PipPose {
        pose.pawUp(.right, -45 - lift, elbow: -60)
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
        case .progressEntrance(let cheer): return named(cheer ? "progress-entrance-cheer" : "progress-entrance")
        case .progressRange: return named("progress-range")
        case .progressTap(let level):
            let rotation = ["progress-tap-boing", "progress-tap-dizzy", "progress-tap-tail-chase",
                            "progress-tap-heart-eyes", "progress-tap-surprise", "progress-tap-sign-tap"]
            return named(rotation[max(level, 0) % rotation.count])
        case .workoutSaved(let activity):
            switch activity {
            case "strength", "hiit", "crossfit": return onTwoLegs("workout-squat")
            case "yoga", "pilates": return onTwoLegs("yoga-tree")
            case "stretching", "mobility": return onTwoLegs("stretch-reach")
            default: return onTwoLegs("workout-jumping-jack")
            }
        case .workoutDone(let hard): return onTwoLegs(hard ? "workout-breather" : "stretch-reach")
        }
    }

    /// An upright move as one moment: Pip rises, does the move (a loop twice) and drops back down, baked as one curve so
    /// the follow-through carries across the joins. Each part starts on the pose the one before ended on.
    /// Its keys are only for a still Pip: four legs cannot hold an upright pose, so it keeps the face from mid-move.
    private static func onTwoLegs(_ name: String) -> PipGesture {
        let move = named(name)
        var beats: [PipBeat] = []
        func append(_ part: [PipBeat]) {
            // On a frame, so each part bakes on the same frames as alone: the drop's swap to four legs is 0.01 s wide.
            let start = (((beats.popLast()?.at ?? 0) * PipBake.rate - 0.001).rounded(.up)) / PipBake.rate
            beats += part.map { var beat = $0; beat.at += start; return beat }
        }
        append(riseUp.beats)
        let held = beats.last!.at + move.beats[move.beats.count / 2].at
        for _ in 0..<(move.loops ? 2 : 1) { append(move.beats) }
        append(named("drop-down").beats)
        var gesture = PipGesture(name: name, keys: [(0, .rest), (held, move.beats[move.beats.count / 2].down().pose), (beats.last!.at, .rest)],
                                 stance: .upright)
        gesture.beats = beats
        return gesture
    }

    static func loop(for moment: PipMoment) -> PipGesture? {
        let gesture = gesture(for: moment)
        return gesture.loops ? gesture : nil
    }

    static func named(_ name: String) -> PipGesture { all.first { $0.name == name }! }
}
