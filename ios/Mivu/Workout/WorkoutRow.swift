import SwiftUI

/// The activity's symbol on a soft workout-purple tile.
struct WorkoutIcon: View {
    let symbol: String
    @ScaledMetric(relativeTo: .body) private var size = 40.0

    var body: some View {
        // Capped so the tile stays a tile at the largest text sizes.
        Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(Color.diaryWorkout)
            .frame(width: min(size, 64), height: min(size, 64))
            .background(Color.diaryWorkout.opacity(0.12), in: .rect(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}

/// One workout on Today: icon, title, one detail line ("5 km · 28 min" or "52 min · 14 sets") and its burn.
struct WorkoutRow: View {
    let session: WorkoutSession
    @Environment(\.dynamicTypeSize) private var typeSize

    static func title(_ session: WorkoutSession) -> String {
        session.title ?? session.activity.flatMap { WorkoutCatalog.activity($0)?.name } ?? session.kind.title
    }

    static func symbol(_ session: WorkoutSession) -> String {
        session.activity.flatMap { WorkoutCatalog.activity($0)?.symbol } ?? "figure.strengthtraining.traditional"
    }

    static func detail(_ session: WorkoutSession) -> String {
        let seconds = session.durationSeconds ?? session.durationMinutes * 60
        let sets = session.exercises.reduce(0) { $0 + $1.sets.count }
        return [session.distanceMeters.flatMap { $0 > 0 ? distance($0, activity: session.activity) : nil },
                minutes(seconds),
                sets > 0 ? "\(sets) \(sets == 1 ? "set" : "sets")" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    /// "28 min" or "1 h 5 min", matching the unit on the cardio ruler.
    static func minutes(_ seconds: Int) -> String {
        let total = max(1, Int((Double(seconds) / 60).rounded()))
        return total < 60 ? "\(total) min" : "\(total / 60) h" + (total % 60 == 0 ? "" : " \(total % 60) min")
    }

    /// Kilometres or miles by the person's region; pools stay in metres.
    static func distance(_ meters: Double, activity: String?) -> String {
        if activity == "swim" { return "\(Int(meters.rounded()).formatted()) m" }
        let miles = Locale.current.measurementSystem != .metric
        return (miles ? meters / 1_609.344 : meters / 1_000).formatted(.number.precision(.fractionLength(0...1))) + (miles ? " mi" : " km")
    }

    /// "~310" for an estimate; a number the person typed shows as is.
    nonisolated static func burn(_ session: WorkoutSession) -> String? {
        session.estimatedBurnKcal.map { (session.burnSource == .userEstimate ? "" : "~") + $0.formatted(.number.precision(.fractionLength(0))) }
    }

    private var burn: String? { Self.burn(session) }

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            WorkoutIcon(symbol: Self.symbol(session))
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.title(session)).font(.body.weight(.semibold)).foregroundStyle(Color.diaryText)
                Text(Self.detail(session)).font(.subheadline).foregroundStyle(Color.diarySecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let burn {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(burn).font(.headline).monospacedDigit().foregroundStyle(Color.diaryWorkout)
                    Text("kcal").font(.caption).foregroundStyle(Color.diarySecondary)
                }.fixedSize()
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([Self.title(session), Self.detail(session), burn.map { "\($0.replacingOccurrences(of: "~", with: "about ")) kilocalories burned" }].compactMap { $0 }.joined(separator: ", "))
    }
}
