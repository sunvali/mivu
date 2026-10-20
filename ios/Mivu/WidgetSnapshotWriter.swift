import Foundation
import WidgetKit

extension WidgetSnapshot {
    init(readModel: DiaryReadModel?, now: Date, cutoffHour: Int) {
        let zone = readModel?.activeDay?.timeZoneID ?? readModel?.head.profile.timeZoneID ?? TimeZone.current.identifier
        // From the day's start, so a day left open past the cutoff reads as over instead of lasting until tomorrow.
        let rolloverAt = Self.nextRollover(after: readModel?.activeDay?.startAt ?? now, timeZoneID: zone, cutoffHour: cutoffHour)
        guard let readModel else {
            self.init(day: "", eaten: 0, target: nil, hasDiary: false, rolloverAt: rolloverAt, writtenAt: now)
            return
        }
        let report = ProgressAnalytics.daily(readModel: readModel)
        self.init(day: report.localDate, eaten: report.foodTotals?.kcal ?? 0, target: report.goal?.targets.kcal,
                  hasDiary: true, rolloverAt: rolloverAt, writtenAt: now)
    }
}

/// Writes today's calories for the widgets and asks WidgetKit to redraw them.
@MainActor func publishWidgetSnapshot(_ readModel: DiaryReadModel?) {
    // UI tests run synthetic diaries; they must never reach a real Home Screen widget.
    guard !DiaryLaunch.isUITest,
          let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup) else { return }
    try? WidgetSnapshot(readModel: readModel, now: Date(), cutoffHour: DayCutoff.hour).write(to: WidgetSnapshot.fileURL(in: container))
    WidgetCenter.shared.reloadAllTimelines()
}
