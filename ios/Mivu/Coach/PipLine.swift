import Foundation

/// What Pip says beside the Coach composer. Pure, so the copy is pinned by tests rather than by the view.
enum PipLine: Equatable {
    case say(String)
    case working(String)
    case problem(String, detail: String?, canRetry: Bool)
    case connect

    static func current(hour: Int, mealsLogged: Bool, typing: Bool, connected: Bool, processing: Bool,
                        withPhotos: Bool, recovery: Bool, error: String?, turnState: CoachTurnState?) -> PipLine? {
        if recovery {
            switch turnState {
            case .waitingForConnection: return .connect
            case .waitingForNetwork: return .problem("I’m offline. I’ll pick this up when you’re back.", detail: error, canRetry: false)
            case .needsClarification: return .problem("I need a bit more detail. My question is above.", detail: error, canRetry: false)
            case .needsRetry: return .problem("That one didn’t go through.", detail: error, canRetry: true)
            default: return .problem("Something went wrong.", detail: error, canRetry: false)
            }
        }
        if processing { return .working(withPhotos ? "Looking at your photo…" : "Counting that up…") }
        if !connected { return .connect }
        if typing { return nil }
        if mealsLogged { return .say("Anything else to log?") }
        switch hour {
        case 4..<11: return .say("Morning! What’s for breakfast?")
        case 11..<15: return .say("Ready for lunch?")
        case 15..<18: return .say("What have you had today?")
        case 18..<22: return .say("What’s for dinner?")
        default: return .say("Anything to log?")
        }
    }
}

/// The logging day and its intake, e.g. "Today · 1,240 / 2,000 kcal". A saved food without calories makes the
/// figure a lower bound ("1,240+"), as on Today; unknown intake reads "—", never zero.
func coachDayChip(localDate: String, today: String, kcal: Double?, kcalPartial: Bool, mealsLogged: Bool,
                  goal: Double?) -> (text: String, spoken: String) {
    let day = CoachReplyLines.dayLabel(localDate, today: today)
    let whole = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
    let eaten = kcal.map { $0.formatted(whole) + (kcalPartial ? "+" : "") } ?? (mealsLogged ? "—" : "0")
    let spokenEaten = kcal.map { (kcalPartial ? "at least " : "") + $0.formatted(whole) } ?? (mealsLogged ? "unknown" : "0")
    let target = goal.map { $0.formatted(whole) }
    return ("\(day.capitalized(with: .current)) · \(eaten)" + (target.map { " / " + $0 } ?? "") + " kcal",
            "Logging to \(day), \(spokenEaten)" + (target.map { " of " + $0 } ?? "") + " kcal")
}
