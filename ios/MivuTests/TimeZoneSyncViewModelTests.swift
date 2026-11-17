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

    private func seedPending(_ model: DiaryViewModel, _ defaults: UserDefaults) throws -> UUID {
        let id = try #require(model.readModel?.profile.id)
        let last = TimeZoneSwitch(from: "America/New_York", to: "Asia/Jerusalem", at: noon, announced: false)
        TimeZoneStateStore(defaults: defaults).save(TimeZoneState(mode: .automatic, knownProfileZone: "Asia/Jerusalem", lastSwitch: last), for: id)
        return id
    }

    @Test func unannouncedSwitchShowsOnlyOnTheSameWakingDay() async throws {
        let p = path(); defer { try? FileManager.default.removeItem(at: p) }
        let (model, defaults) = try await model(profileZone: "Asia/Jerusalem", device: Zone("Asia/Jerusalem"), p)
        _ = try seedPending(model, defaults)
        await model.syncTimeZone(now: noon.addingTimeInterval(2 * 86_400))
        #expect(model.timeZoneNotice == nil)
        await model.syncTimeZone(now: noon.addingTimeInterval(3600))
        #expect(model.timeZoneNotice?.from == "America/New_York")
        model.markTimeZoneNoticeShown()
        #expect(model.timeZoneNotice == nil)
        await model.syncTimeZone(now: noon.addingTimeInterval(7200))
        #expect(model.timeZoneNotice == nil)
    }

    @Test func switchingProfilesDropsTheOtherProfilesNoticeAndLoadsItsMode() async throws {
        let p = path(); defer { try? FileManager.default.removeItem(at: p) }
        let (model, defaults) = try await model(profileZone: "Asia/Jerusalem", device: Zone("Asia/Jerusalem"), p)
        _ = try seedPending(model, defaults)
        await model.syncTimeZone(now: noon.addingTimeInterval(3600))
        #expect(model.timeZoneNotice != nil)
        let other = try await model.store.createProfile(DiaryProfile(name: "Synthetic B", timeZoneID: "Asia/Tokyo")).head.profile.id
        TimeZoneStateStore(defaults: defaults).save(TimeZoneState(mode: .pinned(zone: "Asia/Tokyo", untilDeviceZone: nil), knownProfileZone: "Asia/Tokyo"), for: other)
        await model.switchProfile(other)
        #expect(model.timeZoneNotice == nil)
        #expect(model.timeZoneMode == .pinned(zone: "Asia/Tokyo", untilDeviceZone: nil))
    }

    @Test func failedProfileWriteLeavesTheStateForTheNextSync() async throws {
        let p = path(); defer { try? FileManager.default.removeItem(at: p) }
        let device = Zone("Asia/Jerusalem")
        let (model, defaults) = try await model(profileZone: "Asia/Jerusalem", device: device, p)
        await model.syncTimeZone(now: noon)
        let id = try #require(model.readModel?.profile.id), before = TimeZoneStateStore(defaults: defaults).state(for: id)
        await model.store.signOut() // the store refuses writes for a deselected profile
        device.id = "America/New_York"
        await model.syncTimeZone(now: noon)
        #expect(TimeZoneStateStore(defaults: defaults).state(for: id) == before)
        #expect(model.timeZoneNotice == nil)
    }

    @Test func syncSkipsWhileCoachIsSending() {
        #expect(MivuServices.shouldSync(isSending: true) == false)
        #expect(MivuServices.shouldSync(isSending: false))
    }
}
