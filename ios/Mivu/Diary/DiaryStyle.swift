import SwiftUI

extension Color {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let diaryCanvas = adaptive(0xFFF8EF, 0x1D211E)
    static let diarySurface = adaptive(0xFFFDFA, 0x292D29)
    static let diaryText = adaptive(0x2B231F, 0xFFF8EF)
    static let diarySecondary = adaptive(0x78675B, 0xCABBAB)
    static let diaryAccent = adaptive(0xBB432B, 0xFFA988)
    static let diaryActionText = adaptive(0xFFFFFF, 0x261C18)
    static let diaryLeaf = adaptive(0x4C695B, 0xADCDB9)
}

struct SampleBanner: View {
    var body: some View {
        DisclosureGroup {
            Text("Every capture gets a synthetic apple estimate. Photos and text are saved, but no food recognition runs.")
                .font(.subheadline).foregroundStyle(Color.diarySecondary).padding(.top, 8)
        } label: {
            Label("Apple sample mode", systemImage: "leaf").font(.subheadline.weight(.semibold))
        }
        .tint(.diaryLeaf).foregroundStyle(Color.diaryLeaf)
        .frame(minHeight: 44).padding(.horizontal, 16).padding(.vertical, 4)
        .background(Color.diaryLeaf.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recorded totals").font(.subheadline.weight(.medium)).foregroundStyle(Color.diarySecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(totals.kcal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                    .contentTransition(.numericText()).animation(reduceMotion ? nil : .snappy(duration: 0.25), value: totals.kcal)
                Text("kcal").foregroundStyle(Color.diarySecondary)
            }
            HStack {
                metric("Carbs", totals.carbs)
                Spacer(minLength: 8)
                metric("Protein", totals.protein)
                Spacer(minLength: 8)
                metric("Fat", totals.fat)
            }
            if totals.unknownItemCount > 0 {
                Text("Some nutrients are unknown. Recorded totals may be incomplete.").font(.caption).foregroundStyle(Color.diarySecondary)
            }
        }.accessibilityElement(children: .combine)
    }
    private func metric(_ label: LocalizedStringKey, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Color.diarySecondary)
            Text(value.map { $0.formatted(.number.precision(.fractionLength(1))) + " g" } ?? "—").font(.body.weight(.medium))
        }
    }
}

extension SubmissionState {
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
    let meal: DiaryMeal
    private var title: String {
        let text = meal.submissions.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return meal.items.first.map { $0.provenance == .sample ? "Apple (sample)" : $0.name } ?? (text.isEmpty ? "Meal" : text)
    }
    var body: some View {
        HStack(spacing: 12) {
            if let data = meal.photos.first?.data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityHidden(true)
            } else { Image(systemName: "fork.knife").frame(width: 52, height: 52).background(.quaternary, in: RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).lineLimit(2)
                HStack { Text(meal.state.title); Text(meal.eatenAt, style: .time) }.font(.caption).foregroundStyle(Color.diarySecondary)
            }
            Spacer(minLength: 4)
            if meal.isSaved { Text(meal.totals.kcal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—").font(.headline) }
        }.frame(minHeight: 68)
    }
}
