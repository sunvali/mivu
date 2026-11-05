import SwiftUI

/// The gym screen: one card per exercise, sets already filled from last time. Lift, tap ✓.
struct LiveWorkoutView: View {
    @State private var model: LiveWorkoutModel
    let onClose: () -> Void
    @State private var picking = false
    @State private var editing: SetPosition?
    @State private var askingDiscard = false
    @State private var showingDone = false
    private let rest = RestTimer.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    struct SetPosition: Identifiable { let exercise: Int, set: Int; var id: String { "\(exercise)-\(set)" } }

    init(store: DiaryStore, profileID: UUID, session: WorkoutSession, mode: LiveWorkoutMode, onClose: @escaping () -> Void) {
        let unit = UserDefaults.standard.string(forKey: "weightUnit") ?? "kg"
        _model = State(initialValue: LiveWorkoutModel(store: store, profileID: profileID, session: session, unit: unit, mode: mode, rest: .shared))
        self.onClose = onClose
    }

    private var step: Double {
        WeightStep.step(unit: model.unit, plates: model.unit == "lb" ? WeightStep.defaultPlatesLb : WeightStep.defaultPlatesKg)
    }
    private var tickedCount: Int {
        model.session.exercises.indices.reduce(0) { total, e in total + model.session.exercises[e].sets.indices.filter { model.isTicked(exercise: e, set: $0) }.count }
    }

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
            .safeAreaInset(edge: .bottom) {
                if model.mode == .live, let end = rest.endsAt { RestBar(rest: rest, endsAt: end).padding(.horizontal, 16).padding(.bottom, 8) }
            }
            .animation(reduceMotion ? nil : .snappy, value: model.expandedExercise)
            .sensoryFeedback(trigger: tickedCount) { old, new in new > old ? .success : nil }
            .navigationDestination(isPresented: $showingDone) { WorkoutDoneView(model: model, onClose: onClose) }
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
                let measure = LiveWorkoutModel.measure(exercise)
                SetWheelSheet(number: position.set + 1, set: exercise.sets[position.set], measure: measure, unit: model.unit, step: step,
                              startingWeight: measure == .reps ? 0 : model.startingWeight(exercise: position.exercise)) { weight, reps, seconds in
                    editing = nil
                    Task {
                        if weight != nil || reps != nil || seconds != nil {
                            await model.update(exercise: position.exercise, set: position.set,
                                               kg: weight.map { WeightStep.kg(fromDisplay: $0, unit: model.unit) }, reps: reps, seconds: seconds)
                        }
                        if !model.isTicked(exercise: position.exercise, set: position.set) { await model.tick(exercise: position.exercise, set: position.set) }
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
                // No digit animation: a clock that animates every second never lets the screen settle.
                Text(timerInterval: model.session.performedAt...Date.distantFuture, countsDown: false)
                    .font(.headline).monospacedDigit()
                    .contentTransition(.identity).transaction { $0.animation = nil }
            } else {
                Text(StartWorkoutSheet.day(model.session.performedAt)).font(.headline)
            }
        }
        // Without the glass capsule: a glass item re-animates every second as the clock ticks.
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                if !model.hasTicked { askingDiscard = true; return }
                guard model.mode != .edit else { Task { if await model.finish() { onClose() } }; return }
                // The workout ends now; the Done screen saves it.
                model.endedAt = .now
                if model.effort == nil { model.effort = model.feel }
                showingDone = true
            }
            .fontWeight(.semibold)
            .accessibilityIdentifier("finishWorkout")
        }
    }

    // MARK: Exercise cards

    @ViewBuilder private func expanded(_ index: Int) -> some View {
        let exercise = model.session.exercises[index]
        VStack(alignment: .leading, spacing: 2) {
            // At accessibility sizes the pill sits under the name instead of squeezing beside it.
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))) {
                Text(exercise.name).font(.headline).foregroundStyle(Color.diaryText).frame(maxWidth: .infinity, alignment: .leading)
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
                    if typeSize.isAccessibilitySize, model.newBests.contains(index) { NewBestPill() }
                }
                Spacer(minLength: 8)
                if !typeSize.isAccessibilitySize, model.newBests.contains(index) { NewBestPill() }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.diarySecondary).accessibilityHidden(true)
            }
            .frame(minHeight: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func setRow(_ exercise: Int, _ index: Int) -> some View {
        let current = model.session.exercises[exercise], set = current.sets[index], done = model.isTicked(exercise: exercise, set: index)
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
                SetNumber(value: Double(set.seconds ?? 0), step: 5, range: 0...86_400, unit: nil, label: "Set \(index + 1) time", done: done,
                          text: { Self.clock(Int($0)) }, onCommit: { commit(nil, nil, Int($0)) }, onTap: open)
                    .accessibilityIdentifier("setTime")
            case .reps:
                if (set.loadKg ?? 0) > 0 {
                    Text("+\(weight(kg: set.loadKg ?? 0)) \(model.unit)").font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
                reps(set, number: index + 1, done: done, commit: commit, open: open)
            case .weightReps:
                // An unset weight shows "–"; a swipe starts from the bar or a light dumbbell.
                SetNumber(value: set.loadKg.map { WeightStep.display(kg: $0, unit: model.unit) } ?? model.startingWeight(exercise: exercise),
                          step: step, range: 0...(model.unit == "lb" ? 1_100 : 500), unit: model.unit, label: "Set \(index + 1) weight", done: done,
                          unset: set.loadKg == nil, text: number, onCommit: { commit(WeightStep.kg(fromDisplay: $0, unit: model.unit), nil, nil) }, onTap: open)
                    .accessibilityIdentifier("setWeight")
                Text("×").foregroundStyle(Color.diarySecondary).accessibilityHidden(true)
                reps(set, number: index + 1, done: done, commit: commit, open: open)
            }
            Spacer(minLength: 4)
            // A weight never chosen is chosen first: ✓ opens the wheels, whose Done ticks.
            Button { if model.needsWeight(exercise: exercise, set: index) { open() } else { Task { await model.tick(exercise: exercise, set: index) } } } label: {
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
            // Removed explicitly: inside a List row the button otherwise reads as selected before it is ticked.
            .accessibilityRemoveTraits(done ? [] : .isSelected)
            .accessibilityIdentifier("tickSet")
        }
        .animation(reduceMotion ? nil : .snappy, value: done)
    }

    private func reps(_ set: WorkoutSet, number: Int, done: Bool, commit: @escaping (Double?, Int?, Int?) -> Void, open: @escaping () -> Void) -> some View {
        SetNumber(value: Double(set.repetitions), step: 1, range: 1...100, unit: nil, label: "Set \(number) reps", done: done,
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
        case .weightReps: return set.loadKg.map { "\(weight(kg: $0)) \(model.unit) × \(set.repetitions)" } ?? "\(set.repetitions) reps"
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
    var unset = false
    let text: (Double) -> String
    let onCommit: (Double) -> Void
    let onTap: () -> Void
    @State private var steps = 0
    @ScaledMetric(relativeTo: .title3) private var width = 64.0
    @Environment(\.dynamicTypeSize) private var typeSize

    private func clamped(_ value: Double) -> Double { min(max(value, range.lowerBound), range.upperBound) }
    private var shown: Double { clamped(value + Double(steps) * step) }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(unset && steps == 0 ? "–" : text(shown)).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Color.diaryText)
                if let unit { Text(unit).font(.caption.weight(.medium)).foregroundStyle(Color.diarySecondary) }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 8)
            .frame(minWidth: min(width, 120), minHeight: 44)
            .background(done ? Color.diaryTintBurn : Color.diaryCanvas, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // One step per 24 points; saved once, when the finger lifts. Off at accessibility sizes, where rows scroll more than they swipe.
        .highPriorityGesture(DragGesture(minimumDistance: 8)
            .onChanged { steps = Int(-$0.translation.height / 24) }
            .onEnded { _ in if steps != 0, shown != value || unset { onCommit(shown) } else { steps = 0 } }, isEnabled: !typeSize.isAccessibilitySize)
        .onChange(of: value) { steps = 0 }
        .sensoryFeedback(.selection, trigger: steps)
        .accessibilityLabel(Text(label))
        .accessibilityValue(unset ? String(localized: "Not set") : text(shown) + (unit.map { " \($0)" } ?? ""))
        .accessibilityAdjustableAction { direction in
            // An unset weight is set to its starting value first.
            let next = unset ? value : clamped(value + (direction == .increment ? step : -step))
            if next != value || unset { onCommit(next) }
        }
    }
}

/// Mockup 3: the rest countdown and Skip; tapping the time offers 15 seconds less or more.
private struct RestBar: View {
    let rest: RestTimer
    let endsAt: Date
    @State private var adjusting = false

    var body: some View {
        HStack(spacing: 12) {
            Button { adjusting.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "timer").font(.body.weight(.semibold)).accessibilityHidden(true)
                    Text(timerInterval: Date.now...max(endsAt, .now), countsDown: true).font(.title3.weight(.bold)).monospacedDigit()
                        // No digit animation: a clock that animates every second never lets the screen settle.
                        .contentTransition(.identity).transaction { $0.animation = nil }
                    Text("rest").font(.subheadline).opacity(0.7)
                }
                .frame(minHeight: 44).contentShape(.rect)
            }
            .accessibilityHint("Shows 15 seconds less or more.")
            Spacer(minLength: 4)
            if adjusting {
                Button("−15") { Task { await rest.adjust(by: -15) } }.accessibilityLabel("15 seconds less").frame(minWidth: 44, minHeight: 44)
                Button("+15") { Task { await rest.adjust(by: 15) } }.accessibilityLabel("15 seconds more").frame(minWidth: 44, minHeight: 44)
            }
            Button("Skip") { rest.skip() }.fontWeight(.semibold).frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Skip rest").accessibilityIdentifier("skipRest")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.diaryCanvas)
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(Color.diaryText, in: .rect(cornerRadius: 20))
    }
}

/// "New best" on an exercise when a ticked set beats every earlier one.
struct NewBestPill: View {
    var body: some View {
        Text("New best").font(.caption.weight(.semibold)).foregroundStyle(Color.diaryCarbs).lineLimit(1).fixedSize()
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Color.diaryTintFoods, in: .capsule)
    }
}
