import Foundation
import Testing
@testable import Mivu

@Suite struct CoachPagingTests {
    @Test(arguments: [100, 10_000])
    func keysetPagesCoverEqualTimestampTurnsOnce(count: Int) throws {
        let snapshot = ChatHistoryFixture.pagingSnapshot(exchanges: count)
        let url = try migrated(snapshot)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let metrics = DiaryQueryDiagnostics(), database = try DiaryDatabase(url: url, diagnostics: metrics)
        var page = try database.coachPage(.latest, expectedProfileID: snapshot.profile.id)
        var ids = page.exchanges.map(\.id)
        #expect(ids == Array(snapshot.coachTurns.suffix(20)).map(\.id))
        #expect(!page.hasLater)
        while page.hasEarlier {
            let cursor = try #require(page.before)
            metrics.reset()
            page = try database.coachPage(.before(cursor), expectedProfileID: snapshot.profile.id)
            #expect(page.exchanges.count <= 20)
            #expect(metrics.counters.decodedTurnPayloads == page.exchanges.count)
            #expect(metrics.counters.originalPhotoBytes == 0)
            #expect(metrics.counters.completeReads == 0)
            ids = page.exchanges.map(\.id) + ids
        }
        #expect(ids == snapshot.coachTurns.map(\.id))
        #expect(Set(ids).count == count)
        var forward = try database.coachPage(.aroundTurn(snapshot.coachTurns[0].id), expectedProfileID: snapshot.profile.id)
        var forwardIDs = forward.exchanges.map(\.id)
        while forward.hasLater {
            metrics.reset()
            forward = try database.coachPage(.after(try #require(forward.after)), expectedProfileID: snapshot.profile.id)
            forwardIDs += forward.exchanges.map(\.id)
        }
        #expect(forwardIDs == ids)
    }

    @Test(arguments: [100, 10_000])
    func oldestDayAndSourceSeekAreIndexed(count: Int) throws {
        let snapshot = ChatHistoryFixture.pagingSnapshot(exchanges: count)
        let url = try migrated(snapshot)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let metrics = DiaryQueryDiagnostics(), database = try DiaryDatabase(url: url, diagnostics: metrics)
        let page = try database.coachPage(.atDay(snapshot.days[1].id), expectedProfileID: snapshot.profile.id)
        #expect(page.exchanges.count == 20)
        #expect(page.exchanges.contains { $0.id == snapshot.coachTurns[1].id })
        let source = try #require(UUID(uuidString: ChatHistoryFixture.strings(url, "SELECT turnID FROM record_source WHERE relation = 'origin'")[0][0]))
        metrics.reset()
        let sourcePage = try database.coachPage(.aroundTurn(source), expectedProfileID: snapshot.profile.id)
        #expect(sourcePage.exchanges.first?.id == snapshot.coachTurns[0].id)
        #expect(sourcePage.exchanges.first?.capturedAt == snapshot.coachTurns[0].capturedAt)
        #expect(sourcePage.exchanges.first?.photos.first?.owner == .coachTurn(source))
        #expect(metrics.counters.decodedTurnPayloads == 20)
        #expect(metrics.counters.originalPhotoBytes == 0)
        #expect(metrics.counters.queryPlans.contains { $0.contains("SEARCH") && $0.contains("turnID=?") })
        #expect(metrics.counters.queryPlans.contains { $0.contains("SEARCH") && $0.contains("sequence") })
        metrics.reset()
        _ = try database.coachPage(.atDay(snapshot.days[1].id), expectedProfileID: snapshot.profile.id)
        #expect(metrics.counters.queryPlans.contains { $0.contains("coach_index_day_sequence") && $0.contains("trackingDayID=?") })
    }

    @Test func emptyDayIsNotNearestDay() throws {
        var snapshot = ChatHistoryFixture.snapshot(exchanges: 3)
        let empty = TrackingDay(localDate: "2027-01-13", timeZoneID: "Asia/Jerusalem", startAt: snapshot.days[0].startAt)
        snapshot.days.append(empty)
        let url = try migrated(snapshot)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = try DiaryDatabase(url: url)
        #expect(throws: CoachQueryError.noChatForDay(empty.id)) {
            try database.coachPage(.atDay(empty.id), expectedProfileID: snapshot.profile.id)
        }
        let missing = UUID()
        #expect(throws: CoachQueryError.missingTurn(missing)) {
            try database.coachPage(.aroundTurn(missing), expectedProfileID: snapshot.profile.id)
        }
        let identity = try database.coachPage(.latest, expectedProfileID: snapshot.profile.id).identity
        #expect(try database.coachSegments(displayLocalDate: empty.localDate, before: nil, expectedIdentity: identity).segments.isEmpty)
        let noTurns = ChatHistoryFixture.snapshot(exchanges: 0), emptyURL = try migrated(noTurns)
        defer { try? FileManager.default.removeItem(at: emptyURL.deletingLastPathComponent()) }
        let emptyPage = try DiaryDatabase(url: emptyURL).coachPage(.latest, expectedProfileID: noTurns.profile.id)
        #expect(emptyPage.exchanges.isEmpty && !emptyPage.hasEarlier && !emptyPage.hasLater)
    }

    @Test func foreignAndRestoredCursorsAreRejected() throws {
        let snapshot = ChatHistoryFixture.pagingSnapshot()
        let url = try migrated(snapshot), replacement = try migrated(snapshot)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()); try? FileManager.default.removeItem(at: replacement.deletingLastPathComponent()) }
        let metrics = DiaryQueryDiagnostics(), database = try DiaryDatabase(url: url, diagnostics: metrics)
        let page = try database.coachPage(.latest, expectedProfileID: snapshot.profile.id)
        let cursor = try #require(page.before)
        metrics.reset()
        #expect(throws: CoachQueryError.wrongTimeline) { try database.coachPage(.before(cursor), expectedProfileID: UUID()) }
        #expect(throws: CoachQueryError.wrongTimeline) { try DiaryDatabase(url: replacement).coachPage(.before(cursor), expectedProfileID: snapshot.profile.id) }
        var forged = cursor; forged.turnID = snapshot.coachTurns[0].id
        #expect(throws: CoachQueryError.invalidCursor) { try database.coachPage(.before(forged), expectedProfileID: snapshot.profile.id) }
        forged = cursor; forged.sequence = 0
        #expect(throws: CoachQueryError.invalidCursor) { try database.coachPage(.after(forged), expectedProfileID: snapshot.profile.id) }
        let days = try database.coachDays(before: nil, expectedProfileID: snapshot.profile.id)
        var dayCursor = try #require(days.cursor)
        dayCursor.dateFilterScope = snapshot.days[0].localDate
        #expect(throws: CoachQueryError.invalidCursor) { try database.coachDays(before: dayCursor, expectedProfileID: snapshot.profile.id) }
        dayCursor.dateFilterScope = nil
        #expect(throws: CoachQueryError.invalidCursor) { try database.coachSegments(displayLocalDate: snapshot.days[0].localDate, before: dayCursor, expectedIdentity: page.identity) }
        #expect(throws: CoachQueryError.invalidDateFilter) { try database.coachSegments(displayLocalDate: "2027-02-30", before: nil, expectedIdentity: page.identity) }
        #expect(metrics.counters.decodedTurnPayloads == 0)
        #expect(metrics.counters.originalPhotoBytes == 0)
    }

    @Test func diaryDaySeekUsesFirstExchangeAcrossAllSegments() throws {
        let snapshot = ChatHistoryFixture.pagingSnapshot()
        let url = try migrated(snapshot)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = try DiaryDatabase(url: url)
        let page = try database.coachPage(.atDay(snapshot.days[0].id), expectedProfileID: snapshot.profile.id)
        #expect(page.exchanges.first?.id == snapshot.coachTurns[0].id)
        #expect(page.exchanges.first?.trackingDayID == snapshot.days[0].id)
        #expect(page.earlierSegment == nil)
        #expect(page.laterSegment?.firstExchangeID == snapshot.coachTurns[20].id)
        let centered = try database.coachPage(.aroundTurn(snapshot.coachTurns[50].id), expectedProfileID: snapshot.profile.id)
        #expect(centered.exchanges.map(\.id) == Array(snapshot.coachTurns[41...60]).map(\.id))
        #expect(centered.earlierSegment?.firstExchangeID == snapshot.coachTurns[40].id)
        #expect(centered.laterSegment?.firstExchangeID == snapshot.coachTurns[61].id)
        let end = try database.coachPage(.aroundTurn(snapshot.coachTurns[99].id), expectedProfileID: snapshot.profile.id)
        #expect(end.exchanges.map(\.id) == Array(snapshot.coachTurns[80...99]).map(\.id))
    }

    @Test func repeatedDisplayDatesRetainDistinctSegmentTargets() throws {
        let snapshot = ChatHistoryFixture.pagingSnapshot()
        let url = try migrated(snapshot)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let metrics = DiaryQueryDiagnostics(), database = try DiaryDatabase(url: url, diagnostics: metrics)
        var page = try database.coachDays(before: nil, expectedProfileID: snapshot.profile.id)
        var rows = page.segments
        #expect(rows.count == 30)
        while page.hasMore {
            page = try database.coachDays(before: page.cursor, expectedProfileID: snapshot.profile.id)
            #expect(page.segments.count <= 30)
            rows += page.segments
        }
        #expect(rows.map(\.firstExchangeID) == snapshot.coachTurns.reversed().map(\.id))
        #expect(Set(rows.map(\.segmentID)).count == 100)
        #expect(rows.filter { $0.displayLocalDate == "2027-01-15" }.count == 50)
        #expect(metrics.counters.decodedTurnPayloads == 0)
        #expect(metrics.counters.originalPhotoBytes == 0)
        #expect(metrics.counters.queryPlans.contains { $0.contains("coach_segment_last") && $0.contains("lastSequence") })
        let identity = page.identity
        page = try database.coachSegments(displayLocalDate: "2027-01-15", before: nil, expectedIdentity: identity)
        var exactRows = page.segments
        while page.hasMore {
            page = try database.coachSegments(displayLocalDate: "2027-01-15", before: page.cursor, expectedIdentity: identity)
            exactRows += page.segments
        }
        #expect(exactRows.map(\.firstExchangeID) == stride(from: 98, through: 0, by: -2).map { snapshot.coachTurns[$0].id })
        #expect(metrics.counters.queryPlans.contains { $0.contains("coach_segment_date_last") && $0.contains("displayLocalDate=?") })
    }

    @Test func datePickerFindsLegacySegmentWithoutTrackingDay() throws {
        let snapshot = ChatHistoryFixture.snapshot()
        let url = try migrated(snapshot)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let metrics = DiaryQueryDiagnostics(), database = try DiaryDatabase(url: url, diagnostics: metrics)
        let identity = try database.coachDays(before: nil, expectedProfileID: snapshot.profile.id).identity
        let page = try database.coachSegments(displayLocalDate: "2027-01-15", before: nil, expectedIdentity: identity)
        #expect(page.segments.count == 3)
        #expect(page.segments.contains { $0.trackingDayID == nil && $0.firstExchangeID == snapshot.coachTurns[25].id })
        #expect(metrics.counters.decodedTurnPayloads == 0)
        #expect(metrics.counters.originalPhotoBytes == 0)
    }

    @Test func receiptFactsKeepOriginalDateAndServingWithoutReadingCurrentRecords() throws {
        var snapshot = ChatHistoryFixture.snapshot(exchanges: 5)
        var item = snapshot.meals[0].items[0]
        item.name = "Original serving"; item.quantity = 0.5; item.unit = "bowl"
        let meal = CoachContext.Meal(id: snapshot.meals[0].id, dayID: snapshot.days[1].id, revision: 1,
            eatenAt: snapshot.meals[0].eatenAt, timePrecision: .dateOnly, items: [item])
        snapshot.coachTurns[0].receipts[0].resultJSON = try coachJSON(meal)
        snapshot.meals[0].items[0].quantity = 9
        struct Correction: Encodable { var mealID: UUID; var revision = 2; var state: SubmissionState = .saved; var item: FoodItem; var targetLocalDate: String? }
        snapshot.coachTurns[1].receipts = [CoachReceipt(operationKey: snapshot.coachTurns[1].id.uuidString + "/correct/original", turnID: snapshot.coachTurns[1].id,
            dayID: snapshot.days[1].id, mealID: meal.id, itemID: item.id, committedRevision: 2,
            resultJSON: try coachJSON(Correction(mealID: meal.id, item: item, targetLocalDate: nil)))]
        snapshot.coachTurns[2].receipts = [CoachReceipt(operationKey: snapshot.coachTurns[2].id.uuidString + "/correct/new", turnID: snapshot.coachTurns[2].id,
            dayID: snapshot.days[1].id, mealID: meal.id, itemID: item.id, committedRevision: 3,
            resultJSON: try coachJSON(Correction(mealID: meal.id, item: item, targetLocalDate: "2027-01-14")))]
        snapshot.coachTurns[3].receipts = [CoachReceipt(operationKey: snapshot.coachTurns[3].id.uuidString + "/legacy", turnID: snapshot.coachTurns[3].id,
            dayID: snapshot.days[1].id, committedRevision: 4, resultJSON: "[]")]
        var proposal = meal; proposal.state = .awaitingReview
        snapshot.coachTurns[4].receipts = [CoachReceipt(operationKey: snapshot.coachTurns[4].id.uuidString + "/proposal", turnID: snapshot.coachTurns[4].id,
            dayID: snapshot.days[1].id, mealID: meal.id, committedRevision: 5, resultJSON: try coachJSON(proposal))]
        let url = try migrated(snapshot)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // An unavailable live record must not erase committed receipt facts.
        try ChatHistoryFixture.execute(url, "UPDATE meal SET payload = x'00'; UPDATE item SET payload = x'00'")
        let page = try DiaryDatabase(url: url).coachPage(.latest, expectedProfileID: snapshot.profile.id)
        let facts = try #require(page.exchanges.first?.receipts.first)
        #expect(facts.targetLocalDate == "2027-01-14")
        #expect(facts.items == [CoachCommittedItem(itemID: item.id, name: "Original serving", quantity: 0.5, unit: "bowl")])
        #expect(page.exchanges[1].receipts[0].targetLocalDate == nil)
        #expect(page.exchanges[2].receipts[0].targetLocalDate == "2027-01-14")
        #expect(page.exchanges[3].receipts[0].items.isEmpty)
        #expect(page.exchanges[3].receipts[0].targetLocalDate == nil)
        #expect(page.exchanges[4].receipts[0].items.isEmpty)
    }

    @Test func transferredPhotoCollisionsRetainEveryBoundedOwnerWithoutOriginalReads() throws {
        var snapshot = ChatHistoryFixture.snapshot(exchanges: 1)
        var generator = ChatHistoryFixture.Generator(seed: 123)
        let photos = (0..<16).map { _ in MealPhoto(id: generator.uuid(), data: Data([1]), createdAt: snapshot.coachTurns[0].capturedAt) }
        snapshot.meals[0].photos = photos
        var other = snapshot.meals[0]; other.id = generator.uuid()
        snapshot.meals.append(other)
        snapshot.coachTurns[0].photos = []
        snapshot.coachTurns[0].photoIDs = photos.map(\.id)
        snapshot.coachTurns[0].pendingMealID = snapshot.meals[0].id
        snapshot.coachTurns[0].receipts[0].mealID = other.id
        let url = try migrated(snapshot)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let metrics = DiaryQueryDiagnostics()
        let page = try DiaryDatabase(url: url, diagnostics: metrics).coachPage(.latest, expectedProfileID: snapshot.profile.id)
        let references = try #require(page.exchanges.first?.photos)
        #expect(references.count == 32)
        #expect(Set(references.map(\.id)).count == 32)
        #expect(references.filter { $0.owner == .meal(other.id) }.count == 16)
        #expect(references.filter { $0.owner == .meal(snapshot.meals[0].id) }.count == 16)
        #expect(metrics.counters.originalPhotoBytes == 0)
    }

    private func migrated(_ snapshot: DiarySnapshot) throws -> URL {
        let url = try ChatHistoryFixture.makeDatabase(snapshot)
        try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        return url
    }
}
