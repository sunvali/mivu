import Foundation

/// When a saved meal may ask for an App Store rating. Apple still decides whether the prompt shows (at most 3 a year);
/// guideline 5.6.1 rules out asking about mood first or offering anything for a rating.
struct RatingPrompt {
    let defaults: UserDefaults
    var version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    /// First after 3 logged days; then once per version, 30 days or 7 more logged days after the last ask.
    func shouldAsk(loggedDays: Int, now: Date = Date()) -> Bool {
        guard loggedDays >= 3 else { return false }
        guard let askedVersion = defaults.string(forKey: "ratingAskedVersion") else { return true }
        guard askedVersion != version else { return false }
        let askedAt = defaults.object(forKey: "ratingAskedAt") as? Date ?? .distantPast
        return now.timeIntervalSince(askedAt) >= 30 * 86_400 || loggedDays - defaults.integer(forKey: "ratingAskedLoggedDays") >= 7
    }

    func recordAsk(loggedDays: Int, now: Date = Date()) {
        defaults.set(version, forKey: "ratingAskedVersion")
        defaults.set(now, forKey: "ratingAskedAt")
        defaults.set(loggedDays, forKey: "ratingAskedLoggedDays")
    }
}
