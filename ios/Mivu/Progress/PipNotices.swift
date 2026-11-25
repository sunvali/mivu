import Foundation

/// One thing Pip can say about the person's own diary. Every number is a count the detector made, never a model's.
enum PipNotice: Codable, Equatable, Sendable {
    case welcomeBack
    case bestWeek(near: Int, days: Int)
    case betterWeek(near: Int, before: Int)
    case weekendDrift(over: Bool)
    /// `weekday` is the Gregorian weekday, 1 = Sunday.
    case weekdayDrift(weekday: Int, over: Bool)
    case lateDinners(count: Int)
    case lateFirstMeal(count: Int)
    case proteinShort(short: Int, days: Int)

    /// The case without its values; what rests after being shown.
    var kind: String {
        switch self {
        case .welcomeBack: "welcomeBack"
        case .bestWeek: "bestWeek"
        case .betterWeek: "betterWeek"
        case .weekendDrift: "weekendDrift"
        case .weekdayDrift: "weekdayDrift"
        case .lateDinners: "lateDinners"
        case .lateFirstMeal: "lateFirstMeal"
        case .proteinShort: "proteinShort"
        }
    }
    var isWin: Bool {
        switch self {
        case .welcomeBack, .bestWeek, .betterWeek: true
        default: false
        }
    }
}

struct PipNoticeInput: Sendable {
    /// The active waking day, yyyy-MM-dd.
    var today: String
    /// Daily reports ending yesterday, oldest first; the last 28 are read.
    var reports: [DailyProgress]
    /// Saved meals of the seven days ending yesterday.
    var meals: [RecentMeal]
    /// Days with a saved meal, all-time.
    var loggedDays: Int
    /// The profile's time zone; its locale decides which days are the weekend.
    var calendar: Calendar
}

/// Rule-based observations. Pure, so every threshold is pinned by tests and a server worker could run the same rules.
enum PipNotices {
    /// In order of preference; empty when nothing qualifies. Only closed days count, as on Progress.
    static func candidates(_ input: PipNoticeInput) -> [PipNotice] {
        guard input.loggedDays >= 14 else { return [] }
        let zone = input.calendar.timeZone.identifier
        let labels = ProgressAnalytics.window(endingOn: input.today, days: 28, offset: 1, zone: zone)
        guard labels.count == 28, let noon = ProgressDate.date(input.today, zone: zone) else { return [] }
        let closed = Dictionary(input.reports.filter { $0.status == .closed }.map { ($0.localDate, $0) }, uniquingKeysWith: { $1 })
        guard let newest = closed.keys.max(), ProgressInsights.days(from: newest, to: input.today) < 4 else { return [.welcomeBack] }
        let days = labels.map { closed[$0] }
        let weeks = (0..<4).map { Array(days[(21 - 7 * $0)..<(28 - 7 * $0)]) }
        return [bestWeek(weeks), betterWeek(weeks), weekendDrift(labels, days, noon: noon, input.calendar),
                weekdayDrift(days, weekday: input.calendar.component(.weekday, from: noon)),
                lateDinners(labels, days, input), lateFirstMeal(labels, days, input), proteinShort(days)].compactMap { $0 }
    }

    private static func near(_ week: [DailyProgress?]) -> Int {
        week.filter { $0.flatMap { ProgressBand.of(kcal: $0.foodTotals?.kcal, target: $0.goal?.targets.kcal) } == .near }.count
    }
    private static func closedCount(_ week: [DailyProgress?]) -> Int { week.compactMap { $0 }.count }

    /// 1 when more than 20% over the target, -1 when more than 20% under, else 0. Multiplies first so the edge stays exact.
    private static func drift(kcal: Double?, target: Double?) -> Int {
        guard let kcal, let target, target > 0, abs(kcal - target) * 100 / target > 20 else { return 0 }
        return kcal > target ? 1 : -1
    }
    private static func drift(_ day: DailyProgress?) -> Int { drift(kcal: day?.foodTotals?.kcal, target: day?.goal?.targets.kcal) }
    /// The shared direction of at least three drifts, if any.
    private static func over(_ drifts: [Int]) -> Bool? {
        drifts.filter { $0 == 1 }.count >= 3 ? true : drifts.filter { $0 == -1 }.count >= 3 ? false : nil
    }

    private static func bestWeek(_ weeks: [[DailyProgress?]]) -> PipNotice? {
        let count = near(weeks[0])
        guard count >= 4, weeks[1...].allSatisfy({ near($0) < count }), weeks[1...].map(closedCount).reduce(0, +) >= 10 else { return nil }
        return .bestWeek(near: count, days: closedCount(weeks[0]))
    }
    private static func betterWeek(_ weeks: [[DailyProgress?]]) -> PipNotice? {
        let count = near(weeks[0]), before = near(weeks[1])
        guard count >= 4, count >= before + 2, closedCount(weeks[1]) >= 4 else { return nil }
        return .betterWeek(near: count, before: before)
    }

    private static func weekendDrift(_ labels: [String], _ days: [DailyProgress?], noon: Date, _ calendar: Calendar) -> PipNotice? {
        guard calendar.isDateInWeekend(noon) || calendar.isDateInWeekend(noon.addingTimeInterval(86_400)) else { return nil }
        let zone = calendar.timeZone.identifier
        // Consecutive weekend days form one weekend, judged on its closed days together.
        var weekends: [[DailyProgress]] = [], weekdays: [DailyProgress] = [], inWeekend = false
        for (label, day) in zip(labels, days) {
            let weekend = ProgressDate.date(label, zone: zone).map(calendar.isDateInWeekend) ?? false
            if weekend { if !inWeekend { weekends.append([]) }; if let day { weekends[weekends.count - 1].append(day) } }
            else if let day { weekdays.append(day) }
            inWeekend = weekend
        }
        let drifts = weekends.suffix(4).map { weekend -> Int in
            let judged = weekend.filter { $0.foodTotals?.kcal != nil && ($0.goal?.targets.kcal ?? 0) > 0 }
            return drift(kcal: judged.isEmpty ? nil : judged.reduce(0) { $0 + ($1.foodTotals?.kcal ?? 0) },
                         target: judged.reduce(0) { $0 + ($1.goal?.targets.kcal ?? 0) })
        }
        guard let over = over(drifts), weekdays.filter({ drift($0) != 0 }).count * 3 < weekdays.count else { return nil }
        return .weekendDrift(over: over)
    }

    /// Today's weekday on its last four turns: `days` ends yesterday, so they sit 7, 14, 21 and 28 back.
    private static func weekdayDrift(_ days: [DailyProgress?], weekday: Int) -> PipNotice? {
        over([21, 14, 7, 0].map { drift(days[$0]) }).map { .weekdayDrift(weekday: weekday, over: $0) }
    }

    /// Minutes after the waking day's own midnight, so 00:40 the next morning reads 1,480. Nil when the time is not real.
    private static func minutes(_ recent: RecentMeal, _ calendar: Calendar) -> Int? {
        let meal = recent.meal
        // Older meals carry no precision; one logged within two hours of eating has a real time.
        guard meal.timePrecision == .exact || (meal.timePrecision == nil && abs(meal.capturedAt.timeIntervalSince(meal.eatenAt)) <= 7200) else { return nil }
        var local = calendar
        if let zone = meal.timeZoneID.flatMap(TimeZone.init(identifier:)) { local.timeZone = zone }
        let clock = local.dateComponents([.hour, .minute], from: meal.eatenAt)
        let later = ProgressInsights.days(from: recent.localDate, to: ProgressAnalytics.dateLabel(meal.eatenAt, zone: local.timeZone.identifier))
        return later * 1440 + (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
    }
    /// Timed meals of each closed day in the last seven.
    private static func mealTimes(_ labels: [String], _ days: [DailyProgress?], _ input: PipNoticeInput) -> [[Int]] {
        zip(labels, days).suffix(7).compactMap { label, day in
            guard day != nil else { return nil }
            let times = input.meals.filter { $0.localDate == label }.compactMap { minutes($0, input.calendar) }
            return times.isEmpty ? nil : times
        }
    }
    private static func lateDinners(_ labels: [String], _ days: [DailyProgress?], _ input: PipNoticeInput) -> PipNotice? {
        let count = mealTimes(labels, days, input).filter { ($0.max() ?? 0) >= 21 * 60 + 30 }.count
        return count >= 3 ? .lateDinners(count: count) : nil
    }
    private static func lateFirstMeal(_ labels: [String], _ days: [DailyProgress?], _ input: PipNoticeInput) -> PipNotice? {
        let count = mealTimes(labels, days, input).filter { ($0.min() ?? 0) >= 13 * 60 }.count
        return count >= 4 ? .lateFirstMeal(count: count) : nil
    }

    private static func proteinShort(_ days: [DailyProgress?]) -> PipNotice? {
        let known = days.suffix(14).compactMap { day -> Bool? in
            guard let protein = day?.foodTotals?.protein, let target = day?.goal?.targets.protein, target > 0 else { return nil }
            return protein < target * 0.8
        }
        let short = known.filter { $0 }.count
        return known.count >= 5 && short * 10 >= known.count * 6 ? .proteinShort(short: short, days: known.count) : nil
    }
}

// MARK: Choosing

/// What Pip has said lately, per profile. Small and disposable, so it lives in UserDefaults and stays out of backups.
struct PipNoticeLog: Codable, Equatable, Sendable {
    struct Shown: Codable, Equatable, Sendable {
        var localDate: String
        var notice: PipNotice
        var offerTapped = false
    }
    /// The last waking day the detector ran for, so one day is scanned once even when nothing was found.
    var scanned: String?
    /// Newest last.
    var shown: [Shown] = []
}

struct PipNoticeStore {
    /// One switch for all profiles, like the morning check-in; absent means on.
    static let enabledKey = "pipNoticesEnabled"
    let defaults: UserDefaults

    func log(for profileID: UUID) -> PipNoticeLog {
        defaults.data(forKey: Self.key(profileID)).flatMap { try? JSONDecoder().decode(PipNoticeLog.self, from: $0) } ?? PipNoticeLog()
    }
    /// Keeps the last 30 days, which is more than any rest rule reads.
    func save(_ log: PipNoticeLog, for profileID: UUID) {
        var log = log
        if let latest = log.scanned ?? log.shown.last?.localDate {
            log.shown.removeAll { ProgressInsights.days(from: $0.localDate, to: latest) > 30 }
        }
        defaults.set(try? JSONEncoder().encode(log), forKey: Self.key(profileID))
    }
    private static func key(_ profileID: UUID) -> String { "pipNotices." + profileID.uuidString }
}

extension PipNotices {
    /// The first candidate allowed today: a kind rests seven days, and at most two notices that are not wins show in any seven.
    static func choose(_ candidates: [PipNotice], shown: [PipNoticeLog.Shown], today: String) -> PipNotice? {
        let recent = shown.filter { (0..<7).contains(ProgressInsights.days(from: $0.localDate, to: today)) }.map(\.notice)
        let nudgesLeft = recent.filter { !$0.isWin }.count < 2
        return candidates.first { candidate in (candidate.isWin || nudgesLeft) && !recent.contains { $0.kind == candidate.kind } }
    }
}

// MARK: Words

extension PipNotice {
    /// One short sentence for Pip's bubble. Whole sentences per case, so translations keep their grammar.
    var text: String {
        switch self {
        case .welcomeBack: String(localized: "Good to see you again. Pick up from today?")
        case .bestWeek(let near, let days): String(localized: "\(near) of \(days) days near target. Your best week this month!")
        case .betterWeek(let near, let before): String(localized: "\(near) days near target this week, up from \(before).")
        case .weekendDrift(over: true): String(localized: "Weekends tend to run over for you.")
        case .weekendDrift(over: false): String(localized: "Weekends tend to come in well under for you.")
        case .weekdayDrift(let weekday, over: true):
            switch weekday {
            case 1: String(localized: "Sundays usually run over for you.")
            case 2: String(localized: "Mondays usually run over for you.")
            case 3: String(localized: "Tuesdays usually run over for you.")
            case 4: String(localized: "Wednesdays usually run over for you.")
            case 5: String(localized: "Thursdays usually run over for you.")
            case 6: String(localized: "Fridays usually run over for you.")
            default: String(localized: "Saturdays usually run over for you.")
            }
        case .weekdayDrift(let weekday, over: false):
            switch weekday {
            case 1: String(localized: "Sundays usually come in well under for you.")
            case 2: String(localized: "Mondays usually come in well under for you.")
            case 3: String(localized: "Tuesdays usually come in well under for you.")
            case 4: String(localized: "Wednesdays usually come in well under for you.")
            case 5: String(localized: "Thursdays usually come in well under for you.")
            case 6: String(localized: "Fridays usually come in well under for you.")
            default: String(localized: "Saturdays usually come in well under for you.")
            }
        case .lateDinners(let count): String(localized: "Dinner landed after 9:30 pm on \(count) days this week.")
        case .lateFirstMeal(let count): String(localized: "Your first meal came after 1 pm on \(count) days this week.")
        case .proteinShort(let short, let days): String(localized: "Protein came in short on \(short) of your last \(days) logged days.")
        }
    }

    /// The one next step Pip offers: a chip title and the message it sends to Coach, in the person's voice. Wins need none.
    var offer: (title: String, message: String)? {
        switch self {
        case .welcomeBack, .bestWeek, .betterWeek: nil
        case .weekendDrift(over: true):
            (String(localized: "Plan a lighter weekend"), String(localized: "My weekends usually run over my calorie target. Help me plan a lighter one."))
        case .weekendDrift(over: false):
            (String(localized: "Ideas to fill the weekend"), String(localized: "My weekends usually come in well under my calorie target. Give me easy ideas to reach it."))
        case .weekdayDrift(_, over: true):
            (String(localized: "Plan today with me"), String(localized: "This day of the week usually runs over my calorie target. Help me plan today."))
        case .weekdayDrift(_, over: false):
            (String(localized: "Easy ideas for today"), String(localized: "This day of the week usually comes in well under my calorie target. Give me easy ideas to reach it."))
        case .lateDinners:
            (String(localized: "Earlier dinner ideas"), String(localized: "My dinners have been running late this week. Give me an idea for an earlier dinner."))
        case .lateFirstMeal:
            (String(localized: "A quick earlier option"), String(localized: "My first meal has been coming late this week. Suggest a quick earlier option."))
        case .proteinShort:
            (String(localized: "Easy ways to add protein"), String(localized: "My protein has been short of my target lately. Give me easy ways to add some."))
        }
    }
}
