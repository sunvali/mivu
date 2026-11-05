import SwiftUI

/// After a gym workout: Pip, three numbers, one question, Save. No streaks, no score.
struct WorkoutDoneView: View {
    @Bindable var model: LiveWorkoutModel
    let onClose: () -> Void
    @State private var runtime = CompanionRuntime()
    @State private var saving = false
    /// Saved once; after that Save and the routine button only finish the job, never save the workout twice.
    @State private var finished = false
    @State private var naming = false
    @State private var name = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String { WorkoutRow.title(model.session) }

    var body: some View {
        let summary = model.summary
        ScrollView {
            VStack(spacing: 12) {
                CompanionView(presentation: CompanionOutput(pose: .resting, playback: reduceMotion ? .staticPose : .animated, reactionID: nil, nextDeadline: nil),
                              darkMode: colorScheme == .dark, size: typeSize.isAccessibilitySize ? 96 : 140, runtime: runtime)
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text("Nice work").font(.title2.weight(.bold)).foregroundStyle(Color.diaryText)
                    // A past log's time is set on the ruler below instead.
                    Text(model.mode == .past ? title : "\(title) · \(WorkoutRow.minutes(model.seconds))")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 8))) {
                    stat("\(summary.sets)", summary.sets == 1 ? "set" : "sets")
                    if let kcal = summary.kcal {
                        stat(kcal.formatted(), "kcal", color: .diaryWorkout)
                    } else {
                        // Without a body weight there is no estimate; a dash would be read out as "dash".
                        stat("–", "kcal", color: .diaryWorkout).accessibilityLabel("kcal not estimated")
                    }
                    stat("\(summary.newBests)", summary.newBests == 1 ? "new best" : "new bests")
                }
                .card()
                if model.mode == .past {
                    WorkoutRuler(value: $model.pastMinutes, range: 1...600, step: 1, majorEvery: 5, unit: "min",
                                 format: { $0.formatted(.number.precision(.fractionLength(0))) }, label: "Time")
                        .accessibilityIdentifier("doneTimeRuler").card()
                }
                EffortChips(title: "How did it feel?", effort: $model.effort).card()
                if let error = model.saveError {
                    Label(LocalizedStringKey(error), systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Color.diaryError)
                }
                actions.padding(.top, 8)
            }
            .padding(16)
        }
        .background(Color.diaryCanvas)
        .navigationBarTitleDisplayMode(.inline)
        // Back returns to the workout until it is saved; after that there is nothing to go back to.
        .navigationBarBackButtonHidden(finished || saving)
        .sensoryFeedback(.selection, trigger: model.effort)
        .alert("Save as routine", isPresented: $naming) {
            TextField("Name", text: $name)
            // An alert button's disabled state does not follow typing, so an emptied name falls back to the title.
            // Capped at the store's 100 characters rather than failing with a generic error.
            Button("Save") {
                let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let chosen = String((typed.isEmpty ? title : typed).prefix(100))
                Task { await save { await model.saveRoutine(name: chosen) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            // Task 11b plays the workout moment here; until then Pip rests.
            await runtime.select(CharacterCatalog.bundled.resolve("pip"))
            await runtime.attach(eligible: true)
        }
        .onDisappear { runtime.stop() }
    }

    private func stat(_ value: String, _ label: LocalizedStringKey, color: Color = .diaryText) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(color)
            Text(label).font(.subheadline).foregroundStyle(Color.diarySecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var actions: some View {
        Button { Task { await save { true } } } label: {
            Text("Save").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.glassProminent).tint(.diaryAccent).foregroundStyle(Color.diaryActionText)
        .disabled(saving)
        .accessibilityIdentifier("saveWorkout")
        if let routine = model.routine {
            if model.routineChanged {
                Button("Update \(routine.name)") { Task { await save { await model.updateRoutine() } } }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(saving)
                    .accessibilityIdentifier("updateRoutine")
            }
        } else {
            // A retry keeps what was typed.
            Button("Save as routine") { if name.isEmpty { name = title }; naming = true }
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(saving)
                .accessibilityIdentifier("saveRoutine")
        }
    }

    /// Saves the workout first, then the routine step; closes once both are done.
    private func save(then routine: () async -> Bool) async {
        saving = true; defer { saving = false }
        if !finished { finished = await model.finish(at: model.endedAt) }
        if finished, await routine() { onClose() }
    }
}
