import Foundation
import Testing
@testable import Mivu

private final class Zone: @unchecked Sendable { var id: String; init(_ id: String) { self.id = id } }

@Suite @MainActor struct TimeZoneSyncViewModelTests {
    private func model(profileZone: String, device: Zone, _ path: URL) async throws -> (DiaryViewModel, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "TimeZoneSyncVM-" + UUID().uuidString))
        let store = DiaryStore(directory: path)
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic", timeZoneID: profileZone))
        let model = DiaryViewModel(store: store, preferences: defaults, deviceTimeZone: { TimeZone(identifier: device.id)! })
        await model.load(createDefaultProfile: false)
        return (model, defaults)
    }
    private func path() -> URL { URL.temporaryDirectory.appending(path: "TimeZoneSyncVM-" + UUID().uuidString) }
    private let noon = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func automaticSyncMovesTheProfileAndRaisesTheNotice() async throws {
        let p = path(); defer { try? FileManager.default.removeItem(at: p) }
        let device = Zone("Asia/Jerusalem")
        let (model, _) = try await model(profileZone: "Asia/Jerusalem", device: device, p)
        await model.syncTimeZone(now: noon)
        #expect(model.timeZoneMode == .automatic)
        device.id = "America/New_York"
        await model.syncTimeZone(now: noon)
        #expect(model.readModel?.profile.timeZoneID == "America/New_York")
        #expect(model.timeZoneNotice?.from == "Asia/Jerusalem")
    }

    @Test func keepPreviousRestoresAndPinsUntilHome() async throws {
        let p = path(); defer { try? FileManager.default.removeItem(at: p) }
        let device = Zone("Asia/Jerusalem")
        let (model, _) = try await model(profileZone: "Asia/Jerusalem", device: device, p)
        await model.syncTimeZone(now: noon)
        device.id = "America/New_York"
        await model.syncTimeZone(now: noon)
        await model.keepPreviousTimeZone()
        #expect(model.readModel?.profile.timeZoneID == "Asia/Jerusalem")
        #expect(model.timeZoneMode == .pinned(zone: "Asia/Jerusalem", untilDeviceZone: "Asia/Jerusalem"))
        await model.syncTimeZone(now: noon.addingTimeInterval(7200))
        #expect(model.readModel?.profile.timeZoneID == "Asia/Jerusalem")
    }

    @Test func existingPinnedProfileStaysPinnedOnFirstLaunch() async throws {
        let p = path(); defer { try? FileManager.default.removeItem(at: p) }
        let (model, _) = try await model(profileZone: "Asia/Tokyo", device: Zone("Asia/Jerusalem"), p)
        await model.syncTimeZone(now: noon)
        #expect(model.readModel?.profile.timeZoneID == "Asia/Tokyo")
        #expect(model.timeZoneMode == .pinned(zone: "Asia/Tokyo", untilDeviceZone: nil))
    }

    @Test func syncSkipsWhileCoachIsSending() {
        #expect(MivuServices.shouldSync(isSending: true) == false)
        #expect(MivuServices.shouldSync(isSending: false))
    }
}
