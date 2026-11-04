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

    var title: String { WorkoutCatalog.activity(activity)?.name ?? activity }

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
    let onClose: () -> Void
    @State private var bodyKg: Double?
    @State private var startEdited = false
    @State private var saving = false
    @State private var typingKcal = false
    @State private var typedKcal: Double?
    @Environment(\.dynamicTypeSize) private var typeSize
    private let unit = Locale.current.measurementSystem == .metric ? "km" : "mi"
    private static let efforts: [(String, Int)] = [("Easy", 3), ("Moderate", 5), ("Hard", 7), ("Max", 9)]

    private var zone: String { model.readModel?.profile.timeZoneID ?? TimeZone.current.identifier }
    private var sport: WorkoutActivity? { WorkoutCatalog.activity(state.activity) }
    private var kcal: Double? { state.draft(bodyKg: bodyKg).estimatedBurnKcal }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                WorkoutRuler(value: $state.minutes, range: 1...600, step: 1, majorEvery: 5, unit: "min",
                             format: { $0.formatted(.number.precision(.fractionLength(0))) }, label: "Time")
                    .accessibilityIdentifier("timeRuler").card()
                if state.km != nil { distance.card() }
                effort.card()
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
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onClose).disabled(saving) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.fontWeight(.semibold).disabled(saving).accessibilityIdentifier("saveCardio")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
        .sensoryFeedback(.selection, trigger: state.effort)
        .task(id: diaryDateLabel(state.startedAt, zone: zone)) {
            guard let owner = model.readModel?.profile.id else { return }
            bodyKg = try? await model.store.bodyKg(on: diaryDateLabel(state.startedAt, zone: zone), expectedProfileID: owner)
        }
        .alert("Calories burned", isPresented: $typingKcal) {
            TextField("kcal", value: $typedKcal, format: .number).keyboardType(.numberPad)
            Button("Save") { state.typedKcal = typedKcal.flatMap { (0...100_000).contains($0) ? $0.rounded() : nil } }
            if state.typedKcal != nil { Button("Use estimate") { state.typedKcal = nil } }
            Button("Cancel", role: .cancel) {}
        }
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

    private var effort: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How hard?").font(.headline)
            let chips = ForEach(Self.efforts, id: \.1) { name, value in
                let selected = state.effort == value
                Button { state.effort = value } label: {
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

    private var summary: some View {
        HStack {
            if let pace = state.pace(unit: unit) { Text(pace).monospacedDigit() }
            Spacer(minLength: 12)
            Button { typedKcal = state.typedKcal ?? kcal; typingKcal = true } label: {
                Text(state.typedKcal.map { "\($0.formatted()) kcal" } ?? kcal.map { "~\($0.formatted()) kcal" } ?? "Add weight for kcal")
                    .monospacedDigit().frame(minHeight: 44).contentShape(.rect)
            }
            .tint(Color.diaryWorkout)
            .accessibilityIdentifier("cardioKcal")
        }
        .font(.subheadline).foregroundStyle(Color.diarySecondary)
        .padding(.horizontal, 8)
    }

    private var more: some View {
        DisclosureGroup("More") {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("Start", selection: Binding(get: { state.startedAt }, set: { state.startedAt = $0; startEdited = true }), in: ...Date())
                    .frame(minHeight: 44)
                if sport?.indoorOutdoor == true {
                    Picker("Where", selection: $state.indoor) {
                        Text("Outdoor").tag(Bool?.some(false))
                        Text("Indoor").tag(Bool?.some(true))
                    }
                    .pickerStyle(.segmented).frame(minHeight: 44)
                }
                LabeledContent("Avg heart rate") {
                    TextField("bpm", value: $state.avgHeartRate, format: .number).keyboardType(.numberPad)
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
        if !startEdited { log.startedAt = Date().addingTimeInterval(-log.minutes * 60) }
        if let rate = log.avgHeartRate, !(20...250).contains(rate) { log.avgHeartRate = nil }
        let draft = log.draft(bodyKg: bodyKg), activeDate = model.activeDay?.localDate
        saving = true
        let saved = await model.change {
            // With no open day, logging opens one so the workout shows on Today, as a weigh-in does.
            let date: String
            if startEdited { date = diaryDateLabel(log.startedAt, zone: zone) }
            else if let activeDate { date = activeDate }
            else { date = try await model.store.startDay(expectedProfileID: owner).localDate }
            _ = try await model.store.createWorkout(localDate: date, draft: draft,
                performedAt: diaryDateLabel(log.startedAt, zone: zone) == date ? log.startedAt : nil, expectedProfileID: owner)
        }
        saving = false
        if saved { onClose() }
    }
}

private extension View {
    func card() -> some View { modifier(DiarySummaryCardStyle(padding: 16)) }
}
