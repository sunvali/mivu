import UIKit

private let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
private func isOlder(_ version: String, than other: String) -> Bool { version.compare(other, options: .numeric) == .orderedAscending }

/// A newer App Store version for the update card and Settings row, and the website's emergency minimum.
/// Neither request carries anything about the person.
@MainActor @Observable final class AppUpdate {
    static let lookupURL = URL(string: "https://itunes.apple.com/lookup?id=6826633410")!
    static let configURL = URL(string: "https://mivuapp.com/app-config.json")!
    static let shared: AppUpdate = {
        let update = AppUpdate(defaults: DiaryLaunch.defaults, version: bundleVersion)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if DiaryLaunch.isUITest && arguments.contains("--update-available-fixture") { update.available = "99.0" }
        if DiaryLaunch.isUITest && arguments.contains("--update-required-fixture") { update.minimum = "99.0" }
        if DiaryLaunch.isUITest && arguments.contains("--update-required-on-return") {
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { update.minimum = "99.0" }
            }
        }
        #endif
        return update
    }()

    let defaults: UserDefaults
    let version: String
    private let session: URLSession
    /// Only once it has been out 7 days, so the phased release reaches people before the nudge does.
    private(set) var available: String?
    private var minimum: String? { didSet { defaults.set(minimum, forKey: "appMinimumVersion") } }
    private var lastCheck: Date?

    init(defaults: UserDefaults, version: String, session: URLSession = .shared) {
        self.defaults = defaults
        self.version = version
        self.session = session
        minimum = defaults.string(forKey: "appMinimumVersion")
    }

    var isBlocked: Bool { minimum.map { isOlder(version, than: $0) } ?? false }

    /// Failures change nothing: the last minimum stays, so a broken website never blocks and an offline phone stays blocked.
    func check(now: Date = Date()) async {
        // A blocked person checks every time, so a lowered minimum frees them on their next return.
        if !isBlocked, let lastCheck, now.timeIntervalSince(lastCheck) < 3_600 { return }
        lastCheck = now
        async let store = fetch(Lookup.self, from: Self.lookupURL)
        async let config = fetch(Config.self, from: Self.configURL)
        if let item = await store?.results.first {
            available = isOlder(version, than: item.version) && now.timeIntervalSince(item.currentVersionReleaseDate) >= 7 * 86_400 ? item.version : nil
        }
        if let config = await config { minimum = config.ios }
    }

    /// Once per version, then once more a week after the first dismissal.
    func showsCard(now: Date = Date()) -> Bool {
        guard let available else { return false }
        guard defaults.string(forKey: "updateCardVersion") == available else { return true }
        let dismissedAt = defaults.object(forKey: "updateCardDismissedAt") as? Date ?? .distantPast
        return defaults.integer(forKey: "updateCardDismissals") == 1 && now.timeIntervalSince(dismissedAt) >= 7 * 86_400
    }

    func dismissCard(now: Date = Date()) {
        guard let available else { return }
        let count = defaults.string(forKey: "updateCardVersion") == available ? defaults.integer(forKey: "updateCardDismissals") : 0
        defaults.set(available, forKey: "updateCardVersion")
        defaults.set(count + 1, forKey: "updateCardDismissals")
        defaults.set(now, forKey: "updateCardDismissedAt")
    }

    private struct Lookup: Decodable {
        struct Item: Decodable { let version: String; let currentVersionReleaseDate: Date }
        let results: [Item]
    }
    private struct Config: Decodable { let ios: String? }

    private func fetch<Value: Decodable>(_ type: Value.Type, from url: URL) async -> Value? {
        guard let (data, response) = try? await session.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}

/// Bundled highlights, shown once by Pip to people who updated into a feature release.
@MainActor @Observable final class WhatsNew {
    /// Add one entry per feature release, at most three short lines. Fix-only versions get none.
    static let notes: [String: [LocalizedStringResource]] = [:]
    static let shared: WhatsNew = {
        #if DEBUG
        if DiaryLaunch.isUITest && ProcessInfo.processInfo.arguments.contains("--whats-new-fixture") {
            let lines = ["Synthetic highlight one.", "Synthetic highlight two."].map { LocalizedStringResource(String.LocalizationValue($0)) }
            DiaryLaunch.defaults.set("0.1", forKey: "lastRunVersion")
            return WhatsNew(defaults: DiaryLaunch.defaults, version: bundleVersion, notes: [bundleVersion: lines])
        }
        #endif
        return WhatsNew(defaults: DiaryLaunch.defaults, version: bundleVersion, notes: notes)
    }()

    let defaults: UserDefaults
    let version: String
    private let notes: [String: [LocalizedStringResource]]
    private(set) var pending: [LocalizedStringResource]?

    init(defaults: UserDefaults, version: String, notes: [String: [LocalizedStringResource]]) {
        self.defaults = defaults
        self.version = version
        self.notes = notes
    }

    /// A first run records the version silently, so new installs never see notes for the version they installed.
    func recordLaunch() {
        if let previous = defaults.string(forKey: "lastRunVersion"), isOlder(previous, than: version), notes[version] != nil {
            defaults.set(version, forKey: "whatsNewVersion")
        }
        defaults.set(version, forKey: "lastRunVersion")
        pending = defaults.string(forKey: "whatsNewVersion") == version ? notes[version] : nil
    }

    func markSeen() {
        defaults.removeObject(forKey: "whatsNewVersion")
        pending = nil
    }
}
