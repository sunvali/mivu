import SwiftUI
import AVFoundation

/// Search the built-in exercises (names and aliases), pick a recent one, filter by muscle, add your own by name,
/// or photograph a machine to name it.
struct ExercisePicker: View {
    let recent: [WorkoutExercise]
    var recognizer: MachineRecognizer? = nil
    var onGuess: (MachineGuess) -> Void = { _ in }
    let onPick: (WorkoutExercise) -> Void
    @State private var search = ""
    @State private var muscle: String?
    @State private var showingCamera = false
    @State private var looking = false
    @State private var preparation = PhotoPreparation()
    @FocusState private var searching: Bool
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
            .overlay { if looking { ProgressView("Looking…").padding(24).background(.regularMaterial, in: .rect(cornerRadius: 20)) } }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .searchFocused($searching)
            .fullScreenCover(isPresented: $showingCamera) {
                CameraCapture(preparation: preparation, onPhoto: { jpeg in Task { await recognize(jpeg) } }, onFailure: { searching = true })
                    .ignoresSafeArea()
            }
            .navigationTitle("Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                if recognizer != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button { Task { await openCamera() } } label: { Image(systemName: "camera") }
                            .disabled(looking)
                            .accessibilityLabel("Photo of a machine")
                            .accessibilityIdentifier("machinePhoto")
                    }
                }
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

    /// Camera access is asked the usual way; denied or unavailable falls back to typing, with no error screen.
    private func openCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { searching = true; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showingCamera = true
        case .notDetermined: if await AVCaptureDevice.requestAccess(for: .video) { showingCamera = true } else { searching = true }
        default: searching = true
        }
    }

    /// A recognized machine goes back to the workout; nothing recognized (or offline) opens the search instead.
    private func recognize(_ jpeg: Data) async {
        guard let recognizer else { return }
        looking = true
        let guess = await recognizer.recognize(jpeg: jpeg)
        looking = false
        if let guess { onGuess(guess) } else { searching = true }
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
