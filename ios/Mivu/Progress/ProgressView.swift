import Charts
import SwiftUI

struct GoalSummaryView: View {
    let report: DailyProgress
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text("Your goals") } icon: { Image(systemName: "target").foregroundStyle(Color.diaryEnergy) }.font(.headline)
            if let goal = report.goal {
                if let target = goal.targets.kcal {
                    Text("\(target.formatted(.number.precision(.fractionLength(0)))) kcal goal")
                        .accessibilityIdentifier(identifier)
                } else {
                    Text("No energy target set").foregroundStyle(Color.diarySecondary)
                        .accessibilityIdentifier(identifier)
                }
                if let target = goal.targets.carbs { nutrient("Carbs", color: .diaryCarbs, target: target, recorded: report.foodTotals?.carbs, remaining: report.remainingFromRecorded.carbs) }
                if let target = goal.targets.protein { nutrient("Protein", color: .diaryProtein, target: target, recorded: report.foodTotals?.protein, remaining: report.remainingFromRecorded.protein) }
                if let target = goal.targets.fat { nutrient("Fat", color: .diaryFat, target: target, recorded: report.foodTotals?.fat, remaining: report.remainingFromRecorded.fat) }
                if goal.exerciseCreditEnabled {
                    Text("Exercise-adjusted remaining: \(amount(report.exerciseAdjustedKcalRemaining))")
                }
            } else {
                Text("Set your own dated goals in Settings.").foregroundStyle(Color.diarySecondary)
                    .accessibilityIdentifier(identifier)
            }
            Text("Recorded food: \(amount(report.foodTotals?.kcal))")
            Text("Remaining from recorded food: \(amount(report.remainingFromRecorded.kcal))")
            Text("Estimated workout burn: \(amount(report.estimatedBurnKcal))")
            if report.completeness != .complete || report.hasPending {
                Text("Recorded amounts may be incomplete for this day.")
                    .font(.caption).foregroundStyle(Color.diarySecondary)
            }
        }
    }

    private func amount(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0))) + " kcal" } ?? "unknown"
    }
    private func nutrient(_ name: String, color: Color, target: Double, recorded: Double?, remaining: Double?) -> some View {
        Text("\(name) goal \(grams(target)); recorded \(grams(recorded)); remaining \(grams(remaining))")
            .font(.subheadline).foregroundStyle(color)
    }
    private func grams(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + " g" } ?? "unknown"
    }
}

struct DiaryProgressView: View {
    @Bindable var model: DiaryViewModel
    let openDiary: () -> Void
    @State private var report = Report.weekly
    @State private var showGoals = false
    @State private var showWeight = false
    @ScaledMetric(relativeTo: .largeTitle) private var metricSize = 48.0
    @State private var showWorkout = false
    @State private var editingWeight: WeightEntry?
    @State private var selectedWeightDate: Date?
    @State private var nutritionExpanded = false
    @State private var coverageExpanded = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Report: Equatable { case daily, weekly, monthly }
    private struct ReportRequest: Equatable {
        let ownership: DiarySelectionOwnership?
        let generation: UInt64
        let date: String
        let report: Report
    }
    private struct LedgerRequest: Equatable {
        let ownership: DiarySelectionOwnership?
        let generation: UInt64
        let before: Int?
    }
    @State private var progress: CoachProgress?
    @State private var loadedReport: ReportRequest?
    @State private var reportRequestID = UUID()
    @State private var loadError: String?
    @State private var weightPage: DiaryRecordPage<WeightEntry>?
    @State private var weightBefore: Int?
    @State private var loadedWeights: LedgerRequest?
    @State private var weightRequestID = UUID()
    @State private var weightDates: [UUID: String] = [:]
    @State private var weightError: String?
    @State private var workoutPage: DiaryRecordPage<WorkoutSession>?
    @State private var workoutBefore: Int?
    @State private var loadedWorkouts: LedgerRequest?
    @State private var workoutRequestID = UUID()
    @State private var workoutDates: [UUID: String] = [:]
    @State private var workoutError: String?
    private var reportRequest: ReportRequest {
        ReportRequest(ownership: model.selection, generation: model.changeGeneration, date: today, report: report)
    }
    private var weightRequest: LedgerRequest { LedgerRequest(ownership: model.selection, generation: model.changeGeneration, before: weightBefore) }
    private var workoutRequest: LedgerRequest { LedgerRequest(ownership: model.selection, generation: model.changeGeneration, before: workoutBefore) }
    private var visibleProgress: CoachProgress? {
        let request = reportRequest
        guard let loadedReport, loadedReport.ownership == request.ownership,
              loadedReport.date == request.date, loadedReport.report == request.report else { return nil }
        return progress
    }
    private var visibleWeights: [WeightEntry] { loadedWeights == weightRequest ? weightPage?.values ?? [] : [] }
    private var visibleWorkouts: [WorkoutSession] { loadedWorkouts == workoutRequest ? workoutPage?.values ?? [] : [] }
    private struct Observation: Identifiable {
        let label: String
        let value: Double
        let date: Date
        let complete: Bool
        let coverage: String
        var id: String { label }
    }
    struct WeightObservation: Identifiable {
        let label: String
        let date: Date
        let value: Double
        var id: String { label }
    }

    private var readModel: DiaryReadModel? { model.readModel }
    private var today: String {
        model.activeDay?.localDate
            ?? ProgressDate.label(Date(), zone: readModel?.profile.timeZoneID ?? TimeZone.current.identifier)
    }
    private var daily: DailyProgress? { visibleProgress?.daily }
    private var period: PeriodProgress? { visibleProgress?.period }
    private var weightReport: WeightProgress? { visibleProgress?.weight }
    private var nutrition: [Observation] {
        let zone = readModel?.profile.timeZoneID ?? TimeZone.current.identifier
        let savedDates = Set(visibleProgress?.savedFoodDates ?? [])
        return (visibleProgress?.dailyReports ?? []).compactMap { day in
            guard savedDates.contains(day.localDate), let value = day.foodTotals?.kcal, let date = ProgressDate.date(day.localDate, zone: zone) else { return nil }
            return Observation(label: day.localDate, value: value, date: date,
                               complete: day.completeness == .complete,
                               coverage: day.completeness?.rawValue.capitalized ?? "No tracking day")
        }
    }
    var nutritionDomain: ClosedRange<Date> {
        let zone = readModel?.profile.timeZoneID ?? TimeZone.current.identifier
        let firstLabel = report == .daily ? today : (ProgressAnalytics.window(endingOn: today, days: report == .monthly ? 30 : 7, offset: 0, zone: zone).first ?? today)
        let firstDate = ProgressDate.date(firstLabel, zone: zone) ?? Date()
        let lastDate = ProgressDate.date(today, zone: zone) ?? firstDate
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        let start = calendar.startOfDay(for: firstDate)
        let last = calendar.startOfDay(for: lastDate)
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86_400)
        return start...end
    }
    var weights: [WeightObservation] {
        Self.weightObservations(progress: visibleProgress, zone: readModel?.profile.timeZoneID ?? TimeZone.current.identifier)
    }
    static func weightObservations(progress: CoachProgress?, zone: String) -> [WeightObservation] {
        (progress?.displayWeights ?? []).sorted { $0.localDate < $1.localDate }.compactMap { reference in
            guard let date = ProgressDate.date(reference.localDate, zone: zone) else { return nil }
            let entry = reference.record
            return WeightObservation(label: reference.localDate, date: date,
                                     value: entry.unit == "lb" ? entry.value * 0.45359237 : entry.value)
        }
    }
    private var selectedWeight: WeightObservation? {
        guard let selectedWeightDate else { return nil }
        return weights.min {
            abs($0.date.timeIntervalSince(selectedWeightDate)) < abs($1.date.timeIntervalSince(selectedWeightDate))
        }
    }
    private var weightAxisDates: [Date] {
        let dates = weights.map(\.date)
        guard dates.count > 5 else { return dates }
        let last = dates.count - 1
        return [0, last / 4, last / 2, last * 3 / 4, last].map { dates[$0] }
    }

    var body: some View {
        List {
            if let readModel, let daily {
                Section {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) { reportControls }
                    } else {
                        HStack(spacing: 8) { reportControls }
                    }
                }.listRowSeparator(.hidden)
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        if report == .daily {
                            Text(today).font(.subheadline).foregroundStyle(Color.diarySecondary)
                            GoalSummaryView(report: daily, identifier: "progressGoalSummary")
                            Text(daily.completeness.map { "Coverage: \($0.rawValue)" } ?? "No tracking day recorded")
                                .font(.subheadline)
                            Text(daily.completeness == nil ? "No entry for this day. Missing does not mean zero intake." : "Missing dates are never counted as zero intake.")
                                .font(.subheadline).foregroundStyle(Color.diarySecondary).accessibilityIdentifier("missingDayCopy")
                        } else if let period {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(period.startLocalDate) to \(period.endLocalDate)")
                                    .font(.subheadline).foregroundStyle(Color.diarySecondary)
                                Text("\(period.completeDayCount) of \(period.dayCount) days complete")
                                    .font(.subheadline).foregroundStyle(Color.diarySecondary)
                                Label { Text("Recorded intake") } icon: { Image(systemName: "flame").foregroundStyle(Color.diaryEnergy) }.font(.title3.weight(.bold)).padding(.top, 12)
                                if typeSize.isAccessibilitySize {
                                    VStack(alignment: .leading, spacing: 0) { averageValue(period); Text("kcal").foregroundStyle(Color.diarySecondary) }
                                } else {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) { averageValue(period); Text("kcal").font(.title3).foregroundStyle(Color.diarySecondary) }
                                }
                                Text("Average · \(period.knownIntakeSamples.kcal) complete days with known energy")
                                    .font(.subheadline).foregroundStyle(Color.diarySecondary)
                                if period.knownIntakeSamples.kcal == 0 {
                                    Text("Not enough complete days").font(.headline)
                                    Button(action: openDiary) {
                                        Label("Open Diary", systemImage: "calendar").frame(minHeight: 44)
                                    }.accessibilityIdentifier("openDiaryForCoverage")
                                }
                            }.padding(.vertical, 8)
                        }
                    }.diarySummaryCard()
                }
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Label { Text("Nutrition trend") } icon: { Image(systemName: "chart.bar").foregroundStyle(Color.diaryEnergy) }
                            .font(.title3.weight(.bold))
                        if nutrition.isEmpty {
                            Text("No saved food samples in this period.").foregroundStyle(Color.diarySecondary)
                        } else {
                            Chart(nutrition) { point in
                                BarMark(x: .value("Date", point.date, unit: .day), y: .value("Recorded kcal", point.value))
                                    .foregroundStyle(point.complete ? Color.diaryEnergy : Color.diaryEnergy.opacity(0.70))
                            }
                            .chartXScale(domain: nutritionDomain)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: report == .monthly ? 7 : 1)) { _ in
                                    AxisGridLine()
                                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                }
                            }
                            .chartYScale(domain: .automatic(includesZero: true))
                            .environment(\.timeZone, TimeZone(identifier: readModel.profile.timeZoneID) ?? .gmt)
                            .frame(height: 200).accessibilityHidden(true)
                            Text("Lighter bars show days without complete coverage. Missing days have no bar.")
                                .font(.subheadline).foregroundStyle(Color.diarySecondary)
                        }
                        DisclosureGroup(isExpanded: $nutritionExpanded) {
                            ForEach(nutrition) { point in
                                VStack(alignment: .leading, spacing: 4) {
                                    LabeledContent(point.label, value: "\(point.value.formatted(.number.precision(.fractionLength(0)))) kcal").monospacedDigit()
                                    Text(point.coverage).font(.subheadline).foregroundStyle(Color.diarySecondary)
                                }
                            }
                            Text(nutritionSummary).font(.subheadline).foregroundStyle(Color.diarySecondary)
                                .accessibilityIdentifier("nutritionChartSummary")
                        } label: {
                            Text("Recorded intake data").accessibilityIdentifier("nutritionData")
                                .accessibilityValue(nutritionExpanded ? "Expanded" : "Collapsed")
                        }
                    }.diarySummaryCard()
                }
                Section {
                    NavigationLink { weightDetail } label: {
                        LabeledContent("Weight", value: (visibleProgress?.latestWeight?.record).map { "\($0.value.formatted()) \($0.unit)" } ?? "No measurements")
                            .frame(minHeight: 48).monospacedDigit()
                    }.accessibilityIdentifier("openWeight").diarySummaryCard()
                    NavigationLink { workoutList } label: {
                        LabeledContent("Workouts", value: "\(visibleProgress?.workoutTotal ?? 0) recorded").frame(minHeight: 48).monospacedDigit()
                    }.accessibilityIdentifier("openWorkouts").diarySummaryCard()
                    Button { showGoals = true } label: {
                        HStack { Text("Goals").foregroundStyle(Color.diaryText); Spacer(); Text("Manage").foregroundStyle(Color.diarySecondary); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }.frame(minHeight: 48)
                    }.accessibilityIdentifier("editGoals").diarySummaryCard()
                }
                if report != .daily, let period {
                    Section {
                        DisclosureGroup(isExpanded: $coverageExpanded) {
                            LabeledContent("Complete", value: period.completeDayCount.formatted())
                            LabeledContent("Partial", value: period.partialDayCount.formatted())
                            LabeledContent("Unknown", value: period.unknownDayCount.formatted())
                            LabeledContent("Untracked", value: period.untrackedDayCount.formatted())
                            LabeledContent("Missing", value: period.missingDayCount.formatted())
                            LabeledContent("Pending analysis", value: period.pendingDayCount.formatted())
                            Text("\(period.missingDayCount) missing days were excluded; missing does not mean zero intake.")
                                .font(.subheadline).foregroundStyle(Color.diarySecondary).accessibilityIdentifier("missingDayCopy")
                            Text("Average recorded macros: \(Text("carbs \(grams(period.averageIntake.carbs))").foregroundColor(.diaryCarbs)), \(Text("protein \(grams(period.averageIntake.protein))").foregroundColor(.diaryProtein)), \(Text("fat \(grams(period.averageIntake.fat))").foregroundColor(.diaryFat))")
                            Text("Known samples of \(period.dayCount) dates: kcal \(period.knownIntakeSamples.kcal), \(Text("carbs \(period.knownIntakeSamples.carbs)").foregroundColor(.diaryCarbs)), \(Text("protein \(period.knownIntakeSamples.protein)").foregroundColor(.diaryProtein)), \(Text("fat \(period.knownIntakeSamples.fat)").foregroundColor(.diaryFat))")
                            Text("Within 10% of target: \(period.adherenceNumerator) of \(period.adherenceDenominator) eligible dates")
                            Text("Workout sessions: \(period.workoutCount)")
                        } label: {
                            Label { Text("Coverage & averages") } icon: { Image(systemName: "checkmark.circle").foregroundStyle(Color.diaryEnergy) }.accessibilityIdentifier("progressCoverage")
                                .accessibilityValue(coverageExpanded ? "Expanded" : "Collapsed")
                        }.diarySummaryCard()
                    }
                }
            } else if model.selection != nil {
                if let loadError {
                    Section {
                        Text(loadError).foregroundStyle(Color.diaryError)
                        Button("Retry loading progress") { Task { await reloadProgress() } }.frame(minHeight: 44)
                    }
                } else { ProgressView("Loading progress…") }
            } else {
                ContentUnavailableView("Choose your diary", systemImage: "person.crop.circle")
            }
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .listSectionSpacing(12)
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .accessibilityIdentifier("progressList")
        .navigationTitle("Progress")
        .sheet(isPresented: $showWorkout) { WorkoutEditorView(model: model, localDate: today) }
        .sheet(isPresented: $showGoals) { GoalEditorView(model: model) }
        .sheet(isPresented: $showWeight) { MorningWeightEditorView(model: model) }
        .sheet(item: $editingWeight) { WeightCorrectionView(model: model, entry: $0, localDate: weightDate($0)) }
        .task(id: reportRequest) { await reloadProgress() }
        .onChange(of: model.selection) { _, _ in
            selectedWeightDate = nil; nutritionExpanded = false; coverageExpanded = false
            weightBefore = nil; workoutBefore = nil; editingWeight = nil
            showGoals = false; showWeight = false; showWorkout = false
        }
    }

    @ViewBuilder private var reportControls: some View {
        reportButton("Day", id: "reportDaily", value: .daily)
        reportButton("7 days", id: "reportWeekly", value: .weekly)
        reportButton("30 days", id: "reportMonthly", value: .monthly)
    }

    private func averageValue(_ period: PeriodProgress) -> some View {
        Text(period.averageIntake.kcal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
            .font(.system(size: metricSize, weight: .semibold)).monospacedDigit().foregroundStyle(Color.diaryEnergy)
    }

    private var weightDetail: some View {
        List {
            if let latest = visibleProgress?.latestWeight?.record {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Latest measurement").font(.subheadline).foregroundStyle(Color.diarySecondary)
                        Text("\(latest.value.formatted()) \(latest.unit)").font(.largeTitle.weight(.semibold)).monospacedDigit().foregroundStyle(Color.diaryWeight)
                        Text(weightDate(latest)).font(.subheadline).foregroundStyle(Color.diarySecondary)
                    }.padding(.vertical, 8)
                }.listRowBackground(Color.diarySummarySurface)
            }
                Section {
                    if weights.isEmpty {
                        Text("Insufficient measurements for a weight trend.")
                    } else {
                        Chart(weights) { point in
                            if weights.count >= 2 {
                                LineMark(x: .value("Date", point.date, unit: .day), y: .value("Weight kg", point.value))
                                    .foregroundStyle(Color.diaryWeight)
                            }
                            PointMark(x: .value("Date", point.date, unit: .day), y: .value("Weight kg", point.value))
                                .foregroundStyle(Color.diaryWeight)
                        }
                        .chartXSelection(value: $selectedWeightDate)
                        .chartGesture { proxy in
                            SpatialTapGesture()
                                .onEnded { proxy.selectXValue(at: $0.location.x) }
                        }
                        .chartXAxis {
                            AxisMarks(values: weightAxisDates) { axis in
                                AxisGridLine()
                                AxisTick()
                                if let date = axis.as(Date.self),
                                   let point = weights.first(where: { $0.date == date }) {
                                    AxisValueLabel { Text(String(point.label.suffix(5))) }
                                }
                            }
                        }
                        .frame(height: 180)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("weightChart")
                        if weights.count < 2 { Text("One measurement; a trend needs another date.") }
                        if let selectedWeight {
                            Text("Selected \(selectedWeight.label): \(selectedWeight.value.formatted(.number.precision(.fractionLength(1)))) kg")
                                .accessibilityIdentifier("selectedWeight")
                        }
                    }
                    Text(weightSummary).font(.subheadline).foregroundStyle(Color.diarySecondary)
                        .accessibilityIdentifier("weightChartSummary")

                } header: {
                    Label { Text("Measurements · last 30 days") } icon: { Image(systemName: "chart.xyaxis.line").foregroundStyle(Color.diaryWeight) }
                }
                .listRowBackground(Color.diaryChartSurface)

            Section("Measurement ledger") {
                    if let weightError {
                        Text(weightError).foregroundStyle(Color.diaryError)
                        Button("Retry loading measurements") { Task { await loadWeights() } }.frame(minHeight: 44)
                    } else if loadedWeights != weightRequest { ProgressView("Loading measurements…") }
                    ForEach(visibleWeights.sorted { $0.measuredAt > $1.measuredAt }) { entry in
                        Button { editingWeight = entry } label: {
                            LabeledContent(weightDate(entry), value: "\(entry.value.formatted()) \(entry.unit)")
                                .foregroundStyle(Color.diaryText).monospacedDigit().frame(minHeight: 44)
                        }.accessibilityIdentifier("editWeight")
                    }
                    if loadedWeights == weightRequest, weightPage?.hasMore == true {
                        Button("Older measurements") { weightBefore = weightPage?.cursor }.frame(minHeight: 44)
                    }
                    if weightBefore != nil {
                        Button("Latest measurements") { weightBefore = nil }.frame(minHeight: 44)
                    }
                }
            Section {
                Button { showWeight = true } label: { Label("Add weight manually", systemImage: "plus").frame(minHeight: 44) }
                    .accessibilityIdentifier("logWeight")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("Weight").navigationBarTitleDisplayMode(.inline)
        .task(id: weightRequest) { await loadWeights() }
        .toolbar(.hidden, for: .tabBar)
    }

    private var workoutList: some View {
        List {
                Section {
                    Button("Add workout manually") { showWorkout = true }
                        .frame(minHeight: 44).accessibilityIdentifier("logWorkout")
                    if let workoutError {
                        Text(workoutError).foregroundStyle(Color.diaryError)
                        Button("Retry loading workouts") { Task { await loadWorkouts() } }.frame(minHeight: 44)
                    } else if loadedWorkouts != workoutRequest { ProgressView("Loading workouts…") }
                    else if visibleWorkouts.isEmpty {
                        Text("No workouts recorded yet.").foregroundStyle(Color.diarySecondary)
                    }
                    ForEach(visibleWorkouts.sorted { $0.performedAt > $1.performedAt }) { session in
                        NavigationLink {
                            WorkoutDetailView(model: model, sessionID: session.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.kind.title).font(.headline)
                                Text("\(workoutDate(session)) · \(session.durationMinutes) minutes")
                                    .font(.subheadline).foregroundStyle(Color.diarySecondary)
                            }
                            .frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("workoutRow")
                    }
                    if loadedWorkouts == workoutRequest, workoutPage?.hasMore == true {
                        Button("Older workouts") { workoutBefore = workoutPage?.cursor }.frame(minHeight: 44)
                    }
                    if workoutBefore != nil {
                        Button("Latest workouts") { workoutBefore = nil }.frame(minHeight: 44)
                    }
                } header: {
                    Label { Text("Workouts") } icon: { Image(systemName: "figure.run").foregroundStyle(Color.diaryWorkout) }
                }

        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("Workouts").navigationBarTitleDisplayMode(.inline)
        .task(id: workoutRequest) { await loadWorkouts() }
        .toolbar(.hidden, for: .tabBar)
    }

    private func weightDate(_ entry: WeightEntry) -> String {
        entry.dayID.flatMap { weightDates[$0] }
            ?? (visibleProgress?.latestWeight?.record.id == entry.id ? visibleProgress?.latestWeight?.localDate : nil)
            ?? ProgressDate.label(entry.measuredAt, zone: readModel?.profile.timeZoneID ?? TimeZone.current.identifier)
    }

    private func reportButton(_ title: String, id: String, value: Report) -> some View {
        Button { report = value } label: { Text(title).frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(.bordered)
            .tint(report == value ? .diaryAccent : .diarySecondary)
            .accessibilityAddTraits(report == value ? .isSelected : [])
            .accessibilityIdentifier(id)
    }

    private var nutritionSummary: String {
        guard !nutrition.isEmpty else { return "Nutrition chart: no saved food samples; insufficient data." }
        let values = nutrition.map { "\($0.label): \($0.value.formatted(.number.precision(.fractionLength(0)))) kcal" }
        return "Nutrition chart: \(nutrition.count) recorded dates. " + values.joined(separator: "; ")
    }
    private func grams(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + " g" } ?? "insufficient data"
    }
    private var weightSummary: String {
        let samples = weights.map { "\($0.label): \($0.value.formatted(.number.precision(.fractionLength(1)))) kg" }
        let average = weightReport?.currentSevenDayAverageKg.map { "Seven-day average \($0.formatted(.number.precision(.fractionLength(1)))) kg from \(weightReport!.currentSevenDayObservedCount) dates." }
            ?? "Seven-day average: insufficient data."
        let change = weightReport?.changeFromSevenDaysAgoKg.map { "Seven-day change \($0.formatted(.number.precision(.fractionLength(1)))) kg." }
            ?? "Seven-day change: insufficient data."
        return "Weight chart: \(weights.count) measured dates. " + average + " " + change + " " + samples.joined(separator: "; ")
    }
    private func workoutDate(_ session: WorkoutSession) -> String {
        workoutDates[session.dayID]
            ?? ProgressDate.label(session.performedAt, zone: readModel?.profile.timeZoneID ?? TimeZone.current.identifier)
    }

    private func reloadProgress() async {
        let key = reportRequest, requestID = UUID()
        guard let ownership = key.ownership, model.selection == ownership else { return }
        reportRequestID = requestID; loadError = nil
        do {
            let value = try await Self.loadProgress(model: model, endingOn: key.date,
                days: key.report == .daily ? 1 : (key.report == .monthly ? 30 : 7))
            guard !Task.isCancelled, model.selection == ownership, reportRequest == key, reportRequestID == requestID else { return }
            progress = value; loadedReport = key
        } catch {
            guard !Task.isCancelled, model.selection == ownership, reportRequest == key, reportRequestID == requestID else { return }
            loadError = "Could not load progress. Your diary is preserved."; return
        }
    }

    static func loadProgress(model: DiaryViewModel, endingOn: String, days: Int) async throws -> CoachProgress {
        guard let ownership = model.selection else { throw DiaryError.wrongOwner }
        let generation = model.changeGeneration
        let report = try await model.store.progressForDisplay(endingOn: endingOn, days: days, expectedProfileID: ownership.identity.profileID)
        guard !Task.isCancelled, model.selection == ownership else { throw DiaryError.wrongOwner }
        guard model.changeGeneration == generation else { throw DiaryError.staleRevision }
        return report
    }

    private func loadWeights() async {
        let key = weightRequest, requestID = UUID()
        guard let ownership = key.ownership, model.selection == ownership else { return }
        weightRequestID = requestID; weightError = nil
        do {
            let page = try await model.store.weightHistory(before: key.before, expectedProfileID: ownership.identity.profileID)
            var dates: [UUID: String] = [:]
            for id in Set(page.values.compactMap(\.dayID)) {
                guard !Task.isCancelled, model.selection == ownership, weightRequest == key, weightRequestID == requestID else { return }
                dates[id] = try await model.store.trackingDay(id: id, expectedProfileID: ownership.identity.profileID).localDate
            }
            guard !Task.isCancelled, model.selection == ownership, weightRequest == key, weightRequestID == requestID else { return }
            weightPage = page; weightDates = dates; loadedWeights = key
        } catch {
            guard !Task.isCancelled, model.selection == ownership, weightRequest == key, weightRequestID == requestID else { return }
            weightError = "Could not load measurements. Your diary is preserved."
        }
    }

    private func loadWorkouts() async {
        let key = workoutRequest, requestID = UUID()
        guard let ownership = key.ownership, model.selection == ownership else { return }
        workoutRequestID = requestID; workoutError = nil
        do {
            let page = try await model.store.workoutHistory(before: key.before, expectedProfileID: ownership.identity.profileID)
            var dates: [UUID: String] = [:]
            for id in Set(page.values.map(\.dayID)) {
                guard !Task.isCancelled, model.selection == ownership, workoutRequest == key, workoutRequestID == requestID else { return }
                dates[id] = try await model.store.trackingDay(id: id, expectedProfileID: ownership.identity.profileID).localDate
            }
            guard !Task.isCancelled, model.selection == ownership, workoutRequest == key, workoutRequestID == requestID else { return }
            workoutPage = page; workoutDates = dates; loadedWorkouts = key
        } catch {
            guard !Task.isCancelled, model.selection == ownership, workoutRequest == key, workoutRequestID == requestID else { return }
            workoutError = "Could not load workouts. Your diary is preserved."
        }
    }
}

struct WorkoutDetailView: View {
    @Bindable var model: DiaryViewModel
    let sessionID: UUID
    private struct WorkoutEdit: Identifiable {
        let session: WorkoutSession
        let localDate: String
        var id: UUID { session.id }
    }
    @State private var editingWorkout: WorkoutEdit?
    @State private var pendingDeletion: WorkoutSession?
    @State private var ownership: DiarySelectionOwnership?
    @State private var session: WorkoutSession?
    @State private var day: TrackingDay?
    @State private var loadedGeneration: UInt64?
    @State private var requestID = UUID()
    @State private var loadError: String?
    @State private var loading = true
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss

    init(model: DiaryViewModel, sessionID: UUID) {
        self.model = model; self.sessionID = sessionID
        _ownership = State(initialValue: model.selection)
    }

    private var currentSession: WorkoutSession? {
        model.selection == ownership && loadedGeneration == model.changeGeneration ? session : nil
    }

    var body: some View {
        List {
            if let session = currentSession {
                Section {
                    Text(session.kind.title).font(.title2.weight(.semibold))
                    Text("\(session.durationMinutes) minutes")
                    Text(session.timePrecision == .dateOnly ? "Time unspecified" : session.performedAt.formatted(date: .omitted, time: .shortened))
                    Text(session.estimatedBurnKcal.map { "Estimated burn: \($0.formatted()) kcal" } ?? "Estimated burn: unknown")
                }
                Section {
                    if session.exercises.isEmpty { Text("No exercise details recorded.") }
                    ForEach(session.exercises.indices, id: \.self) { exerciseIndex in
                        let exercise = session.exercises[exerciseIndex]
                        VStack(alignment: .leading) {
                            Text(exercise.name).font(.headline)
                            ForEach(exercise.sets.indices, id: \.self) { index in
                                let set = exercise.sets[index]
                                Text("Set \(index + 1): \(set.repetitions) repetitions · \(set.loadKg.map { "\($0.formatted()) kg" } ?? "bodyweight")")
                            }
                        }
                    }
                } header: {
                    Label { Text("Exercises") } icon: { Image(systemName: "dumbbell").foregroundStyle(Color.diaryWorkout) }
                }
                Section {
                    Button("Edit workout") {
                        guard let day else { return }
                        editingWorkout = WorkoutEdit(session: session, localDate: day.localDate)
                    }.frame(minHeight: 44)
                        .accessibilityIdentifier("editWorkout")
                    Button("Delete workout", role: .destructive) {
                        pendingDeletion = session
                    }.frame(minHeight: 44).accessibilityIdentifier("deleteWorkout")
                }
                if let message = model.errorMessage {
                    Section { Label(LocalizedStringKey(message), systemImage: "exclamationmark.circle").foregroundStyle(Color.diaryError) }
                }
            } else if loading { ProgressView("Loading workout…") }
            else {
                ContentUnavailableView(loadError ?? "Workout unavailable", systemImage: "figure.run")
                Button("Reload workout") { Task { await loadSession() } }.frame(minHeight: 44)
            }
        }
        .disabled(deleting)
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .listStyle(.plain)
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .alert(deletionTitle, isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), presenting: pendingDeletion) { session in
            Button("Delete workout", role: .destructive) {
                guard let ownership, model.selection == ownership, !deleting else { return }
                let owner = ownership.identity.profileID
                deleting = true
                Task {
                    guard model.selection == ownership else { deleting = false; return }
                    let success = await model.change {
                        try await model.store.deleteWorkout(id: session.id, expectedRevision: session.revision, expectedProfileID: owner)
                    }
                    deleting = false
                    if success && model.selection == ownership { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text("This removes only this workout and its exercise details. Meals, weights and other workouts are preserved.")
        }
        .task(id: model.changeGeneration) { await loadSession() }
        .onChange(of: model.selection) { _, selected in
            pendingDeletion = nil; editingWorkout = nil
            if selected != ownership { dismiss() }
        }
        .sheet(item: $editingWorkout) { edit in
            WorkoutEditorView(model: model, localDate: edit.localDate, session: edit.session)
        }
    }

    private var deletionTitle: String {
        guard let session = pendingDeletion else { return "Delete workout?" }
        let date = day?.localDate ?? "its recorded day"
        return "Delete \(session.kind.title.lowercased()) workout on \(date)?"
    }

    private func loadSession() async {
        guard let ownership, model.selection == ownership else { return }
        let generation = model.changeGeneration, request = UUID()
        requestID = request; loading = true; loadError = nil
        do {
            let value = try await model.store.coachWorkout(id: sessionID, expectedProfileID: ownership.identity.profileID)
            guard !Task.isCancelled, model.selection == ownership, model.changeGeneration == generation, requestID == request else { return }
            let recordedDay = try await model.store.trackingDay(id: value.dayID, expectedProfileID: ownership.identity.profileID)
            guard !Task.isCancelled, model.selection == ownership, model.changeGeneration == generation, requestID == request else { return }
            session = value; day = recordedDay; loadedGeneration = generation; loading = false
        } catch {
            guard !Task.isCancelled, model.selection == ownership, model.changeGeneration == generation, requestID == request else { return }
            session = nil; day = nil; loading = false
            loadError = "Could not load this workout. It may have been removed."
        }
    }

}

private extension WorkoutKind {
    var title: String {
        switch self {
        case .strength: "Strength"
        case .cardio: "Cardio"
        case .other: "Other"
        }
    }
}
