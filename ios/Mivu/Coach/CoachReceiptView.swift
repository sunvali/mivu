import SwiftUI

/// Current target availability is independent of the original committed receipt.
enum CoachReceiptTarget: Equatable, Sendable {
    case loading, unavailable, failed
    case meal(MealReadModel, localDate: String)
    case workout(WorkoutSession, localDate: String)
}

/// Read from coach_undo; the committed receipt itself never changes.
enum CoachUndoState: Equatable, Sendable { case available, undone }

struct CoachReceiptPresentation: Equatable {
    let receipt: CoachCommittedReceipt
    let target: CoachReceiptTarget
    var committedDate: String? { receipt.targetLocalDate }
    var committedItems: [String] {
        receipt.items.map { "\($0.name) · \($0.quantity.formatted(.number.grouping(.never))) \($0.unit)" }
    }
    /// The write after the turn ID, so an undo of a delete never reads as the delete itself.
    private static func write(_ key: String) -> Substring { key.split(separator: "/", maxSplits: 1).last ?? "" }
    /// Decided by the receipt alone, so a card never vanishes while undo availability reloads.
    static func showsCard(_ receipt: CoachCommittedReceipt) -> Bool {
        receipt.mealID != nil || receipt.workoutID != nil || ["delete_weight/", "undo/"].contains { write(receipt.operationKey).hasPrefix($0) }
    }
    /// A whole record the Coach deleted; its card only offers Undo.
    var isRemoval: Bool { ["delete_meal/", "delete_weight/", "delete_workout/"].contains { Self.write(receipt.operationKey).hasPrefix($0) } }
    var committedStatus: String {
        if isRemoval { return "Removed" }
        if Self.write(receipt.operationKey).hasPrefix("delete_photo/") { return "Photo removed" }
        return switch receipt.submissionState {
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
    /// Adds the items that know the nutrient, like the diary totals; nutritionCompleteness discloses the gap.
    private func committedTotal(_ nutrient: KeyPath<NutritionValues, Double?>) -> Double? {
        let known = receipt.items.compactMap { $0.nutrition?[keyPath: nutrient] }
        return known.isEmpty ? nil : known.reduce(0, +)
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
        if moved, let date = currentDate { return (edited ? "Edited · moved to " : "Moved to ") + CoachReplyLines.shortDate(date) }
        if edited { return "Edited later" }
        return stateChanged ? "Status changed later" : nil
    }
    private static func macros(carbs: Double?, protein: Double?, fat: Double?) -> String {
        func grams(_ value: Double?) -> String {
            value.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " g" } ?? "unknown"
        }
        return "Carbs " + grams(carbs) + " · Protein " + grams(protein) + " · Fat " + grams(fat)
    }
    var itemRows: [(name: String, amount: String, kcal: String)] {
        receipt.items.map { ($0.name, "\($0.quantity.formatted(.number.grouping(.never))) \($0.unit)", $0.nutrition?.kcal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—") }
    }
    /// Energy share of carbs, protein and fat (4/4/9 kcal per gram); nil when any total is unknown.
    var macroShare: (carbs: Double, protein: Double, fat: Double)? {
        guard !receipt.items.isEmpty, let carbs = committedTotal(\.carbs), let protein = committedTotal(\.protein), let fat = committedTotal(\.fat) else { return nil }
        let energy = carbs * 4 + protein * 4 + fat * 9
        guard energy > 0 else { return nil }
        return (carbs * 4 / energy, protein * 4 / energy, fat * 9 / energy)
    }
    var macroTotals: (carbs: String, protein: String, fat: String)? {
        guard let carbs = committedTotal(\.carbs), let protein = committedTotal(\.protein), let fat = committedTotal(\.fat) else { return nil }
        func grams(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) + " g" }
        return (grams(carbs), grams(protein), grams(fat))
    }
    /// Per-dish grams for the disclosure; nil for a single dish, whose totals the legend already shows.
    var itemMacros: String? {
        guard receipt.items.count > 1 else { return nil }
        return receipt.items.map { item in
            "\(item.name): " + Self.macros(carbs: item.nutrition?.carbs, protein: item.nutrition?.protein, fat: item.nutrition?.fat)
        }.joined(separator: "\n")
    }
    var weightLabel: String? {
        guard receipt.weightID != nil, !receipt.operationKey.contains("/delete_weight/") else { return nil }
        guard let value = receipt.weightValue, let unit = receipt.weightUnit else { return "Weight saved" }
        return "Weight saved · \(value.formatted(.number.grouping(.never))) \(unit)"
    }
    var canOpenTarget: Bool {
        switch target { case .meal, .workout: true; default: false }
    }
    private static func energy(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) + " kcal" }
}

struct CoachReceiptView: View {
    let receipt: CoachCommittedReceipt
    let target: CoachReceiptTarget
    var undoState: CoachUndoState? = nil
    var undo: () -> Void = {}
    let open: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var presentation: CoachReceiptPresentation { CoachReceiptPresentation(receipt: receipt, target: target) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { receiptStatus; committedDate }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) { receiptStatus; Spacer(minLength: 0); committedDate }
            }
            ForEach(Array(presentation.itemRows.enumerated()), id: \.offset) { _, row in
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) { Text(row.name); Text(row.amount).foregroundStyle(Color.diarySecondary); Text(row.kcal + " kcal").monospacedDigit() }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.name).lineLimit(2)
                            Text(row.amount).foregroundStyle(Color.diarySecondary).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(row.kcal).monospacedDigit().foregroundStyle(Color.diarySecondary)
                        }
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.name), \(row.amount), \(row.kcal == "—" ? "calories unknown" : row.kcal + " calories")")
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier("coachReceiptQuantity")
            }
            if presentation.macroShare != nil || presentation.committedNutrition != nil { Divider().overlay(Color.diaryRule).padding(.vertical, 4) }
            committedEnergy
            if let share = presentation.macroShare { macroBar(share); macroLegend }
            if let completeness = presentation.nutritionCompleteness { Text(completeness).accessibilityIdentifier("coachReceiptUnknown") }
            if let notice = presentation.changeNotice {
                Text(notice).foregroundStyle(Color.diarySecondary).accessibilityIdentifier("coachReceiptChange")
            }
            if !presentation.isRemoval, let notice = presentation.targetNotice {
                Text(notice).foregroundStyle(Color.diarySecondary).accessibilityIdentifier("coachReceiptTargetStatus")
            }
            if let macros = presentation.committedMacros {
                DisclosureGroup {
                    // The legend shows meal totals; the disclosure holds each dish's grams.
                    Text(presentation.itemMacros ?? macros).monospacedDigit().foregroundStyle(Color.diarySecondary).accessibilityIdentifier("coachReceiptMacros")
                } label: {
                    Text(presentation.estimateLabel ?? "Nutrition details")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .disclosureGroupStyle(CoachReceiptDisclosureStyle())
            }
            // Actions close the card so they stay in view when a tall card sits above the composer.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) { reviewButton; undoButton }
            } else {
                HStack(spacing: 12) { undoButton; Spacer(minLength: 0); reviewButton }
            }
        }
        .font(.subheadline)
        .modifier(DiarySummaryCardStyle(padding: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coachReceipt-" + receipt.operationKey)
    }
    private var receiptStatus: some View {
        Text(undoState == .undone ? "Undone" : presentation.committedStatus).font(.subheadline.weight(.semibold))
    }
    @ViewBuilder private var undoButton: some View {
        if undoState == .available {
            Button(action: undo) { Label("Undo", systemImage: "arrow.uturn.backward").frame(minWidth: 44, minHeight: 44) }
                .accessibilityIdentifier("coachUndo")
        }
    }
    @ViewBuilder private var committedDate: some View {
        if let date = presentation.committedDate {
            Text(CoachReplyLines.shortDate(date)).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color.diarySecondary).accessibilityIdentifier("coachReceiptDate")
        }
    }
    @ViewBuilder private var committedEnergy: some View {
        if let energy = presentation.committedNutrition {
            Text(energy).font(.headline).monospacedDigit().foregroundStyle(Color.diaryEnergy).accessibilityIdentifier("coachReceiptNutrition")
        }
    }
    @ViewBuilder private var macroLegend: some View {
        if let totals = presentation.macroTotals {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { legend(totals) }
                VStack(alignment: .leading, spacing: 2) { legend(totals) }
            }
            .font(.caption.weight(.medium)).monospacedDigit()
            .accessibilityHidden(true)
        }
    }
    @ViewBuilder private func legend(_ totals: (carbs: String, protein: String, fat: String)) -> some View {
        Text("Carbs \(totals.carbs)").foregroundStyle(Color.diaryCarbs)
        Text("Protein \(totals.protein)").foregroundStyle(Color.diaryProtein)
        Text("Fat \(totals.fat)").foregroundStyle(Color.diaryFat)
    }
    /// One energy split bar in the Today macro colours.
    private func macroBar(_ share: (carbs: Double, protein: Double, fat: Double)) -> some View {
        // Canvas draws at the offered width without feeding a size back into the self-sizing table cell.
        Canvas { context, size in
            var x = 0.0
            for (part, color) in [(share.carbs, Color.diaryCarbs), (share.protein, Color.diaryProtein), (share.fat, Color.diaryFat)] {
                let width = max(0, size.width * part - 2)
                context.fill(Capsule().path(in: CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(color))
                x += width + 2
            }
        }
        .frame(maxWidth: .infinity).frame(height: 6)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.committedMacros ?? "")
        .accessibilityIdentifier("coachReceiptMacroBar")
    }
    @ViewBuilder private var reviewButton: some View {
        if !presentation.isRemoval, receipt.mealID != nil || receipt.workoutID != nil {
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
            // A wrapped label at accessibility sizes must grow the row, not draw past the card.
            .fixedSize(horizontal: false, vertical: true)
            .buttonStyle(.plain).textSelection(.disabled)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("coachReceiptDetails")
            if configuration.isExpanded { configuration.content }
        }
    }
}
