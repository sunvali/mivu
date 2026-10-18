import Foundation
import Testing
@testable import Mivu

@Suite struct CoachRecoveryReviewTests {
    @Test func legacyAdapterLostAcknowledgementFinalizesOriginalCorrectionFactsOnce() async throws {
        let source = ChatHistoryFixture.lunchCorrectionSnapshot()
        let root = URL.temporaryDirectory.appending(path: "LegacyCoachRecovery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: source.profile.id.uuidString + ".sqlite/diary.sqlite")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DiaryDatabase(url: url, create: true).write(source, expected: nil, maximumBytes: ChatHistoryFixture.maximumBytes)
        try ChatHistoryFixture.execute(url, "CREATE TABLE legacy_applications(itemID TEXT)")
        try ChatHistoryFixture.execute(url, "CREATE TRIGGER count_legacy_correction AFTER UPDATE ON item WHEN json_extract(CAST(NEW.payload AS TEXT), '$.quantity') != json_extract(CAST(OLD.payload AS TEXT), '$.quantity') BEGIN INSERT INTO legacy_applications VALUES (NEW.id); END")
        let store = DiaryStore(directory: root); _ = try await store.selectProfile(source.profile.id)
        let turn = try await store.captureCoachTurn(text: "Please edit yesterday’s lunch because I ate one more chicken.", photos: [],
            at: ISO8601DateFormatter().date(from: "2027-01-16T10:00:00Z")!, expectedProfileID: source.profile.id)
        let first = CoachJourneyTransport(interruptAfterCommit: true)
        await #expect(throws: CoachJourneyTransport.Interruption.afterCommit) {
            try await CoachEngine(store: store, infer: { try await first.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: source.profile.id)
        }
        let before = try await store.snapshot(expectedProfileID: source.profile.id)
        let receipt = try #require(before.coachTurns.first { $0.id == turn.id }?.receipts.first)
        #expect(before.meals[0].items[0].quantity == 3)
        let applications = try ChatHistoryFixture.strings(url, "SELECT COUNT(*) FROM legacy_applications")
        #expect(applications == [["1"]])
        let fresh = DiaryStore(directory: root); _ = try await fresh.selectProfile(source.profile.id)
        try await fresh.setCoachTurnState(turnID: turn.id, state: .captured, expectedProfileID: source.profile.id)
        let recovered = CoachJourneyTransport()
        let completed = try await CoachEngine(store: fresh, infer: { try await recovered.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: source.profile.id)
        #expect(completed.state == .completed && completed.receipts == [receipt])
        #expect(completed.assistantText?.contains("2027-01-15") == true && completed.assistantText?.contains("3 piece") == true)
        #expect(await recovered.calls.isEmpty)
        let capturedContext = try #require(await recovered.contexts.first)
        #expect(capturedContext.committedReceipts?.first?.targetLocalDate == "2027-01-15")
        #expect(capturedContext.committedReceipts?.first?.items.first?.quantity == 3)
        #expect(try ChatHistoryFixture.strings(url, "SELECT COUNT(*) FROM legacy_applications") == applications)
        var manual = try await fresh.snapshot(expectedProfileID: source.profile.id).meals[0].items[0]; manual.quantity = 5
        try await fresh.editItem(mealID: source.meals[0].id, item: manual, expectedRevision: 2, expectedProfileID: source.profile.id)
        try await fresh.setCoachTurnState(turnID: turn.id, state: .captured, expectedProfileID: source.profile.id)
        let replay = CoachJourneyTransport()
        let again = try await CoachEngine(store: fresh, infer: { try await replay.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: source.profile.id)
        #expect(again.receipts == [receipt] && again.assistantText?.contains("3 piece") == true)
        #expect(try await fresh.snapshot(expectedProfileID: source.profile.id).meals[0].items[0].quantity == 5)
        #expect(await replay.calls.isEmpty)
        #expect(try ChatHistoryFixture.strings(url, "PRAGMA user_version") == [["0"]])
    }

    @Test(arguments: ["empty", "populated", "nil"])
    func orphanRecoveryInfersCaptureDateWithoutInventingTrackingDayAndPreservesNextBoundary(boundary: String) async throws {
        var source = ChatHistoryFixture.lunchCorrectionSnapshot()
        let target = source.meals[0].dayID, current = try #require(source.activeDayID)
        let savedCapture = ISO8601DateFormatter().date(from: "2027-01-20T10:30:00Z")!
        source.profile.timeZoneID = "Asia/Tokyo"
        source.meals[0].capturedAt = savedCapture
        let orphan = MealSubmission(baseRevision: 1, text: "Synthetic backdated target, captured January 20", photoIDs: [], reviewFirst: false)
        source.meals[0].submissions.append(orphan)
        source.coachTurns = [source.coachTurns[0], source.coachTurns.last!]
        let populated = UUID(), empty = UUID()
        source.coachTurns[1].captureSegmentID = populated
        source.activeConversationSegmentID = boundary == "nil" ? nil : (boundary == "empty" ? empty : populated)
        let f = try CaptureFixture(snapshot: source); defer { f.remove() }
        let store = DiaryStore(directory: f.root), database = try DiaryDatabase(url: f.url)
        let before = try await store.selectPagedProfile(f.profileID)
        let frozen = try f.payload(head: before, text: "Synthetic next normal send")
        let immutable = try f.rows("SELECT turnID,sequence,capturedAt,captureTimeZoneID,trackingDayID,displayLocalDate,displayTimeZoneID,segmentID FROM coach_index ORDER BY sequence")
        let pending = try #require(try await store.nextUnlinkedPendingSubmission(expectedProfileID: f.profileID))
        #expect(pending.submissionID == orphan.id)
        _ = try await store.preparePendingCoachTurn(turnID: orphan.id, expectedProfileID: f.profileID)
        let work = try await store.coachWorkItem(turnID: orphan.id, expectedProfileID: f.profileID)
        let exchange = try database.coachExchangeSummary(turnID: orphan.id, expectedProfileID: f.profileID)
        #expect(work.capturedAt == savedCapture && work.captureTimeZoneID == "UTC")
        #expect(work.activeDayID == nil && work.resolvedDayID == target && work.pendingMealID == source.meals[0].id)
        #expect(exchange.trackingDayID == nil && exchange.displayLocalDate == "2027-01-20" && exchange.displayTimeZoneID == "UTC")
        #expect(exchange.segmentID != populated && exchange.segmentID != empty && exchange.sequence == 3)
        let after = try await store.diaryHead(expectedProfileID: f.profileID)
        #expect(after.activeDayID == current && after.previousDayConfirmedAt == before.previousDayConfirmedAt)
        if boundary == "empty" { #expect(after.activeConversationSegmentID == empty) }
        if boundary == "populated" { #expect(after.activeConversationSegmentID != populated && after.activeConversationSegmentID != nil) }
        if boundary == "nil" { #expect(after.activeConversationSegmentID == nil) }
        #expect(try f.rows("SELECT json_extract(CAST(payload AS TEXT), '$.submissionManifest') FROM coach_turn WHERE id = '\(orphan.id)'") == [["NULL"]])
        #expect(try f.rows("SELECT COUNT(*) FROM coach_index WHERE turnID = '\(orphan.id)' AND trackingDayID IS NOT NULL") == [["0"]])
        let around = try database.coachPage(.aroundTurn(orphan.id), expectedProfileID: f.profileID)
        #expect(around.exchanges.first { $0.id == orphan.id } == exchange)
        let targetPage = try database.coachPage(.atDay(target), expectedProfileID: f.profileID)
        #expect(targetPage.exchanges.first { $0.trackingDayID == target }?.id == source.coachTurns[0].id)
        let currentPage = try database.coachPage(.atDay(current), expectedProfileID: f.profileID)
        #expect(currentPage.exchanges.first { $0.trackingDayID == current }?.id == source.coachTurns[1].id)
        let inferred = try database.coachSegments(displayLocalDate: "2027-01-20", before: nil,
            expectedIdentity: CoachTimelineIdentity(profileID: f.profileID, timelineGeneration: after.timelineGeneration))
        #expect(inferred.segments.first?.firstExchangeID == orphan.id && inferred.segments.first?.trackingDayID == nil)
        let latest = try database.coachPage(.latest, expectedProfileID: f.profileID)
        #expect(latest.latestEmptySegment?.trackingDayID == current && latest.latestEmptySegment?.segmentID == after.effectiveConversationSegmentID)
        let next: CoachExchangeSummary
        if boundary == "empty" { next = try await store.captureCoachSubmission(frozen, expectedProfileID: f.profileID) }
        else {
            await #expect(throws: DiaryError.staleRevision) { try await store.captureCoachSubmission(frozen, expectedProfileID: f.profileID) }
            next = try await store.captureCoachSubmission(f.payload(head: after, text: "Fresh normal send"), expectedProfileID: f.profileID)
        }
        #expect(next.trackingDayID == current && next.segmentID == after.effectiveConversationSegmentID && next.segmentID != exchange.segmentID)
        #expect(try f.rows("SELECT turnID,sequence,capturedAt,captureTimeZoneID,trackingDayID,displayLocalDate,displayTimeZoneID,segmentID FROM coach_index WHERE sequence <= 2 ORDER BY sequence") == immutable)
        let reference = try ChatHistoryFixture.completeReference(databaseURL: f.url)
        let encodedBytes = try JSONEncoder().encode(reference).count
        #expect(try f.rows("SELECT portableBytes FROM storage_quota") == [[String(encodedBytes)]])
        #expect(reference.activeDayID == source.activeDayID && reference.previousDayConfirmedAt == source.previousDayConfirmedAt)
    }

    @Test(arguments: ["meal", "weight", "workout"], ["invalidData", "persistenceFailed", "deleted"])
    func receiptSummaryDistinguishesUnavailableTargetsFromFailedReads(kind: String, fault: String) async throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 0)
        let id = UUID(), recordID = kind == "meal" ? source.meals[0].id : (kind == "weight" ? source.weights[0].id : source.workouts[0].id)
        let dayID = kind == "meal" ? source.meals[0].dayID : (kind == "weight" ? source.weights[0].dayID : source.workouts[0].dayID)
        let receipt = CoachReceipt(operationKey: "\(id)/synthetic-\(kind)/\(recordID)", turnID: id, dayID: dayID,
            mealID: kind == "meal" ? recordID : nil, weightID: kind == "weight" ? recordID : nil,
            workoutID: kind == "workout" ? recordID : nil, committedRevision: 1, resultJSON: "{}")
        source.coachTurns = [CoachTurn(id: id, capturedAt: source.days[0].startAt, text: "Synthetic prior result", receipts: [receipt], captureTimeZoneID: source.profile.timeZoneID)]
        let f = try CaptureFixture(snapshot: source); defer { f.remove() }
        let database = try DiaryDatabase(url: f.url)
        if fault == "deleted" {
            let store = DiaryStore(directory: f.root); _ = try await store.selectPagedProfile(f.profileID)
            if kind == "meal" { try await store.deleteMeal(recordID, expectedProfileID: f.profileID) }
            else if kind == "weight" { try await store.deleteWeight(id: recordID, expectedRevision: 1, expectedProfileID: f.profileID) }
            else { try await store.deleteWorkout(id: recordID, expectedRevision: 1, expectedProfileID: f.profileID) }
            let summary = try database.coachReceiptSummary(turnID: id, expectedProfileID: f.profileID)
            #expect(summary.lowercased().contains("deleted"))
            #expect(try database.coachExchangeSummary(turnID: id, expectedProfileID: f.profileID).receipts.first?.operationKey == receipt.operationKey)
        } else if fault == "invalidData" {
            try ChatHistoryFixture.changePayload(f.url, table: kind) { $0["id"] = UUID().uuidString }
            #expect(throws: DiaryError.invalidData) { try database.coachReceiptSummary(turnID: id, expectedProfileID: f.profileID) }
        } else {
            try f.execute("DROP TABLE \(kind)")
            #expect(throws: DiaryError.persistenceFailed) { try database.coachReceiptSummary(turnID: id, expectedProfileID: f.profileID) }
        }
    }
}
