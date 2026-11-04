import Foundation
import Testing
@testable import Mivu

struct WorkoutBurnTests {
    @Test func netFormula() {
        // Cycling without a distance uses its moderate MET of 8.0.
        let kcal = WorkoutBurn.estimate(activity: "cycle", seconds: 1800, distanceMeters: nil, effort: 5, bodyKg: 70)
        #expect(kcal == 245)  // (8.0 - 1) * 70 * 0.5
    }

    @Test func effortBands() throws {
        let met = try #require(WorkoutCatalog.activity("swim")).met  // 5.8, 7.0, 9.8
        func kcal(_ effort: Int?) -> Double? {
            WorkoutBurn.estimate(activity: "swim", seconds: 3600, distanceMeters: nil, effort: effort, bodyKg: 100)
        }
        #expect(kcal(3) == ((met[0] - 1) * 100).rounded())
        #expect(kcal(5) == ((met[1] - 1) * 100).rounded())
        #expect(kcal(7) == ((met[1] - 1) * 100).rounded())
        #expect(kcal(9) == ((met[2] - 1) * 100).rounded())
        #expect(kcal(nil) == ((met[1] - 1) * 100).rounded())
    }

    @Test func runSpeedOverridesEffort() {
        // 5 km in 28 minutes is 10.7 km/h: the 9 min/mile row (10.5 MET), whatever the effort.
        for effort in [3, 9, nil] {
            let kcal = WorkoutBurn.estimate(activity: "run", seconds: 1680, distanceMeters: 5000, effort: effort, bodyKg: 70)
            #expect(kcal == ((10.5 - 1) * 70 * (1680.0 / 3600)).rounded(), "\(String(describing: effort))")
        }
    }

    @Test func speedClampsToTableEnds() {
        // Walking-pace jog uses the lowest row; a very fast ride uses the highest.
        #expect(WorkoutBurn.estimate(activity: "run", seconds: 3600, distanceMeters: 3000, effort: nil, bodyKg: 100) == 230)
        #expect(WorkoutBurn.estimate(activity: "cycle", seconds: 3600, distanceMeters: 40000, effort: nil, bodyKg: 100) == 1580)
    }

    @Test func noWeightNoEstimate() {
        #expect(WorkoutBurn.estimate(activity: "run", seconds: 1800, distanceMeters: nil, effort: 5, bodyKg: nil) == nil)
        #expect(WorkoutBurn.estimate(activity: "no-such", seconds: 1800, distanceMeters: nil, effort: 5, bodyKg: 70) == nil)
    }

    @Test func bodyKgUsesLatestOnOrBefore() {
        func weigh(_ day: String, _ value: Double, _ unit: String = "kg") -> WeightEntry {
            WeightEntry(measuredAt: ProgressDate.date(day, zone: "UTC")!, value: value, unit: unit)
        }
        let weights = [weigh("2026-11-05", 79), weigh("2026-11-01", 80)]
        #expect(WorkoutBurn.bodyKg(on: "2026-11-04", weights: weights, onboardingKg: 90, zone: "UTC") == 80)
        #expect(WorkoutBurn.bodyKg(on: "2026-11-05", weights: weights, onboardingKg: 90, zone: "UTC") == 79)
        #expect(WorkoutBurn.bodyKg(on: "2026-10-31", weights: weights, onboardingKg: 90, zone: "UTC") == 90)
        #expect(WorkoutBurn.bodyKg(on: "2026-11-04", weights: [weigh("2026-11-02", 176, "lb")], onboardingKg: nil, zone: "UTC")
                == 176 * 0.45359237)
        #expect(WorkoutBurn.bodyKg(on: "2026-11-04", weights: [], onboardingKg: nil, zone: "UTC") == nil)
    }
}
