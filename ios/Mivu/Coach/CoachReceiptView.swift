import SwiftUI

/// Current target availability is independent of the original committed receipt.
enum CoachReceiptTarget: Equatable, Sendable {
    case loading, unavailable, failed
    case meal(MealReadModel, localDate: String)
    case workout(WorkoutSession, localDate: String)
}

struct CoachReceiptPresentation: Equatable {
    let receipt: CoachCommittedReceipt
    let target: CoachReceiptTarget
    var committedDate: String? { receipt.targetLocalDate }
    var committedItems: [String] {
        receipt.items.map { "\($0.name) · \($0.quantity.formatted(.number.grouping(.never))) \($0.unit)" }
    }
    var committedStatus: String {
        switch receipt.submissionState {
        case .saved: "Saved food"
        case .awaitingReview: "Estimate awaiting review"
        default: "Recorded operation"
        }
    }
    var committedNutrition: String? {
        guard !receipt.items.isEmpty else { return nil }
        return committedTotal(\.kcal).map(Self.energy) ?? "Energy unknown"
    }
    var committedMacros: String? {
        guard !receipt.items.isEmpty else { return nil }
        return Self.macros(carbs: committedTotal(\.carbs), protein: committedTotal(\.protein), fat: committedTotal(\.fat))
    }
    private func committedTotal(_ nutrient: KeyPath<NutritionValues, Double?>) -> Double? {
        var total = 0.0
        for item in receipt.items {
            guard let value = item.nutrition?[keyPath: nutrient] else { return nil }
            total += value
        }
        return total
    }
    var nutritionCompleteness: String? {
        guard !receipt.items.isEmpty else { return nil }
        return receipt.items.contains { item in
            guard let values = item.nutrition else { return true }
            return values.kcal == nil || values.carbs == nil || values.protein == nil || values.fat == nil
        } ? "Some nutrients unknown" : nil
    }
    var estimateLabel: String? {
        guard !receipt.items.isEmpty else { return nil }
        if receipt.items.contains(where: { $0.uncertain == true || $0.provenance == .estimate }) { return "Estimated nutrition" }
        if receipt.items.contains(where: { $0.provenance == nil }) { return "Nutrition provenance unknown" }
        return nil
    }
    var currentStatus: String {
        switch target {
        case .loading: return "Loading current record"
        case .unavailable: return "Record unavailable"
        case .failed: return "Could not load current record"
        case .meal(let meal, _):
            if meal.state == .awaitingReview { return "Needs review" }
            if meal.state == .needsRetry { return "Analysis needs retry" }
            return meal.isSaved ? "Current saved meal" : "Captured on this iPhone"
        case .workout: return "Current workout"
        }
    }
    var currentDate: String? {
        switch target { case .meal(_, let date), .workout(_, let date): date; default: nil }
    }
    var currentNutrition: String? {
        switch target {
        case .meal(let meal, _): meal.totals.kcal.map(Self.energy) ?? "Energy unknown"
        default: nil
        }
    }
    var currentMacros: String? {
        guard case .meal(let meal, _) = target else { return nil }
        let totals = meal.totals
        return Self.macros(carbs: totals.carbs, protein: totals.protein, fat: totals.fat)
    }
    var targetNotice: String? {
        switch target {
        case .loading, .unavailable, .failed: return currentStatus
        case .meal(let meal, _):
            if meal.state == .awaitingReview && receipt.submissionState == .awaitingReview { return nil }
            if meal.state == .needsRetry || !meal.isSaved { return currentStatus }
            if meal.state == .awaitingReview && receipt.submissionState != .awaitingReview { return currentStatus }
            return nil
        case .workout: return nil
        }
    }
    var changeNotice: String? {
        let moved = committedDate != nil && currentDate != nil && committedDate != currentDate
        var edited = false
        var stateChanged = false
        if case .meal(let meal, _) = target {
            stateChanged = receipt.submissionState.map { $0 != meal.state } ?? false
            if !receipt.items.isEmpty {
                let current = meal.state == .awaitingReview ? meal.submissions.last?.proposal?.items ?? meal.items : meal.items
                edited = receipt.itemID == nil && receipt.items.count != current.count
                edited = edited || receipt.items.contains { original in
                    guard let item = current.first(where: { $0.id == original.itemID }) else { return true }
                    return original.name != item.name || original.quantity != item.quantity || original.unit != item.unit
                        || original.nutrition.map { $0 != item.nutrition } == true
                        || original.provenance.map { $0 != item.provenance } == true
                        || original.uncertain.map { $0 != item.uncertain } == true
                }
            }
        }
        if moved, let date = currentDate { return (edited ? "Edited · moved to " : "Moved to ") + date }
        if edited { return "Edited since this receipt" }
        return stateChanged ? "Status changed since this receipt" : nil
    }
    private static func macros(carbs: Double?, protein: Double?, fat: Double?) -> String {
        func grams(_ value: Double?) -> String {
            value.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " g" } ?? "unknown"
        }
        return "Carbs " + grams(carbs) + " · Protein " + grams(protein) + " · Fat " + grams(fat)
    }
    var canOpenTarget: Bool {
        switch target { case .meal, .workout: true; default: false }
    }
    private static func energy(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) + " kcal" }
}

struct CoachReceiptView: View {
    let receipt: CoachCommittedReceipt
    let target: CoachReceiptTarget
    let open: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var presentation: CoachReceiptPresentation { CoachReceiptPresentation(receipt: receipt, target: target) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) { receiptStatus; reviewButton }
            } else {
                HStack(spacing: 12) { receiptStatus; Spacer(minLength: 0); reviewButton }
            }
            ForEach(Array(presentation.committedItems.enumerated()), id: \.offset) { _, item in
                Text(item).accessibilityIdentifier("coachReceiptQuantity")
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { committedDate; committedEnergy }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { committedDate; committedEnergy }
                    VStack(alignment: .leading, spacing: 4) { committedDate; committedEnergy }
                }
            }
            if let completeness = presentation.nutritionCompleteness { Text(completeness).accessibilityIdentifier("coachReceiptUnknown") }
            if let notice = presentation.changeNotice {
                Text(notice).foregroundStyle(Color.diarySecondary).accessibilityIdentifier("coachReceiptChange")
            }
            if let notice = presentation.targetNotice {
                Text(notice).foregroundStyle(Color.diarySecondary).accessibilityIdentifier("coachReceiptTargetStatus")
            }
            if let macros = presentation.committedMacros {
                DisclosureGroup {
                    Text(macros).monospacedDigit().accessibilityIdentifier("coachReceiptMacros")
                } label: {
                    Text(presentation.estimateLabel ?? "Nutrition details")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .disclosureGroupStyle(CoachReceiptDisclosureStyle())
            }
        }
        .font(.subheadline).textSelection(.enabled)
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.diarySurface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coachReceipt-" + receipt.operationKey)
    }
    private var receiptStatus: some View {
        Text(presentation.committedStatus).font(.subheadline.weight(.semibold))
    }
    @ViewBuilder private var committedDate: some View {
        if let date = presentation.committedDate {
            Text("Recorded for " + date).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color.diarySecondary).accessibilityIdentifier("coachReceiptDate")
        }
    }
    @ViewBuilder private var committedEnergy: some View {
        if let energy = presentation.committedNutrition {
            Text(energy).monospacedDigit().accessibilityIdentifier("coachReceiptNutrition")
        }
    }
    @ViewBuilder private var reviewButton: some View {
        if receipt.mealID != nil || receipt.workoutID != nil {
            Button(action: open) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text("Review / Edit").fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Label("Review / Edit", systemImage: "square.and.pencil")
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
            }
                .accessibilityLabel(presentation.currentStatus + ". Review / Edit")
                .disabled(!presentation.canOpenTarget)
                .accessibilityIdentifier(receipt.mealID == nil ? "coachWorkoutLink" : "coachMealLink")
        }
    }
}

/// Make the whole nutrition row a reachable control, rather than only the native chevron.
private struct CoachReceiptDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    configuration.label
                    Spacer(minLength: 0)
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).textSelection(.disabled)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("coachReceiptDetails")
            if configuration.isExpanded { configuration.content }
        }
    }
}
