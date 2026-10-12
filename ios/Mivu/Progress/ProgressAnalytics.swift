import Foundation

struct DailyProgress: Codable, Equatable, Sendable {
    let localDate: String
    let completeness: DayCompleteness?
    let hasPending: Bool
    let foodTotals: NutritionTotals?
    let goal: GoalRecord?
    let remainingFromRecorded: NutritionValues
    let workoutCount: Int
    let estimatedBurnKcal: Double?
    let exerciseAdjustedKcalRemaining: Double?
}

struct NutrientSampleCounts: Codable, Equatable, Sendable {
    let kcal: Int
    let carbs: Int
    let protein: Int
    let fat: Int
}

struct PeriodProgress: Codable, Equatable, Sendable {
    let startLocalDate: String
    let endLocalDate: String
    let dayCount: Int
    let completeDayCount: Int
    let partialDayCount: Int
    let untrackedDayCount: Int
    let unknownDayCount: Int
    let missingDayCount: Int
    let pendingDayCount: Int
    let knownIntakeSamples: NutrientSampleCounts
    let averageIntake: NutritionValues
    let adherenceNumerator: Int
    let adherenceDenominator: Int
    let workoutCount: Int
}

enum PlateauReadiness: String, Codable, Equatable, Sendable {
    case insufficientData, stable, changing
}

struct WeightProgress: Codable, Equatable, Sendable {
    let endLocalDate: String
    let currentSevenDayAverageKg: Double?
    let currentSevenDayObservedCount: Int
    let changeFromSevenDaysAgoKg: Double?
    let changeFromThirtyDaysAgoKg: Double?
    let plateau: PlateauReadiness
}

enum ProgressAnalytics {
    static func daily(snapshot: DiarySnapshot, localDate: String) -> DailyProgress {
        let days = snapshot.days.filter { $0.localDate == localDate }
        let dayIDs = Set(days.map(\.id))
        let hasPending = Self.hasPending(on: localDate, dayIDs: dayIDs, snapshot: snapshot)
        let completeness: DayCompleteness?
        if days.isEmpty { completeness = nil }
        else if days.allSatisfy({ $0.completeness == .complete }) {
            completeness = hasPending ? .partial : .complete
        } else if days.allSatisfy({ $0.completeness == .untracked }) { completeness = .untracked }
        else if days.allSatisfy({ $0.completeness == .unknown }) { completeness = .unknown }
        else { completeness = .partial }
        let subtotals = days.map { tracked -> NutritionTotals in
            let pending = Self.hasPending(on: localDate, dayIDs: [tracked.id], snapshot: snapshot)
            let hasSavedMeal = snapshot.meals.contains { $0.dayID == tracked.id && $0.isSaved }
            // A pending capture can coexist with a complete empty day; zero is not confirmed then.
            if pending && !hasSavedMeal {
                return NutritionTotals(kcal: nil, carbs: nil, protein: nil, fat: nil, unknownItemCount: 0)
            }
            return snapshot.totals(dayID: tracked.id)
        }
        func sum(_ field: KeyPath<NutritionTotals, Double?>) -> Double? {
            guard !subtotals.isEmpty, subtotals.allSatisfy({ $0[keyPath: field] != nil }) else { return nil }
            return subtotals.reduce(0) { $0 + $1[keyPath: field]! }
        }
        let totals: NutritionTotals? = subtotals.isEmpty ? nil : NutritionTotals(
            kcal: sum(\.kcal), carbs: sum(\.carbs), protein: sum(\.protein), fat: sum(\.fat),
            unknownItemCount: subtotals.reduce(0) { $0 + $1.unknownItemCount })
        let goal = snapshot.goal(on: localDate)
        let remaining = NutritionValues(
            kcal: remaining(goal?.targets.kcal, totals?.kcal),
            carbs: remaining(goal?.targets.carbs, totals?.carbs),
            protein: remaining(goal?.targets.protein, totals?.protein),
            fat: remaining(goal?.targets.fat, totals?.fat)
        )
        let workouts = snapshot.workouts.filter { dayIDs.contains($0.dayID) }
        let burn: Double? = workouts.allSatisfy { $0.estimatedBurnKcal != nil }
            ? workouts.reduce(0) { $0 + $1.estimatedBurnKcal! } : nil
        let adjusted = goal?.exerciseCreditEnabled == true ? remaining.kcal.flatMap { kcal in burn.map { kcal + $0 } } : nil
        return DailyProgress(localDate: localDate, completeness: completeness, hasPending: hasPending,
                             foodTotals: totals, goal: goal, remainingFromRecorded: remaining,
                             workoutCount: workouts.count, estimatedBurnKcal: burn,
                             exerciseAdjustedKcalRemaining: adjusted)
    }

    static func period(snapshot: DiarySnapshot, endingOn: String, days: Int) -> PeriodProgress {
        precondition(days == 7 || days == 30)
        let labels = window(endingOn: endingOn, days: days, offset: 0, zone: snapshot.profile.timeZoneID)
        let reports = labels.map { daily(snapshot: snapshot, localDate: $0) }
        let eligible = reports.filter { $0.completeness == .complete && !$0.hasPending }
        func average(_ field: KeyPath<NutritionTotals, Double?>) -> (Double?, Int) {
            let values = eligible.compactMap { $0.foodTotals?[keyPath: field] }
            return (values.isEmpty ? nil : values.reduce(0, +) / Double(values.count), values.count)
        }
        let kcal = average(\.kcal), carbs = average(\.carbs)
        let protein = average(\.protein), fat = average(\.fat)
        let adherence = eligible.compactMap { report -> Bool? in
            guard let intake = report.foodTotals?.kcal, let target = report.goal?.targets.kcal else { return nil }
            // A target is a range for reporting: a very low intake is not called adherence.
            return intake >= target * 0.9 && intake <= target * 1.1
        }
        return PeriodProgress(startLocalDate: labels.first ?? endingOn, endLocalDate: endingOn,
                              dayCount: days,
                              completeDayCount: reports.filter { $0.completeness == .complete }.count,
                              partialDayCount: reports.filter { $0.completeness == .partial }.count,
                              untrackedDayCount: reports.filter { $0.completeness == .untracked }.count,
                              unknownDayCount: reports.filter { $0.completeness == .unknown }.count,
                              missingDayCount: reports.filter { $0.completeness == nil }.count,
                              pendingDayCount: reports.filter(\.hasPending).count,
                              knownIntakeSamples: NutrientSampleCounts(kcal: kcal.1, carbs: carbs.1,
                                                                       protein: protein.1, fat: fat.1),
                              averageIntake: NutritionValues(kcal: kcal.0, carbs: carbs.0,
                                                             protein: protein.0, fat: fat.0),
                              adherenceNumerator: adherence.filter { $0 }.count,
                              adherenceDenominator: adherence.count,
                              workoutCount: reports.reduce(0) { $0 + $1.workoutCount })
    }

    static func weight(snapshot: DiarySnapshot, endingOn: String) -> WeightProgress {
        let daysByID = Dictionary(uniqueKeysWithValues: snapshot.days.map { ($0.id, $0.localDate) })
        var latest: [String: WeightEntry] = [:]
        for entry in snapshot.weights {
            let label = entry.dayID.flatMap { daysByID[$0] }
                ?? dateLabel(entry.measuredAt, zone: snapshot.profile.timeZoneID)
            if let prior = latest[label],
               prior.measuredAt > entry.measuredAt ||
               (prior.measuredAt == entry.measuredAt && prior.revision >= entry.revision) { continue }
            latest[label] = entry
        }
        func summary(days: Int, offset: Int) -> (average: Double?, count: Int) {
            let entries = window(endingOn: endingOn, days: days, offset: offset,
                                 zone: snapshot.profile.timeZoneID).compactMap { latest[$0] }
            let kilograms = entries.map { $0.unit == "lb" ? $0.value * 0.45359237 : $0.value }
            return (kilograms.isEmpty ? nil : kilograms.reduce(0, +) / Double(kilograms.count), kilograms.count)
        }
        let current = summary(days: 7, offset: 0)
        let priorWeek = summary(days: 7, offset: 7)
        let priorMonth = summary(days: 7, offset: 30)
        let firstPlateauWeek = summary(days: 7, offset: 21)
        let completeKcalDays = window(endingOn: endingOn, days: 28, offset: 0,
                                      zone: snapshot.profile.timeZoneID).reduce(0) { count, label in
            let report = daily(snapshot: snapshot, localDate: label)
            return count + (report.completeness == .complete && !report.hasPending && report.foodTotals?.kcal != nil ? 1 : 0)
        }
        let plateau: PlateauReadiness
        if current.count < 3 || firstPlateauWeek.count < 3 || completeKcalDays < 14 {
            plateau = .insufficientData
        } else {
            plateau = abs(current.average! - firstPlateauWeek.average!) <= 0.25 ? .stable : .changing
        }
        return WeightProgress(endLocalDate: endingOn, currentSevenDayAverageKg: current.average,
                              currentSevenDayObservedCount: current.count,
                              changeFromSevenDaysAgoKg: current.count >= 3 && priorWeek.count >= 3
                                  ? current.average! - priorWeek.average! : nil,
                              changeFromThirtyDaysAgoKg: current.count >= 3 && priorMonth.count >= 3
                                  ? current.average! - priorMonth.average! : nil,
                              plateau: plateau)
    }

    private static func remaining(_ target: Double?, _ recorded: Double?) -> Double? {
        guard let target, let recorded else { return nil }
        return target - recorded
    }

    private static func hasPending(on localDate: String, dayIDs: Set<UUID>, snapshot: DiarySnapshot) -> Bool {
        if snapshot.meals.contains(where: { dayIDs.contains($0.dayID) && $0.hasUnresolvedInput }) {
            return true
        }
        return snapshot.coachTurns.contains { turn in
            guard turn.state != .completed else { return false }
            if let assignedID = turn.resolvedDayID ?? turn.activeDayID {
                return dayIDs.contains(assignedID)
            }
            return dateLabel(turn.capturedAt, zone: turn.captureTimeZoneID) == localDate
        }
    }

    private static func dateLabel(_ date: Date, zone: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone) ?? .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func window(endingOn: String, days: Int, offset: Int, zone: String) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let endNoon = formatter.date(from: endingOn + " 12:00"),
              let shiftedEnd = calendar.date(byAdding: .day, value: -offset, to: endNoon) else { return [] }
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<days).reversed().compactMap { distance in
            calendar.date(byAdding: .day, value: -distance, to: shiftedEnd).map(formatter.string(from:))
        }
    }
}
