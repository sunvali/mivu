import Foundation
import SQLite3
import Testing
@testable import Mivu

@Suite struct DiaryExportConcurrencyTests {
    @Test func oneLoadedPageExportsEveryTurnAndPhoto() async throws {
        let f = try CaptureFixture(exchanges: 10_000); defer { f.remove() }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: f.root, diagnostics: metrics)
        _ = try await store.selectPagedProfile(f.profileID)
        let page = try DiaryDatabase(url: f.url).coachPage(.latest, expectedProfileID: f.profileID)
        #expect(page.exchanges.count == 20)
        // Legal physical gaps and chat ordinals must never change immutable sequence order.
        try f.execute("UPDATE coach_turn SET ordinal = 30000 - ordinal * 2")
        try f.execute("UPDATE photo SET ordinal = ordinal * 3 + 7")
        try await store.deleteWeight(id: f.before.weights[0].id, expectedRevision: f.before.weights[0].revision, expectedProfileID: f.profileID)
        var goal = f.before.goals[0]; goal.targets.kcal = 2345
        _ = try await store.setGoals(goal, expectedRevision: goal.revision, expectedProfileID: f.profileID)
        let sourceBefore = try f.durableState()
        metrics.reset()
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let request = try await store.exportRequest(expectedProfileID: f.profileID)
        #expect(metrics.counters.completeReads == 0 && metrics.counters.originalPhotoBytes == 0)
        let ticket = try await coordinator.makeClone(request)
        let roundTrip = try DiaryArchive.decode(try await coordinator.archiveData(ticket))
        #expect(roundTrip.coachTurns.count == 10_000)
        #expect(roundTrip.coachTurns.map(\.id) == f.before.coachTurns.map(\.id))
        #expect(roundTrip.coachTurns.flatMap(\.photos) == f.before.coachTurns.flatMap(\.photos))
        #expect(roundTrip.meals.flatMap(\.photos) == f.before.meals.flatMap(\.photos))
        #expect(roundTrip.weights.isEmpty && roundTrip.deletedWeightIDs.contains(f.before.weights[0].id))
        #expect(roundTrip.goals[0].targets.kcal == 2345)
        #expect(roundTrip.revision == ticket.head.revision)
        #expect(try f.durableState() == sourceBefore)
        #expect(metrics.counters.completeReads == 0 && metrics.counters.originalPhotoBytes == 0)
        try await coordinator.release(ticket)
        #expect(!FileManager.default.fileExists(atPath: ticket.protectedCloneURL.path))
    }

    @Test(arguments: [DiaryExportStage.cloneStep, .serialization])
    func concurrentExportIsOneConsistentRevision(stage: DiaryExportStage) async throws {
        let f = try CaptureFixture(exchanges: 100); defer { f.remove() }
        let store = DiaryStore(directory: f.root), gate = ExportStageGate(stage)
        _ = try await store.selectPagedProfile(f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root, pagesPerStep: 1,
            checkpoint: { stage, url in try await gate.checkpoint(stage, url: url) })
        let request = try await store.exportRequest(expectedProfileID: f.profileID)
        let operation = Task { () async throws -> (DiaryExportTicket, Data) in
            let ticket = try await coordinator.makeClone(request)
            return (ticket, try await coordinator.archiveData(ticket))
        }
        try await gate.waitUntilReached()
        let beforeCapture = try await store.diaryHead(expectedProfileID: f.profileID)
        let payload = try f.payload(head: beforeCapture, text: "Synthetic concurrent capture", photos: [f.photo()])
        let captured = try await capturedSubmission(store, payload, expectedProfileID: f.profileID)
        let committed = try await store.diaryHead(expectedProfileID: f.profileID)
        #expect(committed.revision == beforeCapture.revision + 1)
        #expect(captured.id == payload.submissionID)
        await gate.release()
        let (ticket, bytes) = try await operation.value
        let exported = try DiaryArchive.decode(bytes)
        #expect(exported == (try ChatHistoryFixture.completeReference(databaseURL: ticket.protectedCloneURL)))
        #expect(exported.revision == ticket.head.revision)
        #expect(exported.coachTurns.contains { $0.id == captured.id } == (exported.revision == committed.revision))
        if stage == .cloneStep { #expect(ticket.head.revision == committed.revision) }
        else { #expect(ticket.head.revision == request.head.revision) }
        #expect(try await store.diaryHead(expectedProfileID: f.profileID) == committed)
        try await coordinator.release(ticket)
    }

    @Test func onlineBackupIncludesCommittedWALPagesWithoutWritingSource() async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        _ = try await store.selectPagedProfile(f.profileID)
        let request = try await store.exportRequest(expectedProfileID: f.profileID)
        var source: OpaquePointer?
        try #require(sqlite3_open(f.url.path, &source) == SQLITE_OK)
        defer { sqlite3_close(source) }
        try #require(sqlite3_exec(source, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; PRAGMA application_id=192837", nil, nil, nil) == SQLITE_OK)
        let wal = URL(fileURLWithPath: f.url.path + "-wal")
        let sourceBefore = try Data(contentsOf: f.url), walBefore = try Data(contentsOf: wal)
        #expect(!walBefore.isEmpty)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let ticket = try await coordinator.makeClone(request)
        #expect(try ChatHistoryFixture.strings(ticket.protectedCloneURL, "PRAGMA application_id") == [["192837"]])
        #expect(try Data(contentsOf: f.url) == sourceBefore)
        #expect(try Data(contentsOf: wal) == walBefore)
        #expect(try await coordinator.completeSnapshot(ticket) == f.before)
        try await coordinator.release(ticket)
    }

    @Test func diskFullBackupRemovesPartialCloneAndLeavesLiveDiaryWritable() async throws {
        let f = try CaptureFixture(exchanges: 100); defer { f.remove() }
        let store = DiaryStore(directory: f.root), probe = ExportFaultProbe()
        let head = try await store.selectPagedProfile(f.profileID)
        let scratch = try exportScratch(in: f.root)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: scratch, pagesPerStep: 1,
            checkpoint: { stage, url in
                if stage == .cloneStep { await probe.record(url); throw POSIXError(.ENOSPC) }
            })
        let request = try await store.exportRequest(expectedProfileID: f.profileID)
        let before = try f.durableState(), bytes = try Data(contentsOf: f.url)
        await #expect(throws: (any Error).self) { try await coordinator.makeClone(request) }
        #expect(await probe.reached)
        #expect(try f.durableState() == before)
        #expect(try Data(contentsOf: f.url) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path) == ["unrelated-sentinel"])
        let payload = try f.payload(head: head)
        #expect(try await capturedSubmission(store, payload, expectedProfileID: f.profileID).id == payload.submissionID)
    }

    @Test(arguments: [DiaryExportStage.cloneCreated, .cloneStep])
    func cancelledExportRemovesOwnedTemporaryFiles(stage: DiaryExportStage) async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root), gate = ExportStageGate(stage)
        _ = try await store.selectPagedProfile(f.profileID)
        let scratch = try exportScratch(in: f.root)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: scratch, pagesPerStep: 1,
            checkpoint: { stage, url in try await gate.checkpoint(stage, url: url) })
        let request = try await store.exportRequest(expectedProfileID: f.profileID)
        let before = try f.durableState()
        let operation = Task { try await coordinator.makeClone(request) }
        try await gate.waitUntilReached()
        operation.cancel(); await gate.release()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(try f.durableState() == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path) == ["unrelated-sentinel"])
    }

    @Test(arguments: ["replacement", "missing", "reselection"])
    func changedSourceRejectsCloneHandoffWithoutRecreatingIt(change: String) async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root), gate = ExportStageGate(.cloneReady)
        _ = try await store.selectPagedProfile(f.profileID)
        let scratch = try exportScratch(in: f.root)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: scratch,
            checkpoint: { stage, url in try await gate.checkpoint(stage, url: url) })
        let request = try await store.exportRequest(expectedProfileID: f.profileID)
        let operation = Task { try await coordinator.makeClone(request) }
        try await gate.waitUntilReached()
        let preserved = f.root.appending(path: "preserved-source.sqlite")
        if change == "reselection" { _ = try await store.selectPagedProfile(f.profileID) }
        else {
            try FileManager.default.moveItem(at: f.url, to: preserved)
            if change == "replacement" { try FileManager.default.copyItem(at: preserved, to: f.url) }
        }
        await gate.release()
        await #expect(throws: (any Error).self) { try await operation.value }
        if change == "missing" { #expect(!FileManager.default.fileExists(atPath: f.url.path)) }
        else { #expect(try ChatHistoryFixture.completeReference(databaseURL: f.url) == f.before) }
        #expect(try Data(contentsOf: scratch.appending(path: "unrelated-sentinel")) == Data([42]))
    }

    @Test(arguments: [1, 2, 3])
    func archiveVersionsOneTwoThreeRemainReadable(version: Int) async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        _ = try await store.selectPagedProfile(f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let ticket = try await coordinator.makeClone(try await store.exportRequest(expectedProfileID: f.profileID))
        var envelope = try #require(JSONSerialization.jsonObject(with: try await coordinator.archiveData(ticket)) as? [String: Any])
        envelope["version"] = version
        #expect(try DiaryArchive.decode(JSONSerialization.data(withJSONObject: envelope)) == f.before)
        try await coordinator.release(ticket)
    }

    @Test func archiveRoundTripRetainsSubmissionManifestAndReceiptBinding() async throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 4)
        let photo = source.meals[0].photos[0], originalMeal = source.meals[0]
        let segment = source.coachTurns[0].id
        let context = CoachCaptureContext(capturedAt: originalMeal.capturedAt, timeZoneID: source.profile.timeZoneID,
            activeDayID: source.activeDayID, previousDayConfirmedAt: source.previousDayConfirmedAt, activeConversationSegmentID: segment)
        let payload = try CoachSubmissionPayload(submissionID: UUID(), text: "Synthetic accepted original / 🍎", attachments: [photo],
            context: context, pendingMealID: originalMeal.id, pendingMealRevision: originalMeal.revision)
        source.meals[0].submissions.append(MealSubmission(id: payload.submissionID, baseRevision: 1,
            text: payload.text, photoIDs: [photo.id], reviewFirst: false))
        source.coachTurns.append(CoachTurn(id: payload.submissionID, capturedAt: context.capturedAt, text: payload.text,
            captureTimeZoneID: context.timeZoneID, activeDayID: context.activeDayID, photoIDs: [photo.id],
            resolvedDayID: originalMeal.dayID, pendingMealID: originalMeal.id, pendingMealRevision: 1,
            submissionManifest: payload.manifest, captureSegmentID: segment))
        source.activeConversationSegmentID = segment
        let f = try CaptureFixture(snapshot: source); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        _ = try await store.selectPagedProfile(f.profileID)
        let item = FoodItem(name: "Synthetic portion", quantity: 2, unit: "piece", nutrition: NutritionValues(kcal: 200))
        let write = CoachWrite.food(date: f.before.days[1].localDate, items: [item], eatenAt: nil)
        var receipts = try await store.applyCoachWrites([write], turnID: payload.submissionID,
            epoch: store.selectionEpoch(expectedProfileID: f.profileID), expectedProfileID: f.profileID)
        let mealID = try #require(receipts[0].mealID)
        var changed = item; changed.quantity = 3
        receipts += try await store.applyCoachWrites([.correction(mealID: mealID, item: changed, revision: 2)], turnID: payload.submissionID,
            epoch: store.selectionEpoch(expectedProfileID: f.profileID), expectedProfileID: f.profileID)
        try await store.deletePhoto(mealID: mealID, photoID: photo.id, expectedProfileID: f.profileID)
        try await store.deleteMeal(mealID, expectedProfileID: f.profileID)
        let oldReference = try #require(try DiaryDatabase(url: f.url).coachPage(.latest, expectedProfileID: f.profileID).exchanges.first { $0.id == source.coachTurns[1].id }?.photos.first)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let ticket = try await coordinator.makeClone(try await store.exportRequest(expectedProfileID: f.profileID))
        let portable = try DiaryArchive.decode(try await coordinator.archiveData(ticket))
        let accepted = try #require(portable.coachTurns.first { $0.id == payload.submissionID })
        #expect(accepted.submissionManifest == payload.manifest)
        #expect(accepted.pendingMealRevision != payload.manifest.pendingMealRevision)
        #expect(accepted.photos.isEmpty && !accepted.photoIDs.contains(photo.id))
        #expect(accepted.receipts == receipts && receipts[0].commandFingerprint?.count == 64)
        #expect(portable.coachTurns[0].receipts[0].commandFingerprint == nil)
        let prepared = try await coordinator.prepareReplacement(portable, replacing: ticket)
        try assertExportAccounting(prepared.protectedDatabaseURL)
        let restoredHead = try await store.installReplacement(prepared)
        #expect(restoredHead.timelineGeneration != ticket.head.timelineGeneration)
        let restored = try ChatHistoryFixture.completeReference(databaseURL: f.url)
        #expect(restored.coachTurns == portable.coachTurns)
        #expect(restored.activeConversationSegmentID == portable.activeConversationSegmentID)
        #expect(restored.revision == portable.revision + 1)
        #expect(restored.coachTurns.first { $0.id == payload.submissionID }?.receipts == receipts)
        await #expect(throws: DiaryError.notFound) {
            try await store.applyCoachWrites([write], turnID: payload.submissionID,
                epoch: store.selectionEpoch(expectedProfileID: f.profileID), expectedProfileID: f.profileID, mode: .replayOnly)
        }
        await #expect(throws: (any Error).self) { try await store.photoContent(oldReference, expectedProfileID: f.profileID) }
        #expect(try f.rows("SELECT COUNT(*) FROM record_source WHERE recordID = '\(mealID)'") == [["0"]])
        #expect(!restored.meals.contains { $0.id == mealID })
        try assertExportAccounting(f.url)
        try await coordinator.release(ticket)
    }

    @Test func ordinaryNewCaptureTransfersOriginalAttachmentWithoutRewritingAcceptedManifest() async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        let head = try await store.selectPagedProfile(f.profileID)
        let photo = f.photo(), payload = try f.payload(head: head, photos: [photo])
        _ = try await capturedSubmission(store, payload, expectedProfileID: f.profileID)
        let receipt = try await store.applyCoachFood(turnID: payload.submissionID, targetLocalDate: f.before.days[0].localDate,
            items: [FoodItem(name: "Synthetic transferred photo", nutrition: NutritionValues(kcal: 100))], expectedProfileID: f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let ticket = try await coordinator.makeClone(try await store.exportRequest(expectedProfileID: f.profileID))
        let portable = try DiaryArchive.decode(try await coordinator.archiveData(ticket))
        let accepted = try #require(portable.coachTurns.first { $0.id == payload.submissionID })
        #expect(accepted.submissionManifest == payload.manifest && accepted.photos.isEmpty)
        #expect(portable.meals.first { $0.id == receipt.mealID }?.photos == [photo])
        #expect(accepted.receipts == [receipt])
        try await coordinator.release(ticket)
    }

    @Test(arguments: ["nil", "empty", "populated"])
    func replacementPreservesRawLegacyAndExplicitBoundariesWithFreshTokens(boundary: String) async throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 4)
        let populated = UUID(), empty = UUID()
        if boundary != "nil" {
            for index in source.coachTurns.indices { source.coachTurns[index].captureSegmentID = populated }
        }
        source.activeConversationSegmentID = boundary == "nil" ? nil : (boundary == "empty" ? empty : populated)
        let f = try CaptureFixture(snapshot: source); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        _ = try await store.selectPagedProfile(f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let ticket = try await coordinator.makeClone(try await store.exportRequest(expectedProfileID: f.profileID))
        let archived = try DiaryArchive.decode(try await coordinator.archiveData(ticket))
        #expect(archived == source)
        let tokens = try f.rows("SELECT contentToken FROM photo_content ORDER BY ownerKind,parentID,photoID")
        let prepared = try await coordinator.prepareReplacement(archived, replacing: ticket)
        let restoredHead = try await store.installReplacement(prepared)
        #expect(restoredHead.timelineGeneration != ticket.head.timelineGeneration)
        #expect(try f.rows("SELECT contentToken FROM photo_content ORDER BY ownerKind,parentID,photoID") != tokens)
        let restored = try ChatHistoryFixture.completeReference(databaseURL: f.url)
        #expect(restored.activeConversationSegmentID == source.activeConversationSegmentID)
        #expect(restored.coachTurns == source.coachTurns)
        try assertExportAccounting(f.url)
        try await coordinator.release(ticket)
    }

    @Test(arguments: ["submission", "text", "instant", "segment", "duplicateAttachment", "fingerprint"])
    func malformedAcceptedManifestIsRejectedAtArchiveTrustBoundary(change: String) throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 1)
        let context = CoachCaptureContext(capturedAt: source.coachTurns[0].capturedAt, timeZoneID: source.coachTurns[0].captureTimeZoneID,
            activeDayID: source.coachTurns[0].activeDayID, previousDayConfirmedAt: source.previousDayConfirmedAt,
            activeConversationSegmentID: UUID())
        let payload = try CoachSubmissionPayload(submissionID: source.coachTurns[0].id, text: source.coachTurns[0].text,
            attachments: source.coachTurns[0].photos, context: context)
        source.coachTurns[0].captureSegmentID = context.activeConversationSegmentID
        source.coachTurns[0].submissionManifest = payload.manifest
        var envelope = try #require(JSONSerialization.jsonObject(with: DiaryArchive.encode(source)) as? [String: Any])
        var body = try #require(envelope["snapshot"] as? [String: Any])
        var turns = try #require(body["coachTurns"] as? [[String: Any]])
        var manifest = try #require(turns[0]["submissionManifest"] as? [String: Any])
        switch change {
        case "submission": manifest["submissionID"] = UUID().uuidString
        case "text": manifest["textFingerprint"] = String(repeating: "0", count: 64)
        case "instant":
            var capture = try #require(manifest["context"] as? [String: Any]); capture["capturedAt"] = 1; manifest["context"] = capture
        case "segment":
            var capture = try #require(manifest["context"] as? [String: Any]); capture["activeConversationSegmentID"] = UUID().uuidString; manifest["context"] = capture
        default:
            var attachments = try #require(manifest["attachments"] as? [[String: Any]])
            if change == "duplicateAttachment" { attachments.append(attachments[0]) }
            else { attachments[0]["contentFingerprint"] = "invalid" }
            manifest["attachments"] = attachments
        }
        turns[0]["submissionManifest"] = manifest; body["coachTurns"] = turns; envelope["snapshot"] = body
        #expect(throws: DiaryError.invalidData) { try DiaryArchive.decode(JSONSerialization.data(withJSONObject: envelope)) }
    }

    @Test(arguments: [DiaryExportStage.replacementBuild, .replacementValidated])
    func validatedRestoreFailurePreservesLiveDatabase(stage: DiaryExportStage) async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root), probe = ExportFaultProbe()
        let head = try await store.selectPagedProfile(f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root,
            checkpoint: { current, url in if current == stage { await probe.record(url); throw POSIXError(.ENOSPC) } })
        let ticket = try await coordinator.makeClone(try await store.exportRequest(expectedProfileID: f.profileID))
        let before = try f.durableState(), bytes = try Data(contentsOf: f.url)
        await #expect(throws: (any Error).self) { try await coordinator.prepareReplacement(f.before, replacing: ticket) }
        #expect(await probe.reached)
        #expect(try f.durableState() == before && Data(contentsOf: f.url) == bytes)
        let candidate = try #require(await probe.url)
        if stage == .replacementValidated {
            #expect(FileManager.default.fileExists(atPath: candidate.path))
            #expect(try ChatHistoryFixture.completeReference(databaseURL: candidate).revision == f.before.revision + 1)
        } else { #expect(!FileManager.default.fileExists(atPath: candidate.path)) }
        let payload = try f.payload(head: head)
        #expect(try await capturedSubmission(store, payload, expectedProfileID: f.profileID).id == payload.submissionID)
        try await coordinator.release(ticket)
    }

    @Test func finalReplacementFailurePreservesValidatedRecoveryAndLaterCaptureRejectsPreparedSwitch() async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        let head = try await store.selectPagedProfile(f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let ticket = try await coordinator.makeClone(try await store.exportRequest(expectedProfileID: f.profileID))
        let prepared = try await coordinator.prepareReplacement(f.before, replacing: ticket)
        let before = try Data(contentsOf: f.url)
        await #expect(throws: (any Error).self) {
            try await store.installReplacement(prepared, beforeSwitch: { throw POSIXError(.ENOSPC) })
        }
        #expect(try Data(contentsOf: f.url) == before)
        #expect(FileManager.default.fileExists(atPath: prepared.protectedDatabaseURL.path))
        let payload = try f.payload(head: head)
        _ = try await capturedSubmission(store, payload, expectedProfileID: f.profileID)
        let committed = try f.durableState()
        await #expect(throws: (any Error).self) { try await store.installReplacement(prepared) }
        #expect(try f.durableState() == committed)
        #expect(FileManager.default.fileExists(atPath: prepared.protectedDatabaseURL.path))
        try await coordinator.release(ticket)
    }

    @Test(arguments: ["reselection", "inode", "deleted"])
    func preparedReplacementRejectsChangedSelectionOrSource(change: String) async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        _ = try await store.selectPagedProfile(f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let ticket = try await coordinator.makeClone(try await store.exportRequest(expectedProfileID: f.profileID))
        let prepared = try await coordinator.prepareReplacement(f.before, replacing: ticket)
        if change == "reselection" {
            let other = try addProfile(in: f.root)
            _ = try await store.selectPagedProfile(other); _ = try await store.selectPagedProfile(f.profileID)
        } else if change == "deleted" { try await store.deleteProfile(f.profileID) }
        else {
            let preserved = f.root.appending(path: "preserved-before-switch.sqlite")
            try FileManager.default.moveItem(at: f.url, to: preserved)
            try FileManager.default.copyItem(at: preserved, to: f.url)
        }
        await #expect(throws: (any Error).self) { try await store.installReplacement(prepared) }
        #expect(FileManager.default.fileExists(atPath: prepared.protectedDatabaseURL.path))
        if change == "deleted" { #expect(!FileManager.default.fileExists(atPath: f.url.path)) }
        else { #expect(try ChatHistoryFixture.completeReference(databaseURL: f.url) == f.before) }
        try await coordinator.release(ticket)
    }

    @Test(arguments: ["older", "diverged", "resurrection", "wrongOwner"])
    func preparedRestorePreservesExistingOwnershipLineageAndDeletionPolicy(change: String) async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        _ = try await store.selectPagedProfile(f.profileID)
        try await store.deleteWeight(id: f.before.weights[0].id, expectedRevision: 1, expectedProfileID: f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let ticket = try await coordinator.makeClone(try await store.exportRequest(expectedProfileID: f.profileID))
        var incoming = try await coordinator.completeSnapshot(ticket)
        switch change {
        case "older": incoming.revision -= 1
        case "diverged": incoming.revision += 1; incoming.lineage = [UUID()]
        case "wrongOwner": incoming.profile.id = UUID()
        default:
            incoming.revision += 1; incoming.lineage = (incoming.lineage ?? []) + [UUID()]
            incoming.weights = f.before.weights; incoming.deletedWeightIDs = []
        }
        let before = try f.durableState()
        await #expect(throws: change == "wrongOwner" ? DiaryError.wrongOwner : DiaryError.staleArchive) {
            try await coordinator.prepareReplacement(incoming, replacing: ticket)
        }
        #expect(try f.durableState() == before)
        try await coordinator.release(ticket)
    }

    @Test func providerSuspensionAllowsCaptureAndAcknowledgesOnlyActualCloneRevision() async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root), gate = ExportStageGate(.providerWritten)
        let head = try await store.selectPagedProfile(f.profileID)
        let (backup, generation, folder) = try await configuredBackup(f)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root,
            checkpoint: { stage, url in try await gate.checkpoint(stage, url: url) })
        let request = try await store.exportRequest(expectedProfileID: f.profileID, backupGeneration: generation)
        let operation = Task { try await gate.observe { try await backup.save(request, coordinator: coordinator) } }
        try await gate.waitUntilReached()
        let payload = try f.payload(head: head)
        _ = try await capturedSubmission(store, payload, expectedProfileID: f.profileID)
        #expect(try await store.diaryHead(expectedProfileID: f.profileID).revision == head.revision + 1)
        await gate.release(); try await operation.value
        #expect(try DiaryArchive.readContents(folder.appending(path: FolderBackup.filename(profileID: f.profileID))) == f.before)
        #expect(await backup.status(profileID: f.profileID).savedAt != nil)
        #expect(!FileManager.default.fileExists(atPath: f.root.appending(path: "diary-export-" + request.operationID.uuidString).path))
    }

    @Test func folderChangeAfterAcknowledgementPreservesOnlyCompletedBackupUntilNewDestinationSucceeds() async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root), gate = ExportStageGate(.acknowledged)
        _ = try await store.selectPagedProfile(f.profileID)
        let (backup, generation, folderA) = try await configuredBackup(f)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root,
            checkpoint: { stage, url in try await gate.checkpoint(stage, url: url) })
        let requestA = try await store.exportRequest(expectedProfileID: f.profileID, backupGeneration: generation)
        let operationA = Task { try await gate.observe { try await backup.save(requestA, coordinator: coordinator) } }
        try await gate.waitUntilReached()
        #expect(await backup.status(profileID: f.profileID).savedAt != nil)
        let outputA = folderA.appending(path: FolderBackup.filename(profileID: f.profileID))
        let completedA = try Data(contentsOf: outputA)
        #expect(try DiaryArchive.decode(completedA) == f.before)
        let folderB = try exportFolder(in: f.root, name: "pending-provider-B")
        let outputB = folderB.appending(path: FolderBackup.filename(profileID: f.profileID))
        try await backup.selectFolder(folderB, profileID: f.profileID)
        await gate.release()
        await #expect(throws: DiaryError.wrongOwner) { try await operationA.value }
        #expect(FileManager.default.fileExists(atPath: outputA.path))
        #expect(try Data(contentsOf: outputA) == completedA)
        #expect(!FileManager.default.fileExists(atPath: outputB.path))
        let pendingB = await backup.status(profileID: f.profileID)
        #expect(pendingB.configured && pendingB.savedAt == nil && pendingB.pendingError != nil)
        let requestB = try await store.exportRequest(expectedProfileID: f.profileID, backupGeneration: generation)
        try await backup.save(requestB, coordinator: coordinator)
        #expect(try DiaryArchive.readContents(outputB) == f.before)
        #expect(!FileManager.default.fileExists(atPath: outputA.path))
        let savedB = await backup.status(profileID: f.profileID)
        #expect(savedB.savedAt != nil && savedB.pendingError == nil)
    }

    @Test(arguments: ["reselection", "restore", "delete", "replacement", "generation", "folder", "retired"])
    func deleteRestoreOrReplacementRejectsDelayedAcknowledgement(change: String) async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root), gate = ExportStageGate(.acknowledgement)
        var head = try await store.selectPagedProfile(f.profileID)
        let (backup, generation, folder) = try await configuredBackup(f)
        try await backup.save(f.before, generation: generation)
        let previousDate = await backup.status(profileID: f.profileID).savedAt
        if change != "retired" {
            _ = try await capturedSubmission(store, try f.payload(head: head), expectedProfileID: f.profileID)
            head = try await store.diaryHead(expectedProfileID: f.profileID)
        }
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root,
            checkpoint: { stage, url in try await gate.checkpoint(stage, url: url) })
        let request = try await store.exportRequest(expectedProfileID: f.profileID, backupGeneration: generation)
        let operation = Task { try await gate.observe { try await backup.save(request, coordinator: coordinator) } }
        try await gate.waitUntilReached()
        switch change {
        case "reselection":
            let other = try addProfile(in: f.root)
            _ = try await store.selectPagedProfile(other); _ = try await store.selectPagedProfile(f.profileID)
        case "restore":
            let replacementCoordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
            let replacementTicket = try await replacementCoordinator.makeClone(try await store.exportRequest(expectedProfileID: f.profileID))
            let prepared = try await replacementCoordinator.prepareReplacement(
                replacementCoordinator.completeSnapshot(replacementTicket), replacing: replacementTicket)
            _ = try await store.installReplacement(prepared)
            try await replacementCoordinator.release(replacementTicket)
        case "delete": try await store.deleteProfile(f.profileID)
        case "replacement":
            let preserved = f.root.appending(path: "preserved-before-ack.sqlite")
            try FileManager.default.moveItem(at: f.url, to: preserved)
            try FileManager.default.copyItem(at: preserved, to: f.url)
        case "generation": _ = try await backup.authorizeRestoredProfile(f.profileID)
        case "folder": try await backup.selectFolder(exportFolder(in: f.root, name: "new-provider"), profileID: f.profileID)
        default: try await backup.removeProfile(f.profileID)
        }
        await gate.release()
        await #expect(throws: (any Error).self) { try await operation.value }
        let status = await backup.status(profileID: f.profileID)
        #expect(status.savedAt == (change == "folder" || change == "retired" ? nil : previousDate))
        let output = folder.appending(path: FolderBackup.filename(profileID: f.profileID))
        if change == "retired" { #expect(!FileManager.default.fileExists(atPath: output.path)) }
        else { #expect(try DiaryArchive.readContents(output).revision == head.revision) }
        if change == "delete" { #expect(!FileManager.default.fileExists(atPath: f.url.path)) }
    }

    @Test(arguments: [DiaryExportStage.serialization, .providerWrite])
    func failedSerializationOrProviderWriteDoesNotAcknowledgeBackup(stage: DiaryExportStage) async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root), probe = ExportFaultProbe()
        let head = try await store.selectPagedProfile(f.profileID)
        let (backup, generation, folder) = try await configuredBackup(f)
        try await backup.save(f.before, generation: generation)
        let priorDate = await backup.status(profileID: f.profileID).savedAt
        let output = folder.appending(path: FolderBackup.filename(profileID: f.profileID)), priorBytes = try Data(contentsOf: output)
        _ = try await capturedSubmission(store, try f.payload(head: head), expectedProfileID: f.profileID)
        let before = try f.durableState()
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root,
            checkpoint: { current, url in if current == stage { await probe.record(url); throw POSIXError(.ENOSPC) } })
        let request = try await store.exportRequest(expectedProfileID: f.profileID, backupGeneration: generation)
        await #expect(throws: (any Error).self) { try await backup.save(request, coordinator: coordinator) }
        #expect(await probe.reached)
        #expect(await backup.status(profileID: f.profileID).savedAt == priorDate)
        #expect(await backup.status(profileID: f.profileID).pendingError != nil)
        #expect(try Data(contentsOf: output) == priorBytes && f.durableState() == before)
        #expect(!FileManager.default.fileExists(atPath: f.root.appending(path: "diary-export-" + request.operationID.uuidString).path))
    }

    @Test func acknowledgementPersistenceFailureRetainsValidProviderOutputAndHighWater() async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        let head = try await store.selectPagedProfile(f.profileID)
        let (baseline, generation, folder) = try await configuredBackup(f)
        try await baseline.save(f.before, generation: generation)
        let previousDate = await baseline.status(profileID: f.profileID).savedAt
        let backup = FolderBackup(directory: f.root.appending(path: "backup-metadata"),
            beforeAcknowledgementWrite: { _ in throw POSIXError(.ENOSPC) })
        await backup.selectProfile(f.profileID)
        _ = try await capturedSubmission(store, try f.payload(head: head), expectedProfileID: f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let request = try await store.exportRequest(expectedProfileID: f.profileID, backupGeneration: generation)
        await #expect(throws: (any Error).self) { try await backup.save(request, coordinator: coordinator) }
        let completed = try DiaryArchive.readContents(folder.appending(path: FolderBackup.filename(profileID: f.profileID)))
        #expect(completed.revision == request.head.revision && completed.coachTurns.count == 2)
        #expect(await backup.status(profileID: f.profileID).savedAt == previousDate)
        #expect(await backup.status(profileID: f.profileID).pendingError != nil)
        let reopened = FolderBackup(directory: f.root.appending(path: "backup-metadata"))
        await reopened.selectProfile(f.profileID)
        #expect(await reopened.status(profileID: f.profileID).savedAt == previousDate)
        await #expect(throws: DiaryError.staleArchive) { try await reopened.save(f.before, generation: generation) }
    }

    @Test(arguments: [DiaryExportStage.serialized, .providerWritten])
    func cancelledBackupKeepsCompletedProviderOutputAndRejectsAcknowledgement(stage: DiaryExportStage) async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root), gate = ExportStageGate(stage)
        _ = try await store.selectPagedProfile(f.profileID)
        let (backup, generation, folder) = try await configuredBackup(f)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root,
            checkpoint: { current, url in try await gate.checkpoint(current, url: url) })
        let request = try await store.exportRequest(expectedProfileID: f.profileID, backupGeneration: generation)
        let operation = Task { try await gate.observe { try await backup.save(request, coordinator: coordinator) } }
        try await gate.waitUntilReached(); operation.cancel(); await gate.release()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await backup.status(profileID: f.profileID).savedAt == nil)
        let output = folder.appending(path: FolderBackup.filename(profileID: f.profileID))
        if stage == .providerWritten { #expect(try DiaryArchive.readContents(output) == f.before) }
        else { #expect(!FileManager.default.fileExists(atPath: output.path)) }
        #expect(!FileManager.default.fileExists(atPath: f.root.appending(path: "diary-export-" + request.operationID.uuidString).path))
    }

    @Test func unconfiguredBackupDoesNotCloneOrAssembleCompleteProfile() async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let metrics = DiaryQueryDiagnostics(), probe = ExportFaultProbe()
        let store = DiaryStore(directory: f.root, diagnostics: metrics)
        _ = try await store.selectPagedProfile(f.profileID)
        let backup = FolderBackup(directory: f.root.appending(path: "backup-metadata"))
        await backup.selectProfile(f.profileID)
        let generation = try await backup.generation(profileID: f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root,
            checkpoint: { _, url in await probe.record(url) })
        metrics.reset()
        try await backup.save(store.exportRequest(expectedProfileID: f.profileID, backupGeneration: generation), coordinator: coordinator)
        #expect(!(await probe.reached))
        #expect(metrics.counters.completeReads == 0 && metrics.counters.originalPhotoBytes == 0)
    }

    @Test func legacyRecoveryAndRepeatedEmptyDayBoundariesSurvivePortableReplacement() async throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 3)
        let a1 = UUID()
        source.activeConversationSegmentID = a1
        for index in source.coachTurns.indices { source.coachTurns[index].captureSegmentID = a1 }
        let orphan = MealSubmission(baseRevision: 1, text: "Synthetic inferred legacy capture", photoIDs: [], reviewFirst: false)
        source.meals[0].submissions = [orphan]
        let f = try CaptureFixture(snapshot: source); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        _ = try await store.selectPagedProfile(f.profileID)
        _ = try await store.preparePendingCoachTurn(turnID: orphan.id, expectedProfileID: f.profileID)
        let inferred = try await store.coachWorkItem(turnID: orphan.id, expectedProfileID: f.profileID)
        #expect(inferred.activeDayID == nil && inferred.resolvedDayID == source.meals[0].dayID)
        let afterLegacy = try await store.diaryHead(expectedProfileID: f.profileID)
        #expect(afterLegacy.activeConversationSegmentID != a1)
        _ = try await store.startDay(at: source.days[0].startAt.addingTimeInterval(86_400), expectedProfileID: f.profileID)
        let emptyB = try await store.diaryHead(expectedProfileID: f.profileID).activeConversationSegmentID
        _ = try await store.startDay(at: source.days[0].startAt, expectedProfileID: f.profileID)
        let emptyA2 = try await store.diaryHead(expectedProfileID: f.profileID).activeConversationSegmentID
        #expect(emptyA2 != nil && emptyA2 != emptyB && emptyA2 != a1)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let ticket = try await coordinator.makeClone(try await store.exportRequest(expectedProfileID: f.profileID))
        let archived = try DiaryArchive.decode(try await coordinator.archiveData(ticket))
        let legacy = try #require(archived.coachTurns.first { $0.id == orphan.id })
        #expect(legacy.submissionManifest == nil && legacy.activeDayID == nil)
        #expect(legacy.capturedAt == source.meals[0].capturedAt && legacy.captureTimeZoneID == source.days[1].timeZoneID)
        let prepared = try await coordinator.prepareReplacement(archived, replacing: ticket)
        _ = try await store.installReplacement(prepared)
        let restored = try ChatHistoryFixture.completeReference(databaseURL: f.url)
        #expect(restored.coachTurns == archived.coachTurns && restored.activeConversationSegmentID == emptyA2)
        try assertExportAccounting(prepared.request.sourceURL)
        try await coordinator.release(ticket)
    }

    @Test(arguments: ["missingIndex", "orphanPhoto", "compositeOwner", "captureMismatch"])
    func physicalCloneCorruptionCannotBypassAssemblerValidation(kind: String) async throws {
        let f = try CaptureFixture(exchanges: 3); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        _ = try await store.selectPagedProfile(f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let ticket = try await coordinator.makeClone(try await store.exportRequest(expectedProfileID: f.profileID))
        let url = ticket.protectedCloneURL
        switch kind {
        case "missingIndex": try ChatHistoryFixture.execute(url, "DELETE FROM coach_index WHERE sequence = 1")
        case "orphanPhoto": try ChatHistoryFixture.execute(url, "PRAGMA foreign_keys=OFF; UPDATE coach_photo SET parent='\(UUID())' WHERE ordinal=0")
        case "compositeOwner":
            try ChatHistoryFixture.execute(url, "PRAGMA foreign_keys=OFF; UPDATE coach_photo SET parent='\(f.before.coachTurns[1].id)' WHERE parent='\(f.before.coachTurns[0].id)'")
        default:
            try ChatHistoryFixture.changePayload(url, table: "coach_turn") { row in row["capturedAt"] = (row["capturedAt"] as! Double) + 1 }
        }
        await #expect(throws: (any Error).self) { try await coordinator.completeSnapshot(ticket) }
        #expect(try ChatHistoryFixture.completeReference(databaseURL: f.url) == f.before)
        try await coordinator.release(ticket)
    }

    @Test func exactAndOneByteBelowPortableBudgetsUseActualCloneContent() async throws {
        let f = try CaptureFixture(exchanges: 25); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        _ = try await store.selectPagedProfile(f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let request = try await store.exportRequest(expectedProfileID: f.profileID)
        let exact = try JSONEncoder().encode(f.before).count
        func budget(_ count: Int) -> DiaryExportRequest {
            DiaryExportRequest(operationID: UUID(), profileID: request.profileID, head: request.head,
                selectionEpoch: request.selectionEpoch, sourceURL: request.sourceURL, sourceFileIdentity: request.sourceFileIdentity,
                backupGeneration: nil, storageVersion: request.storageVersion, maximumBytes: count)
        }
        let valid = try await coordinator.makeClone(budget(exact))
        #expect(try await coordinator.completeSnapshot(valid) == f.before)
        try assertExportAccounting(valid.protectedCloneURL)
        let short = try await coordinator.makeClone(budget(exact - 1))
        await #expect(throws: DiaryError.invalidData) { try await coordinator.completeSnapshot(short) }
        try await coordinator.release(valid); try await coordinator.release(short)
    }

    @Test func normalizedMetadataExactBudgetIgnoresStaleLegacyMetadata() async throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 1)
        source.profile.preferences = String(repeating: "x", count: 9_000)
        source.meals[0].photos = []
        source.coachTurns[0].photos = []; source.coachTurns[0].photoIDs = []
        let f = try CaptureFixture(snapshot: source); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        _ = try await store.selectPagedProfile(f.profileID)
        var profile = source.profile; profile.preferences = ""
        try await store.updateProfile(profile, expectedProfile: source.profile, expectedProfileID: f.profileID)
        let current = try ChatHistoryFixture.completeReference(databaseURL: f.url)
        let exact = try JSONEncoder().encode(current).count
        let request = try await store.exportRequest(expectedProfileID: f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        func budget(_ count: Int) -> DiaryExportRequest {
            DiaryExportRequest(operationID: UUID(), profileID: request.profileID, head: request.head,
                selectionEpoch: request.selectionEpoch, sourceURL: request.sourceURL, sourceFileIdentity: request.sourceFileIdentity,
                backupGeneration: nil, storageVersion: request.storageVersion, maximumBytes: count)
        }
        let valid = try await coordinator.makeClone(budget(exact))
        #expect(try await coordinator.completeSnapshot(valid) == current)
        let short = try await coordinator.makeClone(budget(exact - 1))
        await #expect(throws: DiaryError.invalidData) { try await coordinator.completeSnapshot(short) }
        try await coordinator.release(valid); try await coordinator.release(short)
    }

    @Test func replacedPhotoRetainedForProgressExportsCurrentPixelsAndOriginalAcceptedManifest() async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let database = try DiaryDatabase(url: f.url)
        let head = try database.readHead(expectedProfileID: f.profileID)
        let photo = f.photo(bytes: Data([1, 2, 3, 4]))
        let payload = try f.payload(head: head, photos: [photo])
        let accepted = try database.captureCoachSubmission(payload, expected: head, maximumBytes: ChatHistoryFixture.maximumBytes)
        let writes: [CoachWrite] = [.food(date: f.before.days[0].localDate,
            items: [FoodItem(name: "Synthetic food with evidence", nutrition: NutritionValues(kcal: 100))], eatenAt: nil),
            .weight(date: "2027-01-13", value: 71, unit: "kg", revision: nil)]
        let committed = try database.applyCoachWrites(writes, turnID: payload.submissionID, at: payload.context.capturedAt,
            expected: accepted.head, maximumBytes: ChatHistoryFixture.maximumBytes)
        let mealID = try #require(committed.value.first?.mealID)
        let oldReference = try #require(database.meal(id: mealID, expectedProfileID: f.profileID).photos.first)
        var replacement = photo; replacement.data = Data([9, 8, 7, 6, 5])
        let updated = try database.transaction(expected: committed.head, maximumBytes: ChatHistoryFixture.maximumBytes) {
            try $0.replacePhoto(replacement, mealID: mealID)
        }
        let updatedReference = try #require(database.meal(id: mealID, expectedProfileID: f.profileID).photos.first)
        #expect(updatedReference.contentToken != oldReference.contentToken)
        _ = try database.deleteMeal(mealID, expected: updated.head, maximumBytes: ChatHistoryFixture.maximumBytes)
        let surviving = try database.coachExchangeSummary(turnID: payload.submissionID, expectedProfileID: f.profileID)
        let retained = try #require(surviving.photos.first)
        #expect(retained.owner == .coachTurn(payload.submissionID))
        #expect(try database.photoContent(retained, expectedProfileID: f.profileID) == replacement.data)
        #expect(surviving.receipts.map(\.operationKey) == committed.value.map(\.operationKey))
        let source = try ChatHistoryFixture.completeReference(databaseURL: f.url)
        #expect(source.coachTurns.first { $0.id == payload.submissionID }?.submissionManifest == payload.manifest)
        let store = DiaryStore(directory: f.root)
        _ = try await store.selectPagedProfile(f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let ticket = try await coordinator.makeClone(try await store.exportRequest(expectedProfileID: f.profileID))
        let archived = try DiaryArchive.decode(try await coordinator.archiveData(ticket))
        let turn = try #require(archived.coachTurns.first { $0.id == payload.submissionID })
        #expect(turn.submissionManifest == payload.manifest)
        #expect(turn.photos.first?.data == replacement.data && turn.photos.first?.id == photo.id)
        let prepared = try await coordinator.prepareReplacement(archived, replacing: ticket)
        _ = try await store.installReplacement(prepared)
        let restored = try ChatHistoryFixture.completeReference(databaseURL: f.url)
        #expect(restored.coachTurns.first { $0.id == payload.submissionID } == turn)
        #expect(restored.weights == source.weights)
        try assertExportAccounting(f.url)
        try await coordinator.release(ticket)
    }

    @Test(arguments: [DiaryExportStage.replacementBuild, .replacementValidated])
    func replacementCancellationCleansOnlyIncompleteOwnedArtifacts(stage: DiaryExportStage) async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root), gate = ExportStageGate(stage)
        _ = try await store.selectPagedProfile(f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root,
            checkpoint: { current, url in try await gate.checkpoint(current, url: url) })
        let ticket = try await coordinator.makeClone(try await store.exportRequest(expectedProfileID: f.profileID))
        let before = try f.durableState()
        let operation = Task { try await gate.observe { try await coordinator.prepareReplacement(f.before, replacing: ticket) } }
        try await gate.waitUntilReached(); operation.cancel(); await gate.release()
        await #expect(throws: CancellationError.self) { try await operation.value }
        let candidate = try #require(await gate.visitedURL)
        if stage == .replacementValidated {
            #expect(FileManager.default.fileExists(atPath: candidate.path))
            #expect(try ChatHistoryFixture.completeReference(databaseURL: candidate).revision == f.before.revision + 1)
        } else { #expect(!FileManager.default.fileExists(atPath: candidate.path)) }
        #expect(try f.durableState() == before)
        try await coordinator.release(ticket)
    }

    private func assertExportAccounting(_ url: URL) throws {
        let snapshot = try ChatHistoryFixture.completeReference(databaseURL: url)
        var expected: [[String]] = []
        func row<Value: Encodable>(_ table: String, _ id: UUID, _ value: Value, parent: UUID? = nil, photoBytes: Int = 0) throws {
            expected.append([table, parent.map { $0.uuidString + "/" + id.uuidString } ?? id.uuidString,
                parent?.uuidString ?? "NULL", String(try JSONEncoder().encode(value).count), String(photoBytes)])
        }
        var metadata = snapshot
        metadata.days = []; metadata.meals = []; metadata.weights = []; metadata.workouts = []; metadata.goals = []
        metadata.coachTurns = []; metadata.deletedMealIDs = []; metadata.deletedWeightIDs = []; metadata.deletedWorkoutIDs = []
        try row("meta", snapshot.profile.id, metadata)
        for value in snapshot.days { try row("day", value.id, value) }
        for original in snapshot.meals {
            var shell = original; shell.submissions = []; shell.items = []; shell.photos = []
            try row("meal", original.id, shell)
            for value in original.submissions {
                expected.append(["submission", value.id.uuidString, original.id.uuidString, String(try JSONEncoder().encode(value).count), "0"])
            }
            for value in original.items { try row("item", value.id, value, parent: original.id) }
            for value in original.photos { try row("photo", value.id, value, parent: original.id, photoBytes: value.data.count) }
        }
        for original in snapshot.coachTurns {
            var shell = original; shell.photos = []
            try row("coach_turn", original.id, shell)
            for value in original.photos { try row("coach_photo", value.id, value, parent: original.id, photoBytes: value.data.count) }
        }
        for value in snapshot.weights { try row("weight", value.id, value) }
        for value in snapshot.workouts { try row("workout", value.id, value) }
        for value in snapshot.goals { try row("goal", value.id, value) }
        for value in snapshot.deletedMealIDs { try row("tombstone", value, value) }
        for value in snapshot.deletedWeightIDs { try row("weight_tombstone", value, value) }
        for value in snapshot.deletedWorkoutIDs { try row("workout_tombstone", value, value) }
        expected.sort { ($0[0], $0[1]) < ($1[0], $1[1]) }
        let actual = try ChatHistoryFixture.strings(url, "SELECT tableName,rowID,COALESCE(parentID,'NULL'),encodedBytes,originalPhotoBytes FROM storage_contribution ORDER BY tableName,rowID")
        #expect(actual == expected)
        let bytes = try JSONEncoder().encode(snapshot).count
        #expect(try ChatHistoryFixture.strings(url, "SELECT portableBytes FROM storage_quota") == [[String(bytes)]])
        let originals = expected.reduce(0) { $0 + Int($1[4])! }
        #expect(try ChatHistoryFixture.strings(url, "SELECT originalPhotoBytes FROM storage_quota") == [[String(originals)]])
        #expect(try ChatHistoryFixture.strings(url, "SELECT SUM(encodedBytes)+(SELECT COALESCE(SUM(n-1),0) FROM (SELECT COUNT(*) n FROM storage_contribution WHERE tableName!='meta' GROUP BY tableName,parentID)) FROM storage_contribution") == [[String(bytes)]])
        for table in ["meta", "day", "meal", "submission", "item", "photo", "coach_turn", "coach_photo", "weight", "workout", "goal", "tombstone", "weight_tombstone", "workout_tombstone"] {
            #expect(try ChatHistoryFixture.strings(url, "SELECT rowCount FROM storage_row_count WHERE tableName='\(table)'") == ChatHistoryFixture.strings(url, "SELECT COUNT(*) FROM \(table)"))
        }
    }

    private func configuredBackup(_ f: CaptureFixture) async throws -> (FolderBackup, UUID, URL) {
        let folder = try exportFolder(in: f.root, name: "provider")
        let backup = FolderBackup(directory: f.root.appending(path: "backup-metadata"))
        await backup.selectProfile(f.profileID)
        try await backup.selectFolder(folder, profileID: f.profileID)
        return (backup, try await backup.generation(profileID: f.profileID), folder)
    }

    private func exportFolder(in root: URL, name: String) throws -> URL {
        let folder = root.appending(path: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func addProfile(in root: URL) throws -> UUID {
        let snapshot = ChatHistoryFixture.snapshot(exchanges: 1, seed: 77)
        let url = root.appending(path: snapshot.profile.id.uuidString + ".sqlite/diary.sqlite")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DiaryDatabase(url: url, create: true).write(snapshot, expected: nil, maximumBytes: ChatHistoryFixture.maximumBytes)
        try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        return snapshot.profile.id
    }

    private func exportScratch(in root: URL) throws -> URL {
        let scratch = root.appending(path: "export-scratch")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try Data([42]).write(to: scratch.appending(path: "unrelated-sentinel"))
        return scratch
    }
}

private actor ExportStageGate {
    let stage: DiaryExportStage
    private var reached = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var failure: (any Error)?
    private(set) var visitedURL: URL?
    init(_ stage: DiaryExportStage) { self.stage = stage }
    func checkpoint(_ current: DiaryExportStage, url: URL) async throws {
        guard current == stage, !reached else { return }
        reached = true; visitedURL = url
        await withCheckedContinuation { continuation = $0 }
        try Task.checkCancellation()
    }
    func waitUntilReached() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !reached {
            if let failure { throw failure }
            guard ContinuousClock.now < deadline else { throw POSIXError(.ETIMEDOUT) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
    func observe<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async throws -> Value {
        do { return try await operation() }
        catch { failure = error; throw error }
    }
    func release() { continuation?.resume(); continuation = nil }
}

private actor ExportFaultProbe {
    private(set) var reached = false
    private(set) var url: URL?
    func record(_ url: URL) { reached = true; self.url = url }
}
