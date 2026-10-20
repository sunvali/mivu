import Foundation
import Testing
@testable import Mivu

@Suite struct ManualNutritionTransactionTests {
    @Test func createCommitsSavedMealAndOriginalEvidenceWithoutChatTurn() throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let db = try DiaryDatabase(url: f.url), payload = manualPayload(f)
        let turns = try f.rows("SELECT * FROM coach_index"), sources = try f.rows("SELECT * FROM record_source")
        let beforeHead = try db.readHead(expectedProfileID: f.profileID), coachTurns = try f.rows("SELECT * FROM coach_turn")
        let result = try save(db, f, payload)
        #expect(result.meal.revision == 1)
        #expect(result.meal.items == payload.items && !result.meal.hasUnresolvedInput)
        #expect(result.meal.items[0].nutrition.carbs == nil && result.meal.items[0].nutrition.protein == 0)
        #expect(result.submissionID == payload.submissionID && !result.replayed)
        let submission = try #require(result.meal.submissions.last)
        #expect(submission.state == .saved && !submission.reviewFirst && submission.photoIDs.isEmpty)
        #expect(submission.proposal?.items == payload.items && submission.manualAcceptance == result.acceptance)
        #expect(result.meal.sourceTurnID == nil)
        #expect(try f.rows("SELECT * FROM coach_index") == turns)
        #expect(try f.rows("SELECT * FROM coach_turn") == coachTurns)
        #expect(try f.rows("SELECT * FROM record_source") == sources)
        let afterHead = try db.readHead(expectedProfileID: f.profileID)
        #expect(afterHead.activeDayID == beforeHead.activeDayID && afterHead.activeConversationSegmentID == beforeHead.activeConversationSegmentID)
        #expect(afterHead.previousDayConfirmedAt == beforeHead.previousDayConfirmedAt)
        let portable = try ChatHistoryFixture.completeReference(databaseURL: f.url)
        #expect(try f.rows("SELECT portableBytes FROM storage_quota") == [[String(try JSONEncoder().encode(portable).count)]])
    }

    @Test func newDayAndMealRollbackTogetherOnQuotaFailure() throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let db = try DiaryDatabase(url: f.url)
        let payload = manualPayload(f, target: .newCurrent(dayID: UUID(), localDate: "2027-01-17", timeZoneID: f.before.profile.timeZoneID, previousActiveDayID: f.before.activeDayID))
        let probe = try CaptureFixture(snapshot: f.before); defer { probe.remove() }
        let accepted = try save(DiaryDatabase(url: probe.url), probe, payload)
        #expect(accepted.meal.revision == 1)
        #expect(try DiaryDatabase(url: probe.url).readHead(expectedProfileID: probe.profileID).activeDayID == payload.target.day.id)
        let beforeState = try manualState(f)
        #expect(throws: DiaryError.invalidData) { _ = try save(db, f, payload, maximumBytes: 1) }
        let afterState = try manualState(f)
        #expect(afterState == beforeState)
    }

    @Test func appendPreservesExistingItemsAndIncrementsRevisionOnce() throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let db = try DiaryDatabase(url: f.url), existing = f.before.meals[0]
        let payload = manualPayload(f, append: existing)
        let result = try save(db, f, payload)
        #expect(result.meal.items == existing.items + payload.items)
        #expect(result.meal.revision == existing.revision + 1)
        #expect(result.meal.submissions.last?.proposal?.items == payload.items)
    }

    @Test func identicalAppendRetryAfterEditAndMoveReturnsCurrentProjection() throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let db = try DiaryDatabase(url: f.url), payload = manualPayload(f, append: f.before.meals[0])
        let original = try save(db, f, payload)
        var item = original.meal.items[0]; item.name = "Edited existing item"
        _ = try db.editItem(mealID: payload.mealID, item: item, explicitNutrients: [], expected: db.readHead(expectedProfileID: f.profileID), maximumBytes: ChatHistoryFixture.maximumBytes)
        _ = try db.moveMeal(payload.mealID, to: f.before.days[0].id, expected: db.readHead(expectedProfileID: f.profileID), maximumBytes: ChatHistoryFixture.maximumBytes)
        let before = try db.meal(id: payload.mealID, expectedProfileID: f.profileID), beforeState = try manualState(f)
        let reopened = try DiaryDatabase(url: f.url), replay = try save(reopened, f, payload)
        #expect(replay.replayed && replay.meal.id == payload.mealID)
        #expect(replay.acceptance == original.acceptance && replay.meal == before)
        #expect(try manualState(f) == beforeState)
    }

    @Test(arguments: [false, true]) func deletedTargetsCannotBeResurrected(append: Bool) throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let db = try DiaryDatabase(url: f.url)
        let payload = manualPayload(f, append: append ? f.before.meals[0] : nil)
        _ = try save(db, f, payload)
        _ = try db.deleteMeal(payload.mealID, expected: db.readHead(expectedProfileID: f.profileID), maximumBytes: ChatHistoryFixture.maximumBytes)
        let beforeState = try manualState(f)
        #expect(throws: DiaryError.self) { _ = try save(db, f, payload) }
        #expect(throws: DiaryError.self) { _ = try db.manualNutritionResult(for: payload, expectedProfileID: f.profileID) }
        let afterState = try manualState(f)
        #expect(afterState == beforeState)
    }
    @Test(arguments: ["quantity", "unknown", "date", "zone", "item", "operation", "revision", "capturedAt", "eatenAt", "precision"])
    func changedPayloadCannotReuseAcceptedIdentity(field: String) throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let db = try DiaryDatabase(url: f.url), payload = manualPayload(f, append: f.before.meals[0])
        _ = try save(db, f, payload)
        var items = payload.items, target = payload.target, operation = payload.operation, revision = payload.expectedMealRevision
        var capturedAt = payload.capturedAt, eatenAt = payload.eatenAt, precision = payload.timePrecision
        switch field {
        case "quantity": items[0].quantity = 3
        case "unknown": items[0].nutrition.protein = nil
        case "date": target = .recorded(dayID: target.day.id, localDate: "2027-01-13", timeZoneID: target.day.timeZoneID)
        case "zone": target = .recorded(dayID: target.day.id, localDate: target.day.localDate, timeZoneID: "UTC")
        case "item": items[0].id = UUID()
        case "operation": operation = .create; revision = nil
        case "capturedAt": capturedAt = capturedAt.addingTimeInterval(1)
        case "eatenAt": eatenAt = eatenAt.addingTimeInterval(1)
        case "precision": precision = .dateOnly
        default: revision = 2
        }
        let changed = ManualNutritionPayload(profileID: payload.profileID, mealID: payload.mealID, submissionID: payload.submissionID,
            operation: operation, target: target, capturedAt: capturedAt, eatenAt: eatenAt,
            timePrecision: precision, expectedMealRevision: revision, items: items)
        let beforeState = try manualState(f)
        #expect(throws: DiaryError.self) { _ = try save(db, f, changed) }
        #expect(throws: DiaryError.self) { _ = try db.manualNutritionResult(for: changed, expectedProfileID: f.profileID) }
        #expect(try manualState(f) == beforeState)
    }

    @Test(arguments: [false, true]) func staleOrUnresolvedAppendRollsBack(unresolved: Bool) throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let db = try DiaryDatabase(url: f.url), payload = manualPayload(f, append: f.before.meals[0])
        if unresolved {
            _ = try db.correctMealProjection(mealID: payload.mealID, text: "Synthetic unresolved correction", at: payload.capturedAt,
                expected: db.readHead(expectedProfileID: f.profileID), maximumBytes: ChatHistoryFixture.maximumBytes)
        } else {
            var item = f.before.meals[0].items[0]; item.name = "Later correction"
            _ = try db.editItem(mealID: payload.mealID, item: item, explicitNutrients: [], expected: db.readHead(expectedProfileID: f.profileID), maximumBytes: ChatHistoryFixture.maximumBytes)
        }
        let beforeState = try manualState(f)
        #expect(throws: DiaryError.self) { _ = try save(db, f, payload) }
        #expect(try manualState(f) == beforeState)
    }

    @Test func reconciliationDistinguishesAbsenceAcceptanceAndLegacyCollision() throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let metrics = DiaryQueryDiagnostics(), db = try DiaryDatabase(url: f.url, diagnostics: metrics), payload = manualPayload(f)
        #expect(try db.manualNutritionResult(for: payload, expectedProfileID: f.profileID) == nil)
        let original = try save(db, f, payload), beforeState = try manualState(f)
        let found = try #require(try db.manualNutritionResult(for: payload, expectedProfileID: f.profileID))
        #expect(found.replayed && found.acceptance == original.acceptance && found.meal == original.meal)
        #expect(try manualState(f) == beforeState)
        let collision = manualPayload(f)
        _ = try db.captureProjection(text: "Synthetic legacy collision", photos: [], reviewFirst: false,
            dayID: collision.target.day.id, at: collision.capturedAt, submissionID: collision.submissionID,
            expected: db.readHead(expectedProfileID: f.profileID), maximumBytes: ChatHistoryFixture.maximumBytes)
        #expect(throws: DiaryError.self) { _ = try db.manualNutritionResult(for: collision, expectedProfileID: f.profileID) }
        #expect(metrics.counters.completeReads == 0 && metrics.counters.completeReconciles == 0 && metrics.counters.originalPhotoBytes == 0)
    }

    @Test func preparationReusesRecordedCurrentDayWithoutMutationAndRejectsStaleSelection() async throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 1)
        source.profile.timeZoneID = "UTC"
        let at = try #require(ISO8601DateFormatter().date(from: "2027-01-17T10:00:00Z"))
        let recorded = TrackingDay(localDate: "2027-01-17", timeZoneID: "UTC", startAt: at)
        source.days.append(recorded)
        let f = try CaptureFixture(snapshot: source); defer { f.remove() }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: f.root, diagnostics: metrics)
        _ = try await store.selectPagedProfile(f.profileID)
        let selection = try await store.selectionOwnership(expectedProfileID: f.profileID), beforeState = try manualState(f)
        let target = try await store.prepareManualNutritionTarget(choice: .newCurrent, at: at, expectedSelection: selection, expectedProfileID: f.profileID)
        #expect(target == .newCurrent(dayID: recorded.id, localDate: recorded.localDate, timeZoneID: recorded.timeZoneID, previousActiveDayID: source.activeDayID))
        #expect(try manualState(f) == beforeState)
        _ = try await store.selectPagedProfile(f.profileID)
        await #expect(throws: DiaryError.wrongOwner) { _ = try await store.prepareManualNutritionTarget(choice: .newCurrent, at: at, expectedSelection: selection, expectedProfileID: f.profileID) }
        #expect(metrics.counters.completeReads == 0)
    }

    @Test func supersededActiveDayDecisionCannotStartAnotherDay() throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let db = try DiaryDatabase(url: f.url)
        let payload = manualPayload(f, target: .newCurrent(dayID: UUID(), localDate: "2027-01-17", timeZoneID: f.before.profile.timeZoneID, previousActiveDayID: f.before.activeDayID))
        _ = try db.startDay(at: payload.capturedAt.addingTimeInterval(172800), expected: db.readHead(expectedProfileID: f.profileID), maximumBytes: ChatHistoryFixture.maximumBytes)
        let beforeState = try manualState(f)
        #expect(throws: DiaryError.self) { _ = try save(db, f, payload) }
        #expect(try manualState(f) == beforeState)
    }

    @Test func originalManualSubmissionCannotBeRewrittenAfterLaterEdit() throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let db = try DiaryDatabase(url: f.url), payload = manualPayload(f)
        let result = try save(db, f, payload)
        var changed = try #require(result.meal.submissions.first)
        var currentItem = result.meal.items[0]; currentItem.name = "Later meal edit"
        _ = try db.editItem(mealID: payload.mealID, item: currentItem, explicitNutrients: [], expected: db.readHead(expectedProfileID: f.profileID), maximumBytes: ChatHistoryFixture.maximumBytes)
        changed.text = "Altered original evidence"
        let beforeState = try manualState(f)
        #expect(throws: DiaryError.invalidData) {
            _ = try db.transaction(expected: db.readHead(expectedProfileID: f.profileID), maximumBytes: ChatHistoryFixture.maximumBytes) { transaction in
                try transaction.saveSubmission(changed, meal: transaction.mealRecord(id: payload.mealID))
            }
        }
        #expect(try manualState(f) == beforeState)
        #expect(try db.manualNutritionResult(for: payload, expectedProfileID: f.profileID)?.acceptance == result.acceptance)
    }

    @Test func staleStoredFingerprintStillReadsAndReplays() throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let db = try DiaryDatabase(url: f.url), payload = manualPayload(f)
        let result = try save(db, f, payload)
        try f.execute("UPDATE submission SET payload = CAST(replace(CAST(payload AS TEXT), '\(result.acceptance.payloadFingerprint)', '\(String(repeating: "0", count: 64))') AS BLOB)")
        let replay = try #require(try db.manualNutritionResult(for: payload, expectedProfileID: f.profileID))
        #expect(replay.replayed && replay.acceptance.payloadFingerprint == String(repeating: "0", count: 64))
        var item = payload.items[0]; item.name = "Different food"
        let changed = ManualNutritionPayload(profileID: payload.profileID, mealID: payload.mealID, submissionID: payload.submissionID,
            operation: payload.operation, target: payload.target, capturedAt: payload.capturedAt, eatenAt: payload.eatenAt,
            timePrecision: payload.timePrecision, expectedMealRevision: payload.expectedMealRevision, items: [item])
        #expect(throws: DiaryError.invalidData) { _ = try db.manualNutritionResult(for: changed, expectedProfileID: f.profileID) }
    }

    @Test func manualReceiptSurvivesPortableRestoreWithFreshSelection() async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root), payload = manualPayload(f, append: f.before.meals[0])
        _ = try await store.selectPagedProfile(f.profileID)
        let originalSelection = try await store.selectionOwnership(expectedProfileID: f.profileID)
        let original = try await store.saveManualNutrition(payload, expectedSelection: originalSelection, expectedProfileID: f.profileID)
        let archive = try await store.snapshotForExport(expectedProfileID: f.profileID)
        try await store.restore(archive, expectedProfileID: f.profileID)
        let selection = try await store.selectionOwnership(expectedProfileID: f.profileID), beforeState = try manualState(f)
        let restored = try await store.meal(id: payload.mealID, expectedProfileID: f.profileID)
        let restoredArchive = try await store.snapshotForExport(expectedProfileID: f.profileID)
        #expect(restoredArchive.meals == archive.meals)
        // Restore renews photo content tokens; the receipt returns the current projection.
        var originalWithCurrentTokens = original.meal
        for index in originalWithCurrentTokens.photos.indices {
            let currentPhoto = try #require(restored.photos.first { $0.photoID == originalWithCurrentTokens.photos[index].photoID })
            originalWithCurrentTokens.photos[index].contentToken = currentPhoto.contentToken
        }
        #expect(restored == originalWithCurrentTokens)
        #expect(restored.photos.map(\.contentToken) != original.meal.photos.map(\.contentToken))
        await #expect(throws: DiaryError.wrongOwner) { _ = try await store.saveManualNutrition(payload, expectedSelection: originalSelection, expectedProfileID: f.profileID) }
        let result = try await store.saveManualNutrition(payload, expectedSelection: selection, expectedProfileID: f.profileID)
        #expect(result.replayed && result.meal.id == payload.mealID)
        #expect(result.acceptance == original.acceptance && result.meal == restored)
        #expect(try manualState(f) == beforeState)
    }

    @Test func plannedCurrentDayIdentityCannotReplaceRecordedDay() throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 1); source.profile.timeZoneID = "UTC"
        let at = try diaryDateOnlyInstant("2027-01-17", zone: "UTC")
        let recorded = TrackingDay(localDate: "2027-01-17", timeZoneID: "UTC", startAt: at)
        source.days.append(recorded)
        let f = try CaptureFixture(snapshot: source); defer { f.remove() }
        let db = try DiaryDatabase(url: f.url)
        let payload = manualPayload(f, target: .newCurrent(dayID: UUID(), localDate: recorded.localDate, timeZoneID: recorded.timeZoneID, previousActiveDayID: source.activeDayID))
        let beforeState = try manualState(f)
        #expect(throws: DiaryError.invalidData) { _ = try save(db, f, payload) }
        #expect(try manualState(f) == beforeState)
        let valid = manualPayload(f, target: .newCurrent(dayID: recorded.id, localDate: recorded.localDate, timeZoneID: recorded.timeZoneID, previousActiveDayID: source.activeDayID))
        #expect(try save(db, f, valid).meal.revision == 1)
        #expect(try f.rows("SELECT COUNT(*) FROM day") == [[String(source.days.count)]])
    }

    @Test func receiptIdentityCannotBeReusedForAnotherMeal() throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let db = try DiaryDatabase(url: f.url), original = manualPayload(f)
        _ = try save(db, f, original)
        let other = manualPayload(f, submissionID: original.submissionID), beforeState = try manualState(f)
        #expect(throws: DiaryError.invalidData) { _ = try save(db, f, other) }
        #expect(throws: DiaryError.invalidData) { _ = try db.manualNutritionResult(for: other, expectedProfileID: f.profileID) }
        #expect(try manualState(f) == beforeState)
    }

    @Test func freshCreateIdentityCannotResurrectExistingTombstone() throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let raw = manualPayload(f)
        let payload = ManualNutritionPayload(profileID: raw.profileID, mealID: f.before.deletedMealIDs[0], submissionID: raw.submissionID,
            operation: .create, target: raw.target, capturedAt: raw.capturedAt, eatenAt: raw.eatenAt,
            timePrecision: raw.timePrecision, expectedMealRevision: nil, items: raw.items)
        let db = try DiaryDatabase(url: f.url), beforeState = try manualState(f)
        #expect(throws: DiaryError.notFound) { _ = try save(db, f, payload) }
        #expect(throws: DiaryError.notFound) { _ = try db.manualNutritionResult(for: payload, expectedProfileID: f.profileID) }
        #expect(try manualState(f) == beforeState)
    }

}

private func manualPayload(_ f: CaptureFixture, append: DiaryMeal? = nil, target: ManualNutritionTarget? = nil,
                           submissionID: UUID = UUID(), items: [FoodItem]? = nil) -> ManualNutritionPayload {
    let day = f.before.days.first { $0.id == append?.dayID } ?? f.before.days[1]
    let capturedAt: Date
    if case let .newCurrent(_, date, zone, _) = target { capturedAt = try! diaryDateOnlyInstant(date, zone: zone) }
    else { capturedAt = day.startAt }
    return ManualNutritionPayload(profileID: f.profileID, mealID: append?.id ?? UUID(), submissionID: submissionID,
        operation: append == nil ? .create : .append,
        target: target ?? .recorded(dayID: day.id, localDate: day.localDate, timeZoneID: day.timeZoneID),
        capturedAt: capturedAt, eatenAt: append?.eatenAt ?? capturedAt, timePrecision: append == nil ? .dateOnly : (append?.timePrecision ?? .exact),
        expectedMealRevision: append?.revision,
        items: items ?? [FoodItem(name: "Synthetic manual yogurt", quantity: 2, unit: "cup", nutrition: NutritionValues(kcal: 120, protein: 0), provenance: .user)])
}
private func save(_ db: DiaryDatabase, _ f: CaptureFixture, _ payload: ManualNutritionPayload,
                  maximumBytes: Int = ChatHistoryFixture.maximumBytes) throws -> ManualNutritionSaveResult {
    try db.saveManualNutrition(payload, expected: db.readHead(expectedProfileID: f.profileID), maximumBytes: maximumBytes).value
}
private func manualState(_ f: CaptureFixture) throws -> [[[String]]] {
    try f.durableState() + ["day", "meal", "item", "submission", "tombstone"].map { try f.rows("SELECT * FROM \($0) ORDER BY rowid") }
}
