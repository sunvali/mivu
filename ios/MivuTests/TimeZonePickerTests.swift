import Foundation
import Testing
@testable import Mivu

struct TimeZonePickerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func searchFindsNewYorkByCity() {
        #expect(TimeZoneCatalog.entries(matching: "new york", at: now).first?.id == "America/New_York")
        #expect(TimeZoneCatalog.entries(matching: "america/new", at: now).contains { $0.id == "America/New_York" })
    }

    @Test func offsetFormatting() {
        let offset = { (id: String) in TimeZoneCatalog.entries(matching: id, at: now).first { $0.id == id }?.offset }
        #expect(offset("Asia/Tokyo") == "GMT+9")
        // `now` is 2027-01-15, standard time: a true minus sign, and minutes only when the offset has them.
        #expect(offset("America/New_York") == "GMT−5")
        #expect(offset("Asia/Calcutta") == "GMT+5:30")
        #expect(offset("GMT") == "GMT")
    }

    @Test func emptyQueryListsEveryZoneSortedByCity() {
        let all = TimeZoneCatalog.entries(matching: "", at: now)
        #expect(all.count == TimeZone.knownTimeZoneIdentifiers.count)
        #expect(all.map(\.city) == all.map(\.city).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }
}
