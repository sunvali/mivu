import SwiftUI

enum ProgressDate {
    static func label(_ date: Date, zone: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone) ?? .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func date(_ label: String, zone: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone) ?? .gmt
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: label + " 12:00")
    }

    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    static func validOptional(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || number(trimmed).map { $0.isFinite && $0 > 0 } == true
    }

    static func validOptionalNonnegative(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || number(trimmed).map { $0.isFinite && (0...100_000).contains($0) } == true
    }
}

struct GoalEditorValues: Equatable {
    let localDate: String
    let original: GoalRecord?
    var kcal: String
    var carbs: String
    var protein: String
    var fat: String
    var weight: String
    var exerciseCredit: Bool

    var expectedRevision: Int? { original?.revision }

    init(snapshot: DiarySnapshot?, localDate: String) {
        self.init(goal: snapshot?.goals.first { $0.effectiveLocalDate == localDate }, localDate: localDate)
    }

    init(goal: GoalRecord?, localDate: String) {
        self.localDate = localDate
        original = goal
        kcal = original?.targets.kcal.map { String($0) } ?? ""
        carbs = original?.targets.carbs.map { String($0) } ?? ""
        protein = original?.targets.protein.map { String($0) } ?? ""
        fat = original?.targets.fat.map { String($0) } ?? ""
        weight = original?.goalWeightKg.map { String($0) } ?? ""
        exerciseCredit = original?.exerciseCreditEnabled ?? false
    }

    var valid: Bool {
        [kcal, carbs, protein, fat, weight].allSatisfy(ProgressDate.validOptional)
    }

    var hasEditedTargets: Bool {
        kcal != (original?.targets.kcal.map { String($0) } ?? "")
            || carbs != (original?.targets.carbs.map { String($0) } ?? "")
            || protein != (original?.targets.protein.map { String($0) } ?? "")
            || fat != (original?.targets.fat.map { String($0) } ?? "")
            || weight != (original?.goalWeightKg.map { String($0) } ?? "")
            || exerciseCredit != (original?.exerciseCreditEnabled ?? false)
    }

    func record(zone: String) -> GoalRecord {
        GoalRecord(id: original?.id ?? UUID(), effectiveLocalDate: localDate, timeZoneID: zone,
                   targets: NutritionValues(kcal: ProgressDate.number(kcal), carbs: ProgressDate.number(carbs),
                                            protein: ProgressDate.number(protein), fat: ProgressDate.number(fat)),
                   goalWeightKg: ProgressDate.number(weight), exerciseCreditEnabled: exerciseCredit)
    }
}

struct GoalEditorView: View {
    @Bindable var model: DiaryViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: String?
    @State private var date: Date
    @State private var values: GoalEditorValues
    @State private var saving = false
    @State private var ownerID: UUID
    @State private var ownership: DiarySelectionOwnership?
    @State private var zone: String
    @State private var originalValues: GoalEditorValues
    @State private var showDiscard = false
    @State private var pendingDate: Date?
    @State private var showDateChange = false
    @State private var saveError: String?
    @State private var loading = true
    @State private var goalLoaded = false
    @State private var goalRequest = UUID()
    @State private var history: DiaryRecordPage<GoalRecord>?
    @State private var historyBefore: Int?
    @State private var historyRequest = UUID()
    @State private var historyLoading = false
    @State private var historyGeneration: UInt64?
    @State private var historyError: String?

    private var isDirty: Bool {
        values != originalValues || ProgressDate.label(date, zone: zone) != originalValues.localDate
    }

    init(model: DiaryViewModel) {
        self.model = model
        let readModel = model.readModel
        _ownerID = State(initialValue: readModel?.profile.id ?? UUID())
        _ownership = State(initialValue: model.selection)
        let zone = readModel?.profile.timeZoneID ?? TimeZone.current.identifier
        _zone = State(initialValue: zone)
        let today = ProgressDate.label(Date(), zone: zone)
        _date = State(initialValue: ProgressDate.date(today, zone: zone) ?? Date())
        let original = GoalEditorValues(goal: nil, localDate: today)
        _originalValues = State(initialValue: original)
        _values = State(initialValue: original)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Effective date") {
                    DatePicker("Starting on", selection: Binding(get: { date }, set: requestDate), displayedComponents: .date)
                    if loading { ProgressView("Loading saved goals…") }
                    Text("Goals are your settings. Earlier dates keep their own records.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                    DisclosureGroup("Goal history") {
                        if !historyLoading, historyGeneration == model.changeGeneration, let history, !history.values.isEmpty {
                            ForEach(history.values.sorted { $0.effectiveLocalDate > $1.effectiveLocalDate }) { goal in
                                Button {
                                    if let chosen = ProgressDate.date(goal.effectiveLocalDate, zone: zone) { requestDate(chosen) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("Effective \(goal.effectiveLocalDate)").foregroundStyle(Color.diaryText)
                                            Spacer(minLength: 8)
                                            if goal.effectiveLocalDate == values.localDate {
                                                Label("Selected", systemImage: "checkmark").font(.subheadline)
                                            }
                                        }
                                        Text(goalHistorySummary(goal)).font(.subheadline).foregroundStyle(Color.diarySecondary)
                                    }.frame(minHeight: 44)
                                }.accessibilityIdentifier("goalPeriod")
                            }
                        } else if let historyError {
                            Text(historyError).foregroundStyle(.red)
                            Button("Retry loading history") { historyRequest = UUID() }.frame(minHeight: 44)
                        } else {
                            Text(historyLoading || historyGeneration != model.changeGeneration ? "Loading goals…" : "No goals set").foregroundStyle(Color.diarySecondary)
                        }
                        if !historyLoading, historyGeneration == model.changeGeneration, history?.hasMore == true {
                            Button("Older goals") { historyBefore = history?.cursor; historyRequest = UUID() }
                                .frame(minHeight: 44).disabled(historyLoading)
                        }
                        if historyBefore != nil {
                            Button("Latest goals") { historyBefore = nil; historyRequest = UUID() }
                                .frame(minHeight: 44).disabled(historyLoading)
                        }
                    }
                }
                if let saveError {
                    Section {
                        Text(saveError).foregroundStyle(.red)
                        if !goalLoaded { Button("Retry loading goals") { goalRequest = UUID() }.frame(minHeight: 44) }
                    }
                }
                Section("Daily targets") {
                    field("Energy (kcal)", text: $values.kcal, id: "goalKcal")
                    field("Carbs (g)", text: $values.carbs, id: "goalCarbs")
                    field("Protein (g)", text: $values.protein, id: "goalProtein")
                    field("Fat (g)", text: $values.fat, id: "goalFat")
                    Text("Leave a nutrient blank if you have no target for it.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
                Section("Optional weight goal") { field("Weight (kg)", text: $values.weight, id: "goalWeight") }
                Section("Exercise") {
                    Toggle("Include estimated workout energy in an adjusted remaining figure", isOn: $values.exerciseCredit)
                        .disabled(!goalLoaded)
                        .accessibilityIdentifier("exerciseCreditEnabled")
                    Text("Recorded food, remaining from recorded food, and estimated burn are always shown separately.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
            }
            .disabled(loading || saving)
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .scrollDismissesKeyboard(.interactively)
            // A keyboard accessory here can leave a stale height after this sheet closes.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focusedField != nil {
                    HStack {
                        Spacer()
                        Button { focusedField = nil } label: { Text("Done").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityIdentifier("progressKeyboardDone")
                    }.padding(.horizontal, 20).background(.bar)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { focusedField = nil; if isDirty { showDiscard = true } else { dismiss() } }.disabled(saving).frame(minHeight: 44)
                    .alert("Discard changes to goals?", isPresented: $showDiscard) {
                        Button("Discard changes", role: .destructive) { dismiss() }
                        Button("Keep editing", role: .cancel) {}
                    } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!values.valid || !goalLoaded || loading || saving || model.isChangingProfile)
                        .frame(minHeight: 44).accessibilityIdentifier("saveGoals")
                        .alert("Could not save goals", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                            Button("OK", role: .cancel) { saveError = nil }
                        } message: { Text(saveError ?? "Your entered goals are preserved.") }
                }
            }
        }
        .onChange(of: model.selection) { _, selected in
            if selected != ownership { dismiss() }
        }
        .task(id: goalRequest) { await loadGoal() }
        .task(id: historyRequest) { await loadHistory() }
        .onChange(of: model.changeGeneration) { _, _ in
            if !goalLoaded { goalRequest = UUID() }
            historyRequest = UUID()
        }
        .onDisappear { focusedField = nil }
        .interactiveDismissDisabled(isDirty || saving)
        .confirmationDialog("Change the effective date?", isPresented: $showDateChange, titleVisibility: .visible) {
            Button("Discard draft and change date", role: .destructive) {
                if let pendingDate { loadDate(pendingDate) }
                pendingDate = nil
            }
            Button("Keep editing", role: .cancel) { pendingDate = nil }
        } message: {
            Text("Your entered targets have not been saved. Changing the date loads the saved settings for the selected date.")
        }
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
    }

    private func field(_ title: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            progressNumberField(title, text: text, id: id, focus: $focusedField).disabled(!goalLoaded)
            if !ProgressDate.validOptional(text.wrappedValue) {
                Text("Enter a positive number, or leave this blank.").font(.subheadline).foregroundStyle(.red)
            }
        }
    }

    private func requestDate(_ chosen: Date) {
        guard ProgressDate.label(chosen, zone: zone) != values.localDate else { return }
        if values.hasEditedTargets {
            pendingDate = chosen
            showDateChange = true
        } else {
            loadDate(chosen)
        }
    }

    private func goalHistorySummary(_ goal: GoalRecord) -> String {
        let targets: [(String, Double?, String)] = [
            ("Energy", goal.targets.kcal, "kcal"), ("Carbs", goal.targets.carbs, "g"),
            ("Protein", goal.targets.protein, "g"), ("Fat", goal.targets.fat, "g"),
            ("Weight goal", goal.goalWeightKg, "kg")
        ]
        var parts = targets.compactMap { name, value, unit in
            value.map { "\(name) \($0.formatted(.number.precision(.fractionLength(0...1)))) \(unit)" }
        }
        if goal.exerciseCreditEnabled { parts.append("Exercise adjustment enabled") }
        return parts.isEmpty ? "No targets set" : parts.joined(separator: " · ")
    }

    private func loadDate(_ chosen: Date) {
        date = chosen
        loading = true; goalLoaded = false; goalRequest = UUID()
    }

    private func loadGoal() async {
        guard let ownership, model.selection == ownership else { return }
        let request = goalRequest, generation = model.changeGeneration
        let label = ProgressDate.label(date, zone: zone), draft = values
        loading = true; goalLoaded = false
        do {
            let goal = try await model.store.goal(on: label, exact: true, expectedProfileID: ownerID)
            guard !Task.isCancelled, model.selection == ownership, model.changeGeneration == generation,
                  goalRequest == request, values == draft, ProgressDate.label(date, zone: zone) == label else { return }
            let loaded = GoalEditorValues(goal: goal, localDate: label)
            values = loaded; originalValues = loaded; goalLoaded = true; loading = false; saveError = nil
        } catch {
            guard !Task.isCancelled, model.selection == ownership, model.changeGeneration == generation, goalRequest == request else { return }
            loading = false; saveError = "Could not load saved goals. Your draft is preserved."
        }
    }

    private func loadHistory() async {
        guard let ownership, model.selection == ownership else { return }
        let request = historyRequest, generation = model.changeGeneration
        historyLoading = true; historyError = nil
        do {
            let page = try await model.store.goalHistory(before: historyBefore, expectedProfileID: ownerID)
            guard !Task.isCancelled, model.selection == ownership, model.changeGeneration == generation, historyRequest == request else { return }
            history = page; historyGeneration = generation; historyLoading = false
        } catch {
            guard !Task.isCancelled, model.selection == ownership, model.changeGeneration == generation, historyRequest == request else { return }
            historyLoading = false; historyError = "Could not load goal history. Your draft is preserved."
        }
    }

    private func save() {
        guard goalLoaded, !loading, values.valid, model.selection == ownership && ownership != nil else { return }
        let label = ProgressDate.label(date, zone: zone)
        guard values.localDate == label else { return }
        let goal = values.record(zone: zone)
        let expectedRevision = values.expectedRevision
        focusedField = nil
        saving = true
        Task {
            guard model.selection == ownership, ownership != nil else { saving = false; return }
            let success = await model.change { _ = try await model.store.setGoals(goal, expectedRevision: expectedRevision, expectedProfileID: ownerID) }
            saving = false
            if success && model.selection == ownership && ownership != nil { dismiss() }
            else if model.selection == ownership && ownership != nil {
                saveError = model.errorMessage ?? "Could not save these goals. Your entries are preserved."
                model.errorMessage = nil
            }
        }
    }
}

struct WeightCorrectionView: View {
    @Bindable var model: DiaryViewModel
    let entry: WeightEntry
    let localDate: String
    @Environment(\.dismiss) private var dismiss
    @State private var value: String
    @State private var saving = false
    @State private var ownerID: UUID
    @State private var ownership: DiarySelectionOwnership?
    @State private var showDiscard = false
    @State private var saveError: String?
    private var isDirty: Bool { value != String(entry.value) }
    private var valid: Bool { ProgressDate.number(value).map { $0.isFinite && $0 > 0 && $0 <= 1000 } == true }

    init(model: DiaryViewModel, entry: WeightEntry, localDate: String) {
        self.model = model; self.entry = entry; self.localDate = localDate
        _ownerID = State(initialValue: model.readModel?.profile.id ?? UUID())
        _ownership = State(initialValue: model.selection)
        _value = State(initialValue: String(entry.value))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Morning weight · \(localDate)") {
                    progressNumberField("Weight in \(entry.unit)", text: $value, id: "weightCorrectionInput")
                    if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !valid {
                        Text("Enter a number greater than 0 and no more than 1,000 \(entry.unit).")
                            .font(.subheadline).foregroundStyle(.red)
                    }
                    Text("This corrects the saved measurement for this waking day.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
            }
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Edit weight")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { dismissProgressKeyboard() }.accessibilityIdentifier("progressKeyboardDone") }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if isDirty { showDiscard = true } else { dismiss() } }.disabled(saving).frame(minHeight: 44)
                    .alert("Discard this weight correction?", isPresented: $showDiscard) {
                        Button("Discard changes", role: .destructive) { dismiss() }
                        Button("Keep editing", role: .cancel) {}
                    } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!valid || saving || model.isChangingProfile)
                        .frame(minHeight: 44).accessibilityIdentifier("saveWeightCorrection")
                        .alert("Could not save weight", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                            Button("OK", role: .cancel) { saveError = nil }
                        } message: { Text(saveError ?? "Your entered weight is preserved.") }
                }
            }
        }
        .onChange(of: model.selection) { _, selected in
            if selected != ownership { dismiss() }
        }
        .interactiveDismissDisabled(isDirty || saving)
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.layoutDirection, .leftToRight)
    }

    private func save() {
        guard valid, let number = ProgressDate.number(value), model.selection == ownership && ownership != nil else { return }
        saving = true
        Task {
            guard model.selection == ownership, ownership != nil else { saving = false; return }
            let success = await model.change {
                _ = try await model.store.updateWeight(id: entry.id, value: number,
                                                       expectedRevision: entry.revision, expectedProfileID: ownerID)
            }
            saving = false
            if success && model.selection == ownership && ownership != nil { dismiss() }
            else if model.selection == ownership && ownership != nil {
                saveError = model.errorMessage ?? "Could not save this weight. Your entry is preserved."
                model.errorMessage = nil
            }
        }
    }
}

struct WorkoutEditorView: View {
    struct SetFields: Identifiable, Equatable {
        let id = UUID()
        var repetitions = ""
        var load = ""

        init(_ set: WorkoutSet? = nil) {
            repetitions = set.map { String($0.repetitions) } ?? ""
            load = set?.loadKg.map { String($0) } ?? ""
        }

        var valid: Bool {
            Int(repetitions).map { (1...10_000).contains($0) } == true && ProgressDate.validOptionalNonnegative(load)
        }

        var record: WorkoutSet? {
            guard valid, let count = Int(repetitions) else { return nil }
            return WorkoutSet(repetitions: count, loadKg: ProgressDate.number(load))
        }
    }

    private struct ExerciseFields: Identifiable, Equatable {
        let id = UUID()
        var name = ""
        var sets: [SetFields] = [SetFields()]

        init(_ exercise: WorkoutExercise? = nil) {
            name = exercise?.name ?? ""
            sets = exercise.map { $0.sets.map(SetFields.init) } ?? [SetFields()]
        }

        var isBlank: Bool {
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && sets.allSatisfy { $0.repetitions.isEmpty && $0.load.isEmpty }
        }

        var valid: Bool {
            isBlank || (!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && sets.allSatisfy(\.valid))
        }

        var record: WorkoutExercise? {
            guard valid, !isBlank else { return nil }
            return WorkoutExercise(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                   sets: sets.compactMap(\.record))
        }
    }

    @Bindable var model: DiaryViewModel
    @State private var session: WorkoutSession?
    let localDate: String
    let dayID: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var kind: WorkoutKind
    @State private var duration: String
    @State private var exercises: [ExerciseFields]
    @State private var burn: String
    @State private var saving = false
    @State private var ownerID: UUID
    @State private var ownership: DiarySelectionOwnership?
    @State private var originalExercises: [ExerciseFields]
    @State private var showDiscard = false
    @State private var saveError: String?
    private var isDirty: Bool {
        kind != (session?.kind ?? .strength)
            || duration != (session.map { String($0.durationMinutes) } ?? "")
            || burn != (session?.estimatedBurnKcal.map { String($0) } ?? "")
            || exercises != originalExercises
    }

    init(model: DiaryViewModel, localDate: String, session: WorkoutSession? = nil, dayID: UUID? = nil) {
        self.model = model; self.localDate = localDate; self.dayID = dayID
        _session = State(initialValue: session)
        _ownerID = State(initialValue: model.readModel?.profile.id ?? UUID())
        _ownership = State(initialValue: model.selection)
        _kind = State(initialValue: session?.kind ?? .strength)
        _duration = State(initialValue: session.map { String($0.durationMinutes) } ?? "")
        let initialExercises = session.map { $0.exercises.map(ExerciseFields.init) } ?? [ExerciseFields()]
        _originalExercises = State(initialValue: initialExercises)
        _exercises = State(initialValue: initialExercises)
        _burn = State(initialValue: session?.estimatedBurnKcal.map { String($0) } ?? "")
    }

    private var valid: Bool {
        guard let minutes = Int(duration), (1...1440).contains(minutes), ProgressDate.validOptionalNonnegative(burn) else { return false }
        return exercises.allSatisfy(\.valid)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout · \(localDate)") {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading) {
                            kindButton(.strength, "Strength", id: "workoutStrength")
                            kindButton(.cardio, "Cardio", id: "workoutCardio")
                            kindButton(.other, "Other", id: "workoutOther")
                        }
                    } else {
                        HStack {
                            kindButton(.strength, "Strength", id: "workoutStrength")
                            kindButton(.cardio, "Cardio", id: "workoutCardio")
                            kindButton(.other, "Other", id: "workoutOther")
                        }
                    }
                    progressNumberField("Duration in minutes", text: $duration, id: "workoutDuration", keyboard: .numberPad)
                    if !duration.isEmpty && Int(duration).map({ (1...1440).contains($0) }) != true {
                        Text("Enter a duration from 1 to 1,440 minutes.").font(.subheadline).foregroundStyle(.red)
                    }
                }
                Section("Exercise details") {
                    ForEach(exercises.indices, id: \.self) { exerciseIndex in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Exercise", text: $exercises[exerciseIndex].name)
                                .accessibilityIdentifier(exerciseIndex == 0 ? "workoutExercise" : "workoutExercise\(exerciseIndex)")
                            ForEach(exercises[exerciseIndex].sets.indices, id: \.self) { setIndex in
                                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                                layout {
                                    progressNumberField("Repetitions", text: $exercises[exerciseIndex].sets[setIndex].repetitions,
                                                        id: setID("workoutRepetitions", exercise: exerciseIndex, set: setIndex), keyboard: .numberPad)
                                    progressNumberField("Load (kg, blank for bodyweight)", text: $exercises[exerciseIndex].sets[setIndex].load,
                                                        id: setID("workoutLoad", exercise: exerciseIndex, set: setIndex))
                                }
                                if exercises[exerciseIndex].sets.count > 1 {
                                    Button("Remove set \(setIndex + 1)") {
                                        exercises[exerciseIndex].sets.remove(at: setIndex)
                                    }
                                    .buttonStyle(.bordered)
                                    .frame(minHeight: 44)
                                    .accessibilityIdentifier(setID("removeWorkoutSet", exercise: exerciseIndex, set: setIndex))
                                }
                            }
                            Button("Add set") { exercises[exerciseIndex].sets.append(SetFields()) }
                                .buttonStyle(.bordered)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier(exerciseIndex == 0 ? "addWorkoutSet" : "addWorkoutSet\(exerciseIndex)")
                            Button("Remove exercise") { exercises.remove(at: exerciseIndex) }
                                .buttonStyle(.bordered)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("removeWorkoutExercise\(exerciseIndex)")
                            if !exercises[exerciseIndex].valid {
                                Text("Enter an exercise name and 1–10,000 repetitions per set. Load can be blank for bodyweight, or 0–100,000 kg.")
                                    .font(.subheadline).foregroundStyle(.red)
                            }
                        }
                    }
                    Button("Add exercise") { exercises.append(ExerciseFields()) }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44).accessibilityIdentifier("addWorkoutExercise")
                    Text("Leave an unused exercise blank for a simple session. Leave load blank for bodyweight.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
                Section("Optional estimate") {
                    progressNumberField("Estimated burn (kcal)", text: $burn, id: "workoutBurn")
                    if !ProgressDate.validOptionalNonnegative(burn) {
                        Text("Enter 0–100,000 kcal, or leave this blank.").font(.subheadline).foregroundStyle(.red)
                    }
                    Text("An estimate, shown separately from recorded food.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
            }
            .accessibilityIdentifier("workoutForm")
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(session == nil ? "Log workout" : "Edit workout")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { dismissProgressKeyboard() }.accessibilityIdentifier("progressKeyboardDone") }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if isDirty { showDiscard = true } else { dismiss() } }.disabled(saving).frame(minHeight: 44)
                    .alert("Discard changes to this workout?", isPresented: $showDiscard) {
                        Button("Discard changes", role: .destructive) { dismiss() }
                        Button("Keep editing", role: .cancel) {}
                    } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!valid || saving || model.isChangingProfile)
                        .frame(minHeight: 44).accessibilityIdentifier("saveWorkout")
                        .alert("Could not save workout", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                            Button("OK", role: .cancel) { saveError = nil }
                        } message: { Text(saveError ?? "Your entered workout is preserved.") }
                }
            }
        }
        .onChange(of: model.selection) { _, selected in
            if selected != ownership { dismiss() }
        }
        .interactiveDismissDisabled(isDirty || saving)
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.layoutDirection, .leftToRight)
    }

    private func kindButton(_ value: WorkoutKind, _ title: String, id: String) -> some View {
        Button { kind = value } label: { Text(title).frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(.bordered)
            .tint(kind == value ? .diaryAccent : .diarySecondary)
            .accessibilityAddTraits(kind == value ? .isSelected : [])
            .accessibilityIdentifier(id)
    }

    private func setID(_ prefix: String, exercise: Int, set: Int) -> String {
        exercise == 0 ? (set == 0 ? prefix : "\(prefix)\(set)") : "\(prefix)\(exercise)_\(set)"
    }

    private func save() {
        guard valid, let minutes = Int(duration), model.selection == ownership && ownership != nil else { return }
        let estimated = ProgressDate.number(burn)
        let draft = WorkoutDraft(kind: kind, durationMinutes: minutes, exercises: exercises.compactMap(\.record),
                                 estimatedBurnKcal: estimated,
                                 burnSource: estimated == nil ? nil : (estimated == session?.estimatedBurnKcal ? session?.burnSource : .userEstimate))
        saving = true
        Task {
            guard model.selection == ownership, ownership != nil else { saving = false; return }
            let success: Bool
            if var session {
                session.kind = draft.kind; session.durationMinutes = draft.durationMinutes
                session.exercises = draft.exercises; session.estimatedBurnKcal = draft.estimatedBurnKcal
                session.burnSource = draft.burnSource
                let updated = session
                success = await model.change { _ = try await model.store.updateWorkout(updated, expectedRevision: updated.revision, expectedProfileID: ownerID) }
            } else if let dayID {
                success = await model.change { _ = try await model.store.createWorkout(dayID: dayID, draft: draft, expectedProfileID: ownerID) }
            } else {
                success = await model.change { _ = try await model.store.createWorkout(localDate: localDate, draft: draft, performedAt: nil, expectedProfileID: ownerID) }
            }
            saving = false
            if success && model.selection == ownership && ownership != nil { dismiss() }
            else if model.selection == ownership && ownership != nil {
                saveError = model.errorMessage ?? "Could not save this workout. Your entries are preserved."
                model.errorMessage = nil
            }
        }
    }
}

@MainActor private func progressNumberField(_ title: String, text: Binding<String>, id: String,
                                          keyboard: UIKeyboardType = .decimalPad,
                                          focus: FocusState<String?>.Binding? = nil) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        let input = TextField(title, text: text).keyboardType(keyboard).frame(minHeight: 44).accessibilityIdentifier(id)
        if let focus { input.focused(focus, equals: id) }
        else { input }
    }
}

@MainActor private func dismissProgressKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

struct MorningWeightEditorView: View {
    @Bindable var model: DiaryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var saving = false
    @State private var showDiscard = false
    @State private var saveError: String?
    @State private var ownerID: UUID
    @State private var ownership: DiarySelectionOwnership?
    private let dayID: UUID?
    @State private var initialWeight: WeightEntry?
    @State private var localDate: String?
    @State private var loading = false
    @State private var dayLoaded = false
    @State private var dayRequest = UUID()

    private var isDirty: Bool { value != (initialWeight.map { String($0.value) } ?? "") }
    private var unit: String { initialWeight?.unit ?? "kg" }

    init(model: DiaryViewModel, dayID: UUID? = nil) {
        self.model = model
        _ownerID = State(initialValue: model.readModel?.profile.id ?? UUID())
        _ownership = State(initialValue: model.selection)
        self.dayID = dayID
        let detail = dayID.flatMap { model.dayDetail($0) }
        let existing = detail?.weight
        _initialWeight = State(initialValue: existing)
        _localDate = State(initialValue: detail?.day.localDate)
        _value = State(initialValue: existing.map { String($0.value) } ?? "")
        _dayLoaded = State(initialValue: dayID == nil || detail != nil)
        _loading = State(initialValue: dayID != nil && detail == nil)
    }

    private var valid: Bool {
        ProgressDate.number(value).map { $0.isFinite && $0 > 0 && $0 <= 1000 } == true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Morning weight") {
                    if let localDate { LabeledContent("Waking day", value: localDate) }
                    progressNumberField("Weight (\(unit))", text: $value, id: "weightInput").disabled(loading || !dayLoaded)
                    if !value.isEmpty && !valid {
                        Label("Enter a weight greater than 0 and no more than 1,000 \(unit).", systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(.red)
                    }
                    Text(dayID == nil ? "Optional. Saving starts or reuses today's waking day." : "Saving updates only this selected waking day. Other day labels and your active day are preserved.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                        if !dayLoaded { Button("Retry loading weight") { dayRequest = UUID() }.frame(minHeight: 44) }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Log morning weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if isDirty { showDiscard = true } else { dismiss() } }.disabled(saving)
                    .alert("Discard this weight entry?", isPresented: $showDiscard) {
                        Button("Discard changes", role: .destructive) { dismiss() }
                        Button("Keep editing", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!valid || !dayLoaded || loading || saving || model.isChangingProfile)
                        .accessibilityIdentifier("saveWeight")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { dismissProgressKeyboard() }.accessibilityIdentifier("progressKeyboardDone") }
            }
        }
        .task(id: dayRequest) { await loadSelectedDay() }
        .onChange(of: model.changeGeneration) { _, _ in if !dayLoaded { dayRequest = UUID() } }
        .onChange(of: model.selection) { _, selected in
            if selected != ownership { dismiss() }
        }
        .interactiveDismissDisabled(isDirty || saving)
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.layoutDirection, .leftToRight)
    }

    private func loadSelectedDay() async {
        guard let dayID, let ownership, model.selection == ownership, !dayLoaded else { return }
        let request = dayRequest, generation = model.changeGeneration, draft = value
        loading = true
        do {
            let detail = try await model.store.diaryDay(id: dayID, expectedProfileID: ownerID)
            guard !Task.isCancelled, model.selection == ownership, model.changeGeneration == generation,
                  dayRequest == request, value == draft else { return }
            initialWeight = detail.weight; localDate = detail.day.localDate
            value = detail.weight.map { String($0.value) } ?? ""
            dayLoaded = true; loading = false; saveError = nil
        } catch {
            guard !Task.isCancelled, model.selection == ownership, model.changeGeneration == generation, dayRequest == request else { return }
            loading = false; saveError = "Could not load this day's saved weight. Your entry is preserved."
        }
    }

    private func save() {
        guard dayLoaded, !loading, valid, let number = ProgressDate.number(value), model.selection == ownership && ownership != nil else { return }
        saving = true
        saveError = nil
        Task {
            guard model.selection == ownership, ownership != nil else { saving = false; return }
            let success: Bool
            if let initialWeight {
                success = await model.change {
                    _ = try await model.store.updateWeight(id: initialWeight.id, value: number,
                                                           expectedRevision: initialWeight.revision, expectedProfileID: ownerID)
                }
            } else if let dayID {
                success = await model.change {
                    _ = try await model.store.setWeight(dayID: dayID, value: number, unit: unit,
                                                        expectedRevision: nil, expectedProfileID: ownerID)
                }
            } else {
                success = await model.change { _ = try await model.store.recordWeight(value: number, expectedProfileID: ownerID) }
            }
            saving = false
            if success && model.selection == ownership && ownership != nil { dismiss() }
            else if model.selection == ownership && ownership != nil {
                saveError = model.errorMessage ?? "Could not save this weight. Your entry is preserved."
                model.errorMessage = nil
            }
        }
    }
}
