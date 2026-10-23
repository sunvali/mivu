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

enum ProgressInsights {
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
