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
            "strength": .traditionalStrengthTraining,
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
}
