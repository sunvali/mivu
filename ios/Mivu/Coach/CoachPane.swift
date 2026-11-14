import Foundation

/// What the pane beside the Coach chat shows on a sideways iPhone Duo; nil is Today.
enum CoachPane: Hashable, Sendable {
    case day(String), meal(UUID), workout(UUID), progress

    /// Where a change Coach just made landed. Only receipts not seen before move the pane, so opening
    /// the app or paging old conversation never does; an open sheet in the pane is never replaced.
    /// A change to the record already open in the pane (`showing`) leaves it open; it updates in place.
    /// `today` is the date of the turn that made the change: the first meal of a day starts that day, so the
    /// diary has no active day to compare against yet when its receipt arrives.
    static func landing(seen: Set<String>?, receipts: [CoachCommittedReceipt], activeDayID: UUID?, today: String?, modalOpen: Bool, showing: CoachPane? = nil) -> CoachPaneLanding {
        guard let seen, !modalOpen else { return CoachPaneLanding(pane: nil, jumps: false) }
        for receipt in receipts.reversed() where !seen.contains(receipt.operationKey) {
            if let showing, showing == receipt.mealID.map(CoachPane.meal) || showing == receipt.workoutID.map(CoachPane.workout) {
                // Unless Coach removed it: then there is nothing left to show, and Today takes over.
                return CoachPaneLanding(pane: nil, jumps: CoachReceiptPresentation(receipt: receipt, target: .loading).isRemoval)
            }
            if receipt.weightID != nil {
                if !receipt.operationKey.contains("/delete_weight/") { return CoachPaneLanding(pane: .progress, jumps: true) }
            } else if receipt.mealID != nil || receipt.workoutID != nil {
                let date = receipt.targetLocalDate
                if (receipt.dayID != nil && receipt.dayID == activeDayID) || (date != nil && date == today) { return CoachPaneLanding(pane: nil, jumps: true) }
                if let date { return CoachPaneLanding(pane: .day(date), jumps: true) }
            }
        }
        return CoachPaneLanding(pane: nil, jumps: false)
    }
}

/// The receipts the pane has already shown, for one diary. A first look, or another profile's diary,
/// only records what is there, so opening the app or switching profile never moves the pane.
struct CoachPaneMemory {
    private var owner: CoachTimelineIdentity?
    private var keys: Set<String> = []

    /// Records the latest turn's receipts and says where the pane goes. A skipped change is recorded too, never queued.
    mutating func observe(owner: CoachTimelineIdentity, receipts: [CoachCommittedReceipt], activeDayID: UUID?, today: String?,
                          modalOpen: Bool, showing: CoachPane?) -> CoachPaneLanding {
        let landing = CoachPane.landing(seen: self.owner == owner ? keys : nil, receipts: receipts, activeDayID: activeDayID,
                                        today: today, modalOpen: modalOpen, showing: showing)
        if self.owner != owner { self.owner = owner; keys = [] }
        keys.formUnion(receipts.map(\.operationKey))
        return landing
    }
}

struct CoachPaneLanding: Equatable {
    var pane: CoachPane?
    var jumps: Bool
}

/// What Coach read to answer a question, kept for this session only.
enum CoachConsulted: Hashable, Sendable { case progress, day(String) }
