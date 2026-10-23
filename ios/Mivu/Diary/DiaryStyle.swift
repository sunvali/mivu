import SwiftUI

struct DiarySummaryCardStyle: ViewModifier {
    var fill: Color = .diarySurface
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(fill)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 10, x: 0, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.diaryRule.opacity(contrast == .increased ? 1 : 0.35), lineWidth: contrast == .increased ? 1 : 0.5)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func diarySummaryCard() -> some View {
        modifier(DiarySummaryCardStyle())
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

struct SampleBanner: View {
    var body: some View {
        DisclosureGroup {
            Text("Every capture gets a synthetic apple estimate. Photos and text are saved, but no food recognition runs.")
                .font(.subheadline).foregroundStyle(Color.diarySecondary).padding(.top, 8)
        } label: {
            Label("Apple sample mode", systemImage: "leaf").font(.subheadline.weight(.semibold))
        }
        .tint(.diaryAccent).foregroundStyle(Color.diaryText)
        .frame(minHeight: 44).padding(.horizontal, 12).padding(.vertical, 4)
    }
}

struct DiaryCaptureAction: View {
    var title: LocalizedStringKey = "Log with Pip"
    var systemImage = "sparkles"
    var identifier = "logMeal"
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.glassProminent)
        }
    }
    private var button: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .tint(.diaryAccent).foregroundStyle(Color.diaryActionText)
        .accessibilityIdentifier(identifier)
    }
}

/// The secondary entry beside the Pip action: typing nutrition in by hand.
struct DiaryManualAction: View {
    let identifier: String
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            button.buttonStyle(.bordered)
        } else {
            button.buttonStyle(.glass)
        }
    }
    private var button: some View {
        Button(action: action) {
            Label("Add manually", systemImage: "number").font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .tint(.diaryAccent)
        .accessibilityIdentifier(identifier)
    }
}

struct NutritionSummary: View {
    let totals: NutritionTotals
    let title: LocalizedStringKey
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var energySize = 48.0

    init(totals: NutritionTotals, title: LocalizedStringKey = "Recorded intake") {
        self.totals = totals
        self.title = title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Color.diarySecondary)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    energyValue
                    Text("kcal").font(.body).foregroundStyle(Color.diarySecondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    energyValue
                    Text("kcal").font(.title3.weight(.medium)).foregroundStyle(Color.diarySecondary)
                }
            }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    metric("Protein", totals.protein, color: .diaryProtein)
                    metric("Carbs", totals.carbs, color: .diaryCarbs)
                    metric("Fat", totals.fat, color: .diaryFat)
                }
            } else {
                HStack(spacing: 0) {
                    metric("Protein", totals.protein, color: .diaryProtein).frame(maxWidth: .infinity, alignment: .leading)
                    separator
                    metric("Carbs", totals.carbs, color: .diaryCarbs).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
                    separator
                    metric("Fat", totals.fat, color: .diaryFat).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
                }
            }
            if totals.unknownItemCount > 0 {
                Text("Some nutrients are unknown. Recorded totals may be incomplete.").font(.caption).foregroundStyle(Color.diarySecondary)
            }
        }
    }
    private var energyValue: some View {
        Text(totals.kcal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
            .font(.system(size: energySize, weight: .semibold, design: .default)).monospacedDigit().foregroundStyle(Color.diaryEnergy)
            .contentTransition(.numericText()).animation(reduceMotion ? nil : .snappy(duration: MivuMotion.numeric), value: totals.kcal)
            .accessibilityIdentifier("nutritionEnergy")
    }
    private var separator: some View {
        Rectangle().fill(Color.diaryRule).frame(width: 1, height: 36).padding(.horizontal, 10).accessibilityHidden(true)
    }
    private func metric(_ label: LocalizedStringKey, _ value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(color).frame(width: 24, height: 3).accessibilityHidden(true)
            Text(label).font(.caption).foregroundStyle(color)
            Text(value.map { $0.formatted(.number.precision(.fractionLength(1))) + " g" } ?? "—").font(.body.weight(.medium)).monospacedDigit().foregroundStyle(color)
        }
    }
}

struct DiarySectionLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color
    var body: some View {
        Label { Text(title).foregroundStyle(Color.diaryText) } icon: {
            Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
        }.font(.headline).textCase(nil)
    }
}

extension SubmissionState {
    var color: Color {
        switch self {
        case .saved: .diarySuccess
        case .needsRetry: .diaryError
        case .captured, .waitingForConnection, .awaitingReview: .diaryWarning
        case .analyzing: .diaryAccent
        case .cancelled: .diarySecondary
        }
    }
    var title: LocalizedStringKey {
        switch self {
        case .captured: "Captured"
        case .waitingForConnection: "Waiting for connection"
        case .analyzing: "Analyzing"
        case .awaitingReview: "Awaiting review"
        case .saved: "Saved"
        case .needsRetry: "Needs retry"
        case .cancelled: "Cancelled"
        }
    }
}

extension DayCompleteness {
    var title: LocalizedStringKey {
        switch self {
        case .unknown: "Unknown"
        case .complete: "Complete"
        case .partial: "Partial"
        case .untracked: "Untracked"
        }
    }
}

struct MealThumbnail: View {
    let meal: MealReadModel
    var model: DiaryViewModel? = nil
    let size: CGFloat
    var body: some View {
        if let reference = meal.photos.first, let model {
            DiaryPhotoPreview(model: model, reference: reference, height: size).frame(width: size)
        } else {
            RoundedRectangle(cornerRadius: 14).fill(Color.diarySummarySurface).frame(width: size, height: size)
                .overlay { Image(systemName: "fork.knife").font(.title3).foregroundStyle(Color.diaryAccent) }
        }
    }
}

struct MealRow: View {
    let meal: MealReadModel
    var prominent = false
    var model: DiaryViewModel? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var thumbnail = 56.0
    private var title: String {
        let text = meal.submissions.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return meal.items.first.map { $0.provenance == .sample ? "Apple (sample)" : $0.name } ?? (text.isEmpty ? "Meal" : text)
    }
    private var needsReview: Bool { meal.state == .awaitingReview }
    private var statusText: Text {
        let time = meal.timePrecision == .dateOnly ? Text("Time unspecified") : Text(meal.eatenAt, style: .time)
        let estimated = meal.items.first?.provenance == .estimate ? Text(" · Estimated") : Text("")
        return meal.state == .saved ? Text("\(time)\(estimated)") : Text("\(Text(meal.state.title)) · \(time)")
    }
    @ViewBuilder private var calories: some View {
        if meal.isSaved {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(meal.totals.kcal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—").font(.headline).monospacedDigit()
                Text("kcal").font(.caption).foregroundStyle(Color.diarySecondary)
            }.fixedSize(horizontal: true, vertical: false)
        }
    }
    private var image: some View { MealThumbnail(meal: meal, model: model, size: thumbnail) }
    private var text: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Color.diaryText).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                if needsReview { Circle().fill(Color.diaryWarning).frame(width: 8, height: 8).accessibilityHidden(true) }
            }
            statusText.font(.subheadline).foregroundStyle(meal.state == .saved ? Color.diarySecondary : meal.state.color)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if typeSize.isAccessibilitySize {
                image.accessibilityHidden(true)
                text
                calories
            } else {
                HStack(spacing: 12) {
                    image.accessibilityHidden(true)
                    text.frame(maxWidth: .infinity, alignment: .leading)
                    calories
                }
            }
            MacroBar(totals: meal.totals).padding(.leading, typeSize.isAccessibilitySize ? 0 : thumbnail + 12)
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
        .accessibilityValue(needsReview ? Text("Needs review") : Text(""))
    }
}

/// Protein, carbs and fat as shares of one thin bar; hidden when every macro is unknown.
struct MacroBar: View {
    let totals: NutritionTotals
    var body: some View {
        let parts: [(Double, Color)] = [(totals.protein ?? 0, .diaryProtein), (totals.carbs ?? 0, .diaryCarbs), (totals.fat ?? 0, .diaryFat)]
        let sum = parts.reduce(0) { $0 + $1.0 }
        if sum > 0 {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(parts.indices, id: \.self) { index in
                        if parts[index].0 > 0 {
                            Capsule().fill(parts[index].1).frame(width: max(4, (proxy.size.width - 4) * parts[index].0 / sum))
                        }
                    }
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
    }
}

extension NutritionProvenance {
    var description: String {
        switch self {
        case .sample: "Synthetic apple estimate"
        case .user: "Edited by you"
        case .confirmedLabel: "Confirmed label values"
        case .identifiedSource: "Retrieved nutrition source"
        case .estimate: "Estimated nutrition"
        }
    }
}

extension FoodItem {
    /// "Estimated nutrition · ChatGPT": the provenance plus the Coach model that produced it, unless the person edited it.
    var sourceCaption: String {
        [provenance.description, provenance == .user ? nil : estimatedByLabel].compactMap { $0 }.joined(separator: " · ")
    }
}
