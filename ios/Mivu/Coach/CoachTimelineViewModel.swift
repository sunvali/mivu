import Foundation

/// Bounded indexed deltas, with latest-edge metadata from the same read transaction.
struct CoachTimelineRefresh: Sendable {
    var identity: CoachTimelineIdentity
    var exchanges: [CoachExchangeSummary]
    var latestCursor: CoachCursor?
    var latestEmptySegment: CoachEmptySegment?
}

@MainActor @Observable final class CoachTimelineViewModel {
    typealias PageSource = @Sendable (CoachPageRequest, UUID) async throws -> CoachPage
    typealias RefreshSource = @Sendable (Set<UUID>, CoachTimelineIdentity, UUID) async throws -> CoachTimelineRefresh
    private(set) var window = CoachPagedHistoryWindow()
    private(set) var restoration: CoachViewportRestoration = .none
    private(set) var revision = 0
    private(set) var requestedRanges: [[Int64]] = []
    private(set) var peakCapacity = 0
    private(set) var hasNewReply = false
    private(set) var isLoadDeferred = false
    private(set) var error: String?
    private let source: PageSource
    private let refreshSource: RefreshSource?
    private var generation = UUID()
    private var requests: [CoachPageDirection: Task<Void, Never>] = [:]
    private var requestIDs: [CoachPageDirection: UUID] = [:]
    private(set) var refreshTask: Task<Void, Never>?
    private var refreshID: UUID?
    private var replacementID: UUID?
    private struct ReplacementIntent {
        var request: CoachPageRequest
        var generation: UUID
        var identity: CoachTimelineIdentity?
        var id = UUID()
    }
    private var pendingReplacement: ReplacementIntent?
    private var replacementTask: Task<Void, Never>?
    private var retiredRequests: [UUID: Task<Void, Never>] = [:]
    private var mutationGeneration = UUID()
    var exchanges: [CoachExchangeSummary] { window.exchanges }
    var showsJumpToLatest: Bool { hasNewReply || window.pages.last?.hasLater == true }

    convenience init(source: @escaping PageSource) { self.init(source: source, refreshSource: nil) }

    init(source: @escaping PageSource, refreshSource: RefreshSource?) {
        self.source = source
        self.refreshSource = refreshSource
    }

    func loadLatest() async { await beginReplacement(.latest).value }
    func jumpToLatest() async { await loadLatest() }
    func seek(_ target: CoachSeekTarget) async {
        let request: CoachPageRequest = switch target { case .turn(let id): .aroundTurn(id); case .day(let id): .atDay(id) }
        await beginReplacement(request).value
    }

    /// New navigation coalesces to one pending intent while an older read drains.
    @discardableResult func beginReplacement(_ request: CoachPageRequest) -> Task<Void, Never> {
        supersede()
        pendingReplacement = ReplacementIntent(request: request, generation: generation, identity: window.identity)
        if let replacementTask { return replacementTask }
        let task = Task {
            await drainReplacements()
            replacementTask = nil
        }
        replacementTask = task
        return task
    }

    private func drainReplacements() async {
        while let intent = pendingReplacement {
            pendingReplacement = nil
            guard isCurrent(intent.generation, identity: intent.identity) else { continue }
            replacementID = intent.id
            isLoadDeferred = false
            preserveReader()
            guard window.reserveReplacement(anchor: window.viewportAnchor) else {
                replacementID = nil
                isLoadDeferred = true
                continue
            }
            recordCapacity()
            revision += 1
            let mutation = mutationGeneration
            do {
                let page = try await source(intent.request, intent.generation)
                window.releaseReplacement()
                guard isCurrent(intent.generation, identity: intent.identity), replacementID == intent.id else { continue }
                guard mutation == mutationGeneration else {
                    // The accepted intent survives, but its pre-mutation value cannot publish.
                    pendingReplacement = intent
                    continue
                }
                guard window.reset(page, request: intent.request) else {
                    error = "The conversation page was invalid. Try again."
                    continue
                }
                error = nil
                record(page)
                switch intent.request {
                case .latest:
                    window.setViewport(.latest)
                    restoration = .latest
                    hasNewReply = false
                case .aroundTurn(let id):
                    let anchor = CoachViewportAnchor(rowID: id, offset: 0)
                    window.setViewport(.history(anchor))
                    restoration = .preserve(anchor)
                case .atDay(let id):
                    if let row = page.exchanges.first(where: { $0.trackingDayID == id }) {
                        let anchor = CoachViewportAnchor(rowID: row.id, offset: 0)
                        window.setViewport(.history(anchor))
                        restoration = .preserve(anchor)
                    }
                default: break
                }
                revision += 1
            } catch {
                window.releaseReplacement()
                guard isCurrent(intent.generation, identity: intent.identity), replacementID == intent.id else { continue }
                if mutation != mutationGeneration { pendingReplacement = intent }
                else { self.error = String(describing: error) }
            }
            replacementID = nil
        }
        replacementID = nil
    }

    @discardableResult func loadEarlier(anchor: CoachViewportAnchor?) -> Task<Void, Never>? { load(.earlier, anchor: anchor) }
    @discardableResult func loadLater(anchor: CoachViewportAnchor?) -> Task<Void, Never>? { load(.later, anchor: anchor) }
    private func load(_ direction: CoachPageDirection, anchor: CoachViewportAnchor?) -> Task<Void, Never>? {
        guard requests[direction] == nil, replacementTask == nil else { return nil }
        // This intent precedes reservation-time eviction and remains through layout changes.
        if let anchor { restoration = .preserve(anchor) }
        else { preserveReader() }
        guard let reservation = window.reserve(direction, anchor: anchor ?? window.viewportAnchor) else { return nil }
        let current = generation
        let identity = window.identity
        requestIDs[direction] = reservation.id
        recordCapacity()
        revision += 1
        requests[direction] = Task {
            defer {
                window.finishRead(reservation)
                retiredRequests[reservation.id] = nil
                if current == generation, requestIDs[direction] == reservation.id {
                    requests[direction] = nil
                    requestIDs[direction] = nil
                }
            }
            guard !Task.isCancelled else { return }
            do {
                let page = try await source(reservation.request, current)
                guard isCurrent(current, identity: identity), requestIDs[direction] == reservation.id, !Task.isCancelled else { return }
                if window.complete(page, reservation: reservation) {
                    error = nil
                    record(page)
                    // A deliberate viewport move may have superseded the original anchor.
                    preserveReader()
                } else if case .failed(let message) = window.edgeState(direction) { error = message }
                revision += 1
            } catch {
                guard isCurrent(current, identity: identity), requestIDs[direction] == reservation.id, !Task.isCancelled else { return }
                let message = String(describing: error)
                window.fail(reservation, message: message)
                self.error = message
                revision += 1
            }
        }
        return requests[direction]
    }

    func setViewport(_ mode: CoachViewportMode, visibleIDs: Set<UUID> = [], isInteracting: Bool = false, measuredAnchor: CoachViewportAnchor? = nil) {
        window.setViewport(mode, visibleIDs: visibleIDs, isInteracting: isInteracting, measuredAnchor: measuredAnchor)
        switch mode {
        case .latest: restoration = .none
        case .history(let anchor): restoration = .preserve(anchor)
        }
    }

    @discardableResult func apply(_ changes: DiaryChanges) -> Task<Void, Never>? {
        if changes.profileReset || changes.timelineReset {
            if let identity = window.identity { invalidate(identity: identity) }
            return nil
        }
        guard !changes.turnIDs.isEmpty || changes.coachLatestChanged else { return nil }
        hasNewReply = true
        mutationGeneration = UUID()
        // Keep cancelled source work charged until its actual completion.
        retirePagingRequests()
        guard let identity = window.identity, let refreshSource else { return nil }
        let current = generation
        let operation = UUID()
        // Retain at most one bounded delta request, even if its source ignores cancellation.
        // A pending request is coalesced rather than accumulating detached result buffers.
        if refreshTask != nil {
            let residentIDs = Set(exchanges.map(\.id))
            pendingChangedIDs.formIntersection(residentIDs)
            pendingChangedIDs.formUnion(changes.turnIDs.intersection(residentIDs))
            pendingLatestChange = pendingLatestChange || changes.coachLatestChanged
            return refreshTask
        }
        let ids = changes.turnIDs.intersection(Set(exchanges.map(\.id)))
        let mutation = mutationGeneration
        refreshID = operation
        refreshTask = Task {
            defer {
                if isCurrent(current, identity: identity), refreshID == operation {
                    if mutation != mutationGeneration {
                        let residentIDs = Set(exchanges.map(\.id))
                        pendingChangedIDs.formIntersection(residentIDs)
                        pendingChangedIDs.formUnion(ids.intersection(residentIDs))
                        // Every delta source reads latest metadata, even for off-window IDs.
                        pendingLatestChange = true
                    }
                    refreshTask = nil
                    refreshID = nil
                    if !pendingChangedIDs.isEmpty || pendingLatestChange {
                        let pending = DiaryChanges(turnIDs: pendingChangedIDs, coachLatestChanged: pendingLatestChange)
                        pendingChangedIDs = []
                        pendingLatestChange = false
                        apply(pending)
                    }
                }
            }
            do {
                let result = try await refreshSource(ids, identity, current)
                guard isCurrent(current, identity: identity), refreshID == operation, mutation == mutationGeneration, !Task.isCancelled else { return }
                guard window.refresh(result, requestedIDs: ids) else {
                    error = "The conversation update was invalid. Try again."
                    return
                }
                error = nil
                preserveReader()
                revision += 1
            } catch {
                guard isCurrent(current, identity: identity), refreshID == operation, mutation == mutationGeneration, !Task.isCancelled else { return }
                self.error = String(describing: error)
            }
        }
        return refreshTask
    }

    private var pendingChangedIDs: Set<UUID> = []
    private var pendingLatestChange = false
    func invalidate(identity: CoachTimelineIdentity) {
        supersede()
        window.invalidate(identity: identity, preserveReplacement: replacementTask != nil)
        restoration = .none
        hasNewReply = false
        isLoadDeferred = false
        error = nil
        requestedRanges = []
        peakCapacity = 0
        revision += 1
    }
    private func supersede() {
        generation = UUID()
        retirePagingRequests()
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = nil
        pendingChangedIDs = []
        pendingLatestChange = false
        pendingReplacement = nil
    }
    private func retirePagingRequests() {
        for reservation in Array(window.reservations.values) {
            window.retire(reservation)
            if let task = requests[reservation.direction] {
                retiredRequests[reservation.id] = task
                task.cancel()
            }
        }
        requests = [:]
        requestIDs = [:]
    }
    private func isCurrent(_ current: UUID, identity: CoachTimelineIdentity?) -> Bool {
        current == generation && window.identity == identity
    }
    private func preserveReader() {
        if let anchor = window.viewportAnchor { restoration = .preserve(anchor) }
    }
    private func recordCapacity() { peakCapacity = max(peakCapacity, window.residentCount + window.reservedCapacity) }
    private func record(_ page: CoachPage) {
        requestedRanges.append(page.exchanges.map(\.sequence))
        if requestedRanges.count > 16 { requestedRanges.removeFirst(requestedRanges.count - 16) }
        recordCapacity()
    }
}
