import Charts
import SwiftUI

struct GoalSummaryView: View {
    let report: DailyProgress
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your goals").font(.headline)
            if let goal = report.goal {
                if let target = goal.targets.kcal {
                    Text("\(target.formatted(.number.precision(.fractionLength(0)))) kcal goal")
                        .accessibilityIdentifier(identifier)
                } else {
                    Text("No energy target set").foregroundStyle(Color.diarySecondary)
                        .accessibilityIdentifier(identifier)
                }
                if let target = goal.targets.carbs { nutrient("Carbs", target: target, recorded: report.foodTotals?.carbs, remaining: report.remainingFromRecorded.carbs) }
                if let target = goal.targets.protein { nutrient("Protein", target: target, recorded: report.foodTotals?.protein, remaining: report.remainingFromRecorded.protein) }
                if let target = goal.targets.fat { nutrient("Fat", target: target, recorded: report.foodTotals?.fat, remaining: report.remainingFromRecorded.fat) }
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
    private func nutrient(_ name: String, target: Double, recorded: Double?, remaining: Double?) -> some View {
        Text("\(name) goal \(grams(target)); recorded \(grams(recorded)); remaining \(grams(remaining))")
            .font(.subheadline)
    }
    private func grams(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + " g" } ?? "unknown"
    }
}

struct DiaryProgressView: View {
    @Bindable var model: DiaryViewModel
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

    private enum Report { case daily, weekly, monthly }
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

    private var snapshot: DiarySnapshot? { model.snapshot }
    private var today: String {
        model.activeDay?.localDate
            ?? ProgressDate.label(Date(), zone: snapshot?.profile.timeZoneID ?? TimeZone.current.identifier)
    }
    private var daily: DailyProgress? {
        snapshot.map { ProgressAnalytics.daily(snapshot: $0, localDate: today) }
    }
    private var period: PeriodProgress? {
        guard let snapshot else { return nil }
        return ProgressAnalytics.period(snapshot: snapshot, endingOn: today, days: report == .monthly ? 30 : 7)
    }
    private var weightReport: WeightProgress? {
        snapshot.map { ProgressAnalytics.weight(snapshot: $0, endingOn: today) }
    }
    private var nutrition: [Observation] {
        guard let snapshot else { return [] }
        let start = report == .daily ? today : (period?.startLocalDate ?? today)
        let dayLabels = Dictionary(uniqueKeysWithValues: snapshot.days.map { ($0.id, $0.localDate) })
        let savedDates = Set(snapshot.meals.compactMap { $0.isSaved ? dayLabels[$0.dayID] : nil })
        return savedDates.filter { $0 >= start && $0 <= today }.sorted().compactMap { label in
            guard let value = ProgressAnalytics.daily(snapshot: snapshot, localDate: label).foodTotals?.kcal else { return nil }
            guard let date = ProgressDate.date(label, zone: snapshot.profile.timeZoneID) else { return nil }
            let day = ProgressAnalytics.daily(snapshot: snapshot, localDate: label)
            return Observation(label: label, value: value, date: date, complete: day.completeness == .complete, coverage: day.completeness?.rawValue.capitalized ?? "No tracking day")
        }
    }
    private var nutritionDomain: ClosedRange<Date> {
        let zone = snapshot?.profile.timeZoneID ?? TimeZone.current.identifier
        let start = ProgressDate.date(report == .daily ? today : (period?.startLocalDate ?? today), zone: zone) ?? Date()
        let last = ProgressDate.date(today, zone: zone) ?? start
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86_400)
        return start...end
    }
    var weights: [WeightObservation] {
        guard let snapshot else { return [] }
        let start = ProgressAnalytics.period(snapshot: snapshot, endingOn: today, days: 30).startLocalDate
        let latest = ProgressAnalytics.latestWeightsByDate(snapshot: snapshot)
        return latest.keys.filter { $0 >= start && $0 <= today }.sorted().compactMap { label in
            guard let entry = latest[label], let date = ProgressDate.date(label, zone: snapshot.profile.timeZoneID) else { return nil }
            return WeightObservation(label: label, date: date,
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
            if let snapshot, let daily {
                Section {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) { reportControls }
                    } else {
                        HStack(spacing: 8) { reportControls }
                    }
                }.listRowSeparator(.hidden)
                Section {
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
                            Text("Recorded intake").font(.headline).padding(.top, 12)
                            if typeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 0) { averageValue(period); Text("kcal").foregroundStyle(Color.diarySecondary) }
                            } else {
                                HStack(alignment: .firstTextBaseline, spacing: 8) { averageValue(period); Text("kcal").font(.title3).foregroundStyle(Color.diarySecondary) }
                            }
                            Text("Average · \(period.knownIntakeSamples.kcal) complete days with known energy")
                                .font(.subheadline).foregroundStyle(Color.diarySecondary)
                            if period.knownIntakeSamples.kcal == 0 {
                                Text("Not enough complete days").font(.headline)
                                NavigationLink {
                                    HistoryView(model: model).toolbar(.hidden, for: .tabBar)
                                } label: {
                                    Label("Open Diary", systemImage: "calendar").frame(minHeight: 44)
                                }.accessibilityIdentifier("openDiaryForCoverage")
                            }
                        }.padding(.vertical, 8)
                    }
                }.listRowSeparator(.hidden)
                Section("Nutrition trend") {
                    if nutrition.isEmpty {
                        Text("No saved food samples in this period.").foregroundStyle(Color.diarySecondary)
                    } else {
                        Chart(nutrition) { point in
                            BarMark(x: .value("Date", point.date, unit: .day), y: .value("Recorded kcal", point.value))
                                .foregroundStyle(point.complete ? Color.diaryAccent : Color.diaryAccent.opacity(0.45))
                        }
                        .chartXScale(domain: nutritionDomain)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: report == .monthly ? 7 : 1)) { _ in
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: true))
                        .environment(\.timeZone, TimeZone(identifier: snapshot.profile.timeZoneID) ?? .gmt)
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
                }
                Section {
                    NavigationLink { weightDetail } label: {
                        LabeledContent("Weight", value: snapshot.weights.max(by: { $0.measuredAt < $1.measuredAt }).map { "\($0.value.formatted()) \($0.unit)" } ?? "No measurements")
                            .frame(minHeight: 48).monospacedDigit()
                    }.accessibilityIdentifier("openWeight")
                    NavigationLink { workoutList(snapshot) } label: {
                        LabeledContent("Workouts", value: "\(snapshot.workouts.count) recorded").frame(minHeight: 48).monospacedDigit()
                    }.accessibilityIdentifier("openWorkouts")
                    Button { showGoals = true } label: {
                        HStack { Text("Goals").foregroundStyle(Color.diaryText); Spacer(); Text("Manage").foregroundStyle(Color.diarySecondary); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }.frame(minHeight: 48)
                    }.accessibilityIdentifier("editGoals")
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
                            Text("Average recorded macros: carbs \(grams(period.averageIntake.carbs)), protein \(grams(period.averageIntake.protein)), fat \(grams(period.averageIntake.fat))")
                            Text("Known samples of \(period.dayCount) dates: kcal \(period.knownIntakeSamples.kcal), carbs \(period.knownIntakeSamples.carbs), protein \(period.knownIntakeSamples.protein), fat \(period.knownIntakeSamples.fat)")
                            Text("Within 10% of target: \(period.adherenceNumerator) of \(period.adherenceDenominator) eligible dates")
                            Text("Workout sessions: \(period.workoutCount)")
                        } label: {
                            Text("Coverage & averages").accessibilityIdentifier("progressCoverage")
                                .accessibilityValue(coverageExpanded ? "Expanded" : "Collapsed")
                        }
                    }
                }
            } else {
                ContentUnavailableView("Choose your diary", systemImage: "person.crop.circle")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .accessibilityIdentifier("progressList")
        .navigationTitle("Progress")
        .sheet(isPresented: $showWorkout) { WorkoutEditorView(model: model, localDate: today) }
        .sheet(isPresented: $showGoals) { GoalEditorView(model: model) }
        .sheet(isPresented: $showWeight) { MorningWeightEditorView(model: model) }
        .sheet(item: $editingWeight) { WeightCorrectionView(model: model, entry: $0, localDate: weightDate($0)) }
        .onChange(of: model.snapshot?.profile.id) { _, _ in
            selectedWeightDate = nil; nutritionExpanded = false; coverageExpanded = false
        }
    }

    @ViewBuilder private var reportControls: some View {
        reportButton("Day", id: "reportDaily", value: .daily)
        reportButton("7 days", id: "reportWeekly", value: .weekly)
        reportButton("30 days", id: "reportMonthly", value: .monthly)
    }

    private func averageValue(_ period: PeriodProgress) -> some View {
        Text(period.averageIntake.kcal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
            .font(.system(size: metricSize, weight: .semibold)).monospacedDigit()
    }

    private var weightDetail: some View {
        List {
            if let latest = snapshot?.weights.max(by: { $0.measuredAt < $1.measuredAt }) {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Latest measurement").font(.subheadline).foregroundStyle(Color.diarySecondary)
                        Text("\(latest.value.formatted()) \(latest.unit)").font(.largeTitle.weight(.semibold)).monospacedDigit()
                        Text(weightDate(latest)).font(.subheadline).foregroundStyle(Color.diarySecondary)
                    }.padding(.vertical, 8)
                }
            }
                Section("Measurements · last 30 days") {
                    if weights.isEmpty {
                        Text("Insufficient measurements for a weight trend.")
                    } else {
                        Chart(weights) { point in
                            if weights.count >= 2 {
                                LineMark(x: .value("Date", point.date, unit: .day), y: .value("Weight kg", point.value))
                                    .foregroundStyle(Color.diaryAccent)
                            }
                            PointMark(x: .value("Date", point.date, unit: .day), y: .value("Weight kg", point.value))
                                .foregroundStyle(Color.diaryAccent)
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

                }

            if let snapshot {
                Section("Measurement ledger") {
                    ForEach(snapshot.weights.sorted { $0.measuredAt > $1.measuredAt }) { entry in
                        Button { editingWeight = entry } label: {
                            LabeledContent(weightDate(entry), value: "\(entry.value.formatted()) \(entry.unit)")
                                .foregroundStyle(Color.diaryText).monospacedDigit().frame(minHeight: 44)
                        }.accessibilityIdentifier("editWeight")
                    }
                }
            }
            Section {
                Button { showWeight = true } label: { Label("Log morning weight", systemImage: "plus").frame(minHeight: 44) }
                    .accessibilityIdentifier("logWeight")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("Weight").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func workoutList(_ snapshot: DiarySnapshot) -> some View {
        List {
                Section("Workouts") {
                    Button("Log workout") { showWorkout = true }
                        .frame(minHeight: 44).accessibilityIdentifier("logWorkout")
                    if snapshot.workouts.isEmpty {
                        Text("No workouts recorded yet.").foregroundStyle(Color.diarySecondary)
                    }
                    ForEach(snapshot.workouts.sorted { $0.performedAt > $1.performedAt }) { session in
                        NavigationLink {
                            WorkoutDetailView(model: model, sessionID: session.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.kind.title).font(.headline)
                                Text("\(workoutDate(session, snapshot: snapshot)) · \(session.durationMinutes) minutes")
                                    .font(.subheadline).foregroundStyle(Color.diarySecondary)
                            }
                            .frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("workoutRow")
                    }
                }

        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("Workouts").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func weightDate(_ entry: WeightEntry) -> String {
        snapshot?.days.first { $0.id == entry.dayID }?.localDate
            ?? ProgressDate.label(entry.measuredAt, zone: snapshot?.profile.timeZoneID ?? TimeZone.current.identifier)
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
    private func workoutDate(_ session: WorkoutSession, snapshot: DiarySnapshot) -> String {
        snapshot.days.first { $0.id == session.dayID }?.localDate
            ?? ProgressDate.label(session.performedAt, zone: snapshot.profile.timeZoneID)
    }
}

struct WorkoutDetailView: View {
    @Bindable var model: DiaryViewModel
    let sessionID: UUID
    @State private var editing = false
    @State private var pendingDeletion: WorkoutSession?
    @State private var deletionOwnerID: UUID?
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let snapshot = model.snapshot, let session = snapshot.workouts.first(where: { $0.id == sessionID }) {
                Section {
                    Text(session.kind.title).font(.title2.weight(.semibold))
                    Text("\(session.durationMinutes) minutes")
                    Text(session.timePrecision == .dateOnly ? "Time unspecified" : session.performedAt.formatted(date: .omitted, time: .shortened))
                    Text(session.estimatedBurnKcal.map { "Estimated burn: \($0.formatted()) kcal" } ?? "Estimated burn: unknown")
                }
                Section("Exercises") {
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
                }
                Section {
                    Button("Edit workout") { editing = true }.frame(minHeight: 44)
                        .accessibilityIdentifier("editWorkout")
                    Button("Delete workout", role: .destructive) {
                        deletionOwnerID = snapshot.profile.id
                        pendingDeletion = session
                    }.frame(minHeight: 44).accessibilityIdentifier("deleteWorkout")
                }
                if let message = model.errorMessage {
                    Section { Label(LocalizedStringKey(message), systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                }
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
                guard let owner = deletionOwnerID, model.snapshot?.profile.id == owner, !deleting else { return }
                deleting = true
                Task {
                    let success = await model.change {
                        try await model.store.deleteWorkout(id: session.id, expectedRevision: session.revision, expectedProfileID: owner)
                    }
                    deleting = false
                    if success && model.snapshot?.profile.id == owner { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text("This removes only this workout and its exercise details. Meals, weights and other workouts are preserved.")
        }
        .onChange(of: model.snapshot?.profile.id) { _, _ in pendingDeletion = nil; editing = false }
        .sheet(isPresented: $editing) {
            if let snapshot = model.snapshot, let session = snapshot.workouts.first(where: { $0.id == sessionID }),
               let date = snapshot.days.first(where: { $0.id == session.dayID })?.localDate {
                WorkoutEditorView(model: model, localDate: date, session: session)
            }
        }
    }

    private var deletionTitle: String {
        guard let session = pendingDeletion else { return "Delete workout?" }
        let date = model.snapshot?.days.first { $0.id == session.dayID }?.localDate ?? "its recorded day"
        return "Delete \(session.kind.title.lowercased()) workout on \(date)?"
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
