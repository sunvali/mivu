import Foundation
import SQLite3
import Testing
@testable import Mivu

@Suite @MainActor struct CoachStoreTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture() async throws -> (DiaryStore, DiaryProfile, URL) {
        let root = URL.temporaryDirectory.appending(path: "Coach-" + UUID().uuidString)
        let clock = now
        let store = DiaryStore(directory: root, currentTime: { clock }); let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay(at: now)
        return (store, profile, root)
    }
    private func food(_ name: String, _ quantity: Double, _ calories: Double) -> FoodItem {
        FoodItem(name: name, quantity: quantity, unit: "portion", nutrition: NutritionValues(kcal: calories), provenance: .estimate, reference: "Synthetic estimate")
    }
    @Test func capturePersistsRawTextBeforeAnyInference() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await store.captureCoachTurn(text: "Two eggs, three bread slices and salad", photos: [], at: now, expectedProfileID: profile.id)
        let restored = try await DiaryStore(directory: root).selectProfile(profile.id)
        #expect(restored.coachTurns == [turn]); #expect(restored.meals.isEmpty)
        #expect(turn.captureTimeZoneID == profile.timeZoneID)
    }
    @Test func savedTotalsAndHalfBreadUseOnlyCommittedItems() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await store.captureCoachTurn(text: "Two eggs, three bread slices and salad", photos: [], at: now, expectedProfileID: profile.id)
        let items = [food("Eggs", 2, 140), food("Bread", 3, 240), food("Salad", 1, 40)]
        let receipt = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-15", items: items, expectedProfileID: profile.id)
        let correction = try await store.captureCoachTurn(text: "Half the bread", photos: [], at: now, expectedProfileID: profile.id)
        var bread = items[1]; bread.quantity /= 2
        _ = try await store.applyCoachItemCorrection(turnID: correction.id, mealID: receipt.mealID!, item: bread, expectedRevision: 1, expectedProfileID: profile.id)
        let meal = try await store.snapshot().meals.first!
        #expect(meal.items[0] == items[0]); #expect(meal.items[2] == items[2])
        #expect(meal.items[1].nutrition.kcal == 120); #expect(meal.totals.kcal == 300)
        #expect(meal.items[1].nutrientSources["kcal"] == .estimate)
    }
    @Test func idempotentFoodRetryAfterRelaunchDoesNotResurrectDeletedMeal() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await store.captureCoachTurn(text: "Chocolate yesterday", photos: [], at: now, expectedProfileID: profile.id)
        let receipt = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-14", items: [food("Chocolate", 30, 160)], expectedProfileID: profile.id)
        let reload = DiaryStore(directory: root); _ = try await reload.selectProfile(profile.id)
        #expect(try await reload.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-14", items: [food("Chocolate", 30, 160)], expectedProfileID: profile.id) == receipt)
        let snapshot = try await reload.snapshot(); #expect(snapshot.meals.count == 1)
        #expect(snapshot.meals[0].timePrecision == .dateOnly)
        #expect(snapshot.activeDayID != receipt.dayID)
        try await reload.deleteMeal(receipt.mealID!)
        await #expect(throws: DiaryError.notFound) { try await reload.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-14", items: [food("Chocolate", 30, 160)], expectedProfileID: profile.id) }
        #expect(try await reload.snapshot().meals.isEmpty)
    }
    @Test func closeUntrackedRetainsFoodAndActiveDay() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await store.captureCoachTurn(text: "Yesterday untracked", photos: [], at: now, expectedProfileID: profile.id)
        _ = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-14", items: [food("Chocolate", 30, 160)], expectedProfileID: profile.id)
        let before = try await store.snapshot()
        _ = try await store.closeCoachDay(turnID: turn.id, localDate: "2027-01-14", completeness: .untracked, expectedProfileID: profile.id)
        let after = try await store.snapshot()
        #expect(after.meals == before.meals); #expect(after.activeDayID == before.activeDayID)
        #expect(after.days.first { $0.localDate == "2027-01-14" }?.closedAt == now)
        #expect(after.days.first { $0.localDate == "2027-01-14" }?.completeness == .untracked)
    }
    @Test func foreignIDsAndStaleCorrectionFailWithoutReceipt() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await store.captureCoachTurn(text: "Food", photos: [], at: now, expectedProfileID: profile.id)
        let item = food("Bread", 3, 240)
        let receipt = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-15", items: [item], expectedProfileID: profile.id)
        let correction = try await store.captureCoachTurn(text: "Half", photos: [], at: now, expectedProfileID: profile.id)
        var edited = item; edited.quantity = 2
        try await store.editItem(mealID: receipt.mealID!, item: edited)
        let before = try await store.snapshot()
        await #expect(throws: DiaryError.staleRevision) { try await store.applyCoachItemCorrection(turnID: correction.id, mealID: receipt.mealID!, item: item, expectedRevision: 1, expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.wrongOwner) { try await store.coachContext(turnID: turn.id, expectedProfileID: UUID()) }
        await #expect(throws: DiaryError.notFound) { try await store.applyCoachItemCorrection(turnID: correction.id, mealID: UUID(), item: item, expectedRevision: 1, expectedProfileID: profile.id) }
        #expect(try await store.snapshot() == before)
    }
    @Test func failedCommitChangesNeitherFoodNorReceipts() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await store.captureCoachTurn(text: "Food", photos: [], at: now, expectedProfileID: profile.id)
        let before = try await store.snapshot()
        var db: OpaquePointer?
        let file = root.appendingPathComponent(profile.id.uuidString + ".sqlite").appendingPathComponent("diary.sqlite")
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TRIGGER reject_coach BEFORE UPDATE ON meta BEGIN SELECT RAISE(ABORT, 'synthetic'); END", nil, nil, nil) == SQLITE_OK)
        await #expect(throws: DiaryError.persistenceFailed) { try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-15", items: [food("Food", 1, 100)], expectedProfileID: profile.id) }
        #expect(try await store.snapshot() == before)
        #expect(try await DiaryStore(directory: root).selectProfile(profile.id) == before)
    }
    @Test func pendingManualMealUsesOneRecordAndPhotoDeletionRoundtrips() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try await store.snapshot().days[0]
        let photo = MealPhoto(data: Data([255, 216, 255, 0]))
        let submissionID = UUID()
        let pending = try await store.capture(text: "Photo food", photos: [photo], reviewFirst: false, dayID: day.id, at: now, submissionID: submissionID)
        let turn = try await store.captureCoachTurn(text: "Photo food", photos: [photo], at: now, turnID: submissionID, pendingMealID: pending.id, expectedProfileID: profile.id)
        #expect(turn.photos.isEmpty); #expect(turn.photoIDs == [photo.id])
        _ = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: day.localDate, items: [food("Food", 1, 100)], expectedProfileID: profile.id)
        #expect(try await store.snapshot().meals.count == 1)
        #expect(try await store.coachPhotos(turnID: turn.id, expectedProfileID: profile.id) == [photo])
        try await store.deletePhoto(mealID: pending.id, photoID: photo.id)
        let archive = try DiaryArchive.encode(await store.snapshot())
        let decoded = try DiaryArchive.decode(archive)
        #expect(decoded.coachTurns[0].photoIDs.isEmpty); #expect(decoded.coachTurns[0].photos.isEmpty)
        #expect(decoded.meals[0].photos.isEmpty)
    }
    @Test func legacyArchiveImportsEmptyConversationAndV3RetainsPending() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try await store.snapshot()
        var object = try JSONSerialization.jsonObject(with: DiaryArchive.encode(original)) as! [String: Any]
        object["version"] = 1
        var snapshot = object["snapshot"] as! [String: Any]; snapshot.removeValue(forKey: "coachTurns"); object["snapshot"] = snapshot
        #expect(try DiaryArchive.decode(JSONSerialization.data(withJSONObject: object)).coachTurns.isEmpty)
        _ = try await store.captureCoachTurn(text: "Pending", photos: [MealPhoto(data: Data([1,2,3]))], at: now, expectedProfileID: profile.id)
        let current = try await store.snapshot()
        let data = try DiaryArchive.encode(current)
        let envelope = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(envelope["version"] as? Int == 3)
        #expect(try DiaryArchive.decode(data) == current)
    }
    @Test func atomicManualCoachCaptureFailureAndRetryStayOneRecord() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try await store.snapshot().days[0]; let submission = UUID()
        let meal = try await store.capture(text: "Synthetic photo", photos: [], reviewFirst: true, dayID: day.id, at: now, submissionID: submission, forCoach: true)
        let snapshot = try await store.snapshot()
        #expect(snapshot.coachTurns.count == 1); #expect(try #require(snapshot.coachTurns.first).pendingMealID == meal.id)
        #expect(try await store.capture(text: "Synthetic photo", photos: [], reviewFirst: true, dayID: day.id, at: now, submissionID: submission, forCoach: true).id == meal.id)
        #expect(try await store.snapshot().coachTurns.count == 1)
        var db: OpaquePointer?
        let file = root.appendingPathComponent(profile.id.uuidString + ".sqlite").appendingPathComponent("diary.sqlite")
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TRIGGER reject_coach_capture BEFORE UPDATE ON meta BEGIN SELECT RAISE(ABORT, 'synthetic'); END", nil, nil, nil) == SQLITE_OK)
        let before = try await store.snapshot()
        await #expect(throws: DiaryError.persistenceFailed) { try await store.capture(text: "Second", photos: [], reviewFirst: false, dayID: day.id, forCoach: true) }
        #expect(try await store.snapshot() == before)
    }
    @Test func manualReviewProposalDoesNotCountAsLoggedFood() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try await store.snapshot().days[0]; let submission = UUID()
        let meal = try await store.capture(text: "Review food", photos: [], reviewFirst: true, dayID: day.id, at: now, submissionID: submission, forCoach: true)
        _ = try await store.applyCoachFood(turnID: submission, targetLocalDate: day.localDate, items: [food("Food", 1, 100)], expectedProfileID: profile.id)
        let snapshot = try await store.snapshot()
        #expect(snapshot.meals[0].state == .awaitingReview); #expect(snapshot.meals[0].revision == 0)
        #expect(snapshot.totals(dayID: day.id).kcal == nil)
        try await store.acceptReview(mealID: meal.id, submissionID: submission)
        #expect(try await store.snapshot().totals(dayID: day.id).kcal == 100)
    }
    @Test func legacySQLiteUpgradeRetainsDiaryAndPersistsConversation() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = try await store.snapshot()
        var db: OpaquePointer?
        let file = root.appendingPathComponent(profile.id.uuidString + ".sqlite").appendingPathComponent("diary.sqlite")
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "DROP TABLE coach_photo; DROP TABLE coach_turn", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let reload = DiaryStore(directory: root)
        #expect(try await reload.selectProfile(profile.id) == before)
        let turn = try await reload.captureCoachTurn(text: "After upgrade", photos: [], at: now, expectedProfileID: profile.id)
        #expect(try await DiaryStore(directory: root).selectProfile(profile.id).coachTurns == [turn])
    }

    @Test func collidingPhotoIDsResolveAndDeleteOnlyTheirLinkedMeal() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try await store.snapshot().days[0]
        let id = UUID(); let firstSubmission = UUID(), secondSubmission = UUID()
        let firstPhoto = MealPhoto(id: id, data: Data([1,2,3]))
        let secondPhoto = MealPhoto(id: id, data: Data([4,5,6]))
        let first = try await store.capture(text: "First", photos: [firstPhoto], reviewFirst: false, dayID: day.id, submissionID: firstSubmission, forCoach: true)
        _ = try await store.capture(text: "Second", photos: [secondPhoto], reviewFirst: false, dayID: day.id, submissionID: secondSubmission, forCoach: true)
        #expect(try await store.coachPhotos(turnID: secondSubmission, expectedProfileID: profile.id) == [secondPhoto])
        try await store.deletePhoto(mealID: first.id, photoID: id)
        #expect(try await store.coachPhotos(turnID: secondSubmission, expectedProfileID: profile.id) == [secondPhoto])
        #expect(try await store.coachTurn(turnID: secondSubmission, expectedProfileID: profile.id).photoIDs == [id])
    }
    @Test func pendingPhotoBlobIsNotRewrittenWhenTurnStateChanges() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await store.captureCoachTurn(text: "Pending", photos: [MealPhoto(data: Data([1,2,3]))], at: now, expectedProfileID: profile.id)
        var db: OpaquePointer?
        let file = root.appendingPathComponent(profile.id.uuidString + ".sqlite").appendingPathComponent("diary.sqlite")
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TRIGGER reject_photo_bytes BEFORE UPDATE OF bytes ON coach_photo BEGIN SELECT RAISE(ABORT, 'synthetic'); END", nil, nil, nil) == SQLITE_OK)
        try await store.setCoachTurnState(turnID: turn.id, state: .analyzing, expectedProfileID: profile.id)
        #expect(try await store.coachPhotos(turnID: turn.id, expectedProfileID: profile.id).first?.data == Data([1,2,3]))
        #expect(try await DiaryStore(directory: root).selectProfile(profile.id).coachTurns[0].state == .analyzing)
    }

    @Test func capturedTimezoneAndExplicitHistoricalTimeSurviveProfileChange() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await store.captureCoachTurn(text: "Yesterday chocolate", photos: [], at: now, expectedProfileID: profile.id)
        var changed = profile; changed.timeZoneID = "Pacific/Honolulu"; try await store.updateProfile(changed)
        let receipt = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-14", items: [food("Chocolate", 30, 160)], expectedProfileID: profile.id)
        let snapshot = try await store.snapshot()
        #expect(snapshot.days.first { $0.id == receipt.dayID }?.timeZoneID == "Asia/Jerusalem")
        #expect(snapshot.meals.first?.timePrecision == .dateOnly)
        let currentDay = try #require(snapshot.days.first { $0.id == snapshot.activeDayID })
        try await store.moveMeal(receipt.mealID!, to: currentDay.id)
        #expect(try await store.snapshot().meals.first?.timePrecision == .dateOnly)
        try await store.moveMeal(receipt.mealID!, to: currentDay.id, eatenAt: now)
        #expect(try await store.snapshot().meals.first?.timePrecision == .exact)
        #expect(try await DiaryStore(directory: root).selectProfile(profile.id).meals.first?.eatenAt == now)
    }

    @Test func validLargeUnicodeHistoryProjectsWithinTransportWithoutChangingDiary() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var updatedProfile = profile; updatedProfile.preferences = String(repeating: "😀", count: 10_000)
        try await store.updateProfile(updatedProfile)
        for _ in 0..<13 {
            let turn = try await store.captureCoachTurn(text: String(repeating: "😀", count: 10_000), photos: [], at: now, expectedProfileID: profile.id)
            try await store.completeCoachTurn(turnID: turn.id, assistantText: String(repeating: "\\", count: 30_000), expectedProfileID: profile.id)
        }
        let day = try await store.snapshot().days[0]
        let pending = try await store.capture(text: "Legacy large meal", photos: [], reviewFirst: false, dayID: day.id)
        let items = (0..<200).map { _ in FoodItem(name: String(repeating: "😀", count: 500), nutrition: NutritionValues(kcal: 42), provenance: .estimate, reference: String(repeating: "x", count: 2000)) }
        let output = AnalysisOutput(profileID: profile.id, mealID: pending.id, submissionID: pending.submissions[0].id, baseRevision: 0, items: items)
        try await store.applyAnalysis(output)
        let current = try await store.captureCoachTurn(text: "Continue", photos: [], at: now, expectedProfileID: profile.id)
        let before = try await store.snapshot()
        try before.validate()
        let context = try await store.coachContext(turnID: current.id, expectedProfileID: profile.id)
        #expect(try JSONEncoder().encode(context).count <= 60_000)
        #expect(context.truncated)
        #expect(!context.recentTurns.contains { $0.id == current.id })
        #expect(context.omittedMeals.contains { $0.id == pending.id })
        #expect(try JSONEncoder().encode(context.recentTurns).count <= 8192)
        let retrieved = try await store.coachMeal(id: pending.id, expectedProfileID: profile.id)
        #expect(try JSONEncoder().encode(retrieved).count <= 60_000)
        #expect(retrieved.omittedItemCount > 0)
        #expect(retrieved.items.allSatisfy { $0.nutrition.kcal == 42 })
        #expect(try await store.snapshot() == before)
    }

    @Test func manualItemCorrectionHonorsReviewBeforeIntakeChanges() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try await store.snapshot().days[0]
        let item = food("Bread", 3, 240)
        let meal = try await store.capture(text: "Original", photos: [], reviewFirst: false, dayID: day.id)
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id, submissionID: meal.submissions[0].id, baseRevision: 0, items: [item]))
        let pending = try await store.correctMeal(mealID: meal.id, text: "Half bread", reviewFirst: true, forCoach: true)
        let id = try #require(pending.submissions.last?.id)
        var half = item; half.quantity = 1.5
        _ = try await store.applyCoachItemCorrection(turnID: id, mealID: meal.id, item: half, expectedRevision: 1, expectedProfileID: profile.id)
        let snapshot = try await store.snapshot()
        #expect(snapshot.meals[0].items == [item]); #expect(snapshot.meals[0].revision == 1)
        #expect(snapshot.meals[0].state == .awaitingReview)
        #expect(snapshot.meals[0].submissions.last?.proposal?.items.first?.nutrition.kcal == 120)
        #expect(try await store.coachCommittedSummary(turnID: id, expectedProfileID: profile.id) == "Estimate ready for review.")
        try await store.acceptReview(mealID: meal.id, submissionID: id)
        #expect(try await store.snapshot().meals[0].totals.kcal == 120)
        #expect(try await store.snapshot().meals[0].state == .saved)
    }

    @Test func savedManualFoodLoggingRejectsReplacementOfExistingItem() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try await store.snapshot().days[0]
        let items = [food("Eggs", 2, 140), food("Bread", 3, 240), food("Salad", 1, 40)]
        let meal = try await store.capture(text: "Original", photos: [], reviewFirst: false, dayID: day.id)
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id, submissionID: meal.submissions[0].id, baseRevision: 0, items: items))
        let pending = try await store.correctMeal(mealID: meal.id, text: "Half bread", forCoach: true)
        let id = try #require(pending.submissions.last?.id), before = try await store.snapshot()
        await #expect(throws: DiaryError.invalidData) { try await store.applyCoachFood(turnID: id, targetLocalDate: day.localDate, items: [food("Bread", 1.5, 120)], expectedProfileID: profile.id) }
        #expect(try await store.snapshot() == before)
    }
    @Test func manualFoodAdditionPreservesAllExistingItemsAndIDs() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try await store.snapshot().days[0]
        let items = [food("Eggs", 2, 140), food("Bread", 3, 240), food("Salad", 1, 40)]
        let meal = try await store.capture(text: "Original", photos: [], reviewFirst: false, dayID: day.id)
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id, submissionID: meal.submissions[0].id, baseRevision: 0, items: items))
        let pending = try await store.correctMeal(mealID: meal.id, text: "Add banana", forCoach: true)
        let id = try #require(pending.submissions.last?.id), banana = food("Banana", 1, 90)
        _ = try await store.applyCoachFood(turnID: id, targetLocalDate: day.localDate, items: [banana], expectedProfileID: profile.id)
        let saved = try await store.snapshot().meals[0]
        #expect(saved.items == items + [banana]); #expect(saved.totals.kcal == 510)
        #expect(saved.submissions.last?.state == .saved)
    }

    @Test func firstCurrentChatStartsVisibleDayWhileHistoricalChatDoesNot() async throws {
        let root = URL.temporaryDirectory.appending(path: "FirstCoachDay-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root); let profile = DiaryProfile(name: "Synthetic first chat")
        _ = try await store.createProfile(profile)
        let historical = try await store.captureCoachTurn(text: "Yesterday", photos: [], at: now, expectedProfileID: profile.id)
        _ = try await store.applyCoachFood(turnID: historical.id, targetLocalDate: "2027-01-14", items: [food("Chocolate", 30, 160)], expectedProfileID: profile.id)
        #expect(try await store.snapshot().activeDayID == nil)
        let current = try await store.captureCoachTurn(text: "I had eggs for breakfast", photos: [], at: now, expectedProfileID: profile.id)
        let receipt = try await store.applyCoachFood(turnID: current.id, targetLocalDate: "2027-01-15", items: [food("Eggs", 2, 140)], expectedProfileID: profile.id)
        let snapshot = try await store.snapshot(), meal = try #require(snapshot.meals.first { $0.id == receipt.mealID })
        #expect(snapshot.activeDayID == receipt.dayID)
        #expect(meal.timePrecision == .dateOnly)
        #expect(snapshot.totals(dayID: receipt.dayID).kcal == 140)
    }

    @Test func mixedManualAdditionAndCorrectionCommitTogetherAndReplay() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try await store.snapshot().days[0], items = [food("Eggs", 2, 140), food("Bread", 3, 240), food("Salad", 1, 40)]
        let meal = try await store.capture(text: "Original", photos: [], reviewFirst: false, dayID: day.id)
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id, submissionID: meal.submissions[0].id, baseRevision: 0, items: items))
        let pending = try await store.correctMeal(mealID: meal.id, text: "Add banana and halve bread", forCoach: true)
        let id = try #require(pending.submissions.last?.id); var half = items[1]; half.quantity = 1.5
        let writes: [CoachWrite] = [.food(date: day.localDate, items: [food("Banana", 1, 90)], eatenAt: nil), .correction(mealID: meal.id, item: half, revision: 1)]
        let before = try await store.snapshot()
        var db: OpaquePointer?; let file = root.appendingPathComponent(profile.id.uuidString + ".sqlite").appendingPathComponent("diary.sqlite")
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TABLE batch_audit (n INTEGER); CREATE TRIGGER count_batch AFTER UPDATE ON meta BEGIN INSERT INTO batch_audit VALUES (1); END", nil, nil, nil) == SQLITE_OK)
        let receipts = try await store.applyCoachWrites(writes, turnID: id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        let snapshot = try await store.snapshot()
        #expect(snapshot.meals[0].totals.kcal == 390); #expect(receipts.count == 2)
        #expect(snapshot.revision == before.revision + 1)
        var count: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM batch_audit", -1, &count, nil) == SQLITE_OK)
        #expect(sqlite3_step(count) == SQLITE_ROW); #expect(sqlite3_column_int(count, 0) == 1)
        sqlite3_finalize(count)
        #expect(Set(receipts.map(\.committedRevision)).count == 1)
        let reload = DiaryStore(directory: root); _ = try await reload.selectProfile(profile.id)
        #expect(try await reload.applyCoachWrites(writes, turnID: id, epoch: reload.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) == receipts)
        #expect(try await reload.snapshot() == snapshot)
    }
    @Test func twoReviewCorrectionsComposeWithoutChangingIntake() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try await store.snapshot().days[0], items = [food("Eggs", 2, 140), food("Bread", 3, 240), food("Salad", 1, 40)]
        let meal = try await store.capture(text: "Original", photos: [], reviewFirst: false, dayID: day.id)
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id, submissionID: meal.submissions[0].id, baseRevision: 0, items: items))
        let pending = try await store.correctMeal(mealID: meal.id, text: "Halve eggs and bread", reviewFirst: true, forCoach: true)
        let id = try #require(pending.submissions.last?.id); var bread = items[1], eggs = items[0]; bread.quantity = 1.5; eggs.quantity = 1
        _ = try await store.applyCoachWrites([.correction(mealID: meal.id, item: bread, revision: 1), .correction(mealID: meal.id, item: eggs, revision: 1)], turnID: id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        let snapshot = try await store.snapshot(), proposal = try #require(snapshot.meals[0].submissions.last?.proposal)
        #expect(snapshot.meals[0].items == items)
        #expect(proposal.items[0].nutrition.kcal == 70); #expect(proposal.items[1].nutrition.kcal == 120)
        try await store.acceptReview(mealID: meal.id, submissionID: id)
        #expect(try await store.snapshot().meals[0].totals.kcal == 230)
    }
    @Test func finalBatchCommitFailureLeavesRecordsAndReceiptsUnchanged() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try await store.snapshot().days[0], item = food("Bread", 3, 240)
        let meal = try await store.capture(text: "Original", photos: [], reviewFirst: false, dayID: day.id)
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id, submissionID: meal.submissions[0].id, baseRevision: 0, items: [item]))
        let pending = try await store.correctMeal(mealID: meal.id, text: "Add banana and halve bread", forCoach: true)
        let id = try #require(pending.submissions.last?.id), before = try await store.snapshot(); var half = item; half.quantity = 1.5
        var db: OpaquePointer?; let file = root.appendingPathComponent(profile.id.uuidString + ".sqlite").appendingPathComponent("diary.sqlite")
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TRIGGER reject_final_batch BEFORE UPDATE ON meta BEGIN SELECT RAISE(ABORT, 'synthetic'); END", nil, nil, nil) == SQLITE_OK)
        await #expect(throws: DiaryError.persistenceFailed) { try await store.applyCoachWrites([.food(date: day.localDate, items: [food("Banana", 1, 90)], eatenAt: nil), .correction(mealID: meal.id, item: half, revision: 1)], turnID: id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) }
        #expect(try await store.snapshot() == before)
        #expect(try await DiaryStore(directory: root).selectProfile(profile.id) == before)
    }
    @Test(arguments: [false, true]) func explicitWakingDayChoiceResolvesSamePendingTurn(usePrevious: Bool) async throws {
        let root = URL.temporaryDirectory.appending(path: "CoachChoice-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root), profile = DiaryProfile(name: "Synthetic choice")
        _ = try await store.createProfile(profile); let previous = try await store.startDay(at: now.addingTimeInterval(-86400))
        let turn = try await store.captureCoachTurn(text: "Food now", photos: [], at: now, expectedProfileID: profile.id)
        await #expect(throws: DiaryError.ambiguousDay) { try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-15", items: [food("Eggs", 2, 140)], expectedProfileID: profile.id) }
        try await store.setCoachTurnState(turnID: turn.id, state: .needsClarification, needsDayChoice: true, expectedProfileID: profile.id)
        let chosen: UUID
        if usePrevious { try await store.confirmPreviousDay(at: now); chosen = previous.id }
        else { chosen = try await store.startDay(at: now).id }
        try await store.setCoachTurnState(turnID: turn.id, state: .captured, expectedProfileID: profile.id)
        let receipt = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-15", items: [food("Eggs", 2, 140)], expectedProfileID: profile.id)
        #expect(receipt.dayID == chosen)
        let resolved = try await store.coachTurn(turnID: turn.id, expectedProfileID: profile.id)
        #expect(resolved.capturedAt == now); #expect(resolved.captureTimeZoneID == profile.timeZoneID)
        #expect(resolved.resolvedDayID == chosen)
        let reload = DiaryStore(directory: root); _ = try await reload.selectProfile(profile.id)
        #expect(try await reload.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-15", items: [food("Eggs", 2, 140)], expectedProfileID: profile.id) == receipt)
        #expect(try await reload.snapshot().meals.count == 1)
    }
    @Test func sourceIdentifiedQuantityCorrectionPreservesMatchUncertainty() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await store.captureCoachTurn(text: "Retrieved food", photos: [], at: now, expectedProfileID: profile.id)
        let item = FoodItem(name: "Synthetic retrieved", quantity: 100, unit: "g", nutrition: NutritionValues(kcal: 500), provenance: .identifiedSource, reference: "https://fdc.nal.usda.gov/food-details/1/nutrients", uncertain: true, nutritionBasis: NutritionValues(kcal: 5))
        let receipt = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-15", items: [item], expectedProfileID: profile.id)
        let correction = try await store.captureCoachTurn(text: "Half", photos: [], at: now, expectedProfileID: profile.id); var half = item; half.quantity = 50
        _ = try await store.applyCoachItemCorrection(turnID: correction.id, mealID: receipt.mealID!, item: half, expectedRevision: 1, expectedProfileID: profile.id)
        let saved = try #require(await store.snapshot().meals.first?.items.first)
        #expect(saved.nutrition.kcal == 250); #expect(saved.uncertain)
        #expect(saved.nutrientSources["kcal"] == .identifiedSource)
    }
    @Test func pendingManualCorrectionRejectsAnotherOwnedMeal() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try await store.snapshot().days[0], bread = food("Bread", 3, 240), soup = food("Soup", 1, 100)
        let first = try await store.capture(text: "First", photos: [], reviewFirst: false, dayID: day.id)
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: first.id, submissionID: first.submissions[0].id, baseRevision: 0, items: [bread]))
        let second = try await store.capture(text: "Second", photos: [], reviewFirst: false, dayID: day.id)
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: second.id, submissionID: second.submissions[0].id, baseRevision: 0, items: [soup]))
        let pending = try await store.correctMeal(mealID: first.id, text: "Half", forCoach: true), id = try #require(pending.submissions.last?.id)
        let context = try await store.coachContext(turnID: id, expectedProfileID: profile.id)
        #expect(context.pendingMealID == first.id); #expect(context.pendingMealRevision == 1)
        let before = try await store.snapshot(); var half = soup; half.quantity = 0.5
        await #expect(throws: DiaryError.invalidData) { try await store.applyCoachItemCorrection(turnID: id, mealID: second.id, item: half, expectedRevision: 1, expectedProfileID: profile.id) }
        #expect(try await store.snapshot() == before)
    }

    @Test func unconfirmedCoachTimeStaysDateOnlyAndManualCaptureRemainsExact() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await store.captureCoachTurn(text: "Breakfast at eight", photos: [], at: now, expectedProfileID: profile.id)
        let time = now.addingTimeInterval(-7200)
        let receipt = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-15", items: [food("Eggs", 2, 140)], eatenAt: time, expectedProfileID: profile.id)
        let explicit = try #require(await store.snapshot().meals.first { $0.id == receipt.mealID })
        #expect(explicit.timePrecision == .dateOnly); #expect(explicit.eatenAt != time)
        let day = try await store.snapshot().days[0], id = UUID()
        _ = try await store.capture(text: "Manual", photos: [], reviewFirst: false, dayID: day.id, at: now, submissionID: id, forCoach: true)
        let manual = try await store.applyCoachFood(turnID: id, targetLocalDate: day.localDate, items: [food("Soup", 1, 100)], eatenAt: time, expectedProfileID: profile.id)
        let saved = try #require(await store.snapshot().meals.first { $0.id == manual.mealID })
        #expect((saved.timePrecision ?? .exact) == .exact); #expect(saved.eatenAt == now)
    }

    private var strength: WorkoutDraft {
        WorkoutDraft(kind: .strength, durationMinutes: 30, exercises: [WorkoutExercise(name: "Squat", sets: [WorkoutSet(repetitions: 8, loadKg: 40), WorkoutSet(repetitions: 6, loadKg: nil)])], estimatedBurnKcal: 100, burnSource: .userEstimate)
    }
    @Test func progressBatchPersistsActualIDsAndStableReceiptsAcrossRelaunch() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await store.captureCoachTurn(text: "I weighed 70 kg this morning; yesterday strength", photos: [], at: now, expectedProfileID: profile.id)
        let writes: [CoachWrite] = [.weight(date: "2027-01-15", value: 70, unit: "kg", revision: nil), .workout(date: "2027-01-14", draft: strength)]
        let before = try await store.snapshot()
        let receipts = try await store.applyCoachWrites(writes, turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        let saved = try await store.snapshot()
        #expect(saved.revision == before.revision + 1)
        #expect(receipts[0].weightID == saved.weights[0].id); #expect(receipts[1].workoutID == saved.workouts[0].id)
        #expect(saved.weights[0].timePrecision == .dateOnly); #expect(saved.workouts[0].timePrecision == .dateOnly)
        #expect(saved.workouts[0].exercises == strength.exercises)
        let reload = DiaryStore(directory: root); _ = try await reload.selectProfile(profile.id)
        #expect(try await reload.applyCoachWrites(writes, turnID: turn.id, epoch: reload.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) == receipts)
        #expect(try await reload.snapshot() == saved)
    }
    @Test func morningWeightStartsCurrentDayAndGuardedCorrectionKeepsManualTime() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await store.startDay(at: now.addingTimeInterval(-86400))
        let turn = try await store.captureCoachTurn(text: "Morning weight", photos: [], at: now, expectedProfileID: profile.id)
        _ = try await store.applyCoachWrites([.weight(date: "2027-01-15", value: 70, unit: "kg", revision: nil)], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        let saved = try await store.snapshot(), first = try #require(saved.weights.first)
        #expect(saved.activeDayID == first.dayID)
        let manual = try await store.recordWeight(value: 71, at: now)
        let correction = try await store.captureCoachTurn(text: "Actually 70", photos: [], at: now, expectedProfileID: profile.id)
        let receipts = try await store.applyCoachWrites([.weight(date: "2027-01-15", value: 70, unit: "kg", revision: manual.revision)], turnID: correction.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        let corrected = try await store.snapshot().weights[0]
        #expect(corrected.id == manual.id); #expect(corrected.revision == manual.revision + 1)
        #expect(corrected.measuredAt == now); #expect(corrected.timePrecision == .exact)
        #expect(receipts[0].weightID == corrected.id)
    }
    @Test func historicalWeightIDCorrectionPreservesDayAndTimeAfterTravel() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let old = try await store.setWeight(dayLocalDate: "2026-12-01", value: 70, unit: "kg", measuredAt: nil, expectedRevision: nil, expectedProfileID: profile.id)
        var changed = profile; changed.timeZoneID = "Pacific/Honolulu"; try await store.updateProfile(changed)
        let turn = try await store.captureCoachTurn(text: "Correct historical weight", photos: [], at: now, expectedProfileID: profile.id)
        let active = try await store.snapshot().activeDayID
        _ = try await store.applyCoachWrites([.correctWeight(id: old.id, value: 154, unit: "lb", revision: old.revision)], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        let current = try #require(await store.snapshot().weights.first { $0.id == old.id })
        #expect(current.dayID == old.dayID); #expect(current.measuredAt == old.measuredAt)
        #expect(current.timePrecision == old.timePrecision); #expect(try await store.snapshot().activeDayID == active)
        let report = try await store.coachProgress(endingOn: "2026-12-01", days: 1, expectedProfileID: profile.id)
        #expect(report.weights.first?.record.id == old.id); #expect(report.weights.first?.localDate == "2026-12-01")
    }
    @Test func historicalWorkoutEditDeleteAndDeletedReplayAreGuarded() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let create = try await store.captureCoachTurn(text: "Strength", photos: [], at: now, expectedProfileID: profile.id)
        let write = CoachWrite.workout(date: "2026-12-01", draft: strength)
        let receipts = try await store.applyCoachWrites([write], turnID: create.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        let old = try #require(await store.snapshot().workouts.first)
        let turn = try await store.captureCoachTurn(text: "45 minutes", photos: [], at: now, expectedProfileID: profile.id)
        var draft = strength; draft.durationMinutes = 45
        let edited = try await store.applyCoachWrites([.editWorkout(id: old.id, draft: draft, revision: 1)], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        let saved = try await store.coachWorkout(id: old.id, expectedProfileID: profile.id)
        #expect(saved.id == old.id); #expect(saved.revision == 2); #expect(saved.performedAt == old.performedAt)
        #expect(saved.dayID == old.dayID); #expect(edited[0].workoutID == old.id)
        let deletion = try await store.captureCoachTurn(text: "Delete", photos: [], at: now, expectedProfileID: profile.id)
        let writes: [CoachWrite] = [.deleteWorkout(id: old.id, revision: 2)]
        let deleted = try await store.applyCoachWrites(writes, turnID: deletion.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        #expect(try await store.snapshot().deletedWorkoutIDs == [old.id])
        #expect(try await store.applyCoachWrites(writes, turnID: deletion.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) == deleted)
        await #expect(throws: DiaryError.notFound) { try await store.applyCoachWrites([write], turnID: create.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) }
        #expect(receipts[0].workoutID == old.id)
    }
    @Test func progressBatchRejectsDuplicatesStaleForeignAndCommitFailureWithoutMutation() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await store.captureCoachTurn(text: "Synthetic batch", photos: [], at: now, expectedProfileID: profile.id)
        let before = try await store.snapshot(), weight = CoachWrite.weight(date: "2027-01-15", value: 70, unit: "kg", revision: nil)
        await #expect(throws: CoachError.invalidArguments) { try await store.applyCoachWrites([weight, weight], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.notFound) { try await store.applyCoachWrites([weight, .deleteWorkout(id: UUID(), revision: 1)], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) }
        #expect(try await store.snapshot() == before)
        var db: OpaquePointer?; let file = root.appendingPathComponent(profile.id.uuidString + ".sqlite").appendingPathComponent("diary.sqlite")
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TRIGGER reject_progress BEFORE UPDATE ON meta BEGIN SELECT RAISE(ABORT, 'synthetic'); END", nil, nil, nil) == SQLITE_OK)
        await #expect(throws: DiaryError.persistenceFailed) { try await store.applyCoachWrites([weight, .workout(date: "2027-01-14", draft: strength)], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) }
        #expect(try await store.snapshot() == before)
        #expect(try await DiaryStore(directory: root).selectProfile(profile.id) == before)
    }
    @Test func progressReferencesAreBoundedAndOversizedWorkoutRefusesReplacement() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var snapshot = try await store.snapshot(); let day = snapshot.days[0]
        snapshot.workouts = (0..<105).map { _ in WorkoutSession(dayID: day.id, performedAt: now, timePrecision: .exact, revision: 1, kind: .cardio, durationMinutes: 45, exercises: [], estimatedBurnKcal: nil, burnSource: nil) }
        let huge = WorkoutSession(dayID: day.id, performedAt: now, timePrecision: .exact, revision: 1, kind: .strength, durationMinutes: 60, exercises: (0..<100).map { _ in WorkoutExercise(name: "Synthetic", sets: (0..<100).map { _ in WorkoutSet(repetitions: 10, loadKg: 40) }) }, estimatedBurnKcal: nil, burnSource: nil)
        snapshot.workouts.append(huge)
        let otherRoot = root.appendingPathComponent("bounded"), otherStore = DiaryStore(directory: otherRoot)
        _ = try await otherStore.importProfile(snapshot)
        let report = try await otherStore.coachProgress(endingOn: "2027-01-15", days: 1, expectedProfileID: profile.id)
        #expect(report.workouts.count == 100); #expect(report.omittedWorkoutCount == 6); #expect(report.truncated)
        #expect(try coachJSON(report).utf8.count <= 65_536)
        #expect(report.workouts.contains { $0.id == huge.id && $0.revision == 1 })
        await #expect(throws: CoachError.limitExceeded) { try await otherStore.coachWorkout(id: huge.id, expectedProfileID: profile.id) }
    }

    @Test func legacyUnlinkedWeightCorrectionAndDeletionPreserveOriginalFields() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var snapshot = try await store.snapshot()
        let original = WeightEntry(dayID: nil, measuredAt: now.addingTimeInterval(-60 * 86400), value: 70)
        snapshot.weights = [original]
        let other = DiaryStore(directory: root.appendingPathComponent("legacy")); _ = try await other.importProfile(snapshot)
        let turn = try await other.captureCoachTurn(text: "Correct legacy weight", photos: [], at: now, expectedProfileID: profile.id)
        let receipts = try await other.applyCoachWrites([.correctWeight(id: original.id, value: 71, unit: "kg", revision: 1)], turnID: turn.id, epoch: other.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        let saved = try await other.snapshot(), corrected = saved.weights[0]
        #expect(corrected.id == original.id); #expect(corrected.dayID == nil)
        #expect(corrected.measuredAt == original.measuredAt); #expect(corrected.timePrecision == original.timePrecision)
        #expect(saved.activeDayID == snapshot.activeDayID)
        let receiptDay = try #require(saved.days.first { $0.id == receipts[0].dayID })
        #expect(receiptDay.completeness == .unknown)
        #expect(ProgressAnalytics.daily(snapshot: saved, localDate: receiptDay.localDate).foodTotals?.kcal == nil)
        let deletion = try await other.captureCoachTurn(text: "Delete legacy weight", photos: [], at: now, expectedProfileID: profile.id)
        let writes: [CoachWrite] = [.deleteWeight(id: original.id, revision: 2)]
        let deleted = try await other.applyCoachWrites(writes, turnID: deletion.id, epoch: other.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        #expect(try await other.applyCoachWrites(writes, turnID: deletion.id, epoch: other.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) == deleted)
        #expect(try await other.snapshot().deletedWeightIDs == [original.id])
    }
    @Test(arguments: [false, true]) func workoutDeletionRetainsSharedProgressPhotosOnly(sharedWeight: Bool) async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let photo = MealPhoto(data: SyntheticConnectionProbe.image)
        let turn = try await store.captureCoachTurn(text: "Synthetic workout image", photos: [photo], at: now, expectedProfileID: profile.id)
        var writes: [CoachWrite] = [.workout(date: "2027-01-15", draft: strength)]
        if sharedWeight { writes.append(.weight(date: "2027-01-15", value: 70, unit: "kg", revision: nil)) }
        _ = try await store.applyCoachWrites(writes, turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        let workout = try #require(await store.snapshot().workouts.first)
        // The native deletion uses the same cleanup as the conversational path.
        try await store.deleteWorkout(id: workout.id, expectedRevision: workout.revision, expectedProfileID: profile.id)
        let saved = try await DiaryStore(directory: root).selectProfile(profile.id)
        #expect(saved.coachTurns[0].photos == (sharedWeight ? [photo] : []))
        #expect(saved.coachTurns[0].photoIDs == (sharedWeight ? [photo.id] : []))
    }
    @Test func staleWeightAndConflictingWorkoutTargetsRejectWholeBatch() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let weight = try await store.recordWeight(value: 70, at: now)
        let workout = try await store.createWorkout(localDate: "2027-01-14", draft: strength, performedAt: nil, expectedProfileID: profile.id)
        let turn = try await store.captureCoachTurn(text: "Synthetic stale edit", photos: [], at: now, expectedProfileID: profile.id)
        let before = try await store.snapshot()
        await #expect(throws: DiaryError.staleRevision) { try await store.applyCoachWrites([.workout(date: "2027-01-15", draft: strength), .correctWeight(id: weight.id, value: 71, unit: "kg", revision: 99)], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) }
        await #expect(throws: CoachError.invalidArguments) { try await store.applyCoachWrites([.editWorkout(id: workout.id, draft: strength, revision: 1), .deleteWorkout(id: workout.id, revision: 2)], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) }
        #expect(try await store.snapshot() == before)
    }
    @Test func progressJSONDistinguishesUnknownFromCompleteZeroAndRoundTrips() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try await store.snapshot().days[0]
        let unknown = try await store.coachProgress(endingOn: day.localDate, days: 1, expectedProfileID: profile.id)
        #expect(unknown.daily.foodTotals?.kcal == nil)
        try await store.setCompleteness(dayID: day.id, .complete)
        let zero = try await store.coachProgress(endingOn: day.localDate, days: 1, expectedProfileID: profile.id)
        #expect(zero.daily.foodTotals?.kcal == 0)
        let unknownJSON = try coachJSON(unknown), zeroJSON = try coachJSON(zero)
        #expect(!unknownJSON.contains("\"kcal\":0")); #expect(zeroJSON.contains("\"kcal\":0"))
        #expect(try JSONDecoder().decode(CoachProgress.self, from: Data(zeroJSON.utf8)) == zero)
    }


    @Test(arguments: ["none", "older", "newer"], [false, true]) func delayedCapturedWeightPreservesProcessingDayChoice(activeState: String, correction: Bool) async throws {
        let (initial, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let existing = correction ? try await initial.recordWeight(value: 70, at: now) : nil
        let processingTime = now.addingTimeInterval(2 * 86400)
        var source = try await initial.snapshot(); source.activeDayID = nil
        let store = DiaryStore(directory: root.appendingPathComponent("delayed"), currentTime: { processingTime })
        _ = try await store.importProfile(source)
        if activeState == "older" { _ = try await store.startDay(at: now.addingTimeInterval(-86400)) }
        if activeState == "newer" { _ = try await store.startDay(at: processingTime) }
        let active = try await store.snapshot().activeDayID
        let turn = try await store.captureCoachTurn(text: "Jan 15 morning weight", photos: [], at: now, expectedProfileID: profile.id)
        let receipts = try await store.applyCoachWrites([.weight(date: "2027-01-15", value: 71, unit: "kg", revision: existing?.revision)], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        let saved = try await store.snapshot()
        #expect(saved.activeDayID == active)
        #expect(saved.weights[0].value == 71); #expect(receipts[0].weightID == saved.weights[0].id)
        #expect(saved.days.first { $0.id == receipts[0].dayID }?.localDate == "2027-01-15")
        if let existing { #expect(saved.weights[0].id == existing.id); #expect(saved.weights[0].measuredAt == existing.measuredAt) }
    }
    @Test func dateWeightCorrectionDoesNotStartAnInactiveDay() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let existing = try await store.recordWeight(value: 70, at: now)
        var imported = try await store.snapshot(); imported.activeDayID = nil
        let other = DiaryStore(directory: root.appendingPathComponent("inactive")); _ = try await other.importProfile(imported)
        let turn = try await other.captureCoachTurn(text: "Correct weight", photos: [], at: now, expectedProfileID: profile.id)
        _ = try await other.applyCoachWrites([.weight(date: "2027-01-15", value: 71, unit: "kg", revision: existing.revision)], turnID: turn.id, epoch: other.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        #expect(try await other.snapshot().activeDayID == nil)
    }

    @Test func correctionReplayCannotRetargetReplacementWeightAfterDeletion() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try await store.recordWeight(value: 70, at: now)
        let correction = try await store.captureCoachTurn(text: "Actually 71", photos: [], at: now, expectedProfileID: profile.id)
        let dateWrite = CoachWrite.weight(date: "2027-01-15", value: 71, unit: "kg", revision: 1)
        _ = try await store.applyCoachWrites([dateWrite], turnID: correction.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        let deletion = try await store.captureCoachTurn(text: "Delete weight", photos: [], at: now, expectedProfileID: profile.id)
        let deleteWrite = CoachWrite.deleteWeight(id: original.id, revision: 2)
        let deleted = try await store.applyCoachWrites([deleteWrite], turnID: deletion.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        let replacement = try await store.recordWeight(value: 80, at: now)
        let before = try await store.snapshot()
        #expect(replacement.id != original.id)
        await #expect(throws: DiaryError.notFound) { try await store.applyCoachWrites([dateWrite], turnID: correction.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.notFound) { try await store.applyCoachWrites([.correctWeight(id: original.id, value: 71, unit: "kg", revision: 1)], turnID: correction.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) }
        #expect(try await store.applyCoachWrites([deleteWrite], turnID: deletion.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) == deleted)
        #expect(try await store.snapshot() == before)
    }

    @Test func originalWeightCreateReceiptStaysCreationReplayAfterEditAndDelete() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await store.captureCoachTurn(text: "Create morning weight", photos: [], at: now, expectedProfileID: profile.id)
        let write = CoachWrite.weight(date: "2027-01-15", value: 70, unit: "kg", revision: nil)
        let receipts = try await store.applyCoachWrites([write], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        let manual = try await store.recordWeight(value: 72, at: now)
        #expect(try await store.applyCoachWrites([.weight(date: "2027-01-15", value: 70, unit: "kg", revision: manual.revision)], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) == receipts)
        #expect(try await store.snapshot().weights == [manual])
        #expect(try await store.coachTurn(turnID: turn.id, expectedProfileID: profile.id).receipts == receipts)
        let deletion = try await store.captureCoachTurn(text: "Delete", photos: [], at: now, expectedProfileID: profile.id)
        let deletes: [CoachWrite] = [.deleteWeight(id: manual.id, revision: manual.revision)]
        let deleted = try await store.applyCoachWrites(deletes, turnID: deletion.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        let before = try await store.snapshot()
        await #expect(throws: DiaryError.notFound) { try await store.applyCoachWrites([write], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) }
        #expect(try await store.applyCoachWrites(deletes, turnID: deletion.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id) == deleted)
        #expect(try await store.snapshot() == before)
    }

}
