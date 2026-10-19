import SwiftUI

struct HistoryView: View {
    @Bindable var model: DiaryViewModel
    @State private var dateFilter: String?
    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var history: DiaryHistoryViewModel
    @AccessibilityFocusState private var focusedDay: UUID?

    init(model: DiaryViewModel) {
        self.model = model
        let store = model.store
        _history = State(initialValue: DiaryHistoryViewModel { scope, start in
            try await store.validateSelectionOwnership(scope.selection)
            let cursor: DiaryHistoryCursor?
            switch start { case .latest: cursor = nil; case .before(let value): cursor = value }
            let page = try await store.diaryHistory(before: cursor, limit: 30, localDate: scope.localDate, expectedProfileID: scope.selection.identity.profileID)
            let coverage = try await store.historyCoverage(expectedProfileID: scope.selection.identity.profileID)
            try await store.validateSelectionOwnership(scope.selection)
            return DiaryHistoryLoad(page: page, coverage: coverage)
        })
    }
    private var historyScope: DiaryHistoryScope? {
        model.selection.map { DiaryHistoryScope(selection: $0, localDate: dateFilter, changeGeneration: model.changeGeneration) }
    }

    var body: some View {
        List {
            if model.readModel != nil {
                if let dateFilter {
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            LabeledContent("Selected date", value: dateFilter)
                            Button("Show all recorded days") { self.dateFilter = nil }
                                .frame(minHeight: 44).accessibilityIdentifier("showAllDiaryDays")
                        }.diarySummaryCard()
                    }
                }
                Section {
                    let days = history.page?.days ?? []
                    if days.isEmpty, !history.isLoading, history.errorMessage == nil, let dateFilter {
                        ContentUnavailableView("No recorded day", systemImage: "calendar", description: Text("There are no records for \(dateFilter). Missing logs do not mean zero intake."))
                    } else if days.isEmpty, !history.isLoading, history.errorMessage == nil {
                        ContentUnavailableView("No recorded days", systemImage: "calendar", description: Text("Meals and measurements appear here after you save them."))
                    }
                    ForEach(days, id: \.day.id) { summary in
                        let day = summary.day
                        NavigationLink(value: HistoryRoute.day(day.id)) {
                            let totals = summary.totals
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 16) {
                                    dayLabel(day, mealCount: summary.mealCount)
                                    Spacer(minLength: 8)
                                    energy(totals.kcal)
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    dayLabel(day, mealCount: summary.mealCount)
                                    energy(totals.kcal)
                                }
                            }
                            .frame(minHeight: 64, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }.accessibilityIdentifier("diaryDay").accessibilityValue(day.localDate + " " + day.timeZoneID)
                            .accessibilityFocused($focusedDay, equals: day.id)
                            .diarySummaryCard()
                    }
                } header: { DiarySectionLabel(title: "Recorded days", symbol: "calendar", color: .diaryProtein) }
                Section {
                    if history.isLoading { ProgressView("Loading diary days…") }
                    if let error = history.errorMessage {
                        Text(error).foregroundStyle(Color.diarySecondary)
                        Button("Retry") { Task { await history.retry(); focusFirstDay() } }
                            .frame(minHeight: 44).disabled(history.isLoading).accessibilityIdentifier("retryDiaryHistory")
                    }
                    if history.page != nil {
                        Button("Earlier days") { navigate(.earlier) }
                            .disabled(!history.canLoadEarlier).accessibilityIdentifier("earlierDiaryDays").frame(minHeight: 44)
                        Button("Newer days") { navigate(.newer) }
                            .disabled(!history.canLoadNewer).accessibilityIdentifier("newerDiaryDays").frame(minHeight: 44)
                        Button("Latest days") { navigate(.latest) }
                            .disabled(!history.canLoadLatest).accessibilityIdentifier("latestDiaryDays").frame(minHeight: 44)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        DisclosureGroup("Day coverage") {
                            ForEach(DayCompleteness.allCases, id: \.self) { status in
                                LabeledContent { Text((history.coverage[status] ?? 0).formatted()).monospacedDigit() } label: { Text(status.title) }
                            }
                        }
                        Text("Complete means all intake was recorded. Partial, unknown and untracked days remain separate. Missing logs do not mean zero intake.")
                            .font(.subheadline).foregroundStyle(Color.diarySecondary)
                    }.diarySummaryCard()
                }
            } else {
                ContentUnavailableView("Choose your diary", systemImage: "person.crop.circle", description: Text("Open Profile and settings to select a private local profile."))
            }
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .listSectionSpacing(12)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationDestination(for: HistoryRoute.self) { route in
            switch route {
            case .day(let id): DayHistoryView(model: model, dayID: id)
            }
        }
        .task(id: historyScope) { await history.setScope(historyScope) }
        .navigationTitle("Diary")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Choose date", systemImage: "calendar") { showDatePicker = true }
                    .accessibilityIdentifier("chooseDiaryDate")
            }
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                Form {
                    DatePicker("Recorded date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    Text("Choose a date to filter the recorded days. Earlier day labels stay unchanged.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
                .navigationTitle("Choose date").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showDatePicker = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Show date") {
                            dateFilter = ProgressDate.label(selectedDate, zone: model.readModel?.profile.timeZoneID ?? TimeZone.current.identifier)
                            showDatePicker = false
                        }.accessibilityIdentifier("applyDiaryDate")
                    }
                }
            }
            .environment(\.timeZone, TimeZone(identifier: model.readModel?.profile.timeZoneID ?? TimeZone.current.identifier) ?? .current)
        }
        .onChange(of: model.readModel?.profile.id) { _, _ in dateFilter = nil; showDatePicker = false }
    }

    private func navigate(_ direction: DiaryHistoryNavigation) {
        Task { await history.navigate(direction); focusFirstDay() }
    }
    private func focusFirstDay() {
        guard history.errorMessage == nil else { return }
        focusedDay = history.page?.days.first?.day.id
    }
    private func dayLabel(_ day: TrackingDay, mealCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formattedDate(day))
                .font(.headline).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                Text(day.completeness.title)
                Text("· \(mealCount) \(mealCount == 1 ? "meal" : "meals")")
            }
            .font(.subheadline).foregroundStyle(Color.diarySecondary)
        }
    }

    private func formattedDate(_ day: TrackingDay) -> String {
        guard let date = ProgressDate.date(day.localDate, zone: day.timeZoneID) else { return day.localDate }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(identifier: day.timeZoneID) ?? .gmt
        formatter.dateFormat = "EEEE, d MMM"
        return formatter.string(from: date)
    }

    private func energy(_ value: Double?) -> some View {
        Text(value.map { $0.formatted(.number.precision(.fractionLength(0))) + " kcal" } ?? "—")
            .font(.body.weight(.semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
    }
}

struct DayHistoryView: View {
    @Bindable var model: DiaryViewModel
    let dayID: UUID
    @Environment(\.openDiaryCoach) private var openChat
    @Environment(\.dismiss) private var dismiss
    @State private var showMeal = false
    @State private var showWeight = false
    @State private var showWorkout = false
    @State private var savedMealID: UUID?
    var body: some View {
        List {
            if let snapshot = model.dayDetail(dayID) {
                let day = snapshot.day
                Section {
                    let selection = model.selection
                    Button {
                        guard let selection, openChat(.day(dayID), expectedSelection: selection) else { return }
                        dismiss()
                    } label: { Label("Open chat", systemImage: "bubble.left").frame(minHeight: 44) }
                        .disabled(selection == nil || model.isChangingProfile || openChat.origin?.selection != selection)
                        .accessibilityIdentifier("diaryDayOpenChat")
                }
                if let savedMealID, model.meal(savedMealID) != nil {
                    Section {
                        NavigationLink { MealDetailView(model: model, mealID: savedMealID) } label: {
                            Label("Saved on this iPhone", systemImage: "checkmark.circle").foregroundStyle(Color.diarySuccess).frame(minHeight: 44)
                        }.accessibilityIdentifier("savedDayMealReceipt")
                        Text("Open the saved meal to review its analysis state.").font(.subheadline).foregroundStyle(Color.diarySecondary)
                    }
                }
                Section { NutritionSummary(totals: snapshot.totals).padding(.vertical, 12).listRowBackground(Color.diarySummarySurface) }
                Section {
                    Button { showMeal = true } label: { Label("Log meal", systemImage: "plus.circle").frame(minHeight: 44) }
                        .accessibilityIdentifier("logMealForDay")
                    Button { showWeight = true } label: { Label("Morning weight", systemImage: "scalemass").frame(minHeight: 44) }
                        .accessibilityIdentifier("logWeightForDay")
                    Button { showWorkout = true } label: { Label("Log workout", systemImage: "figure.strengthtraining.traditional").frame(minHeight: 44) }
                        .accessibilityIdentifier("logWorkoutForDay")
                } header: { Text("Add to this day") }
                Section("Day coverage") {
                    Picker("Coverage", selection: Binding(get: { day.completeness }, set: { value in Task { await model.change { try await model.store.setCompleteness(dayID: dayID, value, expectedProfileID: snapshot.head.profile.id) } } })) {
                        ForEach(DayCompleteness.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("Complete means all intake was recorded, even if some estimates still need review.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                    if let weight = snapshot.weight {
                        LabeledContent("Morning weight", value: "\(weight.value.formatted()) \(weight.unit)").monospacedDigit()
                    }
                }
                Section("Meals") {
                    if snapshot.meals.allSatisfy({ $0.dayID != dayID }) {
                        Text("No meals recorded for this day.").foregroundStyle(Color.diarySecondary)
                    }
                    ForEach(snapshot.meals.filter { $0.dayID == dayID }.sorted { $0.eatenAt < $1.eatenAt }, id: \.id) { meal in
                        NavigationLink { MealDetailView(model: model, mealID: meal.id) } label: { MealRow(meal: meal, model: model) }.accessibilityIdentifier("historyMeal")
                    }
                }
                let workouts = snapshot.workouts.filter { $0.dayID == dayID }
                if !workouts.isEmpty {
                    Section("Workouts") {
                        ForEach(workouts.sorted { $0.performedAt < $1.performedAt }) { workout in
                            NavigationLink { WorkoutDetailView(model: model, sessionID: workout.id) } label: {
                                LabeledContent("Workout", value: "\(workout.durationMinutes) minutes").frame(minHeight: 44)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Day unavailable", systemImage: "calendar", description: Text("This recorded day is unavailable in the selected diary."))
                    .accessibilityIdentifier("diaryDayUnavailable")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .task(id: model.changeGeneration) { await model.loadDay(dayID) }
        .navigationTitle(model.day(dayID)?.localDate ?? "Day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showMeal) { MealComposerView(model: model, dayID: dayID, onSaved: { savedMealID = $0 }) }
        .sheet(isPresented: $showWeight) { MorningWeightEditorView(model: model, dayID: dayID) }
        .sheet(isPresented: $showWorkout) {
            if let day = model.day(dayID) {
                WorkoutEditorView(model: model, localDate: day.localDate, dayID: dayID)
            }
        }
        .onChange(of: model.readModel?.profile.id) { _, _ in savedMealID = nil; showMeal = false; showWeight = false; showWorkout = false }
    }
}

private enum HistoryRoute: Hashable { case day(UUID) }
