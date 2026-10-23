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
    var id: Date { start }
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
    /// Energy balance: average intake on complete days minus the energy the trend change stored or released (~7,700 kcal per kg).
    static func burn(days: [DailyProgress], trend: [TrendPoint]) -> BurnProgress {
        let intake = days.filter { $0.completeness == .complete && !$0.hasPending }.compactMap { $0.foodTotals?.kcal }
        let span = trend.count >= 2 ? Self.days(from: trend[0].localDate, to: trend[trend.count - 1].localDate) : 0
        let daysNeeded = max(0, 14 - intake.count, 14 - span), weighInsNeeded = max(0, 4 - trend.count)
        guard daysNeeded == 0, weighInsNeeded == 0, let first = trend.first, let last = trend.last else {
            return .needs(days: daysNeeded, weighIns: weighInsNeeded)
        }
        let average = intake.reduce(0, +) / Double(intake.count)
        let kcalPerDay = average - (last.trend - first.trend) * 7_700 / Double(span)
        return .estimate(BurnEstimate(kcalPerDay: kcalPerDay, band: 100 + 300 * Double(max(0, 30 - intake.count)) / 16))
    }

    /// At most three, most notable first; never a lost streak.
    static func wins(days: [DailyProgress], weighIns: Int) -> [ProgressWin] {
        var run = 0
        for day in days.sorted(by: { $0.localDate > $1.localDate }) {
            guard let protein = day.foodTotals?.protein, let target = day.goal?.targets.protein, protein >= target else { break }
            run += 1
        }
        let logged = days.filter { $0.completeness != nil && $0.foodTotals?.kcal != nil }.count
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
            let logged = groups[start, default: []].filter { $0.foodTotals?.kcal != nil && $0.completeness != nil }
            let kcal = logged.compactMap { $0.foodTotals?.kcal }, targets = logged.compactMap { $0.goal?.targets.kcal }
            let average = kcal.isEmpty ? nil : kcal.reduce(0, +) / Double(kcal.count)
            let target = targets.isEmpty ? nil : targets.reduce(0, +) / Double(targets.count)
            return ProgressBucket(start: start, averageKcal: average, averageTarget: target,
                                  band: ProgressBand.of(kcal: average, target: target), loggedDays: logged.count)
        }
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
            let towardPerWeek = (last.trend - first.trend) * direction / Double(span) * 7
            return towardPerWeek >= 0.1 ? .onTrack : towardPerWeek <= -0.1 ? .drifting : .holdingSteady
        }
        let bands = days.compactMap { ProgressBand.of(kcal: $0.foodTotals?.kcal, target: $0.goal?.targets.kcal) }
        guard !bands.isEmpty else { return .notEnoughData }
        let near = bands.filter { $0 == .near }.count
        return near * 2 > bands.count ? .caloriesOnTrack(near: near, logged: bands.count) : .caloriesOff(near: near, logged: bands.count)
    }
}
