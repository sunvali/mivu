import Foundation

struct CoachViewportAnchor: Equatable, Sendable {
    var rowID: UUID
    var offset: Double
    var focusedExchangeID: UUID?
}

enum CoachViewportMode: Equatable, Sendable { case latest, history(CoachViewportAnchor) }
enum CoachViewportRestoration: Equatable, Sendable { case none, latest, preserve(CoachViewportAnchor) }
enum CoachPageDirection: Hashable, Sendable { case earlier, later }
enum CoachPageEdgeState: Equatable, Sendable { case available, loading, exhausted, failed(String) }

struct CoachPageReservation: Equatable, Sendable {
    var id: UUID
    var request: CoachPageRequest
    var direction: CoachPageDirection
}

struct CoachPagedHistoryWindow {
    static let pageSize = 20
    static let maximumPages = 5
    static let maximumExchanges = 100
    private(set) var pages: [CoachPage] = []
    private(set) var reservations: [CoachPageDirection: CoachPageReservation] = [:]
    private(set) var identity: CoachTimelineIdentity?
    private(set) var viewport: CoachViewportMode = .latest
    private(set) var viewportAnchor: CoachViewportAnchor?
    private(set) var visibleIDs: Set<UUID> = []
    private(set) var isInteracting = false
    private(set) var replacementReserved = false
    private(set) var retiredReadIDs: Set<UUID> = []
    private var failures: [CoachPageDirection: String] = [:]
    var exchanges: [CoachExchangeSummary] { pages.flatMap(\.exchanges) }
    var reservedCapacity: Int { (reservations.count + retiredReadIDs.count + (replacementReserved ? 1 : 0)) * Self.pageSize }
    var residentCount: Int { pages.reduce(0) { $0 + $1.exchanges.count } }
    var occupiedPageSlots: Int { pages.count + reservations.count + retiredReadIDs.count + (replacementReserved ? 1 : 0) }
    /// True only for the newest exchange of the whole conversation, not of a mid-history page.
    func isLatest(_ id: UUID) -> Bool { pages.last?.hasLater == false && exchanges.last?.id == id }
    var latestEmptySegment: CoachEmptySegment? { pages.last.flatMap { $0.hasLater ? nil : $0.latestEmptySegment } }

    func edgeState(_ direction: CoachPageDirection) -> CoachPageEdgeState {
        if reservations[direction] != nil { return .loading }
        if let failure = failures[direction] { return .failed(failure) }
        guard let edge = direction == .earlier ? pages.first : pages.last else { return .exhausted }
        return (direction == .earlier ? edge.hasEarlier : edge.hasLater) ? .available : .exhausted
    }

    @discardableResult mutating func reset(_ page: CoachPage, request: CoachPageRequest = .latest) -> Bool {
        guard Self.valid(page, for: request), identity == nil || identity == page.identity else { return false }
        identity = page.identity
        pages = [page]
        releaseReservations()
        return true
    }

    mutating func setViewport(_ value: CoachViewportMode, visibleIDs: Set<UUID> = [], isInteracting: Bool = false, measuredAnchor: CoachViewportAnchor? = nil) {
        viewport = value
        if case .history(let anchor) = value { viewportAnchor = anchor } else { viewportAnchor = measuredAnchor }
        self.visibleIDs = visibleIDs
        self.isInteracting = isInteracting
    }

    mutating func reserve(_ direction: CoachPageDirection, anchor: CoachViewportAnchor?) -> CoachPageReservation? {
        guard !replacementReserved, reservations[direction] == nil,
              let edge = direction == .earlier ? pages.first : pages.last,
              direction == .earlier ? edge.hasEarlier : edge.hasLater,
              let cursor = direction == .earlier ? edge.before : edge.after,
              makeRoom(anchor: anchor, evictFrom: direction == .earlier ? .later : .earlier) else { return nil }
        let reservation = CoachPageReservation(id: UUID(), request: direction == .earlier ? .before(cursor) : .after(cursor), direction: direction)
        reservations[direction] = reservation
        failures[direction] = nil
        return reservation
    }

    // A replacement result also consumes one page while the reader remains resident.
    mutating func reserveReplacement(anchor: CoachViewportAnchor?) -> Bool {
        guard !replacementReserved, reservations.isEmpty,
              makeRoom(anchor: anchor, evictFrom: .earlier, allowEitherEdge: true) else { return false }
        replacementReserved = true
        return true
    }

    private mutating func makeRoom(anchor: CoachViewportAnchor?, evictFrom direction: CoachPageDirection, allowEitherEdge: Bool = false) -> Bool {
        guard residentCount + reservedCapacity + Self.pageSize > Self.maximumExchanges || occupiedPageSlots >= Self.maximumPages else { return true }
        guard let anchor, !isInteracting, reservations.isEmpty else { return false }
        let pinned = visibleIDs.union([anchor.rowID]).union(anchor.focusedExchangeID.map { [$0] } ?? [])
            .union([viewportAnchor?.rowID, viewportAnchor?.focusedExchangeID].compactMap { $0 })
        guard pages.count > 1 else { return false }
        let preferred = direction == .earlier ? 0 : pages.count - 1
        let candidates = allowEitherEdge ? [preferred, preferred == 0 ? pages.count - 1 : 0] : [preferred]
        guard let index = candidates.first(where: { index in !pages[index].exchanges.contains(where: { pinned.contains($0.id) }) }) else { return false }
        pages.remove(at: index)
        let removedDirection: CoachPageDirection = index == 0 ? .earlier : .later
        if removedDirection == .earlier {
            pages[0].hasEarlier = true
        } else {
            pages[pages.count - 1].hasLater = true
            pages[pages.count - 1].latestEmptySegment = nil
        }
        failures[removedDirection] = nil
        return true
    }

    @discardableResult mutating func complete(_ page: CoachPage, reservation: CoachPageReservation) -> Bool {
        guard reservations[reservation.direction] == reservation else { return false }
        reservations[reservation.direction] = nil
        guard !pages.isEmpty, identity == page.identity, Self.valid(page, for: reservation.request),
              !page.exchanges.contains(where: { row in exchanges.contains(where: { $0.id == row.id || $0.sequence == row.sequence }) }) else {
            failures[reservation.direction] = "The conversation page was invalid. Try again."
            return false
        }
        failures[reservation.direction] = nil
        if page.exchanges.isEmpty {
            if reservation.direction == .earlier {
                pages[0].hasEarlier = false
                pages[0].earlierSegment = nil
            } else {
                pages[pages.count - 1].hasLater = false
                pages[pages.count - 1].laterSegment = nil
                pages[pages.count - 1].latestEmptySegment = page.latestEmptySegment
            }
        } else if reservation.direction == .earlier {
            pages.insert(page, at: 0)
        } else {
            if !pages.isEmpty { pages[pages.count - 1].latestEmptySegment = nil }
            pages.append(page)
        }
        return true
    }

    mutating func fail(_ reservation: CoachPageReservation, message: String) {
        guard reservations[reservation.direction] == reservation else { return }
        reservations[reservation.direction] = nil
        failures[reservation.direction] = message
    }
    mutating func cancel(_ reservation: CoachPageReservation) {
        if reservations[reservation.direction] == reservation { reservations[reservation.direction] = nil }
    }
    mutating func retire(_ reservation: CoachPageReservation) {
        guard reservations[reservation.direction] == reservation else { return }
        reservations[reservation.direction] = nil
        retiredReadIDs.insert(reservation.id)
    }
    mutating func finishRead(_ reservation: CoachPageReservation) {
        cancel(reservation)
        retiredReadIDs.remove(reservation.id)
    }
    mutating func releaseReplacement() { replacementReserved = false }
    mutating func releaseReservations() {
        reservations = [:]
        replacementReserved = false
        failures = [:]
    }

    /// Only requested resident IDs can enter a delta; absence means deletion.
    @discardableResult mutating func refresh(_ result: CoachTimelineRefresh, requestedIDs: Set<UUID>) -> Bool {
        let previousRows = exchanges
        let resident = Dictionary(uniqueKeysWithValues: previousRows.map { ($0.id, $0.sequence) })
        let returnedIDs = Set(result.exchanges.map(\.id))
        let retained = previousRows.filter { !requestedIDs.contains($0.id) || returnedIDs.contains($0.id) }
        if let last = retained.last {
            guard let cursor = result.latestCursor, cursor.sequence >= last.sequence,
                  cursor.sequence != last.sequence || cursor.turnID == last.id else { return false }
        }
        guard result.identity == identity, requestedIDs.count <= Self.maximumExchanges,
              result.exchanges.count <= requestedIDs.count,
              Set(result.exchanges.map(\.id)).count == result.exchanges.count,
              result.exchanges.allSatisfy({ requestedIDs.contains($0.id) && resident[$0.id] == $0.sequence }),
              result.latestCursor == nil || (result.latestCursor?.identity == identity && (result.latestCursor?.sequence ?? 0) > 0) else { return false }
        let updates = Dictionary(uniqueKeysWithValues: result.exchanges.map { ($0.id, $0) })
        for index in pages.indices {
            pages[index].exchanges = pages[index].exchanges.compactMap { row in
                requestedIDs.contains(row.id) ? updates[row.id] : row
            }
            pages[index].before = pages[index].exchanges.first.map { Self.cursor($0, identity: result.identity) }
            pages[index].after = pages[index].exchanges.last.map { Self.cursor($0, identity: result.identity) }
            pages[index].latestEmptySegment = nil
        }
        pages.removeAll { $0.exchanges.isEmpty }
        if !pages.isEmpty {
            let index = pages.count - 1
            pages[index].hasLater = pages[index].after != result.latestCursor
            if !pages[index].hasLater { pages[index].latestEmptySegment = result.latestEmptySegment }
        } else if result.latestCursor == nil {
            pages = [CoachPage(identity: result.identity, exchanges: [], before: nil, after: nil, hasEarlier: false, hasLater: false,
                               earlierSegment: nil, laterSegment: nil, latestEmptySegment: result.latestEmptySegment)]
        }
        let remainingIDs = Set(exchanges.map(\.id))
        visibleIDs.formIntersection(remainingIDs)
        if case .history(var anchor) = viewport {
            if !remainingIDs.contains(anchor.rowID), let sequence = resident[anchor.rowID],
               let fallback = exchanges.first(where: { $0.sequence >= sequence }) ?? exchanges.last {
                anchor.rowID = fallback.id
            }
            if let focus = anchor.focusedExchangeID, !remainingIDs.contains(focus) { anchor.focusedExchangeID = nil }
            viewport = .history(anchor)
            viewportAnchor = anchor
        }
        return true
    }

    mutating func invalidate(identity: CoachTimelineIdentity, preserveReplacement: Bool = false) {
        let replacementInFlight = preserveReplacement && replacementReserved
        self.identity = identity
        pages = []
        releaseReservations()
        replacementReserved = replacementInFlight
        viewport = .latest
        viewportAnchor = nil
        visibleIDs = []
        isInteracting = false
    }

    static func valid(_ page: CoachPage, for request: CoachPageRequest) -> Bool {
        let rows = page.exchanges
        guard rows.count <= pageSize, Set(rows.map(\.id)).count == rows.count,
              rows.allSatisfy({ $0.sequence > 0 }),
              zip(rows, rows.dropFirst()).allSatisfy({ $0.sequence < $1.sequence }),
              page.before == rows.first.map({ cursor($0, identity: page.identity) }),
              page.after == rows.last.map({ cursor($0, identity: page.identity) }),
              !page.hasLater || page.latestEmptySegment == nil else { return false }
        if rows.isEmpty, page.hasEarlier || page.hasLater { return false }
        switch request {
        case .latest: return !page.hasLater
        case .before(let cursor):
            return cursor.identity == page.identity && rows.allSatisfy { $0.sequence < cursor.sequence } && page.latestEmptySegment == nil
        case .after(let cursor):
            return cursor.identity == page.identity && rows.allSatisfy { $0.sequence > cursor.sequence }
        case .aroundTurn(let id): return rows.contains { $0.id == id }
        case .atDay(let id): return rows.contains { $0.trackingDayID == id }
        }
    }

    private static func cursor(_ row: CoachExchangeSummary, identity: CoachTimelineIdentity) -> CoachCursor {
        CoachCursor(identity: identity, sequence: row.sequence, turnID: row.id)
    }
}
