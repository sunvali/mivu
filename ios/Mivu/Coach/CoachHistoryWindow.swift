import Foundation

struct CoachHistoryWindow {
    private static let pageSize = 20
    private(set) var firstVisibleTurnID: UUID?

    func startIndex(in ids: [UUID]) -> Int {
        firstVisibleTurnID.flatMap { ids.firstIndex(of: $0) }
            ?? max(0, ids.count - Self.pageSize)
    }

    mutating func reset(ids: [UUID]) {
        firstVisibleTurnID = ids.dropFirst(max(0, ids.count - Self.pageSize)).first
    }

    mutating func reconcile(ids: [UUID]) {
        guard let firstVisibleTurnID, ids.contains(firstVisibleTurnID) else {
            reset(ids: ids)
            return
        }
    }

    @discardableResult mutating func showEarlier(ids: [UUID]) -> UUID? {
        reconcile(ids: ids)
        let start = startIndex(in: ids)
        guard start > 0 else { return nil }
        firstVisibleTurnID = ids[max(0, start - Self.pageSize)]
        return firstVisibleTurnID
    }
}
