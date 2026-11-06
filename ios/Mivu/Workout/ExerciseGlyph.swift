import SwiftUI

/// An exercise's tile: its muscle's colour and an SF Symbol for its equipment, as Apple Fitness does.
/// Exercises outside the catalog get a neutral tile.
struct ExerciseGlyph: View {
    let style: ExerciseGlyphStyle
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 36

    init(exerciseID: String?, name: String) { style = ExerciseGlyphStyle(exerciseID: exerciseID, name: name) }

    var body: some View {
        // Capped so the tile never crowds the name at the largest text sizes.
        let side = min(size, 52)
        Image(systemName: style.symbol)
            .font(.system(size: side * 0.5, weight: .semibold))
            .foregroundStyle(style.family.ink)
            .frame(width: side, height: side)
            .background(style.family.tint, in: .rect(cornerRadius: side * 0.28))
            .accessibilityHidden(true)
    }
}

struct ExerciseGlyphStyle: Equatable {
    let symbol: String
    let family: MuscleFamily
    /// "Chest · Barbell"; nil for the user's own exercises.
    let subtitle: String?

    init(exerciseID: String?, name: String) {
        let catalog = exerciseID.flatMap(WorkoutCatalog.exercise) ?? WorkoutCatalog.resolve(name)
        symbol = catalog.map { Self.symbol(equipment: $0.equipment, muscle: $0.muscle) } ?? "figure.strengthtraining.traditional"
        family = MuscleFamily(muscle: catalog?.muscle)
        subtitle = catalog.map { "\($0.muscle.capitalized) · \($0.equipment.capitalized)" }
    }

    static func symbol(equipment: String, muscle: String) -> String {
        switch equipment {
        case "barbell", "ez bar": "figure.strengthtraining.traditional"
        case "dumbbell", "kettlebell": "dumbbell.fill"
        case "machine": "gearshape.2.fill"
        case "cable", "rope", "sled": "figure.strengthtraining.functional"
        case "cardio": "figure.mixed.cardio"
        case "medicine ball", "ab wheel": "figure.core.training"
        default: muscle == "core" ? "figure.core.training" : "figure.cross.training"
        }
    }
}

/// Six colour families, so a workout reads by body region without turning into a rainbow.
enum MuscleFamily: CaseIterable {
    case chest, back, shoulders, arms, legs, core, other

    init(muscle: String?) {
        switch muscle {
        case "chest": self = .chest
        case "back": self = .back
        case "shoulders": self = .shoulders
        case "biceps", "triceps", "forearms": self = .arms
        case "quads", "hamstrings", "glutes", "calves": self = .legs
        case "core": self = .core
        default: self = .other
        }
    }

    var ink: Color {
        switch self {
        case .chest: Color.adaptive(0xB4235A, 0xFFA3C4)
        case .back: .diaryAccent
        case .shoulders: Color.adaptive(0x9A4A00, 0xFFB57A)
        case .arms: .diaryFat
        case .legs: .diaryProtein
        case .core: .diarySuccess
        case .other: .diarySecondary
        }
    }

    var tint: Color {
        switch self {
        case .chest: Color.adaptive(0xFCE8F0, 0x3A1B28)
        case .back: .diarySummarySurface
        case .shoulders: Color.adaptive(0xFDEFE0, 0x33230F)
        case .arms: Color.adaptive(0xF2EAFB, 0x281B36)
        case .legs: .diaryChartSurface
        case .core: .diaryTintBurn
        case .other: Color.adaptive(0xEDF2F3, 0x263033)
        }
    }
}
