import SwiftUI

/// One exercise across workouts: its bests, then the last 20 sessions with it.
struct ExerciseDetailView: View {
    @Bindable var model: DiaryViewModel
    let key: ExerciseKey
    let name: String
    @State private var sessions: [WorkoutSession]?
    @AppStorage("weightUnit") private var unit = "kg"
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        List {
            if let sessions {
                let bests = WorkoutHistory.bests(for: key, in: sessions)
                Section {
                    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))) {
                        if let kg = bests.heaviestKg, kg > 0 {
                            best(WeightStep.display(kg: kg, unit: unit).formatted(.number.precision(.fractionLength(0...2))) + " \(unit)", "Heaviest", id: "bestHeaviest")
                        }
                        if let reps = bests.mostReps, reps > 0 { best("\(reps)", "Most reps", id: "bestReps") }
                        if let seconds = bests.longestSeconds, seconds > 0 { best(LiveWorkoutView.clock(seconds), "Longest", id: "bestTime") }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    if sessions.isEmpty { Text("No saved workouts with this exercise yet.").foregroundStyle(Color.diarySecondary) }
                    ForEach(sessions.prefix(20)) { row($0) }
                } header: {
                    Text("Last 20 sessions").font(.subheadline.weight(.semibold)).foregroundStyle(Color.diarySecondary).textCase(nil)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .listSectionSpacing(12)
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: model.changeGeneration) {
            guard let owner = model.selection?.identity.profileID else { return }
            // shortcut: bests read the latest 1,000 workouts with this exercise, as the gym screen does; store bests if someone logs more.
            sessions = (try? await model.store.finishedWorkouts(containing: key, limit: 1_000, expectedProfileID: owner)) ?? []
        }
    }

    private func best(_ value: String, _ label: LocalizedStringKey, id: String) -> some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .center, spacing: 2) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(Color.diaryWorkout)
            Text(label).font(.subheadline).foregroundStyle(Color.diarySecondary)
        }
        .frame(maxWidth: .infinity, alignment: typeSize.isAccessibilitySize ? .leading : .center)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    /// The day, then every set of this exercise that day.
    private func row(_ session: WorkoutSession) -> some View {
        let exercises = session.exercises.filter { ExerciseKey($0) == key }
        let sets = exercises.flatMap { exercise in
            exercise.sets.filter { $0.done != false }.map { WorkoutRow.describe($0, measure: LiveWorkoutModel.measure(exercise), unit: unit) }
        }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 4) {
            Text(StartWorkoutSheet.day(session.performedAt)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.diaryText)
            Text(sets).font(.subheadline).monospacedDigit().foregroundStyle(Color.diarySecondary)
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("exerciseSession")
    }
}
