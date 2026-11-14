import Foundation

/// What the pane beside the Coach chat shows on a sideways iPhone Duo; nil is Today.
enum CoachPane: Hashable, Sendable {
    case day(String), meal(UUID), workout(UUID), progress

    /// Where a change Coach just made landed. Only receipts not seen before move the pane, so opening
    /// the app or paging old conversation never does; an open sheet in the pane is never replaced.
    static func landing(seen: Set<String>?, receipts: [CoachCommittedReceipt], activeDayID: UUID?, modalOpen: Bool) -> CoachPaneLanding {
        guard let seen, !modalOpen else { return CoachPaneLanding(pane: nil, jumps: false) }
        for receipt in receipts.reversed() where !seen.contains(receipt.operationKey) {
            if receipt.weightID != nil {
                if !receipt.operationKey.contains("/delete_weight/") { return CoachPaneLanding(pane: .progress, jumps: true) }
            } else if receipt.mealID != nil || receipt.workoutID != nil {
                if receipt.dayID != nil, receipt.dayID == activeDayID { return CoachPaneLanding(pane: nil, jumps: true) }
                if let date = receipt.targetLocalDate { return CoachPaneLanding(pane: .day(date), jumps: true) }
            }
        }
        return CoachPaneLanding(pane: nil, jumps: false)
    }
}

struct CoachPaneLanding: Equatable {
    var pane: CoachPane?
    var jumps: Bool
}

/// What Coach read to answer a question, kept for this session only.
enum CoachConsulted: Hashable, Sendable { case progress, day(String) }
