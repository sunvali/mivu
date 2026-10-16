import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct CoachHistoryWindowTests {
    @Test(arguments: [0, 1, 20, 21, 45, 61])
    func initialWindowShowsLatestTwentyAndPagesBackToEveryTurn(count: Int) {
        let ids = (0..<count).map { _ in UUID() }
        var window = CoachHistoryWindow()
        #expect(window.startIndex(in: ids) == max(0, count - 20))
        window.reconcile(ids: ids)
        #expect(window.firstVisibleTurnID == ids.dropFirst(max(0, count - 20)).first)

        while window.startIndex(in: ids) > 0 {
            let previousStart = window.startIndex(in: ids)
            #expect(window.showEarlier(ids: ids) == ids[max(0, previousStart - 20)])
            #expect(window.startIndex(in: ids) == max(0, previousStart - 20))
        }
        #expect(Array(ids.dropFirst(window.startIndex(in: ids))) == ids)
        #expect(window.showEarlier(ids: ids) == nil)
    }

    @Test(arguments: [false, true])
    func appendingPreservesHistoryBeingRead(afterShowingEarlier: Bool) {
        var ids = (0..<65).map { _ in UUID() }
        var window = CoachHistoryWindow()
        window.reset(ids: ids)
        if afterShowingEarlier { _ = window.showEarlier(ids: ids) }
        let anchor = window.firstVisibleTurnID
        let visibleBeforeAppend = Array(ids.dropFirst(window.startIndex(in: ids)))
        ids.append(contentsOf: (0..<30).map { _ in UUID() })
        window.reconcile(ids: ids)
        #expect(window.firstVisibleTurnID == anchor)
        #expect(window.startIndex(in: ids) == (afterShowingEarlier ? 25 : 45))
        #expect(Array(ids.dropFirst(window.startIndex(in: ids)).prefix(visibleBeforeAppend.count)) == visibleBeforeAppend)
        #expect(ids.count - window.startIndex(in: ids) == (afterShowingEarlier ? 70 : 50))
    }

    @Test func removingTurnsBeforeAnchorKeepsAnchorButRemovingAnchorResetsLatestTwenty() {
        var ids = (0..<65).map { _ in UUID() }
        var window = CoachHistoryWindow()
        window.reset(ids: ids)
        _ = window.showEarlier(ids: ids)
        let anchor = window.firstVisibleTurnID
        ids.removeFirst(10)
        window.reconcile(ids: ids)
        #expect(window.firstVisibleTurnID == anchor)
        #expect(window.startIndex(in: ids) == 15)
        ids.remove(at: 15)
        window.reconcile(ids: ids)
        #expect(window.startIndex(in: ids) == ids.count - 20)
        #expect(window.firstVisibleTurnID == ids[ids.count - 20])
    }

    @Test func replacedArchiveAndEmptyArchiveResetSafely() {
        let original = (0..<45).map { _ in UUID() }
        let replacement = (0..<61).map { _ in UUID() }
        var window = CoachHistoryWindow()
        window.reset(ids: original)
        _ = window.showEarlier(ids: original)
        #expect(window.startIndex(in: replacement) == 41)
        window.reconcile(ids: replacement)
        #expect(window.firstVisibleTurnID == replacement[41])
        window.reconcile(ids: [])
        #expect(window.firstVisibleTurnID == nil)
        #expect(window.startIndex(in: []) == 0)
        #expect(window.showEarlier(ids: []) == nil)
        window.reconcile(ids: original)
        #expect(window.firstVisibleTurnID == original[25])
    }

    @Test func explicitProfileResetReturnsToLatestEvenWhenIDsOverlap() {
        let ids = (0..<61).map { _ in UUID() }
        var window = CoachHistoryWindow()
        window.reset(ids: ids)
        _ = window.showEarlier(ids: ids)
        _ = window.showEarlier(ids: ids)
        #expect(window.startIndex(in: ids) == 1)
        window.reset(ids: ids)
        #expect(window.firstVisibleTurnID == ids[41])
        #expect(window.startIndex(in: ids) == 41)
    }
}
