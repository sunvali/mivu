import SwiftUI

/// A saved workout as the gym screen shows it, read-only: Edit changes everything, Delete has Undo, Ask Pip quotes it.
struct WorkoutDetailView: View {
    @Bindable var model: DiaryViewModel
    let sessionID: UUID
    @State private var ownership: DiarySelectionOwnership?
    @State private var session: WorkoutSession?
    @State private var loadedGeneration: UInt64?
    @State private var requestID = UUID()
    @State private var loadError: String?
    @State private var loading = true
    @State private var deleting = false
    @State private var editingGym: WorkoutSession?
    @State private var editingCardio: WorkoutSession?
    @AppStorage("weightUnit") private var unit = "kg"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openDiaryCoach) private var openChat
    @Environment(\.dynamicTypeSize) private var typeSize

    init(model: DiaryViewModel, sessionID: UUID) {
        self.model = model; self.sessionID = sessionID
        _ownership = State(initialValue: model.selection)
    }

    private var currentSession: WorkoutSession? {
        model.selection == ownership && loadedGeneration == model.changeGeneration ? session : nil
    }

    var body: some View {
        List {
            if let session = currentSession {
                Section { header(session) }
                ForEach(Self.blocks(session.exercises), id: \.self) { block in
                    Section {
                        ForEach(block, id: \.self) { exercise(session.exercises[$0]) }
                    } header: {
                        if block.count > 1 {
                            Text(block.count == 2 ? "Superset" : "Circuit").font(.subheadline.weight(.semibold)).foregroundStyle(Color.diaryWorkout).textCase(nil)
                        }
                    }
                }
                Section {
                    Button("Ask Pip", systemImage: "sparkles") { askPip(session) }
                        .frame(minHeight: 44).accessibilityIdentifier("askPipWorkout")
                    Button("Delete workout", systemImage: "trash", role: .destructive) { Task { await delete(session) } }
                        .frame(minHeight: 44).accessibilityIdentifier("deleteWorkout")
                }
                if let message = model.errorMessage {
                    Section { Label(LocalizedStringKey(message), systemImage: "exclamationmark.circle").foregroundStyle(Color.diaryError) }
                }
            } else if loading { ProgressView("Loading workout…") }
            else {
                ContentUnavailableView(loadError ?? "Workout unavailable", systemImage: "figure.run")
                Button("Reload workout") { Task { await loadSession() } }.frame(minHeight: 44)
            }
        }
        .disabled(deleting)
        .listSectionSpacing(12)
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    guard let session = currentSession else { return }
                    // Lifting opens the gym screen; cardio and sports their rulers.
                    if session.kind == .strength || !session.exercises.isEmpty { editingGym = session } else { editingCardio = session }
                }
                .disabled(currentSession == nil || deleting)
                .accessibilityIdentifier("editWorkout")
            }
        }
        .task(id: model.changeGeneration) { await loadSession() }
        .onChange(of: model.selection) { _, selected in
            editingGym = nil; editingCardio = nil
            if selected != ownership { dismiss() }
        }
        .fullScreenCover(item: $editingGym) { session in
            if let owner = ownership?.identity.profileID {
                LiveWorkoutView(store: model.store, profileID: owner, session: session, mode: .edit, onSaved: { _, _ in }) { editingGym = nil }
                    .proofTypeSize()
            }
        }
        .sheet(item: $editingCardio) { session in
            NavigationStack {
                CardioLogView(model: model, state: CardioLogState(editing: session), editing: session) { editingCardio = nil }
            }
            .tint(.diaryAccent)
        }
    }

    /// Icon, title and when; then time, sets, distance and burn as big numbers.
    private func header(_ session: WorkoutSession) -> some View {
        let sets = session.exercises.reduce(0) { $0 + $1.sets.filter { $0.done != false }.count }
        let when = [StartWorkoutSheet.day(session.performedAt),
                    session.timePrecision == .exact ? session.performedAt.formatted(date: .omitted, time: .shortened) : nil].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                WorkoutIcon(symbol: WorkoutRow.symbol(session))
                VStack(alignment: .leading, spacing: 2) {
                    Text(WorkoutRow.title(session)).font(.title3.weight(.bold)).foregroundStyle(Color.diaryText)
                    Text(when).font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
            }
            .accessibilityElement(children: .combine)
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))) {
                stat(WorkoutRow.minutes(session.durationSeconds ?? session.durationMinutes * 60), "time")
                if sets > 0 { stat("\(sets)", sets == 1 ? "set" : "sets") }
                if let meters = session.distanceMeters, meters > 0 { stat(WorkoutRow.distance(meters, activity: session.activity), "distance") }
                if let burn = WorkoutRow.burn(session) {
                    stat(burn, "kcal", color: .diaryWorkout).accessibilityLabel("\(burn.replacingOccurrences(of: "~", with: "about ")) kilocalories burned")
                }
            }
            if let note = session.note { Text(note).font(.subheadline).foregroundStyle(Color.diarySecondary) }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ value: String, _ label: LocalizedStringKey, color: Color = .diaryText) -> some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .center, spacing: 2) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(color)
            Text(label).font(.subheadline).foregroundStyle(Color.diarySecondary)
        }
        .frame(maxWidth: .infinity, alignment: typeSize.isAccessibilitySize ? .leading : .center)
        .accessibilityElement(children: .combine)
    }

    /// The exercise's name opens its history; its sets read as on the gym screen.
    @ViewBuilder private func exercise(_ exercise: WorkoutExercise) -> some View {
        NavigationLink {
            ExerciseDetailView(model: model, key: ExerciseKey(exercise), name: exercise.name)
        } label: {
            Text(exercise.name).font(.headline).foregroundStyle(Color.diaryText).frame(minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier("exerciseName")
        if let note = exercise.note { Text(note).font(.subheadline).foregroundStyle(Color.diarySecondary) }
        let measure = LiveWorkoutModel.measure(exercise)
        ForEach(Array(exercise.sets.filter { $0.done != false }.enumerated()), id: \.offset) { number, set in
            let caption = [set.type.flatMap(LiveWorkoutView.typeName), set.effort.map { String(localized: "How hard: \($0)") }].compactMap { $0 }.joined(separator: " · ")
            let text = WorkoutRow.describe(set, measure: measure, unit: unit)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(number + 1)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Color.diarySecondary)
                    .frame(minWidth: 20, alignment: .leading)
                Text(text).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Color.diaryText)
                Spacer(minLength: 8)
                if !caption.isEmpty { Text(caption).font(.caption).foregroundStyle(Color.diarySecondary).multilineTextAlignment(.trailing) }
            }
            .frame(minHeight: 32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([String(localized: "Set \(number + 1)"), text, caption].filter { !$0.isEmpty }.joined(separator: ", "))
        }
    }

    /// Neighbours sharing a group form one superset card; others stand alone.
    static func blocks(_ exercises: [WorkoutExercise]) -> [Range<Int>] {
        var result: [Range<Int>] = [], index = 0
        while index < exercises.count {
            let block = WorkoutSession.block(of: index, in: exercises)
            result.append(block); index = block.upperBound
        }
        return result
    }

    private func askPip(_ session: WorkoutSession) {
        guard let selection = model.selection else { return }
        let text = "\(WorkoutRow.title(session)) · \(session.durationMinutes) min · \(session.performedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
        openChat(.day(session.dayID), reply: CoachReply(target: .workout(workoutID: session.id), excerpt: String(text.prefix(280))), expectedSelection: selection)
    }

    /// Deleted at once; the screen it returns to offers Undo.
    private func delete(_ session: WorkoutSession) async {
        guard let ownership, model.selection == ownership, !deleting else { return }
        let owner = ownership.identity.profileID
        deleting = true
        let success = await model.change { try await model.store.deleteWorkout(id: session.id, expectedRevision: session.revision, expectedProfileID: owner) }
        deleting = false
        guard success, model.selection == ownership else { return }
        model.deletedWorkout = .init(session: session, owner: owner)
        dismiss()
    }

    private func loadSession() async {
        guard let ownership, model.selection == ownership else { return }
        let generation = model.changeGeneration, request = UUID()
        requestID = request; loading = true; loadError = nil
        do {
            let value = try await model.store.coachWorkout(id: sessionID, expectedProfileID: ownership.identity.profileID)
            guard !Task.isCancelled, model.selection == ownership, model.changeGeneration == generation, requestID == request else { return }
            session = value; loadedGeneration = generation; loading = false
        } catch {
            guard !Task.isCancelled, model.selection == ownership, model.changeGeneration == generation, requestID == request else { return }
            session = nil; loading = false
            loadError = "Could not load this workout. It may have been removed."
        }
    }
}

/// "Workout deleted" with Undo over the screen the detail returned to, for five seconds (ten with VoiceOver).
struct WorkoutDeletedToast: ViewModifier {
    @Bindable var model: DiaryViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let deleted = model.deletedWorkout, model.selection?.identity.profileID == deleted.owner {
                // At accessibility sizes Undo goes under the message, so neither breaks mid-word.
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))) {
                    HStack(spacing: 12) {
                        Image(systemName: "trash").foregroundStyle(Color.diarySecondary).accessibilityHidden(true)
                        Text("Workout deleted").font(.subheadline.weight(.semibold)).foregroundStyle(Color.diaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    Button { Task { await model.undoWorkoutDeletion() } } label: {
                        Text("Undo").font(.subheadline.weight(.semibold)).foregroundStyle(Color.diaryAccent)
                            .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                    }
                    .accessibilityIdentifier("undoWorkoutDelete")
                }
                .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 6)
                // Solid, not glass, like the logged-meal toast: it sits over busy rows.
                .background(Color.diarySurface, in: .rect(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.diaryRule))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding(.horizontal, 16).padding(.bottom, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .task(id: deleted.session.id) {
                    AccessibilityNotification.Announcement("Workout deleted").post()
                    try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 10 : 5))
                    if !Task.isCancelled, model.deletedWorkout == deleted { withAnimation { model.deletedWorkout = nil } }
                }
            }
        }
    }
}
