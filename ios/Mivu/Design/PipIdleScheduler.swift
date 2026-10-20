import CoreGraphics
import Foundation

/// Picks Pip's next idle beat and when to play it. Pure and seedable; the caller plays the beat and
/// skips it when anything higher priority (typing, feedback, taps, motion policy) is active.
struct PipIdleScheduler {
    enum Beat: Equatable {
        case blink, doubleBlink, glance(CGPoint), earFlick, weightShift, yawn, stretch, hugTail, curlUp
    }

    private struct Generator: RandomNumberGenerator {
        var base: any RandomNumberGenerator
        mutating func next() -> UInt64 { base.next() }
    }

    private var random: Generator
    private var last: Beat?
    /// Set after a hug; the curl follows unless the user has touched Pip since.
    private var hugged: Date?
    private var curled: Date?

    init(random: some RandomNumberGenerator) { self.random = Generator(base: random) }

    /// The beat to play at `at`, 2-6 s after `now`. Yawn and stretch need 30 s of quiet; on Today, a tail hug and
    /// then a curl-up need 90 s. A curled Pip only blinks and flicks an ear until the next input.
    mutating func next(after lastInput: Date, now: Date, surface: CompanionSurface) -> (beat: Beat, at: Date) {
        let quiet = now.timeIntervalSince(lastInput)
        if let hugged, hugged < lastInput { self.hugged = nil }
        if let curled, curled < lastInput { self.curled = nil }
        var choices: [(beat: Beat, weight: Double)]
        if curled != nil {
            choices = [(.blink, 5), (.doubleBlink, 1), (.earFlick, 2)]
        } else if hugged != nil, surface == .today { // Coach never curls, even after a hug on Today
            choices = [(.curlUp, 1)]
        } else {
            choices = [(.blink, 5), (.doubleBlink, 1), (.glance(glanceTarget()), 3), (.earFlick, 2), (.weightShift, 2)]
            if quiet >= 30 { choices += [(.yawn, 1), (.stretch, 1)] }
            if quiet >= 90, surface == .today { choices.append((.hugTail, 3)) }
        }
        // Never the same beat twice in a row, so no loop shows.
        let fresh = choices.filter { !Self.sameKind($0.beat, last) }
        if !fresh.isEmpty { choices = fresh }
        var roll = Double.random(in: 0..<choices.reduce(0) { $0 + $1.weight }, using: &random)
        let beat = choices.first { roll -= $0.weight; return roll < 0 }?.beat ?? choices[0].beat
        last = beat
        if beat == .hugTail { hugged = now }
        if beat == .curlUp { curled = now; hugged = nil }
        return (beat, now.addingTimeInterval(.random(in: 2...6, using: &random)))
    }

    private mutating func glanceTarget() -> CGPoint {
        CGPoint(x: .random(in: -0.9...0.9, using: &random), y: .random(in: -0.4...0.4, using: &random))
    }

    private static func sameKind(_ a: Beat, _ b: Beat?) -> Bool {
        if case .glance = a, case .glance? = b { return true }
        return a == b
    }
}
