import Foundation

/// Today's calories for the widgets, written by the app into the App Group; the widget never opens the diary.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let appGroup = "group.com.yakov103.mivu"

    var day: String
    var eaten: Double
    var target: Double?
    var hasDiary: Bool
    var rolloverAt: Date
    var writtenAt: Date

    static func fileURL(in container: URL) -> URL { container.appending(path: "widget-snapshot.json") }

    static func read(from url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func write(to url: URL) throws {
        var parent = url.deletingLastPathComponent(), file = url, values = URLResourceValues()
        values.isExcludedFromBackup = true
        try parent.setResourceValues(values)
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try file.setResourceValues(values)
    }

    /// The next waking-day start, in the day's own time zone so travel cannot shift it.
    static func nextRollover(after now: Date, timeZoneID: String, cutoffHour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return calendar.nextDate(after: now, matching: DateComponents(hour: cutoffHour, minute: 0), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(86_400)
    }

    func afterRollover() -> WidgetSnapshot {
        var next = self
        next.eaten = 0
        return next
    }

    var ringFraction: Double {
        guard let target, target > 0 else { return 0 }
        return min(eaten / target, 1)
    }
}
