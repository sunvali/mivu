import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct ProfileTimezoneTests {
    @Test(arguments: ["America/Los_Angeles", "Asia/Tokyo"])
    func namedAndDefaultProfilesCaptureInjectedTimezone(zone: String) async throws {
        for createDefault in [false, true] {
            let path = URL.temporaryDirectory.appending(path: "ProfileTimezone-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: path) }
            let model = DiaryViewModel(store: DiaryStore(directory: path), deviceTimeZone: { TimeZone(identifier: zone)! })
            await model.load(createDefaultProfile: createDefault)
            if !createDefault { await model.createProfile(name: "Synthetic") }
            let id = try #require(model.readModel?.profile.id)
            let saved = try await completeSelectedProfile(DiaryStore(directory: path), id).profile
            #expect(saved.timeZoneID == zone)
        }
    }

    @Test func profileDefaultUsesDeviceTimezone() {
        #expect(adultProfile(name: "Synthetic").timeZoneID == TimeZone.current.identifier)
    }

    @Test func newProfileDoesNotRewriteExistingCalendarContext() async throws {
        let path = URL.temporaryDirectory.appending(path: "ProfileTimezone-" + UUID().uuidString)
        let restoredPath = URL.temporaryDirectory.appending(path: "ProfileTimezoneRestore-" + UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: path)
            try? FileManager.default.removeItem(at: restoredPath)
        }
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-19T22:30:00Z"))
        let store = DiaryStore(directory: path, currentTime: { instant })
        let profile = adultProfile(name: "Synthetic retained diary", timeZoneID: "Asia/Jerusalem")
        _ = try await store.createProfile(profile)
        _ = try await store.startDay(at: instant)
        _ = try await capturedTurn(store, text: "Synthetic late meal", photos: [], at: instant, expectedProfileID: profile.id)
        let original = try await store.snapshotForExport()
        let restored = DiaryStore(directory: restoredPath)
        _ = try await restored.importAdultFixture(original)
        let model = DiaryViewModel(store: restored, deviceTimeZone: { TimeZone(identifier: "America/Los_Angeles")! })
        await model.load(createDefaultProfile: false)
        await model.createProfile(name: "Synthetic new diary")
        let reopenedStore = DiaryStore(directory: restoredPath)
        let snapshot = try await completeSelectedProfile(reopenedStore, profile.id)
        let reopened = snapshot.profile
        #expect(reopened.timeZoneID == "Asia/Jerusalem")
        #expect(snapshot.days == original.days)
        #expect(snapshot.coachTurns == original.coachTurns)
    }
}
