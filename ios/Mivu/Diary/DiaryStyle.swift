import SwiftUI

extension Color {
    private static func adaptive(_ light: UInt32, _ dark: UInt32, highContrastLight: UInt32? = nil, highContrastDark: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { traits in
            let highContrast = traits.accessibilityContrast == .high
            let value = traits.userInterfaceStyle == .dark
                ? (highContrast ? highContrastDark ?? dark : dark)
                : (highContrast ? highContrastLight ?? light : light)
            return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let diaryCanvas = adaptive(0xF5F8F8, 0x111516)
    static let diarySurface = adaptive(0xFFFFFF, 0x1D2324)
    static let diaryText = adaptive(0x142023, 0xF4F7F6)
    static let diarySecondary = adaptive(0x53646B, 0xB7C4C8, highContrastLight: 0x34474D, highContrastDark: 0xD5E0E3)
    static let diaryAccent = adaptive(0x006D75, 0x63D5CD, highContrastLight: 0x00545C, highContrastDark: 0x9CEDE6)
    static let diaryActionText = adaptive(0xFFFFFF, 0x092126)
    static let diaryProtein = adaptive(0x195DC2, 0x91BCFF, highContrastLight: 0x124994, highContrastDark: 0xBAD5FF)
    static let diaryCarbs = adaptive(0x925000, 0xF4BC62, highContrastLight: 0x713D00, highContrastDark: 0xFFDBA0)
    static let diaryFat = adaptive(0x7740AD, 0xCCA5F8, highContrastLight: 0x5E2E8E, highContrastDark: 0xE2CAFF)
    static let diarySuccess = adaptive(0x237448, 0x80D5A4, highContrastLight: 0x175A34, highContrastDark: 0xB0EBC6)
    static let diaryWarning = diaryCarbs
    static let diaryError = adaptive(0xB33143, 0xFF9BA6, highContrastLight: 0x8C2030, highContrastDark: 0xFFC2C9)
    static let diaryMessage = adaptive(0x007987, 0x006778)
    static let diarySummarySurface = adaptive(0xEAF5F3, 0x142D2D)
    static let diaryChartSurface = adaptive(0xEDF3FC, 0x19283A)
    static let diaryEnergy = diaryAccent
    static let diaryWeight = diaryProtein
    static let diaryWorkout = diaryFat
    static let diaryLeaf = diaryAccent
    static let diaryRule = adaptive(0xD5DFE1, 0x374346, highContrastLight: 0x9BAEB2, highContrastDark: 0x68777B)
}

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
    @ViewBuilder private var image: some View {
        if let reference = meal.photos.first, let model {
            DiaryPhotoPreview(model: model, reference: reference, height: thumbnail).frame(width: thumbnail)
        } else {
            RoundedRectangle(cornerRadius: 14).fill(Color.diarySummarySurface).frame(width: thumbnail, height: thumbnail)
                .overlay { Image(systemName: "fork.knife").font(.title3).foregroundStyle(Color.diaryAccent) }
        }
    }
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
