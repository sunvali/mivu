import SwiftUI
import UniformTypeIdentifiers

/// Import from Strong or Hevy: pick their CSV export, see what it holds, import it in one go.
struct WorkoutImportView: View {
    @Bindable var model: DiaryViewModel
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var picking = false
    @State private var parsed: (format: WorkoutCSVFormat, workouts: [ImportedWorkout], skipped: Int)?
    @State private var result: String?
    @State private var problem: String?
    @State private var importing = false
    /// The person's own exercise names, so the preview counts only exercises that would be new.
    @State private var ownNames: Set<String> = []

    private var owner: (id: UUID, zone: TimeZone)? {
        model.readModel.map { ($0.profile.id, TimeZone(identifier: $0.profile.timeZoneID) ?? .current) }
    }

    var body: some View {
        List {
            Section {
                Button { picking = true } label: { Label("Choose a CSV file", systemImage: "doc").frame(minHeight: 44) }
                    .accessibilityIdentifier("chooseWorkoutCSV")
            } footer: {
                Text("In Strong or Hevy, export your workouts as CSV, then choose that file here.")
            }
            if let parsed {
                Section {
                    Text(preview(parsed)).font(.headline).accessibilityIdentifier("importPreview")
                    if parsed.skipped > 0 { Text("\(parsed.skipped) couldn't be read and will be skipped.").foregroundStyle(Color.diarySecondary) }
                    Button { Task { await save(parsed) } } label: { Text("Import").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.borderedProminent).disabled(importing || parsed.workouts.isEmpty || owner == nil)
                        .accessibilityIdentifier("importWorkouts")
                }
            }
            if let result { Section { Text(result).accessibilityIdentifier("importResult") } }
            if let problem { Section { Text(problem).foregroundStyle(Color.diaryError) } }
        }
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("Import workouts")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText]) { read($0) }
        .task(id: model.changeGeneration) {
            guard let owner, let names = try? await model.store.ownExerciseNames(expectedProfileID: owner.id) else { return }
            ownNames = Set(names.map { "own:" + WorkoutCatalog.normalized($0) })
        }
    }

    /// "84 workouts · 23 exercises (6 new)": new means neither built in nor already one of yours.
    private func preview(_ parsed: (format: WorkoutCSVFormat, workouts: [ImportedWorkout], skipped: Int)) -> String {
        let exercises = Set(parsed.workouts.flatMap(\.draft.exercises).map { ExerciseKey($0).raw })
        let new = exercises.filter { $0.hasPrefix("own:") && !ownNames.contains($0) }.count
        let count = parsed.workouts.count
        return "\(count) \(count == 1 ? "workout" : "workouts") · \(exercises.count) \(exercises.count == 1 ? "exercise" : "exercises")" + (new > 0 ? " (\(new) new)" : "")
    }

    private func read(_ picked: Result<URL, any Error>) {
        result = nil; problem = nil; parsed = nil
        guard case let .success(url) = picked, let owner else { problem = "Couldn't open that file."; return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count <= 50_000_000,
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let format = WorkoutCSV.detect(header: String(text.prefix { $0 != "\n" && $0 != "\r" })),
              let found = try? WorkoutCSV.parse(text, format: format, defaultUnit: unit, zone: owner.zone) else {
            problem = "This doesn't look like a Strong or Hevy export."; return
        }
        parsed = (format, found.workouts, found.skipped)
    }

    private func save(_ parsed: (format: WorkoutCSVFormat, workouts: [ImportedWorkout], skipped: Int)) async {
        guard let owner else { return }
        importing = true; defer { importing = false }
        var counts: (added: Int, duplicates: Int)?
        let saved = await model.change {
            counts = try await model.store.importWorkouts(parsed.workouts, source: parsed.format == .strong ? .importStrong : .importHevy, expectedProfileID: owner.id)
        }
        guard saved, let counts else { problem = model.errorMessage ?? "Couldn't import. Nothing was changed."; return }
        self.parsed = nil
        result = "Imported \(counts.added) \(counts.added == 1 ? "workout" : "workouts")" + (counts.duplicates > 0 ? ", \(counts.duplicates) already here." : ".")
    }
}

/// Every finished workout as one CSV file, for the share sheet.
enum WorkoutExport {
    @MainActor static func file(model: DiaryViewModel) async throws -> URL {
        guard let profile = model.readModel?.profile else { throw DiaryError.notFound }
        var sessions: [WorkoutSession] = [], before: Int?
        repeat {
            let page = try await model.store.workoutHistory(before: before, expectedProfileID: profile.id)
            sessions += page.values; before = page.cursor
            if !page.hasMore { break }
        } while before != nil
        let csv = WorkoutCSV.export(sessions.sorted { $0.performedAt < $1.performedAt }, zone: TimeZone(identifier: profile.timeZoneID) ?? .current)
        let url = URL.temporaryDirectory.appending(path: "Mivu workouts.csv")
        try Data(csv.utf8).write(to: url, options: .atomic)
        return url
    }
}
