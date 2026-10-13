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
                    throw CoachFlowWaitFailure.workerEndedBeforeInference(state: coach.turns.first?.state, message: coach.errorMessage)
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
        #expect(diary.snapshot?.coachTurns.first?.state == .waitingForConnection)
        #expect(diary.snapshot?.meals.isEmpty == true)
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
        #expect(diary.snapshot?.coachTurns.first?.assistantText == nil)
        await suspended.finish()
    }

    private func fixture() async throws -> (DiaryViewModel, URL) {
        let path = URL.temporaryDirectory.appending(path: "CoachFlow-" + UUID().uuidString)
        let store = DiaryStore(directory: path)
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic coach"))
        let diary = DiaryViewModel(store: store)
        diary.snapshot = try await store.snapshot()
        return (diary, path)
    }
    @Test func sendCommitsTextAndPhotoBeforeInferenceAndRelaunch() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let suspended = CoachFlowSuspension()
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in await suspended.respond() } })
        coach.draft.text = "Synthetic lunch"; coach.draft.photos = [SyntheticConnectionProbe.image]
        let id = coach.draft.submissionID
        #expect(await coach.send())
        #expect(coach.draft.text.isEmpty)
        let stored = try await DiaryStore(directory: path).selectProfile(#require(diary.snapshot?.profile.id))
        #expect(stored.coachTurns.first?.id == id)
        #expect(stored.coachTurns.first?.text == "Synthetic lunch")
        #expect(stored.coachTurns.first?.photos.first?.data == SyntheticConnectionProbe.image)
        #expect(stored.coachTurns.first?.assistantText == nil)
        try await waitUntilStarted(suspended, coach: coach)
        try #require(await suspended.started)
        await suspended.finish(); await coach.waitForWorker()
        #expect(diary.snapshot?.coachTurns.first?.state == .completed)
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
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        coach.draft.text = "Synthetic dinner"
        #expect(await coach.send()); await coach.waitForWorker()
        #expect(diary.snapshot?.coachTurns.first?.state == .waitingForConnection)
        #expect(diary.snapshot?.meals.isEmpty == true)
        #expect(diary.snapshot?.coachTurns.first?.assistantText == nil)
    }
    @Test func profileTransitionFencesSuspendedCoachResult() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let suspended = CoachFlowSuspension()
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in await suspended.respond() } })
        coach.draft.text = "Synthetic input"
        #expect(await coach.send())
        try await waitUntilStarted(suspended, coach: coach)
        try #require(await suspended.started)
        let first = try #require(diary.snapshot?.profile.id)
        await diary.createProfile(name: "Synthetic second")
        await diary.switchProfile(first)
        await suspended.finish(); await coach.waitForWorker()
        #expect(diary.snapshot?.coachTurns.first?.assistantText == nil)
        #expect(diary.snapshot?.meals.isEmpty == true)
    }
    @Test func manualProductionCaptureAssociatesSameMealAndNeverRunsSampleWorker() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let owner = try #require(diary.snapshot?.profile.id)
        let day = try await diary.store.startDay(expectedProfileID: owner)
        var draft = MealDraft(); draft.text = "Synthetic manual dinner"; draft.reviewFirst = true
        #expect(await diary.capture(draft, dayID: day.id)); await diary.waitForWorker()
        #expect(diary.snapshot?.meals.count == 1)
        #expect(diary.snapshot?.meals.first?.items.isEmpty == true)
        #expect(diary.snapshot?.coachTurns.first?.id == draft.submissionID)
        #expect(diary.snapshot?.coachTurns.first?.pendingMealID == diary.snapshot?.meals.first?.id)
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
        #expect(diary.snapshot?.coachTurns.first?.state == .completed)
    }
    @Test func exhaustedOfflineTurnResumesAfterRelaunchWithoutNewCapture() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let replies = CoachRetryFixture(transientFailures: 4)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in try await replies.respond() } }, sleep: { await replies.record($0) })
        coach.draft.text = "Synthetic offline capture"
        let id = coach.draft.submissionID
        #expect(await coach.send()); await coach.waitForWorker()
        #expect(await replies.calls == 4)
        #expect(diary.snapshot?.coachTurns.first?.state == .waitingForNetwork)
        let reopened = DiaryViewModel(store: DiaryStore(directory: path))
        reopened.snapshot = try await reopened.store.selectProfile(#require(diary.snapshot?.profile.id))
        let resumed = CoachViewModel(diary: reopened, connection: ChatGPTConnection(), inference: { { _, _ in try await replies.respond() } }, sleep: { await replies.record($0) })
        resumed.resume(); await resumed.waitForWorker()
        #expect(await replies.calls == 5)
        #expect(reopened.snapshot?.coachTurns.count == 1)
        #expect(reopened.snapshot?.coachTurns.first?.id == id)
        #expect(reopened.snapshot?.coachTurns.first?.state == .completed)
    }
    @Test func forbiddenInferenceNeverRetriesAutomatically() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let replies = CoachRetryFixture(forbidden: true)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in try await replies.respond() } }, sleep: { await replies.record($0) })
        coach.draft.text = "Synthetic permission capture"
        #expect(await coach.send()); await coach.waitForWorker()
        #expect(await replies.calls == 1)
        #expect(await replies.delays.isEmpty)
        #expect(diary.snapshot?.coachTurns.first?.state == .waitingForConnection)
    }
    @Test func legacyPhotoSubmissionRecoversStableTurnWithoutDuplicateMealOrBytes() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let owner = try #require(diary.snapshot?.profile.id)
        let day = try await diary.store.startDay(expectedProfileID: owner)
        let id = UUID(), photo = MealPhoto(data: SyntheticConnectionProbe.image)
        let meal = try await diary.store.capture(text: "", photos: [photo], reviewFirst: false, dayID: day.id, submissionID: id, expectedProfileID: owner)
        try await diary.refresh(profileID: owner)
        let arguments = "{\"target_local_date\":\"\(day.localDate)\",\"items\":[{\"name\":\"Eggs\",\"quantity\":2,\"unit\":\"egg\",\"kcal\":140,\"carbs\":1,\"protein\":12,\"fat\":10}]}"
        let call = CoachToolCall(id: "legacy-call", callID: "legacy-call", name: "log_food", namespace: "mivu", arguments: arguments)
        let replies = CoachRetryFixture(responses: [CoachInferenceResult(model: "fixture", text: "", calls: [call], outputItems: []), CoachInferenceResult(model: "fixture", text: "Fixture finished.", calls: [], outputItems: [])])
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in try await replies.respond() } })
        coach.resume(); await coach.waitForWorker(); coach.resume(); await coach.waitForWorker()
        #expect(diary.snapshot?.coachTurns.count == 1)
        #expect(diary.snapshot?.coachTurns.first?.id == id)
        #expect(diary.snapshot?.coachTurns.first?.pendingMealID == meal.id)
        #expect(diary.snapshot?.coachTurns.first?.photos.isEmpty == true)
        #expect(diary.snapshot?.meals.count == 1)
        #expect(diary.snapshot?.meals.first?.photos == [photo])
        #expect(diary.snapshot?.meals.first?.items.first?.name == "Eggs")
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
        let owner = try #require(diary.snapshot?.profile.id)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { CoachUITestInference.respond })
        coach.draft.text = "Two eggs, three bread slices and salad"
        #expect(await coach.send()); await coach.waitForWorker()
        let foodTurn = try #require(coach.turns.last), meal = try #require(diary.snapshot?.meals.first)
        coach.draft.text = "I did 30 minutes of strength: Squat, 8 repetitions at 40 kg, estimated burn 200 kcal"
        #expect(await coach.send()); await coach.waitForWorker()
        let turn = try #require(coach.turns.last), workout = try #require(diary.snapshot?.workouts.first)
        #expect(coach.linkedWorkouts(turn).map(\.id) == [workout.id])
        #expect(coach.linkedMeals(turn).isEmpty)
        #expect(coach.linkedMeals(foodTurn).map(\.id) == [meal.id])
        #expect(coach.linkedWorkouts(foodTurn).isEmpty)
        await diary.createProfile(name: "Synthetic other owner")
        #expect(coach.linkedWorkouts(turn).isEmpty)
        await diary.switchProfile(owner)
        #expect(coach.linkedWorkouts(turn).map(\.id) == [workout.id])
        try await diary.store.deleteWorkout(id: workout.id, expectedRevision: workout.revision, expectedProfileID: owner)
        try await diary.refresh(profileID: owner)
        #expect(coach.linkedWorkouts(turn).isEmpty)
        #expect(coach.linkedMeals(foodTurn).map(\.id) == [meal.id])
    }

    @Test func queuedLegacySubmissionsUseFreshMealRevisionWithoutDuplicateRecords() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let owner = try #require(diary.snapshot?.profile.id), firstID = UUID(), secondID = UUID()
        let day = try await diary.store.startDay(expectedProfileID: owner)
        let photo = MealPhoto(data: SyntheticConnectionProbe.image)
        let meal = try await diary.store.capture(text: "Synthetic first food", photos: [photo], reviewFirst: false, dayID: day.id, submissionID: firstID, expectedProfileID: owner)
        _ = try await diary.store.correctMeal(mealID: meal.id, text: "Synthetic additional food", submissionID: secondID, expectedProfileID: owner)
        try await diary.refresh(profileID: owner)
        let replies = CoachRetryFixture(responses: [foodReply(date: day.localDate, name: "Eggs", quantity: 2, kcal: 140, id: "first"), finishedReply,
            foodReply(date: day.localDate, name: "Bread", quantity: 1, kcal: 80, id: "second"), finishedReply])
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in try await replies.respond() } })
        coach.resume(); await coach.waitForWorker()
        #expect(diary.snapshot?.meals.count == 1)
        #expect(diary.snapshot?.meals.first?.id == meal.id)
        #expect(diary.snapshot?.meals.first?.items.map(\.name) == ["Eggs", "Bread"])
        #expect(diary.snapshot?.meals.first?.photos == [photo])
        #expect(diary.snapshot?.coachTurns.map(\.id) == [firstID, secondID])
        #expect(diary.snapshot?.coachTurns.allSatisfy { $0.state == .completed } == true)
    }

    @Test func legacyPendingCorrectionAfterDirectEditUsesCurrentIdsAndRevision() async throws {
        let (diary, path) = try await fixture(); defer { try? FileManager.default.removeItem(at: path) }
        let owner = try #require(diary.snapshot?.profile.id), pendingID = UUID()
        let day = try await diary.store.startDay(expectedProfileID: owner)
        let initial = CoachRetryFixture(responses: [foodReply(date: day.localDate, name: "Bread", quantity: 2, kcal: 160, id: "initial"), finishedReply])
        let first = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in try await initial.respond() } })
        first.draft.text = "Synthetic bread"
        #expect(await first.send()); await first.waitForWorker()
        let saved = try #require(diary.snapshot?.meals.first), previousReceipts = try #require(diary.snapshot?.coachTurns.first?.receipts)
        let photo = MealPhoto(data: SyntheticConnectionProbe.image)
        _ = try await diary.store.correctMeal(mealID: saved.id, text: "Half of the current bread", photos: [photo], submissionID: pendingID, expectedProfileID: owner)
        var edited = try #require(saved.items.first); edited.quantity = 3
        try await diary.store.editItem(mealID: saved.id, item: edited, expectedRevision: saved.revision, expectedProfileID: owner)
        try await diary.refresh(profileID: owner)
        let current = try #require(diary.snapshot?.meals.first)
        let arguments = "{\"meal_id\":\"\(current.id)\",\"item_id\":\"\(edited.id)\",\"expected_revision\":\(current.revision),\"quantity\":1.5}"
        let call = CoachToolCall(id: "correction", callID: "correction", name: "correct_item", namespace: "mivu", arguments: arguments)
        let replies = CoachRetryFixture(responses: [CoachInferenceResult(model: "fixture", text: "", calls: [call], outputItems: []), finishedReply])
        let resumed = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in try await replies.respond() } })
        resumed.resume(); await resumed.waitForWorker()
        #expect(diary.snapshot?.meals.count == 1)
        #expect(diary.snapshot?.meals.first?.items.first?.id == edited.id)
        #expect(diary.snapshot?.meals.first?.items.first?.quantity == 1.5)
        #expect(diary.snapshot?.meals.first?.items.first?.nutrition.kcal == 120)
        #expect(diary.snapshot?.meals.first?.photos == [photo])
        #expect(diary.snapshot?.coachTurns.first?.receipts == previousReceipts)
        #expect(diary.snapshot?.coachTurns.last?.id == pendingID)
        #expect(diary.snapshot?.coachTurns.last?.state == .completed)
    }
}
