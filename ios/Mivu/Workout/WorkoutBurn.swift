import Foundation

/// Estimated net calories burned (above resting) from the Compendium MET values.
enum WorkoutBurn {
    /// Whole kcal, or nil without an activity or body weight. Running and cycling with a distance use their speed row; others use effort.
    static func estimate(activity: String, seconds: Int, distanceMeters: Double?, effort: Int?, bodyKg: Double?) -> Double? {
        guard let bodyKg, let activity = WorkoutCatalog.activity(activity), activity.met.count == 3 else { return nil }
        let hours = Double(seconds) / 3600
        // Gym is 3.5 for easy and moderate and 6.0 from Hard up; other sports reach vigorous only at Max.
        let vigorousFrom = activity.id == "strength" ? 7 : 8
        var met = activity.met[effort.map { $0 <= 3 ? 0 : $0 < vigorousFrom ? 1 : 2 } ?? 1]
        if let rows = activity.speedMET, let distanceMeters, hours > 0 {
            let kmh = distanceMeters / 1000 / hours
            met = (rows.last { $0[0] <= kmh } ?? rows[0])[1]
        }
        return ((max(met - 1, 0)) * bodyKg * hours).rounded()
    }

    /// The latest weigh-in on or before `localDate` (yyyy-MM-dd), else the onboarding weight.
    /// A weigh-in's date is its `measuredAt` in `zone`; the caller passes the day's time zone.
    static func bodyKg(on localDate: String, weights: [WeightEntry], onboardingKg: Double?,
                       zone: String = TimeZone.current.identifier) -> Double? {
        let latest = weights
            .map { (day: ProgressDate.label($0.measuredAt, zone: zone), entry: $0) }
            .filter { $0.day <= localDate }
            .max { ($0.day, $0.entry.measuredAt) < ($1.day, $1.entry.measuredAt) }?.entry
        guard let latest else { return onboardingKg }
        return latest.unit == "lb" ? latest.value * 0.45359237 : latest.value
    }
}
