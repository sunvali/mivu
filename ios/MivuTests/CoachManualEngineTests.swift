import Foundation
import Testing
@testable import Mivu

private actor ManualCoachReplies {
    private var replies: [CoachInferenceResult]
    init(_ replies: [CoachInferenceResult]) { self.replies = replies }
    func next(_ input: [CoachInferenceInput], _ tools: Data) throws -> CoachInferenceResult {
        guard !replies.isEmpty else { throw CoachError.limitExceeded }
        return replies.removeFirst()
    }
}

private actor RevisionCoachReplies {
    private var isFirst = true
    private let goal: CoachToolCall?
    private let stale: Bool
    init(goal: CoachToolCall? = nil, stale: Bool = false) { self.goal = goal; self.stale = stale }
    func next(_ input: [CoachInferenceInput], _ tools: Data) throws -> CoachInferenceResult {
        guard isFirst else { return CoachInferenceResult(model: "fixture", text: "Done", calls: [], outputItems: []) }
        isFirst = false
        guard let developer = input.compactMap({ item -> String? in
            if case .message(role: .developer, text: let text, images: _) = item { return text }
            return nil
        }).last,
              let range = developer.range(of: "Context: ", options: .backwards),
              let data = String(developer[range.upperBound...]).data(using: .utf8),
              let context = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let revision = context["diaryRevision"] as? Int else { throw DiaryError.invalidData }
        let args: [String: Any] = ["expected_diary_revision": revision - (stale ? 1 : 0),
            "preferences": "Synthetic vegetarian preference"]
        let encoded = try JSONSerialization.data(withJSONObject: args)
        let preference = CoachToolCall(id: "preference", callID: "preference", name: "update_preferences",
            namespace: "mivu", arguments: String(decoding: encoded, as: UTF8.self))
        return CoachInferenceResult(model: "fixture", text: "", calls: (goal.map { [$0] } ?? []) + [preference], outputItems: [])
    }
}

@Suite @MainActor struct CoachManualEngineTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture(startDay: Bool = true) async throws -> (DiaryStore, DiaryProfile, TrackingDay?, URL) {
        let root = URL.temporaryDirectory.appending(path: "CoachManual-" + UUID().uuidString)
        let clock = now
        let store = DiaryStore(directory: root, currentTime: { clock })
        let profile = adultProfile(name: "Synthetic owner")
        _ = try await store.createProfile(profile)
        let day = startDay ? try await store.startDay(at: now) : nil
        return (store, profile, day, root)
    }

    private func call(_ name: String, _ args: [String: Any], id: String = UUID().uuidString) throws -> CoachToolCall {
        let data = try JSONSerialization.data(withJSONObject: args)
        return CoachToolCall(id: id, callID: id, name: name, namespace: "mivu", arguments: String(decoding: data, as: UTF8.self))
    }

    private func result(_ calls: [CoachToolCall] = [], text: String = "Done") -> CoachInferenceResult {
        CoachInferenceResult(model: "fixture", text: text, calls: calls, outputItems: [])
    }

    private func run(_ store: DiaryStore, _ profile: DiaryProfile, _ turn: CoachTurn, _ calls: [CoachToolCall]) async throws -> CoachTurnResult {
        let reads = try calls.compactMap { edit -> CoachToolCall? in
            guard ["edit_item", "delete_item", "accept_review", "attach_photos", "delete_photo"].contains(edit.name) else { return nil }
            guard let args = try JSONSerialization.jsonObject(with: Data(edit.arguments.utf8)) as? [String: Any],
                  let mealID = args["meal_id"] as? String else { throw DiaryError.invalidData }
            return try call("get_meal", ["meal_id": mealID])
        }
        let replies = ManualCoachReplies((reads.isEmpty ? [] : [result(reads)]) + [result(calls), result()])
        return try await CoachEngine(store: store, infer: { try await replies.next($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
    }

    private func savedMeal(_ store: DiaryStore, _ profile: DiaryProfile, _ day: TrackingDay) async throws -> DiaryMeal {
        let meal = try await capturedMeal(store, text: "Synthetic bread and egg", photos: [], reviewFirst: false, dayID: day.id, at: now)
        let bread = FoodItem(name: "Synthetic bread", quantity: 2, unit: "slice",
                             nutrition: NutritionValues(kcal: 160, carbs: 30, protein: 6, fat: 2),
                             provenance: .estimate, reference: "Synthetic estimate")
        let egg = FoodItem(name: "Synthetic egg", quantity: 1, unit: "egg",
                           nutrition: NutritionValues(kcal: 70, carbs: 1, protein: 6, fat: 5),
                           provenance: .estimate, reference: "Synthetic estimate")
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id,
            submissionID: meal.submissions[0].id, baseRevision: 0, items: [bread, egg]), expectedProfileID: profile.id)
        return try #require(await store.snapshotForExport().meals.first)
    }

    @Test func oneNutrientPatchPreservesOtherFoodFieldsAndItems() async throws {
        let (store, profile, possibleDay, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try #require(possibleDay), meal = try await savedMeal(store, profile, day)
        let original = meal.items[0]
        let turn = try await capturedTurn(store, text: "Correct bread calories", photos: [], at: now, expectedProfileID: profile.id)
        let args: [String: Any] = ["meal_id": meal.id.uuidString, "item_id": original.id.uuidString,
            "expected_revision": meal.revision, "nutrients": [["nutrient": "kcal", "value": 150]]]
        let done = try await run(store, profile, turn, [call("edit_item", args)])
        let updated = try #require(await store.snapshotForExport().meals.first)
        #expect(done.receipts.count == 1)
        #expect(updated.items[0].nutrition.kcal == 150)
        #expect(updated.items[0].nutrition.carbs == original.nutrition.carbs)
        #expect(updated.items[0].nutrition.protein == original.nutrition.protein)
        #expect(updated.items[0].nutrition.fat == original.nutrition.fat)
        #expect(updated.items[0].name == original.name && updated.items[0].unit == original.unit && updated.items[0].quantity == original.quantity)
        #expect(updated.items[1] == meal.items[1])
    }

    @Test func goalsAndPreferencesDoNotFabricateTrackingDays() async throws {
        let (store, profile, _, root) = try await fixture(startDay: false); defer { try? FileManager.default.removeItem(at: root) }
        let goalTurn = try await capturedTurn(store, text: "Set my goal", photos: [], at: now, expectedProfileID: profile.id)
        let goals = try call("set_goals", ["effective_local_date": "2027-01-15",
            "targets": [["nutrient": "kcal", "value": 2100]], "exercise_credit_enabled": false])
        let goalResult = try await run(store, profile, goalTurn, [goals])
        let preferenceTurn = try await capturedTurn(store, text: "Set my preference", photos: [], at: now, expectedProfileID: profile.id)
        let replies = RevisionCoachReplies()
        let preferenceResult = try await CoachEngine(store: store, infer: { try await replies.next($0, $1) })
            .run(turnID: preferenceTurn.id, expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.days.isEmpty && snapshot.activeDayID == nil)
        #expect(snapshot.goals.first?.targets.kcal == 2100)
        #expect(snapshot.profile.preferences == "Synthetic vegetarian preference")
        #expect(goalResult.receipts.count == 1 && goalResult.receipts[0].dayID == nil)
        #expect(preferenceResult.receipts.count == 1 && preferenceResult.receipts[0].dayID == nil)
        let archive = try DiaryArchive.decode(DiaryArchive.encode(snapshot), expectedProfileID: profile.id)
        #expect(archive == snapshot)
    }

    @Test func openSettingsOnEmptyDiaryReturnsDestinationWithoutStartingDay() async throws {
        let (store, profile, _, root) = try await fixture(startDay: false); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await capturedTurn(store, text: "Open settings", photos: [], at: now, expectedProfileID: profile.id)
        let done = try await run(store, profile, turn, [call("open_settings", ["destination": "settings"])])
        let receipt = try #require(done.receipts.first)
        #expect(receipt.destination == .settings && receipt.dayID == nil)
        #expect(try await store.snapshotForExport().days.isEmpty)
        #expect(try await store.snapshotForExport().activeDayID == nil)
    }

    @Test func moveThenDeleteMealKeepsTombstoneAndRetryDoesNotRestoreIt() async throws {
        let (store, profile, possibleDay, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try #require(possibleDay), meal = try await savedMeal(store, profile, day)
        let moving = try await capturedTurn(store, text: "Move that meal", photos: [], at: now, expectedProfileID: profile.id)
        let move = try call("move_meal", ["meal_id": meal.id.uuidString, "expected_revision": meal.revision,
            "target_local_date": "2027-01-14"])
        _ = try await run(store, profile, moving, [move])
        let moved = try #require(await store.snapshotForExport().meals.first)
        #expect(try await store.snapshotForExport().days.first { $0.id == moved.dayID }?.localDate == "2027-01-14")
        let deleting = try await capturedTurn(store, text: "Delete that meal", photos: [], at: now, expectedProfileID: profile.id)
        let delete = try call("delete_meal", ["meal_id": meal.id.uuidString, "expected_revision": moved.revision])
        let first = ManualCoachReplies([result([delete])])
        try await interruptAfterWrite(store, profile.id, deleting.id) {
            try await CoachEngine(store: store, infer: { try await first.next($0, $1) }).run(turnID: deleting.id, expectedProfileID: profile.id)
        }
        let after = try await store.snapshotForExport()
        #expect(after.meals.isEmpty && after.deletedMealIDs.contains(meal.id))
        let retry = ManualCoachReplies([result([delete]), result()])
        _ = try await CoachEngine(store: store, infer: { try await retry.next($0, $1) }).run(turnID: deleting.id, expectedProfileID: profile.id)
        let replayed = try await store.snapshotForExport()
        #expect(replayed.meals.isEmpty && replayed.deletedMealIDs.filter { $0 == meal.id }.count == 1)
        #expect(replayed.coachTurns.first { $0.id == deleting.id }?.receipts.count == 1)
    }

    @Test func deleteItemRemovesOneFood() async throws {
        let (store, profile, possibleDay, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try #require(possibleDay), meal = try await savedMeal(store, profile, day)
        let turn = try await capturedTurn(store, text: "Remove the bread", photos: [], at: now, expectedProfileID: profile.id)
        let done = try await run(store, profile, turn, [call("delete_item", ["meal_id": meal.id.uuidString, "item_id": meal.items[0].id.uuidString, "expected_revision": meal.revision])])
        let after = try #require(await store.snapshotForExport().meals.first)
        #expect(after.items.map(\.name) == ["Synthetic egg"])
        let receipt = try #require(done.receipts.first)
        #expect(receipt.mealID == meal.id && receipt.dayID == day.id)
    }

    @Test func deleteItemReplayRemovesOnce() async throws {
        let (store, profile, possibleDay, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try #require(possibleDay), meal = try await savedMeal(store, profile, day)
        let turn = try await capturedTurn(store, text: "Remove the bread", photos: [], at: now, expectedProfileID: profile.id)
        let read = try call("get_meal", ["meal_id": meal.id.uuidString])
        let delete = try call("delete_item", ["meal_id": meal.id.uuidString, "item_id": meal.items[0].id.uuidString, "expected_revision": meal.revision])
        let first = ManualCoachReplies([result([read]), result([delete])])
        try await interruptAfterWrite(store, profile.id, turn.id) {
            try await CoachEngine(store: store, infer: { try await first.next($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        }
        #expect(try await store.snapshotForExport().meals.first?.items.count == 1)
        let retry = ManualCoachReplies([result([read]), result([delete]), result()])
        _ = try await CoachEngine(store: store, infer: { try await retry.next($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        let replayed = try await store.snapshotForExport()
        #expect(replayed.meals.first?.items.map(\.name) == ["Synthetic egg"])
        #expect(replayed.coachTurns.first { $0.id == turn.id }?.receipts.count == 1)
    }

    @Test func staleDeleteItemChangesNothing() async throws {
        let (store, profile, possibleDay, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try #require(possibleDay), meal = try await savedMeal(store, profile, day)
        let turn = try await capturedTurn(store, text: "Remove the bread", photos: [], at: now, expectedProfileID: profile.id)
        _ = try? await run(store, profile, turn, [call("delete_item", ["meal_id": meal.id.uuidString, "item_id": meal.items[0].id.uuidString, "expected_revision": 999_999])])
        #expect(try await store.snapshotForExport().meals.first?.items.count == 2)
    }

    @Test func photoAttachAndDeleteRemoveEveryPersistedCopy() async throws {
        let (store, profile, possibleDay, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try #require(possibleDay), meal = try await savedMeal(store, profile, day)
        let photo = MealPhoto(data: Data([255, 216, 255, 224]), role: .before)
        let attaching = try await capturedTurn(store, text: "Attach synthetic photo", photos: [photo], at: now, expectedProfileID: profile.id)
        let attach = try call("attach_photos", ["meal_id": meal.id.uuidString, "expected_revision": meal.revision,
            "photo_ids": [photo.id.uuidString], "role": "before"])
        _ = try await run(store, profile, attaching, [attach])
        let attached = try #require(await store.snapshotForExport().meals.first)
        #expect(attached.photos.map(\.id) == [photo.id])
        let deleting = try await capturedTurn(store, text: "Delete synthetic photo", photos: [], at: now, expectedProfileID: profile.id)
        let delete = try call("delete_photo", ["meal_id": meal.id.uuidString,
            "expected_revision": attached.revision, "photo_id": photo.id.uuidString])
        _ = try await run(store, profile, deleting, [delete])
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.meals[0].photos.isEmpty)
        #expect(snapshot.coachTurns.allSatisfy { !$0.photoIDs.contains(photo.id) && !$0.photos.contains { $0.id == photo.id } })
        #expect(try DiaryArchive.decode(DiaryArchive.encode(snapshot)).meals[0].photos.isEmpty)
    }

    @Test func reviewPatchDoesNotCountUntilAccepted() async throws {
        let (store, profile, possibleDay, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try #require(possibleDay)
        let meal = try await capturedMeal(store, text: "Synthetic review food", photos: [], reviewFirst: true, dayID: day.id, at: now)
        let item = FoodItem(name: "Synthetic soup", nutrition: NutritionValues(kcal: 100, carbs: 15, protein: 4, fat: 2))
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id,
            submissionID: meal.submissions[0].id, baseRevision: 0, items: [item]), expectedProfileID: profile.id)
        let editing = try await capturedTurn(store, text: "Review soup calories", photos: [], at: now, expectedProfileID: profile.id)
        let edit = try call("edit_item", ["meal_id": meal.id.uuidString, "item_id": item.id.uuidString,
            "expected_revision": 0, "review_submission_id": meal.submissions[0].id.uuidString,
            "nutrients": [["nutrient": "kcal", "value": 120]]])
        _ = try await run(store, profile, editing, [edit])
        let pending = try #require(await store.snapshotForExport().meals.first)
        #expect(pending.items.isEmpty && pending.submissions[0].proposal?.items[0].nutrition.kcal == 120)
        #expect(try await store.snapshotForExport().totals(dayID: day.id).kcal == nil)
        let accepting = try await capturedTurn(store, text: "Save reviewed soup", photos: [], at: now, expectedProfileID: profile.id)
        let accept = try call("accept_review", ["meal_id": meal.id.uuidString,
            "expected_revision": 0, "submission_id": meal.submissions[0].id.uuidString])
        _ = try await run(store, profile, accepting, [accept])
        #expect(try await store.snapshotForExport().totals(dayID: day.id).kcal == 120)
    }

    @Test func invalidSecondWriteRollsBackFirstWriteAndReceipts() async throws {
        let (store, profile, possibleDay, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try #require(possibleDay), meal = try await savedMeal(store, profile, day)
        let turn = try await capturedTurn(store, text: "Patch and delete", photos: [], at: now, expectedProfileID: profile.id)
        let before = try await store.snapshotForExport()
        let edit = try call("edit_item", ["meal_id": meal.id.uuidString, "item_id": meal.items[0].id.uuidString,
            "expected_revision": meal.revision, "nutrients": [["nutrient": "kcal", "value": 150]]])
        let staleDelete = try call("delete_meal", ["meal_id": meal.id.uuidString, "expected_revision": 999_999])
        let retrieve = try call("get_meal", ["meal_id": meal.id.uuidString])
        let replies = ManualCoachReplies([result([retrieve]), result([edit, staleDelete])])
        await #expect(throws: CoachError.limitExceeded) {
            try await CoachEngine(store: store, infer: { try await replies.next($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        }
        let after = try await store.snapshotForExport()
        #expect(after.meals == before.meals && after.deletedMealIDs == before.deletedMealIDs)
        #expect(after.coachTurns[0].receipts.isEmpty)
    }

    @Test func stalePreferenceInMixedBatchDoesNotCommitGoal() async throws {
        let (store, profile, _, root) = try await fixture(startDay: false); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await capturedTurn(store, text: "Set goal and preference", photos: [], at: now, expectedProfileID: profile.id)
        let before = try await store.snapshotForExport()
        let goal = try call("set_goals", ["effective_local_date": "2027-01-15",
            "targets": [["nutrient": "kcal", "value": 2000]]])
        let replies = RevisionCoachReplies(goal: goal, stale: true)
        let completed = try await CoachEngine(store: store, infer: { try await replies.next($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(completed.receipts.isEmpty)
        let after = try await store.snapshotForExport()
        #expect(after.goals == before.goals && after.profile == before.profile)
        #expect(after.days.isEmpty && after.coachTurns[0].receipts.isEmpty)
    }

    @Test func photoAttachmentPreservesPendingReviewProposal() async throws {
        let (store, profile, possibleDay, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try #require(possibleDay)
        let meal = try await capturedMeal(store, text: "Synthetic review soup", photos: [], reviewFirst: true, dayID: day.id, at: now)
        let item = FoodItem(name: "Synthetic soup", nutrition: NutritionValues(kcal: 100, carbs: 15, protein: 4, fat: 2))
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id,
            submissionID: meal.submissions[0].id, baseRevision: 0, items: [item]), expectedProfileID: profile.id)
        let photo = MealPhoto(data: Data([255, 216, 255, 224]), role: .before)
        let attaching = try await capturedTurn(store, text: "Attach soup photo", photos: [photo], at: now, expectedProfileID: profile.id)
        let attach = try call("attach_photos", ["meal_id": meal.id.uuidString, "expected_revision": 0,
            "photo_ids": [photo.id.uuidString], "role": "before"])
        _ = try await run(store, profile, attaching, [attach])
        let pending = try #require(await store.snapshotForExport().meals.first)
        #expect(pending.revision == 0 && pending.photos.map(\.id) == [photo.id])
        #expect(pending.submissions[0].proposal?.items == [item])
        #expect(try await store.snapshotForExport().totals(dayID: day.id).kcal == nil)
        let accepting = try await capturedTurn(store, text: "Save reviewed soup", photos: [], at: now, expectedProfileID: profile.id)
        let accept = try call("accept_review", ["meal_id": meal.id.uuidString,
            "expected_revision": 0, "submission_id": meal.submissions[0].id.uuidString])
        _ = try await run(store, profile, accepting, [accept])
        #expect(try await store.snapshotForExport().totals(dayID: day.id).kcal == 100)
    }
    @Test func appendFoodKeepsExistingItemsAndMealIdentity() async throws {
        let (store, profile, possibleDay, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try #require(possibleDay), meal = try await savedMeal(store, profile, day)
        let turn = try await capturedTurn(store, text: "Add synthetic yogurt to that meal", photos: [], at: now, expectedProfileID: profile.id)
        let args: [String: Any] = ["meal_id": meal.id.uuidString, "expected_revision": meal.revision,
            "items": [["name": "Synthetic yogurt", "quantity": 1, "unit": "cup", "kcal": 90,
                       "carbs": 8, "protein": 9, "fat": 2]]]
        _ = try await run(store, profile, turn, [call("append_food", args)])
        let updated = try #require(await store.snapshotForExport().meals.first)
        #expect(updated.id == meal.id && updated.items.count == 3)
        #expect(Array(updated.items.prefix(2)) == meal.items)
        #expect(updated.items[2].name == "Synthetic yogurt")
        #expect(try await store.snapshotForExport().meals.count == 1)
    }

    @Test func goalPatchClearsOnlyNamedNutrientAndNewDateInheritsOthers() async throws {
        let (store, profile, _, root) = try await fixture(startDay: false); defer { try? FileManager.default.removeItem(at: root) }
        let seeded = GoalRecord(effectiveLocalDate: "2027-01-14", timeZoneID: profile.timeZoneID,
            targets: NutritionValues(kcal: 2000, carbs: 220, protein: 110, fat: 70),
            goalWeightKg: 72, exerciseCreditEnabled: true)
        _ = try await store.setGoals(seeded, expectedRevision: nil, expectedProfileID: profile.id)
        let turn = try await capturedTurn(store, text: "Clear carbs and set calories", photos: [], at: now, expectedProfileID: profile.id)
        let read = try call("get_goals", ["local_date": "2027-01-15"])
        let patch = try call("set_goals", ["effective_local_date": "2027-01-15", "expected_revision": NSNull(),
            "targets": [["nutrient": "carbs", "value": NSNull()], ["nutrient": "kcal", "value": 2100]]])
        let replies = ManualCoachReplies([result([read]), result([patch]), result()])
        _ = try await CoachEngine(store: store, infer: { try await replies.next($0, $1) })
            .run(turnID: turn.id, expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport()
        let earlier = try #require(snapshot.goals.first { $0.effectiveLocalDate == "2027-01-14" })
        let later = try #require(snapshot.goals.first { $0.effectiveLocalDate == "2027-01-15" })
        #expect(earlier.targets.carbs == 220 && earlier.targets.kcal == 2000)
        #expect(later.targets.kcal == 2100 && later.targets.carbs == nil)
        #expect(later.targets.protein == 110 && later.targets.fat == 70)
        #expect(later.goalWeightKg == 72 && later.exerciseCreditEnabled)
        #expect(snapshot.days.isEmpty && snapshot.activeDayID == nil)
    }

    @Test func nullItemNutrientClearsOnlyThatField() async throws {
        let (store, profile, possibleDay, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try #require(possibleDay), meal = try await savedMeal(store, profile, day)
        let original = meal.items[0]
        let turn = try await capturedTurn(store, text: "Calories are unknown", photos: [], at: now, expectedProfileID: profile.id)
        let patch = try call("edit_item", ["meal_id": meal.id.uuidString, "item_id": original.id.uuidString,
            "expected_revision": meal.revision, "nutrients": [["nutrient": "kcal", "value": NSNull()]]])
        _ = try await run(store, profile, turn, [patch])
        let updated = try #require(await store.snapshotForExport().meals.first)
        #expect(updated.items[0].nutrition.kcal == nil)
        #expect(updated.items[0].nutrition.carbs == original.nutrition.carbs)
        #expect(updated.items[0].nutrition.protein == original.nutrition.protein)
        #expect(updated.items[0].nutrition.fat == original.nutrition.fat)
        #expect(updated.items[1] == meal.items[1])
        #expect(updated.totals.kcal == meal.items[1].nutrition.kcal && updated.totals.unknownItemCount == 1)
    }

    @Test func startDayThenHistoricalCoverageLeavesActiveDayOpen() async throws {
        let (store, profile, _, root) = try await fixture(startDay: false); defer { try? FileManager.default.removeItem(at: root) }
        let starting = try await capturedTurn(store, text: "Start my waking day", photos: [], at: now, expectedProfileID: profile.id)
        let startReplies = StartDayReplies()
        _ = try await CoachEngine(store: store, infer: { try await startReplies.next($0, $1) })
            .run(turnID: starting.id, expectedProfileID: profile.id)
        let started = try await store.snapshotForExport()
        let active = try #require(started.activeDayID)
        let coverageTurn = try await capturedTurn(store, text: "Skip January 13", photos: [], at: now, expectedProfileID: profile.id)
        let coverage = try call("set_day_coverage", ["local_date": "2027-01-13", "skipped": true])
        _ = try await run(store, profile, coverageTurn, [coverage])
        let snapshot = try await store.snapshotForExport()
        let historical = try #require(snapshot.days.first { $0.localDate == "2027-01-13" })
        #expect(snapshot.activeDayID == active)
        #expect(historical.completeness == .untracked && historical.closedAt == nil)
        #expect(snapshot.days.first { $0.id == active }?.closedAt == nil)
        // Counting the day again stores unknown, never complete.
        let countTurn = try await capturedTurn(store, text: "Count January 13 again", photos: [], at: now, expectedProfileID: profile.id)
        _ = try await run(store, profile, countTurn, [try call("set_day_coverage", ["local_date": "2027-01-13", "skipped": false])])
        #expect(try await store.snapshotForExport().days.first { $0.localDate == "2027-01-13" }?.completeness == .unknown)
    }
}

private actor StartDayReplies {
    private var first = true
    func next(_ input: [CoachInferenceInput], _ tools: Data) throws -> CoachInferenceResult {
        guard first else { return CoachInferenceResult(model: "fixture", text: "Done", calls: [], outputItems: []) }
        first = false
        guard let developer = input.compactMap({ item -> String? in
            if case .message(role: .developer, text: let text, images: _) = item { return text }
            return nil
        }).last,
              let range = developer.range(of: "Context: ", options: .backwards),
              let data = String(developer[range.upperBound...]).data(using: .utf8),
              let context = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let revision = context["diaryRevision"] as? Int else { throw DiaryError.invalidData }
        let args = try JSONSerialization.data(withJSONObject: ["expected_diary_revision": revision])
        let call = CoachToolCall(id: "start", callID: "start", name: "start_day", namespace: "mivu", arguments: String(decoding: args, as: UTF8.self))
        return CoachInferenceResult(model: "fixture", text: "", calls: [call], outputItems: [])
    }
}
