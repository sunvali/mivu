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

// Staged paged contract. Task 11 removes the legacy ID-slice helper above when its
// shipping call sites migrate; the spike and eventual timeline share this policy.
struct CoachViewportAnchor: Equatable, Sendable {
    var rowID: UUID
    var offset: Double
    var focusedExchangeID: UUID?
}

enum CoachViewportMode: Equatable, Sendable { case latest, history(CoachViewportAnchor) }
enum CoachViewportRestoration: Equatable, Sendable { case none, latest, preserve(CoachViewportAnchor) }
enum CoachPageDirection: Hashable, Sendable { case earlier, later }

struct CoachPageReservation: Equatable, Sendable {
    var id: UUID
    var request: CoachPageRequest
    var direction: CoachPageDirection
}

struct CoachPagedHistoryWindow {
    private(set) var pages: [CoachPage] = []
    private(set) var reservations: [CoachPageDirection: CoachPageReservation] = [:]
    private(set) var identity: CoachTimelineIdentity?
    private(set) var viewport: CoachViewportMode = .latest
    var exchanges: [CoachExchangeSummary] { pages.flatMap(\.exchanges) }
    var reservedCapacity: Int { reservations.count * 20 }
    var residentCount: Int { pages.reduce(0) { $0 + $1.exchanges.count } }

    mutating func reset(_ page: CoachPage) {
        identity = page.identity; pages = [page]; reservations = [:]
    }
    mutating func setViewport(_ value: CoachViewportMode) { viewport = value }

    mutating func reserve(_ direction: CoachPageDirection, anchor: CoachViewportAnchor?) -> CoachPageReservation? {
        guard reservations[direction] == nil, let edge = direction == .earlier ? pages.first : pages.last,
              direction == .earlier ? edge.hasEarlier : edge.hasLater,
              let cursor = direction == .earlier ? edge.before : edge.after else { return nil }
        let pinned = Set([anchor?.rowID, anchor?.focusedExchangeID].compactMap { $0 })
        while residentCount + reservedCapacity + 20 > 100 || pages.count + reservations.count >= 5 {
            // Do not evict the boundary supporting an opposite in-flight cursor.
            // Below capacity both directions can reserve independently.
            guard reservations.isEmpty else { return nil }
            let index = direction == .earlier ? pages.count - 1 : 0
            guard pages.indices.contains(index), !pages[index].exchanges.contains(where: { pinned.contains($0.id) }) else { return nil }
            pages.remove(at: index)
        }
        let reservation = CoachPageReservation(id: UUID(), request: direction == .earlier ? .before(cursor) : .after(cursor), direction: direction)
        reservations[direction] = reservation
        return reservation
    }

    mutating func complete(_ page: CoachPage, reservation: CoachPageReservation) -> Bool {
        guard reservations[reservation.direction] == reservation else { return false }
        reservations[reservation.direction] = nil
        guard identity == page.identity, page.exchanges.count <= 20,
              Set(page.exchanges.map(\.id)).count == page.exchanges.count,
              !page.exchanges.contains(where: { row in exchanges.contains(where: { $0.id == row.id }) }) else { return false }
        pages.append(page); pages.sort { ($0.exchanges.first?.sequence ?? 0) < ($1.exchanges.first?.sequence ?? 0) }
        return true
    }
    mutating func cancel(_ reservation: CoachPageReservation) {
        if reservations[reservation.direction] == reservation { reservations[reservation.direction] = nil }
    }
    mutating func invalidate(identity: CoachTimelineIdentity) {
        self.identity = identity; pages = []; reservations = [:]; viewport = .latest
    }
}
