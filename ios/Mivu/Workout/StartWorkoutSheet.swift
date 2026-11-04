import SwiftUI

/// Gym on top, the most-used sports, then "Again" for routines and recent workouts.
struct StartWorkoutSheet: View {
    @Bindable var model: DiaryViewModel
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
                            onGym(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: routine.exercises, title: routine.name,
                                               activity: "strength", routineID: routine.id))
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
