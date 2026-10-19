import Foundation
import SQLite3
import Testing
@testable import Mivu

@Suite struct DiaryMigrationTests {
    @Test func migrationPreservesIdentityBytesAndLegacyDayEvidence() throws {
        let before = ChatHistoryFixture.snapshot()
        let url = try ChatHistoryFixture.makeDatabase(before)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try ChatHistoryFixture.strings(url, "PRAGMA user_version") == [["0"]])
        try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        let after = try ChatHistoryFixture.completeReference(databaseURL: url)
        #expect(after == before)
        #expect(try ChatHistoryFixture.strings(url, "PRAGMA user_version") == [["1"]])
        #expect(try ChatHistoryFixture.strings(url, "SELECT COUNT(*), COUNT(DISTINCT sequence) FROM coach_index") == [["100", "100"]])
        #expect(try ChatHistoryFixture.strings(url, "SELECT COUNT(*) FROM coach_segment") == [["4"]])
        #expect(try ChatHistoryFixture.strings(url, "SELECT trackingDayID FROM coach_index ORDER BY sequence LIMIT 1") == [[before.days[0].id.uuidString]])
        #expect(try ChatHistoryFixture.strings(url, "SELECT COUNT(DISTINCT contentToken), COUNT(*) FROM photo_content") == [["6", "6"]])
        #expect(try ChatHistoryFixture.strings(url, "SELECT recordID FROM record_source WHERE kind = 'meal'") == [[before.meals[0].id.uuidString]])
    }

    @Test func migrationIsIdempotentAndRollsBackOnFailure() throws {
        let before = ChatHistoryFixture.snapshot()
        let url = try ChatHistoryFixture.makeDatabase(before)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        let firstGeneration = try ChatHistoryFixture.strings(url, "SELECT timelineGeneration FROM storage_head")
        let firstTokens = try ChatHistoryFixture.strings(url, "SELECT contentToken FROM photo_content ORDER BY ownerKind, parentID, photoID")
        try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        let secondGeneration = try ChatHistoryFixture.strings(url, "SELECT timelineGeneration FROM storage_head")
        #expect(secondGeneration == firstGeneration)
        #expect(try ChatHistoryFixture.strings(url, "SELECT contentToken FROM photo_content ORDER BY ownerKind, parentID, photoID") == firstTokens)

        let failed = try ChatHistoryFixture.makeDatabase(before)
        defer { try? FileManager.default.removeItem(at: failed.deletingLastPathComponent()) }
        let diskBefore = try Data(contentsOf: failed)
        #expect(throws: DiaryError.invalidData) {
            try DiaryDatabase(url: failed).migrateForPagedStorage(maximumBytes: 1)
        }
        let failedMigrationVersion = try ChatHistoryFixture.strings(failed, "PRAGMA user_version")
        #expect(failedMigrationVersion == [["0"]])
        #expect(try Data(contentsOf: failed) == diskBefore)
        #expect(try ChatHistoryFixture.completeReference(databaseURL: failed) == before)
    }

    @Test func legacyNilDaySegmentsRetainDatesWithoutCreatingDiaryDays() throws {
        let before = ChatHistoryFixture.snapshot()
        let url = try ChatHistoryFixture.makeDatabase(before)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let legacyDaysBefore = before.days
        try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        let legacyDaysAfter = try ChatHistoryFixture.completeReference(databaseURL: url).days
        #expect(legacyDaysAfter == legacyDaysBefore)
        let nilDaySegments = try ChatHistoryFixture.strings(url, "SELECT trackingDayID, displayLocalDate, displayTimeZoneID FROM coach_segment WHERE trackingDayID IS NULL")
        #expect(nilDaySegments == [["NULL", "2027-01-15", "Asia/Jerusalem"]])
        #expect(nilDaySegments.allSatisfy { $0[0] == "NULL" })
    }

    @Test func migrationUsesLegacyOrdinalThenIDAndRejectsMalformedSourcesAtomically() throws {
        let before = ChatHistoryFixture.snapshot(exchanges: 3)
        let url = try ChatHistoryFixture.makeDatabase(before)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try ChatHistoryFixture.execute(url, "UPDATE coach_turn SET ordinal = 7")
        try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        let ids = try ChatHistoryFixture.strings(url, "SELECT turnID FROM coach_index ORDER BY sequence").flatMap { $0 }
        #expect(ids == before.coachTurns.map { $0.id.uuidString }.sorted())

        let malformed = try ChatHistoryFixture.makeDatabase(before)
        defer { try? FileManager.default.removeItem(at: malformed.deletingLastPathComponent()) }
        try ChatHistoryFixture.execute(malformed, "UPDATE coach_turn SET payload = x'00' WHERE ordinal = 2")
        let diskBefore = try Data(contentsOf: malformed)
        #expect(throws: DiaryError.invalidData) { try DiaryDatabase(url: malformed).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes) }
        #expect(try ChatHistoryFixture.strings(malformed, "PRAGMA user_version") == [["0"]])
        #expect(try Data(contentsOf: malformed) == diskBefore)
    }

    @Test(arguments: ["full", "commit"])
    func migrationStorageFailuresPreserveOriginalDatabase(failure: String) throws {
        let before = ChatHistoryFixture.snapshot()
        let url = try ChatHistoryFixture.makeDatabase(before)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = try DiaryDatabase(url: url)
        if failure == "full" {
            let pages = try ChatHistoryFixture.strings(url, "PRAGMA page_count")[0][0]
            try #require(sqlite3_exec(database.connection, "PRAGMA max_page_count = \(pages)", nil, nil, nil) == SQLITE_OK)
        } else { sqlite3_commit_hook(database.connection, { _ in 1 }, nil) }
        let diskBefore = try Data(contentsOf: url)
        #expect(throws: DiaryError.persistenceFailed) { try database.migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes) }
        #expect(try ChatHistoryFixture.strings(url, "PRAGMA user_version") == [["0"]])
        #expect(try ChatHistoryFixture.strings(url, "SELECT name FROM sqlite_master WHERE name = 'coach_index'").isEmpty)
        #expect(try Data(contentsOf: url) == diskBefore)
        #expect(try ChatHistoryFixture.completeReference(databaseURL: url) == before)
    }

    @Test(arguments: ["turnText", "photoReference", "itemQuantity", "goalTarget", "orphan"])
    func migrationRejectsSemanticallyMalformedRows(kind: String) throws {
        let url = try ChatHistoryFixture.makeDatabase(ChatHistoryFixture.snapshot())
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        switch kind {
        case "turnText": try ChatHistoryFixture.changePayload(url, table: "coach_turn") { $0["text"] = String(repeating: "x", count: 20_001) }
        case "photoReference": try ChatHistoryFixture.changePayload(url, table: "coach_turn") { $0["photoIDs"] = [UUID().uuidString] }
        case "itemQuantity": try ChatHistoryFixture.changePayload(url, table: "item") { $0["quantity"] = -1 }
        case "goalTarget": try ChatHistoryFixture.changePayload(url, table: "meta") { object in
            var goals = object["goals"] as! [[String: Any]]; goals[0]["targets"] = ["kcal": -1]; object["goals"] = goals
        }
        default: try ChatHistoryFixture.execute(url, "PRAGMA foreign_keys = OFF; UPDATE coach_photo SET parent = '\(UUID().uuidString)'")
        }
        let diskBefore = try Data(contentsOf: url)
        #expect(throws: DiaryError.invalidData) { try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes) }
        #expect(try ChatHistoryFixture.strings(url, "PRAGMA user_version") == [["0"]])
        #expect(try Data(contentsOf: url) == diskBefore)
    }

    @Test func migrationStreamsNearLimitHistoryAndUsesIndexesWithoutCompleteReads() throws {
        var before = ChatHistoryFixture.snapshot(exchanges: 10_000)
        before.meals[0].photos[0].data = Data(repeating: 255, count: 98_305)
        let url = try ChatHistoryFixture.makeDatabase(before)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let diagnostics = DiaryQueryDiagnostics()
        try DiaryDatabase(url: url, diagnostics: diagnostics).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        let counters = diagnostics.counters
        #expect(counters.decodedTurnPayloads == 10_000)
        #expect(counters.completeReads == 0)
        #expect(counters.completeReconciles == 0)
        #expect(counters.originalPhotoBytes == 98_320)
        #expect(counters.maximumPhotoReadChunkBytes <= 49_152)
        #expect(counters.queryPlans.count == 3)
        #expect(counters.queryPlans.allSatisfy { $0.contains("INDEX") && !$0.contains("SCAN coach_") })
        #expect(try ChatHistoryFixture.completeReference(databaseURL: url) == before)
    }

    @Test func restoredContentGetsFreshGenerationAndParentScopedTokens() throws {
        let before = ChatHistoryFixture.snapshot()
        let first = try ChatHistoryFixture.makeDatabase(before), replacement = try ChatHistoryFixture.makeDatabase(before)
        defer { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()); try? FileManager.default.removeItem(at: replacement.deletingLastPathComponent()) }
        try DiaryDatabase(url: first).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        try DiaryDatabase(url: replacement).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        #expect(try ChatHistoryFixture.strings(first, "SELECT timelineGeneration FROM storage_head") != ChatHistoryFixture.strings(replacement, "SELECT timelineGeneration FROM storage_head"))
        #expect(try ChatHistoryFixture.strings(first, "SELECT contentToken FROM photo_content ORDER BY ownerKind, parentID, photoID") != ChatHistoryFixture.strings(replacement, "SELECT contentToken FROM photo_content ORDER BY ownerKind, parentID, photoID"))
    }

    @Test func correctionAndAttachmentReferencesDoNotInventMealOrigins() throws {
        var before = ChatHistoryFixture.snapshot(exchanges: 3)
        before.coachTurns[0].receipts[0].operationKey = before.coachTurns[0].id.uuidString + "/correct/" + before.meals[0].id.uuidString + "/" + before.meals[0].items[0].id.uuidString
        let url = try ChatHistoryFixture.makeDatabase(before)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        #expect(try ChatHistoryFixture.strings(url, "SELECT COUNT(*) FROM record_source WHERE relation = 'origin'") == [["0"]])
        #expect(try ChatHistoryFixture.strings(url, "SELECT COUNT(*) FROM record_source WHERE relation = 'reference'") == [["1"]])
    }

    @Test func captureSequenceAndDayEvidenceCannotBeRewritten() throws {
        let url = try ChatHistoryFixture.makeDatabase(ChatHistoryFixture.snapshot())
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        let before = try ChatHistoryFixture.strings(url, "SELECT turnID, sequence, trackingDayID FROM coach_index ORDER BY sequence")
        #expect(throws: DiaryError.persistenceFailed) { try ChatHistoryFixture.execute(url, "UPDATE coach_index SET sequence = sequence + 10000") }
        #expect(throws: DiaryError.persistenceFailed) { try ChatHistoryFixture.execute(url, "UPDATE coach_index SET trackingDayID = NULL WHERE sequence = 1") }
        #expect(try ChatHistoryFixture.strings(url, "SELECT turnID, sequence, trackingDayID FROM coach_index ORDER BY sequence") == before)
    }

    @Test func normalizedMetadataIsAuthoritativeForCompleteReference() throws {
        let before = ChatHistoryFixture.snapshot()
        let url = try ChatHistoryFixture.makeDatabase(before)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        // A v1 reader must never consult the legacy recovery metadata, even if it cannot decode it.
        try ChatHistoryFixture.execute(url, "UPDATE meta SET payload = x'00'")
        #expect(try ChatHistoryFixture.completeReference(databaseURL: url) == before)
        try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
    }

    @Test func photoConsumersKeepActualOwnerAfterFoodTransferAndForProgressReceipts() throws {
        var before = ChatHistoryFixture.snapshot(exchanges: 3)
        before.coachTurns[0].photos = []
        let progressTurnID = before.coachTurns[1].id
        before.coachTurns[1].receipts = [CoachReceipt(operationKey: progressTurnID.uuidString + "/weight/2027-01-15",
            turnID: progressTurnID, dayID: before.days[0].id, weightID: before.weights[0].id,
            committedRevision: 1, resultJSON: "{\"synthetic\":true}")]
        try before.validate()
        let url = try ChatHistoryFixture.makeDatabase(before)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        #expect(try ChatHistoryFixture.strings(url, "SELECT ownerKind, parentID FROM photo_consumer WHERE turnID = '\(before.coachTurns[0].id.uuidString)'") == [["meal", before.meals[0].id.uuidString]])
        #expect(try ChatHistoryFixture.strings(url, "SELECT ownerKind, parentID FROM photo_consumer WHERE turnID = '\(progressTurnID.uuidString)'") == [["coachTurn", progressTurnID.uuidString]])
        #expect(try ChatHistoryFixture.strings(url, "SELECT COUNT(*) FROM photo_content WHERE ownerKind NOT IN ('meal','coachTurn')") == [["0"]])
    }
}
