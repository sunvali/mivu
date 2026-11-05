import SwiftUI

/// Exercises the person added by name: rename one everywhere, or merge it into a built-in exercise so its history joins.
struct MyExercisesView: View {
    @Bindable var model: DiaryViewModel
    @State private var names: [String] = []
    @State private var chosen: String?
    @State private var renaming: String?
    @State private var newName = ""
    @State private var merging: String?
    @State private var picking = false
    @State private var mergeTarget: WorkoutExercise?
    @State private var confirmingMerge = false

    var body: some View {
        List {
            Section {
                ForEach(names, id: \.self) { name in
                    Button { chosen = name } label: {
                        Text(name).foregroundStyle(Color.diaryText).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Rename or merge.")
                }
            } footer: {
                Text(names.isEmpty ? "Exercises you add by name show here." : "Changes apply to every saved workout and routine.")
            }
        }
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("My exercises")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.changeGeneration) {
            guard let owner = model.readModel?.profile.id else { return }
            names = (try? await model.store.ownExerciseNames(expectedProfileID: owner)) ?? []
        }
        .confirmationDialog(chosen ?? "", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }), titleVisibility: .visible, presenting: chosen) { name in
            Button("Rename") { newName = name; renaming = name }
            Button("Merge into…") { merging = name; picking = true }
        }
        .alert("Rename exercise", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") { if let name = renaming { rename(name, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
        // The merge is confirmed once the picker has gone, so the two never present at once.
        .sheet(isPresented: $picking, onDismiss: { if mergeTarget != nil { confirmingMerge = true } }) {
            ExercisePicker(recent: []) { target in
                // A name typed in the picker is a rename; a built-in exercise is a merge.
                if let name = merging {
                    if target.exerciseID == nil { rename(name, to: target.name) } else { mergeTarget = target }
                }
                picking = false
            }
        }
        .confirmationDialog(mergeTarget.map { "Merge into \($0.name)?" } ?? "", isPresented: $confirmingMerge, titleVisibility: .visible) {
            Button("Merge") {
                guard let name = merging, let target = mergeTarget else { return }
                // Into a built-in exercise, or into another of their own (a rename to its name).
                if target.exerciseID != nil {
                    write { _ = try await model.store.mergeOwnExercise(name, into: ExerciseKey(target), expectedProfileID: $0) }
                } else {
                    write { _ = try await model.store.renameOwnExercise(from: name, to: target.name, expectedProfileID: $0) }
                }
            }
        } message: { Text("Their workouts and routines become one exercise. This can't be undone.") }
        .onChange(of: confirmingMerge) { _, shown in if !shown { mergeTarget = nil } }
        // A rename that turned out to be a merge asks once the rename alert has gone.
        .onChange(of: renaming) { _, name in if name == nil, mergeTarget != nil { confirmingMerge = true } }
    }

    /// A new name that is a built-in exercise, or another of their own, is a merge: it asks first.
    private func rename(_ name: String, to newName: String) {
        if let target = Self.mergeTarget(renaming: name, to: newName, own: names) { merging = name; mergeTarget = target; return }
        write { _ = try await model.store.renameOwnExercise(from: name, to: newName, expectedProfileID: $0) }
    }

    /// The exercise a rename would join: a built-in one with that name, or another own exercise with it; nil for a plain rename.
    static func mergeTarget(renaming name: String, to newName: String, own: [String]) -> WorkoutExercise? {
        if let catalog = WorkoutCatalog.resolve(newName.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return WorkoutExercise(name: catalog.name, sets: [], exerciseID: catalog.id, measure: catalog.measure)
        }
        let key = ExerciseKey(WorkoutExercise(name: newName, sets: [])), current = ExerciseKey(WorkoutExercise(name: name, sets: []))
        guard key != current, let other = own.first(where: { ExerciseKey(WorkoutExercise(name: $0, sets: [])) == key }) else { return nil }
        return WorkoutExercise(name: other, sets: [])
    }

    private func write(_ operation: @escaping (UUID) async throws -> Void) {
        guard let owner = model.readModel?.profile.id else { return }
        Task { await model.change { try await operation(owner) } }
    }
}
