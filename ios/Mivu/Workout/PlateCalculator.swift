import Foundation

/// Which plates go on each side of the bar, in the shown unit. Any number of each plate, heaviest first.
enum PlateCalculator {
    /// nil when the plates cannot make the weight exactly, or it is lighter than the bar.
    static func perSide(target: Double, bar: Double, plates: [Double]) -> [Double]? {
        let (loaded, left) = fill((target - bar) / 2, plates)
        return target >= bar - 0.001 && left < 0.001 ? loaded : nil
    }

    /// The closest weights the plates can make around the target.
    // shortcut: assumes every plate is a multiple of the smallest (true of gym sets); odd plates may miss a closer weight.
    static func nearest(target: Double, bar: Double, plates: [Double]) -> (below: Double, above: Double) {
        guard target > bar, let smallest = plates.min() else { return (bar, bar) }
        let (loaded, left) = fill((target - bar) / 2, plates)
        let below = bar + 2 * loaded.reduce(0, +)
        return (below, left < 0.001 ? below : below + 2 * smallest)
    }

    private static func fill(_ side: Double, _ plates: [Double]) -> (plates: [Double], left: Double) {
        var left = side, loaded: [Double] = []
        for plate in plates.sorted(by: >) where plate > 0 {
            while left >= plate - 0.001 { loaded.append(plate); left -= plate }
        }
        return (loaded, max(left, 0))
    }
}
