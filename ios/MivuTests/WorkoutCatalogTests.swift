import HealthKit
import Testing
import UIKit
@testable import Mivu

struct WorkoutCatalogTests {
    @Test func catalogLoads() {
        let ids = Set(WorkoutCatalog.activities.map(\.id))
        #expect(ids.count >= 35)
        for id in ["strength", "run", "walk", "cycle", "swim", "hike", "yoga", "pilates", "hiit", "crossfit",
                   "stretching", "mobility", "tennis"] { #expect(ids.contains(id), "\(id)") }
        #expect(WorkoutCatalog.exercises.count >= 140)
    }

    @Test func idsUniqueAndStable() {
        let activityIDs = WorkoutCatalog.activities.map(\.id)
        #expect(Set(activityIDs).count == activityIDs.count)
        let ids = WorkoutCatalog.exercises.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0 == $0.lowercased() && !$0.contains(" ") })
        let names = WorkoutCatalog.exercises.flatMap { [$0.name] + $0.aliases }.map(WorkoutCatalog.normalized)
        #expect(Set(names).count == names.count)
    }

    // Saved workouts refer to these IDs: new ones may be added, none may be removed or renamed.
    @Test func shippedIDsNeverDisappear() {
        let activities = Set(WorkoutCatalog.activities.map(\.id))
        let exercises = Set(WorkoutCatalog.exercises.map(\.id))
        #expect(Set(Self.activityIDs).subtracting(activities).isEmpty, "\(Set(Self.activityIDs).subtracting(activities))")
        #expect(Set(Self.exerciseIDs).subtracting(exercises).isEmpty, "\(Set(Self.exerciseIDs).subtracting(exercises))")
    }

    @Test func resolveByAlias() {
        for name in ["Bench", "bench press", "BB Bench Press"] {
            #expect(WorkoutCatalog.resolve(name)?.id == "barbell-bench-press", "\(name)")
        }
        #expect(WorkoutCatalog.resolve("Lat pull down")?.id == "lat-pulldown")
        #expect(WorkoutCatalog.resolve("not an exercise") == nil)
    }

    @Test func normalizedFoldsCaseSpaceHyphenPlural() {
        #expect(WorkoutCatalog.normalized(" Pull-Ups ") == WorkoutCatalog.normalized("pull ups"))
        #expect(WorkoutCatalog.normalized("Lat Pull Down") == WorkoutCatalog.normalized("lat-pulldown"))
        #expect(WorkoutCatalog.normalized("Bench Press") != WorkoutCatalog.normalized("Bench"))
    }

    @Test func everyActivityHasThreeMETsAscending() {
        for activity in WorkoutCatalog.activities {
            #expect(activity.met.count == 3, "\(activity.id)")
            #expect(activity.met == activity.met.sorted() && activity.met[0] > 0, "\(activity.id)")
        }
        #expect(WorkoutCatalog.activity("strength")?.met == [3.5, 3.5, 6.0])
    }

    @Test func activitiesMapToHealthKitAndSymbols() {
        let expected: [String: HKWorkoutActivityType] = [
            "run": .running, "walk": .walking, "cycle": .cycling, "swim": .swimming, "hike": .hiking, "yoga": .yoga,
            "pilates": .pilates, "hiit": .highIntensityIntervalTraining, "tennis": .tennis,
            "strength": .traditionalStrengthTraining, "crossfit": .crossTraining, "stretching": .flexibility,
            "mobility": .preparationAndRecovery,
        ]
        for (id, type) in expected { #expect(WorkoutCatalog.activity(id)?.healthKitType == type.rawValue, "\(id)") }
        for activity in WorkoutCatalog.activities { #expect(UIImage(systemName: activity.symbol) != nil, "\(activity.id)") }
    }

    @Test func exerciseFlagsAndMeasures() throws {
        #expect(WorkoutCatalog.exercise("barbell-bench-press")?.barbell == true)
        #expect(WorkoutCatalog.exercise("lat-pulldown")?.machine == true)
        #expect(WorkoutCatalog.exercise("push-up")?.measure == .reps)
        #expect(WorkoutCatalog.exercise("plank")?.measure == .time)
        #expect(WorkoutCatalog.exercise("farmers-carry")?.measure == .distanceTime)
        #expect(WorkoutCatalog.exercises.allSatisfy { !($0.machine && $0.barbell) })
    }

    private static let activityIDs = [
        "strength", "run", "walk", "cycle", "swim", "hike", "yoga", "pilates", "hiit", "crossfit", "stretching",
        "mobility", "tennis", "elliptical", "rowing", "stairs", "jump-rope", "boxing", "kickboxing", "martial-arts",
        "dance", "basketball", "soccer", "volleyball", "badminton", "table-tennis", "squash", "pickleball", "golf",
        "climbing", "surfing", "skiing", "cross-country-skiing", "snowboarding", "skating", "core", "step-training",
        "water-fitness", "tai-chi", "baseball", "other",
    ]

    private static let exerciseIDs = [
        "barbell-bench-press", "incline-barbell-bench-press", "decline-barbell-bench-press", "dumbbell-bench-press",
        "incline-dumbbell-press", "decline-dumbbell-press", "dumbbell-fly", "incline-dumbbell-fly",
        "chest-press-machine", "incline-chest-press-machine", "pec-deck", "cable-crossover", "low-cable-fly",
        "smith-machine-bench-press", "push-up", "incline-push-up", "decline-push-up", "diamond-push-up", "dip",
        "assisted-dip-machine", "deadlift", "sumo-deadlift", "romanian-deadlift", "trap-bar-deadlift", "barbell-row",
        "pendlay-row", "t-bar-row", "dumbbell-row", "chest-supported-row-machine", "seated-cable-row",
        "seated-row-machine", "lat-pulldown", "close-grip-lat-pulldown", "straight-arm-pulldown", "pull-up",
        "chin-up", "assisted-pull-up-machine", "inverted-row", "face-pull", "hyperextension", "barbell-shrug",
        "dumbbell-shrug", "rack-pull", "good-morning", "dumbbell-pullover", "pullover-machine", "overhead-press",
        "push-press", "dumbbell-shoulder-press", "arnold-press", "shoulder-press-machine",
        "smith-machine-shoulder-press", "lateral-raise", "cable-lateral-raise", "lateral-raise-machine",
        "front-raise", "rear-delt-fly", "reverse-pec-deck", "upright-row", "pike-push-up", "landmine-press",
        "barbell-curl", "ez-bar-curl", "dumbbell-curl", "hammer-curl", "incline-dumbbell-curl", "preacher-curl",
        "preacher-curl-machine", "cable-curl", "concentration-curl", "triceps-pushdown",
        "overhead-triceps-extension", "cable-overhead-triceps-extension", "skull-crusher", "close-grip-bench-press",
        "bench-dip", "triceps-dip-machine", "triceps-extension-machine", "triceps-kickback", "wrist-curl",
        "barbell-back-squat", "front-squat", "goblet-squat", "smith-machine-squat", "hack-squat", "leg-press",
        "leg-extension", "lying-leg-curl", "seated-leg-curl", "hip-abductor-machine", "hip-adductor-machine",
        "walking-lunge", "dumbbell-lunge", "reverse-lunge", "barbell-lunge", "bulgarian-split-squat", "step-up",
        "hip-thrust", "hip-thrust-machine", "glute-bridge", "glute-kickback-machine", "cable-pull-through",
        "standing-calf-raise-machine", "seated-calf-raise", "calf-raise", "bodyweight-squat", "jump-squat",
        "wall-sit", "nordic-curl", "dumbbell-romanian-deadlift", "plank", "side-plank", "hollow-hold", "crunch",
        "sit-up", "decline-sit-up", "bicycle-crunch", "leg-raise", "hanging-leg-raise", "hanging-knee-raise",
        "captains-chair-leg-raise", "russian-twist", "dead-bug", "ab-wheel-rollout", "mountain-climber",
        "cable-crunch", "ab-crunch-machine", "pallof-press", "woodchopper", "torso-rotation-machine",
        "farmers-carry", "suitcase-carry", "sled-push", "sled-pull", "treadmill", "stationary-bike",
        "rowing-machine", "ski-erg", "stair-climber", "elliptical-trainer", "battle-ropes", "jump-rope", "burpee",
        "box-jump", "kettlebell-swing", "turkish-get-up", "thruster", "power-clean", "power-snatch",
        "clean-and-jerk", "medicine-ball-slam", "wall-ball",
    ]
}

extension WorkoutCatalogTests {
    /// A tile with a symbol iOS lacks shows blank, so every catalog exercise and the fallback must name a real one.
    @Test func everyExerciseGlyphIsARealSymbol() {
        for exercise in WorkoutCatalog.exercises {
            let style = ExerciseGlyphStyle(exerciseID: exercise.id, name: exercise.name)
            #expect(UIImage(systemName: style.symbol) != nil, "\(exercise.id): \(style.symbol)")
            #expect(style.family != .other || exercise.muscle == "full body", "\(exercise.id) has no colour family")
            #expect(style.subtitle == "\(exercise.muscle.capitalized) · \(exercise.equipment.capitalized)")
        }
        let own = ExerciseGlyphStyle(exerciseID: nil, name: "Synthetic own lift")
        #expect(UIImage(systemName: own.symbol) != nil && own.family == .other && own.subtitle == nil)
        #expect(ExerciseGlyphStyle(exerciseID: nil, name: "bench press").family == .chest, "a named catalog lift without an id still finds its tile")
    }
}
