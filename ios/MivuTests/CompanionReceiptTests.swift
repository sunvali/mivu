import Foundation
import Testing
@testable import Mivu

private enum ReceiptGateFailure: Error { case timeout, closed }

private func receiptDeadline(_ operation: @escaping @Sendable () async throws -> Void) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await operation() }
        group.addTask { try await Task.sleep(for: .seconds(10)); throw ReceiptGateFailure.timeout }
        defer { group.cancelAll() }
        _ = try await group.next()
    }
}

private actor ReceiptRefreshGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var paused = false
    private let entered = AsyncStream<Void>.makeStream()
    func pause() async {
        guard !paused else { return }; paused = true
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation; entered.continuation.yield(())
            }
        } onCancel: { Task { await self.release() } }
    }
    func waitUntilPaused() async throws {
        if paused { return }
        let stream = entered.stream
        do {
            try await receiptDeadline {
                for await _ in stream { return }
                throw ReceiptGateFailure.closed
            }
        } catch { release(); throw error }
    }
    func release() { continuation?.resume(); continuation = nil }
}

private enum ReceiptReviewAction { @TaskLocal static var name: String? }

private actor OrderedReceiptRefreshes {
    private var started: Set<String> = []
    private var continuations: [String: CheckedContinuation<Void, Never>] = [:]
    private let entered = AsyncStream<String>.makeStream()
    func pause(_ name: String?) async {
        guard let name else { return }
        started.insert(name)
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                continuations[name] = continuation; entered.continuation.yield(name)
            }
        } onCancel: { Task { await self.release(name) } }
    }
    func waitUntilPaused(_ name: String) async throws {
        if started.contains(name) { return }
        let stream = entered.stream
        do {
            try await receiptDeadline {
                for await value in stream { if value == name { return } }
                throw ReceiptGateFailure.closed
            }
        } catch { releaseAll(); throw error }
    }
    func release(_ name: String) { continuations.removeValue(forKey: name)?.resume() }
    func releaseAll() { let pending = continuations.values; continuations = [:]; for continuation in pending { continuation.resume() } }
}

private actor ReceiptCaptureAckFailureOnce {
    private var shouldFail = true
    func claim() -> Bool { defer { shouldFail = false }; return shouldFail }
}

@Suite @MainActor struct CompanionReceiptTests {
    private func fixture() async throws -> (URL, DiaryStore, DiaryProfile, TrackingDay) {
        let path = URL.temporaryDirectory.appending(path: "CompanionReceipt-" + UUID().uuidString)
        let store = DiaryStore(directory: path)
        let profile = DiaryProfile(name: "Synthetic owner", timeZoneID: "UTC")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay()
        return (path, store, profile, day)
    }

    private func proposal(_ store: DiaryStore, _ profile: DiaryProfile, _ day: TrackingDay) async throws -> DiaryMeal {
        let meal = try await capturedMeal(store, text: "Synthetic review apple", photos: [], reviewFirst: true,
            dayID: day.id, expectedProfileID: profile.id)
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id,
            submissionID: meal.submissions[0].id, baseRevision: 0,
            items: [FoodItem(name: "Synthetic apple", nutrition: NutritionValues(kcal: 95))]), expectedProfileID: profile.id)
        return try #require(await store.snapshotForExport().meals.first { $0.id == meal.id })
    }

    @Test func capturePublishesCommittingOperationAndRepeatedSubmissionKeepsTimestamp() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let model = DiaryViewModel(store: store); await model.load(createDefaultProfile: false)
        var draft = MealDraft(); draft.text = "Synthetic historical lunch"
        let historical = Date(timeIntervalSince1970: 1_600_000_000)
        let before = Date()
        #expect(await model.capture(draft, dayID: day.id, at: historical))
        let after = Date()
        let event = try #require(model.companionCaptureEvent)
        #expect(event.profileID == profile.id && event.operationID == draft.submissionID && event.kind == .saved)
        #expect(event.committedAt >= before && event.committedAt <= after)
        #expect(model.captureReceipt == draft.submissionID)
        #expect(await model.capture(draft, dayID: day.id, at: historical))
        #expect(model.companionCaptureEvent == event)
        #expect(try await store.snapshotForExport().meals.count == 1)
        #expect(try await store.snapshotForExport().meals.first?.capturedAt == historical)
    }

    @Test func sendPublishesCommittingOperationAndRepeatedSubmissionKeepsTimestamp() async throws {
        let (path, store, profile, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let diary = DiaryViewModel(store: store); await diary.load(createDefaultProfile: false)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        coach.enterBackground()
        var draft = MealDraft(); draft.text = "Synthetic lunch"
        coach.draft = draft
        let before = Date()
        #expect(await coach.send())
        let after = Date()
        let event = try #require(coach.companionCaptureEvent)
        #expect(event.profileID == profile.id && event.operationID == draft.submissionID && event.kind == .saved)
        #expect(event.committedAt >= before && event.committedAt <= after)
        #expect(coach.captureReceipt == draft.submissionID && coach.draft.text.isEmpty)
        coach.draft = draft
        #expect(await coach.send())
        #expect(coach.companionCaptureEvent == event)
        #expect(try await store.snapshotForExport().coachTurns.map(\.id) == [draft.submissionID])
    }

    @Test func acceptedSendPublishesDurableFeedbackBeforeRefresh() async throws {
        let (path, store, profile, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let gate = ReceiptRefreshGate()
        defer { Task { await gate.release() } }
        let diary = DiaryViewModel(store: store, actionReadModelLoading: { id in
            await gate.pause()
            return try await store.diaryReadModel(expectedProfileID: id)
        })
        await diary.load(createDefaultProfile: false)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        coach.enterBackground()
        coach.errorMessage = "Synthetic prior failure"
        coach.draft.text = "Synthetic submit"
        let operation = coach.draft.submissionID
        let before = Date()
        let sending = Task { await coach.send() }
        try await gate.waitUntilPaused()
        let submission = try #require(coach.companionSubmission)
        #expect(submission.profileID == profile.id && submission.operationID == operation)
        #expect(submission.acceptedAt >= before && submission.acceptedAt <= Date())
        #expect(coach.isSending && coach.companionIsProcessing && !coach.companionNeedsRecovery)
        #expect(coach.errorMessage == nil)
        #expect(coach.companionCaptureEvent?.operationID == operation && coach.captureReceipt == operation)
        #expect(coach.draft.text.isEmpty)
        #expect(!(await coach.send()))
        #expect(coach.companionSubmission == submission)
        await gate.release()
        #expect(await sending.value)
        #expect(coach.companionCaptureEvent?.operationID == operation)
        #expect(coach.errorMessage == nil)
    }

    @Test func invalidSendNeverSignalsAndFailedSaveImmediatelyNeedsRecovery() async throws {
        let (path, store, _, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let diary = DiaryViewModel(store: store); await diary.load(createDefaultProfile: false)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        coach.enterBackground()
        #expect(!(await coach.send()))
        #expect(coach.companionSubmission == nil)
        coach.draft.text = "Synthetic failed capture"
        try FileManager.default.removeItem(at: path); try Data([1]).write(to: path)
        #expect(!(await coach.send()))
        #expect(coach.companionSubmission?.operationID == coach.draft.submissionID)
        #expect(coach.companionCaptureEvent == nil && coach.captureReceipt == nil)
        #expect(coach.companionNeedsRecovery && !coach.companionIsProcessing)
    }

    @Test func acceptedRetryAfterUncertainCapturePublishesANewGestureWithoutDuplicatingCapture() async throws {
        let (path, store, profile, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let failure = ReceiptCaptureAckFailureOnce()
        let diary = DiaryViewModel(store: store)
        await diary.load(createDefaultProfile: false)
        var dependencies = CoachAttachmentDraft.Dependencies(store: store,
            refresh: { owner in try await diary.refresh(profileID: owner.identity.profileID) })
        let capture = dependencies.capture
        dependencies.capture = { payload, owner in
            let result = try await capture(payload, owner)
            if await failure.claim() { throw DiaryError.persistenceFailed }
            return result
        }
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), attachmentDependencies: dependencies)
        coach.enterBackground()
        coach.draft.text = "Synthetic capture retried after uncertain acknowledgement"
        let operation = coach.draft.submissionID
        #expect(!(await coach.send()))
        let first = try #require(coach.companionSubmission)
        #expect(coach.draft.submissionID == operation && coach.canSend)
        #expect(coach.companionCaptureEvent == nil && coach.captureReceipt == nil)
        #expect(coach.companionNeedsRecovery)
        #expect(await coach.send())
        let retried = try #require(coach.companionSubmission)
        #expect(retried != first, "A separately accepted retry needs a new gesture identity")
        #expect(retried.profileID == profile.id && retried.operationID == operation)
        #expect(coach.companionCaptureEvent?.operationID == operation)
        #expect(try await store.snapshotForExport().coachTurns.map(\.id) == [operation])
    }

    @Test(arguments: [false, true])
    func newlyReportedErrorInterruptsSubmissionAndSurvivesItsSuccessfulSave(repeatsPriorText: Bool) async throws {
        let (path, store, _, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let gate = ReceiptRefreshGate()
        defer { Task { await gate.release() } }
        let diary = DiaryViewModel(store: store, actionReadModelLoading: { id in
            await gate.pause()
            return try await store.diaryReadModel(expectedProfileID: id)
        })
        await diary.load(createDefaultProfile: false)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        coach.enterBackground()
        coach.errorMessage = "Synthetic prior worker error"
        coach.draft.text = "Synthetic next capture"
        let sending = Task { await coach.send() }
        try await gate.waitUntilPaused()
        #expect(!coach.companionNeedsRecovery)
        let newerError = repeatsPriorText ? "Synthetic prior worker error" : "Synthetic newly reported worker error"
        coach.errorMessage = newerError
        #expect(coach.companionNeedsRecovery, "A new error must interrupt acceptance even when its text repeats")
        #expect(!coach.companionIsProcessing)
        await gate.release()
        #expect(await sending.value)
        #expect(coach.errorMessage == newerError, "Saving newer input must not erase another operation's newly reported error")
        #expect(coach.companionNeedsRecovery)
        #expect(coach.captureReceipt != nil)
    }

    @Test func failedCapturePreservesDraftAndEmitsNothing() async throws {
        let (path, store, _, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let model = DiaryViewModel(store: store); await model.load(createDefaultProfile: false)
        try FileManager.default.removeItem(at: path); try Data([1]).write(to: path)
        var draft = MealDraft(); draft.text = "Synthetic lunch"; draft.photos = [Data([1, 2, 3])]
        #expect(!(await model.capture(draft, dayID: day.id)))
        #expect(draft.text == "Synthetic lunch" && draft.photos == [Data([1, 2, 3])])
        #expect(model.companionCaptureEvent == nil && model.captureReceipt == nil)
        await #expect(throws: DiaryError.persistenceFailed) { try await store.snapshotForExport() }
        #expect(model.readModel?.meals.isEmpty == true)
    }

    @Test func failedSendPreservesDraftAndEmitsNothing() async throws {
        let (path, store, _, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let diary = DiaryViewModel(store: store); await diary.load(createDefaultProfile: false)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        coach.enterBackground(); coach.draft.text = "Synthetic lunch"; coach.draft.photos = [Data([1, 2, 3])]
        let submissionID = coach.draft.submissionID
        try FileManager.default.removeItem(at: path); try Data([1]).write(to: path)
        #expect(!(await coach.send()))
        #expect(coach.draft.text == "Synthetic lunch" && coach.draft.photos == [Data([1, 2, 3])])
        #expect(coach.draft.submissionID == submissionID)
        #expect(coach.companionCaptureEvent == nil && coach.captureReceipt == nil)
        await #expect(throws: DiaryError.persistenceFailed) { try await store.snapshotForExport() }
        #expect(coach.exchanges.isEmpty)
    }

    @Test func passiveRefreshAndAnalysisNeverEmitFeedback() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let meal = try await capturedMeal(store, text: "Synthetic apple", photos: [], reviewFirst: true,
            dayID: day.id, expectedProfileID: profile.id)
        let model = DiaryViewModel(store: store); await model.load(createDefaultProfile: false)
        let coach = CoachViewModel(diary: model, connection: ChatGPTConnection())
        coach.enterBackground()
        try await store.processPending(expectedProfileID: profile.id)
        try await model.refresh(profileID: profile.id)
        #expect(model.meal(meal.id)?.state == .awaitingReview)
        #expect(model.companionCaptureEvent == nil && model.companionReviewEvent == nil)
        #expect(coach.companionCaptureEvent == nil)
    }

    @Test func acceptedReviewEmitsOnlyAfterSuccessfulCommit() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let meal = try await proposal(store, profile, day), submissionID = meal.submissions[0].id
        let gate = ReceiptRefreshGate()
        defer { Task { await gate.release() } }
        let model = DiaryViewModel(store: store, actionReadModelLoading: { id in
            let updated = try await store.diaryReadModel(expectedProfileID: id)
            await gate.pause()
            return updated
        })
        await model.load(createDefaultProfile: false)
        var completionTime = Date(timeIntervalSince1970: 1_800_000_000)
        let accepting = Task { await model.acceptReview(mealID: meal.id, submissionID: submissionID,
            expectedProfileID: profile.id, currentTime: { completionTime }) }
        try await gate.waitUntilPaused()
        #expect(model.companionReviewEvent == nil)
        // Subscribers may publish durable facts before the action's own refresh finishes.
        #expect(try await store.snapshotForExport().meals.first?.state == .saved)
        completionTime = completionTime.addingTimeInterval(30)
        await gate.release()
        #expect(await accepting.value)
        let event = try #require(model.companionReviewEvent)
        #expect(event == CompanionEvent(profileID: profile.id, operationID: submissionID,
            kind: .reviewed, committedAt: completionTime))
        #expect(model.meal(meal.id)?.state == .saved)
        #expect(model.companionCaptureEvent == nil && model.captureReceipt == nil)
        #expect(await model.acceptReview(mealID: meal.id, submissionID: submissionID,
            expectedProfileID: profile.id, currentTime: { completionTime.addingTimeInterval(60) }))
        #expect(model.companionReviewEvent == event)
    }

    @Test func failedReviewEmitsNothing() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let meal = try await proposal(store, profile, day)
        let model = DiaryViewModel(store: store); await model.load(createDefaultProfile: false)
        try FileManager.default.removeItem(at: path); try Data([1]).write(to: path)
        #expect(!(await model.acceptReview(mealID: meal.id, submissionID: meal.submissions[0].id, expectedProfileID: profile.id)))
        #expect(model.companionReviewEvent == nil)
        #expect(model.meal(meal.id)?.state == .awaitingReview)
        await #expect(throws: DiaryError.persistenceFailed) { try await store.snapshotForExport() }
    }

    @Test func reviewForChangedProfileCannotEmit() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let meal = try await proposal(store, profile, day)
        let other = DiaryProfile(name: "Synthetic second owner")
        _ = try await store.createProfile(other); _ = try await store.selectProfile(profile.id)
        let gate = ReceiptRefreshGate()
        defer { Task { await gate.release() } }
        let model = DiaryViewModel(store: store, actionReadModelLoading: { id in
            let updated = try await store.diaryReadModel(expectedProfileID: id)
            await gate.pause()
            return updated
        })
        await model.load(createDefaultProfile: false)
        let accepting = Task { await model.acceptReview(mealID: meal.id, submissionID: meal.submissions[0].id, expectedProfileID: profile.id) }
        try await gate.waitUntilPaused()
        await model.switchProfile(other.id)
        await gate.release()
        #expect(!(await accepting.value))
        #expect(model.readModel?.profile.id == other.id && model.readModel?.meals.isEmpty == true)
        let otherSnapshot = try await store.snapshotForExport()
        #expect(otherSnapshot.profile.id == other.id && otherSnapshot.meals.isEmpty)
        #expect(model.companionReviewEvent == nil && model.companionCaptureEvent == nil)
        #expect(!(await model.acceptReview(mealID: meal.id, submissionID: meal.submissions[0].id, expectedProfileID: profile.id)))
        let committed = try await completeSelectedProfile(store, profile.id)
        #expect(committed.meals.first?.state == .saved)
    }

    @Test func captureRefreshFailureStillAcknowledgesDurableSave() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let model = DiaryViewModel(store: store, actionReadModelLoading: { _ in throw DiaryError.persistenceFailed })
        await model.load(createDefaultProfile: false)
        var draft = MealDraft(); draft.text = "Synthetic durable capture"
        #expect(await model.capture(draft, dayID: day.id))
        #expect(model.companionCaptureEvent?.operationID == draft.submissionID && model.captureReceipt == draft.submissionID)
        #expect(draft.text == "Synthetic durable capture" && model.readModel?.profile.id == profile.id)
        // Presentation failure cannot turn an already durable save into a failed capture.
        let durable = try await completeSelectedProfile(DiaryStore(directory: path), profile.id)
        #expect(durable.meals.first?.submissions.first?.id == draft.submissionID)
    }

    @Test func sendRefreshFailureStillEmitsDurableSavedFeedback() async throws {
        let (path, store, profile, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let diary = DiaryViewModel(store: store, actionReadModelLoading: { _ in throw DiaryError.persistenceFailed })
        await diary.load(createDefaultProfile: false)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        coach.enterBackground(); coach.draft.text = "Synthetic durable turn"
        let submissionID = coach.draft.submissionID
        #expect(await coach.send())
        #expect(coach.companionCaptureEvent?.operationID == submissionID && coach.captureReceipt == submissionID)
        #expect(coach.draft.text.isEmpty && coach.draft.submissionID != submissionID)
        #expect(coach.errorMessage == nil)
        let durable = try await completeSelectedProfile(DiaryStore(directory: path), profile.id)
        #expect(durable.coachTurns.map(\.id) == [submissionID])
    }

    @Test func cancelledCaptureWaiterKeepsDurableAcknowledgement() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let other = DiaryProfile(name: "Synthetic second owner")
        _ = try await store.createProfile(other); _ = try await store.selectProfile(profile.id)
        let gate = ReceiptRefreshGate()
        defer { Task { await gate.release() } }
        let model = DiaryViewModel(store: store, actionReadModelLoading: { id in
            let updated = try await store.diaryReadModel(expectedProfileID: id)
            await gate.pause()
            return updated
        })
        await model.load(createDefaultProfile: false)
        var draft = MealDraft(); draft.text = "Synthetic cancelled capture"
        let capture = Task { await model.capture(draft, dayID: day.id) }
        try await gate.waitUntilPaused()
        #expect(model.captureReceipt == draft.submissionID)
        capture.cancel()
        await gate.release()
        #expect(await capture.value)
        #expect(model.companionCaptureEvent?.operationID == draft.submissionID && model.captureReceipt == draft.submissionID)
        #expect(try await store.snapshotForExport().meals.first?.submissions.first?.id == draft.submissionID)
        await model.switchProfile(other.id)
        #expect(model.readModel?.profile.id == other.id && model.readModel?.meals.isEmpty == true)
        let otherSnapshot = try await store.snapshotForExport()
        #expect(otherSnapshot.profile.id == other.id && otherSnapshot.meals.isEmpty)
        #expect(model.companionCaptureEvent?.profileID == profile.id && model.companionCaptureEvent?.profileID != other.id)
        let original = try await completeSelectedProfile(store, profile.id)
        #expect(original.meals.count == 1)
    }

    @Test func cancelledSendWaiterStillAcknowledgesDurableCommitAndPreservesNewerDraft() async throws {
        let (path, store, profile, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let gate = ReceiptRefreshGate()
        defer { Task { await gate.release() } }
        let diary = DiaryViewModel(store: store, actionReadModelLoading: { id in
            let updated = try await store.diaryReadModel(expectedProfileID: id)
            await gate.pause()
            return updated
        })
        await diary.load(createDefaultProfile: false)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        coach.enterBackground(); coach.draft.text = "Synthetic cancelled turn"
        let submissionID = coach.draft.submissionID
        let sending = Task { await coach.send() }
        try await gate.waitUntilPaused()
        #expect(coach.captureReceipt == submissionID && coach.draft.text.isEmpty)
        coach.draft = MealDraft(text: "Synthetic newer unsent draft")
        let newer = coach.draft
        sending.cancel(); await gate.release()
        #expect(await sending.value)
        #expect(coach.companionCaptureEvent?.operationID == submissionID && coach.captureReceipt == submissionID)
        #expect(coach.draft == newer)
        let durable = try await completeSelectedProfile(DiaryStore(directory: path), profile.id)
        #expect(durable.coachTurns.map(\.id) == [submissionID])
    }
    @Test func captureAndReviewUseDistinctKindsForTheSameSubmission() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let model = DiaryViewModel(store: store); await model.load(createDefaultProfile: false)
        var draft = MealDraft(); draft.text = "Synthetic review apple"; draft.reviewFirst = true
        #expect(await model.capture(draft, dayID: day.id))
        let captured = try #require(model.companionCaptureEvent)
        try await store.processPending(expectedProfileID: profile.id)
        try await model.refresh(profileID: profile.id)
        let meal = try #require(model.readModel?.meals.first)
        #expect(await model.acceptReview(mealID: meal.id, submissionID: draft.submissionID, expectedProfileID: profile.id))
        let reviewed = try #require(model.companionReviewEvent)
        #expect(captured.operationID == reviewed.operationID && captured.profileID == reviewed.profileID)
        #expect(captured.kind == .saved && reviewed.kind == .reviewed)
        #expect(model.companionCaptureEvent == captured)
        #expect(try await store.snapshotForExport().meals.first?.state == .saved)
    }

    @Test func reviewRefreshFailureDoesNotEmitAfterDurableCommit() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let meal = try await proposal(store, profile, day)
        let model = DiaryViewModel(store: store, actionReadModelLoading: { _ in throw DiaryError.persistenceFailed })
        await model.load(createDefaultProfile: false)
        #expect(!(await model.acceptReview(mealID: meal.id, submissionID: meal.submissions[0].id, expectedProfileID: profile.id)))
        #expect(model.companionReviewEvent == nil && model.meal(meal.id)?.state == .awaitingReview)
        let durable = try await completeSelectedProfile(DiaryStore(directory: path), profile.id)
        #expect(durable.meals.first?.state == .saved)
    }

    @Test func cancellationCannotEmitAnotherProfilesSuccess() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let meal = try await proposal(store, profile, day)
        let other = DiaryProfile(name: "Synthetic second owner")
        _ = try await store.createProfile(other); _ = try await store.selectProfile(profile.id)
        let gate = ReceiptRefreshGate()
        defer { Task { await gate.release() } }
        let model = DiaryViewModel(store: store, actionReadModelLoading: { id in
            let updated = try await store.diaryReadModel(expectedProfileID: id)
            await gate.pause()
            return updated
        })
        await model.load(createDefaultProfile: false)
        let accepting = Task { await model.acceptReview(mealID: meal.id, submissionID: meal.submissions[0].id, expectedProfileID: profile.id) }
        try await gate.waitUntilPaused()
        accepting.cancel()
        await model.switchProfile(other.id)
        await gate.release()
        #expect(!(await accepting.value))
        #expect(model.readModel?.profile.id == other.id && model.readModel?.meals.isEmpty == true)
        let otherSnapshot = try await store.snapshotForExport()
        #expect(otherSnapshot.profile.id == other.id && otherSnapshot.meals.isEmpty)
        #expect(model.companionReviewEvent == nil && model.companionCaptureEvent == nil)
        let original = try await completeSelectedProfile(store, profile.id)
        #expect(original.meals.first?.state == .saved)
    }

    @Test func overlappingReviewCompletionsCannotRepeatAnEarlierOperation() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let first = try await proposal(store, profile, day), second = try await proposal(store, profile, day)
        let refreshes = OrderedReceiptRefreshes()
        defer { Task { await refreshes.releaseAll() } }
        let model = DiaryViewModel(store: store, actionReadModelLoading: { id in
            let updated = try await store.diaryReadModel(expectedProfileID: id)
            await refreshes.pause(ReceiptReviewAction.name)
            return updated
        })
        await model.load(createDefaultProfile: false)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let firstAccept = Task { await ReceiptReviewAction.$name.withValue("first") {
            await model.acceptReview(mealID: first.id, submissionID: first.submissions[0].id,
                expectedProfileID: profile.id, currentTime: { now })
        } }
        try await refreshes.waitUntilPaused("first")
        let secondAccept = Task { await ReceiptReviewAction.$name.withValue("second") {
            await model.acceptReview(mealID: second.id, submissionID: second.submissions[0].id,
                expectedProfileID: profile.id, currentTime: { now.addingTimeInterval(1) })
        } }
        try await refreshes.waitUntilPaused("second")
        var duplicateClockRead = false
        let duplicateAccept = Task { await ReceiptReviewAction.$name.withValue("duplicate") {
            await model.acceptReview(mealID: first.id, submissionID: first.submissions[0].id,
                expectedProfileID: profile.id, currentTime: { duplicateClockRead = true; return now.addingTimeInterval(2) })
        } }
        try await refreshes.waitUntilPaused("duplicate")
        #expect(model.companionReviewEvent == nil)
        await refreshes.release("first")
        #expect(await firstAccept.value)
        #expect(model.companionReviewEvent?.operationID == first.submissions[0].id)
        await refreshes.release("second")
        #expect(await secondAccept.value)
        let secondEvent = try #require(model.companionReviewEvent)
        #expect(secondEvent.operationID == second.submissions[0].id)
        await refreshes.release("duplicate")
        #expect(await duplicateAccept.value)
        #expect(model.companionReviewEvent == secondEvent)
        #expect(!duplicateClockRead)
        let durable = try await completeSelectedProfile(DiaryStore(directory: path), profile.id)
        #expect(durable.meals.count == 2 && durable.meals.allSatisfy { $0.state == .saved && $0.revision == 1 })
    }

}
