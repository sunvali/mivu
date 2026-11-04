import Foundation

/// A bundled activity; `met` is light, moderate, vigorous (2024 Compendium) and `healthKitType` is an `HKWorkoutActivityType` raw value.
struct WorkoutActivity: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let symbol: String
    let hasDistance: Bool
    let indoorOutdoor: Bool
    let met: [Double]
    let healthKitType: UInt
}

/// A bundled gym exercise. `machine` marks machines and cable stations; `barbell` marks lifts that use the plate calculator.
struct CatalogExercise: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let aliases: [String]
    let measure: ExerciseMeasure
    let equipment: String
    let muscle: String
    let machine: Bool
    let barbell: Bool
}

enum WorkoutCatalog {
    static let activities: [WorkoutActivity] = load("activities")
    static let exercises: [CatalogExercise] = load("exercises")

    private static let activitiesByID = Dictionary(activities.map { ($0.id, $0) }) { first, _ in first }
    private static let exercisesByID = Dictionary(exercises.map { ($0.id, $0) }) { first, _ in first }
    private static let exercisesByName = Dictionary(
        exercises.flatMap { exercise in ([exercise.name] + exercise.aliases).map { (normalized($0), exercise) } }
    ) { first, _ in first }

    static func activity(_ id: String) -> WorkoutActivity? { activitiesByID[id] }
    static func exercise(_ id: String) -> CatalogExercise? { exercisesByID[id] }
    static func resolve(_ name: String) -> CatalogExercise? { exercisesByName[normalized(name)] }

    /// Folds case, spaces, hyphens and a trailing plural so "Pull-Ups" and "pull up" match.
    static func normalized(_ name: String) -> String {
        let letters = String(name.lowercased().filter { $0.isLetter || $0.isNumber })
        return letters.hasSuffix("s") && !letters.hasSuffix("ss") ? String(letters.dropLast()) : letters
    }

    private static func load<T: Decodable>(_ file: String) -> [T] {
        guard let url = Bundle.main.url(forResource: file, withExtension: "json"),
              let list = try? JSONDecoder().decode([T].self, from: Data(contentsOf: url)) else {
            fatalError("Missing bundled \(file).json")
        }
        return list
    }
}
