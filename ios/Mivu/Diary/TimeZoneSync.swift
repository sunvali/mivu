import Foundation

enum TimeZoneMode: Codable, Equatable, Sendable {
    case automatic
    case pinned(zone: String, untilDeviceZone: String?)
}

struct TimeZoneSwitch: Codable, Equatable, Sendable {
    var from: String
    var to: String
    var at: Date
    var announced: Bool
}

struct TimeZoneState: Codable, Equatable, Sendable {
    var mode: TimeZoneMode
    var knownProfileZone: String
    var lastSwitch: TimeZoneSwitch? = nil
}

struct TimeZoneDecision: Equatable {
    var state: TimeZoneState
    var newProfileZone: String?
    var announce: Bool
}

enum TimeZoneSync {
    /// Decides whether the profile's zone should follow the device zone; the caller applies `newProfileZone` and saves `state`.
    static func decide(state: TimeZoneState?, profileZone: String, deviceZone: String, now: Date) -> TimeZoneDecision {
        // First launch: a zone saved long ago is usually stale, so follow the phone; the announcement's Keep restores a real choice.
        var state = state ?? TimeZoneState(mode: .automatic, knownProfileZone: profileZone)
        // The profile zone changed elsewhere (Coach, a restore): adopt it, pinned when it differs from the phone.
        guard state.knownProfileZone == profileZone else {
            var adopted = state
            adopted.mode = profileZone == deviceZone ? .automatic : .pinned(zone: profileZone, untilDeviceZone: nil)
            adopted.knownProfileZone = profileZone
            return TimeZoneDecision(state: adopted, newProfileZone: nil, announce: false)
        }
        if case .pinned(_, let until) = state.mode, until == deviceZone { state.mode = .automatic }
        guard state.mode == .automatic, profileZone != deviceZone else {
            return TimeZoneDecision(state: state, newProfileZone: nil, announce: false)
        }
        let announce = clockDiffers(profileZone, deviceZone, at: now)
            && state.lastSwitch.map { now.timeIntervalSince($0.at) >= 3600 } ?? true
        state.knownProfileZone = deviceZone
        state.lastSwitch = TimeZoneSwitch(from: profileZone, to: deviceZone, at: now, announced: !announce)
        return TimeZoneDecision(state: state, newProfileZone: deviceZone, announce: announce)
    }

    static func clockDiffers(_ a: String, _ b: String, at: Date) -> Bool {
        // An unknown identifier (corrupt backup) must not trap the foreground sync; treat it as no clock change.
        guard let za = TimeZone(identifier: a), let zb = TimeZone(identifier: b) else { return false }
        return za.secondsFromGMT(for: at) != zb.secondsFromGMT(for: at)
    }

    static func city(_ zoneID: String) -> String {
        String(zoneID.split(separator: "/").last ?? "").replacingOccurrences(of: "_", with: " ")
    }
}

struct TimeZoneStateStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    func state(for profileID: UUID) -> TimeZoneState? {
        defaults.data(forKey: Self.key(profileID)).flatMap { try? JSONDecoder().decode(TimeZoneState.self, from: $0) }
    }

    func save(_ state: TimeZoneState, for profileID: UUID) {
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.key(profileID))
    }

    func forget(_ profileID: UUID) { defaults.removeObject(forKey: Self.key(profileID)) }

    private static func key(_ id: UUID) -> String { "timeZoneState." + id.uuidString }
}
