import ActivityKit
import Foundation
import OSLog

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

enum DayProgressSync: Equatable {
    case endAll, start, update(endingExtra: Int)

    static let enabledKey = "liveActivityEnabled", hideWhenLockedKey = "liveActivityHideWhenLocked"

    static func decide(enabled: Bool, authorized: Bool, hasDiary: Bool, running: Int) -> DayProgressSync {
        guard enabled, authorized, hasDiary else { return .endAll }
        return running == 0 ? .start : .update(endingExtra: running - 1)
    }
}

private let liveActivityLog = Logger(subsystem: "com.yakov103.mivu", category: "LiveActivity")

/// Starts, refreshes or ends today's Live Activity; called whenever the diary or the person's choice changes.
@MainActor func syncDayProgressActivity(_ readModel: DiaryReadModel?) {
    // UI tests run synthetic diaries; only a test that asks for it may show a real activity.
    guard !DiaryLaunch.isUITest || ProcessInfo.processInfo.arguments.contains("--live-activity") else { return }
    let defaults = UserDefaults.standard
    let enabled = defaults.bool(forKey: DayProgressSync.enabledKey)
    let hide = defaults.object(forKey: DayProgressSync.hideWhenLockedKey) as? Bool ?? true
    let content = readModel.flatMap { model in
        model.activeDay.map { day in
            // Past the cutoff the numbers belong to yesterday, so the island asks to open Mivu instead.
            ActivityContent(state: DayProgressAttributes.ContentState(report: ProgressAnalytics.daily(readModel: model), hideWhenLocked: hide),
                            staleDate: WidgetSnapshot.nextRollover(after: Date(), timeZoneID: day.timeZoneID, cutoffHour: DayCutoff.hour))
        }
    }
    let authorized = ActivityAuthorizationInfo().areActivitiesEnabled
    // Each sync waits for the previous one, so a burst of diary changes lands in order.
    let previous = DayProgressSync.lastSync
    DayProgressSync.lastSync = Task.detached {
        await previous?.value
        await applyDayProgress(enabled: enabled, authorized: authorized, content: content)
    }
}

extension DayProgressSync {
    @MainActor static var lastSync: Task<Void, Never>?
}

private func applyDayProgress(enabled: Bool, authorized: Bool,
                              content: ActivityContent<DayProgressAttributes.ContentState>?) async {
    let running = Activity<DayProgressAttributes>.activities
    switch DayProgressSync.decide(enabled: enabled, authorized: authorized, hasDiary: content != nil, running: running.count) {
    case .endAll:
        for activity in running { await activity.end(nil, dismissalPolicy: .immediate) }
    case .start:
        guard let content else { return }
        do { _ = try Activity.request(attributes: DayProgressAttributes(), content: content, pushType: nil) }
        catch { liveActivityLog.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)") }
    case .update(let extra):
        guard let content, let first = running.first else { return }
        await first.update(content)
        for activity in running.dropFirst().prefix(extra) { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
