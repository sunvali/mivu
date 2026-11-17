import SwiftUI

/// A meal's clock time where it was eaten, tagged with the city only when the phone's clock would read differently.
enum MealClock {
    /// Meals saved before the zone was recorded fall back to their day's zone.
    static func zone(meal: String?, day: String) -> String { meal ?? day }

    static func label(_ at: Date, mealZone: String, deviceZone: String) -> (time: String, tag: String?, spoken: String) {
        let time = at.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: TimeZone(identifier: mealZone) ?? .current))
        guard TimeZoneSync.clockDiffers(mealZone, deviceZone, at: at) else { return (time, nil, time) }
        let city = TimeZoneSync.city(mealZone)
        return (time, city, String(localized: "\(time), \(city) time"))
    }

    /// The label for a meal on screen. A meal saved before zones were recorded keeps the phone's clock, as it always showed.
    static func label(_ meal: MealReadModel, deviceZone: String = TimeZone.current.identifier) -> (time: String, tag: String?, spoken: String) {
        label(meal.eatenAt, mealZone: meal.timeZoneID ?? deviceZone, deviceZone: deviceZone)
    }

    static func text(_ label: (time: String, tag: String?, spoken: String)) -> Text {
        guard let tag = label.tag else { return Text(verbatim: label.time) }
        return Text("\(Text(verbatim: label.time))\(Text(verbatim: " · \(tag)").foregroundStyle(Color.diarySecondary))")
    }
}
