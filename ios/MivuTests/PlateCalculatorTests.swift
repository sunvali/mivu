import Foundation
import Testing
@testable import Mivu

@Suite struct PlateCalculatorTests {
    @Test func plates62_5() {
        #expect(PlateCalculator.perSide(target: 62.5, bar: 20, plates: WeightStep.defaultPlatesKg) == [20, 1.25])
        #expect(PlateCalculator.perSide(target: 20, bar: 20, plates: WeightStep.defaultPlatesKg) == [])
        #expect(PlateCalculator.perSide(target: 140, bar: 20, plates: WeightStep.defaultPlatesKg) == [25, 25, 10])
    }

    @Test func platesImpossible() {
        #expect(PlateCalculator.perSide(target: 61, bar: 20, plates: WeightStep.defaultPlatesKg) == nil)
        let nearest = PlateCalculator.nearest(target: 61, bar: 20, plates: WeightStep.defaultPlatesKg)
        #expect(nearest.below == 60 && nearest.above == 62.5)
        // Lighter than the bar: the bar is the closest.
        #expect(PlateCalculator.perSide(target: 15, bar: 20, plates: WeightStep.defaultPlatesKg) == nil)
        let light = PlateCalculator.nearest(target: 15, bar: 20, plates: WeightStep.defaultPlatesKg)
        #expect(light.below == 20 && light.above == 20)
    }

    @Test func platesLb() {
        #expect(PlateCalculator.perSide(target: 225, bar: 45, plates: WeightStep.defaultPlatesLb) == [45, 45])
        #expect(PlateCalculator.perSide(target: 135, bar: 0, plates: WeightStep.defaultPlatesLb) == [45, 10, 10, 2.5])
    }

    @Test func storedPlatesValidated() throws {
        let defaults = try #require(UserDefaults(suiteName: "Plates-" + UUID().uuidString))
        #expect(WeightStep.plates(unit: "kg", defaults: defaults) == WeightStep.defaultPlatesKg)
        #expect(WeightStep.bar(unit: "lb", defaults: defaults) == 45)
        defaults.set("[20,10,0.5]", forKey: WeightStep.platesKgKey)
        defaults.set(15.0, forKey: WeightStep.barKey)
        #expect(WeightStep.plates(unit: "kg", defaults: defaults) == [20, 10, 0.5])
        #expect(WeightStep.bar(unit: "kg", defaults: defaults) == 15)
        // A zero plate would make the wheel's step zero; any bad value falls back to the defaults.
        for bad in ["[20,0]", "[]", "[-5]", "nonsense"] {
            defaults.set(bad, forKey: WeightStep.platesKgKey)
            #expect(WeightStep.plates(unit: "kg", defaults: defaults) == WeightStep.defaultPlatesKg, "\(bad)")
        }
        defaults.set(0.0, forKey: WeightStep.barKey)
        #expect(WeightStep.bar(unit: "kg", defaults: defaults) == 20)
    }

    @Test func barSnapsToTheUnit() throws {
        let defaults = try #require(UserDefaults(suiteName: "Bar-" + UUID().uuidString))
        // Chosen as 45 lb, then the unit switched to kg: the 20 kg bar, which the picker can show as chosen.
        defaults.set(WeightStep.kg(fromDisplay: 45, unit: "lb"), forKey: WeightStep.barKey)
        #expect(WeightStep.bar(unit: "lb", defaults: defaults) == 45)
        #expect(WeightStep.bar(unit: "kg", defaults: defaults) == 20)
        defaults.set(15.0, forKey: WeightStep.barKey)
        #expect(WeightStep.bar(unit: "lb", defaults: defaults) == 35)
        #expect(WeightStep.bars(unit: "kg").contains(WeightStep.bar(unit: "kg", defaults: defaults)))
    }
}
