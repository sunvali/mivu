import Foundation

/// Short app-written lines used when the model's prose cannot be shown.
enum CoachReplyLines {
    static func factLine(progress: [CoachProgress], goals: [GoalRecord], workouts: [WorkoutSession], preferencesRead: Bool, today: String) -> String {
        var sentences = progress.map { progressLine($0, today: today) }
        sentences += goals.compactMap(goalLine)
        sentences += workouts.map { "\($0.kind.rawValue.capitalized), \($0.durationMinutes) minutes." }
        if preferencesRead { sentences.append("Your preferences are up to date.") }
        return sentences.isEmpty ? "I couldn't find anything to add there." : sentences.prefix(2).joined(separator: " ")
    }

    private static func progressLine(_ progress: CoachProgress, today: String) -> String {
        if let period = progress.period, period.dayCount > 1 {
            guard let average = period.averageIntake.kcal else { return "There's no food recorded for the last \(period.dayCount) days yet." }
            return "Last \(period.dayCount) days: about \(number(average, step: 10)) kcal a day on \(period.knownIntakeSamples.kcal) tracked days."
        }
        let daily = progress.daily
        let label = daily.localDate == today ? "Today" : daily.localDate
        guard let eaten = daily.foodTotals?.kcal, eaten > 0 else { return "There's no food recorded for \(daily.localDate) yet." }
        var line = "\(label): \(number(eaten))"
        if let target = daily.goal?.targets.kcal { line += " of \(number(target))" }
        line += " kcal"
        if let remaining = daily.remainingFromRecorded.kcal { line += remaining >= 0 ? ", about \(number(remaining, step: 10)) left" : ", about \(number(-remaining, step: 10)) over" }
        if let weight = progress.weight.currentSevenDayAverageKg { line += ". Weight average \(number(weight)) kg" }
        return line + "."
    }

    private static func goalLine(_ goal: GoalRecord) -> String? {
        guard let kcal = goal.targets.kcal else { return nil }
        return "Goal: \(number(kcal)) kcal a day" + (goal.targets.protein.map { ", \(number($0)) g protein" } ?? "") + "."
    }

    enum FollowUp: Equatable { case today, progress }

    static func followUps(for turn: CoachExchangeSummary) -> [FollowUp] {
        guard turn.state == .completed else { return [] }
        return (turn.receipts.contains { $0.mealID != nil } ? [.today] : []) + (turn.receipts.contains { $0.weightID != nil } ? [.progress] : [])
    }

    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    /// For notifications and other plain-text surfaces.
    static func plain(_ text: String) -> String { String(attributed(text).characters) }

    /// "today", "yesterday" or a short date such as "Oct 17"; the year appears only when it differs.
    static func dayLabel(_ localDate: String, today: String, locale: Locale = .current) -> String {
        if localDate == today { return "today" }
        guard let day = date(localDate), let now = date(today) else { return localDate }
        if Calendar.gregorianUTC.dateComponents([.day], from: day, to: now).day == 1 { return "yesterday" }
        let sameYear = localDate.prefix(4) == today.prefix(4)
        var style = Date.FormatStyle(locale: locale, timeZone: .gmt).month(.abbreviated).day()
        if !sameYear { style = style.year() }
        return day.formatted(style)
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
