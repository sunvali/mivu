import Foundation
import Testing
@testable import Mivu

@Suite struct WidgetSnapshotTests {
    let sample = WidgetSnapshot(day: "2026-10-20", eaten: 1359.6, target: 2000, hasDiary: true,
                                rolloverAt: Date(timeIntervalSince1970: 1_000), writtenAt: Date(timeIntervalSince1970: 0))

    @Test func roundTripsThroughFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        try sample.write(to: url)
        #expect(WidgetSnapshot.read(from: url) == sample)
    }

    @Test func missingOrCorruptFileReadsNil() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        #expect(WidgetSnapshot.read(from: url) == nil)
        try Data("{".utf8).write(to: url)
        #expect(WidgetSnapshot.read(from: url) == nil)
    }

    @Test func ringCapsWhenOverTargetAndIsEmptyWithoutTarget() {
        var snapshot = sample; snapshot.eaten = 2300
        #expect(snapshot.ringFraction == 1)
        snapshot.target = nil
        #expect(snapshot.ringFraction == 0)
    }

    @Test func afterRolloverKeepsTargetAndZeroesEaten() {
        let next = sample.afterRollover()
        #expect(next.eaten == 0 && next.target == 2000 && next.hasDiary)
    }

    @Test func rolloverUsesTheDaysTimeZone() throws {
        // 23:00 UTC on the 20th is 02:00 on the 21st in Jerusalem; the next 4 AM there is 01:00 UTC on the 21st.
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-20T23:00:00Z"))
        let next = WidgetSnapshot.nextRollover(after: now, timeZoneID: "Asia/Jerusalem", cutoffHour: 4)
        #expect(next == ISO8601DateFormatter().date(from: "2026-10-21T01:00:00Z"))
    }
}
