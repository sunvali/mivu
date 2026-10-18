import SwiftUI

struct HistoryView: View {
    @Bindable var model: DiaryViewModel
    @State private var dateFilter: String?
    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var page: DiaryHistoryPage?
    @State private var coverage: [DayCompleteness: Int] = [:]

    var body: some View {
        List {
            if model.readModel != nil {
                if let dateFilter {
                    Section {
                        LabeledContent("Selected date", value: dateFilter)
                        Button("Show all recorded days") { self.dateFilter = nil }
                            .frame(minHeight: 44).accessibilityIdentifier("showAllDiaryDays")
                    }
                }
                Section {
                    let days = page?.days ?? []
                    if days.isEmpty, let dateFilter {
                        ContentUnavailableView("No recorded day", systemImage: "calendar", description: Text("There are no records for \(dateFilter). Missing logs do not mean zero intake."))
                    } else if days.isEmpty {
                        ContentUnavailableView("No recorded days", systemImage: "calendar", description: Text("Meals and measurements appear here after you save them."))
                    }
                    ForEach(days, id: \.day.id) { summary in
                        let day = summary.day
                        NavigationLink(value: HistoryRoute.day(day.id)) {
                            let totals = summary.totals
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 16) {
                                    dayLabel(day, mealCount: summary.savedMealCount + summary.pendingMealCount)
                                    Spacer(minLength: 8)
                                    energy(totals.kcal)
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    dayLabel(day, mealCount: summary.savedMealCount + summary.pendingMealCount)
                                    energy(totals.kcal)
                                }
                            }
                            .frame(minHeight: 64, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }.accessibilityIdentifier("diaryDay")
                    }
                } header: { DiarySectionLabel(title: "Recorded days", symbol: "calendar", color: .diaryProtein) }
                if page?.hasMore == true { Button("Earlier days") { Task { await loadHistory(before: page?.cursor) } }.frame(minHeight: 44) }
                Section {
                    DisclosureGroup("Day coverage") {
                        ForEach(DayCompleteness.allCases, id: \.self) { status in
                            LabeledContent { Text((coverage[status] ?? 0).formatted()).monospacedDigit() } label: { Text(status.title) }
                        }
                    }
                    Text("Complete means all intake was recorded. Partial, unknown and untracked days remain separate. Missing logs do not mean zero intake.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
            } else {
                ContentUnavailableView("Choose your diary", systemImage: "person.crop.circle", description: Text("Open Profile and settings to select a private local profile."))
            }
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationDestination(for: HistoryRoute.self) { route in
            switch route {
            case .day(let id): DayHistoryView(model: model, dayID: id)
            }
        }
        .task(id: model.changeGeneration) { await loadHistory() }
        .task(id: dateFilter) { await loadHistory() }
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

    private func loadHistory(before: DiaryHistoryCursor? = nil) async {
        guard let token = model.selection else { page = nil; return }
        let filter = dateFilter
        do {
            let loaded = try await model.store.diaryHistory(before: before, localDate: filter, expectedProfileID: token.identity.profileID)
            let counts = try await model.store.historyCoverage(expectedProfileID: token.identity.profileID)
            guard !Task.isCancelled, model.selection == token, dateFilter == filter else { return }; page = loaded; coverage = counts
        } catch { if model.selection == token { model.errorMessage = error.localizedDescription } }
    }
    private func dayLabel(_ day: TrackingDay, mealCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formattedDate(day))
                .font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
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
    @State private var showMeal = false
    @State private var showWeight = false
    @State private var showWorkout = false
    @State private var savedMealID: UUID?
    var body: some View {
        List {
            if let snapshot = model.dayDetail(dayID) {
                let day = snapshot.day
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
