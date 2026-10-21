import SwiftUI

/// One-tap answers to a Coach question: the candidate records, or Remove/Keep for a whole-meal delete.
struct CoachQuestionChips: View {
    let question: CoachQuestion
    let meals: [MealReadModel]
    var model: DiaryViewModel? = nil
    let onPick: (CoachReply.Target, String) -> Void
    @ScaledMetric(relativeTo: .body) private var thumbnail = 44.0

    private func mealID(_ target: CoachReply.Target) -> UUID? {
        switch target { case .meal(let id), .item(let id, _): id; default: nil }
    }
    private func name(_ meal: MealReadModel, _ target: CoachReply.Target) -> String {
        if case .item(_, let itemID) = target, let item = meal.items.first(where: { $0.id == itemID }) { return item.name }
        let names = meal.items.prefix(3).map(\.name).joined(separator: ", ")
        return names.isEmpty ? "Meal" : names
    }
    private func time(_ meal: MealReadModel) -> String {
        meal.timePrecision == .dateOnly ? "Time unspecified" : meal.eatenAt.formatted(date: .omitted, time: .shortened)
    }
    var body: some View {
        if question.kind == .confirm, let target = question.candidates.first {
            HStack(spacing: 12) {
                Button(role: .destructive) { onPick(target, "Remove it") } label: { Text("Remove").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.bordered).tint(Color.diaryError).accessibilityIdentifier("coachConfirmRemove")
                Button { onPick(target, "Keep it") } label: { Text("Keep").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.bordered).tint(Color.diaryAccent).accessibilityIdentifier("coachConfirmKeep")
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(question.candidates.enumerated()), id: \.offset) { _, target in
                    if let id = mealID(target), let meal = meals.first(where: { $0.id == id }) {
                        let title = name(meal, target)
                        Button { onPick(target, title) } label: {
                            HStack(spacing: 12) {
                                MealThumbnail(meal: meal, model: model, size: thumbnail).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title).font(.body.weight(.semibold)).foregroundStyle(Color.diaryText)
                                    Text(time(meal)).font(.subheadline).foregroundStyle(Color.diarySecondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(8).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(Color.diarySummarySurface, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore).accessibilityLabel("\(title), \(time(meal))").accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("coachQuestionChip")
                    }
                }
            }
        }
    }
}
