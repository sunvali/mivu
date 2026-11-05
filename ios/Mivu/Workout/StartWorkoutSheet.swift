import SwiftUI

/// When it starts ("Today, now" unless changed), gym on top, the most-used sports, then "Again" for routines and recent workouts.
struct StartWorkoutSheet: View {
    @Bindable var model: DiaryViewModel
    /// nil means now.
    @Binding var start: Date?
    let onGym: (WorkoutDraft?) -> Void
    let onCardio: (String, WorkoutSession?) -> Void
    @State private var routines: [WorkoutRoutine] = []
    @State private var recent: [WorkoutSession] = []
    @Environment(\.dismiss) private var dismiss

    /// At most three sports: the most used first, topped up with Run, Walk and Cycle.
    private var sports: [WorkoutActivity] {
        let counts = Dictionary(recent.compactMap(\.activity).map { ($0, 1) }, uniquingKeysWith: +)
        var seen: Set = ["strength"]
        return (counts.keys.sorted { (counts[$0]!, $1) > (counts[$1]!, $0) } + ["run", "walk", "cycle"])
            .filter { seen.insert($0).inserted }.compactMap(WorkoutCatalog.activity).prefix(3).map { $0 }
    }

    /// The last three distinct workouts that are not already a routine.
    private var again: [WorkoutSession] {
        var seen = Set(routines.map(\.name))
        return Array(recent.filter { seen.insert(WorkoutRow.title($0)).inserted }.prefix(3))
    }

    var body: some View {
        List {
            Section { WorkoutStartPicker(start: $start) }
            Section {
                Button { onGym(nil) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dumbbell.fill").font(.body.weight(.semibold))
                            .frame(width: 40, height: 40).background(Color.diaryActionText.opacity(0.18), in: .rect(cornerRadius: 12))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gym").font(.headline)
                            Text("Sets and reps").font(.subheadline).opacity(0.85)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.diaryActionText).frame(minHeight: 52).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.diaryWorkout)
                .accessibilityIdentifier("startGym")
            }
            Section {
                ForEach(sports) { sport in
                    row(sport.name, symbol: sport.symbol) { onCardio(sport.id, last(sport.id)) }
                }
                NavigationLink {
                    OtherSportList { onCardio($0, last($0)) }
                } label: {
                    HStack(spacing: 12) { WorkoutIcon(symbol: "ellipsis"); Text("Other sport") }.frame(minHeight: 44)
                }
            }
            if !routines.isEmpty || !again.isEmpty {
                Section {
                    ForEach(routines) { routine in
                        row(routine.name, symbol: "figure.strengthtraining.traditional", detail: routine.lastUsedAt.map(Self.day)) {
                            onGym(routine.draft)
                        }
                    }
                    ForEach(again) { session in
                        row(WorkoutRow.title(session), symbol: WorkoutRow.symbol(session), detail: Self.day(session.performedAt)) { repeatWorkout(session) }
                    }
                } header: {
                    Text("Again").font(.subheadline.weight(.semibold)).foregroundStyle(Color.diarySecondary).textCase(nil)
                }
            }
        }
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("Start workout")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } } }
        .task {
            guard let owner = model.readModel?.profile.id else { return }
            routines = (try? await model.store.routines(expectedProfileID: owner)) ?? []
            // shortcut: "Again" and most-used sports look at the latest 30 workouts; widen if people ask for older ones.
            recent = (try? await model.store.workoutHistory(expectedProfileID: owner).values) ?? []
        }
    }

    private func last(_ activity: String) -> WorkoutSession? { recent.first { $0.activity == activity } }

    /// Gym workouts start again with the same exercises; anything else opens its last numbers.
    private func repeatWorkout(_ session: WorkoutSession) {
        guard session.kind == .strength || !session.exercises.isEmpty else { return onCardio(session.activity ?? "other", session) }
        let exercises = session.exercises.map { exercise in
            var copy = exercise; copy.sets = exercise.sets.map { var set = $0; set.done = nil; set.effort = nil; return set }; return copy
        }
        onGym(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: exercises, title: session.title,
                           activity: session.activity ?? "strength", routineID: session.routineID))
    }

    private func row(_ title: String, symbol: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                WorkoutIcon(symbol: symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Color.diaryText)
                    if let detail { Text(detail).font(.subheadline).foregroundStyle(Color.diarySecondary) }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.diarySecondary).accessibilityHidden(true)
            }
            .frame(minHeight: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// "Today", "Yesterday", a weekday within the week, else the date.
    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.day().month(.wide))
    }
}

/// The Start workout sheet and where it leads, for Today, the Diary and Progress: cardio logs inside the sheet,
/// a gym workout opens on the root's gym screen once the sheet has closed.
struct StartWorkoutFlow: ViewModifier {
    @Bindable var model: DiaryViewModel
    @Binding var isPresented: Bool
    /// The start the sheet opens with; nil is now.
    var initialStart: Date? = nil
    let openWorkout: (WorkoutSession) -> Void
    @State private var cardioPath: [CardioLogState] = []
    @State private var start: Date?
    /// The gym screen waits for the sheet to finish closing; presenting during that slide can leave a transition hanging.
    @State private var sheetOpen = false
    @State private var openAfterSheet: WorkoutSession?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, shown in if shown { cardioPath = []; start = initialStart; sheetOpen = true } }
            .sheet(isPresented: $isPresented, onDismiss: {
                sheetOpen = false
                if let session = openAfterSheet { openAfterSheet = nil; openWorkout(session) }
            }) {
                NavigationStack(path: $cardioPath) {
                    StartWorkoutSheet(model: model, start: $start, onGym: startGym) {
                        var state = CardioLogState(activity: $0, last: $1, now: Date())
                        if let start { state.startedAt = start; state.startEdited = true }
                        cardioPath.append(state)
                    }
                    .navigationDestination(for: CardioLogState.self) { CardioLogView(model: model, state: $0) { isPresented = false } }
                }
                .tint(.diaryAccent)
            }
    }

    /// Starts a live gym workout; a workout already running opens instead of a second one.
    /// A start moved more than five minutes back logs a past workout instead, saved only on Done.
    private func startGym(_ draft: WorkoutDraft?) {
        isPresented = false
        guard let profile = model.readModel?.profile else { return }
        let draft = draft ?? WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: [], activity: "strength")
        let now = Date(), at = start ?? now
        if LiveWorkoutModel.mode(start: start, now: now) == .past {
            var past = WorkoutSession(dayID: UUID(), performedAt: at, timePrecision: .exact, revision: 1, kind: .strength, durationMinutes: 0, exercises: [])
            past.apply(draft)
            return present(past)
        }
        if let active = model.activeWorkout { return present(active) }
        Task { await model.change { present(try await model.store.startWorkout(draft, at: at, expectedProfileID: profile.id)) } }
    }

    private func present(_ session: WorkoutSession) {
        if sheetOpen { openAfterSheet = session } else { openWorkout(session) }
    }
}

/// "Today, now" or the chosen day and time; tap for the date and time wheels. nil means now.
struct WorkoutStartPicker: View {
    @Binding var start: Date?
    @State private var choosing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { withAnimation(reduceMotion ? nil : .snappy) { choosing.toggle() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock").foregroundStyle(Color.diarySecondary).accessibilityHidden(true)
                Text(start.map { "\(StartWorkoutSheet.day($0)), \($0.formatted(date: .omitted, time: .shortened))" } ?? String(localized: "Today, now"))
                    .foregroundStyle(Color.diaryText)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(Color.diarySecondary)
                    .rotationEffect(.degrees(choosing ? 180 : 0)).accessibilityHidden(true)
            }
            .frame(minHeight: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start")
        .accessibilityValue(start.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? String(localized: "Today, now"))
        .accessibilityIdentifier("workoutStart")
        if choosing {
            DatePicker("Start", selection: Binding(get: { start ?? Date() }, set: { start = $0 }), in: ...Date())
                .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
        }
    }
}

/// Every built-in activity except gym, searchable by name.
private struct OtherSportList: View {
    let onPick: (String) -> Void
    @State private var search = ""

    var body: some View {
        List(WorkoutCatalog.activities.filter { $0.id != "strength" && (search.isEmpty || $0.name.localizedStandardContains(search)) }) { sport in
            Button { onPick(sport.id) } label: {
                HStack(spacing: 12) { WorkoutIcon(symbol: sport.symbol); Text(sport.name).foregroundStyle(Color.diaryText) }
                    .frame(minHeight: 44).contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Other sport")
        .navigationBarTitleDisplayMode(.inline)
    }
}
