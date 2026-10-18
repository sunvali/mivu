import Foundation
import Testing
@testable import Mivu

enum CoachTimelineTestData {
    static let identity = CoachTimelineIdentity(profileID: id(900), timelineGeneration: id(901))
    static func id(_ number: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))! }
    static func row(_ number: Int) -> CoachExchangeSummary {
        CoachExchangeSummary(id: id(number), sequence: Int64(number), capturedAt: Date(timeIntervalSince1970: Double(number)),
            captureTimeZoneID: "UTC", segmentID: id(902), trackingDayID: id(903), displayLocalDate: "2026-10-18",
            displayTimeZoneID: "UTC", text: "Synthetic exchange \(number)", assistantText: nil, state: .completed, photos: [], receipts: [])
    }
    static func cursor(_ number: Int) -> CoachCursor { CoachCursor(identity: identity, sequence: Int64(number), turnID: id(number)) }
    static func page(_ range: ClosedRange<Int>, total: Int = 160) -> CoachPage {
        CoachPage(identity: identity, exchanges: range.map(row), before: cursor(range.lowerBound), after: cursor(range.upperBound),
            hasEarlier: range.lowerBound > 1, hasLater: range.upperBound < total, earlierSegment: nil, laterSegment: nil)
    }
    static func empty(_ boundary: Int) -> CoachEmptySegment {
        CoachEmptySegment(segmentID: id(boundary), trackingDayID: id(903), displayLocalDate: "2026-10-18", displayTimeZoneID: "UTC")
    }
    static func anchor(_ number: Int, focus: Int? = nil) -> CoachViewportAnchor {
        CoachViewportAnchor(rowID: id(number), offset: -13.5, focusedExchangeID: focus.map(id))
    }
}

private actor SuspendedCoachTimelineSource {
    struct Request: Sendable { let request: CoachPageRequest; let generation: UUID }
    private enum Failure: Error { case timedOut }
    private enum Wait: Hashable { case page(Int), request(Int), refresh(Int), refreshRequest(Int) }
    private var calls: [Request] = []
    private var pending: [Int: CheckedContinuation<CoachPage, any Error>] = [:]
    private var waiters: [Int: CheckedContinuation<Request, Never>] = [:]
    private var refreshCalls: [Set<UUID>] = []
    private var pendingRefreshes: [Int: CheckedContinuation<CoachTimelineRefresh, any Error>] = [:]
    private var refreshWaiters: [Int: CheckedContinuation<Set<UUID>, Never>] = [:]
    private var deadlines: [Wait: Task<Void, Never>] = [:]
    private var failed = false
    private let failedRequest = Request(request: .latest, generation: UUID())

    func page(_ request: CoachPageRequest, _ generation: UUID) async throws -> CoachPage {
        guard !failed else { throw Failure.timedOut }
        return try await withCheckedThrowingContinuation { continuation in
            let index = calls.count
            calls.append(Request(request: request, generation: generation))
            pending[index] = continuation
            arm(.page(index))
            disarm(.request(index))
            waiters.removeValue(forKey: index)?.resume(returning: calls[index])
        }
    }
    func request(_ index: Int) async -> Request {
        if calls.indices.contains(index) { return calls[index] }
        guard !failed else { return failedRequest }
        return await withCheckedContinuation {
            waiters[index] = $0
            arm(.request(index))
        }
    }
    func finish(_ index: Int, _ page: CoachPage) {
        disarm(.page(index))
        pending.removeValue(forKey: index)?.resume(returning: page)
    }
    func fail(_ index: Int) {
        disarm(.page(index))
        pending.removeValue(forKey: index)?.resume(throwing: CoachQueryError.invalidCursor)
    }
    func pageReadCounts() -> (entered: Int, outstanding: Int) { (calls.count, pending.count) }
    func refresh(_ ids: Set<UUID>, _: CoachTimelineIdentity, _: UUID) async throws -> CoachTimelineRefresh {
        guard !failed else { throw Failure.timedOut }
        return try await withCheckedThrowingContinuation { continuation in
            let index = refreshCalls.count
            refreshCalls.append(ids)
            pendingRefreshes[index] = continuation
            arm(.refresh(index))
            disarm(.refreshRequest(index))
            refreshWaiters.removeValue(forKey: index)?.resume(returning: ids)
        }
    }
    func refreshRequest(_ index: Int) async -> Set<UUID> {
        if refreshCalls.indices.contains(index) { return refreshCalls[index] }
        guard !failed else { return [] }
        return await withCheckedContinuation {
            refreshWaiters[index] = $0
            arm(.refreshRequest(index))
        }
    }
    func finishRefresh(_ index: Int, _ result: CoachTimelineRefresh) {
        disarm(.refresh(index))
        pendingRefreshes.removeValue(forKey: index)?.resume(returning: result)
    }
    func failRefresh(_ index: Int) {
        disarm(.refresh(index))
        pendingRefreshes.removeValue(forKey: index)?.resume(throwing: CoachQueryError.invalidCursor)
    }

    private func arm(_ wait: Wait) {
        deadlines[wait] = Task {
            do { try await Task.sleep(for: .seconds(10)) }
            catch { return }
            expire()
        }
    }
    private func disarm(_ wait: Wait) { deadlines.removeValue(forKey: wait)?.cancel() }
    private func expire() {
        guard !failed else { return }
        failed = true
        Issue.record("Timeline source did not enter or drain an operation within 10 seconds.")
        deadlines.values.forEach { $0.cancel() }
        deadlines = [:]
        let pages = pending
        let requests = waiters
        let refreshes = pendingRefreshes
        let requestedRefreshes = refreshWaiters
        pending = [:]
        waiters = [:]
        pendingRefreshes = [:]
        refreshWaiters = [:]
        pages.values.forEach { $0.resume(throwing: Failure.timedOut) }
        requests.values.forEach { $0.resume(returning: failedRequest) }
        refreshes.values.forEach { $0.resume(throwing: Failure.timedOut) }
        requestedRefreshes.values.forEach { $0.resume(returning: []) }
    }
}

@Suite @MainActor struct CoachTimelineTests {
    private typealias Data = CoachTimelineTestData
    private func model(_ source: SuspendedCoachTimelineSource) -> CoachTimelineViewModel {
        CoachTimelineViewModel(source: { try await source.page($0, $1) }, refreshSource: { try await source.refresh($0, $1, $2) })
    }
    private func open(_ model: CoachTimelineViewModel, source: SuspendedCoachTimelineSource, page: CoachPage, index: Int = 0) async {
        let task = Task { await model.loadLatest() }
        _ = await source.request(index)
        await source.finish(index, page)
        await task.value
    }

    @Test func oppositeEdgeRequestsReserveBeforeFetching() async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        let seek = Task { await model.seek(.turn(Data.id(70))) }
        _ = await source.request(0)
        await source.finish(0, Data.page(61...80))
        await seek.value
        let anchor = Data.anchor(70)
        model.setViewport(.history(anchor))
        let loadEarlierResult1 = model.loadEarlier(anchor: anchor)
        let earlier = try #require(loadEarlierResult1)
        let loadLaterResult2 = model.loadLater(anchor: anchor)
        let later = try #require(loadLaterResult2)
        let loadEarlierResult3 = model.loadEarlier(anchor: anchor)
        #expect(loadEarlierResult3 == nil)
        let loadLaterResult4 = model.loadLater(anchor: anchor)
        #expect(loadLaterResult4 == nil)
        #expect(model.window.reservations.count == 2)
        #expect(model.window.residentCount + model.window.reservedCapacity == 60)
        #expect(model.window.occupiedPageSlots == 3)
        #expect(model.window.edgeState(.earlier) == .loading)
        _ = await source.request(1)
        _ = await source.request(2)
        // Tasks may enter their independent source in either order.
        for index in [2, 1] {
            let call = await source.request(index)
            if case .before = call.request { await source.finish(index, Data.page(41...60)) }
            else { await source.finish(index, Data.page(81...100)) }
        }
        await earlier.value
        await later.value
        #expect(model.exchanges.map(\.sequence) == (41...100).map(Int64.init))
        #expect(model.restoration == .preserve(anchor))
        #expect(model.window.reservedCapacity == 0)
    }

    @Test func reservationPublishesAnchorBeforeEvictionAndKeepsItAfterCompletion() async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        await open(model, source: source, page: Data.page(141...160))
        for (index, upper) in [140, 120, 100, 80].enumerated() {
            let anchor = Data.anchor(upper + 1)
            model.setViewport(.history(anchor))
            let loadEarlierResult5 = model.loadEarlier(anchor: anchor)
            let task = try #require(loadEarlierResult5)
            _ = await source.request(index + 1)
            await source.finish(index + 1, Data.page((upper - 19)...upper))
            await task.value
        }
        let anchor = Data.anchor(70)
        model.setViewport(.history(anchor), visibleIDs: [Data.id(70), Data.id(71)])
        let loadEarlierResult6 = model.loadEarlier(anchor: anchor)
        let task = try #require(loadEarlierResult6)
        #expect(model.restoration == .preserve(anchor))
        #expect(model.window.residentCount == 80)
        #expect(model.window.reservedCapacity == 20)
        #expect(!model.exchanges.contains { $0.id == Data.id(160) })
        #expect(model.window.pages.last?.hasLater == true)
        _ = await source.request(5)
        await source.finish(5, Data.page(41...60))
        await task.value
        #expect(model.restoration == .preserve(anchor))
        #expect(model.peakCapacity <= 100)
        #expect(model.window.occupiedPageSlots == 5)
    }

    @Test func staleResponsesAfterSeekOrProfileChangeAreIgnored() async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        await open(model, source: source, page: Data.page(141...160))
        let loadEarlierResult7 = model.loadEarlier(anchor: Data.anchor(145))
        let oldEdge = try #require(loadEarlierResult7)
        _ = await source.request(1)
        let seek = Task { await model.seek(.turn(Data.id(70))) }
        _ = await source.request(2)
        await source.finish(2, Data.page(61...80))
        await seek.value
        let loadEarlierResult8 = model.loadEarlier(anchor: Data.anchor(70))
        let newEdge = try #require(loadEarlierResult8)
        _ = await source.request(3)
        await source.fail(1)
        await oldEdge.value
        #expect(model.error == nil)
        #expect(model.window.reservations[.earlier] != nil)
        await source.finish(3, Data.page(41...60))
        await newEdge.value
        let staleLatest = Task { await model.loadLatest() }
        _ = await source.request(4)
        model.invalidate(identity: Data.identity) // Same identity, new local selection epoch.
        let freshLatest = Task { await model.loadLatest() }
        #expect(model.window.reservedCapacity == 20)
        await source.fail(4) // The new source waits for the noncooperative old read to exit.
        _ = await source.request(5)
        await source.finish(5, Data.page(141...160))
        await freshLatest.value
        await staleLatest.value
        #expect(model.exchanges.first?.sequence == 141)
        #expect(model.error == nil)
        #expect(model.restoration == .latest)
        let other = CoachTimelineIdentity(profileID: Data.id(950), timelineGeneration: Data.id(951))
        let staleSeek = Task { await model.seek(.turn(Data.id(70))) }
        _ = await source.request(6)
        model.invalidate(identity: other)
        await source.finish(6, Data.page(61...80))
        await staleSeek.value
        #expect(model.window.identity == other)
        #expect(model.exchanges.isEmpty)
        #expect(model.restoration == .none)
    }

    @Test func replyWhileReadingDoesNotFollowLatest() async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        await open(model, source: source, page: Data.page(141...160))
        let loadEarlierResult9 = model.loadEarlier(anchor: Data.anchor(145))
        let edge = try #require(loadEarlierResult9)
        _ = await source.request(1)
        await source.finish(1, Data.page(121...140))
        await edge.value
        let anchor = Data.anchor(130, focus: 131)
        model.setViewport(.history(anchor), visibleIDs: [Data.id(130), Data.id(131)])
        let untouched = Array(model.exchanges.prefix(20))
        let applyResult10 = model.apply(DiaryChanges(turnIDs: [Data.id(150), Data.id(999)]))
        let refresh = try #require(applyResult10)
        #expect(await source.refreshRequest(0) == [Data.id(150)])
        var changed = Data.row(150)
        changed.assistantText = "Synthetic completed reply"
        await source.finishRefresh(0, CoachTimelineRefresh(identity: Data.identity, exchanges: [changed], latestCursor: Data.cursor(160), latestEmptySegment: nil))
        await refresh.value
        #expect(model.exchanges.first { $0.id == changed.id }?.assistantText == changed.assistantText)
        #expect(Array(model.exchanges.prefix(20)) == untouched)
        #expect(model.restoration == .preserve(anchor))
        #expect(model.window.viewport == .history(anchor))
        #expect(model.showsJumpToLatest)
        let failedJump = Task { await model.jumpToLatest() }
        _ = await source.request(2)
        await source.fail(2)
        await failedJump.value
        #expect(model.showsJumpToLatest)
        #expect(model.restoration == .preserve(anchor))
        let jump = Task { await model.jumpToLatest() }
        _ = await source.request(3)
        await source.finish(3, Data.page(141...160))
        await jump.value
        #expect(!model.showsJumpToLatest)
        #expect(model.restoration == .latest)
    }

    @Test func staleRefreshSuccessAndErrorCannotPublishAfterInvalidation() async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        await open(model, source: source, page: Data.page(141...160))
        let applyResult11 = model.apply(DiaryChanges(turnIDs: [Data.id(150)]))
        let old = try #require(applyResult11)
        _ = await source.refreshRequest(0)
        model.invalidate(identity: Data.identity)
        await open(model, source: source, page: Data.page(141...160), index: 1)
        let applyResult12 = model.apply(DiaryChanges(coachLatestChanged: true))
        let current = try #require(applyResult12)
        _ = await source.refreshRequest(1)
        await source.failRefresh(0)
        await old.value
        #expect(model.error == nil)
        await source.finishRefresh(1, CoachTimelineRefresh(identity: Data.identity, exchanges: [], latestCursor: Data.cursor(160), latestEmptySegment: Data.empty(920)))
        await current.value
        #expect(model.window.latestEmptySegment?.segmentID == Data.id(920))
        let applyResult13 = model.apply(DiaryChanges(turnIDs: [Data.id(150)]))
        let stale = try #require(applyResult13)
        _ = await source.refreshRequest(2)
        let seek = Task { await model.seek(.turn(Data.id(70))) }
        _ = await source.request(2)
        await source.finish(2, Data.page(61...80))
        await seek.value
        await source.finishRefresh(2, CoachTimelineRefresh(identity: Data.identity, exchanges: [Data.row(150)], latestCursor: Data.cursor(160), latestEmptySegment: nil))
        await stale.value
        #expect(model.exchanges.first?.sequence == 61)
        #expect(model.window.latestEmptySegment == nil)
        #expect(model.error == nil)
    }

    @Test func failedPageCanRetryAndCancellationReleasesCapacity() async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        await open(model, source: source, page: Data.page(141...160))
        let anchor = Data.anchor(145)
        let loadEarlierResult14 = model.loadEarlier(anchor: anchor)
        let first = try #require(loadEarlierResult14)
        _ = await source.request(1)
        await source.fail(1)
        await first.value
        #expect(model.window.reservedCapacity == 0)
        if case .failed = model.window.edgeState(.earlier) {} else { Issue.record("Expected retryable edge") }
        let loadEarlierResult15 = model.loadEarlier(anchor: anchor)
        let retry = try #require(loadEarlierResult15)
        _ = await source.request(2)
        retry.cancel()
        await source.finish(2, Data.page(121...140))
        await retry.value
        #expect(model.window.reservedCapacity == 0)
        #expect(model.exchanges.count == 20)
        let loadEarlierResult16 = model.loadEarlier(anchor: anchor)
        let final = try #require(loadEarlierResult16)
        _ = await source.request(3)
        await source.finish(3, Data.page(121...140))
        await final.value
        #expect(model.exchanges.count == 40)
        #expect(model.error == nil)
    }
    @Test func fullWindowDefersReplacementUntilAVisibleAnchorIsAvailable() async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        await open(model, source: source, page: Data.page(141...160))
        for (index, upper) in [140, 120, 100, 80].enumerated() {
            let loadEarlierResult17 = model.loadEarlier(anchor: Data.anchor(upper + 1))
            let task = try #require(loadEarlierResult17)
            _ = await source.request(index + 1)
            await source.finish(index + 1, Data.page((upper - 19)...upper))
            await task.value
        }
        model.setViewport(.latest)
        model.apply(DiaryChanges(turnIDs: [Data.id(999)]))
        // No source call can start until the renderer supplies a measured anchor.
        await model.jumpToLatest()
        #expect(model.isLoadDeferred)
        #expect(model.showsJumpToLatest)
        #expect(model.exchanges.count == 100)
        model.setViewport(.latest, visibleIDs: [Data.id(150)], measuredAnchor: Data.anchor(150))
        let jump = Task { await model.jumpToLatest() }
        #expect((await source.request(5)).request == .latest)
        #expect(model.restoration == .preserve(Data.anchor(150)))
        #expect(model.window.residentCount + model.window.reservedCapacity == 100)
        await source.finish(5, Data.page(141...160))
        await jump.value
        #expect(!model.isLoadDeferred)
        #expect(!model.showsJumpToLatest)
    }

    @Test func requestDiagnosticsRemainBounded() async {
        let model = CoachTimelineViewModel { _, _ in Data.page(141...160) }
        for _ in 0..<31 { await model.loadLatest() }
        #expect(model.requestedRanges.count == 16)
        #expect(model.peakCapacity <= 100)
        #expect(model.window.residentCount == 20)
    }

    @Test(arguments: [false, true])
    func replacementRetriesAfterNewerResidentMutationWithoutResurrectingRows(oldReadFails: Bool) async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        await open(model, source: source, page: Data.page(141...160))
        let held = model.beginReplacement(.latest)
        _ = await source.request(1)
        let refreshResult = model.apply(DiaryChanges(turnIDs: [Data.id(150), Data.id(160)]))
        let refresh = try #require(refreshResult)
        #expect(await source.refreshRequest(0) == [Data.id(150), Data.id(160)])
        var updated = Data.row(150)
        updated.assistantText = "New committed reply"
        await source.finishRefresh(0, CoachTimelineRefresh(identity: Data.identity, exchanges: [updated], latestCursor: Data.cursor(159), latestEmptySegment: nil))
        await refresh.value
        #expect(!model.exchanges.contains { $0.id == Data.id(160) })
        #expect(model.exchanges.first { $0.id == Data.id(150) }?.assistantText == updated.assistantText)
        #expect(model.showsJumpToLatest)
        if oldReadFails { await source.fail(1) }
        else { await source.finish(1, Data.page(141...160)) }
        let retry = await source.request(2)
        #expect(retry.request == .latest)
        #expect(!model.exchanges.contains { $0.id == Data.id(160) })
        #expect(model.exchanges.first { $0.id == Data.id(150) }?.assistantText == updated.assistantText)
        #expect(model.showsJumpToLatest)
        #expect(model.error == nil)
        var fresh = Data.page(140...159, total: 159)
        fresh.exchanges[fresh.exchanges.firstIndex { $0.id == updated.id }!] = updated
        await source.finish(2, fresh)
        await held.value
        #expect(!model.exchanges.contains { $0.id == Data.id(160) })
        #expect(model.exchanges.first { $0.id == Data.id(150) }?.assistantText == updated.assistantText)
        #expect(!model.showsJumpToLatest)
        #expect(model.window.reservedCapacity == 0)
    }

    @Test func supersededReplacementsCoalesceUntilActualSourceExit() async {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        await open(model, source: source, page: Data.page(141...160))
        let held = model.beginReplacement(.latest)
        _ = await source.request(1)
        var callers: [Task<Void, Never>] = []
        for number in 70...75 { callers.append(model.beginReplacement(.aroundTurn(Data.id(number)))) }
        let heldCounts = await source.pageReadCounts()
        #expect(heldCounts.entered == 2) // Initial latest and exactly one held replacement.
        #expect(heldCounts.outstanding == 1)
        #expect(model.window.reservedCapacity == heldCounts.outstanding * 20)
        #expect(model.window.residentCount + model.window.reservedCapacity <= 100)
        await source.finish(1, Data.page(141...160))
        let latestIntent = await source.request(2)
        #expect(latestIntent.request == .aroundTurn(Data.id(75)))
        let nextCounts = await source.pageReadCounts()
        #expect(nextCounts.entered == 3)
        #expect(nextCounts.outstanding == 1)
        #expect(model.window.reservedCapacity == nextCounts.outstanding * 20)
        #expect(model.window.occupiedPageSlots <= 5)
        await source.finish(2, Data.page(61...80))
        await held.value
        for caller in callers { await caller.value }
        let finishedCounts = await source.pageReadCounts()
        #expect(finishedCounts.entered == 3)
        #expect(finishedCounts.outstanding == 0)
        #expect(model.window.reservedCapacity == 0)
        #expect(model.exchanges.first?.sequence == 61)
        #expect(model.restoration == .preserve(CoachViewportAnchor(rowID: Data.id(75), offset: 0)))
    }

    @Test(arguments: [false, true])
    func coalescedDisjointDeltasRetryAllDiscardedResidentIDs(firstTurnDeleted: Bool) async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        await open(model, source: source, page: Data.page(141...160))
        let firstResult = model.apply(DiaryChanges(turnIDs: [Data.id(150)], coachLatestChanged: true))
        let first = try #require(firstResult)
        #expect(await source.refreshRequest(0) == [Data.id(150)])
        let coalescedResult = model.apply(DiaryChanges(turnIDs: [Data.id(151)]))
        let coalesced = try #require(coalescedResult)
        var changed150 = Data.row(150)
        changed150.assistantText = "First committed reply"
        var changed151 = Data.row(151)
        changed151.assistantText = "Second committed reply"
        await source.finishRefresh(0, CoachTimelineRefresh(identity: Data.identity,
            exchanges: firstTurnDeleted ? [] : [changed150], latestCursor: Data.cursor(160), latestEmptySegment: Data.empty(920)))
        #expect(await source.refreshRequest(1) == [Data.id(150), Data.id(151)])
        await first.value
        await coalesced.value
        let retryResult = model.refreshTask
        let retry = try #require(retryResult)
        let retryRows = firstTurnDeleted ? [changed151] : [changed150, changed151]
        await source.finishRefresh(1, CoachTimelineRefresh(identity: Data.identity, exchanges: retryRows,
            latestCursor: Data.cursor(160), latestEmptySegment: Data.empty(920)))
        await retry.value
        #expect(model.exchanges.first { $0.id == Data.id(151) }?.assistantText == changed151.assistantText)
        if firstTurnDeleted { #expect(!model.exchanges.contains { $0.id == Data.id(150) }) }
        else { #expect(model.exchanges.first { $0.id == Data.id(150) }?.assistantText == changed150.assistantText) }
        #expect(model.window.latestEmptySegment?.segmentID == Data.id(920))
        #expect(model.exchanges.count == (firstTurnDeleted ? 19 : 20))
        #expect(model.refreshTask == nil)
        #expect(model.error == nil)
    }

}
