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
    private var presentation: CoachReceiptPresentation { CoachReceiptPresentation(receipt: receipt, target: target) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.committedStatus).font(.subheadline.weight(.semibold))
            if let date = presentation.committedDate { Text("Recorded for " + date).accessibilityIdentifier("coachReceiptDate") }
            ForEach(Array(presentation.committedItems.enumerated()), id: \.offset) { _, item in
                Text(item).accessibilityIdentifier("coachReceiptQuantity")
            }
            if let energy = presentation.committedNutrition { Text(energy).monospacedDigit().accessibilityIdentifier("coachReceiptNutrition") }
            if let macros = presentation.committedMacros { Text(macros).monospacedDigit().accessibilityIdentifier("coachReceiptMacros") }
            if let completeness = presentation.nutritionCompleteness { Text(completeness).accessibilityIdentifier("coachReceiptUnknown") }
            if let estimate = presentation.estimateLabel { Text(estimate).foregroundStyle(Color.diarySecondary) }
            if receipt.mealID != nil || receipt.workoutID != nil {
                Divider()
                Text(presentation.currentStatus).font(.subheadline.weight(.medium))
                if let date = presentation.currentDate { Text("Current record: " + date).font(.caption) }
                if let energy = presentation.currentNutrition { Text(energy).monospacedDigit() }
                if let macros = presentation.currentMacros { Text(macros).monospacedDigit() }
                Button(action: open) { Label("Review / Edit", systemImage: "square.and.pencil").frame(minHeight: 44) }
                    .accessibilityLabel(presentation.currentStatus + ". Review / Edit")
                    .disabled(!presentation.canOpenTarget)
                    .accessibilityIdentifier(receipt.mealID == nil ? "coachWorkoutLink" : "coachMealLink")
            }
        }
        .font(.subheadline).textSelection(.enabled)
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.diarySurface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coachReceipt-" + receipt.operationKey)
    }
}
