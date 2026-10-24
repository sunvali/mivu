import SwiftUI

/// How far a day's energy landed from that day's own target; over and under share a band.
enum ProgressBand: Int, CaseIterable {
    case near, bitOff, off, farOff

    static func of(kcal: Double?, target: Double?) -> ProgressBand? {
        guard let kcal, let target, target > 0 else { return nil }
        // Multiply before dividing so the 10/20/35% edges stay exact.
        let percent = abs(kcal - target) * 100 / target
        return percent <= 10 ? .near : percent <= 20 ? .bitOff : percent <= 35 ? .off : .farOff
    }

    var title: String {
        switch self {
        case .near: "Near"
        case .bitOff: "A bit off"
        case .off: "Off"
        case .farOff: "Far off"
        }
    }

    var color: Color {
        switch self {
        case .near: .diaryAccent
        case .bitOff: .diaryBandBitOff
        case .off: .diaryBandOff
        case .farOff: .diaryBandFarOff
        }
    }
}

enum ProgressRange: String, CaseIterable, Identifiable {
    case week, month, quarter, year
    var id: Self { self }
    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 91
        case .year: 365
        }
    }
    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .quarter: "3M"
        case .year: "Year"
        }
    }
}

/// One bar of a range chart: a day for Week and Month, a Monday week for 3M, a month for Year.
struct ProgressBucket: Identifiable, Equatable {
    let start: Date
    let averageKcal: Double?
    let averageTarget: Double?
    let band: ProgressBand?
    let loggedDays: Int
    /// False when the value comes only from partial or pending days: drawn lighter, never banded.
    var complete = true
    var id: Date { start }
}

enum ProgressCalendarDot: Equatable {
    case outside, noLog, logged(ProgressBand?)
}

/// A calendar line: a Monday week of seven dots (Week, Month) or a month's logged share (3M, Year).
struct ProgressCalendarRowData: Identifiable, Equatable {
    let title: String
    let dots: [ProgressCalendarDot]?
    let logged: Int
    let total: Int
    var id: String { title }
}

/// One weigh-in in kilograms with its smoothed trend.
struct TrendPoint: Equatable {
    let localDate: String
    let raw: Double
    let trend: Double
}

enum WeightTrend {
    /// Exponential moving average weighted by elapsed days, so a gap of weeks moves the trend further than one day does.
    static func points(_ weights: [CoachWeightReference]) -> [TrendPoint] {
        var result: [TrendPoint] = []
        for reference in weights.sorted(by: { $0.localDate < $1.localDate }) {
            let kg = reference.record.unit == "lb" ? reference.record.value * 0.45359237 : reference.record.value
            guard let previous = result.last else { result.append(TrendPoint(localDate: reference.localDate, raw: kg, trend: kg)); continue }
            let alpha = 1 - pow(0.9, Double(ProgressInsights.days(from: previous.localDate, to: reference.localDate)))
            result.append(TrendPoint(localDate: reference.localDate, raw: kg, trend: previous.trend + (kg - previous.trend) * alpha))
        }
        return result
    }
}

enum ProgressHeadline: Equatable {
    case onTrack, holdingSteady, drifting, atGoal
    case caloriesOnTrack(near: Int, logged: Int), caloriesOff(near: Int, logged: Int)
    case notEnoughData

    var title: String {
        switch self {
        case .onTrack, .caloriesOnTrack: "You're on track"
        case .holdingSteady: "Holding steady"
        case .drifting: "A new chance this week"
        case .atGoal: "You're at your goal"
        case .caloriesOff: "Fresh start ahead"
        case .notEnoughData: "Let's get started"
        }
    }

    var celebrates: Bool {
        switch self {
        case .onTrack, .atGoal, .caloriesOnTrack: true
        default: false
        }
    }
}

struct BurnEstimate: Equatable {
    let kcalPerDay: Double
    /// Half-width of the uncertainty band in kcal.
    let band: Double
}

enum BurnProgress: Equatable {
    case estimate(BurnEstimate)
    case needs(days: Int, weighIns: Int)
}

struct ProgressWin: Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let color: Color
}

enum ProgressInsights {
    /// Only a complete day with nothing still being analyzed is judged against its target.
    static func band(_ day: DailyProgress) -> ProgressBand? {
        guard day.status == .closed else { return nil }
        return ProgressBand.of(kcal: day.foodTotals?.kcal, target: day.goal?.targets.kcal)
    }

    /// Energy balance: average intake on complete days minus the energy the trend change stored or released (~7,700 kcal per kg).
    static func burn(days: [DailyProgress], trend: [TrendPoint]) -> BurnProgress {
        let intake = days.filter { $0.status == .closed }.compactMap { $0.foodTotals?.kcal }
        let span = trend.count >= 2 ? Self.days(from: trend[0].localDate, to: trend[trend.count - 1].localDate) : 0
        let daysNeeded = max(0, 14 - intake.count, 14 - span), weighInsNeeded = max(0, 4 - trend.count)
        guard daysNeeded == 0, weighInsNeeded == 0, let slope = slopePerDay(trend) else {
            return .needs(days: daysNeeded, weighIns: weighInsNeeded)
        }
        let average = intake.reduce(0, +) / Double(intake.count)
        let kcalPerDay = average - slope * 7_700
        return .estimate(BurnEstimate(kcalPerDay: kcalPerDay, band: 100 + 300 * Double(max(0, 30 - intake.count)) / 16))
    }

    /// At most three, most notable first; never a lost streak.
    static func wins(days: [DailyProgress], weighIns: Int, today: String? = nil) -> [ProgressWin] {
        var run = 0
        for day in days.sorted(by: { $0.localDate > $1.localDate }) {
            // Today is still in progress: it can extend a streak but never break one.
            if day.localDate == today, (day.foodTotals?.protein ?? 0) < (day.goal?.targets.protein ?? .infinity) { continue }
            guard let protein = day.foodTotals?.protein, let target = day.goal?.targets.protein, protein >= target else { break }
            run += 1
        }
        let logged = days.filter { $0.status != nil && $0.foodTotals?.kcal != nil }.count
        var wins: [ProgressWin] = []
        if run >= 3 { wins.append(ProgressWin(id: "protein-run", title: "Protein goal \(run) days running", detail: "Keep it going", symbol: "bolt.fill", color: .diaryProtein)) }
        if logged >= 5 { wins.append(ProgressWin(id: "logged-days", title: "\(logged) days logged", detail: "Every one counts", symbol: "checkmark", color: .diaryAccent)) }
        if weighIns >= 3 { wins.append(ProgressWin(id: "weigh-ins", title: "\(weighIns) weigh-ins", detail: "Your trend keeps sharpening", symbol: "scalemass.fill", color: .diaryWeight)) }
        return wins
    }

    /// Missing days stay out of every average; a bucket with no logged day has no value at all.
    static func buckets(_ days: [DailyProgress], range: ProgressRange, zone: String) -> [ProgressBucket] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        calendar.firstWeekday = 2
        let component: Calendar.Component = switch range {
        case .week, .month: .day
        case .quarter: .weekOfYear
        case .year: .month
        }
        var order: [Date] = [], groups: [Date: [DailyProgress]] = [:]
        for day in days.sorted(by: { $0.localDate < $1.localDate }) {
            guard let date = ProgressDate.date(day.localDate, zone: zone),
                  let start = calendar.dateInterval(of: component, for: date)?.start else { continue }
            if groups[start] == nil { order.append(start) }
            groups[start, default: []].append(day)
        }
        return order.map { start in
            let logged = groups[start, default: []].filter { $0.foodTotals?.kcal != nil && $0.status != nil }
            let judged = logged.filter { $0.status == .closed }
            let source = judged.isEmpty ? logged : judged
            let kcal = source.compactMap { $0.foodTotals?.kcal }, targets = source.compactMap { $0.goal?.targets.kcal }
            let average = kcal.isEmpty ? nil : kcal.reduce(0, +) / Double(kcal.count)
            let target = targets.isEmpty ? nil : targets.reduce(0, +) / Double(targets.count)
            return ProgressBucket(start: start, averageKcal: average, averageTarget: target,
                                  band: judged.isEmpty ? nil : ProgressBand.of(kcal: average, target: target), loggedDays: logged.count,
                                  complete: !judged.isEmpty)
        }
    }

    private static func whole(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }

    /// "2,420 kcal · 320 over": the day's energy against its own target, in words.
    static func plainResult(_ day: DailyProgress) -> String {
        guard day.status != nil, let kcal = day.foodTotals?.kcal else { return "No log" }
        let energy = whole(kcal) + " kcal"
        guard let target = day.goal?.targets.kcal, let band = band(day) else { return energy }
        if band == .near { return energy + " · on target" }
        return energy + " · \(whole(abs(kcal - target))) \(kcal > target ? "over" : "under")"
    }

    /// "400 over", or "on target" within 10%.
    static func plainGap(_ value: Double, goal: Double) -> String {
        if abs(value - goal) <= goal * 0.1 { return "on target" }
        return "\(whole(abs(value - goal))) \(value > goal ? "over" : "under")"
    }

    static func plainMacro(_ grams: Double?, goal: Double?) -> String {
        guard let grams else { return "No complete days" }
        let amount = "\(whole(grams)) g a day"
        guard let goal, goal > 0 else { return amount }
        if abs(grams - goal) <= goal * 0.1 { return amount + " · on goal" }
        return amount + " · \(whole(abs(grams - goal))) g \(grams > goal ? "over" : "under") goal"
    }

    /// Newest first. Week and Month show Monday weeks as dots; 3M and Year show months as counts.
    static func calendarRows(_ days: [DailyProgress], range: ProgressRange, zone: String) -> [ProgressCalendarRowData] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        calendar.firstWeekday = 2
        let byWeek = range == .week || range == .month
        var order: [Date] = [], groups: [Date: [(Date, DailyProgress)]] = [:]
        for day in days.sorted(by: { $0.localDate < $1.localDate }) {
            guard let date = ProgressDate.date(day.localDate, zone: zone),
                  let start = calendar.dateInterval(of: byWeek ? .weekOfYear : .month, for: date)?.start else { continue }
            if groups[start] == nil { order.append(start) }
            groups[start, default: []].append((date, day))
        }
        func dot(_ day: DailyProgress) -> ProgressCalendarDot { day.status == nil || day.foodTotals?.kcal == nil ? .noLog : .logged(band(day)) }
        return order.reversed().map { start in
            let members = groups[start, default: []]
            let logged = members.filter { if case .logged = dot($0.1) { true } else { false } }.count
            guard byWeek else {
                return ProgressCalendarRowData(title: DiaryWeek.format(ProgressDate.label(start, zone: zone), "MMMM yyyy"), dots: nil, logged: logged, total: members.count)
            }
            let dots = (0..<7).map { offset -> ProgressCalendarDot in
                guard let date = calendar.date(byAdding: .day, value: offset, to: start),
                      let member = members.first(where: { calendar.isDate($0.0, inSameDayAs: date) }) else { return .outside }
                return dot(member.1)
            }
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let first = ProgressDate.label(start, zone: zone), last = ProgressDate.label(end, zone: zone)
            let title = DiaryWeek.format(first, "MMM d") + " – " + DiaryWeek.format(last, first.prefix(7) == last.prefix(7) ? "d" : "MMM d")
            return ProgressCalendarRowData(title: title, dots: dots, logged: logged, total: members.count)
        }
    }

    /// Least-squares kg per day through the raw weigh-ins; the smoothed trend lags about nine days, so it only draws the line.
    static func slopePerDay(_ points: [TrendPoint]) -> Double? {
        guard let first = points.first, points.count >= 2 else { return nil }
        let xs = points.map { Double(days(from: first.localDate, to: $0.localDate)) }, ys = points.map(\.raw)
        let meanX = xs.reduce(0, +) / Double(xs.count), meanY = ys.reduce(0, +) / Double(ys.count)
        let spread = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard spread > 0 else { return nil }
        return zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) } / spread
    }

    static func days(from start: String, to end: String) -> Int {
        guard let from = ProgressDate.date(start, zone: "UTC"), let to = ProgressDate.date(end, zone: "UTC") else { return 0 }
        return Int((to.timeIntervalSince(from) / 86_400).rounded())
    }

    /// Weight trend first (needs a goal weight and 3 weigh-ins over 7 days); otherwise most logged days near the calorie target.
    static func headline(trend: [TrendPoint], goalWeightKg: Double?, startKg: Double?, days: [DailyProgress]) -> ProgressHeadline {
        if let goal = goalWeightKg, trend.count >= 3, let first = trend.first, let last = trend.last,
           case let span = Self.days(from: first.localDate, to: last.localDate), span >= 7 {
            if abs(last.trend - goal) <= 1 { return .atGoal }
            let direction = goal < (startKg ?? first.trend) ? -1.0 : 1.0
            let towardPerWeek = (slopePerDay(trend) ?? 0) * direction * 7
            return towardPerWeek >= 0.1 ? .onTrack : towardPerWeek <= -0.1 ? .drifting : .holdingSteady
        }
        let bands = days.compactMap(band)
        guard !bands.isEmpty else { return .notEnoughData }
        let near = bands.filter { $0 == .near }.count
        return near * 2 > bands.count ? .caloriesOnTrack(near: near, logged: bands.count) : .caloriesOff(near: near, logged: bands.count)
    }
}
