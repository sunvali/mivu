import Charts
import SwiftUI

/// Everything the Progress cards draw, derived once per load from `CoachProgress`.
struct ProgressSnapshot {
    let range: ProgressRange
    let zone: String
    let days: [DailyProgress]
    let buckets: [ProgressBucket]
    let trend: [TrendPoint]
    let goal: GoalRecord?
    let startKg: Double?
    let headline: ProgressHeadline
    let burn: BurnProgress
    let wins: [ProgressWin]
    let averages: NutritionValues

    /// Loads hold at least 30 days so burn and the weight verdict have data on Week; the cards show only the range.
    static func loadDays(_ range: ProgressRange) -> Int { max(30, range.days) }
    static func rangeStart(_ progress: CoachProgress, _ range: ProgressRange) -> String {
        (progress.dailyReports ?? []).suffix(range.days).first?.localDate ?? progress.startLocalDate
    }

    init(progress: CoachProgress, range: ProgressRange, zone: String, today: String) {
        self.range = range; self.zone = zone
        let loaded = progress.dailyReports ?? []
        let days = Array(loaded.suffix(range.days)), start = days.first?.localDate ?? ""
        self.days = days; loadedDays = loaded
        buckets = ProgressInsights.buckets(days, range: range, zone: zone)
        let allTrend = WeightTrend.points(progress.displayWeights ?? []), goal = loaded.last(where: { $0.goal != nil })?.goal
        trend = allTrend.filter { $0.localDate >= start }; loadedTrend = allTrend; self.goal = goal
        // shortcut: the start is the first trend point in the loaded window on or after the goal date, not the first ever weigh-in.
        startKg = (allTrend.first { $0.localDate >= (goal?.effectiveLocalDate ?? "") } ?? allTrend.first)?.trend
        headline = ProgressInsights.headline(trend: allTrend, goalWeightKg: goal?.goalWeightKg, startKg: startKg, days: days)
        burn = ProgressInsights.burn(days: loaded, trend: allTrend)
        wins = ProgressInsights.wins(days: days, weighIns: trend.count, today: today)
        // Averages use complete days with nothing pending, the same days the bands judge.
        let judged = days.filter { $0.status == .closed }.compactMap(\.foodTotals)
        func mean(_ field: KeyPath<NutritionTotals, Double?>) -> Double? {
            let values = judged.compactMap { $0[keyPath: field] }
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        averages = NutritionValues(kcal: mean(\.kcal), carbs: mean(\.carbs), protein: mean(\.protein), fat: mean(\.fat))
        judgedDays = judged.filter { $0.kcal != nil }.count
    }

    var bands: [ProgressBand] { days.compactMap(ProgressInsights.band) }
    var burnSummary: String {
        if case let .estimate(estimate) = burn { return String(localized: "~\(kcal(estimate.kcalPerDay)) a day") }
        return String(localized: "Needs more data")
    }
    /// Complete days with nothing pending: the ones averages and bands use.
    let judgedDays: Int
    /// The whole load (at least 30 days) behind burn and the weight verdict.
    let loadedDays: [DailyProgress]
    let loadedTrend: [TrendPoint]
    var loggedDays: Int { days.filter { $0.status != nil && $0.foodTotals?.kcal != nil }.count }
    var averageKcal: Double? { averages.kcal }
    var target: Double? { goal?.targets.kcal }

    /// The hero's one line under the verdict, as short as Today's "Complete day".
    var shortEvidence: String {
        switch headline {
        case .onTrack, .holdingSteady, .drifting, .atGoal:
            let points = loadedTrend
            let span = points.count >= 2 ? ProgressInsights.days(from: points[0].localDate, to: points[points.count - 1].localDate) : 0
            let change = (ProgressInsights.slopePerDay(points) ?? 0) * Double(span)
            let amount = abs(change).formatted(.number.precision(.fractionLength(1)))
            return change <= 0 ? String(localized: "Down \(amount) kg in \(loadedDays.count) days") : String(localized: "Up \(amount) kg in \(loadedDays.count) days")
        case let .caloriesOnTrack(near, logged), let .caloriesOff(near, logged):
            return String(localized: "\(near) of \(logged) days near your target")
        case .notEnoughData:
            return loggedDays > 0 ? String(localized: "Set a calorie goal to see how close you land") : String(localized: "Log a meal or weigh in to begin")
        }
    }
}

func kcal(_ value: Double) -> String { String(localized: "\(value.formatted(.number.precision(.fractionLength(0)))) kcal") }

// MARK: Shared pieces

/// Bars per bucket, colored by how far each landed from its own target, with a stepped target line.
struct ProgressBucketChart: View {
    let buckets: [ProgressBucket]
    let range: ProgressRange
    let zone: String
    var height: CGFloat = 150

    private var unit: Calendar.Component {
        switch range {
        case .week, .month: .day
        case .quarter: .weekOfYear
        case .year: .month
        }
    }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone) ?? .gmt
        value.firstWeekday = 2
        return value
    }
    private var stub: Double { (buckets.compactMap(\.averageKcal).max() ?? 2000) * 0.06 }

    var body: some View {
        Chart(buckets) { bucket in
            if let value = bucket.averageKcal {
                BarMark(x: .value("Date", bucket.start, unit: unit), y: .value("kcal", value))
                    .foregroundStyle(bucket.band?.color ?? Color.diarySecondary.opacity(bucket.complete ? 1 : 0.4))
                    .clipShape(RoundedRectangle(cornerRadius: range == .week ? 8 : 3))
            } else {
                // A day with no log gets a faint stub, never a zero bar.
                BarMark(x: .value("Date", bucket.start, unit: unit), y: .value("kcal", stub))
                    .foregroundStyle(Color.diaryRule.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            if let target = bucket.averageTarget, let end = calendar.date(byAdding: unit, value: 1, to: bucket.start) {
                RuleMark(xStart: .value("Start", bucket.start), xEnd: .value("End", end), y: .value("Target", target))
                    .foregroundStyle(Color.diaryText.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
        // Time runs left to right in every language; only the layout around the chart mirrors.
        .environment(\.layoutDirection, .leftToRight)
        .chartXAxis {
            AxisMarks(values: .stride(by: unit, count: axisStride)) { _ in
                AxisValueLabel(format: axisFormat)
            }
        }
        .chartYAxis(.hidden)
        .environment(\.timeZone, TimeZone(identifier: zone) ?? .gmt)
        .frame(height: height)
    }

    private var axisStride: Int {
        switch range {
        case .week: 1
        case .month: 7
        case .quarter: 4
        case .year: 3
        }
    }
    private var axisFormat: Date.FormatStyle {
        switch range {
        case .week: .dateTime.weekday(.abbreviated)
        case .month, .quarter: .dateTime.day().month(.abbreviated)
        case .year: .dateTime.month(.abbreviated)
        }
    }
}

struct ProgressPlaceholder: View {
    let symbol: String
    let text: String
    var body: some View {
        Label { Text(text) } icon: { Image(systemName: symbol).foregroundStyle(Color.diaryAccent) }
            .font(.subheadline).foregroundStyle(Color.diarySecondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

struct ProgressCardTitle: View {
    let title: String
    var detail: String? = nil
    var color: Color = .diaryText
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).foregroundStyle(color)
            Spacer()
            if let detail { Text(detail).font(.subheadline).foregroundStyle(Color.diarySecondary) }
        }
    }
}

// MARK: Cards

/// Today's hero, for a range: Pip beside one plain verdict, then the bars.
struct ProgressHeadlineCard: View {
    let snapshot: ProgressSnapshot
    let dates: String
    let companion: CompanionView?
    let openDiary: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(dates).font(.subheadline).foregroundStyle(Color.diarySecondary)
            if typeSize.isAccessibilitySize {
                pip.frame(maxWidth: .infinity, alignment: .trailing)
                verdict
            } else {
                HStack(alignment: .center, spacing: 8) { verdict.frame(maxWidth: .infinity, alignment: .leading); pip }
            }
            if snapshot.loggedDays == 0 {
                Button(action: openDiary) { Label("Open Diary", systemImage: "calendar").frame(minHeight: 44) }
                    .accessibilityIdentifier("openDiaryForCoverage")
            } else {
                ProgressBucketChart(buckets: snapshot.buckets, range: snapshot.range, zone: snapshot.zone, height: 96)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(snapshot.range == .week || snapshot.range == .month ? Text("Calories by day") : snapshot.range == .quarter ? Text("Calories by week") : Text("Calories by month"))
                    .accessibilityValue(ProgressSummary.buckets(snapshot.buckets, zone: snapshot.zone))
                    .accessibilityIdentifier("nutritionChartSummary")
            }
            Text("Empty days aren't counted as zero.").font(.caption).foregroundStyle(Color.diarySecondary)
                .accessibilityIdentifier("missingDayCopy")
        }
        .diaryProgressCard()
    }

    /// Pip stands on the right, mirrored to face the verdict and the bars (the rig itself only faces right).
    @ViewBuilder private var pip: some View { if let companion { companion.scaleEffect(x: -1, y: 1) } }

    private var verdict: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.headline.title).font(.system(.title, weight: .bold)).foregroundStyle(Color.diaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(snapshot.shortEvidence).font(.subheadline).foregroundStyle(Color.diaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Today's average-day hero: one big number, then protein / carbs / fat and the goal line.
struct ProgressMacrosCard: View {
    let snapshot: ProgressSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let average = snapshot.averageKcal {
                VStack(alignment: .leading, spacing: 0) {
                    Text(average.formatted(.number.precision(.fractionLength(0))))
                        .font(.system(size: 44, weight: .bold)).tracking(-1.5).monospacedDigit().foregroundStyle(Color.diaryText)
                    Text("kcal on an average day").font(.subheadline).foregroundStyle(Color.diaryText)
                }
                DiaryMacroRow(protein: snapshot.averages.protein, carbs: snapshot.averages.carbs, fat: snapshot.averages.fat)
            } else {
                ProgressPlaceholder(symbol: "fork.knife", text: String(localized: "Log a full day to see your average day."))
            }
            if let target = snapshot.target, target > 0 {
                ProgressGoalLine(left: String(localized: "\(kcal(target)) goal"), right: snapshot.averageKcal.map { ProgressInsights.plainGap($0, goal: target) } ?? String(localized: "no full days yet"),
                                 value: (snapshot.averageKcal ?? 0) / target)
            } else {
                Text("No energy target set").font(.subheadline).foregroundStyle(Color.diarySecondary)
            }
        }
        .diaryProgressCard()
    }
}

/// The goal line under Today's hero: label left, gap right, one thin bar.
struct ProgressGoalLine: View {
    let left: String
    let right: String
    let value: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(left); Spacer(minLength: 12); Text(right).foregroundStyle(Color.diarySecondary) }
                .font(.subheadline).monospacedDigit()
            ProgressView(value: max(0, min(value, 1))).tint(Color.diaryAccent)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One big trend number, a line with no axes, and the distance to the goal.
struct ProgressWeightCard: View {
    let snapshot: ProgressSnapshot
    private var trend: [TrendPoint] { snapshot.trend }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let last = trend.last {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(last.trend.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(size: 44, weight: .bold)).tracking(-1.5).monospacedDigit().foregroundStyle(Color.diaryText)
                        Text("kg trend").font(.subheadline).foregroundStyle(Color.diaryText)
                    }
                    if trend.count >= 2 { sparkline.frame(maxWidth: .infinity).frame(height: 56) }
                }
                if let goal = snapshot.goal?.goalWeightKg, let start = snapshot.startKg {
                    let total = abs(start - goal), left = abs(last.trend - goal)
                    ProgressGoalLine(left: String(localized: "\(goal.formatted(.number.precision(.fractionLength(1)))) kg goal"),
                                     right: left < 0.1 ? String(localized: "At goal") : String(localized: "\(left.formatted(.number.precision(.fractionLength(1)))) kg to go"),
                                     value: total > 0 ? (total - left) / total : 1)
                } else {
                    ProgressPlaceholder(symbol: "flag", text: String(localized: "Add a goal weight to see how far is left."))
                }
            }
            if trend.count < 3 {
                ProgressPlaceholder(symbol: "scalemass", text: String(localized: "Weigh in on \(3 - trend.count) more days to see your trend."))
            }
        }
        .diaryProgressCard()
    }

    private var sparkline: some View {
        Chart(trend, id: \.localDate) { point in
            if let date = ProgressDate.date(point.localDate, zone: snapshot.zone) {
                LineMark(x: .value("Date", date, unit: .day), y: .value("Trend", point.trend))
                    .foregroundStyle(Color.diaryWeight).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round)).interpolationMethod(.monotone)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weight trend")
        .accessibilityValue(ProgressSummary.weights(trend))
    }
}

struct ProgressCaloriesCard: View {
    let snapshot: ProgressSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressCardTitle(title: String(localized: "Calories vs target"), detail: snapshot.range.title)
            Text([snapshot.averageKcal.map { String(localized: "Average \(kcal($0))") }, snapshot.target.map { String(localized: "target \(kcal($0))") } ?? String(localized: "No energy target set")].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(Color.diarySecondary)
            if snapshot.loggedDays == 0 {
                ProgressPlaceholder(symbol: "chart.bar", text: String(localized: "Log a meal to see your calories against your target."))
            } else {
                ProgressBucketChart(buckets: snapshot.buckets, range: snapshot.range, zone: snapshot.zone)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Calories vs target")
                    .accessibilityValue(ProgressSummary.buckets(snapshot.buckets, zone: snapshot.zone))
                    .accessibilityIdentifier("nutritionChartSummary")
            }
        }
        .diaryProgressCard()
    }
}

struct ProgressBurnCard: View {
    let snapshot: ProgressSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressCardTitle(title: String(localized: "Estimated burn"), color: .diarySuccess)
            switch snapshot.burn {
            case let .estimate(estimate):
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("~" + estimate.kcalPerDay.formatted(.number.precision(.fractionLength(0)))).font(.system(.largeTitle, weight: .semibold)).monospacedDigit().foregroundStyle(Color.diarySuccess)
                    Text("kcal a day").font(.title3).foregroundStyle(Color.diarySecondary)
                }
                // The estimate's likely range, drawn as a band around the center value.
                GeometryReader { proxy in
                    // Band runs 100–400 kcal; wider uncertainty draws a wider band.
                    let width = proxy.size.width, share = 0.2 + 0.7 * min(1, estimate.band / 400)
                    ZStack {
                        Capsule().fill(Color.diarySuccess.opacity(0.15))
                        Capsule().fill(Color.diarySuccess.opacity(0.35)).frame(width: width * share)
                        Circle().fill(Color.diarySuccess).frame(width: 12, height: 12)
                    }
                }
                .frame(height: 12)
                .accessibilityHidden(true)
                Text("Likely between \(kcal(estimate.kcalPerDay - estimate.band)) and \(kcal(estimate.kcalPerDay + estimate.band)). From your intake and weight trend; it firms up as you log.")
                    .font(.footnote).foregroundStyle(Color.diarySecondary)
            case let .needs(days, weighIns):
                ProgressPlaceholder(symbol: "flame", text: Self.burnPlaceholder(days: days, weighIns: weighIns))
            }
        }
        .diaryProgressCard(fill: .diaryTintBurn)
        .accessibilityElement(children: .combine)
    }

    /// What is still needed before the burn estimate appears; plural forms live in the catalog.
    static func burnPlaceholder(days: Int, weighIns: Int) -> String {
        switch (days > 0, weighIns > 0) {
        case (true, true): String(localized: "Log \(days) more complete days and weigh in \(weighIns) more times to see your burn.")
        case (true, false): String(localized: "Log \(days) more complete days to see your burn.")
        case (false, true): String(localized: "Weigh in \(weighIns) more times to see your burn.")
        case (false, false): String(localized: "Keep logging to see your burn.")
        }
    }
}

enum ProgressSummary {
    static func buckets(_ buckets: [ProgressBucket], zone: String) -> String {
        let logged = buckets.filter { $0.averageKcal != nil }
        guard !logged.isEmpty else { return String(localized: "No logged days in this range.") }
        return logged.map { bucket in
            let day = DiaryWeek.format(ProgressDate.label(bucket.start, zone: zone), "MMM d"), energy = kcal(bucket.averageKcal ?? 0)
            return bucket.band.map { String(localized: "\(day): \(energy), \($0.spoken)") } ?? String(localized: "\(day): \(energy)")
        }.joined(separator: "; ")
    }
    static func weights(_ trend: [TrendPoint]) -> String {
        guard let last = trend.last else { return String(localized: "No weigh-ins in this range.") }
        return String(localized: "\(trend.count) weigh-ins. Trend \(last.trend.formatted(.number.precision(.fractionLength(1)))) kg on \(last.localDate).")
    }
}

extension View {
    /// The Progress card: `diarySummaryCard` geometry with an optional tint.
    func diaryProgressCard(fill: Color = .diarySurface) -> some View { modifier(DiarySummaryCardStyle(fill: fill)) }
    /// The list row a Progress card sits in, matching `diarySummaryCard()`'s insets.
    func listCardRow() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
