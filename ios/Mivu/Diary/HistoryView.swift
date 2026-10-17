import SwiftUI

struct HistoryView: View {
    @Bindable var model: DiaryViewModel
    @State private var dateFilter: String?
    @State private var selectedDate = Date()
    @State private var showDatePicker = false

    var body: some View {
        List {
            if let snapshot = model.snapshot {
                if let dateFilter {
                    Section {
                        LabeledContent("Selected date", value: dateFilter)
                        Button("Show all recorded days") { self.dateFilter = nil }
                            .frame(minHeight: 44).accessibilityIdentifier("showAllDiaryDays")
                    }
                }
                Section {
                    let days = snapshot.days.filter { dateFilter == nil || $0.localDate == dateFilter }
                    if days.isEmpty, let dateFilter {
                        ContentUnavailableView("No recorded day", systemImage: "calendar", description: Text("There are no records for \(dateFilter). Missing logs do not mean zero intake."))
                    } else if days.isEmpty {
                        ContentUnavailableView("No recorded days", systemImage: "calendar", description: Text("Meals and measurements appear here after you save them."))
                    }
                    ForEach(days.sorted { $0.startAt > $1.startAt }, id: \.id) { day in
                        NavigationLink(value: HistoryRoute.day(day.id)) {
                            let meals = snapshot.meals.filter { $0.dayID == day.id }
                            let totals = snapshot.totals(dayID: day.id)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 16) {
                                    dayLabel(day, mealCount: meals.count)
                                    Spacer(minLength: 8)
                                    energy(totals.kcal)
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    dayLabel(day, mealCount: meals.count)
                                    energy(totals.kcal)
                                }
                            }
                            .frame(minHeight: 64, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }.accessibilityIdentifier("diaryDay")
                    }
                } header: { DiarySectionLabel(title: "Recorded days", symbol: "calendar", color: .diaryProtein) }
                Section {
                    DisclosureGroup("Day coverage") {
                        ForEach(DayCompleteness.allCases, id: \.self) { status in
                            LabeledContent { Text(snapshot.days.filter { $0.completeness == status }.count.formatted()).monospacedDigit() } label: { Text(status.title) }
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
                            dateFilter = ProgressDate.label(selectedDate, zone: model.snapshot?.profile.timeZoneID ?? TimeZone.current.identifier)
                            showDatePicker = false
                        }.accessibilityIdentifier("applyDiaryDate")
                    }
                }
            }
            .environment(\.timeZone, TimeZone(identifier: model.snapshot?.profile.timeZoneID ?? TimeZone.current.identifier) ?? .current)
        }
        .onChange(of: model.snapshot?.profile.id) { _, _ in dateFilter = nil; showDatePicker = false }
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
            if let snapshot = model.snapshot, let day = snapshot.days.first(where: { $0.id == dayID }) {
                if let savedMealID, model.meal(savedMealID) != nil {
                    Section {
                        NavigationLink { MealDetailView(model: model, mealID: savedMealID) } label: {
                            Label("Saved on this iPhone", systemImage: "checkmark.circle").foregroundStyle(Color.diarySuccess).frame(minHeight: 44)
                        }.accessibilityIdentifier("savedDayMealReceipt")
                        Text("Open the saved meal to review its analysis state.").font(.subheadline).foregroundStyle(Color.diarySecondary)
                    }
                }
                Section { NutritionSummary(totals: snapshot.totals(dayID: dayID)).padding(.vertical, 12).listRowBackground(Color.diarySummarySurface) }
                Section {
                    Button { showMeal = true } label: { Label("Log meal", systemImage: "plus.circle").frame(minHeight: 44) }
                        .accessibilityIdentifier("logMealForDay")
                    Button { showWeight = true } label: { Label("Morning weight", systemImage: "scalemass").frame(minHeight: 44) }
                        .accessibilityIdentifier("logWeightForDay")
                    Button { showWorkout = true } label: { Label("Log workout", systemImage: "figure.strengthtraining.traditional").frame(minHeight: 44) }
                        .accessibilityIdentifier("logWorkoutForDay")
                } header: { Text("Add to this day") }
                Section("Day coverage") {
                    Picker("Coverage", selection: Binding(get: { day.completeness }, set: { value in Task { await model.change { try await model.store.setCompleteness(dayID: dayID, value, expectedProfileID: snapshot.profile.id) } } })) {
                        ForEach(DayCompleteness.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("Complete means all intake was recorded, even if some estimates still need review.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                    if let weight = snapshot.weights.first(where: { $0.dayID == dayID }) {
                        LabeledContent("Morning weight", value: "\(weight.value.formatted()) \(weight.unit)").monospacedDigit()
                    }
                }
                Section("Meals") {
                    if snapshot.meals.allSatisfy({ $0.dayID != dayID }) {
                        Text("No meals recorded for this day.").foregroundStyle(Color.diarySecondary)
                    }
                    ForEach(snapshot.meals.filter { $0.dayID == dayID }.sorted { $0.eatenAt < $1.eatenAt }, id: \.id) { meal in
                        NavigationLink { MealDetailView(model: model, mealID: meal.id) } label: { MealRow(meal: meal) }.accessibilityIdentifier("historyMeal")
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
        .navigationTitle(model.snapshot?.days.first { $0.id == dayID }?.localDate ?? "Day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showMeal) { MealComposerView(model: model, dayID: dayID, onSaved: { savedMealID = $0 }) }
        .sheet(isPresented: $showWeight) { MorningWeightEditorView(model: model, dayID: dayID) }
        .sheet(isPresented: $showWorkout) {
            if let day = model.snapshot?.days.first(where: { $0.id == dayID }) {
                WorkoutEditorView(model: model, localDate: day.localDate, dayID: dayID)
            }
        }
        .onChange(of: model.snapshot?.profile.id) { _, _ in savedMealID = nil; showMeal = false; showWeight = false; showWorkout = false }
    }
}

private enum HistoryRoute: Hashable { case day(UUID) }
