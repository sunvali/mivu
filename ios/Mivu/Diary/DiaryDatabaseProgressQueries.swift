import Foundation
import SQLite3

extension DiaryDatabase {
    func progressRange(endingOn: String, days: Int, finalizingTurnID: UUID? = nil, expectedProfileID: UUID) throws -> CoachProgress {
        guard validLocalDate(endingOn), [1, 7, 30].contains(days) else { throw CoachError.invalidArguments }
        return try domainRead(expectedProfileID: expectedProfileID) { head in
            let transaction = DiaryTransaction(database: self, head: head), zone = head.profile.timeZoneID
            if let id = finalizingTurnID { guard try transaction.turn(id: id) != nil else { throw DiaryError.notFound } }
            let horizon = ProgressAnalytics.window(endingOn: endingOn, days: 37, offset: 0, zone: zone)
            guard horizon.count == 37 else { throw DiaryError.invalidData }
            var reports: [String: DailyProgress] = [:], latest: [String: WeightEntry] = [:]
            var weights: [(Int, CoachWeightReference)] = [], workouts: [(Int, WorkoutReference)] = [], workoutCount = 0
            for label in horizon {
                let rows = try transaction.records("day", clause: "json_extract(CAST(payload AS TEXT), '$.localDate') = ?", values: [.text(label)])
                let tracked = try rows.map { row in let day = try decode(TrackingDay.self, row); try validateTrackingDayFields(day); return day }
                let nilDay = try domainStatement("SELECT EXISTS(SELECT 1 FROM coach_index i JOIN coach_turn t ON t.id = i.turnID WHERE i.displayLocalDate = ? AND i.state != 'completed' AND i.turnID != ? AND COALESCE(json_extract(CAST(t.payload AS TEXT), '$.resolvedDayID'), json_extract(CAST(t.payload AS TEXT), '$.activeDayID')) IS NULL)", [.text(label), .text(finalizingTurnID?.uuidString ?? "")])
                defer { sqlite3_finalize(nilDay) }; guard try mutationStep(nilDay) else { throw DiaryError.invalidData }
                let nilDayPending = sqlite3_column_int64(nilDay, 0) != 0
                var totals: [NutritionTotals] = [], pending = nilDayPending, dailyWorkoutCount = 0, burn: Double? = 0
                for day in tracked {
                    let summary = try transaction.daySummary(day)
                    let pendingStatement = try domainStatement("SELECT EXISTS(SELECT 1 FROM coach_turn WHERE COALESCE(json_extract(CAST(payload AS TEXT), '$.resolvedDayID'), json_extract(CAST(payload AS TEXT), '$.activeDayID')) = ? AND json_extract(CAST(payload AS TEXT), '$.state') != 'completed' AND id != ?)", [.text(day.id.uuidString), .text(finalizingTurnID?.uuidString ?? "")])
                    defer { sqlite3_finalize(pendingStatement) }; guard try mutationStep(pendingStatement) else { throw DiaryError.invalidData }
                    let dayPending = nilDayPending || summary.pendingMealCount > 0 || sqlite3_column_int64(pendingStatement, 0) != 0
                    pending = pending || dayPending
                    totals.append(dayPending && summary.savedMealCount == 0 ? NutritionTotals(kcal: nil, carbs: nil, protein: nil, fat: nil, unknownItemCount: 0) : summary.totals)
                    for row in try transaction.records("weight", clause: "parent = ?", values: [.text(day.id.uuidString)]) {
                        let weight = try decode(WeightEntry.self, row); try validateWeightFields(weight)
                        weights.append((row.ordinal, CoachWeightReference(localDate: label, record: weight)))
                    }
                    let statement = try domainStatement("SELECT COUNT(*), CASE WHEN COUNT(*) = COUNT(json_extract(CAST(payload AS TEXT), '$.estimatedBurnKcal')) THEN COALESCE(SUM(json_extract(CAST(payload AS TEXT), '$.estimatedBurnKcal')), 0) END FROM workout WHERE parent = ?", [.text(day.id.uuidString)])
                    defer { sqlite3_finalize(statement) }; guard try mutationStep(statement) else { throw DiaryError.invalidData }
                    let count = Int(sqlite3_column_int64(statement, 0)); dailyWorkoutCount += count
                    if sqlite3_column_type(statement, 1) == SQLITE_NULL { burn = nil } else if let previous = burn { burn = previous + sqlite3_column_double(statement, 1) }
                    if label >= horizon[horizon.count - days] {
                        workoutCount += count
                        let selected = try domainStatement("SELECT id, ordinal, json_extract(CAST(payload AS TEXT), '$.revision'), json_extract(CAST(payload AS TEXT), '$.kind'), json_extract(CAST(payload AS TEXT), '$.durationMinutes') FROM workout WHERE parent = ? ORDER BY ordinal DESC, id DESC LIMIT 100", [.text(day.id.uuidString)])
                        defer { sqlite3_finalize(selected) }
                        while try mutationStep(selected) {
                            guard let id = try mutationOptionalUUID(selected, 0), let kind = WorkoutKind(rawValue: try mutationText(selected, 3)) else { throw DiaryError.invalidData }
                            workouts.append((Int(sqlite3_column_int64(selected, 1)), WorkoutReference(id: id, dayID: day.id, localDate: label, revision: Int(sqlite3_column_int64(selected, 2)), kind: kind, durationMinutes: Int(sqlite3_column_int64(selected, 4)))))
                        }
                        workouts = Array(workouts.sorted { $0.0 < $1.0 }.suffix(100))
                    }
                }
                reports[label] = ProgressAnalytics.daily(localDate: label, days: tracked, subtotals: totals, hasPending: pending, goal: try transaction.goal(on: label), workoutCount: dailyWorkoutCount, estimatedBurnKcal: burn)
            }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!
            let start = calendar.startOfDay(for: try diaryDateOnlyInstant(horizon[0], zone: zone))
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: try diaryDateOnlyInstant(endingOn, zone: zone)))!
            for row in try transaction.records("weight", clause: "parent IS NULL AND json_extract(CAST(payload AS TEXT), '$.measuredAt') >= ? AND json_extract(CAST(payload AS TEXT), '$.measuredAt') < ?", values: [.real(start.timeIntervalSinceReferenceDate), .real(end.timeIntervalSinceReferenceDate)]) {
                let weight = try decode(WeightEntry.self, row); try validateWeightFields(weight)
                weights.append((row.ordinal, CoachWeightReference(localDate: diaryDateLabel(weight.measuredAt, zone: zone), record: weight)))
            }
            weights.sort { $0.0 < $1.0 }
            for (_, reference) in weights {
                let entry = reference.record
                if let prior = latest[reference.localDate], prior.measuredAt > entry.measuredAt || (prior.measuredAt == entry.measuredAt && prior.revision >= entry.revision) { continue }
                latest[reference.localDate] = entry
            }
            let labels = Array(horizon.suffix(days)), references = weights.map(\.1).filter { $0.localDate >= labels[0] }
            let complete = horizon.suffix(28).compactMap { reports[$0] }.filter { $0.completeness == .complete && !$0.hasPending && $0.foodTotals?.kcal != nil }.count
            return CoachProgress(startLocalDate: labels[0], endLocalDate: endingOn, daily: reports[endingOn]!,
                period: days == 1 ? nil : ProgressAnalytics.period(endingOn: endingOn, days: days, reports: labels.compactMap { reports[$0] }),
                weight: ProgressAnalytics.weight(endingOn: endingOn, zone: zone, latest: latest, completeKcalDays: complete),
                weights: Array(references.suffix(40)), workouts: workouts.map(\.1), omittedWeightCount: max(0, references.count - 40), omittedWorkoutCount: max(0, workoutCount - 100), truncated: references.count > 40 || workoutCount > 100)
        }
    }
}
