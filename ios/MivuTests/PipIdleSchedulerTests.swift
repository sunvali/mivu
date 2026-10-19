import Foundation
import Testing
@testable import Mivu

/// SplitMix64: deterministic draws for the scheduler.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct PipIdleSchedulerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func scheduler(_ seed: UInt64 = 7) -> PipIdleScheduler { PipIdleScheduler(random: SeededGenerator(state: seed)) }

    /// Draws `count` beats, each made when the previous one is due, with no input after `start`.
    private func draws(_ count: Int, quietFor quiet: TimeInterval, surface: CompanionSurface, seed: UInt64 = 7)
        -> [(beat: PipIdleScheduler.Beat, quiet: TimeInterval, gap: TimeInterval)] {
        var scheduler = scheduler(seed)
        var now = start.addingTimeInterval(quiet)
        var result: [(PipIdleScheduler.Beat, TimeInterval, TimeInterval)] = []
        for _ in 0..<count {
            let next = scheduler.next(after: start, now: now, surface: surface)
            result.append((next.beat, now.timeIntervalSince(start), next.at.timeIntervalSince(now)))
            now = next.at
        }
        return result
    }

    @Test func commonBeatsSpacedTwoToSixSeconds() {
        for draw in draws(200, quietFor: 0, surface: .today) { #expect((2.0...6.0).contains(draw.gap), "\(draw.gap)") }
    }

    @Test func noYawnBeforeThirtySecondsOfQuiet() {
        for seed in 1...5 as ClosedRange<UInt64> {
            for draw in draws(100, quietFor: 0, surface: .coach, seed: seed) where draw.quiet < 30 {
                #expect(draw.beat != .yawn && draw.beat != .stretch, "\(draw.beat) at \(draw.quiet) s")
            }
        }
        #expect(draws(200, quietFor: 30, surface: .coach).contains { $0.beat == .yawn })
    }

    @Test func curlOnlyOnTodayAfterNinetySeconds() {
        let early = draws(300, quietFor: 0, surface: .today)
        for draw in early where draw.quiet < 90 { #expect(draw.beat != .hugTail && draw.beat != .curlUp) }
        let late = draws(40, quietFor: 90, surface: .today).map(\.beat)
        let hug = late.firstIndex(of: .hugTail)
        #expect(hug != nil)
        #expect(late.firstIndex(of: .curlUp) == hug.map { $0 + 1 }, "curl follows the hug")
    }

    @Test func coachNeverCurls() {
        for draw in draws(500, quietFor: 600, surface: .coach) { #expect(draw.beat != .hugTail && draw.beat != .curlUp) }
    }

    @Test func neverRepeatsABeatAndVariesTheGlance() {
        let beats = draws(300, quietFor: 40, surface: .coach).map(\.beat)
        for pair in zip(beats, beats.dropFirst()) { #expect(pair.0 != pair.1) }
        #expect(beats.contains(.doubleBlink))
        #expect(Set(beats.compactMap { if case .glance(let p) = $0 { p } else { nil } }).count > 3)
    }

    @Test func inputWakesAndRestartsTheCurl() {
        var scheduler = scheduler()
        var now = start.addingTimeInterval(95)
        var beats: [PipIdleScheduler.Beat] = []
        while beats.last != .curlUp {
            let next = scheduler.next(after: start, now: now, surface: .today)
            beats.append(next.beat)
            now = next.at
        }
        let curled = scheduler.next(after: start, now: now, surface: .today).beat
        #expect(curled == .blink || curled == .doubleBlink || curled == .earFlick, "asleep Pip only blinks and flicks an ear")
        let input = now.addingTimeInterval(1)
        let fresh = scheduler.next(after: input, now: input, surface: .today).beat
        #expect(fresh != .curlUp && fresh != .hugTail)
    }
}
