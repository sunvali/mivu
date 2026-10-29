import Foundation
import Testing
@testable import Mivu

private actor CoachFlowSuspension {
    private var continuation: CheckedContinuation<CoachInferenceResult, Never>?
    private var finished = false
    var started = false
    func respond() async -> CoachInferenceResult {
        if started || finished { return CoachInferenceResult(model: "fixture", text: "Unexpected duplicate inference", calls: [], outputItems: []) }
        return await withCheckedContinuation {
            continuation = $0
            started = true
        }
    }
    func finish() {
        finished = true
        let waiting = continuation
        continuation = nil
        waiting?.resume(returning: CoachInferenceResult(model: "fixture", text: "Synthetic guidance", calls: [], outputItems: []))
    }
}

private enum CoachFlowWaitFailure: Error, Equatable {
    case workerEndedBeforeInference(state: CoachTurnState?, message: String?)
    case inferenceStartTimedOut
}

@Suite @MainActor struct CoachFlowTests {
    private func waitUntilStarted(_ suspended: CoachFlowSuspension, coach: CoachViewModel) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        do {
            while !(await suspended.started) {
                try Task.checkCancellation()
                guard coach.isWorking else {
                    let state: CoachTurnState?
                    if let owner = coach.diary.selection, let operationID = coach.captureReceipt {
                        state = try await coach.diary.store.coachOperationMetadata(turnID: operationID, expectedSelection: owner)?.state
                    } else { state = nil }
                    throw CoachFlowWaitFailure.workerEndedBeforeInference(state: state, message: coach.errorMessage)
                }
                guard clock.now < deadline else { throw CoachFlowWaitFailure.inferenceStartTimedOut }
                try await Task.sleep(for: .milliseconds(10))
            }
            try Task.checkCancellation()
        } catch {
            coach.cancel()
            await suspended.finish()
            await coach.waitForWorker()
            throw error
        }
    }

    @Test func startWaitReportsWorkerExitBeforeInference() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let suspended = CoachFlowSuspension()
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { throw SessionError.noActiveSession })
        coach.draft.text = "Synthetic pre-inference failure"
        #expect(await coach.send())
        await #expect(throws: CoachFlowWaitFailure.workerEndedBeforeInference(state: .waitingForConnection, message: nil)) {
            try await waitUntilStarted(suspended, coach: coach)
        }
        #expect(!(await suspended.started))
        #expect(!coach.isWorking)
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.first?.state == .waitingForConnection)
        #expect(diary.readModel?.meals.isEmpty == true)
    }

    @Test func cancelledStartWaitCleansUpSuspendedWorker() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let suspended = CoachFlowSuspension()
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in await suspended.respond() } })
        coach.draft.text = "Synthetic cancellation"
        #expect(await coach.send())
        try await waitUntilStarted(suspended, coach: coach)
        let waiting = Task { try await waitUntilStarted(suspended, coach: coach) }
        waiting.cancel()
        await #expect(throws: CancellationError.self) { try await waiting.value }
        #expect(!coach.isWorking)
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.first?.assistantText == nil)
        await suspended.finish()
    }

    private func fixture() async throws -> (DiaryViewModel, URL) {
        let path = URL.temporaryDirectory.appending(path: "CoachFlow-" + UUID().uuidString)
        let store = DiaryStore(directory: path)
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic coach"))
        let diary = DiaryViewModel(store: store)
        await diary.load(createDefaultProfile: false)
        return (diary, path)
    }
    @Test func sendCommitsTextAndPhotoBeforeInferenceCompletesAndSurvivesRelaunch() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let suspended = CoachFlowSuspension()
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in await suspended.respond() } })
        coach.draft.text = "Synthetic lunch"; coach.draft.photos = [SyntheticConnectionProbe.image]
        let id = coach.draft.submissionID
        #expect(await coach.send())
        #expect(coach.draft.text.isEmpty)
        // Park the worker before reopening the same database with another store.
        try await waitUntilStarted(suspended, coach: coach)
        try #require(await suspended.started)
        let reopenedStore = DiaryStore(directory: path)
        _ = try await reopenedStore.selectProfile(#require(diary.readModel?.profile.id))
        let stored = try await reopenedStore.snapshotForExport()
        #expect(stored.coachTurns.first?.id == id)
        #expect(stored.coachTurns.first?.text == "Synthetic lunch")
        #expect(stored.coachTurns.first?.photos.first?.data == SyntheticConnectionProbe.image)
        #expect(stored.coachTurns.first?.state == .analyzing)
        #expect(stored.coachTurns.first?.assistantText == nil)
        await suspended.finish(); await coach.waitForWorker()
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.first?.state == .completed)
    }
    @Test func failedWriteRetainsDraftAndNeverAcknowledges() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        coach.draft.text = "Synthetic input"; coach.draft.photos = [SyntheticConnectionProbe.image]
        let id = coach.draft.submissionID
        try FileManager.default.removeItem(at: path); try Data([1]).write(to: path)
        #expect(!(await coach.send()))
        #expect(coach.draft.text == "Synthetic input")
        #expect(coach.draft.photos == [SyntheticConnectionProbe.image])
        #expect(coach.draft.submissionID == id)
        #expect(coach.captureReceipt == nil)
    }
    @Test func disconnectedCaptureRemainsDurableWaitingAndNotSampleFood() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(appleModelAvailable: { false }))
        coach.draft.text = "Synthetic dinner"
        #expect(await coach.send()); await coach.waitForWorker()
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.first?.state == .waitingForConnection)
        #expect(diary.readModel?.meals.isEmpty == true)
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.first?.assistantText == nil)
    }
    @Test func profileTransitionFencesSuspendedCoachResult() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let suspended = CoachFlowSuspension()
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in await suspended.respond() } })
        coach.draft.text = "Synthetic input"
        #expect(await coach.send())
        try await waitUntilStarted(suspended, coach: coach)
        try #require(await suspended.started)
        let first = try #require(diary.readModel?.profile.id)
        await diary.createProfile(name: "Synthetic second")
        await diary.switchProfile(first)
        await suspended.finish(); await coach.waitForWorker()
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.first?.assistantText == nil)
        #expect(diary.readModel?.meals.isEmpty == true)
    }
    @Test func manualProductionCaptureAssociatesSameMealAndNeverRunsSampleWorker() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let owner = try #require(diary.readModel?.profile.id)
        let day = try await diary.store.startDay(expectedProfileID: owner)
        var draft = MealDraft(); draft.text = "Synthetic manual dinner"; draft.reviewFirst = true
        #expect(await diary.capture(draft, dayID: day.id)); await diary.waitForWorker()
        #expect(diary.readModel?.meals.count == 1)
        #expect(diary.readModel?.meals.first?.items.isEmpty == true)
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.first?.id == draft.submissionID)
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.first?.pendingMealID == diary.readModel?.meals.first?.id)
    }
}

private actor CoachRetryFixture {
    var transientFailures: Int
    var calls = 0
    var delays: [Int64] = []
    var responses: [CoachInferenceResult]
    let forbidden: Bool
    init(transientFailures: Int = 0, forbidden: Bool = false, responses: [CoachInferenceResult] = []) {
        self.transientFailures = transientFailures; self.forbidden = forbidden; self.responses = responses
    }
    func respond() throws -> CoachInferenceResult {
        calls += 1
        if forbidden { throw ResponsesClient.Failure.forbidden }
        if transientFailures > 0 { transientFailures -= 1; throw URLError(.notConnectedToInternet) }
        if !responses.isEmpty { return responses.removeFirst() }
        return CoachInferenceResult(model: "fixture", text: "Synthetic guidance", calls: [], outputItems: [])
    }
    func record(_ duration: Duration) { delays.append(duration.components.seconds) }
}

extension CoachFlowTests {
    @Test func transientInferenceRetriesSameRoundWithBoundedDelays() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let replies = CoachRetryFixture(transientFailures: 3)
        var bindings = 0
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: {
            bindings += 1; return { _, _ in try await replies.respond() }
        }, sleep: { await replies.record($0) })
        coach.draft.text = "Synthetic transient capture"
        #expect(await coach.send()); await coach.waitForWorker()
        #expect(await replies.calls == 4)
        #expect(await replies.delays == [1, 2, 4])
        #expect(bindings == 1)
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.first?.state == .completed)
    }
    @Test func exhaustedOfflineTurnResumesAfterRelaunchWithoutNewCapture() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let replies = CoachRetryFixture(transientFailures: 4)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in try await replies.respond() } }, sleep: { await replies.record($0) })
        coach.draft.text = "Synthetic offline capture"
        let id = coach.draft.submissionID
        #expect(await coach.send()); await coach.waitForWorker()
        #expect(await replies.calls == 4)
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.first?.state == .waitingForNetwork)
        let reopened = DiaryViewModel(store: DiaryStore(directory: path))
        let owner = try #require(diary.readModel?.profile.id)
        await reopened.switchProfile(owner)
        let resumed = CoachViewModel(diary: reopened, connection: ChatGPTConnection(), inference: { { _, _ in try await replies.respond() } }, sleep: { await replies.record($0) })
        resumed.resume(); await resumed.waitForWorker()
        #expect(await replies.calls == 5)
        #expect((try? await reopened.store.snapshotForExport())?.coachTurns.count == 1)
        #expect((try? await reopened.store.snapshotForExport())?.coachTurns.first?.id == id)
        #expect((try? await reopened.store.snapshotForExport())?.coachTurns.first?.state == .completed)
    }
    @Test func forbiddenInferenceNeverRetriesAutomatically() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let replies = CoachRetryFixture(forbidden: true)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in try await replies.respond() } }, sleep: { await replies.record($0) })
        coach.draft.text = "Synthetic permission capture"
        #expect(await coach.send()); await coach.waitForWorker()
        #expect(await replies.calls == 1)
        #expect(await replies.delays.isEmpty)
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.first?.state == .waitingForConnection)
    }
    @Test func legacyPhotoSubmissionRecoversStableTurnWithoutDuplicateMealOrBytes() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let owner = try #require(diary.readModel?.profile.id)
        let day = try await diary.store.startDay(expectedProfileID: owner)
        let id = UUID(), photo = MealPhoto(data: SyntheticConnectionProbe.image)
        let meal = try await capturedMeal(diary.store, text: "", photos: [photo], reviewFirst: false, dayID: day.id, submissionID: id, expectedProfileID: owner)
        try await diary.refresh(profileID: owner)
        let arguments = "{\"target_local_date\":\"\(day.localDate)\",\"items\":[{\"name\":\"Eggs\",\"quantity\":2,\"unit\":\"egg\",\"kcal\":140,\"carbs\":1,\"protein\":12,\"fat\":10}]}"
        let call = CoachToolCall(id: "legacy-call", callID: "legacy-call", name: "log_food", namespace: "mivu", arguments: arguments)
        let replies = CoachRetryFixture(responses: [CoachInferenceResult(model: "fixture", text: "", calls: [call], outputItems: []), CoachInferenceResult(model: "fixture", text: "Fixture finished.", calls: [], outputItems: [])])
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in try await replies.respond() } })
        coach.resume(); await coach.waitForWorker(); coach.resume(); await coach.waitForWorker()
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.count == 1)
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.first?.id == id)
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.first?.pendingMealID == meal.id)
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.first?.photos.isEmpty == true)
        #expect(diary.readModel?.meals.count == 1)
        #expect((try? await diary.store.snapshotForExport())?.meals.first?.photos == [photo])
        #expect(diary.readModel?.meals.first?.items.first?.name == "Eggs")
    }
    /// Re-selecting the same profile mid-reply moves the store's epoch, so the engine cannot record its own failure.
    private func unrecordedFailure(_ diary: DiaryViewModel, after responses: [CoachInferenceResult]) -> CoachViewModel.Inference {
        let replies = CoachRetryFixture(responses: responses), store = diary.store, owner = diary.readModel!.profile.id
        return { _, _ in
            if await replies.responses.isEmpty {
                _ = try await store.selectPagedProfile(owner)
                throw CocoaError(.fileReadUnknown)
            }
            return try await replies.respond()
        }
    }
    @Test func unrecordedFailureAfterSavedFoodEndsWithItsSummary() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let owner = try #require(diary.readModel?.profile.id)
        let day = try await diary.store.startDay(expectedProfileID: owner)
        try await diary.refresh(profileID: owner)
        let infer = unrecordedFailure(diary, after: [foodReply(date: day.localDate, name: "Synthetic toast", quantity: 1, kcal: 530, id: "unrecorded-food")])
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { infer })
        coach.draft.text = "Synthetic toast"
        #expect(await coach.send()); await coach.waitForWorker()
        let turn = try #require(try await turns(diary).first)
        #expect(turn.state == .completed && turn.incomplete == true && turn.assistantText != nil && !turn.receipts.isEmpty)
        #expect(coach.errorMessage == nil)
    }
    @Test func unrecordedFailureWithoutSavedFoodOffersTryAgain() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let infer = unrecordedFailure(diary, after: [])
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { infer })
        coach.draft.text = "Synthetic question"
        #expect(await coach.send()); await coach.waitForWorker()
        let turn = try #require(try await turns(diary).first)
        #expect(turn.state == .needsRetry && turn.failureReason != nil)
        #expect(coach.errorMessage != nil)
    }
}

extension CoachFlowTests {
    private func foodReply(date: String, name: String, quantity: Double, kcal: Double, id: String) -> CoachInferenceResult {
        let arguments = "{\"target_local_date\":\"\(date)\",\"items\":[{\"name\":\"\(name)\",\"quantity\":\(quantity),\"unit\":\"serving\",\"kcal\":\(kcal),\"carbs\":1,\"protein\":2,\"fat\":3}]}"
        return CoachInferenceResult(model: "fixture", text: "", calls: [CoachToolCall(id: id, callID: id, name: "log_food", namespace: "mivu", arguments: arguments)], outputItems: [])
    }
    private var finishedReply: CoachInferenceResult { CoachInferenceResult(model: "fixture", text: "Fixture finished.", calls: [], outputItems: []) }

    @Test func workoutReceiptsResolveOwnedSurvivorsAndPreserveMealLinks() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let owner = try #require(diary.readModel?.profile.id)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { CoachUITestInference.respond })
        coach.draft.text = "Two eggs, three bread slices and salad"
        #expect(await coach.send()); await coach.waitForWorker()
        let foodTurnID = try #require(coach.captureReceipt), ownerSelection = try #require(diary.selection)
        let foodTurn = try await diary.store.coachExchange(turnID: foodTurnID, expectedSelection: ownerSelection)
        let meal = try #require(diary.readModel?.meals.first)
        coach.draft.text = "I did 30 minutes of strength: Squat, 8 repetitions at 40 kg, estimated burn 200 kcal"
        #expect(await coach.send()); await coach.waitForWorker()
        let turnID = try #require(coach.captureReceipt)
        let turn = try await diary.store.coachExchange(turnID: turnID, expectedSelection: ownerSelection)
        let workout = try #require(diary.readModel?.workouts.first)
        await coach.loadTimelineIfNeeded()
        await coach.refreshLinks()
        #expect(coach.linkedWorkouts(turn).map(\.id) == [workout.id])
        #expect(coach.linkedMeals(turn).isEmpty)
        #expect(coach.linkedMeals(foodTurn).map(\.id) == [meal.id])
        #expect(coach.linkedWorkouts(foodTurn).isEmpty)
        await diary.createProfile(name: "Synthetic other owner")
        #expect(coach.linkedWorkouts(turn).isEmpty)
        #expect(coach.linkedMeals(foodTurn).isEmpty)
        await diary.switchProfile(owner)
        await coach.refreshLinks()
        #expect(coach.linkedWorkouts(turn).map(\.id) == [workout.id])
        try await diary.store.deleteWorkout(id: workout.id, expectedRevision: workout.revision, expectedProfileID: owner)
        try await diary.refresh(profileID: owner)
        #expect(coach.linkedWorkouts(turn).isEmpty)
        let receipt = try #require(turn.receipts.first)
        #expect(coach.receiptTarget(receipt) == .loading)
        await coach.refreshLinks()
        #expect(coach.linkedWorkouts(turn).isEmpty)
        #expect(coach.linkedMeals(foodTurn).map(\.id) == [meal.id])
    }

    @Test func queuedLegacySubmissionsUseFreshMealRevisionWithoutDuplicateRecords() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let owner = try #require(diary.readModel?.profile.id), firstID = UUID(), secondID = UUID()
        let day = try await diary.store.startDay(expectedProfileID: owner)
        let photo = MealPhoto(data: SyntheticConnectionProbe.image)
        let meal = try await capturedMeal(diary.store, text: "Synthetic first food", photos: [photo], reviewFirst: false, dayID: day.id, submissionID: firstID, expectedProfileID: owner)
        _ = try await correctedMeal(diary.store, mealID: meal.id, text: "Synthetic additional food", submissionID: secondID, expectedProfileID: owner)
        try await diary.refresh(profileID: owner)
        let replies = CoachRetryFixture(responses: [foodReply(date: day.localDate, name: "Eggs", quantity: 2, kcal: 140, id: "first"), finishedReply,
            foodReply(date: day.localDate, name: "Bread", quantity: 1, kcal: 80, id: "second"), finishedReply])
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in try await replies.respond() } })
        coach.resume(); await coach.waitForWorker()
        #expect(diary.readModel?.meals.count == 1)
        #expect(diary.readModel?.meals.first?.id == meal.id)
        #expect(diary.readModel?.meals.first?.items.map(\.name) == ["Eggs", "Bread"])
        #expect((try? await diary.store.snapshotForExport())?.meals.first?.photos == [photo])
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.map(\.id) == [firstID, secondID])
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.allSatisfy { $0.state == .completed } == true)
    }

    @Test func legacyPendingCorrectionAfterDirectEditUsesCurrentIdsAndRevision() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let owner = try #require(diary.readModel?.profile.id), pendingID = UUID()
        let day = try await diary.store.startDay(expectedProfileID: owner)
        let initial = CoachRetryFixture(responses: [foodReply(date: day.localDate, name: "Bread", quantity: 2, kcal: 160, id: "initial"), finishedReply])
        let first = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in try await initial.respond() } })
        first.draft.text = "Synthetic bread"
        #expect(await first.send()); await first.waitForWorker()
        let saved = try #require(diary.readModel?.meals.first), previousReceipts = try #require((try? await diary.store.snapshotForExport())?.coachTurns.first?.receipts)
        let photo = MealPhoto(data: SyntheticConnectionProbe.image)
        _ = try await correctedMeal(diary.store, mealID: saved.id, text: "Half of the current bread", photos: [photo], submissionID: pendingID, expectedProfileID: owner)
        var edited = try #require(saved.items.first); edited.quantity = 3
        try await diary.store.editItem(mealID: saved.id, item: edited, explicitNutrients: [], expectedRevision: saved.revision, expectedProfileID: owner)
        try await diary.refresh(profileID: owner)
        let current = try #require(diary.readModel?.meals.first)
        let arguments = "{\"meal_id\":\"\(current.id)\",\"item_id\":\"\(edited.id)\",\"expected_revision\":\(current.revision),\"quantity\":1.5}"
        let call = CoachToolCall(id: "correction", callID: "correction", name: "correct_item", namespace: "mivu", arguments: arguments)
        let replies = CoachRetryFixture(responses: [CoachInferenceResult(model: "fixture", text: "", calls: [call], outputItems: []), finishedReply])
        let resumed = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in try await replies.respond() } })
        resumed.resume(); await resumed.waitForWorker()
        #expect(diary.readModel?.meals.count == 1)
        #expect(diary.readModel?.meals.first?.items.first?.id == edited.id)
        #expect(diary.readModel?.meals.first?.items.first?.quantity == 1.5)
        #expect(diary.readModel?.meals.first?.items.first?.nutrition.kcal == 120)
        #expect((try? await diary.store.snapshotForExport())?.meals.first?.photos == [photo])
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.first?.receipts == previousReceipts)
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.last?.id == pendingID)
        #expect((try? await diary.store.snapshotForExport())?.coachTurns.last?.state == .completed)
    }

    // MARK: Siri capture

    private func siriCoach(_ diary: DiaryViewModel) -> CoachViewModel {
        CoachViewModel(diary: diary, connection: ChatGPTConnection(appleModelAvailable: { false }),
                       inference: { { _, _ in CoachInferenceResult(model: "fixture", text: "Synthetic guidance", calls: [], outputItems: []) } })
    }
    private func turns(_ diary: DiaryViewModel) async throws -> [CoachTurn] { try await diary.store.snapshotForExport().coachTurns }
    private func inbox() -> CoachInbox { CoachInbox(directory: URL.temporaryDirectory.appending(path: "CoachFlowInbox-" + UUID().uuidString)) }

    @Test func externalCaptureCreatesTurnAtSpokenTime() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let coach = siriCoach(diary), id = UUID(), spoken = Date(timeIntervalSinceNow: -600)
        try await coach.captureExternal(profileID: try #require(diary.selection?.identity.profileID), "Synthetic eggs", submissionID: id, capturedAt: spoken)
        await coach.waitForWorker()
        let turn = try #require(try await turns(diary).first { $0.id == id })
        #expect(turn.text == "Synthetic eggs")
        #expect(abs(turn.capturedAt.timeIntervalSince(spoken)) < 0.001)
    }
    @Test func externalCaptureLeavesDraftUntouched() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let coach = siriCoach(diary)
        coach.draft.text = "Unsent"
        let draftID = coach.draft.submissionID
        try await coach.captureExternal(profileID: try #require(diary.selection?.identity.profileID), "Synthetic eggs", submissionID: UUID(), capturedAt: Date())
        await coach.waitForWorker()
        #expect(coach.draft.text == "Unsent")
        #expect(coach.draft.submissionID == draftID)
    }
    @Test func externalCaptureTwiceStoresOneTurn() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let coach = siriCoach(diary), id = UUID(), spoken = Date()
        try await coach.captureExternal(profileID: try #require(diary.selection?.identity.profileID), "Synthetic eggs", submissionID: id, capturedAt: spoken)
        await coach.waitForWorker()
        try await coach.captureExternal(profileID: try #require(diary.selection?.identity.profileID), "Synthetic eggs", submissionID: id, capturedAt: spoken)
        await coach.waitForWorker()
        #expect(try await turns(diary).filter { $0.id == id }.count == 1)
    }
    @Test func queuedSiriWaitsForApproval() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let coach = siriCoach(diary), inbox = inbox(), owner = try #require(diary.selection?.identity.profileID)
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        coach.inbox = inbox
        try inbox.add(CoachInbox.Entry(id: UUID(), profileID: owner, text: "Synthetic toast", capturedAt: Date(timeIntervalSinceNow: -60)))
        try inbox.add(CoachInbox.Entry(id: UUID(), profileID: owner, text: "Synthetic tea", capturedAt: Date(timeIntervalSinceNow: -30)))
        coach.loadQueuedSiri()
        #expect(coach.queuedSiri.map(\.text) == ["Synthetic toast", "Synthetic tea"])
        #expect(try await turns(diary).isEmpty)
    }
    @Test func sendQueuedCapturesAndRemoves() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let coach = siriCoach(diary), inbox = inbox(), owner = try #require(diary.selection?.identity.profileID)
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        coach.inbox = inbox
        let entry = CoachInbox.Entry(id: UUID(), profileID: owner, text: "Synthetic toast", capturedAt: Date(timeIntervalSinceNow: -60))
        try inbox.add(entry); coach.loadQueuedSiri()
        await coach.sendQueued(entry)
        await coach.waitForWorker()
        #expect(try await turns(diary).map(\.text) == ["Synthetic toast"])
        #expect(inbox.entries().isEmpty && coach.queuedSiri.isEmpty)
    }
    @Test func discardQueuedRemovesWithoutCapture() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let coach = siriCoach(diary), inbox = inbox(), owner = try #require(diary.selection?.identity.profileID)
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        coach.inbox = inbox
        let entry = CoachInbox.Entry(id: UUID(), profileID: owner, text: "Synthetic toast", capturedAt: Date())
        try inbox.add(entry); coach.loadQueuedSiri()
        coach.discardQueued(entry)
        #expect(try await turns(diary).isEmpty)
        #expect(inbox.entries().isEmpty && coach.queuedSiri.isEmpty)
    }
    @Test func queuedSiriFollowsTheSelectedProfile() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let coach = siriCoach(diary), inbox = inbox(), first = try #require(diary.selection?.identity.profileID)
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        coach.inbox = inbox
        try inbox.add(CoachInbox.Entry(id: UUID(), profileID: first, text: "Synthetic toast", capturedAt: Date()))
        coach.loadQueuedSiri()
        await diary.createProfile(name: "Synthetic second")
        #expect(diary.selection?.identity.profileID != first)
        #expect(coach.queuedSiri.isEmpty)
        await diary.switchProfile(first)
        #expect(coach.queuedSiri.map(\.text) == ["Synthetic toast"])
    }
    @Test func queuedEntriesOfDeletedProfilesArePruned() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let coach = siriCoach(diary), inbox = inbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        coach.inbox = inbox
        try inbox.add(CoachInbox.Entry(id: UUID(), profileID: UUID(), text: "Synthetic toast", capturedAt: Date()))
        coach.loadQueuedSiri()
        #expect(inbox.entries().isEmpty && coach.queuedSiri.isEmpty)
    }
    @Test func sendingAnAlreadyCapturedEntryStoresOneTurn() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let coach = siriCoach(diary), inbox = inbox(), owner = try #require(diary.selection?.identity.profileID)
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        coach.inbox = inbox
        let entry = CoachInbox.Entry(id: UUID(), profileID: owner, text: "Synthetic toast", capturedAt: Date(timeIntervalSinceNow: -60))
        try inbox.add(entry)
        // A crash after capture but before removal leaves the entry behind.
        try await coach.captureExternal(profileID: owner, entry.text, submissionID: entry.id, capturedAt: entry.capturedAt)
        await coach.waitForWorker()
        await coach.sendQueued(entry)
        await coach.waitForWorker()
        #expect(try await turns(diary).filter { $0.id == entry.id }.count == 1)
        #expect(inbox.entries().isEmpty)
    }
    @Test func inboxRefusesMoreThanTwentyEntries() throws {
        let inbox = inbox(); defer { try? FileManager.default.removeItem(at: inbox.directory) }
        for index in 0..<20 { try inbox.add(CoachInbox.Entry(id: UUID(), profileID: UUID(), text: "Synthetic \(index)", capturedAt: Date())) }
        #expect(throws: (any Error).self) { try inbox.add(CoachInbox.Entry(id: UUID(), profileID: UUID(), text: "One too many", capturedAt: Date())) }
        #expect(inbox.entries().count == 20)
    }
    @Test func externalCaptureWithReusedIDKeepsFirstCapture() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let coach = siriCoach(diary), id = UUID()
        try await coach.captureExternal(profileID: try #require(diary.selection?.identity.profileID), "Synthetic eggs", submissionID: id, capturedAt: Date())
        await coach.waitForWorker()
        try await coach.captureExternal(profileID: try #require(diary.selection?.identity.profileID), "Synthetic other", submissionID: id, capturedAt: Date(timeIntervalSinceNow: 60))
        await coach.waitForWorker()
        #expect(try await turns(diary).filter { $0.id == id }.map(\.text) == ["Synthetic eggs"])
    }
    @Test func externalCaptureRefusesAnotherProfile() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let coach = siriCoach(diary)
        await #expect(throws: DiaryError.wrongOwner) {
            try await coach.captureExternal(profileID: UUID(), "Synthetic eggs", submissionID: UUID(), capturedAt: Date())
        }
        #expect(try await turns(diary).isEmpty)
    }
}
