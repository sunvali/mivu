import ActivityKit
import Foundation
import OSLog

extension DayProgressAttributes.ContentState {
    /// Built from the same daily report Today and the widget use, so no totals are computed twice.
    init(readModel: DiaryReadModel, hideWhenLocked: Bool) {
        let report = ProgressAnalytics.daily(readModel: readModel)
        let eaten = report.foodTotals, target = report.goal?.targets
        // The same saved items the report adds; a nutrient any of them lacks is shown as a bound.
        let items = readModel.meals.filter(\.isSaved).flatMap(\.items)
        let fields: [(String, KeyPath<NutritionValues, Double?>)] = [("kcal", \.kcal), ("protein", \.protein), ("carbs", \.carbs), ("fat", \.fat)]
        let partial = fields.filter { _, field in items.contains { $0.nutrition[keyPath: field] == nil } }.map(\.0)
        self.init(kcalEaten: eaten?.kcal, kcalTarget: target?.kcal,
                  protein: eaten?.protein, proteinTarget: target?.protein,
                  carbs: eaten?.carbs, carbsTarget: target?.carbs,
                  fat: eaten?.fat, fatTarget: target?.fat,
                  hideWhenLocked: hideWhenLocked, partial: partial)
    }
}

enum DayProgressSync: Equatable {
    case endAll, start, update(endingExtra: Int)

    static let enabledKey = "liveActivityEnabled", hideWhenLockedKey = "liveActivityHideWhenLocked"

    /// iOS keeps an ended activity listed until its Lock Screen card goes; it can no longer be updated.
    static func isLive(_ state: ActivityState) -> Bool { state == .active || state == .stale }

    /// iOS ends an activity by itself after eight hours but keeps its outdated card for up to four more.
    static func lingers(_ state: ActivityState) -> Bool { state == .ended }

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
    var content = readModel.flatMap { model in
        model.activeDay.map { day in
            // Past the cutoff the numbers belong to yesterday, so the island asks to open Mivu instead.
            ActivityContent(state: DayProgressAttributes.ContentState(readModel: model, hideWhenLocked: hide),
                            staleDate: WidgetSnapshot.nextRollover(after: Date(), timeZoneID: day.timeZoneID, cutoffHour: DayCutoff.hour))
        }
    }
    #if DEBUG
    // Visual checks need a full day with targets; the synthetic diaries have neither.
    let arguments = ProcessInfo.processInfo.arguments
    if let index = arguments.firstIndex(of: "--live-activity-sample"), arguments.indices.contains(index + 1),
       let eaten = Double(arguments[index + 1]) {
        content = ActivityContent(state: .init(kcalEaten: eaten, kcalTarget: 2000, protein: eaten * 0.06, proteinTarget: 120,
                                               carbs: eaten * 0.11, carbsTarget: 200, fat: eaten * 0.03, fatTarget: 60,
                                               hideWhenLocked: hide), staleDate: nil)
    }
    #endif
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
    let activities = Activity<DayProgressAttributes>.activities
    // Otherwise a fresh activity would sit beside the old card with yesterday's or this morning's numbers.
    for activity in activities where DayProgressSync.lingers(activity.activityState) {
        await activity.end(nil, dismissalPolicy: .immediate)
    }
    let running = activities.filter { DayProgressSync.isLive($0.activityState) }
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
