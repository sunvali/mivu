import SwiftUI

/// What the workout screen shows; imported Health workouts are read-only except Delete.
struct WorkoutDetailPresentation {
    let session: WorkoutSession
    var canEdit: Bool { !session.isFromHealth }
    var sourceLine: String? { session.healthSource.map { String(localized: "From \($0)") } }
    var burnLine: String {
        guard let kcal = session.estimatedBurnKcal else {
            return session.isFromHealth ? String(localized: "No calories from Health") : String(localized: "Estimated burn: unknown")
        }
        return session.isFromHealth ? String(localized: "Active calories: \(kcal.formatted(.number.precision(.fractionLength(0)))) kcal")
            : String(localized: "Estimated burn: \(kcal.formatted()) kcal")
    }
}

/// A Coach or hand-entered workout that an imported Health workout already covers; only the Health one earns calories.
struct WorkoutOverlapWarning: View {
    @Bindable var model: DiaryViewModel
    let workout: WorkoutSession
    let coveredBy: WorkoutSession
    @State private var removing = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { message; Spacer(minLength: 8); remove }
            VStack(alignment: .leading, spacing: 4) { message; remove }
        }
    }

    private var message: some View {
        let source = coveredBy.healthSource ?? "Apple Health"
        return Label("\(source) may have this workout already. Remove yours?", systemImage: "exclamationmark.circle")
            .font(.caption).foregroundStyle(Color.diarySecondary)
    }

    private var remove: some View {
        Button("Remove") {
            guard let owner = model.selection?.identity.profileID, !removing else { return }
            removing = true
            Task {
                await model.change { try await model.store.deleteWorkout(id: workout.id, expectedRevision: workout.revision, expectedProfileID: owner) }
                removing = false
            }
        }
        .frame(minHeight: 44)
        .disabled(removing)
        .accessibilityLabel(removeLabel)
        .accessibilityIdentifier("workoutOverlapRemove")
    }

    private var removeLabel: String {
        switch workout.kind {
        case .strength: String(localized: "Remove your strength workout")
        case .cardio: String(localized: "Remove your cardio workout")
        case .other: String(localized: "Remove your other workout")
        }
    }
}
