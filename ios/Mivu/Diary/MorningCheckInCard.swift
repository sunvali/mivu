import SwiftUI

/// Shown after a new waking day starts: the last day's recap and an optional weigh-in.
/// Nothing here blocks logging; the first meal of the day hides it.
struct MorningCheckInCard: View {
    @Bindable var model: DiaryViewModel
    let day: TrackingDay
    let previous: DiaryDaySummary
    let previousTarget: Double?
    let todayWeight: WeightEntry?
    /// Coach shows only what is still asked, with the option to answer in a message instead.
    var compact = false
    var onTellCoach: (() -> Void)? = nil
    var onDismiss: () -> Void
    @AppStorage("weightUnit") private var unit = "kg"
    @AppStorage("morningWeightSkippedDay") private var skippedDay = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var weight = ""
    @State private var lastKg: Double?
    @State private var trendKg: Double?
    @State private var saving = false
    @FocusState private var weightFocused: Bool

    private var showsRecap: Bool { previous.mealCount > 0 }
    private var askingWeight: Bool { todayWeight == nil && skippedDay != day.id.uuidString }
    private var enteredKg: Double? {
        guard let value = ProgressDate.number(weight), value > 0 else { return nil }
        let kg = unit == "lb" ? value * 0.45359237 : value
        return (20...400).contains(kg) ? kg : nil
    }

    var body: some View {
        if !compact { card }
        else if askingWeight { compactCard }
    }

    /// Coach: a short weigh-in bubble above Pip, so the conversation stays visible.
    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(greeting). Weighed in yet?")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.diaryText)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("morningCheckIn")
                Spacer(minLength: 4)
                dismissButton
            }
            HStack(spacing: 8) {
                weightField.padding(.horizontal, 12).background(Capsule().fill(Color.diaryCanvas))
                saveButton.fixedSize()
            }
            HStack {
                if let onTellCoach {
                    Button("Tell Coach instead", action: onTellCoach).accessibilityIdentifier("morningTellCoach")
                }
                Spacer()
                skipButton
            }.font(.subheadline).foregroundStyle(Color.diaryAccent)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.diarySurface).shadow(color: .black.opacity(0.06), radius: 8, y: 3))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(greeting).font(.title3.weight(.bold)).foregroundStyle(Color.diaryText).accessibilityAddTraits(.isHeader).accessibilityIdentifier("morningCheckIn")
                Spacer()
                dismissButton
            }
            if showsRecap { recap }
            if askingWeight { weightEntry }
            else if let todayWeight { weightResult(todayWeight) }
            if !askingWeight {
                Label("You're set for today", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Color.diarySuccess)
            }
        }
        .diarySummaryCard()
        .animation(reduceMotion ? nil : .snappy, value: askingWeight)
        .sensoryFeedback(.success, trigger: todayWeight?.id)
        .task(id: todayWeight?.revision) { await loadWeights() }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var recap: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(wakingDayTitle(previous.day.localDate, relativeTo: day.localDate))
                .font(.subheadline).foregroundStyle(Color.diarySecondary)
            let kcal = previous.totals.kcal ?? 0
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(kcal.formatted(.number.precision(.fractionLength(0))))
                    .font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(Color.diaryText)
                Text(previousTarget.map { "of \($0.formatted(.number.precision(.fractionLength(0)))) kcal" } ?? "kcal")
                    .font(.subheadline).foregroundStyle(Color.diarySecondary)
            }
            if let target = previousTarget, target > 0 {
                ProgressView(value: min(kcal / target, 1)).tint(Color.diaryEnergy)
                    .accessibilityLabel("Intake toward that day's goal")
            }
        }
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(Color.diarySecondary)
                .frame(width: 30, height: 30).background(Circle().fill(Color.diaryCanvas))
                .frame(width: 44, height: 44)
        }.buttonStyle(.plain).accessibilityLabel("Hide check-in").accessibilityIdentifier("morningDismiss")
    }
    private var weightField: some View {
        HStack(spacing: 8) {
            TextField(lastKg.map { display($0) } ?? "Weight", text: $weight)
                .keyboardType(.decimalPad).focused($weightFocused)
                .font((compact ? Font.body : .title2).weight(.semibold)).monospacedDigit()
                .accessibilityLabel("Weight in \(unit == "lb" ? "pounds" : "kilograms")").accessibilityIdentifier("morningWeight")
            Menu {
                Picker("Unit", selection: $unit) { Text("kg").tag("kg"); Text("lb").tag("lb") }
            } label: {
                HStack(spacing: 4) { Text(unit); Image(systemName: "chevron.up.chevron.down").font(.caption2) }
                    .font(.subheadline.weight(.medium)).foregroundStyle(Color.diaryAccent).frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Unit, \(unit)")
        }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { weightFocused = false } } }
    }
    private var skipButton: some View {
        Button { weightFocused = false; skippedDay = day.id.uuidString } label: {
            Text("Skip").font(.subheadline.weight(.semibold)).frame(maxWidth: compact ? nil : .infinity, minHeight: 44)
        }.accessibilityIdentifier("morningWeightSkip")
    }
    private var saveButton: some View {
        Button { Task { await save() } } label: {
            Group { if saving { ProgressView() } else { Text("Save") } }
                .font(.subheadline.weight(.semibold)).frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 36 : 44)
                .padding(.horizontal, compact ? 8 : 0)
        }.buttonStyle(.borderedProminent).tint(Color.diaryAccent).buttonBorderShape(.capsule)
            .disabled(enteredKg == nil || saving).accessibilityIdentifier("morningWeightSave")
    }

    private var weightEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { Text("Morning weight") } icon: { Image(systemName: "scalemass").foregroundStyle(Color.diaryWeight) }
                .font(.subheadline.weight(.medium)).foregroundStyle(Color.diaryText)
            weightField.padding(.horizontal, 14).background(RoundedRectangle(cornerRadius: 14).fill(Color.diaryCanvas))
            HStack(spacing: 10) {
                skipButton.buttonStyle(.bordered).tint(Color.diarySecondary)
                saveButton
            }
        }
    }

    private func weightResult(_ entry: WeightEntry) -> some View {
        HStack {
            Label { Text("\(display(entry.unit == "lb" ? entry.value * 0.45359237 : entry.value)) \(unit)").monospacedDigit() }
                icon: { Image(systemName: "scalemass").foregroundStyle(Color.diaryWeight) }
                .font(.subheadline.weight(.medium)).foregroundStyle(Color.diaryText)
            Spacer()
            if let trendKg {
                // The weekly trend, not the day-to-day change: daily swings are mostly water.
                Text("\(trendKg > 0 ? "+" : trendKg < 0 ? "−" : "")\(display(abs(trendKg))) \(unit) this week")
                    .font(.subheadline).monospacedDigit().foregroundStyle(Color.diarySecondary)
            }
        }.frame(minHeight: 44).accessibilityElement(children: .combine)
    }

    /// Kilograms shown in the chosen unit, one decimal.
    private func display(_ kg: Double) -> String {
        (unit == "lb" ? kg / 0.45359237 : kg).formatted(.number.precision(.fractionLength(1)))
    }

    private func save() async {
        guard let kg = enteredKg else { return }
        saving = true; defer { saving = false }
        weightFocused = false
        if await model.saveMorningWeight(kg: kg) { weight = "" }
    }

    private func loadWeights() async {
        guard let owner = model.readModel?.profile.id,
              let progress = try? await model.store.progressForDisplay(endingOn: day.localDate, days: 7, expectedProfileID: owner) else { return }
        trendKg = progress.weight.changeFromSevenDaysAgoKg
        lastKg = progress.latestWeight.map { $0.record.unit == "lb" ? $0.record.value * 0.45359237 : $0.record.value }
    }
}

/// "Yesterday" for the day before `reference`, otherwise a short weekday and date.
func wakingDayTitle(_ localDate: String, relativeTo reference: String? = nil) -> String {
    let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = .gmt
    guard let date = formatter.date(from: localDate) else { return localDate }
    if let reference, let next = formatter.date(from: reference), next.timeIntervalSince(date) == 86_400 { return "Yesterday" }
    return date.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).month(.abbreviated).day())
}
