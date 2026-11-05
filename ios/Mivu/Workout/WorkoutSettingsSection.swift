import SwiftUI

/// Settings › Workouts (mockup 10): everything optional about workouts, out of the main screens' way.
struct WorkoutSettingsSection: View {
    @Bindable var model: DiaryViewModel
    @AppStorage(RestTimer.secondsKey) private var restSeconds = 90
    @AppStorage("weightUnit") private var unit = "kg"
    /// Today's "Add burn to food budget"; nil until read.
    @State private var credit: Int?
    @State private var routineCount: Int?
    @State private var ownCount: Int?

    private static let restChoices = [30, 45, 60, 90, 120, 150, 180, 240, 300]

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add burn to food budget").accessibilityHidden(true)
                Picker("Add burn to food budget", selection: Binding(get: { credit ?? 0 }, set: setCredit)) {
                    Text("Off").tag(0); Text("50%").tag(50); Text("100%").tag(100)
                }
                .pickerStyle(.segmented).labelsHidden()
                // Segments at the 44-point minimum.
                .controlSize(.extraLarge)
                .disabled(credit == nil)
                .accessibilityIdentifier("exerciseCreditPercent")
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Estimates often run high. Changes count from today; earlier days keep their numbers.")
        }
        Section {
            Picker("Rest timer", selection: $restSeconds) {
                ForEach(Self.restChoices, id: \.self) { Text(LiveWorkoutView.clock($0)).tag($0) }
            }
            .pickerStyle(.navigationLink)
            .frame(minHeight: 44)
            .accessibilityIdentifier("restTimerDefault")
            Picker("Weight unit", selection: $unit) { Text("kg").tag("kg"); Text("lb").tag("lb") }
                .pickerStyle(.navigationLink)
                .frame(minHeight: 44)
                .accessibilityIdentifier("weightUnit")
            NavigationLink { BarAndPlatesView() } label: { Text("Bar and plates").frame(minHeight: 44) }
                .accessibilityIdentifier("barAndPlates")
            NavigationLink { RoutinesView(model: model) } label: { row("Routines", count: routineCount) }
                .accessibilityIdentifier("workoutRoutines")
            NavigationLink { MyExercisesView(model: model) } label: { row("My exercises", count: ownCount) }
                .accessibilityIdentifier("myExercises")
        }
        .task(id: model.changeGeneration) { await load() }
    }

    private func row(_ title: LocalizedStringKey, count: Int?) -> some View {
        LabeledContent(title) { if let count { Text("\(count)") } }.frame(minHeight: 44)
    }

    private var owner: (id: UUID, zone: String)? { model.readModel.map { ($0.profile.id, $0.profile.timeZoneID) } }

    private func load() async {
        guard let owner else { return }
        let today = ProgressDate.label(Date(), zone: owner.zone)
        do { credit = try await model.store.goal(on: today, expectedProfileID: owner.id)?.exerciseCreditPercent ?? 0 } catch { credit = nil }
        routineCount = try? await model.store.routines(expectedProfileID: owner.id).count
        ownCount = try? await model.store.ownExerciseNames(expectedProfileID: owner.id).count
    }

    /// Writes today's goal revision; the menu shows the new choice once it is saved.
    private func setCredit(_ percent: Int) {
        guard let owner else { return }
        let today = ProgressDate.label(Date(), zone: owner.zone)
        Task {
            if await model.change({ _ = try await model.store.setExerciseCredit(percent, on: today, expectedProfileID: owner.id) }) { credit = percent }
        }
    }
}

/// The bar and the plates the person's gym has. They set the weight wheel's step and the plate calculator.
struct BarAndPlatesView: View {
    @AppStorage("weightUnit") private var unit = "kg"
    @AppStorage(WeightStep.barKey) private var barKg = 0.0
    @AppStorage(WeightStep.platesKgKey) private var platesKg = ""
    @AppStorage(WeightStep.platesLbKey) private var platesLb = ""

    private var bars: [Double] { unit == "lb" ? [45, 35, 25] : [20, 15, 10] }
    private var choices: [Double] { unit == "lb" ? [55, 45, 35, 25, 15, 10, 5, 2.5, 1.25] : [25, 20, 15, 10, 5, 2.5, 2, 1.25, 1, 0.5] }
    // Read through WeightStep so a bad stored value shows the defaults the wheel uses; the AppStorage above redraws on change.
    private var mine: [Double] { _ = platesKg + platesLb; return WeightStep.plates(unit: unit) }

    var body: some View {
        Form {
            Section("Bar") {
                Picker("Bar", selection: Binding(get: { WeightStep.bar(unit: unit) }, set: { barKg = WeightStep.kg(fromDisplay: $0, unit: unit) })) {
                    ForEach(bars, id: \.self) { Text("\(PlateCalculatorView.number($0)) \(unit)").tag($0) }
                }
                .pickerStyle(.inline).labelsHidden()
            }
            Section {
                ForEach(choices, id: \.self) { plate in
                    let on = mine.contains(plate)
                    Toggle("\(PlateCalculatorView.number(plate)) \(unit)", isOn: Binding(get: { on }, set: { save($0 ? mine + [plate] : mine.filter { $0 != plate }) }))
                        // At least one plate stays: the wheel steps by the smallest.
                        .disabled(on && mine.count == 1)
                        .frame(minHeight: 44)
                }
            } header: { Text("My plates") } footer: {
                Text("The weight wheel moves by two of your smallest plate.")
            }
        }
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("Bar and plates")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save(_ plates: [Double]) {
        let json = (try? JSONEncoder().encode(plates.sorted(by: >))).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if unit == "lb" { platesLb = json } else { platesKg = json }
    }
}

/// Saved routines: rename or delete. New ones are saved from a workout's Done screen.
struct RoutinesView: View {
    @Bindable var model: DiaryViewModel
    @State private var routines: [WorkoutRoutine] = []
    @State private var renaming: WorkoutRoutine?
    @State private var name = ""

    var body: some View {
        List {
            Section {
                ForEach(routines) { routine in
                    Button { name = routine.name; renaming = routine } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(routine.name).foregroundStyle(Color.diaryText)
                            Text(routine.exercises.map(\.name).joined(separator: " · ")).font(.subheadline).foregroundStyle(Color.diarySecondary).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Renames it.")
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            write { try await model.store.deleteRoutine(id: routine.id, expectedRevision: routine.revision, expectedProfileID: $0) }
                        }
                    }
                }
            } footer: {
                Text(routines.isEmpty ? "Save a workout as a routine from its Done screen." : "Swipe left to delete a routine.")
            }
        }
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("Routines")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.changeGeneration) {
            guard let owner = model.readModel?.profile.id else { return }
            routines = (try? await model.store.routines(expectedProfileID: owner)) ?? []
        }
        .alert("Rename routine", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Save") {
                guard var routine = renaming, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                routine.name = String(name.prefix(100))
                write { _ = try await model.store.saveRoutine(routine, expectedRevision: routine.revision, expectedProfileID: $0) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func write(_ operation: @escaping (UUID) async throws -> Void) {
        guard let owner = model.readModel?.profile.id else { return }
        Task { await model.change { try await operation(owner) } }
    }
}
