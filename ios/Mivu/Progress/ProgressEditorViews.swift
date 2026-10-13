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

struct GoalEditorValues {
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
        self.localDate = localDate
        original = snapshot?.goals.first { $0.effectiveLocalDate == localDate }
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
    @State private var date: Date
    @State private var values: GoalEditorValues
    @State private var saving = false
    private let ownerID: UUID
    private let zone: String

    init(model: DiaryViewModel) {
        self.model = model
        let snapshot = model.snapshot
        ownerID = snapshot?.profile.id ?? UUID()
        zone = snapshot?.profile.timeZoneID ?? TimeZone.current.identifier
        let today = ProgressDate.label(Date(), zone: zone)
        _date = State(initialValue: ProgressDate.date(today, zone: zone) ?? Date())
        _values = State(initialValue: GoalEditorValues(snapshot: snapshot, localDate: today))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Effective date") {
                    DatePicker("Starting on", selection: $date, displayedComponents: .date)
                        .onChange(of: date) { _, chosen in
                            values = GoalEditorValues(snapshot: model.snapshot,
                                                      localDate: ProgressDate.label(chosen, zone: zone))
                        }
                    Text("Goals are your settings. Earlier dates keep their own records.")
                        .font(.caption).foregroundStyle(Color.diarySecondary)
                }
                Section("Daily targets") {
                    field("Energy (kcal)", text: $values.kcal, id: "goalKcal")
                    field("Carbs (g)", text: $values.carbs, id: "goalCarbs")
                    field("Protein (g)", text: $values.protein, id: "goalProtein")
                    field("Fat (g)", text: $values.fat, id: "goalFat")
                    Text("Leave a nutrient blank if you have no target for it.")
                        .font(.caption).foregroundStyle(Color.diarySecondary)
                }
                Section("Optional weight goal") { field("Weight (kg)", text: $values.weight, id: "goalWeight") }
                Section("Exercise") {
                    Toggle("Include estimated workout energy in an adjusted remaining figure", isOn: $values.exerciseCredit)
                        .accessibilityIdentifier("exerciseCreditEnabled")
                    Text("Recorded food, remaining from recorded food, and estimated burn are always shown separately.")
                        .font(.caption).foregroundStyle(Color.diarySecondary)
                }
            }
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minHeight: 44) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!values.valid || saving || model.isChangingProfile)
                        .frame(minHeight: 44).accessibilityIdentifier("saveGoals")
                }
            }
        }
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
    }

    private func field(_ title: String, text: Binding<String>, id: String) -> some View {
        progressNumberField(title, text: text, id: id)
    }

    private func save() {
        guard values.valid, model.snapshot?.profile.id == ownerID else { return }
        let label = ProgressDate.label(date, zone: zone)
        guard values.localDate == label else { return }
        let goal = values.record(zone: zone)
        let expectedRevision = values.expectedRevision
        saving = true
        Task {
            let success = await model.change { _ = try await model.store.setGoals(goal, expectedRevision: expectedRevision, expectedProfileID: ownerID) }
            saving = false
            if success && model.snapshot?.profile.id == ownerID { dismiss() }
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
    private let ownerID: UUID

    init(model: DiaryViewModel, entry: WeightEntry, localDate: String) {
        self.model = model; self.entry = entry; self.localDate = localDate
        ownerID = model.snapshot?.profile.id ?? UUID()
        _value = State(initialValue: String(entry.value))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Morning weight · \(localDate)") {
                    progressNumberField("Weight in \(entry.unit)", text: $value, id: "weightCorrectionInput")
                    Text("This corrects the saved measurement for this waking day.")
                        .font(.caption).foregroundStyle(Color.diarySecondary)
                }
            }
            .navigationTitle("Edit weight")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minHeight: 44) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(ProgressDate.number(value).map { $0 > 0 && $0 <= 1000 } != true || saving)
                        .frame(minHeight: 44).accessibilityIdentifier("saveWeightCorrection")
                }
            }
        }
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.layoutDirection, .leftToRight)
    }

    private func save() {
        guard let number = ProgressDate.number(value), model.snapshot?.profile.id == ownerID else { return }
        saving = true
        Task {
            let success = await model.change {
                _ = try await model.store.setWeight(dayLocalDate: localDate, value: number, unit: entry.unit,
                                                    measuredAt: entry.timePrecision == .exact ? entry.measuredAt : nil,
                                                    expectedRevision: entry.revision, expectedProfileID: ownerID)
            }
            saving = false
            if success && model.snapshot?.profile.id == ownerID { dismiss() }
        }
    }
}

struct WorkoutEditorView: View {
    struct SetFields: Identifiable {
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

    private struct ExerciseFields: Identifiable {
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
    let session: WorkoutSession?
    let localDate: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var kind: WorkoutKind
    @State private var duration: String
    @State private var exercises: [ExerciseFields]
    @State private var burn: String
    @State private var saving = false
    private let ownerID: UUID

    init(model: DiaryViewModel, localDate: String, session: WorkoutSession? = nil) {
        self.model = model; self.localDate = localDate; self.session = session
        ownerID = model.snapshot?.profile.id ?? UUID()
        _kind = State(initialValue: session?.kind ?? .strength)
        _duration = State(initialValue: session.map { String($0.durationMinutes) } ?? "")
        _exercises = State(initialValue: session.map { $0.exercises.map(ExerciseFields.init) } ?? [ExerciseFields()])
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
                }
                Section("Exercise details") {
                    ForEach(exercises.indices, id: \.self) { exerciseIndex in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Exercise", text: $exercises[exerciseIndex].name)
                                .accessibilityIdentifier(exerciseIndex == 0 ? "workoutExercise" : "workoutExercise\(exerciseIndex)")
                            ForEach(exercises[exerciseIndex].sets.indices, id: \.self) { setIndex in
                                HStack {
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
                        }
                    }
                    Button("Add exercise") { exercises.append(ExerciseFields()) }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44).accessibilityIdentifier("addWorkoutExercise")
                    Text("Leave an unused exercise blank for a simple session. Leave load blank for bodyweight.")
                        .font(.caption).foregroundStyle(Color.diarySecondary)
                }
                Section("Optional estimate") {
                    progressNumberField("Estimated burn (kcal)", text: $burn, id: "workoutBurn")
                    Text("An estimate, shown separately from recorded food.")
                        .font(.caption).foregroundStyle(Color.diarySecondary)
                }
            }
            .accessibilityIdentifier("workoutForm")
            .navigationTitle(session == nil ? "Log workout" : "Edit workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minHeight: 44) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!valid || saving || model.isChangingProfile)
                        .frame(minHeight: 44).accessibilityIdentifier("saveWorkout")
                }
            }
        }
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.layoutDirection, .leftToRight)
    }

    private func kindButton(_ value: WorkoutKind, _ title: String, id: String) -> some View {
        Button { kind = value } label: { Text(title).frame(minHeight: 44) }
            .buttonStyle(.bordered)
            .tint(kind == value ? .diaryAccent : .diaryLeaf)
            .accessibilityAddTraits(kind == value ? .isSelected : [])
            .accessibilityIdentifier(id)
    }

    private func setID(_ prefix: String, exercise: Int, set: Int) -> String {
        exercise == 0 ? (set == 0 ? prefix : "\(prefix)\(set)") : "\(prefix)\(exercise)_\(set)"
    }

    private func save() {
        guard valid, let minutes = Int(duration), model.snapshot?.profile.id == ownerID else { return }
        let estimated = ProgressDate.number(burn)
        let draft = WorkoutDraft(kind: kind, durationMinutes: minutes, exercises: exercises.compactMap(\.record),
                                 estimatedBurnKcal: estimated,
                                 burnSource: estimated == nil ? nil : (estimated == session?.estimatedBurnKcal ? session?.burnSource : .userEstimate))
        saving = true
        Task {
            let success: Bool
            if var session {
                session.kind = draft.kind; session.durationMinutes = draft.durationMinutes
                session.exercises = draft.exercises; session.estimatedBurnKcal = draft.estimatedBurnKcal
                session.burnSource = draft.burnSource
                let updated = session
                success = await model.change { _ = try await model.store.updateWorkout(updated, expectedRevision: updated.revision, expectedProfileID: ownerID) }
            } else {
                success = await model.change { _ = try await model.store.createWorkout(localDate: localDate, draft: draft, performedAt: nil, expectedProfileID: ownerID) }
            }
            saving = false
            if success && model.snapshot?.profile.id == ownerID { dismiss() }
        }
    }
}

@MainActor private func progressNumberField(_ title: String, text: Binding<String>, id: String,
                                          keyboard: UIKeyboardType = .decimalPad) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        TextField(title, text: text).keyboardType(keyboard).frame(minHeight: 44).accessibilityIdentifier(id)
    }
}
