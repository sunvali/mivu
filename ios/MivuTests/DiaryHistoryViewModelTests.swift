import Foundation
import Testing
@testable import Mivu

@MainActor @Suite struct DiaryHistoryViewModelTests {
    @Test func olderNewerAndLatestNavigateSeventyFiveDaysWithOneResidentPage() async throws {
        let f = HistoryLoader(), model = DiaryHistoryViewModel(load: { try await f.load($0, $1) })
        await model.setScope(f.scope)
        try expectPage(model, f, 0..<30)
        await model.navigate(.earlier); try expectPage(model, f, 30..<60)
        await model.navigate(.earlier); try expectPage(model, f, 60..<75)
        await model.navigate(.newer); try expectPage(model, f, 30..<60)
        await model.navigate(.newer); try expectPage(model, f, 0..<30)
        await model.navigate(.earlier); await model.navigate(.latest); try expectPage(model, f, 0..<30)
        let beforeReadCount = await f.readCount
        await model.setScope(f.scope)
        let readCount = await f.readCount
        #expect(readCount == beforeReadCount)
    }
    @Test func exhaustedEdgesPerformNoQuery() async {
        let f = HistoryLoader(), model = DiaryHistoryViewModel(load: { try await f.load($0, $1) })
        await model.setScope(f.scope)
        var beforeReadCount = await f.readCount
        await model.navigate(.newer); await model.navigate(.latest)
        var readCount = await f.readCount
        #expect(readCount == beforeReadCount)
        await model.navigate(.earlier); await model.navigate(.earlier)
        beforeReadCount = await f.readCount
        await model.navigate(.earlier)
        readCount = await f.readCount
        #expect(readCount == beforeReadCount)
    }
    @Test func onlyOneRequestRunsAndRepeatedNavigationDoesNotAdvanceTwice() async throws {
        let f = HistoryLoader(), model = DiaryHistoryViewModel(load: { try await f.load($0, $1) })
        await model.setScope(f.scope); await f.pauseNext()
        let task = Task { await model.navigate(.earlier) }
        await f.waitForPause()
        await model.navigate(.earlier); await model.navigate(.latest)
        await f.resume(); await task.value
        try expectPage(model, f, 30..<60)
        let maxConcurrentLoads = await f.maxConcurrentLoads
        #expect(maxConcurrentLoads == 1)
    }
    @Test func navigationFailurePreservesRowsAndRetryTarget() async throws {
        let f = HistoryLoader(), model = DiaryHistoryViewModel(load: { try await f.load($0, $1) })
        await model.setScope(f.scope); await f.failNext()
        await model.navigate(.earlier)
        try expectPage(model, f, 0..<30); #expect(model.errorMessage != nil)
        await model.retry(); try expectPage(model, f, 30..<60)
        await model.navigate(.newer); try expectPage(model, f, 0..<30)
    }
    @Test func scopeChangeRejectsLatePageAndError() async throws {
        for fail in [false, true] {
            for variation in 0..<4 {
                let f = HistoryLoader(), model = DiaryHistoryViewModel(load: { try await f.load($0, $1) })
                await model.setScope(f.scope); await f.pauseNext(fail: fail)
                let task = Task { await model.navigate(.earlier) }; await f.waitForPause()
                task.cancel()
                var scope = f.scope
                switch variation {
                case 0: scope.selection = DiarySelectionOwnership(identity: .init(profileID: UUID(), timelineGeneration: UUID()), selectionEpoch: 2)
                case 1: scope.localDate = "2027-01-15"
                case 2: scope.selection = DiarySelectionOwnership(identity: .init(profileID: scope.selection.identity.profileID, timelineGeneration: UUID()), selectionEpoch: 1)
                default: scope.changeGeneration += 1
                }
                await model.setScope(scope)
                #expect(!model.canLoadEarlier && !model.canLoadNewer)
                if variation == 3 { try expectPage(model, f, 0..<30) } else { #expect(model.page == nil) }
                var newest = scope; newest.changeGeneration += 1
                await model.setScope(newest)
                await f.resume(); await task.value
                try expectPage(model, f, 0..<30); #expect(model.errorMessage == nil)
                let maxConcurrentLoads = await f.maxConcurrentLoads
                #expect(maxConcurrentLoads == 1)
                #expect(await f.scopes.last == newest)
                #expect(await f.readCount == 3)
                await model.setScope(nil); #expect(model.page == nil && model.coverage.isEmpty)
            }
        }
    }
    @Test func nilScopeAndInvalidateRejectInFlightWork() async {
        let f = HistoryLoader(), model = DiaryHistoryViewModel(load: { try await f.load($0, $1) })
        await f.pauseNext()
        let task = Task { await model.setScope(f.scope) }; await f.waitForPause()
        model.invalidate(); await model.setScope(nil); await f.resume(); await task.value
        #expect(model.page == nil && model.errorMessage == nil && !model.isLoading)
    }
    private func expectPage(_ model: DiaryHistoryViewModel, _ f: HistoryLoader, _ range: Range<Int>) throws {
        let page = try #require(model.page)
        #expect(model.page!.days.count <= 30)
        #expect(page.days.map(\.day.id) == range.map { f.days[$0].day.id })
    }
}

private actor HistoryLoader {
    nonisolated let scope = DiaryHistoryScope(selection: .init(identity: .init(profileID: UUID(), timelineGeneration: UUID()), selectionEpoch: 1), localDate: nil, changeGeneration: 0)
    nonisolated let days: [DiaryDaySummary] = (0..<75).map { index in
        DiaryDaySummary(mealCount: 0, day: TrackingDay(localDate: "2027-01-15", timeZoneID: "UTC", startAt: Date(timeIntervalSince1970: Double(75-index)*86400)), totals: .init(kcal: nil, carbs: nil, protein: nil, fat: nil, unknownItemCount: 0), savedMealCount: 0, pendingMealCount: 0)
    }
    var readCount = 0, maxConcurrentLoads = 0
    var scopes: [DiaryHistoryScope] = []
    private var active = 0, pause = false, fail = false
    private var continuation: CheckedContinuation<Void, Never>?
    func pauseNext(fail: Bool = false) { pause = true; self.fail = fail }
    func failNext() { fail = true }
    func waitForPause() async { while continuation == nil { await Task.yield() } }
    func resume() { continuation?.resume(); continuation = nil }
    func load(_ scope: DiaryHistoryScope, _ start: DiaryHistoryPageStart) async throws -> DiaryHistoryLoad {
        readCount += 1; scopes.append(scope); active += 1; maxConcurrentLoads = max(maxConcurrentLoads, active)
        defer { active -= 1 }
        let shouldFail = fail; fail = false
        if pause { pause = false; await withCheckedContinuation { continuation = $0 } }
        if shouldFail { throw DiaryError.persistenceFailed }
        let offset: Int
        switch start { case .latest: offset = 0; case .before(let cursor): offset = cursor.ordinal }
        let end = min(offset + 30, days.count)
        return DiaryHistoryLoad(page: .init(days: Array(days[offset..<end]), cursor: .init(identity: scope.selection.identity, ordinal: end, dayID: days[end-1].day.id, recordedOnly: false, localDate: scope.localDate), hasMore: end < days.count), coverage: [.complete: 75])
    }
}
