import SwiftUI

struct DiarySummaryCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.diarySurface)
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
            Label("Log meal", systemImage: "plus.circle.fill").font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .tint(.diaryAccent).foregroundStyle(Color.diaryActionText)
        .accessibilityIdentifier("logMeal")
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

struct MealRow: View {
    let meal: MealReadModel
    var prominent = false
    var model: DiaryViewModel? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    private var title: String {
        let text = meal.submissions.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return meal.items.first.map { $0.provenance == .sample ? "Apple (sample)" : $0.name } ?? (text.isEmpty ? "Meal" : text)
    }
    private var statusText: Text {
        let time = meal.timePrecision == .dateOnly ? Text("Time unspecified") : Text(meal.eatenAt, style: .time)
        if let provenance = meal.items.first?.provenance {
            let label = provenance == .estimate ? "Estimated" : provenance == .sample ? "Sample estimate" : provenance.description
            return Text("\(Text(meal.state.title)) · \(time) · \(label)")
        }
        return Text("\(Text(meal.state.title)) · \(time)")
    }
    @ViewBuilder private var calories: some View {
        if meal.isSaved {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(meal.totals.kcal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—").font(.body.weight(.semibold)).monospacedDigit()
                Text("kcal").font(.caption).foregroundStyle(Color.diarySecondary)
            }.fixedSize(horizontal: true, vertical: false)
        }
    }
    var body: some View {
        HStack(spacing: 12) {
            if let reference = meal.photos.first, let model {
                DiaryPhotoPreview(model: model, reference: reference, height: prominent ? 72 : 40)
                    .frame(width: prominent ? 72 : 40).accessibilityHidden(true)
            } else { Image(systemName: "fork.knife").font(.body).foregroundStyle(Color.diaryCarbs).frame(width: 24).accessibilityHidden(true) }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                    statusText.font(.subheadline).foregroundStyle(meal.state.color)
                    calories
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(prominent ? .subheadline.weight(.semibold) : .body).lineLimit(2)
                    statusText.font(.caption).foregroundStyle(meal.state.color)
                }
                Spacer(minLength: 8)
                if !prominent { calories }
            }
        }
        .frame(minHeight: typeSize.isAccessibilitySize ? 72 : 56)
        .accessibilityElement(children: .combine)
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
