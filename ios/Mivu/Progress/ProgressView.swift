import Charts
import SwiftUI

struct DiaryProgressView: View {
    @Bindable var model: DiaryViewModel
    let openDiary: () -> Void
    @State private var range = ProgressRange.week
    @State private var showGoals = false
    @State private var showWeight = false
    @State private var showWorkout = false
    @State private var editingWeight: WeightEntry?
    @State private var selectedWeightDate: Date?
    @State private var companionRuntime = CompanionRuntime()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openDiaryCoach) private var openChat

    private struct ReportRequest: Equatable {
        let ownership: DiarySelectionOwnership?
        let generation: UInt64
        let date: String
        let range: ProgressRange
    }
    private struct LedgerRequest: Equatable {
        let ownership: DiarySelectionOwnership?
        let generation: UInt64
        let before: Int?
    }
    @State private var progress: CoachProgress?
    @State private var foods: [TopFood] = []
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
        ReportRequest(ownership: model.selection, generation: model.changeGeneration, date: today, range: range)
    }
    private var weightRequest: LedgerRequest { LedgerRequest(ownership: model.selection, generation: model.changeGeneration, before: weightBefore) }
    private var workoutRequest: LedgerRequest { LedgerRequest(ownership: model.selection, generation: model.changeGeneration, before: workoutBefore) }
    private var visibleProgress: CoachProgress? {
        let request = reportRequest
        guard let loadedReport, loadedReport.ownership == request.ownership,
              loadedReport.date == request.date, loadedReport.range == request.range else { return nil }
        return progress
    }
    private var visibleWeights: [WeightEntry] { loadedWeights == weightRequest ? weightPage?.values ?? [] : [] }
    private var visibleWorkouts: [WorkoutSession] { loadedWorkouts == workoutRequest ? workoutPage?.values ?? [] : [] }
    struct WeightObservation: Identifiable {
        let label: String
        let date: Date
        let value: Double
        var id: String { label }
    }

    private var readModel: DiaryReadModel? { model.readModel }
    private var zone: String { readModel?.profile.timeZoneID ?? TimeZone.current.identifier }
    private var today: String {
        model.activeDay?.localDate ?? ProgressDate.label(Date(), zone: zone)
    }
    private var weightReport: WeightProgress? { visibleProgress?.weight }
    private var snapshot: ProgressSnapshot? { visibleProgress.map { ProgressSnapshot(progress: $0, range: range, zone: zone) } }
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
            if readModel != nil, let snapshot, let progress = visibleProgress {
                Section {
                    Picker("Range", selection: $range) {
                        ForEach(ProgressRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("progressRange")
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    .listRowBackground(Color.clear)
                }.listRowSeparator(.hidden)
                Section {
                    ProgressHeadlineCard(snapshot: snapshot, dates: dates(progress), companion: companion(snapshot.headline))
                        .listCardRow()
                    if !snapshot.wins.isEmpty {
                        ProgressWinsRow(wins: snapshot.wins).listCardRow()
                    }
                    ProgressMacrosCard(snapshot: snapshot).listCardRow()
                    NavigationLink { weightDetail } label: { ProgressWeightCard(snapshot: snapshot) }
                        .buttonStyle(.plain).accessibilityIdentifier("openWeight").listCardRow()
                    ProgressCalendarCard(snapshot: snapshot, openDiary: openDiary).listCardRow()
                    ProgressCaloriesCard(snapshot: snapshot).listCardRow()
                    ProgressBurnCard(snapshot: snapshot).listCardRow()
                    ProgressTopFoodsCard(foods: foods).listCardRow()
                }.listRowSeparator(.hidden)
                Section {
                    NavigationLink { workoutList } label: {
                        LabeledContent("Workouts", value: "\(progress.workoutTotal ?? 0) recorded").frame(minHeight: 48).monospacedDigit()
                    }.accessibilityIdentifier("openWorkouts").diarySummaryCard()
                    Button { showGoals = true } label: {
                        HStack { Text("Goals").foregroundStyle(Color.diaryText); Spacer(); Text("Manage").foregroundStyle(Color.diarySecondary); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }.frame(minHeight: 48)
                    }.accessibilityIdentifier("editGoals").diarySummaryCard()
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
        .task(id: snapshot?.headline.celebrates) {
            guard let snapshot else { return }
            await companionRuntime.select(CharacterCatalog.bundled.resolve("pip"))
            await companionRuntime.attach(eligible: true)
            await companionRuntime.apply(companionOutput(snapshot.headline), darkMode: colorScheme == .dark)
        }
        .onDisappear { companionRuntime.stop() }
        .onChange(of: model.selection) { _, _ in
            selectedWeightDate = nil
            weightBefore = nil; workoutBefore = nil; editingWeight = nil
            showGoals = false; showWeight = false; showWorkout = false
        }
    }

    /// Pip cheers a good period and greets an off one; never a sad pose.
    private func companionOutput(_ headline: ProgressHeadline) -> CompanionOutput {
        CompanionOutput(pose: headline.celebrates ? .dayComplete : .welcomeBack, playback: reduceMotion ? .staticPose : .animated, reactionID: nil, nextDeadline: nil)
    }
    private func companion(_ headline: ProgressHeadline) -> CompanionView {
        CompanionView(presentation: companionOutput(headline), darkMode: colorScheme == .dark, size: typeSize.isAccessibilitySize ? 64 : 104, runtime: companionRuntime)
    }
    private func dates(_ progress: CoachProgress) -> String {
        let format = range.days > 30 ? "MMM d, yyyy" : "MMM d"
        return "\(DiaryWeek.format(progress.startLocalDate, format)) – \(DiaryWeek.format(progress.endLocalDate, format))"
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
                        .contextMenu { askPipButton("askPipWeight", weightPrompt(entry)) }
                        .swipeActions(edge: .leading) { askPipButton("askPipWeight", weightPrompt(entry)).tint(.diaryAccent) }
                        .accessibilityAction(named: "Ask Pip", weightPrompt(entry))
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
                        .contextMenu { askPipButton("askPipWorkout", workoutPrompt(session)) }
                        .swipeActions(edge: .leading) { askPipButton("askPipWorkout", workoutPrompt(session)).tint(.diaryAccent) }
                        .accessibilityAction(named: "Ask Pip", workoutPrompt(session))
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

    private var weightSummary: String {
        let samples = weights.map { "\($0.label): \($0.value.formatted(.number.precision(.fractionLength(1)))) kg" }
        let average = weightReport?.currentSevenDayAverageKg.map { "Seven-day average \($0.formatted(.number.precision(.fractionLength(1)))) kg from \(weightReport!.currentSevenDayObservedCount) dates." }
            ?? "Seven-day average: insufficient data."
        let change = weightReport?.changeFromSevenDaysAgoKg.map { "Seven-day change \($0.formatted(.number.precision(.fractionLength(1)))) kg." }
            ?? "Seven-day change: insufficient data."
        return "Weight chart: \(weights.count) measured dates. " + average + " " + change + " " + samples.joined(separator: "; ")
    }
    private func askPipButton(_ id: String, _ action: @escaping () -> Void) -> some View {
        Button("Ask Pip", systemImage: "sparkles", action: action).accessibilityIdentifier(id)
    }
    private func weightPrompt(_ entry: WeightEntry) -> () -> Void {
        let text = "Weight · \(entry.value.formatted()) \(entry.unit) · \(DiaryWeek.format(weightDate(entry), "EEE d MMM"))"
        return { askPip(.weight(weightID: entry.id), text, day: entry.dayID) }
    }
    private func workoutPrompt(_ session: WorkoutSession) -> () -> Void {
        let text = "\(session.kind.title) · \(session.durationMinutes) min · \(DiaryWeek.format(workoutDate(session), "EEE d MMM"))"
        return { askPip(.workout(workoutID: session.id), text, day: session.dayID) }
    }
    private func askPip(_ target: CoachReply.Target, _ excerpt: String, day: UUID?) {
        guard let selection = model.selection else { return }
        openChat(day.map { .day($0) }, reply: CoachReply(target: target, excerpt: String(excerpt.prefix(280))), expectedSelection: selection)
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
            let value = try await Self.loadProgress(model: model, endingOn: key.date, days: key.range.days)
            let top = try await model.store.topFoods(from: value.startLocalDate, through: value.endLocalDate, limit: 4, expectedProfileID: ownership.identity.profileID)
            guard !Task.isCancelled, model.selection == ownership, reportRequest == key, reportRequestID == requestID else { return }
            progress = value; foods = top; loadedReport = key
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
