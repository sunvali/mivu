import Foundation
import Testing
@testable import Mivu

struct TimeZoneSyncTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func auto(_ zone: String) -> TimeZoneState { TimeZoneState(mode: .automatic, knownProfileZone: zone) }

    @Test func firstLaunchFollowsThePhoneAndOffersKeep() {
        let same = TimeZoneSync.decide(state: nil, profileZone: "Asia/Jerusalem", deviceZone: "Asia/Jerusalem", now: now)
        #expect(same.state.mode == .automatic && same.newProfileZone == nil && !same.announce)
        // A zone saved long ago is usually stale, not a choice: follow the phone and announce, so Keep restores a real pin.
        let moved = TimeZoneSync.decide(state: nil, profileZone: "Asia/Jerusalem", deviceZone: "America/New_York", now: now)
        #expect(moved.state.mode == .automatic && moved.newProfileZone == "America/New_York" && moved.announce)
        #expect(moved.state.lastSwitch?.from == "Asia/Jerusalem" && moved.state.knownProfileZone == "America/New_York")
    }
    @Test func automaticFollowsTheDeviceAndAnnouncesAClockChange() {
        let d = TimeZoneSync.decide(state: auto("Asia/Jerusalem"), profileZone: "Asia/Jerusalem", deviceZone: "America/New_York", now: now)
        #expect(d.newProfileZone == "America/New_York" && d.announce && d.state.lastSwitch?.from == "Asia/Jerusalem" && d.state.lastSwitch?.announced == false)
    }
    @Test func sameOffsetSwitchIsSilent() {
        let d = TimeZoneSync.decide(state: auto("Europe/Paris"), profileZone: "Europe/Paris", deviceZone: "Europe/Berlin", now: now)
        #expect(d.newProfileZone == "Europe/Berlin" && !d.announce && d.state.lastSwitch?.announced == true)
    }
    @Test func flipBackWithinAnHourIsSilent() {
        let first = TimeZoneSync.decide(state: auto("Asia/Jerusalem"), profileZone: "Asia/Jerusalem", deviceZone: "Asia/Amman", now: now)
        let back = TimeZoneSync.decide(state: first.state, profileZone: "Asia/Amman", deviceZone: "Asia/Jerusalem", now: now + 1800)
        #expect(back.newProfileZone == "Asia/Jerusalem" && !back.announce && back.state.lastSwitch?.announced == true)
    }
    @Test func tripPinHoldsAwayAndReleasesAtHome() {
        let pin = TimeZoneState(mode: .pinned(zone: "Asia/Jerusalem", untilDeviceZone: "Asia/Jerusalem"), knownProfileZone: "Asia/Jerusalem")
        #expect(TimeZoneSync.decide(state: pin, profileZone: "Asia/Jerusalem", deviceZone: "America/New_York", now: now).newProfileZone == nil)
        let home = TimeZoneSync.decide(state: pin, profileZone: "Asia/Jerusalem", deviceZone: "Asia/Jerusalem", now: now)
        #expect(home.state.mode == .automatic && home.newProfileZone == nil && !home.announce)
    }
    @Test func outsideChangeToAnotherZonePinsWithoutRelease() {
        let d = TimeZoneSync.decide(state: auto("Asia/Jerusalem"), profileZone: "Asia/Tokyo", deviceZone: "Asia/Jerusalem", now: now)
        #expect(d.state.mode == .pinned(zone: "Asia/Tokyo", untilDeviceZone: nil) && d.newProfileZone == nil)
    }
    @Test func stateIsPerProfile() {
        let store = TimeZoneStateStore(defaults: UserDefaults(suiteName: "TimeZoneSync-" + UUID().uuidString)!)
        let a = UUID(), b = UUID()
        store.save(TimeZoneState(mode: .pinned(zone: "Asia/Jerusalem", untilDeviceZone: nil), knownProfileZone: "Asia/Jerusalem"), for: a)
        store.save(auto("UTC"), for: b)
        #expect(store.state(for: a)?.mode == .pinned(zone: "Asia/Jerusalem", untilDeviceZone: nil) && store.state(for: b)?.mode == .automatic)
    }
    @Test func unknownZoneIsNotAClockChange() { #expect(!TimeZoneSync.clockDiffers("Nope/Zone", "UTC", at: now)) }
    @Test func cityNames() {
        #expect(TimeZoneSync.city("America/New_York", locale: Locale(identifier: "en")) == "New York" && TimeZoneSync.city("UTC") == "UTC")
        #expect(TimeZoneSync.city("America/New_York", locale: Locale(identifier: "ru")) == "Нью-Йорк")
        #expect(TimeZoneSync.city("America/Argentina/Buenos_Aires", locale: Locale(identifier: "es")) == "Buenos Aires")
        #expect(TimeZoneSync.city("Etc/GMT+5", locale: Locale(identifier: "ru")) == "GMT+5")
    }
}
