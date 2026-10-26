import Foundation
import Testing
@testable import Mivu

private actor CoachFeedbackReplies {
    private var replies: [CoachInferenceResult]
    init(_ replies: [CoachInferenceResult]) { self.replies = replies }
    func next(_ input: [CoachInferenceInput], _ tools: Data) throws -> CoachInferenceResult {
        guard !replies.isEmpty else { throw CoachError.limitExceeded }
        return replies.removeFirst()
    }
}

@Suite @MainActor struct CoachReceiptFeedbackTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture() async throws -> (DiaryStore, DiaryProfile, TrackingDay, URL) {
        let root = URL.temporaryDirectory.appending(path: "CoachFeedback-" + UUID().uuidString)
        let clock = now
        let store = DiaryStore(directory: root, currentTime: { clock })
        let profile = adultProfile(name: "Synthetic owner")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay(at: now)
        return (store, profile, day, root)
    }

    private func call(_ name: String, _ args: [String: Any]) throws -> CoachToolCall {
        let id = UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: args)
        return CoachToolCall(id: id, callID: id, name: name, namespace: "mivu",
            arguments: String(decoding: data, as: UTF8.self))
    }

    private func reply(_ calls: [CoachToolCall] = []) -> CoachInferenceResult {
        CoachInferenceResult(model: "fixture", text: "Done", calls: calls, outputItems: [])
    }

    private func run(_ store: DiaryStore, _ profile: DiaryProfile, _ turn: CoachTurn,
                     replies: [CoachInferenceResult]) async throws -> CoachTurnResult {
        let script = CoachFeedbackReplies(replies)
        return try await CoachEngine(store: store, infer: { try await script.next($0, $1) })
            .run(turnID: turn.id, expectedProfileID: profile.id)
    }

    private func savedMeal(_ store: DiaryStore, _ profile: DiaryProfile, _ day: TrackingDay,
                           photos: [MealPhoto] = []) async throws -> DiaryMeal {
        let meal = try await capturedMeal(store, text: "Synthetic soup", photos: photos, reviewFirst: false,
            dayID: day.id, at: now, expectedProfileID: profile.id)
        let item = FoodItem(name: "Synthetic soup", nutrition: NutritionValues(kcal: 100, carbs: 15, protein: 4, fat: 2))
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id,
            submissionID: meal.submissions[0].id, baseRevision: 0, items: [item]), expectedProfileID: profile.id)
        return try #require(await store.snapshotForExport().meals.first)
    }

    @Test func completedSubmissionCannotMaskADifferentPendingRecoveryOperation() async throws {
        let (store, profile, _, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let diary = DiaryViewModel(store: store)
        await diary.load(createDefaultProfile: false)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        coach.enterBackground()
        coach.draft.text = "Synthetic completed submission"
        #expect(await coach.send())
        let completed = try #require(coach.captureReceipt)
        let submission = coach.companionSubmission, event = coach.companionCaptureEvent
        try await store.setCoachTurnState(turnID: completed, state: .completed, expectedProfileID: profile.id)
        let pending = try await capturedTurn(store, text: "Synthetic pending network operation", photos: [], at: now,
                                             expectedProfileID: profile.id)
        try await store.setCoachTurnState(turnID: pending.id, state: .waitingForNetwork, expectedProfileID: profile.id)
        try await diary.refresh(profileID: profile.id)
        #expect(diary.workStatus.pendingTurnID == pending.id)
        await coach.refreshActiveOperation()
        #expect(coach.activeOperationTurn?.id == pending.id)
        #expect(coach.activeOperationTurn?.state == .waitingForNetwork)
        #expect(coach.companionNeedsRecovery && !coach.companionIsProcessing)
        #expect(coach.companionSubmission == submission && coach.companionCaptureEvent == event && coach.captureReceipt == completed,
                "Refreshing another operation's state cannot invent acceptance or durable feedback")
    }

    @Test func twoReviewPatchesToOneItemInOneTurnBothPersist() async throws {
        let (store, profile, day, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let meal = try await capturedMeal(store, text: "Synthetic review soup", photos: [], reviewFirst: true,
            dayID: day.id, at: now, expectedProfileID: profile.id)
        let item = FoodItem(name: "Synthetic soup", nutrition: NutritionValues(kcal: 100, carbs: 15, protein: 4, fat: 2))
        let submission = try #require(meal.submissions.first)
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id,
            submissionID: submission.id, baseRevision: 0, items: [item]), expectedProfileID: profile.id)
        let turn = try await capturedTurn(store, text: "Change calories, then rename the review item", photos: [],
            at: now, expectedProfileID: profile.id)
        let base: [String: Any] = ["meal_id": meal.id.uuidString, "item_id": item.id.uuidString,
            "expected_revision": 0, "review_submission_id": submission.id.uuidString]
        let calories = try call("edit_item", base.merging(["nutrients": [["nutrient": "kcal", "value": 120]]]) { _, new in new })
        let rename = try call("edit_item", base.merging(["name": "Synthetic tomato soup"]) { _, new in new })
        let done = try await run(store, profile, turn, replies: [
            reply([try call("get_meal", ["meal_id": meal.id.uuidString])]),
            reply([calories]), reply([rename]), reply()
        ])
        let snapshot = try await store.snapshotForExport()
        let updated = try #require(snapshot.meals.first)
        let proposal = try #require(updated.submissions.first?.proposal?.items.first)
        #expect(proposal.name == "Synthetic tomato soup")
        #expect(proposal.nutrition.kcal == 120)
        #expect(updated.items.isEmpty && updated.state == .awaitingReview)
        #expect(snapshot.totals(dayID: day.id).kcal == nil)
        #expect(done.receipts.count == 2)
        #expect(Set(done.receipts.map(\.operationKey)).count == 2)
    }

    @Test func attachedPhotoKeepsOneDurableByteCopyAndResolvesThroughMeal() async throws {
        let (store, profile, day, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let meal = try await savedMeal(store, profile, day)
        let photo = MealPhoto(data: Data([255, 216, 255, 224]), role: .before)
        let turn = try await capturedTurn(store, text: "Attach this synthetic photo", photos: [photo],
            at: now, expectedProfileID: profile.id)
        let attach = try call("attach_photos", ["meal_id": meal.id.uuidString,
            "expected_revision": meal.revision, "photo_ids": [photo.id.uuidString], "role": "before"])
        _ = try await run(store, profile, turn, replies: [
            reply([try call("get_meal", ["meal_id": meal.id.uuidString])]), reply([attach]), reply()
        ])
        let snapshot = try await store.snapshotForExport()
        let savedTurn = try #require(snapshot.coachTurns.first { $0.id == turn.id })
        #expect(savedTurn.photos.isEmpty)
        #expect(savedTurn.photoIDs == [photo.id])
        #expect(snapshot.meals.first?.photos == [photo])
        #expect(try await exportedCoachPhotos(store, turnID: turn.id, expectedProfileID: profile.id) == [photo])
        let archived = try DiaryArchive.decode(DiaryArchive.encode(snapshot))
        #expect(archived.coachTurns.first { $0.id == turn.id }?.photos.isEmpty == true)
        #expect(archived.meals.first?.photos == [photo])
    }

    @Test func twoPhotoAttachmentsInOneTurnKeepBothPhotosWithoutRawTurnCopies() async throws {
        let (store, profile, day, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let meal = try await savedMeal(store, profile, day)
        let before = MealPhoto(data: Data([255, 216, 255, 224]), role: .before)
        let after = MealPhoto(data: Data([255, 216, 255, 225]), role: .after)
        let turn = try await capturedTurn(store, text: "Attach both synthetic photos", photos: [before, after],
            at: now, expectedProfileID: profile.id)
        let base: [String: Any] = ["meal_id": meal.id.uuidString, "expected_revision": meal.revision]
        let attachBefore = try call("attach_photos", base.merging([
            "photo_ids": [before.id.uuidString], "role": "before"]) { _, new in new })
        let attachAfter = try call("attach_photos", base.merging([
            "photo_ids": [after.id.uuidString], "role": "after"]) { _, new in new })
        let done = try await run(store, profile, turn, replies: [
            reply([try call("get_meal", ["meal_id": meal.id.uuidString])]),
            reply([attachBefore]), reply([attachAfter]), reply()
        ])
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.meals.first?.photos == [before, after])
        #expect(snapshot.coachTurns.first { $0.id == turn.id }?.photos.isEmpty == true)
        #expect(try await exportedCoachPhotos(store, turnID: turn.id, expectedProfileID: profile.id) == [before, after])
        #expect(done.receipts.count == 2)
        #expect(Set(done.receipts.map(\.operationKey)).count == 2)
    }

    @Test func moveReceiptNamesTheSavedDateInsteadOfLoggingFood() async throws {
        let (store, profile, day, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let meal = try await savedMeal(store, profile, day)
        // A 04:00 capture can belong to the previous waking day without losing its real time.
        let eatenAt = try #require(ISO8601DateFormatter().date(from: "2027-01-15T02:00:00Z"))
        try await store.moveMeal(meal.id, to: day.id, eatenAt: eatenAt, expectedProfileID: profile.id)
        let exactMeal = try #require(await store.snapshotForExport().meals.first)
        #expect(exactMeal.eatenAt == eatenAt && exactMeal.timePrecision == .exact)
        let turn = try await capturedTurn(store, text: "Move the soup to yesterday", photos: [],
            at: now, expectedProfileID: profile.id)
        let destination = "2027-01-14"
        let move = try call("move_meal", ["meal_id": meal.id.uuidString,
            "expected_revision": exactMeal.revision, "target_local_date": destination])
        let done = try await run(store, profile, turn, replies: [reply([move]), reply()])
        let snapshot = try await store.snapshotForExport()
        let moved = try #require(snapshot.meals.first)
        #expect(snapshot.days.first { $0.id == moved.dayID }?.localDate == destination)
        #expect(moved.eatenAt == eatenAt && moved.timePrecision == .exact)
        #expect(done.assistantText == "Moved to \(CoachReplyLines.shortDate(destination)).")
        #expect(done.assistantText?.contains("Logged") == false)
    }

    @Test func photoDeletionReceiptConfirmsRemovalInsteadOfLoggingFood() async throws {
        let (store, profile, day, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = MealPhoto(data: Data([255, 216, 255, 224]), role: .before)
        let meal = try await savedMeal(store, profile, day, photos: [photo])
        let turn = try await capturedTurn(store, text: "Delete that photo", photos: [],
            at: now, expectedProfileID: profile.id)
        let remove = try call("delete_photo", ["meal_id": meal.id.uuidString,
            "expected_revision": meal.revision, "photo_id": photo.id.uuidString])
        let done = try await run(store, profile, turn, replies: [
            reply([try call("get_meal", ["meal_id": meal.id.uuidString])]), reply([remove]), reply()
        ])
        #expect(try await store.snapshotForExport().meals.first?.photos.isEmpty == true)
        #expect(done.assistantText?.localizedCaseInsensitiveContains("photo") == true)
        #expect(done.assistantText?.contains("Logged") == false)
    }
    @Test func changedRevisionPatchRejectsAndOriginalCommandReplaysAfterRelaunch() async throws {
        let (store, profile, day, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let meal = try await savedMeal(store, profile, day)
        let item = try #require(meal.items.first)
        let turn = try await capturedTurn(store, text: "Correct soup calories", photos: [], at: now, expectedProfileID: profile.id)
        var args: [String: Any] = ["meal_id": meal.id.uuidString, "item_id": item.id.uuidString,
            "expected_revision": meal.revision, "nutrients": [["nutrient": "kcal", "value": 120]]]
        let first = CoachFeedbackReplies([reply([try call("edit_item", args)])])
        try await interruptAfterWrite(store, profile.id, turn.id) {
            try await CoachEngine(store: store, infer: { try await first.next($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        }
        let saved = try #require(await store.snapshotForExport().meals.first)
        let reopened = DiaryStore(directory: root)
        _ = try await reopened.selectProfile(profile.id)
        let originalReceipts = try await exportedTurn(reopened, turnID: turn.id, expectedProfileID: profile.id).receipts
        args["expected_revision"] = saved.revision
        let changed = CoachFeedbackReplies([reply([try call("edit_item", args)])])
        try await interruptAfterWrite(reopened, profile.id, turn.id) {
            try await CoachEngine(store: reopened, infer: { try await changed.next($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        }
        #expect(try await reopened.snapshotForExport().meals.first == saved)
        #expect(try await exportedTurn(reopened, turnID: turn.id, expectedProfileID: profile.id).receipts == originalReceipts)
        args["expected_revision"] = meal.revision
        let done = try await run(reopened, profile, turn, replies: [reply([try call("edit_item", args)]), reply()])
        #expect(done.receipts.count == 1)
        #expect(try await reopened.snapshotForExport().meals.first == saved)
    }
}
