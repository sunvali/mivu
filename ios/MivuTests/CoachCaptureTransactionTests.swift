import Foundation
import SQLite3
import Testing
@testable import Mivu

@Suite struct CoachCaptureTransactionTests {
    @Test func connectionBoundaryRejectsIdenticalReplacementAfterSelectionCheck() async throws {
        let fixture = try CaptureFixture(); defer { fixture.remove() }
        let store = DiaryStore(directory: fixture.root)
        let head = try await store.selectPagedProfile(fixture.profileID)
        let identity = try #require(FileManager.default.attributesOfItem(atPath: fixture.url.path)[.systemFileNumber] as? NSNumber).uint64Value
        let payload = try fixture.payload(head: head, photos: [fixture.photo()])
        // Reproduce the exact boundary: selection check succeeds, then an identical new inode replaces it.
        #expect(try await store.diaryHead(expectedProfileID: fixture.profileID) == head)
        let before = try fixture.durableState()
        let replacement = fixture.root.appending(path: "replacement.sqlite")
        let original = fixture.root.appending(path: "preserved-original.sqlite")
        try FileManager.default.copyItem(at: fixture.url, to: replacement)
        try FileManager.default.moveItem(at: fixture.url, to: original)
        try FileManager.default.moveItem(at: replacement, to: fixture.url)
        let replacementIdentity = try #require(FileManager.default.attributesOfItem(atPath: fixture.url.path)[.systemFileNumber] as? NSNumber).uint64Value
        #expect(replacementIdentity != identity)
        #expect(try fixture.durableState(databaseURL: original) == before)
        #expect(try fixture.durableState() == before)
        var acknowledgements = 0
        do {
            let database = try DiaryDatabase(url: fixture.url, expectedFileIdentity: identity)
            _ = try database.captureCoachSubmission(payload, expected: head, maximumBytes: ChatHistoryFixture.maximumBytes)
            acknowledgements += 1
        } catch { #expect(error as? DiaryError == .persistenceFailed) }
        #expect(acknowledgements == 0)
        #expect(try fixture.durableState(databaseURL: original) == before)
        #expect(try fixture.durableState() == before)
        try FileManager.default.removeItem(at: fixture.url)
        #expect(throws: DiaryError.persistenceFailed) {
            try DiaryDatabase(url: fixture.url, create: true, expectedFileIdentity: identity)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.url.path))
        #expect(try fixture.durableState(databaseURL: original) == before)
    }

    @Test func captureAppendsWithoutReadingOrReplacingHistory() async throws {
        let fixture = try CaptureFixture(exchanges: 9_999)
        defer { fixture.remove() }
        let metrics = DiaryQueryDiagnostics()
        let store = DiaryStore(directory: fixture.root, diagnostics: metrics)
        let head = try await store.selectPagedProfile(fixture.profileID)
        let unloadedTurnBefore = try fixture.rows("SELECT id, hex(payload) FROM coach_turn ORDER BY ordinal LIMIT 1")
        let payload = try fixture.payload(head: head, text: "Synthetic append", photos: [fixture.photo()])
        metrics.reset()
        let committed = try await store.captureCoachSubmission(payload, expectedProfileID: fixture.profileID)
        #expect(committed.id == payload.submissionID && committed.sequence == 10_000)
        #expect(committed.photos.map(\.photoID) == payload.attachments.map(\.id))
        #expect(try fixture.rows("SELECT id, hex(payload) FROM coach_turn ORDER BY ordinal LIMIT 1") == unloadedTurnBefore)
        #expect(try fixture.rows("SELECT COUNT(*) FROM coach_turn") == [["10000"]])
        #expect(try fixture.rows("SELECT COUNT(*) FROM meal") == [["1"]])
        #expect(metrics.counters.completeReads == 0 && metrics.counters.completeReconciles == 0)
        #expect(metrics.counters.originalPhotoBytes == 0)
        let over = try fixture.payload(head: try await store.diaryHead(expectedProfileID: fixture.profileID))
        await #expect(throws: DiaryError.invalidData) { try await store.captureCoachSubmission(over, expectedProfileID: fixture.profileID) }
    }

    @Test func repeatedCaptureRetainsDateAndSequence() async throws {
        let fixture = try CaptureFixture(); defer { fixture.remove() }
        let store = DiaryStore(directory: fixture.root)
        let head = try await store.selectPagedProfile(fixture.profileID)
        let payload = try fixture.payload(head: head, text: " exact text \n", photos: [fixture.photo()])
        let first = try await store.captureCoachSubmission(payload, expectedProfileID: fixture.profileID)
        try await store.setCoachTurnState(turnID: first.id, state: .waitingForNetwork, expectedProfileID: fixture.profileID)
        let afterStatus = try await store.diaryHead(expectedProfileID: fixture.profileID)
        // A later profile/day context cannot reinterpret an already accepted attempt.
        try fixture.execute("UPDATE storage_head SET activeDayID = NULL, previousDayConfirmedAt = NULL, activeConversationSegmentID = NULL")
        let reopened = DiaryStore(directory: fixture.root)
        _ = try await reopened.selectPagedProfile(fixture.profileID)
        let retried = try await reopened.captureCoachSubmission(payload, expectedProfileID: fixture.profileID)
        #expect(retried.id == first.id && retried.sequence == first.sequence)
        #expect(retried.capturedAt == first.capturedAt && retried.captureTimeZoneID == first.captureTimeZoneID)
        #expect(retried.trackingDayID == first.trackingDayID && retried.segmentID == first.segmentID)
        #expect(retried.state == .waitingForNetwork)
        #expect(try await reopened.diaryHead(expectedProfileID: fixture.profileID).revision == afterStatus.revision)
        #expect(try fixture.rows("SELECT COUNT(*) FROM coach_turn") == [["2"]])
    }

    @Test func staleRemovedOrReplacedDatabaseRejectsCommit() async throws {
        for failure in ["head", "removed", "replaced", "epoch", "owner"] {
            let fixture = try CaptureFixture(); defer { fixture.remove() }
            let first = DiaryStore(directory: fixture.root), stale = DiaryStore(directory: fixture.root)
            let head = try await first.selectPagedProfile(fixture.profileID)
            _ = try await stale.selectPagedProfile(fixture.profileID)
            let payload = try fixture.payload(head: head)
            switch failure {
            case "head": _ = try await first.captureCoachSubmission(try fixture.payload(head: head), expectedProfileID: fixture.profileID)
            case "removed": try FileManager.default.removeItem(at: fixture.url)
            case "replaced":
                let replacement = fixture.root.appending(path: "replacement")
                try FileManager.default.copyItem(at: fixture.url, to: replacement)
                try FileManager.default.removeItem(at: fixture.url)
                try FileManager.default.moveItem(at: replacement, to: fixture.url)
            case "epoch": await stale.signOut()
            default: break
            }
            let owner = failure == "owner" ? UUID() : fixture.profileID
            await #expect(throws: (any Error).self) { try await stale.captureCoachSubmission(payload, expectedProfileID: owner) }
            if failure != "removed" { #expect(try fixture.rows("SELECT COUNT(*) FROM coach_turn") == [[failure == "head" ? "2" : "1"]]) }
        }
    }

    @Test func quotaAndCommitFailureLeaveHeadAndRowsUnchanged() throws {
        let fixture = try CaptureFixture(); defer { fixture.remove() }
        let database = try DiaryDatabase(url: fixture.url)
        let originalHead = try database.readHead(expectedProfileID: fixture.profileID)
        let before = try fixture.durableState()
        let payload = try fixture.payload(head: originalHead, photos: [fixture.photo()])
        let currentBytes = try #require(Int(fixture.rows("SELECT portableBytes FROM storage_quota")[0][0]))
        #expect(throws: DiaryError.invalidData) { try database.captureCoachSubmission(payload, expected: originalHead, maximumBytes: currentBytes) }
        #expect(try fixture.durableState() == before)
        let probe = CaptureCommitProbe()
        sqlite3_commit_hook(database.connection, { context in
            Unmanaged<CaptureCommitProbe>.fromOpaque(context!).takeUnretainedValue().attempted = true
            return 1
        }, Unmanaged.passUnretained(probe).toOpaque())
        defer { sqlite3_commit_hook(database.connection, nil, nil) }
        var savedAcknowledgementsBeforeCommit = 0
        do {
            _ = try database.captureCoachSubmission(payload, expected: originalHead, maximumBytes: ChatHistoryFixture.maximumBytes)
            savedAcknowledgementsBeforeCommit += 1
        } catch { }
        #expect(probe.attempted)
        #expect(savedAcknowledgementsBeforeCommit == 0)
        #expect(try database.readHead(expectedProfileID: fixture.profileID) == originalHead)
        #expect(try fixture.durableState() == before)
    }

    @Test func crashBeforeCaptureProducesNoAcknowledgementOrMutation() async throws {
        let fixture = try CaptureFixture(); defer { fixture.remove() }
        let store = DiaryStore(directory: fixture.root)
        let head = try await store.selectPagedProfile(fixture.profileID)
        let frozenAttempt = try fixture.payload(head: head, photos: [fixture.photo()])
        let before = try fixture.durableState()
        let reopened = DiaryStore(directory: fixture.root)
        _ = try await reopened.selectPagedProfile(fixture.profileID)
        #expect(try await reopened.reconcileCoachCapture(submissionID: frozenAttempt.submissionID,
            expectedManifest: frozenAttempt.manifest, expectedProfileID: fixture.profileID) == .absent)
        #expect(try fixture.durableState() == before)
        #expect(try fixture.rows("SELECT COUNT(*) FROM meal") == [["1"]])
    }

    @Test func crashAfterCaptureBeforeSchedulingRecoversSameSubmission() async throws {
        let fixture = try CaptureFixture(); defer { fixture.remove() }
        let store = DiaryStore(directory: fixture.root)
        let head = try await store.selectPagedProfile(fixture.profileID)
        let payload = try fixture.payload(head: head, photos: [fixture.photo()])
        let captured = try await store.captureCoachSubmission(payload, expectedProfileID: fixture.profileID)
        // Fresh actor and connection simulate restart after capture, without scheduling any worker.
        let reopened = DiaryStore(directory: fixture.root)
        _ = try await reopened.selectPagedProfile(fixture.profileID)
        let result = try await reopened.reconcileCoachCapture(submissionID: payload.submissionID,
            expectedManifest: payload.manifest, expectedProfileID: fixture.profileID)
        guard case .accepted(let recovered) = result else { Issue.record("accepted capture missing after reopening"); return }
        #expect(recovered == captured && recovered.state == .captured)
        #expect(recovered.id == payload.submissionID && recovered.photos.map(\.photoID) == payload.attachments.map(\.id))
        #expect(try fixture.rows("SELECT COUNT(*) FROM coach_index WHERE turnID = '\(payload.submissionID.uuidString)'") == [["1"]])
        #expect(try fixture.rows("SELECT COUNT(*) FROM meal") == [["1"]])
        #expect(try fixture.rows("SELECT COUNT(*) FROM record_source WHERE turnID = '\(payload.submissionID.uuidString)'") == [["0"]])
    }

    @Test func acceptedIDRejectsChangedTextAttachmentOrContext() async throws {
        let fixture = try CaptureFixture(); defer { fixture.remove() }
        let store = DiaryStore(directory: fixture.root)
        let head = try await store.selectPagedProfile(fixture.profileID)
        let photos = [fixture.photo(), fixture.photo()]
        let original = try fixture.payload(head: head, text: "exact", photos: photos)
        _ = try await store.captureCoachSubmission(original, expectedProfileID: fixture.profileID)
        let before = try fixture.durableState()
        var changedContext = original.context; changedContext.previousDayConfirmedAt = nil
        var changedTime = original.context; changedTime.capturedAt.addTimeInterval(1)
        var changedZone = original.context; changedZone.timeZoneID = "UTC"
        var changedDay = original.context; changedDay.activeDayID = nil
        var changedBytes = photos; changedBytes[0].data.append(42)
        var changedID = photos; changedID[0].id = UUID()
        var changedRole = photos; changedRole[0].role = .after
        var changedDate = photos; changedDate[0].createdAt.addTimeInterval(1)
        let variants = try [
            fixture.payload(head: head, id: original.submissionID, text: "exact ", photos: photos),
            fixture.payload(head: head, id: original.submissionID, text: "exact", photos: Array(photos.reversed())),
            fixture.payload(head: head, id: original.submissionID, text: "exact", photos: changedBytes),
            fixture.payload(head: head, id: original.submissionID, text: "exact", photos: changedID),
            fixture.payload(head: head, id: original.submissionID, text: "exact", photos: changedRole),
            fixture.payload(head: head, id: original.submissionID, text: "exact", photos: changedDate),
            fixture.payload(head: head, id: original.submissionID, text: "exact", photos: photos, context: changedContext),
            fixture.payload(head: head, id: original.submissionID, text: "exact", photos: photos, context: changedTime),
            fixture.payload(head: head, id: original.submissionID, text: "exact", photos: photos, context: changedZone),
            fixture.payload(head: head, id: original.submissionID, text: "exact", photos: photos, context: changedDay)
        ]
        for variant in variants {
            #expect(try await store.reconcileCoachCapture(submissionID: original.submissionID,
                expectedManifest: variant.manifest, expectedProfileID: fixture.profileID) == .conflictingPayload)
            await #expect(throws: DiaryError.staleRevision) { try await store.captureCoachSubmission(variant, expectedProfileID: fixture.profileID) }
        }
        #expect(try fixture.durableState() == before)
    }

    @Test func uncertainCaptureReconcilesWithoutDuplicateOrDraftLoss() async throws {
        let fixture = try CaptureFixture(); defer { fixture.remove() }
        let store = DiaryStore(directory: fixture.root)
        let head = try await store.selectPagedProfile(fixture.profileID)
        let attempted = try fixture.payload(head: head, text: "original draft", photos: [fixture.photo()])
        _ = try await store.captureCoachSubmission(attempted, expectedProfileID: fixture.profileID)
        // The caller loses the returned acknowledgement, then edits its in-memory composer.
        let editedDraft = try fixture.payload(head: head, text: "edited draft", photos: [fixture.photo()])
        let reopened = DiaryStore(directory: fixture.root)
        _ = try await reopened.selectPagedProfile(fixture.profileID)
        guard case .accepted(let accepted) = try await reopened.reconcileCoachCapture(submissionID: attempted.submissionID,
            expectedManifest: attempted.manifest, expectedProfileID: fixture.profileID) else { Issue.record("uncertain attempt not reconciled"); return }
        #expect(accepted.text == "original draft" && accepted.id == attempted.submissionID)
        #expect(editedDraft.text == "edited draft" && editedDraft.manifest != attempted.manifest)
        #expect(try fixture.rows("SELECT COUNT(*) FROM coach_turn") == [["2"]])
        #expect(try await reopened.reconcileCoachCapture(submissionID: editedDraft.submissionID,
            expectedManifest: editedDraft.manifest, expectedProfileID: fixture.profileID) == .absent)
    }

    @Test func diskFullAppendRollsBackWithoutLosingExistingPhotos() throws {
        let fixture = try CaptureFixture(); defer { fixture.remove() }
        let database = try DiaryDatabase(url: fixture.url)
        let head = try database.readHead(expectedProfileID: fixture.profileID)
        let before = try fixture.durableState()
        let pages = try #require(Int(fixture.rows("PRAGMA page_count")[0][0]))
        try database.execute("PRAGMA max_page_count = \(pages)")
        let payload = try fixture.payload(head: head, photos: [fixture.photo(bytes: Data(repeating: 255, count: 200_000))])
        #expect(throws: DiaryError.persistenceFailed) { try database.captureCoachSubmission(payload, expected: head, maximumBytes: ChatHistoryFixture.maximumBytes) }
        #expect(try fixture.durableState() == before)
        #expect(try database.readHead(expectedProfileID: fixture.profileID) == head)
    }

    @Test func frozenManifestUsesExactTextAndBoundedOrderedAttachments() throws {
        let context = CoachCaptureContext(capturedAt: Date(timeIntervalSinceReferenceDate: 0.125), timeZoneID: "UTC", activeDayID: nil, previousDayConfirmedAt: nil)
        let photo = MealPhoto(data: Data("abc".utf8), createdAt: context.capturedAt)
        let payload = try CoachSubmissionPayload(submissionID: UUID(), text: "abc", attachments: [photo], context: context)
        let literal = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect(payload.manifest.textFingerprint == literal)
        #expect(payload.manifest.attachments.map(\.contentFingerprint) == [literal])
        #expect(payload.manifest.attachments.map(\.id) == [photo.id])
        #expect(throws: DiaryError.invalidData) { try CoachSubmissionPayload(submissionID: UUID(), text: "x", attachments: Array(repeating: photo, count: 9), context: context) }
    }

    @Test func newCaptureRejectsStaleContextAndLegacyAcceptedIDs() async throws {
        let fixture = try CaptureFixture(); defer { fixture.remove() }
        let store = DiaryStore(directory: fixture.root)
        let head = try await store.selectPagedProfile(fixture.profileID)
        var context = try fixture.payload(head: head).context; context.previousDayConfirmedAt = nil
        let stale = try fixture.payload(head: head, context: context)
        await #expect(throws: DiaryError.staleRevision) { try await store.captureCoachSubmission(stale, expectedProfileID: fixture.profileID) }
        let legacy = try fixture.payload(head: head, id: fixture.before.coachTurns[0].id)
        #expect(try await store.reconcileCoachCapture(submissionID: legacy.submissionID,
            expectedManifest: legacy.manifest, expectedProfileID: fixture.profileID) == .conflictingPayload)
        await #expect(throws: DiaryError.staleRevision) { try await store.captureCoachSubmission(legacy, expectedProfileID: fixture.profileID) }
        #expect(try fixture.rows("SELECT COUNT(*) FROM coach_turn") == [["1"]])
    }
}

private final class CaptureCommitProbe { var attempted = false }

struct CaptureFixture {
    let root: URL
    let url: URL
    let before: DiarySnapshot
    var profileID: UUID { before.profile.id }
    init(exchanges: Int = 1) throws {
        try self.init(snapshot: ChatHistoryFixture.snapshot(exchanges: exchanges))
    }
    init(snapshot: DiarySnapshot) throws {
        before = snapshot
        root = URL.temporaryDirectory.appending(path: "Capture-" + UUID().uuidString)
        url = root.appending(path: before.profile.id.uuidString + ".sqlite/diary.sqlite")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DiaryDatabase(url: url, create: true).write(before, expected: nil, maximumBytes: ChatHistoryFixture.maximumBytes)
        try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func rows(_ sql: String) throws -> [[String]] { try ChatHistoryFixture.strings(url, sql) }
    func execute(_ sql: String) throws { try ChatHistoryFixture.execute(url, sql) }
    func photo(bytes: Data = Data([255, 255, 255, 0])) -> MealPhoto {
        MealPhoto(data: bytes, createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000.125))
    }
    func payload(head: DiaryHead, id: UUID = UUID(), text: String = "Synthetic capture", photos: [MealPhoto] = [], context: CoachCaptureContext? = nil) throws -> CoachSubmissionPayload {
        try CoachSubmissionPayload(submissionID: id, text: text, attachments: photos,
            context: context ?? CoachCaptureContext(capturedAt: Date(timeIntervalSinceReferenceDate: 800_000_000.125),
                timeZoneID: head.profile.timeZoneID, activeDayID: head.activeDayID, previousDayConfirmedAt: head.previousDayConfirmedAt,
                activeConversationSegmentID: head.effectiveConversationSegmentID))
    }
    func durableState(databaseURL: URL? = nil) throws -> [[[String]]] {
        try ["storage_head", "coach_turn", "coach_photo", "photo", "coach_index", "coach_segment", "photo_content", "photo_consumer", "storage_contribution", "storage_row_count", "storage_quota"].map { table in
            let columns: String
            switch table {
            case "storage_head": columns = "id, schemaVersion, profileID, hex(profilePayload), revision, hex(lineagePayload), activeDayID, previousDayConfirmedAt, timelineGeneration, nextSequence, activeConversationSegmentID"
            case "coach_turn": columns = "id, ordinal, hex(payload)"
            case "photo", "coach_photo": columns = "id, parent, ordinal, hex(payload), hex(bytes)"
            default: columns = "*"
            }
            return try ChatHistoryFixture.strings(databaseURL ?? url, "SELECT \(columns) FROM \(table) ORDER BY rowid")
        }
    }
}
