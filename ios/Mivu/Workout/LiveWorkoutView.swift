import SwiftUI

/// The gym screen: one card per exercise, sets already filled from last time. Lift, tap ✓.
struct LiveWorkoutView: View {
    @State private var model: LiveWorkoutModel
    let onClose: () -> Void
    /// Pip's bar in a live workout; nil where there is no Coach (editing a saved workout).
    let coach: CoachViewModel?
    @State private var picking = false
    @State private var pickerOpensCamera = false
    @State private var editing: SetPosition?
    @State private var askingDiscard = false
    @State private var showingDone = false
    /// The exercise "Replace" swaps out, while the picker is open for it.
    @State private var replacing: Int?
    @State private var noting: Int?
    @State private var noteText = ""
    @State private var removing: Int?
    @State private var typingKcal = false
    @State private var kcalText = ""
    @State private var notice: String?
    /// "Which one?" for a machine photo's guess with several uses.
    @State private var choosingGuess = false
    /// The exercise a one-use machine photo just added, offered for Undo.
    @State private var guessedName: String?
    @Environment(ChatGPTConnection.self) private var connection: ChatGPTConnection?
    @AccessibilityFocusState private var focusedTick: String?
    private let rest = RestTimer.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    struct SetPosition: Identifiable { let exercise: Int, set: Int; var id: String { "\(exercise)-\(set)" } }

    init(store: DiaryStore, profileID: UUID, session: WorkoutSession, mode: LiveWorkoutMode, notice: String? = nil, coach: CoachViewModel? = nil,
         onSaved: @escaping (WorkoutSession, UUID) -> Void, onClose: @escaping () -> Void) {
        _notice = State(initialValue: notice)
        self.coach = coach
        let unit = UserDefaults.standard.string(forKey: "weightUnit") ?? "kg"
        _model = State(initialValue: LiveWorkoutModel(store: store, profileID: profileID, session: session, unit: unit, mode: mode, rest: .shared,
                                                      onSaved: onSaved))
        self.onClose = onClose
    }

    private var step: Double { WeightStep.step(unit: model.unit, plates: WeightStep.plates(unit: model.unit)) }
    private var recognizer: MachineRecognizer? {
        guard let connection, MachineRecognizer.offered(provider: connection.provider, connected: connection.planAuthorized),
              let infer = try? connection.inference() else { return nil }
        return MachineRecognizer(infer: infer)
    }
    /// Pip can change a workout only through ChatGPT; the on-device model reads food alone.
    private var pipAvailable: Bool {
        (connection?.provider == .chatGPT && connection?.planAuthorized == true) || DiaryLaunch.isCoachInferenceFixture
    }
    private var tickedCount: Int {
        model.session.exercises.indices.reduce(0) { total, e in total + model.session.exercises[e].sets.indices.filter { model.isTicked(exercise: e, set: $0) }.count }
    }

    /// A machine guess, the rest countdown and Pip's bar, pinned under the list.
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let guessedName { guessToast(guessedName) }
            if model.mode == .live, let end = rest.endsAt { RestBar(rest: rest, endsAt: end) }
            if model.mode == .live, let coach, pipAvailable {
                GymPipBar(coach: coach, model: model, onCamera: recognizer == nil ? nil : { pickerOpensCamera = true; picking = true })
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    /// Sets ticked, the burn so far and new bests, above the cards.
    private var stats: some View {
        let summary = model.summary
        return HStack(spacing: 20) {
            Label("\(tickedCount) \(tickedCount == 1 ? "set" : "sets")", systemImage: "checkmark.circle.fill")
            if let kcal = summary.kcal { Label("~\(Int(kcal.rounded())) kcal", systemImage: "flame.fill") }
            if summary.newBests > 0 { Label("\(summary.newBests) new best", systemImage: "trophy.fill").foregroundStyle(Color.diaryCarbs) }
        }
        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.diarySecondary)
        .frame(minHeight: 28, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        NavigationStack {
            List {
                if model.mode == .edit {
                    // Editing a saved workout: when it started, how long it took, how it felt, its burn and note.
                    Section {
                        WorkoutStartPicker(start: Binding(get: { model.session.performedAt }, set: { if let date = $0 { model.session.performedAt = date } }))
                        // A stored time under a minute reads "1 min", as its row does, and stays as it was unless dragged.
                        WorkoutRuler(value: $model.pastMinutes, range: 1...600, step: 1, majorEvery: 5, unit: "min",
                                     format: { max($0, 1).formatted(.number.precision(.fractionLength(0))) }, label: "Time")
                            .accessibilityIdentifier("editTimeRuler")
                        EffortChips(title: "How did it feel?", effort: Binding(get: { model.session.effort }, set: { model.session.effort = $0 }))
                            .padding(.vertical, 4)
                        editKcal
                        TextField("Note", text: Binding(get: { model.session.note ?? "" }, set: { model.session.note = $0 }), axis: .vertical)
                            .lineLimit(1...4).frame(minHeight: 44)
                            .accessibilityIdentifier("editWorkoutNote")
                    }
                }
                if let notice {
                    Section {
                        Label(notice, systemImage: "info.circle").font(.subheadline).foregroundStyle(Color.diarySecondary)
                            .frame(minHeight: 44, alignment: .leading).accessibilityIdentifier("liveWorkoutNotice")
                    }
                    .task {
                        AccessibilityNotification.Announcement(notice).post()
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation(reduceMotion ? nil : .snappy) { self.notice = nil }
                    }
                }
                if let error = model.saveError {
                    Section {
                        HStack {
                            Label(LocalizedStringKey(error), systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Color.diaryError)
                            Spacer(minLength: 8)
                            Button("Retry") { Task { await model.retry() } }.frame(minHeight: 44)
                        }
                    }
                }
                if model.mode == .live, tickedCount > 0 { Section { stats }.listRowBackground(Color.clear) }
                ForEach(blocks, id: \.self) { block in
                    Section {
                        ForEach(block, id: \.self) { index in
                            // Rows are positions: a row can redraw after saving dropped its exercise, before the list does.
                            if model.session.exercises.indices.contains(index) {
                                if block.contains(model.expandedExercise) { expanded(index) } else { collapsed(index) }
                            }
                        }
                        // A superset's cards share a bar down their left edge.
                        .listRowBackground(block.count > 1 ? Color.diarySurface.overlay(alignment: .leading) { Color.diaryWorkout.frame(width: 4) } : nil)
                    } header: {
                        if block.count > 1 { supersetHeader(block) }
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
            .safeAreaInset(edge: .bottom) { bottomBar }
            .animation(reduceMotion ? nil : .snappy, value: model.expandedExercise)
            .animation(reduceMotion ? nil : .snappy, value: model.session.exercises.map(\.groupID))
            // VoiceOver follows a superset to its next exercise.
            .onChange(of: model.focus.map { "\($0.exercise)-\($0.set)" }) { _, id in if let id, isGrouped(model.focus?.exercise) { focusedTick = id } }
            .sensoryFeedback(trigger: tickedCount) { old, new in new > old ? .success : nil }
            .navigationDestination(isPresented: $showingDone) { WorkoutDoneView(model: model, onClose: onClose) }
        }
        .tint(.diaryAccent)
        .task { await model.load() }
        .sheet(isPresented: $picking, onDismiss: { replacing = nil; pickerOpensCamera = false }) {
            ExercisePicker(recent: model.recent, recognizer: replacing == nil ? recognizer : nil, opensCamera: pickerOpensCamera, onGuess: { guess in
                picking = false
                Task {
                    await model.addGuess(guess)
                    if model.pendingGuess != nil { choosingGuess = true } else { guessedName = model.session.exercises.last?.name }
                }
            }) { exercise in
                let replaced = replacing
                picking = false
                Task { if let replaced { await model.replaceExercise(replaced, with: exercise) } else { await model.addExercise(exercise) } }
            }
        }
        .sheet(isPresented: $choosingGuess) {
            if let guess = model.pendingGuess {
                MachineChoiceSheet(options: guess.options, current: model.session.exercises.indices.contains(guess.exercise) ? model.session.exercises[guess.exercise].exerciseID : nil) { id in
                    Task { await model.chooseGuess(id) }
                }
            }
        }
        .task(id: guessedName) {
            guard guessedName != nil else { return }
            try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 10 : 4))
            if !Task.isCancelled { withAnimation(reduceMotion ? nil : .snappy) { guessedName = nil } }
        }
        .alert("Calories burned", isPresented: $typingKcal) {
            TextField("kcal", text: $kcalText).keyboardType(.numberPad)
            Button("Save") { model.typedKcal = Double(kcalText).flatMap { (0...100_000).contains($0) ? $0.rounded() : nil } }
            if model.typedKcal != nil { Button("Use estimate") { model.typedKcal = nil } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Note", isPresented: Binding(get: { noting != nil }, set: { if !$0 { noting = nil } })) {
            TextField("Note", text: $noteText)
            Button("Save") { if let index = noting { Task { await model.setNote(noteText, exercise: index) } } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(removing.map { model.session.exercises.indices.contains($0) ? "Remove \(model.session.exercises[$0].name)?" : "" } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) { if let index = removing { Task { await model.removeExercise(index) } } }
        } message: { Text("Its ticked sets are removed too.") }
        .sheet(item: $editing) { position in
            // A set deleted while its sheet opens shows nothing.
            if let exercise = model.session.exercises.indices.contains(position.exercise) ? model.session.exercises[position.exercise] : nil,
               exercise.sets.indices.contains(position.set) {
                let measure = LiveWorkoutModel.measure(exercise)
                SetWheelSheet(number: position.set + 1, set: exercise.sets[position.set], measure: measure, unit: model.unit, step: step,
                              barbell: exercise.exerciseID.flatMap { WorkoutCatalog.exercise($0)?.barbell } == true,
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
        .alert(model.mode == .edit ? "Discard changes?" : model.hasTicked ? "Discard this workout?" : "Discard empty workout?", isPresented: $askingDiscard) {
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
                Button(role: .close) { if model.mode == .edit ? model.editChanged : model.hasTicked { askingDiscard = true } else { onClose() } }
            }
        }
        ToolbarItem(placement: .principal) {
            if model.mode == .live {
                // No digit animation: a clock that animates every second never lets the screen settle.
                Text(timerInterval: model.session.clockStart...Date.distantFuture, countsDown: false)
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
                // An edit saves as it is: an older workout may have no sets at all, only its time.
                guard model.mode != .edit else { Task { if await model.finish() { onClose() } }; return }
                if !model.hasTicked { askingDiscard = true; return }
                // The workout ends now (or at its last change, if Done was forgotten); the Done screen saves it.
                model.endedAt = model.doneTime(now: .now)
                if model.effort == nil { model.effort = model.feel }
                showingDone = true
            }
            .fontWeight(.semibold)
            .accessibilityIdentifier("finishWorkout")
        }
    }

    /// The burn an edit saves: "~310 kcal" estimated or "310 kcal" typed; tap to type your own, as on the cardio screen.
    private var editKcal: some View {
        let kcal = model.editKcal
        let shown = kcal.map { (model.typedKcal == nil ? "~" : "") + "\($0.formatted()) kcal" } ?? String(localized: "Type kcal")
        return Button { kcalText = kcal.map { $0.formatted(.number.grouping(.never)) } ?? ""; typingKcal = true } label: {
            HStack {
                Text("Burn").foregroundStyle(Color.diaryText)
                Spacer(minLength: 8)
                Text(shown).monospacedDigit().foregroundStyle(Color.diaryWorkout)
            }
            .frame(minHeight: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Burn")
        .accessibilityValue(kcal == nil ? String(localized: "Not estimated") : shown.replacingOccurrences(of: "~", with: "About "))
        .accessibilityIdentifier("editKcal")
    }

    /// A one-use machine photo's exercise was added; Undo takes it out again.
    private func guessToast(_ name: String) -> some View {
        HStack(spacing: 12) {
            Text(name).font(.body.weight(.semibold)).foregroundStyle(Color.diaryText).frame(maxWidth: .infinity, alignment: .leading)
            Button("Undo") {
                guessedName = nil
                if let last = model.session.exercises.indices.last, model.session.exercises[last].name == name { Task { await model.removeExercise(last) } }
            }
            .font(.body.weight(.semibold)).foregroundStyle(Color.diaryAccent).frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier("undoGuess")
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(Color.diarySurface, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }

    // MARK: Exercise cards

    @ViewBuilder private func expanded(_ index: Int) -> some View {
        let exercise = model.session.exercises[index]
        let glyph = ExerciseGlyphStyle(exerciseID: exercise.exerciseID, name: exercise.name)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                ExerciseGlyph(exerciseID: exercise.exerciseID, name: exercise.name)
                VStack(alignment: .leading, spacing: 2) {
                    // At accessibility sizes the pill sits under the name instead of squeezing beside it.
                    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))) {
                        Text(exercise.name).font(.headline).foregroundStyle(Color.diaryText).frame(maxWidth: .infinity, alignment: .leading)
                        if model.newBests.contains(index) { NewBestPill() }
                    }
                    // At accessibility sizes the tile's colour carries the muscle, so the sets stay in view.
                    if let subtitle = glyph.subtitle, !typeSize.isAccessibilitySize { Text(subtitle).font(.subheadline).foregroundStyle(glyph.family.ink) }
                }
                exerciseMenu(index)
            }
            let next = exercise.sets.firstIndex { $0.done != true } ?? 0
            if !exercise.sets.isEmpty, let last = model.lastTime(exercise: index, set: next) {
                Text("Last time \(describe(last, exercise))").font(.subheadline).foregroundStyle(Color.diarySecondary)
            }
            if let note = exercise.note { Text(note).font(.subheadline).foregroundStyle(Color.diarySecondary) }
            if model.pendingGuess?.exercise == index {
                Button("Change") { choosingGuess = true }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.diaryAccent).buttonStyle(.plain).frame(minHeight: 44)
                    .accessibilityLabel("Change exercise")
                    .accessibilityIdentifier("changeGuess")
            }
        }
        .padding(.bottom, 4)
        ForEach(exercise.sets.indices, id: \.self) { set in
            if model.session.exercises.indices.contains(index), model.session.exercises[index].sets.indices.contains(set) {
                setRow(index, set)
                    .contextMenu { setMenu(index, set) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await model.deleteSet(exercise: index, set: set) } } label: { Label("Delete", systemImage: "trash") }
                    }
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
                ExerciseGlyph(exerciseID: exercise.exerciseID, name: exercise.name)
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
        // In a superset the set to lift next is ringed in the workout colour.
        let next = !done && isGrouped(exercise) && model.focus.map { $0 == (exercise, index) } == true
        let caption = [set.type.flatMap(Self.typeName), set.effort.map { String(localized: "How hard: \($0)") }].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 8) {
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
                    .foregroundStyle(done ? Color.diaryActionText : next ? Color.diaryWorkout : Color.diaryRule)
                    .frame(width: 36, height: 36)
                    .background(done ? Color.diarySuccess : .clear, in: .circle)
                    .overlay { Circle().strokeBorder(done ? Color.diarySuccess : next ? Color.diaryWorkout : Color.diaryRule, lineWidth: 2) }
                    .frame(width: 44, height: 44).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set \(index + 1) done")
            .accessibilityAddTraits(done ? .isSelected : [])
            // Removed explicitly: inside a List row the button otherwise reads as selected before it is ticked.
            .accessibilityRemoveTraits(done ? [] : .isSelected)
            .accessibilityValue(next ? String(localized: "Up next") : "")
            .accessibilityFocused($focusedTick, equals: "\(exercise)-\(index)")
            .accessibilityIdentifier("tickSet")
        }
        if !caption.isEmpty {
            Label { Text(caption) } icon: { Image(systemName: set.type.flatMap(Self.typeSymbol) ?? "gauge.with.dots.needle.67percent") }
                .font(.caption).foregroundStyle(set.type == .warmup ? Color.diaryCarbs : Color.diarySecondary).padding(.leading, 28).padding(.bottom, 4)
        }
        }
        .animation(reduceMotion ? nil : .snappy, value: done)
    }

    // MARK: Hidden one level down

    /// Consecutive exercises sharing a group form one superset card; others stand alone.
    private var blocks: [Range<Int>] {
        var result: [Range<Int>] = [], index = 0
        while index < model.session.exercises.count {
            let block = WorkoutSession.block(of: index, in: model.session.exercises)
            result.append(block); index = block.upperBound
        }
        return result
    }

    private func isGrouped(_ exercise: Int?) -> Bool {
        guard let exercise, model.session.exercises.indices.contains(exercise) else { return false }
        return WorkoutSession.block(of: exercise, in: model.session.exercises).count > 1
    }

    /// "Superset · Round 2 of 3", or "Circuit" for three or more.
    private func supersetHeader(_ block: Range<Int>) -> some View {
        let round = model.round(of: block)
        return Text("\(block.count == 2 ? String(localized: "Superset") : String(localized: "Circuit")) · Round \(round.current) of \(round.total)")
            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.diaryWorkout).textCase(nil)
            .accessibilityIdentifier("supersetHeader")
    }

    private static let restChoices = [30, 45, 60, 90, 120, 150, 180, 240, 300]

    /// The exercise ⋯ menu: superset, rest, replace, move, note, remove.
    private func exerciseMenu(_ index: Int) -> some View {
        let exercises = model.session.exercises, block = WorkoutSession.block(of: index, in: exercises)
        let others = exercises.indices.filter { !block.contains($0) }
        let ticked = exercises[index].sets.contains { $0.done == true }
        return Menu {
            Menu {
                ForEach(others, id: \.self) { other in
                    Button(exercises[other].name) { Task { await model.group([index, other]) } }
                }
                if block.count > 1 {
                    Button("Take out of superset", systemImage: "minus.circle") { Task { await model.ungroup(exercise: index) } }
                }
            } label: { Label("Superset with…", systemImage: "link") }
            .disabled(others.isEmpty && block.count < 2)
            Picker(selection: Binding(get: { exercises[index].restSeconds }, set: { seconds in Task { await model.setRest(seconds, exercise: index) } })) {
                Text("Default").tag(Int?.none)
                ForEach(Self.restChoices, id: \.self) { Text(Self.clock($0)).tag(Int?.some($0)) }
            } label: { Label("Rest time", systemImage: "timer") }
            .pickerStyle(.menu)
            Button("Replace", systemImage: "arrow.left.arrow.right") { replacing = index; picking = true }.disabled(ticked)
            Menu {
                Button("Up", systemImage: "arrow.up") { Task { await model.moveExercise(index, up: true) } }.disabled(index == 0)
                Button("Down", systemImage: "arrow.down") { Task { await model.moveExercise(index, up: false) } }.disabled(index == exercises.count - 1)
            } label: { Label("Move", systemImage: "arrow.up.arrow.down") }
            Button("Note", systemImage: "note.text") { noteText = exercises[index].note ?? ""; noting = index }
            Button("Remove", systemImage: "trash", role: .destructive) {
                if ticked { removing = index } else { Task { await model.removeExercise(index) } }
            }
        } label: {
            Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(Color.diarySecondary)
                .frame(width: 44, height: 44).contentShape(.rect)
        }
        .accessibilityLabel("\(exercises[index].name) options")
        .accessibilityIdentifier("exerciseMenu")
    }

    /// Long-press a set: its kind, how hard it was, or delete it.
    @ViewBuilder private func setMenu(_ exercise: Int, _ index: Int) -> some View {
        let set = model.session.exercises[exercise].sets[index], type = set.type ?? .normal
        ForEach([WorkoutSetType.warmup, .drop, .failure], id: \.self) { option in
            Toggle(isOn: Binding(get: { type == option }, set: { on in
                Task { await model.setType(on ? option : .normal, exercise: exercise, set: index) }
            })) { Label(Self.typeName(option) ?? "", systemImage: Self.typeSymbol(option) ?? "") }
        }
        Menu {
            Picker("How hard?", selection: Binding(get: { set.effort }, set: { effort in Task { await model.setEffort(effort, exercise: exercise, set: index) } })) {
                ForEach(1...10, id: \.self) { level in
                    Text(EffortChips.efforts.first { $0.1 == level }.map { "\(level) · \($0.0)" } ?? "\(level)").tag(Int?.some(level))
                }
            }
            .pickerStyle(.inline)
            if set.effort != nil { Button("Clear") { Task { await model.setEffort(nil, exercise: exercise, set: index) } } }
        } label: { Label("How hard?", systemImage: "gauge.with.dots.needle.67percent") }
        Button("Delete", systemImage: "trash", role: .destructive) { Task { await model.deleteSet(exercise: exercise, set: index) } }
    }

    static func typeSymbol(_ type: WorkoutSetType) -> String? {
        switch type {
        case .normal: nil
        case .warmup: "flame"
        case .drop: "arrow.down.right"
        case .failure: "bolt.fill"
        }
    }

    static func typeName(_ type: WorkoutSetType) -> String? {
        switch type {
        case .normal: nil
        case .warmup: String(localized: "Warm-up")
        case .drop: String(localized: "Drop set")
        case .failure: String(localized: "To failure")
        }
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

    nonisolated static func clock(_ seconds: Int) -> String { "\(seconds / 60):" + String(format: "%02d", seconds % 60) }
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the buttons take a second row, so the countdown never wraps.
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))) {
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
            .accessibilityIdentifier("restTime")
            HStack(spacing: 12) {
                Spacer(minLength: 4)
                if adjusting {
                    Button("−15") { Task { await rest.adjust(by: -15) } }.accessibilityLabel("15 seconds less").frame(minWidth: 44, minHeight: 44)
                    Button("+15") { Task { await rest.adjust(by: 15) } }.accessibilityLabel("15 seconds more").frame(minWidth: 44, minHeight: 44)
                }
                Button("Skip") { rest.skip() }.fontWeight(.semibold).frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Skip rest").accessibilityIdentifier("skipRest")
            }
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
