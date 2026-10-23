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
        let judged = days.filter { $0.completeness == .complete && !$0.hasPending }.compactMap(\.foodTotals)
        func mean(_ field: KeyPath<NutritionTotals, Double?>) -> Double? {
            let values = judged.compactMap { $0[keyPath: field] }
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        averages = NutritionValues(kcal: mean(\.kcal), carbs: mean(\.carbs), protein: mean(\.protein), fat: mean(\.fat))
        judgedDays = judged.filter { $0.kcal != nil }.count
    }

    var bands: [ProgressBand] { days.compactMap(ProgressInsights.band) }
    var burnSummary: String {
        if case let .estimate(estimate) = burn { return "~" + kcal(estimate.kcalPerDay) + " a day" }
        return "Needs more data"
    }
    /// Complete days with nothing pending: the ones averages and bands use.
    let judgedDays: Int
    /// The whole load (at least 30 days) behind burn and the weight verdict.
    let loadedDays: [DailyProgress]
    let loadedTrend: [TrendPoint]
    var loggedDays: Int { days.filter { $0.completeness != nil && $0.foodTotals?.kcal != nil }.count }
    var averageKcal: Double? { averages.kcal }
    var target: Double? { goal?.targets.kcal }

    var evidence: String {
        let near = bands.filter { $0 == .near }.count, logged = bands.count
        let calories = target.map { logged == 0 ? nil : "\(near) of \(logged) logged days near your \(kcal($0)) target" } ?? nil
        switch headline {
        case .onTrack, .holdingSteady, .drifting, .atGoal:
            // Quote the same window the verdict used (the whole load, at least 30 days), so the two never disagree.
            let points = loadedTrend
            let span = points.count >= 2 ? ProgressInsights.days(from: points[0].localDate, to: points[points.count - 1].localDate) : 0
            let change = (ProgressInsights.slopePerDay(points) ?? 0) * Double(span)
            let weight = "Trend \(change <= 0 ? "down" : "up") \(abs(change).formatted(.number.precision(.fractionLength(1)))) kg over \(loadedDays.count) days"
            return [weight, calories].compactMap { $0 }.joined(separator: " · ") + "."
        case let .caloriesOnTrack(near, logged), let .caloriesOff(near, logged):
            return "\(near) of \(logged) logged days landed near your \(target.map(kcal) ?? "calorie") target."
        case .notEnoughData:
            return loggedDays > 0 ? "Set a calorie goal in Goals to see how close each day lands." : "Log a meal or weigh in, and Pip will show how it's going."
        }
    }
}

func kcal(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) + " kcal" }

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

struct ProgressHeadlineCard: View {
    let snapshot: ProgressSnapshot
    let dates: String
    let companion: CompanionView
    let openDiary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(dates).font(.subheadline.weight(.semibold)).foregroundStyle(Color.diaryAccent)
                    Text(snapshot.headline.title).font(.title.weight(.bold)).foregroundStyle(Color.diaryAccent)
                    Text(snapshot.evidence).font(.subheadline).foregroundStyle(Color.diaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                companion
            }
            .accessibilityElement(children: .combine)
            if snapshot.loggedDays == 0 {
                Button(action: openDiary) { Label("Open Diary", systemImage: "calendar").frame(minHeight: 44) }
                    .accessibilityIdentifier("openDiaryForCoverage")
            } else {
                ProgressBucketChart(buckets: snapshot.buckets, range: snapshot.range, zone: snapshot.zone)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Calories by \(snapshot.range == .week || snapshot.range == .month ? "day" : snapshot.range == .quarter ? "week" : "month")")
                    .accessibilityValue(ProgressSummary.buckets(snapshot.buckets, zone: snapshot.zone))
            }
            // One sentence instead of a five-color key.
            Text("Teal bars landed near your target; orange gets deeper the further off. Empty days are never counted as zero.")
                .font(.caption).foregroundStyle(Color.diarySecondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("missingDayCopy")
            if let win = snapshot.wins.first {
                Label { Text(win.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.diaryText) } icon: {
                    Image(systemName: win.symbol).foregroundStyle(win.color)
                }
                .accessibilityIdentifier("progressWin")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.diarySummarySurface, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct ProgressMacrosCard: View {
    let snapshot: ProgressSnapshot
    @Environment(\.dynamicTypeSize) private var typeSize
    private struct Slice: Identifiable { let name: String; let grams: Double; let kcal: Double; let goal: Double?; let color: Color; var id: String { name } }
    private var slices: [Slice] {
        let goal = snapshot.goal?.targets, average = snapshot.averages
        return [Slice(name: "Protein", grams: average.protein ?? 0, kcal: (average.protein ?? 0) * 4, goal: goal?.protein, color: .diaryProtein),
                Slice(name: "Carbs", grams: average.carbs ?? 0, kcal: (average.carbs ?? 0) * 4, goal: goal?.carbs, color: .diaryCarbs),
                Slice(name: "Fat", grams: average.fat ?? 0, kcal: (average.fat ?? 0) * 9, goal: goal?.fat, color: .diaryFat)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressCardTitle(title: "Average day", detail: "\(snapshot.judgedDays) complete days")
            if slices.allSatisfy({ $0.kcal == 0 }) {
                ProgressPlaceholder(symbol: "chart.pie", text: "Log a full day to see your average macros.")
            } else {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 16) { donut.frame(width: 160, height: 160); legend }
                } else {
                    HStack(spacing: 18) { donut.frame(width: 132, height: 132); legend }
                }
            }
        }
        .diaryProgressCard()
    }

    private var donut: some View {
        Chart(slices) { slice in
            SectorMark(angle: .value("kcal", slice.kcal), innerRadius: .ratio(0.62), angularInset: 1.5)
                .foregroundStyle(slice.color).cornerRadius(4)
        }
        .chartBackground { _ in
            VStack(spacing: 0) {
                Text(snapshot.averageKcal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—").font(.title2.weight(.bold)).monospacedDigit()
                Text("kcal avg").font(.caption).foregroundStyle(Color.diarySecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Average macros")
        .accessibilityValue(slices.map { "\($0.name) \(Int($0.grams.rounded())) grams" }.joined(separator: ", "))
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(slices) { slice in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(slice.name) \(Int(slice.grams.rounded())) g").font(.subheadline.weight(.semibold)).foregroundStyle(slice.color)
                    if let goal = slice.goal, goal > 0 {
                        Text("of \(Int(goal.rounded())) g goal").font(.caption).foregroundStyle(Color.diarySecondary)
                        ProgressView(value: min(slice.grams, goal), total: goal).tint(slice.color)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct ProgressWeightCard: View {
    let snapshot: ProgressSnapshot
    private var trend: [TrendPoint] { snapshot.trend }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressCardTitle(title: "Weight trend", detail: snapshot.range.title, color: .diaryWeight)
            if let last = trend.last {
                HStack(alignment: .firstTextBaseline) {
                    Text(last.trend.formatted(.number.precision(.fractionLength(1)))).font(.system(.largeTitle, weight: .semibold)).monospacedDigit().foregroundStyle(Color.diaryWeight)
                    Text("kg").font(.title3).foregroundStyle(Color.diarySecondary)
                    Spacer()
                    if trend.count >= 2, let first = trend.first {
                        let change = (ProgressInsights.slopePerDay(trend) ?? 0) * Double(ProgressInsights.days(from: first.localDate, to: last.localDate))
                        Text("\(change <= 0 ? "↓" : "↑") \(abs(change).formatted(.number.precision(.fractionLength(1)))) kg")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.diaryWeight)
                            .padding(.horizontal, 10).padding(.vertical, 4).background(Color.diaryWeight.opacity(0.12), in: Capsule())
                    }
                }
                .accessibilityElement(children: .combine)
                chart
            }
            if trend.count < 3 {
                ProgressPlaceholder(symbol: "scalemass", text: "Weigh in on \(3 - trend.count) more \(3 - trend.count == 1 ? "day" : "days") to see your trend.")
            } else if let goal = snapshot.goal?.goalWeightKg, let start = snapshot.startKg, let last = trend.last {
                let total = abs(start - goal), done = max(0, total - abs(last.trend - goal))
                HStack { Text("Start \(start.formatted(.number.precision(.fractionLength(1)))) kg"); Spacer(); Text("Goal \(goal.formatted(.number.precision(.fractionLength(1)))) kg") }
                    .font(.caption).foregroundStyle(Color.diarySecondary)
                ProgressView(value: done, total: max(total, 0.1)).tint(Color.diaryWeight)
                Text("\(abs(last.trend - goal).formatted(.number.precision(.fractionLength(1)))) kg to go · faint dots are weigh-ins, the line smooths out water swings.")
                    .font(.footnote).foregroundStyle(Color.diarySecondary)
            } else {
                ProgressPlaceholder(symbol: "flag", text: "Add a goal weight to see how far is left.")
            }
        }
        .diaryProgressCard(fill: .diaryChartSurface)
    }

    private var chart: some View {
        Chart {
            ForEach(trend, id: \.localDate) { point in
                if let date = ProgressDate.date(point.localDate, zone: snapshot.zone) {
                    PointMark(x: .value("Date", date, unit: .day), y: .value("Weigh-in", point.raw))
                        .foregroundStyle(Color.diaryWeight.opacity(0.3)).symbolSize(30)
                    LineMark(x: .value("Date", date, unit: .day), y: .value("Trend", point.trend))
                        .foregroundStyle(Color.diaryWeight).lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round)).interpolationMethod(.monotone)
                }
            }
            if let goal = snapshot.goal?.goalWeightKg {
                RuleMark(y: .value("Goal", goal)).foregroundStyle(Color.diarySuccess)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) { Text("Goal").font(.caption2).foregroundStyle(Color.diarySuccess) }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .environment(\.timeZone, TimeZone(identifier: snapshot.zone) ?? .gmt)
        .frame(height: 160)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weight trend")
        .accessibilityValue(ProgressSummary.weights(trend))
    }
}

struct ProgressCaloriesCard: View {
    let snapshot: ProgressSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressCardTitle(title: "Calories vs target", detail: snapshot.range.title)
            Text([snapshot.averageKcal.map { "Average \(kcal($0))" }, snapshot.target.map { "target \(kcal($0))" } ?? "No energy target set"].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(Color.diarySecondary)
            if snapshot.loggedDays == 0 {
                ProgressPlaceholder(symbol: "chart.bar", text: "Log a meal to see your calories against your target.")
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
            ProgressCardTitle(title: "Estimated burn", color: .diarySuccess)
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
                ProgressPlaceholder(symbol: "flame", text: [days > 0 ? "Log \(days) more complete \(days == 1 ? "day" : "days")" : nil,
                                                            weighIns > 0 ? "weigh in \(weighIns) more \(weighIns == 1 ? "time" : "times")" : nil]
                    .compactMap { $0 }.joined(separator: " and ") + " to see your burn.")
            }
        }
        .diaryProgressCard(fill: .diaryTintBurn)
        .accessibilityElement(children: .combine)
    }
}

enum ProgressSummary {
    static func buckets(_ buckets: [ProgressBucket], zone: String) -> String {
        let logged = buckets.filter { $0.averageKcal != nil }
        guard !logged.isEmpty else { return "No logged days in this range." }
        return logged.map { bucket in
            "\(DiaryWeek.format(ProgressDate.label(bucket.start, zone: zone), "MMM d")): \(kcal(bucket.averageKcal ?? 0))\(bucket.band.map { ", \($0.title.lowercased())" } ?? "")"
        }.joined(separator: "; ")
    }
    static func weights(_ trend: [TrendPoint]) -> String {
        guard let last = trend.last else { return "No weigh-ins in this range." }
        return "\(trend.count) weigh-ins. Trend \(last.trend.formatted(.number.precision(.fractionLength(1)))) kg on \(last.localDate)."
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
