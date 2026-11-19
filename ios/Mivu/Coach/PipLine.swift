import Foundation

/// What Pip says beside the Coach composer. Pure, so the copy is pinned by tests rather than by the view.
enum PipLine: Equatable {
    case say(String)
    case working(String)
    case problem(String, detail: String?, canRetry: Bool)
    case connect

    static func current(hour: Int, mealsLogged: Bool, typing: Bool, connected: Bool, processing: Bool,
                        withPhotos: Bool, recovery: Bool, error: String?, turnState: CoachTurnState?, chips: Bool = false) -> PipLine? {
        if recovery {
            switch turnState {
            case .waitingForConnection: return .connect
            case .waitingForNetwork: return .problem(String(localized: "I’m offline. I’ll pick this up when you’re back."), detail: error, canRetry: false)
            case .needsClarification: return .problem(String(localized: "I need a bit more detail. My question is above."), detail: error, canRetry: false)
            case .needsRetry: return .problem(String(localized: "That one didn’t go through."), detail: error, canRetry: true)
            default: return .problem(String(localized: "Something went wrong."), detail: error, canRetry: false)
            }
        }
        if processing { return .working(withPhotos ? String(localized: "Looking at your photo…") : String(localized: "Counting that up…")) }
        if !connected { return .connect }
        if typing { return nil }
        // Beside the quick prompts Pip keeps to a short mood line, so the bubble never repeats the chips.
        if chips {
            if mealsLogged { return .say(String(localized: "Anything else?")) }
            switch hour {
            case 4..<11: return .say(String(localized: "Morning!"))
            case 11..<15: return .say(String(localized: "Lunch time?"))
            case 15..<18: return .say(String(localized: "Snack time?"))
            case 18..<22: return .say(String(localized: "Dinner time?"))
            default: return .say(String(localized: "Hi again!"))
            }
        }
        if mealsLogged { return .say(String(localized: "Anything else to log?")) }
        switch hour {
        case 4..<11: return .say(String(localized: "Morning! What’s for breakfast?"))
        case 11..<15: return .say(String(localized: "Ready for lunch?"))
        case 15..<18: return .say(String(localized: "What have you had today?"))
        case 18..<22: return .say(String(localized: "What’s for dinner?"))
        default: return .say(String(localized: "Anything to log?"))
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
    let spokenEaten = kcal.map { kcalPartial ? String(localized: "at least \($0.formatted(whole))") : $0.formatted(whole) } ?? (mealsLogged ? String(localized: "unknown") : "0")
    let target = goal.map { $0.formatted(whole) }
    let title = CoachReplyLines.dayLabel(localDate, today: today, title: true)
    guard let target else { return (String(localized: "\(title) · \(eaten) kcal"), String(localized: "Logging to \(day), \(spokenEaten) kcal")) }
    return (String(localized: "\(title) · \(eaten) / \(target) kcal"), String(localized: "Logging to \(day), \(spokenEaten) of \(target) kcal"))
}
