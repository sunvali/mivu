import Foundation

/// Bounded paging orchestration, shared by the feasibility surface and Task 11.
/// Storage activation and production view wiring remain separate integration work.
@MainActor @Observable final class CoachTimelineViewModel {
    typealias PageSource = @Sendable (CoachPageRequest, UUID) async throws -> CoachPage
    private(set) var window = CoachPagedHistoryWindow()
    private(set) var restoration: CoachViewportRestoration = .none
    private(set) var revision = 0
    private(set) var requestedRanges: [[Int64]] = []
    private(set) var peakCapacity = 0
    private(set) var hasNewReply = false
    private(set) var error: String?
    private let source: PageSource
    private var generation = UUID()
    private var requests: [CoachPageDirection: Task<Void, Never>] = [:]
    var exchanges: [CoachExchangeSummary] { window.exchanges }

    init(source: @escaping PageSource) { self.source = source }

    func loadLatest() async {
        let current = generation
        do {
            let page = try await source(.latest, current)
            guard current == generation, !Task.isCancelled else { return }
            window.reset(page); record(page); restoration = .latest; revision += 1
        } catch { self.error = String(describing: error) }
    }
    func loadEarlier(anchor: CoachViewportAnchor?) { load(.earlier, anchor: anchor) }
    func loadLater(anchor: CoachViewportAnchor?) { load(.later, anchor: anchor) }
    private func load(_ direction: CoachPageDirection, anchor: CoachViewportAnchor?) {
        guard requests[direction] == nil, let reservation = window.reserve(direction, anchor: anchor) else { return }
        peakCapacity = max(peakCapacity, window.residentCount + window.reservedCapacity)
        let current = generation
        requests[direction] = Task {
            defer { if current == generation { requests[direction] = nil } }
            do {
                let page = try await source(reservation.request, current)
                guard current == generation, !Task.isCancelled else { return }
                if window.complete(page, reservation: reservation) {
                    let currentAnchor: CoachViewportAnchor? = if case .history(let value) = window.viewport { value } else { anchor }
                    record(page); restoration = currentAnchor.map(CoachViewportRestoration.preserve) ?? .none; revision += 1
                }
            } catch {
                if current == generation { window.cancel(reservation); self.error = String(describing: error) }
            }
        }
    }
    func setViewport(_ mode: CoachViewportMode) { window.setViewport(mode) }
    func seek(_ target: CoachSeekTarget) async {
        if let identity = window.identity { invalidate(identity: identity) }
        let current = generation
        do {
            let request: CoachPageRequest = switch target { case .turn(let id): .aroundTurn(id); case .day(let id): .atDay(id) }
            let page = try await source(request, current)
            guard current == generation, !Task.isCancelled else { return }
            window.reset(page); record(page); revision += 1
        } catch { self.error = String(describing: error) }
    }
    func apply(_ changes: DiaryChanges) {
        // This early contract only signals an off-window update. Task 11 performs
        // indexed visible-row refresh when mutation integration is available.
        if !changes.turnIDs.isEmpty { hasNewReply = true }
    }
    func jumpToLatest() async { await loadLatest(); hasNewReply = false }
    func invalidate(identity: CoachTimelineIdentity) {
        generation = UUID(); requests.values.forEach { $0.cancel() }; requests = [:]
        window.invalidate(identity: identity); restoration = .none; revision += 1
    }
    private func record(_ page: CoachPage) {
        requestedRanges.append(page.exchanges.map(\.sequence))
        peakCapacity = max(peakCapacity, window.residentCount + window.reservedCapacity)
    }
}
