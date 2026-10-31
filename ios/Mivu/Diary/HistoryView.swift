import SwiftUI

/// Diary tab: a week strip above the selected day's summary and meals.
struct HistoryView: View {
    @Bindable var model: DiaryViewModel
    @Environment(\.openDiaryCoach) private var openChat
    @State private var selected = ""
    @State private var week: DiaryWeekPage?
    @State private var weekStart: String?
    @State private var loadError: String?
    @State private var retries = 0
    @State private var showDatePicker = false
    @State private var pickedDate = Date()
    @State private var showMeal = false
    @State private var showManualNutrition = false
    @State private var showWeight = false
    @State private var showWorkout = false
    @State private var savedMealID: UUID?

    private struct WeekScope: Equatable {
        let selection: DiarySelectionOwnership
        let start: String, end: String
        let generation: UInt64, retries: Int
    }
    private struct DayLoad: Equatable { let ids: [UUID]; let generation: UInt64 }
    private var zone: String { model.readModel?.profile.timeZoneID ?? TimeZone.current.identifier }
    private var calendarToday: String { diaryDateLabel(Date(), zone: zone) }
    private var defaultDate: String { model.activeDay?.localDate ?? calendarToday }
    // Records can sit after today's calendar date (travel across zones); keep them reachable.
    private var lastDate: String { max(calendarToday, week?.latestLocalDate ?? "") }
    /// Only the loaded page for the selected week counts; an older page must not read as "nothing logged".
    private var weekLoaded: Bool { week != nil && weekStart == weekScope?.start }
    private var summaries: [String: [DiaryDaySummary]] { weekLoaded ? Dictionary(grouping: week?.days ?? [], by: \.day.localDate) : [:] }
    private var selectedDays: [TrackingDay] { summaries[selected]?.map(\.day) ?? [] }
    private var recordedDay: TrackingDay? { selectedDays.first }
    private var weekScope: WeekScope? {
        let dates = DiaryWeek.dates(containing: selected, calendar: .current)
        guard let selection = model.selection, let start = dates.first, let end = dates.last else { return nil }
        return WeekScope(selection: selection, start: start, end: end, generation: model.changeGeneration, retries: retries)
    }

    var body: some View {
        List {
            if model.readModel != nil, !selected.isEmpty {
                Section {
                    DiaryWeekStrip(selected: $selected, today: lastDate, earliest: week?.earliestLocalDate, summaries: summaries, activeDayID: model.activeDay?.id)
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                }
                if let loadError {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(loadError).foregroundStyle(Color.diarySecondary)
                            Button("Retry") { retries += 1 }.frame(minHeight: 44).accessibilityIdentifier("retryDiaryHistory")
                        }.diarySummaryCard()
                    }
                }
                if let savedMealID, model.meal(savedMealID) != nil {
                    Section {
                        NavigationLink { MealDetailView(model: model, mealID: savedMealID) } label: {
                            Label("Saved on this iPhone", systemImage: "checkmark.circle").foregroundStyle(Color.diarySuccess).frame(minHeight: 44)
                        }.accessibilityIdentifier("savedDayMealReceipt").diarySummaryCard()
                    }
                }
                if !weekLoaded, loadError == nil {
                    Section { ProgressView().frame(maxWidth: .infinity, minHeight: 120).listRowBackground(Color.clear).listRowSeparator(.hidden) }
                }
                if selectedDays.isEmpty, weekLoaded {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(DiaryWeek.format(selected, "EEEE, d MMMM")).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                            ContentUnavailableView("Nothing logged", systemImage: "fork.knife", description: Text("Ask Pip to add what you ate on this day."))
                        }.diarySummaryCard()
                    }
                }
                ForEach(selectedDays, id: \.id) { day in
                    DaySections(model: model, dayID: day.id, title: DiaryWeek.format(selected, "EEEE, d MMMM"))
                }
            } else if model.readModel == nil {
                ContentUnavailableView("Choose your diary", systemImage: "person.crop.circle", description: Text("Open Profile and settings to select a private local profile."))
            }
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .listSectionSpacing(12)
        .contentMargins(.top, 0, for: .scrollContent)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .task(id: weekScope) { await loadWeek() }
        .task(id: DayLoad(ids: selectedDays.map(\.id), generation: model.changeGeneration)) {
            for day in selectedDays { await model.loadDay(day.id) }
        }
        .onAppear { if selected.isEmpty { selected = defaultDate } }
        .onChange(of: model.activeDay?.localDate) { _, _ in if selected.isEmpty { selected = defaultDate } }
        .onChange(of: selected) { _, _ in savedMealID = nil }
        .onChange(of: model.readModel?.profile.id) { _, _ in
            week = nil; weekStart = nil; selected = defaultDate; savedMealID = nil
            showMeal = false; showManualNutrition = false; showWeight = false; showWorkout = false; showDatePicker = false
        }
        .navigationTitle("Diary")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            // A leading item collapses into a "More" overflow beside the inline-large title.
            ToolbarItem(placement: .topBarTrailing) {
                Button("Choose date", systemImage: "calendar") {
                    pickedDate = ProgressDate.date(selected, zone: zone) ?? Date(); showDatePicker = true
                }.accessibilityIdentifier("chooseDiaryDate")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Ask Pip", systemImage: "sparkles", action: askPipAction)
                    .disabled(!weekLoaded || model.selection == nil || model.isChangingProfile || openChat.origin?.selection != model.selection)
                    .accessibilityIdentifier("diaryAskPip")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // The composer names its destination from the loaded day, so wait for it.
                    if model.sampleMode, let day = recordedDay, model.dayDetail(day.id) != nil {
                        Button("Log meal", systemImage: "plus.circle") { showMeal = true }.accessibilityIdentifier("logMealForDay")
                    }
                    Button("Enter nutrition manually", systemImage: "number") { showManualNutrition = true }.accessibilityIdentifier("enterNutritionForDay")
                    Button("Add weight manually", systemImage: "scalemass") { showWeight = true }.accessibilityIdentifier("logWeightForDay")
                    Button("Add workout manually", systemImage: "figure.strengthtraining.traditional") { showWorkout = true }.accessibilityIdentifier("logWorkoutForDay")
                } label: {
                    Image(systemName: "plus").frame(minWidth: 44, minHeight: 44).accessibilityLabel("Add to this day")
                }
                .disabled(recordedDay == nil)
                .accessibilityIdentifier("diaryAddMenu")
            }
        }
        .sheet(isPresented: $showDatePicker) { datePicker }
        .sheet(isPresented: $showMeal) {
            if let day = recordedDay { MealComposerView(model: model, dayID: day.id, onSaved: { savedMealID = $0 }) }
        }
        .sheet(isPresented: $showManualNutrition) {
            if let day = recordedDay {
                ManualNutritionView(model: model, target: .recorded(dayID: day.id, localDate: day.localDate, timeZoneID: day.timeZoneID)) { savedMealID = $0 }
            }
        }
        .sheet(isPresented: $showWeight) { if let day = recordedDay { MorningWeightEditorView(model: model, dayID: day.id) } }
        .sheet(isPresented: $showWorkout) {
            if let day = recordedDay { WorkoutEditorView(model: model, localDate: day.localDate, dayID: day.id) }
        }
    }

    private func askPipAction() {
        guard let selection = model.selection else { return }
        if let day = recordedDay {
            let reply = CoachReply(target: .day(dayID: day.id), excerpt: DiaryWeek.format(day.localDate, "EEEE, d MMM"))
            openChat(.day(day.id), reply: reply, expectedSelection: selection)
        } else {
            openChat(nil, draft: "For \(DiaryWeek.format(selected, "EEEE, d MMM")): ", expectedSelection: selection)
        }
    }

    private var datePicker: some View {
        let first = week?.earliestLocalDate.flatMap { ProgressDate.date($0, zone: zone) } ?? .distantPast
        let last = ProgressDate.date(lastDate, zone: zone) ?? Date()
        return NavigationStack {
            Form {
                DatePicker("Date", selection: $pickedDate, in: min(first, last)...last, displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
            .navigationTitle("Choose date").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showDatePicker = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show date") {
                        selected = min(ProgressDate.label(pickedDate, zone: zone), lastDate)
                        showDatePicker = false
                    }.accessibilityIdentifier("applyDiaryDate")
                }
            }
        }
        .environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
        .presentationDetents([.medium, .large])
    }

    private func loadWeek() async {
        guard let scope = weekScope else { week = nil; return }
        let store = model.store
        do {
            try await store.validateSelectionOwnership(scope.selection)
            let page = try await store.diaryWeek(from: scope.start, through: scope.end, expectedProfileID: scope.selection.identity.profileID)
            try await store.validateSelectionOwnership(scope.selection)
            guard !Task.isCancelled, weekScope == scope else { return }
            week = page; weekStart = scope.start; loadError = nil
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription
        }
    }
}

/// Summary, meals and workouts of one recorded day.
private struct DaySections: View {
    @Bindable var model: DiaryViewModel
    let dayID: UUID
    let title: String

    var body: some View {
        Group {
            if let snapshot = model.dayDetail(dayID) {
                Section { summary(snapshot).diarySummaryCard() }
                Section {
                    let meals = snapshot.meals.filter { $0.dayID == dayID }.sorted { $0.eatenAt < $1.eatenAt }
                    if meals.isEmpty {
                        Text("No meals recorded for this day.").foregroundStyle(Color.diarySecondary).diarySummaryCard()
                    }
                    ForEach(meals, id: \.id) { meal in
                        NavigationLink { MealDetailView(model: model, mealID: meal.id) } label: { MealRow(meal: meal, model: model) }
                            .modifier(MealRowDeletion(meal: meal, model: model))
                            .accessibilityIdentifier("historyMeal")
                            .diarySummaryCard()
                    }
                } header: { DiarySectionHeader(title: "Meals") }
                let workouts = snapshot.workouts.filter { $0.dayID == dayID }.sorted { $0.performedAt < $1.performedAt }
                if !workouts.isEmpty {
                    Section {
                        ForEach(workouts) { workout in
                            NavigationLink { WorkoutDetailView(model: model, sessionID: workout.id) } label: {
                                Label { LabeledContent("Workout", value: "\(workout.durationMinutes) minutes") } icon: {
                                    Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(Color.diaryWorkout)
                                }.frame(minHeight: 44)
                            }.diarySummaryCard()
                        }
                    } header: { DiarySectionHeader(title: "Workouts") }
                }
            }
        }
    }

    private func summary(_ snapshot: DiaryDayReadModel) -> some View {
        let totals = snapshot.totals
        return VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    Text(title).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    coverage(snapshot)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                    coverage(snapshot)
                }
            }
            NutritionSummary(totals: totals)
            if let target = snapshot.goal?.targets.kcal, target > 0, let kcal = totals.kcal {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: min(kcal, target), total: target).tint(.diaryAccent).accessibilityHidden(true)
                    Text("\(kcal.formatted(.number.precision(.fractionLength(0)))) of \(target.formatted(.number.precision(.fractionLength(0)))) kcal target")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary).monospacedDigit()
                }
            }
            if let weight = snapshot.weight {
                LabeledContent("Morning weight", value: "\(weight.value.formatted()) \(weight.unit)").monospacedDigit()
            }
        }
    }

    private func coverage(_ snapshot: DiaryDayReadModel) -> some View {
        let status = ProgressAnalytics.status(days: [snapshot.day], hasFood: snapshot.meals.contains(where: \.isSaved), activeDayID: snapshot.head.activeDayID) ?? .open
        return DayStatusChip(status: status, isMarkedSkipped: snapshot.day.completeness == .untracked) { skip in
            // Counting again stores `unknown`, which reads as open or closed like any unmarked day.
            Task { await model.change { try await model.store.setCompleteness(dayID: dayID, skip ? .untracked : .unknown, expectedProfileID: snapshot.head.profile.id) } }
        }
    }
}
