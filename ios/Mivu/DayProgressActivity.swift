import ActivityKit
import Foundation

extension DayProgressAttributes.ContentState {
    /// Built from the same daily report Today and the widget use, so no totals are computed twice.
    init(report: DailyProgress, hideWhenLocked: Bool) {
        let eaten = report.foodTotals, target = report.goal?.targets
        self.init(kcalEaten: eaten?.kcal ?? 0, kcalTarget: target?.kcal,
                  protein: eaten?.protein, proteinTarget: target?.protein,
                  carbs: eaten?.carbs, carbsTarget: target?.carbs,
                  fat: eaten?.fat, fatTarget: target?.fat,
                  hasPending: report.hasPending || (eaten?.unknownItemCount ?? 0) > 0,
                  hideWhenLocked: hideWhenLocked)
    }
}
