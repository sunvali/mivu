import SwiftUI

/// What the cardio screen edits; `km` is nil for sports without a distance.
struct CardioLogState: Hashable {
    var activity: String
    var minutes: Double
    var km: Double?
    var effort: Int
    var startedAt: Date
    var avgHeartRate: Int?
    var indoor: Bool?
    var note: String
    var typedKcal: Double?
    /// Set when the person picked the start; otherwise the workout ends when it is saved.
    var startEdited = false

    private static let typicalKm: [String: Double] = ["walk": 3, "cycle": 15, "swim": 1, "hike": 8, "cross-country-skiing": 10]

    /// Starts from the last workout of this activity, else 30 minutes and a typical distance, ending now.
    init(activity: String, last: WorkoutSession?, now: Date) {
        let sport = WorkoutCatalog.activity(activity)
        self.activity = activity
        minutes = last.map { Double($0.durationSeconds ?? $0.durationMinutes * 60) / 60 }.map { $0.rounded() } ?? 30
        km = sport?.hasDistance == true ? (last?.distanceMeters).map { $0 / 1000 } ?? Self.typicalKm[activity] ?? 5 : nil
        effort = last?.effort ?? 5
        startedAt = now.addingTimeInterval(-minutes * 60)
        indoor = sport?.indoorOutdoor == true ? last?.indoor : nil
        note = ""
    }

    /// Editing a saved workout: its own numbers and start.
    init(editing session: WorkoutSession) {
        self.init(activity: session.activity ?? "other", last: session, now: session.performedAt)
        startedAt = session.performedAt; startEdited = true
        avgHeartRate = session.avgHeartRate; note = session.note ?? ""
        typedKcal = session.burnSource == .userEstimate ? session.estimatedBurnKcal : nil
    }

    /// The saved workout with these numbers; it keeps its title and origin, and an estimate it cannot redo keeps its number.
    func edited(_ session: WorkoutSession, bodyKg: Double?) -> WorkoutSession {
        var draft = draft(bodyKg: bodyKg)
        draft.title = nil; draft.source = nil
        if draft.estimatedBurnKcal == nil { draft.estimatedBurnKcal = session.estimatedBurnKcal }
        var edited = session
        edited.apply(draft)
        if startedAt != session.performedAt { edited.performedAt = startedAt; edited.timePrecision = .exact }
        return edited
    }

    var title: String { WorkoutCatalog.activity(activity)?.name ?? activity }

    /// The diary day the start counts on: after midnight, before the cutoff, it is still the previous waking day, as for meals and gym.
    func day(zone: String) -> String { wakingDateLabel(startedAt, zone: zone) }

    /// "5:36 /km" for foot sports, "2:00 /100 m" for swimming, else speed such as "20 km/h". `unit` is "km" or "mi".
    func pace(unit: String) -> String? {
        guard let km, km > 0, minutes > 0 else { return nil }
        let seconds = minutes * 60, distance = unit == "mi" ? km / 1.609344 : km
        func clock(_ value: Double) -> String { let total = Int(value.rounded()); return "\(total / 60):" + String(format: "%02d", total % 60) }
        switch activity {
        case "swim": return clock(seconds / (km * 10)) + " /100 m"
        case "run", "walk", "hike": return clock(seconds / distance) + " /\(unit)"
        default: return (distance / (seconds / 3600)).formatted(.number.precision(.fractionLength(0...1))) + (unit == "mi" ? " mph" : " km/h")
        }
    }

    func draft(bodyKg: Double?) -> WorkoutDraft {
        let seconds = max(1, Int((minutes * 60).rounded()))
        let meters = km.flatMap { $0 > 0 ? $0 * 1000 : nil }
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkoutDraft(kind: .cardio, durationMinutes: max(1, Int(minutes.rounded())), exercises: [],
            estimatedBurnKcal: typedKcal ?? WorkoutBurn.estimate(activity: activity, seconds: seconds, distanceMeters: meters, effort: effort, bodyKg: bodyKg),
            burnSource: typedKcal == nil ? nil : .userEstimate, title: title, activity: activity, state: .finished,
            durationSeconds: seconds, distanceMeters: meters, avgHeartRate: avgHeartRate, effort: effort, indoor: indoor,
            note: note.isEmpty ? nil : note, source: .manual)
    }
}

/// Cardio and sports in two moves: set the numbers on the rulers, then Save.
struct CardioLogView: View {
    @Bindable var model: DiaryViewModel
    @State var state: CardioLogState
    /// The saved workout being edited; Save then updates it instead of logging a new one.
    var editing: WorkoutSession?
    let onClose: () -> Void
    private let initial: CardioLogState
    @State private var bodyKg: Double?
    @State private var saving = false
    @State private var typingKcal = false
    @State private var kcalText = ""
    @State private var addingWeight = false
    @State private var confirmingDiscard = false
    private let unit = Locale.current.measurementSystem == .metric ? "km" : "mi"

    private var zone: String { model.readModel?.profile.timeZoneID ?? TimeZone.current.identifier }
    private var sport: WorkoutActivity? { WorkoutCatalog.activity(state.activity) }
    private var kcal: Double? { state.draft(bodyKg: bodyKg).estimatedBurnKcal }
    private var changed: Bool { state != initial }
    /// The day Save files the log on, so the estimate reads that day's body weight: an edited start's waking day, else the open day.
    private var logDay: String { state.startEdited ? state.day(zone: zone) : model.activeDay?.localDate ?? state.day(zone: zone) }

    init(model: DiaryViewModel, state: CardioLogState, editing: WorkoutSession? = nil, onClose: @escaping () -> Void) {
        self.model = model; _state = State(initialValue: state); initial = state; self.editing = editing; self.onClose = onClose
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                WorkoutRuler(value: $state.minutes, range: 1...600, step: 1, majorEvery: 5, unit: "min",
                             format: { $0.formatted(.number.precision(.fractionLength(0))) }, label: "Time")
                    .accessibilityIdentifier("timeRuler").card()
                if state.km != nil { distance.card() }
                EffortChips(title: "How hard?", effort: Binding(get: { state.effort }, set: { state.effort = $0 ?? state.effort })).card()
                summary
                more.card()
                if let message = model.errorMessage {
                    Label(LocalizedStringKey(message), systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Color.diaryError)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.diaryCanvas)
        .navigationTitle(state.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if changed { confirmingDiscard = true } else { onClose() } }.disabled(saving)
                    .accessibilityIdentifier("cancelCardio")
                    .alert("Discard changes to this workout?", isPresented: $confirmingDiscard) {
                        Button("Discard changes", role: .destructive, action: onClose)
                        Button("Keep editing", role: .cancel) {}
                    }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.fontWeight(.semibold).disabled(saving).accessibilityIdentifier("saveCardio")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
        .interactiveDismissDisabled(changed || saving)
        .sensoryFeedback(.selection, trigger: state.effort)
        // Reloads after a weigh-in is saved from here, so the estimate appears.
        .task(id: "\(logDay)\(model.changeGeneration)") {
            guard let owner = model.readModel?.profile.id else { return }
            bodyKg = try? await model.store.bodyKg(on: logDay, expectedProfileID: owner)
        }
        .alert("Calories burned", isPresented: $typingKcal) {
            TextField("kcal", text: $kcalText).keyboardType(.numberPad)
            Button("Save") { state.typedKcal = Double(kcalText).flatMap { (0...100_000).contains($0) ? $0.rounded() : nil } }
            if state.typedKcal != nil { Button("Use estimate") { state.typedKcal = nil } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $addingWeight) { MorningWeightEditorView(model: model) }
    }

    /// Distance in the person's unit; pools in metres.
    private var distance: some View {
        let swim = state.activity == "swim", cycle = state.activity == "cycle"
        let scale = swim ? 1_000 : unit == "mi" ? 1 / 1.609344 : 1
        return WorkoutRuler(value: Binding(get: { (state.km ?? 0) * scale }, set: { state.km = $0 / scale }),
                            range: swim ? 0...10_000 : cycle ? 0...300 : 0...100, step: swim ? 25 : cycle ? 0.5 : 0.1,
                            majorEvery: swim ? 4 : cycle ? 10 : 5, unit: swim ? "m" : unit,
                            format: { $0.formatted(.number.precision(.fractionLength(swim || cycle ? 0...1 : 1...1))) }, label: "Distance")
            .accessibilityIdentifier("distanceRuler")
    }

    private var summary: some View {
        HStack {
            if let pace = state.pace(unit: unit) { Text(pace).monospacedDigit() }
            Spacer(minLength: 12)
            if let shown = state.typedKcal.map({ "\($0.formatted()) kcal" }) ?? kcal.map({ "~\($0.formatted()) kcal" }) {
                Button { kcalText = (state.typedKcal ?? kcal).map { $0.formatted(.number.grouping(.never)) } ?? ""; typingKcal = true } label: {
                    Text(shown).monospacedDigit().foregroundStyle(Color.diaryWorkout).frame(minHeight: 44).contentShape(.rect)
                }
                .accessibilityLabel(shown.replacingOccurrences(of: "~", with: "About "))
                .accessibilityIdentifier("cardioKcal")
            } else {
                // Without a body weight there is no estimate; a weigh-in brings it.
                Button { addingWeight = true } label: {
                    Text("Add weight for kcal").foregroundStyle(Color.diaryAccent).frame(minHeight: 44).contentShape(.rect)
                }
                .accessibilityIdentifier("cardioAddWeight")
            }
        }
        .font(.subheadline).foregroundStyle(Color.diarySecondary)
        .padding(.horizontal, 8)
    }

    private var more: some View {
        DisclosureGroup("More") {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("Start", selection: Binding(get: { state.startedAt }, set: { state.startedAt = $0; state.startEdited = true }), in: ...Date())
                    .frame(minHeight: 44)
                if sport?.indoorOutdoor == true {
                    Picker("Where", selection: $state.indoor) {
                        Text("Outdoor").tag(Bool?.some(false))
                        Text("Indoor").tag(Bool?.some(true))
                    }
                    .pickerStyle(.segmented).frame(minHeight: 44)
                }
                LabeledContent("Avg heart rate") {
                    // Text, not a formatted value: it updates as typed, so Save never misses it.
                    TextField("bpm", text: Binding(get: { state.avgHeartRate.map(String.init) ?? "" },
                                                   set: { state.avgHeartRate = Int($0.filter(\.isNumber).prefix(3)) }))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing).frame(minHeight: 44)
                }
                TextField("Note", text: $state.note, axis: .vertical).lineLimit(1...4).frame(minHeight: 44)
            }
            .padding(.top, 8)
        }
        .tint(Color.diaryText)
    }

    private func save() async {
        guard let owner = model.readModel?.profile.id else { return }
        var log = state
        // Logged right after finishing: it ended now and counts on the day Today shows.
        if !log.startEdited { log.startedAt = Date().addingTimeInterval(-log.minutes * 60) }
        if let rate = log.avgHeartRate, !(20...250).contains(rate) { log.avgHeartRate = nil }
        if let editing {
            let updated = log.edited(editing, bodyKg: bodyKg)
            saving = true
            // A moved start moves the workout to that start's waking day.
            let saved = await model.change {
                _ = try await model.store.updateWorkout(updated, onDate: updated.performedAt != editing.performedAt ? log.day(zone: zone) : nil,
                                                        expectedRevision: editing.revision, expectedProfileID: owner)
            }
            saving = false
            if saved { onClose() }
            return
        }
        let draft = log.draft(bodyKg: bodyKg), activeDate = model.activeDay?.localDate
        saving = true
        var created: WorkoutSession?
        let saved = await model.change {
            // With no open day, logging opens one so the workout shows on Today, as a weigh-in does.
            let date: String
            if log.startEdited { date = log.day(zone: zone) }
            else if let activeDate { date = activeDate }
            else { date = try await model.store.startDay(expectedProfileID: owner).localDate }
            created = try await model.store.createWorkout(localDate: date, draft: draft,
                performedAt: [diaryDateLabel(log.startedAt, zone: zone), log.day(zone: zone)].contains(date) ? log.startedAt : nil, expectedProfileID: owner)
        }
        saving = false
        if saved, let created { model.noteWorkoutSaved(created, owner: owner) }
        if saved { onClose() }
    }
}

/// The four effort chips, shared by the cardio screen's "How hard?" and the Done screen's "How did it feel?".
struct EffortChips: View {
    static let efforts: [(String, Int)] = [("Easy", 3), ("Moderate", 5), ("Hard", 7), ("Max", 9)]
    let title: LocalizedStringKey
    @Binding var effort: Int?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            let chips = ForEach(Self.efforts, id: \.1) { name, value in
                let selected = effort == value
                Button { effort = value } label: {
                    Text(name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selected ? Color.diaryActionText : Color.diaryText)
                        .background(selected ? Color.diaryWorkout : Color.diaryCanvas, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            if typeSize.isAccessibilitySize { VStack(spacing: 8) { chips } } else { HStack(spacing: 8) { chips } }
        }
    }
}

extension View {
    func card() -> some View { modifier(DiarySummaryCardStyle(padding: 16)) }
}
