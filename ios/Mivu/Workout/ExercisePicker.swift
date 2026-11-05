import SwiftUI

/// Search the built-in exercises (names and aliases), pick a recent one, filter by muscle, or add your own by name.
struct ExercisePicker: View {
    let recent: [WorkoutExercise]
    let onPick: (WorkoutExercise) -> Void
    @State private var search = ""
    @State private var muscle: String?
    @Environment(\.dismiss) private var dismiss

    private static let muscles = Array(Set(WorkoutCatalog.exercises.map(\.muscle))).sorted()

    private var trimmed: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The exact match first, then the rest alphabetically.
    private var matches: [CatalogExercise] {
        let exact = WorkoutCatalog.resolve(trimmed)?.id
        return WorkoutCatalog.exercises
            .filter { muscle == nil || $0.muscle == muscle }
            .filter { trimmed.isEmpty || ([$0.name] + $0.aliases).contains { $0.localizedStandardContains(trimmed) } }
            .sorted { ($0.id == exact ? 0 : 1, $0.name) < ($1.id == exact ? 0 : 1, $1.name) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !trimmed.isEmpty, WorkoutCatalog.resolve(trimmed) == nil, !recent.contains(where: { WorkoutCatalog.normalized($0.name) == WorkoutCatalog.normalized(trimmed) }) {
                    Button { onPick(WorkoutExercise(name: trimmed, sets: [], measure: .weightReps)) } label: {
                        Label("Add “\(trimmed)”", systemImage: "plus").frame(minHeight: 44)
                    }
                }
                let recentShown = recent.filter { trimmed.isEmpty || $0.name.localizedStandardContains(trimmed) }
                if muscle == nil, !recentShown.isEmpty {
                    Section("Recent") {
                        ForEach(recentShown, id: \.name) { exercise in row(exercise.name, detail: nil) { onPick(exercise) } }
                    }
                }
                Section {
                    ForEach(matches) { exercise in
                        row(exercise.name, detail: exercise.muscle.capitalized) {
                            onPick(WorkoutExercise(name: exercise.name, sets: [], exerciseID: exercise.id, measure: exercise.measure))
                        }
                    }
                } header: {
                    if muscle == nil, !recentShown.isEmpty { Text("All") }
                }
            }
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Muscle", selection: $muscle) {
                            Text("All").tag(String?.none)
                            ForEach(Self.muscles, id: \.self) { Text($0.capitalized).tag(String?.some($0)) }
                        }
                    } label: {
                        Image(systemName: muscle == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Muscle")
                    .accessibilityValue(muscle?.capitalized ?? "All")
                }
            }
        }
        .tint(.diaryAccent)
    }

    private func row(_ name: String, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(name).foregroundStyle(Color.diaryText)
                Spacer(minLength: 8)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(Color.diarySecondary) }
            }
            .frame(minHeight: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(name)
    }
}
