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
        let refresh = try #require(model.apply(DiaryChanges(turnIDs: [Data.id(999)])))
        #expect(await source.refreshRequest(0) == [])
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
        // Replacement cancels the metadata refresh, but its source still owns a held read.
        await source.finishRefresh(0, CoachTimelineRefresh(identity: Data.identity, exchanges: [], latestCursor: Data.cursor(160), latestEmptySegment: nil))
        await refresh.value
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

    @Test func rebindingKeepsOldSourcesChargedAndNeverRebindsTheirOwnership() async throws {
        let oldSource = SuspendedCoachTimelineSource(), newSource = SuspendedCoachTimelineSource()
        let model = model(oldSource)
        await open(model, source: oldSource, page: Data.page(141...160))
        let oldTaskResult = model.loadEarlier(anchor: Data.anchor(150))
        let oldTask = try #require(oldTaskResult)
        let oldRequest = await oldSource.request(1)
        let newIdentity = CoachTimelineIdentity(profileID: Data.id(990), timelineGeneration: Data.id(991))
        model.rebind(identity: newIdentity, source: { try await newSource.page($0, $1) },
            refreshSource: { try await newSource.refresh($0, $1, $2) })
        #expect(model.window.reservedCapacity == 20)
        #expect(model.window.residentCount == 0)
        func page(_ range: ClosedRange<Int>) -> CoachPage {
            var page = Data.page(range); page.identity = newIdentity
            page.before?.identity = newIdentity; page.after?.identity = newIdentity
            return page
        }
        let latest = model.beginReplacement(.latest)
        _ = await newSource.request(0)
        #expect(model.window.reservedCapacity == 40)
        await newSource.finish(0, page(141...160)); await latest.value
        for (index, upper) in [140, 120, 100, 80].enumerated() {
            let anchor = Data.anchor(upper + 1)
            model.setViewport(.history(anchor), measuredAnchor: anchor)
            let result = model.loadEarlier(anchor: anchor), task = try #require(result)
            _ = await newSource.request(index + 1)
            #expect(model.window.residentCount + model.window.reservedCapacity <= 100)
            #expect(model.window.occupiedPageSlots <= 5)
            await newSource.finish(index + 1, page((upper - 19)...upper)); await task.value
        }
        let enteredOld = await oldSource.pageReadCounts()
        #expect(enteredOld.entered == 2 && enteredOld.outstanding == 1)
        #expect(oldRequest.request == .before(Data.cursor(141)))
        #expect(model.window.reservedCapacity == 20)
        let before = model.exchanges
        await oldSource.finish(1, Data.page(121...140)); await oldTask.value
        #expect(model.window.reservedCapacity == 0)
        #expect(model.exchanges == before && model.window.identity == newIdentity)
        #expect(model.error == nil && model.queryError == nil)
    }

    @Test(arguments: [false, true])
    func incomingReplyHonorsSemanticViewportWithMeasuredAnchor(readingHistory: Bool) async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        await open(model, source: source, page: Data.page(141...160))
        let anchor = Data.anchor(150)
        let viewport: CoachViewportMode = readingHistory ? .history(anchor) : .latest
        model.setViewport(viewport, visibleIDs: [Data.id(150)], measuredAnchor: anchor)
        #expect(model.window.viewportAnchor == anchor)
        let result = model.apply(DiaryChanges(turnIDs: [Data.id(160)]))
        let refresh = try #require(result)
        #expect(await source.refreshRequest(0) == [Data.id(160)])
        var changed = Data.row(160)
        changed.assistantText = "Completed incoming reply"
        await source.finishRefresh(0, CoachTimelineRefresh(identity: Data.identity, exchanges: [changed],
            latestCursor: Data.cursor(160), latestEmptySegment: nil))
        await refresh.value
        #expect(model.exchanges.first { $0.id == changed.id }?.assistantText == changed.assistantText)
        #expect(model.window.viewport == viewport)
        #expect(model.restoration == (readingHistory ? .preserve(anchor) : .none))
        #expect(model.window.pages.last?.hasLater == false)
    }

    @Test(arguments: [false, true])
    func externalTailLoadsOneBoundedLatestPage(initiallyEmpty: Bool) async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        let empty = CoachPage(identity: Data.identity, exchanges: [], before: nil, after: nil,
            hasEarlier: false, hasLater: false, earlierSegment: nil, laterSegment: nil)
        await open(model, source: source, page: initiallyEmpty ? empty : Data.page(141...160))
        if !initiallyEmpty {
            model.setViewport(.latest, visibleIDs: [Data.id(150)], measuredAnchor: Data.anchor(150))
        }
        let latestNumber = initiallyEmpty ? 1 : 161
        let result = model.apply(DiaryChanges(turnIDs: [Data.id(latestNumber)], coachLatestChanged: true))
        let update = try #require(result)
        #expect(await source.refreshRequest(0) == [])
        await source.finishRefresh(0, CoachTimelineRefresh(identity: Data.identity, exchanges: [],
            latestCursor: Data.cursor(latestNumber), latestEmptySegment: nil))
        #expect((await source.request(1)).request == .latest)
        let held = await source.pageReadCounts()
        #expect(held.entered == 2 && held.outstanding == 1)
        #expect(model.window.reservedCapacity == CoachPagedHistoryWindow.pageSize)
        var page = initiallyEmpty ? Data.page(1...1, total: 1) : Data.page(142...161, total: 161)
        page.exchanges[page.exchanges.count - 1].assistantText = "Estimate ready for review."
        await source.finish(1, page)
        await update.value
        #expect(model.exchanges == page.exchanges)
        #expect(model.window.viewport == .latest)
        #expect(model.restoration == .latest)
        #expect(model.window.pages.last?.hasLater == false)
        #expect(model.window.reservedCapacity == 0)
        let drained = await source.pageReadCounts()
        #expect(drained.entered == 2 && drained.outstanding == 0)
        #expect(model.peakCapacity <= (initiallyEmpty ? 20 : 40))
    }

    @Test func externalTailDoesNotMoveHistoryReader() async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        await open(model, source: source, page: Data.page(141...160))
        let anchor = Data.anchor(150, focus: 151)
        model.setViewport(.history(anchor), visibleIDs: [Data.id(150), Data.id(151)], measuredAnchor: anchor)
        let before = model.exchanges
        let result = model.apply(DiaryChanges(turnIDs: [Data.id(161)], coachLatestChanged: true))
        let update = try #require(result)
        #expect(await source.refreshRequest(0) == [])
        await source.finishRefresh(0, CoachTimelineRefresh(identity: Data.identity, exchanges: [],
            latestCursor: Data.cursor(161), latestEmptySegment: nil))
        await update.value
        #expect(model.exchanges == before)
        #expect(model.window.viewport == .history(anchor))
        #expect(model.restoration == .preserve(anchor))
        #expect(model.window.pages.last?.hasLater == true)
        let calls = await source.pageReadCounts()
        #expect(calls.entered == 1 && calls.outstanding == 0)
    }

    @Test func unloadedOldMutationWithUnchangedTailDoesNotReloadLatest() async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        await open(model, source: source, page: Data.page(141...160))
        model.setViewport(.latest, visibleIDs: [Data.id(150)], measuredAnchor: Data.anchor(150))
        let before = model.exchanges
        let result = model.apply(DiaryChanges(turnIDs: [Data.id(5)]))
        let update = try #require(result)
        #expect(await source.refreshRequest(0) == [])
        await source.finishRefresh(0, CoachTimelineRefresh(identity: Data.identity, exchanges: [],
            latestCursor: Data.cursor(160), latestEmptySegment: nil))
        await update.value
        #expect(model.exchanges == before)
        #expect(model.window.viewport == .latest)
        #expect(model.restoration == .none)
        let calls = await source.pageReadCounts()
        #expect(calls.entered == 1 && calls.outstanding == 0)
        #expect(model.apply(DiaryChanges()) == nil)
    }

    @Test func newerTailCoalescesWhileMetadataOwnedReplacementDrains() async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        await open(model, source: source, page: Data.page(141...160))
        model.setViewport(.latest, visibleIDs: [Data.id(150)], measuredAnchor: Data.anchor(150))
        let firstResult = model.apply(DiaryChanges(turnIDs: [Data.id(161)], coachLatestChanged: true))
        let first = try #require(firstResult)
        #expect(await source.refreshRequest(0) == [])
        await source.finishRefresh(0, CoachTimelineRefresh(identity: Data.identity, exchanges: [],
            latestCursor: Data.cursor(161), latestEmptySegment: nil))
        #expect((await source.request(1)).request == .latest)
        #expect(model.refreshTask != nil, "The refresh retains ownership while its tail page is physically held")
        let firstHeld = await source.pageReadCounts()
        #expect(firstHeld.entered == 2 && firstHeld.outstanding == 1)
        #expect(model.window.reservedCapacity == 20)
        #expect(model.window.occupiedPageSlots == 2)
        let coalescedResult = model.apply(DiaryChanges(turnIDs: [Data.id(162)], coachLatestChanged: true))
        let coalesced = try #require(coalescedResult)
        let afterCoalescing = await source.pageReadCounts()
        #expect(afterCoalescing.entered == 2 && afterCoalescing.outstanding == 1)
        #expect(model.refreshTask != nil)
        #expect(model.window.residentCount + model.window.reservedCapacity <= 100)
        // This page was read before the second accepted capture. It must drain but cannot publish.
        await source.finish(1, Data.page(142...161, total: 161))
        #expect((await source.request(2)).request == .latest)
        #expect(!model.exchanges.contains { $0.id == Data.id(161) })
        let retryHeld = await source.pageReadCounts()
        #expect(retryHeld.entered == 3 && retryHeld.outstanding == 1)
        #expect(model.window.reservedCapacity == 20)
        #expect(model.window.occupiedPageSlots == 2)
        var latest = Data.page(143...162, total: 162)
        latest.exchanges[latest.exchanges.count - 1].assistantText = "Second external capture completed"
        await source.finish(2, latest)
        await first.value
        await coalesced.value
        // Finishing the owning refresh must replay the newer coalesced metadata notification.
        #expect(await source.refreshRequest(1) == [])
        let replayResult = model.refreshTask
        let replay = try #require(replayResult)
        #expect(model.exchanges == latest.exchanges)
        #expect(model.window.reservedCapacity == 0)
        await source.finishRefresh(1, CoachTimelineRefresh(identity: Data.identity, exchanges: [],
            latestCursor: Data.cursor(162), latestEmptySegment: nil))
        await replay.value
        #expect(model.exchanges == latest.exchanges)
        #expect(model.window.viewport == .latest)
        #expect(model.restoration == .none)
        #expect(model.window.pages.last?.hasLater == false)
        #expect(model.refreshTask == nil)
        #expect(model.window.reservedCapacity == 0)
        #expect(model.window.occupiedPageSlots == 1)
        let drained = await source.pageReadCounts()
        #expect(drained.entered == 3 && drained.outstanding == 0)
        #expect(model.peakCapacity <= 40)
    }

    @Test func metadataTailNeverOverridesAnExplicitSeekRetry() async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        await open(model, source: source, page: Data.page(141...160))
        model.setViewport(.latest, visibleIDs: [Data.id(150)], measuredAnchor: Data.anchor(150))
        let seek = Task { await model.seek(.turn(Data.id(70))) }
        #expect((await source.request(1)).request == .aroundTurn(Data.id(70)))
        let deltaResult = model.apply(DiaryChanges(turnIDs: [Data.id(161)], coachLatestChanged: true))
        let delta = try #require(deltaResult)
        #expect(await source.refreshRequest(0) == [])
        // The mutation invalidates the first page value. Hold its retry after it adopts the new mutation.
        await source.finish(1, Data.page(61...80))
        #expect((await source.request(2)).request == .aroundTurn(Data.id(70)))
        await source.finishRefresh(0, CoachTimelineRefresh(identity: Data.identity, exchanges: [],
            latestCursor: Data.cursor(161), latestEmptySegment: nil))
        // The accepted metadata must finish independently, without appending a latest intent to the seek.
        await delta.value
        let held = await source.pageReadCounts()
        #expect(held.entered == 3 && held.outstanding == 1)
        #expect(model.window.reservedCapacity == 20)
        await source.finish(2, Data.page(61...80))
        await seek.value
        let anchor = CoachViewportAnchor(rowID: Data.id(70), offset: 0)
        #expect(model.window.viewport == .history(anchor))
        #expect(model.restoration == .preserve(anchor))
        #expect(model.exchanges.map(\.sequence) == (61...80).map(Int64.init))
        #expect(model.window.reservedCapacity == 0)
        #expect(model.refreshTask == nil)
        let drained = await source.pageReadCounts()
        #expect(drained.entered == 3 && drained.outstanding == 0)
        #expect(model.peakCapacity <= 40)
    }


    @Test func historyMoveWhileAutomaticTailIsHeldPreventsLatestPublication() async throws {
        let source = SuspendedCoachTimelineSource()
        let model = model(source)
        await open(model, source: source, page: Data.page(141...160))
        model.setViewport(.latest, visibleIDs: [Data.id(150)], measuredAnchor: Data.anchor(150))
        let before = model.exchanges
        let result = model.apply(DiaryChanges(turnIDs: [Data.id(161)], coachLatestChanged: true))
        let update = try #require(result)
        #expect(await source.refreshRequest(0) == [])
        await source.finishRefresh(0, CoachTimelineRefresh(identity: Data.identity, exchanges: [],
            latestCursor: Data.cursor(161), latestEmptySegment: nil))
        #expect((await source.request(1)).request == .latest)
        let anchor = Data.anchor(150, focus: 151)
        model.setViewport(.history(anchor), visibleIDs: [Data.id(150), Data.id(151)], measuredAnchor: anchor)
        #expect(model.window.reservedCapacity == 20, "The abandoned auto-read stays charged until its physical source exits")
        await source.finish(1, Data.page(142...161, total: 161))
        await update.value
        #expect(model.exchanges == before)
        #expect(model.window.viewport == .history(anchor))
        #expect(model.restoration == .preserve(anchor))
        #expect(model.window.pages.last?.hasLater == true)
        #expect(model.window.reservedCapacity == 0)
        #expect(model.refreshTask == nil)
        let drained = await source.pageReadCounts()
        #expect(drained.entered == 2 && drained.outstanding == 0)
        #expect(model.peakCapacity <= 40)
    }

}
