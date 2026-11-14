import Foundation

/// Short app-written lines used when the model's prose cannot be shown.
enum CoachReplyLines {
    static func factLine(progress: [CoachProgress], goals: [GoalRecord], workouts: [WorkoutSession], preferencesRead: Bool, today: String) -> String {
        var sentences = progress.map { progressLine($0, today: today) }
        sentences += goals.compactMap(goalLine)
        sentences += workouts.map { String(localized: "\($0.kind.rawValue.capitalized), \($0.durationMinutes) minutes.") }
        if preferencesRead { sentences.append(String(localized: "Your preferences are up to date.")) }
        return sentences.isEmpty ? String(localized: "I couldn't find anything to add there.") : sentences.prefix(2).joined(separator: " ")
    }

    private static func progressLine(_ progress: CoachProgress, today: String) -> String {
        if let period = progress.period, period.dayCount > 1 {
            guard let average = period.averageIntake.kcal else { return String(localized: "No finished days in the last \(period.dayCount) days yet.") }
            let tracked = period.knownIntakeSamples.kcal
            return tracked == 1 ? String(localized: "Last \(period.dayCount) days: about \(number(average, step: 10)) kcal a day on 1 tracked day.")
                : String(localized: "Last \(period.dayCount) days: about \(number(average, step: 10)) kcal a day on \(tracked) tracked days.")
        }
        let daily = progress.daily
        let label = daily.localDate == today ? String(localized: "Today") : daily.localDate
        guard let eaten = daily.foodTotals?.kcal, eaten > 0 else { return String(localized: "There's no food recorded for \(daily.localDate) yet.") }
        // Each clause wraps the line so far, so a translation can reorder it.
        var line = daily.goal?.targets.kcal.map { String(localized: "\(label): \(number(eaten)) of \(number($0)) kcal") } ?? String(localized: "\(label): \(number(eaten)) kcal")
        if let remaining = daily.remainingFromRecorded.kcal {
            line = remaining >= 0 ? String(localized: "\(line), about \(number(remaining, step: 10)) left") : String(localized: "\(line), about \(number(-remaining, step: 10)) over")
        }
        if let weight = progress.weight.currentSevenDayAverageKg { line = String(localized: "\(line). Weight average \(number(weight)) kg") }
        return line + "."
    }

    private static func goalLine(_ goal: GoalRecord) -> String? {
        guard let kcal = goal.targets.kcal else { return nil }
        return goal.targets.protein.map { String(localized: "Goal: \(number(kcal)) kcal a day, \(number($0)) g protein.") } ?? String(localized: "Goal: \(number(kcal)) kcal a day.")
    }

    enum FollowUp: Equatable { case today, progress }

    static func followUps(for turn: CoachExchangeSummary) -> [FollowUp] {
        guard turn.state == .completed else { return [] }
        return (turn.receipts.contains { $0.mealID != nil } ? [.today] : []) + (turn.receipts.contains { $0.weightID != nil && !$0.operationKey.contains("/delete_weight/") } ? [.progress] : [])
    }

    /// Inline Markdown for emphasis only; links are dropped so model text cannot add tappable destinations.
    nonisolated static func attributed(_ text: String) -> AttributedString {
        var reply = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        for run in reply.runs where run.link != nil { reply[run.range].link = nil }
        return reply
    }

    /// For notifications and other plain-text surfaces.
    nonisolated static func plain(_ text: String) -> String { String(attributed(text).characters) }

    /// "today", "yesterday" or a short date such as "Oct 17"; the year appears only when it differs.
    static func dayLabel(_ localDate: String, today: String, locale: Locale = .current) -> String {
        if localDate == today { return String(localized: "today") }
        guard let day = date(localDate), let now = date(today) else { return localDate }
        if Calendar.gregorianUTC.dateComponents([.day], from: day, to: now).day == 1 { return String(localized: "yesterday") }
        let sameYear = localDate.prefix(4) == today.prefix(4)
        var style = Date.FormatStyle(locale: locale, timeZone: .gmt).month(.abbreviated).day()
        if !sameYear { style = style.year() }
        return day.formatted(style)
    }

    /// A heading such as "Today" or "Oct 17", relative to today in the profile's `zone`.
    static func dayTitle(_ localDate: String, zone: String) -> String {
        dayLabel(localDate, today: ProgressAnalytics.dateLabel(Date(), zone: zone)).capitalized(with: .current)
    }

    static func shortDate(_ localDate: String, locale: Locale = .current) -> String {
        date(localDate)?.formatted(Date.FormatStyle(locale: locale, timeZone: .gmt).month(.abbreviated).day()) ?? localDate
    }

    private static func date(_ localDate: String) -> Date? {
        try? Date(localDate, strategy: Date.ParseStrategy(format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)", timeZone: .gmt))
    }

    static func number(_ value: Double, step: Double = 0) -> String {
        let shown = step > 0 ? (value / step).rounded() * step : value
        return shown.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US")))
    }
}

private extension Calendar {
    static let gregorianUTC: Calendar = { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt; return calendar }()
}
