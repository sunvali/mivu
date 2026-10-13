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
    @State private var report = Report.daily
    @State private var showWorkout = false
    @State private var editingWeight: WeightEntry?
    @State private var selectedWeightDate: Date?
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Report { case daily, weekly, monthly }
    private struct Observation: Identifiable {
        let label: String
        let value: Double
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
        let start = ProgressAnalytics.period(snapshot: snapshot, endingOn: today, days: 30).startLocalDate
        let dayLabels = Dictionary(uniqueKeysWithValues: snapshot.days.map { ($0.id, $0.localDate) })
        let savedDates = Set(snapshot.meals.compactMap { $0.isSaved ? dayLabels[$0.dayID] : nil })
        return savedDates.filter { $0 >= start && $0 <= today }.sorted().compactMap { label in
            guard let value = ProgressAnalytics.daily(snapshot: snapshot, localDate: label).foodTotals?.kcal else { return nil }
            return Observation(label: label, value: value)
        }
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
    private var currentWeight: WeightEntry? {
        guard let snapshot else { return nil }
        let dayIDs = Set(snapshot.days.filter { $0.localDate == today && $0.timeZoneID == snapshot.profile.timeZoneID }.map(\.id))
        return snapshot.weights.first { $0.dayID.map(dayIDs.contains) == true }
    }

    var body: some View {
        List {
            if let snapshot, let daily {
                Section {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading) {
                            reportButton("Day", id: "reportDaily", value: .daily)
                            reportButton("7 days", id: "reportWeekly", value: .weekly)
                            reportButton("30 days", id: "reportMonthly", value: .monthly)
                        }
                    } else {
                        HStack {
                            reportButton("Day", id: "reportDaily", value: .daily)
                            reportButton("7 days", id: "reportWeekly", value: .weekly)
                            reportButton("30 days", id: "reportMonthly", value: .monthly)
                        }
                    }
                }
                Section {
                    if report == .daily {
                        Text("Daily report").font(.headline)
                        Text(today).foregroundStyle(Color.diarySecondary)
                        GoalSummaryView(report: daily, identifier: "progressGoalSummary")
                        Text(daily.completeness.map { "Coverage: \($0.rawValue)" } ?? "No tracking day recorded")
                            .font(.subheadline)
                        Text(daily.completeness == nil ? "No entry for this day. Missing does not mean zero intake." : "Missing dates are never counted as zero intake.")
                            .font(.caption).foregroundStyle(Color.diarySecondary).accessibilityIdentifier("missingDayCopy")
                    } else if let period {
                        Text(report == .weekly ? "7-day report" : "30-day report").font(.headline)
                        Text("\(period.startLocalDate) to \(period.endLocalDate)")
                            .foregroundStyle(Color.diarySecondary)
                        Text("\(period.completeDayCount) complete · \(period.partialDayCount) partial · \(period.missingDayCount) missing")
                        Text("\(period.missingDayCount) missing days were excluded; missing does not mean zero intake.")
                            .font(.caption).foregroundStyle(Color.diarySecondary).accessibilityIdentifier("missingDayCopy")
                        Text("Average recorded food: \(period.averageIntake.kcal.map { $0.formatted(.number.precision(.fractionLength(0))) + " kcal" } ?? "insufficient data")")
                        Text("Known samples of \(period.dayCount) dates: kcal \(period.knownIntakeSamples.kcal), carbs \(period.knownIntakeSamples.carbs), protein \(period.knownIntakeSamples.protein), fat \(period.knownIntakeSamples.fat)")
                        Text("Average recorded macros: carbs \(grams(period.averageIntake.carbs)), protein \(grams(period.averageIntake.protein)), fat \(grams(period.averageIntake.fat))")
                        Text("Within 10% of target: \(period.adherenceNumerator) of \(period.adherenceDenominator) eligible dates")
                        Text("Workout sessions: \(period.workoutCount)")
                    }
                }
                Section("Nutrition trend") {
                    if nutrition.isEmpty {
                        Text("Insufficient saved food data for a nutrition trend.")
                    } else {
                        Chart(nutrition) { point in
                            BarMark(x: .value("Date", point.label), y: .value("Recorded kcal", point.value))
                                .foregroundStyle(Color.diaryAccent)
                        }
                        .frame(height: 180).accessibilityHidden(true)
                    }
                    Text(nutritionSummary).font(.caption).foregroundStyle(Color.diarySecondary)
                        .accessibilityIdentifier("nutritionChartSummary")
                }
                Section("Weight trend") {
                    if weights.isEmpty {
                        Text("Insufficient measurements for a weight trend.")
                    } else {
                        Chart(weights) { point in
                            if weights.count >= 2 {
                                LineMark(x: .value("Date", point.date, unit: .day), y: .value("Weight kg", point.value))
                                    .foregroundStyle(Color.diaryLeaf)
                            }
                            PointMark(x: .value("Date", point.date, unit: .day), y: .value("Weight kg", point.value))
                                .foregroundStyle(Color.diaryLeaf)
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
                    Text(weightSummary).font(.caption).foregroundStyle(Color.diarySecondary)
                        .accessibilityIdentifier("weightChartSummary")
                    if let currentWeight {
                        Text("\(currentWeight.value.formatted()) \(currentWeight.unit)")
                        Button("Edit today's weight") { editingWeight = currentWeight }
                            .frame(minHeight: 44).accessibilityIdentifier("editWeight")
                    }
                }
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
                                    .font(.caption).foregroundStyle(Color.diarySecondary)
                            }
                            .frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("workoutRow")
                    }
                }
            } else {
                ContentUnavailableView("Choose your diary", systemImage: "person.crop.circle")
            }
        }
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .accessibilityIdentifier("progressList")
        .navigationTitle("Progress")
        .sheet(isPresented: $showWorkout) { WorkoutEditorView(model: model, localDate: today) }
        .sheet(item: $editingWeight) { WeightCorrectionView(model: model, entry: $0, localDate: today) }
        .onChange(of: model.snapshot?.profile.id) { _, _ in selectedWeightDate = nil }
    }

    private func reportButton(_ title: String, id: String, value: Report) -> some View {
        Button { report = value } label: { Text(title).frame(minHeight: 44) }
            .buttonStyle(.bordered)
            .tint(report == value ? .diaryAccent : .diaryLeaf)
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
                }
            }
        }
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("Workout")
        .sheet(isPresented: $editing) {
            if let snapshot = model.snapshot, let session = snapshot.workouts.first(where: { $0.id == sessionID }),
               let date = snapshot.days.first(where: { $0.id == session.dayID })?.localDate {
                WorkoutEditorView(model: model, localDate: date, session: session)
            }
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
