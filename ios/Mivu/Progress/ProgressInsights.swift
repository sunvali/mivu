import SwiftUI

/// How far a day's energy landed from that day's own target; over and under share a band.
enum ProgressBand: Int, CaseIterable {
    case near, bitOff, off, farOff

    static func of(kcal: Double?, target: Double?) -> ProgressBand? {
        guard let kcal, let target, target > 0 else { return nil }
        // Multiply before dividing so the 10/20/35% edges stay exact.
        let percent = abs(kcal - target) * 100 / target
        return percent <= 10 ? .near : percent <= 20 ? .bitOff : percent <= 35 ? .off : .farOff
    }

    var title: String {
        switch self {
        case .near: "Near"
        case .bitOff: "A bit off"
        case .off: "Off"
        case .farOff: "Far off"
        }
    }

    var color: Color {
        switch self {
        case .near: .diaryAccent
        case .bitOff: .diaryBandBitOff
        case .off: .diaryBandOff
        case .farOff: .diaryBandFarOff
        }
    }
}
