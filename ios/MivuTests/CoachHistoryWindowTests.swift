import Foundation
import Testing
@testable import Mivu

@Suite struct CoachHistoryWindowTests {
    private typealias Data = CoachTimelineTestData

    private func fullWindow() throws -> CoachPagedHistoryWindow {
        var window = CoachPagedHistoryWindow()
        let resetResult2 = window.reset(Data.page(141...160))
        #expect(resetResult2)
        for upper in [140, 120, 100, 80] {
            let reserveResult3 = window.reserve(.earlier, anchor: Data.anchor(upper + 1))
            let reservation = try #require(reserveResult3)
            let completeResult4 = window.complete(Data.page((upper - 19)...upper), reservation: reservation)
            #expect(completeResult4)
        }
        return window
    }

    @Test func focusedPageCannotBeEvicted() throws {
        var window = try fullWindow()
        let anchor = Data.anchor(70, focus: 150)
        window.setViewport(.history(anchor))
        let reserveResult5 = window.reserve(.earlier, anchor: anchor)
        #expect(reserveResult5 == nil)
        #expect(window.exchanges.contains { $0.id == anchor.focusedExchangeID })
        #expect(window.residentCount == 100)
        #expect(window.reservedCapacity == 0)
        let reserveResult6 = window.reserve(.earlier, anchor: nil)
        #expect(reserveResult6 == nil)
    }

    @Test func visiblePagesAndInteractiveScrollingDeferConflictingEviction() throws {
        var window = try fullWindow()
        let anchor = Data.anchor(70)
        window.setViewport(.history(anchor), visibleIDs: [Data.id(70), Data.id(150)])
        let reserveResult7 = window.reserve(.earlier, anchor: anchor)
        #expect(reserveResult7 == nil)
        window.setViewport(.history(anchor), visibleIDs: [Data.id(70)], isInteracting: true)
        let reserveResult8 = window.reserve(.earlier, anchor: anchor)
        #expect(reserveResult8 == nil)
        window.setViewport(.history(anchor), visibleIDs: [Data.id(70)])
        let reserveResult9 = window.reserve(.earlier, anchor: anchor)
        let reservation = try #require(reserveResult9)
        #expect(window.residentCount + window.reservedCapacity == 100)
        #expect(window.occupiedPageSlots == 5)
        #expect(window.pages.last?.hasLater == true)
        window.cancel(reservation)
        #expect(window.edgeState(.later) == .available)
    }

    @Test func sixPlusPagesReloadBothEvictedEdgesWithinBudgets() throws {
        var window = CoachPagedHistoryWindow()
        let resetResult10 = window.reset(Data.page(141...160))
        #expect(resetResult10)
        for upper in [140, 120, 100, 80, 60, 40, 20] {
            let reserveResult11 = window.reserve(.earlier, anchor: Data.anchor(upper + 1))
            let reservation = try #require(reserveResult11)
            #expect(window.residentCount + window.reservedCapacity <= 100)
            #expect(window.occupiedPageSlots <= 5)
            let completeResult12 = window.complete(Data.page((upper - 19)...upper), reservation: reservation)
            #expect(completeResult12)
        }
        #expect(window.exchanges.first?.sequence == 1)
        #expect(window.edgeState(.earlier) == .exhausted)
        for lower in [101, 121, 141] {
            let reserveResult13 = window.reserve(.later, anchor: Data.anchor(lower - 1))
            let reservation = try #require(reserveResult13)
            #expect(reservation.request == .after(Data.cursor(lower - 1)))
            #expect(window.residentCount + window.reservedCapacity <= 100)
            let completeResult14 = window.complete(Data.page(lower...(lower + 19)), reservation: reservation)
            #expect(completeResult14)
        }
        #expect(window.exchanges.last?.sequence == 160)
        #expect(window.edgeState(.later) == .exhausted)
        #expect(window.edgeState(.earlier) == .available)
        #expect(window.residentCount == 100)
    }

    @Test func oppositeReservationPinsItsBoundaryUntilCompletion() throws {
        var window = CoachPagedHistoryWindow()
        let resetResult15 = window.reset(Data.page(61...80), request: .aroundTurn(Data.id(70)))
        #expect(resetResult15)
        for upper in [60, 40] {
            let reserveResult16 = window.reserve(.earlier, anchor: Data.anchor(70))
            let reservation = try #require(reserveResult16)
            let completeResult17 = window.complete(Data.page((upper - 19)...upper), reservation: reservation)
            #expect(completeResult17)
        }
        let reserveResult18 = window.reserve(.earlier, anchor: Data.anchor(30))
        let earlier = try #require(reserveResult18)
        let reserveResult19 = window.reserve(.later, anchor: Data.anchor(30))
        let later = try #require(reserveResult19)
        #expect(window.residentCount + window.reservedCapacity == 100)
        let completeResult20 = window.complete(Data.page(1...20), reservation: earlier)
        #expect(completeResult20)
        let reserveResult21 = window.reserve(.earlier, anchor: Data.anchor(30))
        #expect(reserveResult21 == nil)
        let completeResult22 = window.complete(Data.page(81...100), reservation: later)
        #expect(completeResult22)
        #expect(window.residentCount == 100)
    }

    @Test(arguments: 0...5)
    func malformedPagesReleaseTheirReservationWithoutChangingRows(kind: Int) throws {
        var window = CoachPagedHistoryWindow()
        let resetResult23 = window.reset(Data.page(141...160))
        #expect(resetResult23)
        let before = window.exchanges
        let reserveResult24 = window.reserve(.earlier, anchor: Data.anchor(145))
        let reservation = try #require(reserveResult24)
        var page = Data.page(121...140)
        switch kind {
        case 0: page.identity.profileID = Data.id(990)
        case 1: page.exchanges.reverse()
        case 2: page.exchanges[1] = page.exchanges[0]
        case 3: page.before = Data.cursor(120)
        case 4: page = Data.page(122...142)
        default: page = Data.page(141...160)
        }
        let completeResult25 = window.complete(page, reservation: reservation)
        #expect(!completeResult25)
        #expect(window.exchanges == before)
        #expect(window.reservedCapacity == 0)
        if case .failed = window.edgeState(.earlier) {} else { Issue.record("Expected failed edge") }
        let reserveResult26 = window.reserve(.earlier, anchor: Data.anchor(145))
        #expect(reserveResult26 != nil)
    }

    @Test func emptySuccessExhaustsOnlyItsEdgeAndInvalidResetPreservesReader() throws {
        var window = CoachPagedHistoryWindow()
        let resetResult27 = window.reset(Data.page(141...160))
        #expect(resetResult27)
        let original = window.exchanges
        var invalid = Data.page(121...140)
        let resetResult28 = window.reset(invalid)
        #expect(!resetResult28) // A latest result cannot claim newer rows.
        #expect(window.exchanges == original)
        let reserveResult29 = window.reserve(.earlier, anchor: Data.anchor(145))
        let reservation = try #require(reserveResult29)
        invalid = CoachPage(identity: Data.identity, exchanges: [], before: nil, after: nil, hasEarlier: false, hasLater: false,
                            earlierSegment: nil, laterSegment: nil)
        let completeResult30 = window.complete(invalid, reservation: reservation)
        #expect(completeResult30)
        #expect(window.exchanges == original)
        #expect(window.pages.count == 1)
        #expect(window.edgeState(.earlier) == .exhausted)
        #expect(window.reservedCapacity == 0)
    }

    @Test func replacementResultsAreChargedAndStaleTokensCannotReleaseNewWork() throws {
        var window = try fullWindow()
        window.setViewport(.history(Data.anchor(70)), visibleIDs: [Data.id(70), Data.id(150)])
        let reserveReplacementResult31 = window.reserveReplacement(anchor: Data.anchor(70))
        #expect(reserveReplacementResult31 == false)
        window.setViewport(.history(Data.anchor(150)))
        let reserveReplacementResult32 = window.reserveReplacement(anchor: Data.anchor(150))
        #expect(reserveReplacementResult32)
        #expect(window.residentCount + window.reservedCapacity == 100)
        #expect(window.occupiedPageSlots == 5)
        let reserveResult33 = window.reserve(.earlier, anchor: Data.anchor(150))
        #expect(reserveResult33 == nil)
        window.releaseReservations()
        let reserveResult34 = window.reserve(.earlier, anchor: Data.anchor(100))
        let old = try #require(reserveResult34)
        window.cancel(old)
        let reserveResult35 = window.reserve(.earlier, anchor: Data.anchor(100))
        let new = try #require(reserveResult35)
        window.cancel(old)
        #expect(window.reservations[.earlier] == new)
        let completeResult36 = window.complete(Data.page(61...80), reservation: old)
        #expect(!completeResult36)
        #expect(window.reservations[.earlier] == new)
    }

    @Test func latestEmptyDividerChangesWithoutRelabelingExchanges() throws {
        var window = CoachPagedHistoryWindow()
        let page = Data.page(141...160)
        let resetResult37 = window.reset(page)
        #expect(resetResult37)
        for boundary in [920, 921] {
            let refresh = CoachTimelineRefresh(identity: Data.identity, exchanges: [], latestCursor: Data.cursor(160), latestEmptySegment: Data.empty(boundary))
            let refreshResult38 = window.refresh(refresh, requestedIDs: [])
            #expect(refreshResult38)
            #expect(window.latestEmptySegment?.segmentID == Data.id(boundary))
            #expect(window.exchanges == page.exchanges)
        }
        let later = CoachTimelineRefresh(identity: Data.identity, exchanges: [], latestCursor: Data.cursor(161), latestEmptySegment: Data.empty(922))
        let refreshResult39 = window.refresh(later, requestedIDs: [])
        #expect(refreshResult39)
        #expect(window.latestEmptySegment == nil)
        #expect(window.edgeState(.later) == .available)
        #expect(window.exchanges == page.exchanges)
    }

    @Test func residentDeltasRejectWrongScopeAndRemoveDeletedRows() throws {
        var window = CoachPagedHistoryWindow()
        let resetResult40 = window.reset(Data.page(141...160))
        #expect(resetResult40)
        let original = window.exchanges
        let invalid = CoachTimelineRefresh(identity: Data.identity, exchanges: [Data.row(120)], latestCursor: Data.cursor(160), latestEmptySegment: nil)
        let refreshResult41 = window.refresh(invalid, requestedIDs: [Data.id(150)])
        #expect(!refreshResult41)
        #expect(window.exchanges == original)
        var duplicate = invalid
        duplicate.exchanges = [Data.row(150), Data.row(150)]
        let refreshResult42 = window.refresh(duplicate, requestedIDs: [Data.id(150), Data.id(151)])
        #expect(!refreshResult42)
        let deleted = CoachTimelineRefresh(identity: Data.identity, exchanges: [], latestCursor: Data.cursor(159), latestEmptySegment: nil)
        let refreshResult43 = window.refresh(deleted, requestedIDs: [Data.id(160)])
        #expect(refreshResult43)
        #expect(window.exchanges.count == 19)
        #expect(window.pages.last?.after == Data.cursor(159))
        #expect(window.pages.last?.hasLater == false)
    }
    @Test func emptyLatestCanPublishAnActiveDayDividerWithoutAFakeExchange() {
        var window = CoachPagedHistoryWindow()
        let empty = CoachPage(identity: Data.identity, exchanges: [], before: nil, after: nil, hasEarlier: false, hasLater: false,
                              earlierSegment: nil, laterSegment: nil, latestEmptySegment: Data.empty(920))
        let resetResult44 = window.reset(empty)
        #expect(resetResult44)
        #expect(window.exchanges.isEmpty)
        #expect(window.latestEmptySegment?.segmentID == Data.id(920))
        #expect(window.edgeState(.earlier) == .exhausted)
        let reserveResult45 = window.reserve(.earlier, anchor: nil)
        #expect(reserveResult45 == nil)
        let refreshResult46 = window.refresh(CoachTimelineRefresh(identity: Data.identity, exchanges: [], latestCursor: nil,
                                                   latestEmptySegment: Data.empty(921)), requestedIDs: [])
        #expect(refreshResult46)
        #expect(window.exchanges.isEmpty)
        #expect(window.latestEmptySegment?.segmentID == Data.id(921))
    }

    @Test func retiredSourcesStayChargedAcrossInvalidationUntilActualExit() throws {
        var window = CoachPagedHistoryWindow()
        let reset = window.reset(Data.page(141...160))
        #expect(reset)
        let reserved = window.reserve(.earlier, anchor: Data.anchor(145))
        let reservation = try #require(reserved)
        window.retire(reservation)
        #expect(window.reservations.isEmpty)
        #expect(window.retiredReadIDs == [reservation.id])
        #expect(window.reservedCapacity == 20)
        window.invalidate(identity: Data.identity)
        #expect(window.reservedCapacity == 20)
        #expect(window.occupiedPageSlots == 1)
        window.finishRead(reservation)
        #expect(window.reservedCapacity == 0)
        #expect(window.retiredReadIDs.isEmpty)
    }

}
