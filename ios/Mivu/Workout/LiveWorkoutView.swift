import SwiftUI

/// The gym screen: one card per exercise, sets already filled from last time. Lift, tap ✓.
struct LiveWorkoutView: View {
    @State private var model: LiveWorkoutModel
    let onClose: () -> Void
    @State private var picking = false
    @State private var editing: SetPosition?
    @State private var askingDiscard = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct SetPosition: Identifiable { let exercise: Int, set: Int; var id: String { "\(exercise)-\(set)" } }

    init(store: DiaryStore, profileID: UUID, session: WorkoutSession, mode: LiveWorkoutMode, onClose: @escaping () -> Void) {
        let unit = UserDefaults.standard.string(forKey: "weightUnit") ?? "kg"
        _model = State(initialValue: LiveWorkoutModel(store: store, profileID: profileID, session: session, unit: unit, mode: mode))
        self.onClose = onClose
    }

    private var step: Double {
        WeightStep.step(unit: model.unit, plates: model.unit == "lb" ? WeightStep.defaultPlatesLb : WeightStep.defaultPlatesKg)
    }
    private var tickedCount: Int { model.session.exercises.reduce(0) { $0 + $1.sets.filter { $0.done == true }.count } }

    var body: some View {
        NavigationStack {
            List {
                if let error = model.saveError {
                    Section {
                        HStack {
                            Label(LocalizedStringKey(error), systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Color.diaryError)
                            Spacer(minLength: 8)
                            Button("Retry") { Task { await model.retry() } }.frame(minHeight: 44)
                        }
                    }
                }
                ForEach(model.session.exercises.indices, id: \.self) { index in
                    Section {
                        if index == model.expandedExercise { expanded(index) } else { collapsed(index) }
                    }
                }
                Section {
                    Button { picking = true } label: {
                        Label("Exercise", systemImage: "plus").font(.headline).foregroundStyle(Color.diaryAccent).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityLabel("Add exercise")
                    .accessibilityIdentifier("addExercise")
                }
                .listRowBackground(Color.clear)
            }
            .listSectionSpacing(12)
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .animation(reduceMotion ? nil : .snappy, value: model.expandedExercise)
            .sensoryFeedback(trigger: tickedCount) { old, new in new > old ? .success : nil }
        }
        .tint(.diaryAccent)
        .task { await model.load() }
        .sheet(isPresented: $picking) {
            ExercisePicker(recent: model.recent) { exercise in
                picking = false
                Task { await model.addExercise(exercise) }
            }
        }
        .sheet(item: $editing) { position in
            // A set deleted while its sheet opens shows nothing.
            if let exercise = model.session.exercises.indices.contains(position.exercise) ? model.session.exercises[position.exercise] : nil,
               exercise.sets.indices.contains(position.set) {
                SetWheelSheet(number: position.set + 1, set: exercise.sets[position.set], measure: LiveWorkoutModel.measure(exercise),
                              unit: model.unit, step: step) { weight, reps, seconds in
                    editing = nil
                    Task {
                        if weight != nil || reps != nil || seconds != nil {
                            await model.update(exercise: position.exercise, set: position.set,
                                               kg: weight.map { WeightStep.kg(fromDisplay: $0, unit: model.unit) }, reps: reps, seconds: seconds)
                        }
                        if model.session.exercises[position.exercise].sets[position.set].done != true { await model.tick(exercise: position.exercise, set: position.set) }
                    }
                }
            }
        }
        .alert(model.hasTicked ? "Discard this workout?" : "Discard empty workout?", isPresented: $askingDiscard) {
            Button("Discard", role: .destructive) { Task { if await model.discard() { onClose() } } }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if model.mode == .live {
                // Keeps the workout running.
                Button(action: onClose) { Image(systemName: "chevron.down") }.accessibilityLabel("Minimize")
            } else {
                Button(role: .close) { if model.hasTicked { askingDiscard = true } else { onClose() } }
            }
        }
        ToolbarItem(placement: .principal) {
            if model.mode == .live {
                Text(timerInterval: model.session.performedAt...Date.distantFuture, countsDown: false)
                    .font(.headline).monospacedDigit()
            } else {
                Text(StartWorkoutSheet.day(model.session.performedAt)).font(.headline)
            }
        }
        // Without the glass capsule: a glass item re-animates every second as the clock ticks.
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                if !model.hasTicked { askingDiscard = true; return }
                Task { if await model.finish() { onClose() } }
            }
            .fontWeight(.semibold)
            .accessibilityIdentifier("finishWorkout")
        }
    }

    // MARK: Exercise cards

    @ViewBuilder private func expanded(_ index: Int) -> some View {
        let exercise = model.session.exercises[index]
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name).font(.headline).foregroundStyle(Color.diaryText)
                Spacer(minLength: 8)
                if model.newBests.contains(index) { NewBestPill() }
            }
            let next = exercise.sets.firstIndex { $0.done != true } ?? 0
            if !exercise.sets.isEmpty, let last = model.lastTime(exercise: index, set: next) {
                Text("Last time \(describe(last, exercise))").font(.subheadline).foregroundStyle(Color.diarySecondary)
            }
        }
        .padding(.vertical, 4)
        ForEach(exercise.sets.indices, id: \.self) { set in
            setRow(index, set)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { Task { await model.deleteSet(exercise: index, set: set) } } label: { Label("Delete", systemImage: "trash") }
                }
        }
        Button { Task { await model.addSet(exercise: index) } } label: {
            Label("Set", systemImage: "plus").font(.body.weight(.semibold)).foregroundStyle(Color.diaryAccent).frame(minHeight: 44)
        }
        .accessibilityLabel("Add set")
        .accessibilityIdentifier("addSet")
    }

    private func collapsed(_ index: Int) -> some View {
        let exercise = model.session.exercises[index]
        let count = exercise.sets.count
        let last = count > 0 ? model.lastTime(exercise: index, set: 0).map { "last " + describe($0, exercise) } : nil
        return Button { model.expandedExercise = index } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name).font(.headline).foregroundStyle(Color.diaryText)
                    Text(["\(count) \(count == 1 ? "set" : "sets")", last].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
                Spacer(minLength: 8)
                if model.newBests.contains(index) { NewBestPill() }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.diarySecondary).accessibilityHidden(true)
            }
            .frame(minHeight: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func setRow(_ exercise: Int, _ index: Int) -> some View {
        let current = model.session.exercises[exercise], set = current.sets[index], done = set.done == true
        let measure = LiveWorkoutModel.measure(current)
        let commit = { (kg: Double?, reps: Int?, seconds: Int?) -> Void in
            Task { await model.update(exercise: exercise, set: index, kg: kg, reps: reps, seconds: seconds) }
        }
        let open = { editing = SetPosition(exercise: exercise, set: index) }
        return HStack(spacing: 8) {
            Text("\(index + 1)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Color.diarySecondary)
                .frame(minWidth: 20, alignment: .leading).accessibilityHidden(true)
            switch measure {
            case .time, .distanceTime:
                SetNumber(value: Double(set.seconds ?? 0), step: 5, range: 0...86_400, unit: nil, label: "Time", done: done,
                          text: { Self.clock(Int($0)) }, onCommit: { commit(nil, nil, Int($0)) }, onTap: open)
                    .accessibilityIdentifier("setTime")
            case .reps:
                if (set.loadKg ?? 0) > 0 {
                    Text("+\(weight(kg: set.loadKg ?? 0)) \(model.unit)").font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
                reps(set, done: done, commit: commit, open: open)
            case .weightReps:
                SetNumber(value: WeightStep.display(kg: set.loadKg ?? 0, unit: model.unit), step: step, range: 0...(model.unit == "lb" ? 1_100 : 500),
                          unit: model.unit, label: "Weight", done: done, text: number, onCommit: { commit(WeightStep.kg(fromDisplay: $0, unit: model.unit), nil, nil) }, onTap: open)
                    .accessibilityIdentifier("setWeight")
                Text("×").foregroundStyle(Color.diarySecondary).accessibilityHidden(true)
                reps(set, done: done, commit: commit, open: open)
            }
            Spacer(minLength: 4)
            Button { Task { await model.tick(exercise: exercise, set: index) } } label: {
                // Fixed size: the glyph sits in a fixed circle; the label carries the text for VoiceOver.
                Image(systemName: "checkmark").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(done ? Color.diaryActionText : Color.diaryRule)
                    .frame(width: 36, height: 36)
                    .background(done ? Color.diarySuccess : .clear, in: .circle)
                    .overlay { Circle().strokeBorder(done ? Color.diarySuccess : Color.diaryRule, lineWidth: 2) }
                    .frame(width: 44, height: 44).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set \(index + 1) done")
            .accessibilityAddTraits(done ? .isSelected : [])
            .accessibilityIdentifier("tickSet")
        }
        .animation(reduceMotion ? nil : .snappy, value: done)
    }

    private func reps(_ set: WorkoutSet, done: Bool, commit: @escaping (Double?, Int?, Int?) -> Void, open: @escaping () -> Void) -> some View {
        SetNumber(value: Double(set.repetitions), step: 1, range: 1...100, unit: nil, label: "Reps", done: done,
                  text: { "\(Int($0))" }, onCommit: { commit(nil, Int($0), nil) }, onTap: open)
            .accessibilityIdentifier("setReps")
    }

    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    private func weight(kg: Double) -> String { number(WeightStep.display(kg: kg, unit: model.unit)) }

    /// "60 kg × 8", "12 reps", "+10 kg × 12" or "1:30".
    private func describe(_ set: WorkoutSet, _ exercise: WorkoutExercise) -> String {
        switch LiveWorkoutModel.measure(exercise) {
        case .time, .distanceTime: return Self.clock(set.seconds ?? 0)
        case .reps: return (set.loadKg ?? 0) > 0 ? "+\(weight(kg: set.loadKg!)) \(model.unit) × \(set.repetitions)" : "\(set.repetitions) reps"
        case .weightReps: return "\(weight(kg: set.loadKg ?? 0)) \(model.unit) × \(set.repetitions)"
        }
    }

    static func clock(_ seconds: Int) -> String { "\(seconds / 60):" + String(format: "%02d", seconds % 60) }
}

/// A number in a set row: swipe it up or down one step per notch, or tap it for the wheels.
private struct SetNumber: View {
    let value: Double
    let step: Double
    let range: ClosedRange<Double>
    let unit: String?
    let label: String
    let done: Bool
    let text: (Double) -> String
    let onCommit: (Double) -> Void
    let onTap: () -> Void
    @State private var steps = 0
    @ScaledMetric(relativeTo: .title3) private var width = 64.0

    private func clamped(_ value: Double) -> Double { min(max(value, range.lowerBound), range.upperBound) }
    private var shown: Double { clamped(value + Double(steps) * step) }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(text(shown)).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Color.diaryText)
                if let unit { Text(unit).font(.caption.weight(.medium)).foregroundStyle(Color.diarySecondary) }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 8)
            .frame(minWidth: min(width, 120), minHeight: 44)
            .background(done ? Color.diaryTintBurn : Color.diaryCanvas, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // One step per 24 points; saved once, when the finger lifts.
        .highPriorityGesture(DragGesture(minimumDistance: 8)
            .onChanged { steps = Int(-$0.translation.height / 24) }
            .onEnded { _ in if shown != value { onCommit(shown) } else { steps = 0 } })
        .onChange(of: value) { steps = 0 }
        .sensoryFeedback(.selection, trigger: steps)
        .accessibilityLabel(LocalizedStringKey(label))
        .accessibilityValue(text(shown) + (unit.map { " \($0)" } ?? ""))
        .accessibilityAdjustableAction { direction in
            let next = clamped(value + (direction == .increment ? step : -step))
            if next != value { onCommit(next) }
        }
    }
}

/// "New best" on an exercise when a ticked set beats every earlier one.
struct NewBestPill: View {
    var body: some View {
        Text("New best").font(.caption.weight(.semibold)).foregroundStyle(Color.diaryCarbs)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Color.diaryTintFoods, in: .capsule)
    }
}
