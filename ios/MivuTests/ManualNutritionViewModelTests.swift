import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct ManualNutritionViewModelTests {
    @Test func manualSaveFailureRetainsFrozenDraftAndEmitsNoFeedback() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let model = DiaryViewModel(store: f.store, manualNutritionSaving: { _, _ in throw DiaryError.persistenceFailed })
        await model.load(createDefaultProfile: false)
        let owner = try #require(model.selection), before = model.readModel
        let receipt = model.captureReceipt, reaction = model.companionCaptureEvent
        let payload = f.payload
        #expect(await model.saveManualNutrition(payload, expectedSelection: owner) == nil)
        #expect(model.errorMessage != nil)
        #expect(model.readModel == before && model.captureReceipt == receipt && model.companionCaptureEvent == reaction)
        #expect(payload == f.payload)
    }
    @Test func manualStorageFailureReplacesStaleErrorWhenOwnershipReadAlsoFails() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let database = f.path.appendingPathComponent(f.payload.profileID.uuidString + ".sqlite").appendingPathComponent("diary.sqlite")
        let model = DiaryViewModel(store: f.store, manualNutritionSaving: { _, _ in
            try FileManager.default.removeItem(at: database)
            throw DiaryError.persistenceFailed
        })
        await model.load(createDefaultProfile: false)
        let owner = try #require(model.selection), before = model.readModel
        let receipt = model.captureReceipt, reaction = model.companionCaptureEvent, payload = f.payload
        model.errorMessage = "Synthetic stale error"
        #expect(await model.saveManualNutrition(payload, expectedSelection: owner) == nil)
        #expect(model.selection == owner)
        #expect(model.errorMessage == DiaryError.persistenceFailed.localizedDescription)
        #expect(model.readModel == before && model.captureReceipt == receipt && model.companionCaptureEvent == reaction)
        #expect(payload == f.payload)
    }

    @Test func manualReplayDoesNotReplaySaveReaction() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let model = DiaryViewModel(store: f.store)
        await model.load(createDefaultProfile: false)
        let owner = try #require(model.selection)
        model.errorMessage = DiaryError.persistenceFailed.errorDescription
        let saved = await model.saveManualNutrition(f.payload, expectedSelection: owner)
        #expect(saved?.replayed == false)
        #expect(model.errorMessage == nil)
        #expect(model.captureReceipt == f.payload.submissionID)
        let receipt = model.captureReceipt, reaction = model.companionCaptureEvent
        let replay = await model.saveManualNutrition(f.payload, expectedSelection: owner)
        #expect(replay?.replayed == true)
        #expect(model.captureReceipt == receipt && model.companionCaptureEvent == reaction)
    }
    @Test func obsoleteManualSaveCannotPublishOrDismissAnotherProfile() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let other = DiaryProfile(name: "Synthetic other", timeZoneID: "UTC")
        _ = try await f.store.createProfile(other)
        let model = DiaryViewModel(store: f.store)
        await model.switchProfile(f.payload.profileID)
        let oldOwner = try #require(model.selection)
        await model.switchProfile(other.id)
        let before = model.readModel, reaction = model.companionCaptureEvent, receipt = model.captureReceipt
        #expect(await model.saveManualNutrition(f.payload, expectedSelection: oldOwner) == nil)
        #expect(model.readModel == before && model.companionCaptureEvent == reaction && model.captureReceipt == receipt)
    }
    @Test func committedManualSaveSurvivesRefreshFailure() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let model = DiaryViewModel(store: f.store, actionReadModelLoading: { _ in throw DiaryError.persistenceFailed })
        await model.load(createDefaultProfile: false)
        let owner = try #require(model.selection)
        let saved = await model.saveManualNutrition(f.payload, expectedSelection: owner)
        #expect(saved?.meal.id == f.payload.mealID)
        #expect(model.captureReceipt == f.payload.submissionID)
        #expect(try await f.store.meal(id: f.payload.mealID, expectedProfileID: f.payload.profileID).items.first?.nutrition.carbs == nil)
    }
    @Test func delayedManualSaveCannotOverwriteNewerProjection() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let gate = ManualNutritionSaveGate()
        let model = DiaryViewModel(store: f.store, manualNutritionSaving: { payload, selection in
            let result = try await f.store.saveManualNutrition(payload, expectedSelection: selection, expectedProfileID: payload.profileID)
            await gate.pause(); return result
        })
        await model.load(createDefaultProfile: false)
        let owner = try #require(model.selection)
        let pending = Task { await model.saveManualNutrition(f.payload, expectedSelection: owner) }
        try await gate.waitUntilPaused()
        var updated = f.payload.items[0]; updated.nutrition.kcal = 75
        try await f.store.editItem(mealID: f.payload.mealID, item: updated, explicitNutrients: ["kcal"], expectedRevision: 1, expectedProfileID: f.payload.profileID)
        try await model.refresh(profileID: f.payload.profileID)
        await gate.release(); _ = await pending.value
        #expect(model.meal(f.payload.mealID)?.revision == 2)
        #expect(model.meal(f.payload.mealID)?.items[0].nutrition.kcal == 75)
    }
    @Test func externalSelectionChangeDuringManualSaveCannotEmitReaction() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let other = DiaryProfile(name: "Synthetic other")
        _ = try await f.store.createProfile(other)
        let gate = ManualNutritionSaveGate()
        let model = DiaryViewModel(store: f.store, manualNutritionSaving: { payload, selection in
            let result = try await f.store.saveManualNutrition(payload, expectedSelection: selection, expectedProfileID: payload.profileID)
            await gate.pause(); return result
        })
        await model.switchProfile(f.payload.profileID)
        let owner = try #require(model.selection), reaction = model.companionCaptureEvent, receipt = model.captureReceipt
        let pending = Task { await model.saveManualNutrition(f.payload, expectedSelection: owner) }
        try await gate.waitUntilPaused()
        await model.switchProfile(other.id)
        #expect(model.selection == owner, "The existing save lock blocks profile transition")
        _ = try await f.store.selectProfile(other.id)
        await gate.release()
        #expect(await pending.value == nil)
        #expect(model.companionCaptureEvent == reaction && model.captureReceipt == receipt)
        await model.switchProfile(other.id)
        #expect(model.readModel?.profile.id == other.id && model.todaysMeals.isEmpty)
    }
    @Test func offlineNativeCoachAndNativeEditShareOneDurableMeal() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let model = DiaryViewModel(store: f.store); await model.load(createDefaultProfile: false)
        let owner = try #require(model.selection), epoch = owner.selectionEpoch
        _ = try #require(await model.saveManualNutrition(f.payload, expectedSelection: owner))
        let grounded = try await f.store.coachMeal(id: f.payload.mealID, expectedProfileID: f.payload.profileID)
        #expect(grounded.items[0].id == f.payload.items[0].id && grounded.items[0].nutrition.kcal == 0 && grounded.items[0].nutrition.carbs == nil)
        func turn() async throws -> UUID {
            let preparation = try await f.store.coachCapturePreparation(at: f.payload.capturedAt, expectedProfileID: f.payload.profileID)
            let payload = try CoachSubmissionPayload(submissionID: UUID(), text: "Synthetic food correction", attachments: [], context: preparation.context)
            return try await f.store.captureCoachSubmission(payload, expectedSelection: owner, expectedProfileID: f.payload.profileID).id
        }
        let correctionTurn = try await turn()
        var corrected = grounded.items[0]; corrected.quantity = 2
        _ = try await f.store.applyCoachItemCorrection(turnID: correctionTurn, mealID: grounded.id, item: corrected, expectedRevision: 1, expectedProfileID: f.payload.profileID)
        let appendTurn = try await turn()
        let estimate = FoodItem(name: "Synthetic estimated side", unit: "serving", nutrition: NutritionValues(kcal: 50), provenance: .estimate,
            reference: "Synthetic conversational estimate", uncertain: true, nutrientSources: ["kcal": .estimate])
        _ = try await f.store.applyCoachWrites([.manual(.append(mealID: grounded.id, items: [estimate], revision: 2))], turnID: appendTurn,
            epoch: epoch, expectedProfileID: f.payload.profileID)
        var native = try await f.store.meal(id: grounded.id, expectedProfileID: f.payload.profileID).items[0]
        native.nutrition.kcal = 125
        try await f.store.editItem(mealID: grounded.id, item: native, explicitNutrients: ["kcal"], expectedRevision: 3, expectedProfileID: f.payload.profileID)
        let delayed = try await turn()
        await #expect(throws: DiaryError.staleRevision) {
            try await f.store.applyCoachItemCorrection(turnID: delayed, mealID: grounded.id, item: corrected, expectedRevision: 2, expectedProfileID: f.payload.profileID)
        }
        let reopened = DiaryStore(directory: f.path)
        _ = try await reopened.selectProfile(f.payload.profileID)
        let final = try await reopened.meal(id: grounded.id, expectedProfileID: f.payload.profileID)
        #expect(final.id == grounded.id && final.items.map(\.id) == [grounded.items[0].id, estimate.id])
        #expect(final.revision == 4 && final.totals.kcal == 175 && final.totals.carbs == nil)
        #expect(final.items[0].provenance == .user && final.items[0].nutrientSources["kcal"] == .user)
        #expect(final.items[1] == estimate)
        #expect(final.dayID == f.payload.target.day.id && final.timePrecision == .dateOnly)
        #expect(final.submissions[0].manualAcceptance?.enteredItemIDs == [grounded.items[0].id])
    }
    @Test func historicalManualSaveMakesCurrentSavedProjectionAvailableForReceipt() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let active = try await f.store.startDay(at: f.payload.capturedAt.addingTimeInterval(86_400))
        let model = DiaryViewModel(store: f.store); await model.load(createDefaultProfile: false)
        await model.loadDay(f.payload.target.day.id)
        let owner = try #require(model.selection)
        let result = try #require(await model.saveManualNutrition(f.payload, expectedSelection: owner))
        #expect(result.meal.id == f.payload.mealID)
        #expect(model.meal(result.meal.id)?.items[0].nutrition.kcal == 0)
        #expect(model.meal(result.meal.id)?.timePrecision == .dateOnly)
        #expect(model.activeDay?.id == active.id)
    }
    private func fixture() async throws -> (path: URL, store: DiaryStore, payload: ManualNutritionPayload) {
        let path = URL.temporaryDirectory.appending(path: "ManualVM-" + UUID().uuidString)
        let store = DiaryStore(directory: path)
        let profile = DiaryProfile(name: "Synthetic manual", timeZoneID: "UTC")
        _ = try await store.createProfile(profile)
        let at = Date(timeIntervalSince1970: 1_792_411_200)
        let day = try await store.startDay(at: at)
        let item = FoodItem(name: "Synthetic food", quantity: 1, unit: "serving", nutrition: NutritionValues(kcal: 0), provenance: .user,
                            reference: "Entered manually", uncertain: false, nutrientSources: ["kcal": .user])
        return (path, store, ManualNutritionPayload(profileID: profile.id, mealID: UUID(), submissionID: UUID(), operation: .create,
            target: .recorded(dayID: day.id, localDate: day.localDate, timeZoneID: "UTC"), capturedAt: at,
            eatenAt: at, timePrecision: .dateOnly, expectedMealRevision: nil, items: [item]))
    }
}

private actor ManualNutritionSaveGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async { await withCheckedContinuation { continuation = $0 } }
    func waitUntilPaused() async throws {
        for _ in 0..<1000 {
            if continuation != nil { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw DiaryError.persistenceFailed
    }
    func release() { continuation?.resume(); continuation = nil }
}
