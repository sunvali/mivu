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

    static func number(_ value: Double, step: Double = 0) -> String {
        let shown = step > 0 ? (value / step).rounded() * step : value
        return shown.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US")))
    }
}
