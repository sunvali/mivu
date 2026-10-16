import Foundation
import Testing
@testable import Mivu

private actor ReceiptRefreshGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var paused = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        guard !paused else { return }
        paused = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            waiters.forEach { $0.resume() }; waiters = []
        }
    }
    func waitUntilPaused() async {
        if !paused { await withCheckedContinuation { waiters.append($0) } }
    }
    func release() { continuation?.resume(); continuation = nil }
}

private actor OrderedReceiptRefreshes {
    private var started = 0
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]

    func pause() async {
        started += 1
        let index = started
        await withCheckedContinuation { continuation in
            continuations[index] = continuation
            waiters.removeValue(forKey: index)?.resume()
        }
    }
    func waitUntilPaused(_ index: Int) async {
        if started < index { await withCheckedContinuation { waiters[index] = $0 } }
    }
    func release(_ index: Int) { continuations.removeValue(forKey: index)?.resume() }
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
        let meal = try await store.capture(text: "Synthetic review apple", photos: [], reviewFirst: true,
            dayID: day.id, expectedProfileID: profile.id)
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id,
            submissionID: meal.submissions[0].id, baseRevision: 0,
            items: [FoodItem(name: "Synthetic apple", nutrition: NutritionValues(kcal: 95))]), expectedProfileID: profile.id)
        return try #require(await store.snapshot().meals.first { $0.id == meal.id })
    }

    @Test func capturePublishesCommittingOperationAndRepeatedSubmissionKeepsTimestamp() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let model = DiaryViewModel(store: store); model.snapshot = try await store.snapshot()
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
        #expect(try await store.snapshot().meals.count == 1)
        #expect(try await store.snapshot().meals.first?.capturedAt == historical)
    }

    @Test func sendPublishesCommittingOperationAndRepeatedSubmissionKeepsTimestamp() async throws {
        let (path, store, profile, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let diary = DiaryViewModel(store: store); diary.snapshot = try await store.snapshot()
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
        #expect(try await store.snapshot().coachTurns.map(\.id) == [draft.submissionID])
    }

    @Test func failedCapturePreservesDraftAndEmitsNothing() async throws {
        let (path, store, _, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let model = DiaryViewModel(store: store); model.snapshot = try await store.snapshot()
        try FileManager.default.removeItem(at: path); try Data([1]).write(to: path)
        var draft = MealDraft(); draft.text = "Synthetic lunch"; draft.photos = [Data([1, 2, 3])]
        #expect(!(await model.capture(draft, dayID: day.id)))
        #expect(draft.text == "Synthetic lunch" && draft.photos == [Data([1, 2, 3])])
        #expect(model.companionCaptureEvent == nil && model.captureReceipt == nil)
        #expect(try await store.snapshot().meals.isEmpty)
    }

    @Test func failedSendPreservesDraftAndEmitsNothing() async throws {
        let (path, store, _, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let diary = DiaryViewModel(store: store); diary.snapshot = try await store.snapshot()
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        coach.enterBackground(); coach.draft.text = "Synthetic lunch"; coach.draft.photos = [Data([1, 2, 3])]
        let submissionID = coach.draft.submissionID
        try FileManager.default.removeItem(at: path); try Data([1]).write(to: path)
        #expect(!(await coach.send()))
        #expect(coach.draft.text == "Synthetic lunch" && coach.draft.photos == [Data([1, 2, 3])])
        #expect(coach.draft.submissionID == submissionID)
        #expect(coach.companionCaptureEvent == nil && coach.captureReceipt == nil)
        #expect(try await store.snapshot().coachTurns.isEmpty)
    }

    @Test func passiveRefreshAndAnalysisNeverEmitFeedback() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let meal = try await store.capture(text: "Synthetic apple", photos: [], reviewFirst: true,
            dayID: day.id, expectedProfileID: profile.id)
        let model = DiaryViewModel(store: store); model.snapshot = try await store.snapshot()
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
        let model = DiaryViewModel(store: store, snapshotLoading: { id in
            let updated = try await store.snapshot(expectedProfileID: id)
            await gate.pause()
            return updated
        })
        model.snapshot = try await store.snapshot()
        var completionTime = Date(timeIntervalSince1970: 1_800_000_000)
        let accepting = Task { await model.acceptReview(mealID: meal.id, submissionID: submissionID,
            expectedProfileID: profile.id, currentTime: { completionTime }) }
        await gate.waitUntilPaused()
        #expect(model.companionReviewEvent == nil)
        #expect(model.meal(meal.id)?.state == .awaitingReview)
        #expect(try await store.snapshot().meals.first?.state == .saved)
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
        let model = DiaryViewModel(store: store); model.snapshot = try await store.snapshot()
        try FileManager.default.removeItem(at: path); try Data([1]).write(to: path)
        #expect(!(await model.acceptReview(mealID: meal.id, submissionID: meal.submissions[0].id, expectedProfileID: profile.id)))
        #expect(model.companionReviewEvent == nil)
        #expect(model.meal(meal.id)?.state == .awaitingReview)
        #expect(try await store.snapshot().meals.first?.state == .awaitingReview)
    }

    @Test func reviewForChangedProfileCannotEmit() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let meal = try await proposal(store, profile, day)
        let other = DiaryProfile(name: "Synthetic second owner")
        _ = try await store.createProfile(other); _ = try await store.selectProfile(profile.id)
        let gate = ReceiptRefreshGate()
        let model = DiaryViewModel(store: store, snapshotLoading: { id in
            let updated = try await store.snapshot(expectedProfileID: id)
            await gate.pause()
            return updated
        })
        model.snapshot = try await store.snapshot()
        let accepting = Task { await model.acceptReview(mealID: meal.id, submissionID: meal.submissions[0].id, expectedProfileID: profile.id) }
        await gate.waitUntilPaused()
        await model.switchProfile(other.id)
        await gate.release()
        #expect(!(await accepting.value))
        #expect(model.snapshot?.profile.id == other.id && model.snapshot?.meals.isEmpty == true)
        let otherSnapshot = try await store.snapshot()
        #expect(otherSnapshot.profile.id == other.id && otherSnapshot.meals.isEmpty)
        #expect(model.companionReviewEvent == nil && model.companionCaptureEvent == nil)
        #expect(!(await model.acceptReview(mealID: meal.id, submissionID: meal.submissions[0].id, expectedProfileID: profile.id)))
        let committed = try await store.selectProfile(profile.id)
        #expect(committed.meals.first?.state == .saved)
    }

    @Test func captureRefreshFailureDoesNotEmit() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let model = DiaryViewModel(store: store, snapshotLoading: { _ in throw DiaryError.persistenceFailed })
        model.snapshot = try await store.snapshot()
        var draft = MealDraft(); draft.text = "Synthetic durable capture"
        #expect(!(await model.capture(draft, dayID: day.id)))
        #expect(model.companionCaptureEvent == nil && model.captureReceipt == nil)
        #expect(draft.text == "Synthetic durable capture" && model.snapshot?.meals.isEmpty == true)
        let durable = try await DiaryStore(directory: path).selectProfile(profile.id)
        #expect(durable.meals.first?.submissions.first?.id == draft.submissionID)
    }

    @Test func sendRefreshFailureDoesNotEmit() async throws {
        let (path, store, profile, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let diary = DiaryViewModel(store: store, snapshotLoading: { _ in throw DiaryError.persistenceFailed })
        diary.snapshot = try await store.snapshot()
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        coach.enterBackground(); coach.draft.text = "Synthetic durable turn"
        let submissionID = coach.draft.submissionID
        #expect(!(await coach.send()))
        #expect(coach.companionCaptureEvent == nil && coach.captureReceipt == nil)
        #expect(coach.draft.text == "Synthetic durable turn" && coach.draft.submissionID == submissionID)
        let durable = try await DiaryStore(directory: path).selectProfile(profile.id)
        #expect(durable.coachTurns.map(\.id) == [submissionID])
    }

    @Test func cancelledCaptureDoesNotEmitAfterDurableCommit() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let other = DiaryProfile(name: "Synthetic second owner")
        _ = try await store.createProfile(other); _ = try await store.selectProfile(profile.id)
        let gate = ReceiptRefreshGate()
        let model = DiaryViewModel(store: store, snapshotLoading: { id in
            let updated = try await store.snapshot(expectedProfileID: id)
            await gate.pause()
            return updated
        })
        model.snapshot = try await store.snapshot()
        var draft = MealDraft(); draft.text = "Synthetic cancelled capture"
        let capture = Task { await model.capture(draft, dayID: day.id) }
        await gate.waitUntilPaused()
        capture.cancel()
        await gate.release()
        #expect(!(await capture.value))
        #expect(model.companionCaptureEvent == nil && model.captureReceipt == nil)
        #expect(try await store.snapshot().meals.first?.submissions.first?.id == draft.submissionID)
        await model.switchProfile(other.id)
        #expect(model.snapshot?.profile.id == other.id && model.snapshot?.meals.isEmpty == true)
        let otherSnapshot = try await store.snapshot()
        #expect(otherSnapshot.profile.id == other.id && otherSnapshot.meals.isEmpty)
        #expect(model.companionCaptureEvent == nil)
        let original = try await store.selectProfile(profile.id)
        #expect(original.meals.count == 1)
    }

    @Test func cancelledSendKeepsDraftAndDoesNotEmitAfterDurableCommit() async throws {
        let (path, store, profile, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let gate = ReceiptRefreshGate()
        let diary = DiaryViewModel(store: store, snapshotLoading: { id in
            let updated = try await store.snapshot(expectedProfileID: id)
            await gate.pause()
            return updated
        })
        diary.snapshot = try await store.snapshot()
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        coach.enterBackground(); coach.draft.text = "Synthetic cancelled turn"
        let submissionID = coach.draft.submissionID
        let sending = Task { await coach.send() }
        await gate.waitUntilPaused(); sending.cancel(); await gate.release()
        #expect(!(await sending.value))
        #expect(coach.companionCaptureEvent == nil && coach.captureReceipt == nil)
        #expect(coach.draft.text == "Synthetic cancelled turn" && coach.draft.submissionID == submissionID)
        let durable = try await DiaryStore(directory: path).selectProfile(profile.id)
        #expect(durable.coachTurns.map(\.id) == [submissionID])
    }
    @Test func captureAndReviewUseDistinctKindsForTheSameSubmission() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let model = DiaryViewModel(store: store); model.snapshot = try await store.snapshot()
        var draft = MealDraft(); draft.text = "Synthetic review apple"; draft.reviewFirst = true
        #expect(await model.capture(draft, dayID: day.id))
        let captured = try #require(model.companionCaptureEvent)
        try await store.processPending(expectedProfileID: profile.id)
        try await model.refresh(profileID: profile.id)
        let meal = try #require(model.snapshot?.meals.first)
        #expect(await model.acceptReview(mealID: meal.id, submissionID: draft.submissionID, expectedProfileID: profile.id))
        let reviewed = try #require(model.companionReviewEvent)
        #expect(captured.operationID == reviewed.operationID && captured.profileID == reviewed.profileID)
        #expect(captured.kind == .saved && reviewed.kind == .reviewed)
        #expect(model.companionCaptureEvent == captured)
        #expect(try await store.snapshot().meals.first?.state == .saved)
    }

    @Test func reviewRefreshFailureDoesNotEmitAfterDurableCommit() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let meal = try await proposal(store, profile, day)
        let model = DiaryViewModel(store: store, snapshotLoading: { _ in throw DiaryError.persistenceFailed })
        model.snapshot = try await store.snapshot()
        #expect(!(await model.acceptReview(mealID: meal.id, submissionID: meal.submissions[0].id, expectedProfileID: profile.id)))
        #expect(model.companionReviewEvent == nil && model.meal(meal.id)?.state == .awaitingReview)
        let durable = try await DiaryStore(directory: path).selectProfile(profile.id)
        #expect(durable.meals.first?.state == .saved)
    }

    @Test func cancellationCannotEmitAnotherProfilesSuccess() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let meal = try await proposal(store, profile, day)
        let other = DiaryProfile(name: "Synthetic second owner")
        _ = try await store.createProfile(other); _ = try await store.selectProfile(profile.id)
        let gate = ReceiptRefreshGate()
        let model = DiaryViewModel(store: store, snapshotLoading: { id in
            let updated = try await store.snapshot(expectedProfileID: id)
            await gate.pause()
            return updated
        })
        model.snapshot = try await store.snapshot()
        let accepting = Task { await model.acceptReview(mealID: meal.id, submissionID: meal.submissions[0].id, expectedProfileID: profile.id) }
        await gate.waitUntilPaused()
        accepting.cancel()
        await model.switchProfile(other.id)
        await gate.release()
        #expect(!(await accepting.value))
        #expect(model.snapshot?.profile.id == other.id && model.snapshot?.meals.isEmpty == true)
        let otherSnapshot = try await store.snapshot()
        #expect(otherSnapshot.profile.id == other.id && otherSnapshot.meals.isEmpty)
        #expect(model.companionReviewEvent == nil && model.companionCaptureEvent == nil)
        let original = try await store.selectProfile(profile.id)
        #expect(original.meals.first?.state == .saved)
    }

    @Test func overlappingReviewCompletionsCannotRepeatAnEarlierOperation() async throws {
        let (path, store, profile, day) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let first = try await proposal(store, profile, day), second = try await proposal(store, profile, day)
        let refreshes = OrderedReceiptRefreshes()
        let model = DiaryViewModel(store: store, snapshotLoading: { id in
            let updated = try await store.snapshot(expectedProfileID: id)
            await refreshes.pause()
            return updated
        })
        model.snapshot = try await store.snapshot()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let firstAccept = Task { await model.acceptReview(mealID: first.id, submissionID: first.submissions[0].id,
            expectedProfileID: profile.id, currentTime: { now }) }
        await refreshes.waitUntilPaused(1)
        let secondAccept = Task { await model.acceptReview(mealID: second.id, submissionID: second.submissions[0].id,
            expectedProfileID: profile.id, currentTime: { now.addingTimeInterval(1) }) }
        await refreshes.waitUntilPaused(2)
        var duplicateClockRead = false
        let duplicateAccept = Task { await model.acceptReview(mealID: first.id, submissionID: first.submissions[0].id,
            expectedProfileID: profile.id, currentTime: { duplicateClockRead = true; return now.addingTimeInterval(2) }) }
        await refreshes.waitUntilPaused(3)
        #expect(model.companionReviewEvent == nil)
        await refreshes.release(1)
        #expect(await firstAccept.value)
        #expect(model.companionReviewEvent?.operationID == first.submissions[0].id)
        await refreshes.release(2)
        #expect(await secondAccept.value)
        let secondEvent = try #require(model.companionReviewEvent)
        #expect(secondEvent.operationID == second.submissions[0].id)
        await refreshes.release(3)
        #expect(await duplicateAccept.value)
        #expect(model.companionReviewEvent == secondEvent)
        #expect(!duplicateClockRead)
        let durable = try await DiaryStore(directory: path).selectProfile(profile.id)
        #expect(durable.meals.count == 2 && durable.meals.allSatisfy { $0.state == .saved && $0.revision == 1 })
    }

}
