import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct HistoricalCaptureReceiptTests {
    @Test func historicalCapturePublishesBoundedCurrentReceiptWithoutMovingToday() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let model = DiaryViewModel(store: f.store)
        await model.load(createDefaultProfile: false)
        await model.loadDay(f.historical.id)
        let owner = try #require(model.selection)
        f.metrics.reset()
        var draft = MealDraft(); draft.text = "Synthetic historical photo"; draft.photos = [SyntheticConnectionProbe.image]; draft.reviewFirst = true
        #expect(await model.capture(draft, dayID: f.historical.id, at: f.now, dateOnly: true, expectedSelection: owner))
        let id = try #require(model.savedMealID)
        let projected = try #require(model.meal(id))
        #expect(projected.dayID == f.historical.id && projected.timePrecision == .dateOnly)
        #expect(projected.capturedAt == f.now && projected.eatenAt == f.historical.startAt)
        #expect(projected.submissions.first?.reviewFirst == true && projected.photos.count == 1)
        #expect(model.activeDay?.id == f.today.id && model.todaysMeals.isEmpty)
        let event = model.companionCaptureEvent
        #expect(await model.capture(draft, dayID: f.historical.id, at: f.now, dateOnly: true, expectedSelection: owner))
        #expect(model.savedMealID == id && model.companionCaptureEvent == event)
        #expect(try await f.store.diaryDay(id: f.historical.id, expectedProfileID: f.profile.id).meals.count == 1)
        #expect(f.metrics.counters.completeReads == 0 && f.metrics.counters.completeReconciles == 0 && f.metrics.counters.originalPhotoBytes == 0)
    }

    @Test func historicalReceiptCacheEvictsOldEntriesAtItsExistingBound() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let model = DiaryViewModel(store: f.store); await model.load(createDefaultProfile: false)
        f.metrics.reset()
        var firstID: UUID?
        for index in 0..<31 {
            var draft = MealDraft(); draft.text = "Synthetic historical receipt \(index)"
            #expect(await model.capture(draft, dayID: f.historical.id, at: f.now, dateOnly: true))
            let id = try #require(model.savedMealID)
            if firstID == nil { firstID = id }
            #expect(model.meal(id) != nil)
        }
        #expect(model.meal(try #require(firstID)) == nil)
        #expect(model.activeDay?.id == f.today.id && model.todaysMeals.isEmpty)
        #expect(f.metrics.counters.completeReads == 0 && f.metrics.counters.originalPhotoBytes == 0)
    }

    @Test func durableCaptureAcknowledgesBeforeRefreshAndSurvivesPresentationFailure() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let gate = HistoricalReceiptGate()
        let model = DiaryViewModel(store: f.store, actionReadModelLoading: { _ in
            await gate.pauseOnce(); throw DiaryError.persistenceFailed
        }, mealDetailLoading: { _, _ in throw DiaryError.persistenceFailed })
        await model.load(createDefaultProfile: false)
        var draft = MealDraft(); draft.text = "Synthetic durable historical input"
        let task = Task { await model.capture(draft, dayID: f.historical.id, at: f.now, dateOnly: true) }
        try await gate.waitUntilPaused()
        #expect(model.captureReceipt == draft.submissionID && model.companionCaptureEvent?.operationID == draft.submissionID)
        #expect(model.savedMealID != nil)
        await gate.release()
        #expect(await task.value)
        #expect(model.errorMessage == "Saved on this iPhone. Reload the diary to refresh totals.")
        let first = try #require(model.savedMealID), event = model.companionCaptureEvent
        #expect(await model.capture(draft, dayID: f.historical.id, at: f.now, dateOnly: true))
        #expect(model.savedMealID == first && model.companionCaptureEvent == event)
        #expect(try await f.store.diaryDay(id: f.historical.id, expectedProfileID: f.profile.id).meals.count == 1)
    }

    @Test func lateHistoricalReceiptLoadCannotPublishForAnotherStoreOwner() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let other = adultProfile(name: "Synthetic other", timeZoneID: "UTC")
        _ = try await f.store.createProfile(other); _ = try await f.store.selectProfile(f.profile.id)
        let gate = HistoricalReceiptGate()
        let model = DiaryViewModel(store: f.store, mealDetailLoading: { id, owner in
            let value = try await f.store.meal(id: id, expectedProfileID: owner)
            await gate.pauseOnce(); return value
        })
        await model.load(createDefaultProfile: false)
        var draft = MealDraft(); draft.text = "Synthetic old owner capture"
        let task = Task { await model.capture(draft, dayID: f.historical.id, at: f.now, dateOnly: true) }
        try await gate.waitUntilPaused()
        let id = try #require(model.savedMealID), acknowledged = model.companionCaptureEvent
        _ = try await f.store.selectProfile(other.id)
        await gate.release()
        #expect(!(await task.value))
        #expect(model.meal(id) == nil && model.companionCaptureEvent == acknowledged)
        await model.switchProfile(other.id)
        #expect(model.savedMealID == nil && model.meal(id) == nil)
        #expect(model.companionCaptureEvent == acknowledged && acknowledged?.profileID != other.id)
        #expect(model.readModel?.profile.id == other.id && model.todaysMeals.isEmpty)
    }

    @Test func newerGenerationRejectsOldReceiptLoadAndReloadsCurrentProposal() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let gate = HistoricalReceiptGate()
        let model = DiaryViewModel(store: f.store, mealDetailLoading: { id, owner in
            let value = try await f.store.meal(id: id, expectedProfileID: owner)
            await gate.pauseOnce(); return value
        })
        await model.load(createDefaultProfile: false)
        var draft = MealDraft(); draft.text = "Synthetic later review"; draft.reviewFirst = true
        let task = Task { await model.capture(draft, dayID: f.historical.id, at: f.now, dateOnly: true) }
        try await gate.waitUntilPaused()
        let id = try #require(model.savedMealID), generation = model.changeGeneration
        try await f.store.processPending(expectedProfileID: f.profile.id)
        try await model.refresh(profileID: f.profile.id)
        #expect(model.changeGeneration > generation)
        await gate.release()
        #expect(await task.value)
        #expect(model.meal(id)?.state == .awaitingReview)
        #expect(model.meal(id)?.submissions.first?.proposal != nil)
        #expect(model.activeDay?.id == f.today.id && model.todaysMeals.isEmpty)
    }

    @Test func ownedDiaryCaptureProtectionAndBackgroundHandoffSurviveWaiterCancellation() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let refresh = HistoricalReceiptGate(), analysis = HistoricalReceiptGate(), protection = HistoricalProtectionProbe(), lease = HistoricalLeaseProbe()
        let model = DiaryViewModel(store: f.store, actionReadModelLoading: { owner in
            await refresh.pauseOnce(); return try await f.store.diaryReadModel(expectedProfileID: owner)
        }, beginCaptureProtection: protection.begin)
        await model.load(createDefaultProfile: false)
        let coach = CoachViewModel(diary: model, connection: ChatGPTConnection(), inference: { { _, _ in
            await analysis.pauseOnce()
            return CoachInferenceResult(model: "fixture", text: "Synthetic result", calls: [], outputItems: [])
        } })
        defer { coach.cancel(); model.enterBackground() }
        model.resumeCoach = { coach.resume() }; coach.pauseForInactiveScene()
        #expect(!(await model.capture(MealDraft(), dayID: f.historical.id)))
        #expect(protection.begun == 0)
        var draft = MealDraft(); draft.text = "Synthetic pocketed Diary photo"; draft.photos = [SyntheticConnectionProbe.image]
        let sending = Task { await model.capture(draft, dayID: f.historical.id, at: f.now, dateOnly: true) }
        try await refresh.waitUntilPaused()
        #expect(protection.begun == 1 && protection.ended == 0 && model.hasCaptureInFlight)
        #expect(model.captureReceipt == draft.submissionID)
        #expect(!(await model.capture(draft, dayID: f.historical.id)))
        #expect(protection.begun == 1)
        sending.cancel()
        coach.continueInBackground(begin: lease.begin, end: lease.end)
        #expect(lease.begun == 1 && lease.ended == 0)
        await refresh.release()
        #expect(await sending.value)
        try await analysis.waitUntilPaused()
        #expect(lease.ended == 0 && protection.ended == 1)
        await analysis.release()
        await model.waitForCapture(); await coach.waitForBackgroundCompletion()
        #expect(!model.hasCaptureInFlight && lease.ended == 1)
        #expect(coach.captureReceipt == nil && model.captureReceipt == draft.submissionID)
        #expect(try await f.store.coachResult(turnID: draft.submissionID, expectedProfileID: f.profile.id).state == .completed)
    }

    @Test(arguments: ["denied", "expired"])
    func lateSampleCaptureWakeCannotRestartProcessingAfterLeaseEnds(outcome: String) async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let model = DiaryViewModel(store: f.store, sampleMode: true)
        await model.load(createDefaultProfile: false)
        await model.waitForWorker()
        let coach = CoachViewModel(diary: model, connection: ChatGPTConnection())
        defer { coach.cancel(); model.enterBackground() }
        let owner = try #require(model.selection)
        let saved = try await f.store.captureProjection(text: "Synthetic pending sample", photos: [], reviewFirst: true,
            dayID: f.today.id, at: f.now, expectedSelection: owner, expectedProfileID: f.profile.id)
        try await model.refresh(profileID: f.profile.id)
        #expect(try await f.store.meal(id: saved.id, expectedProfileID: f.profile.id).state == .captured)
        var begins = 0
        var expiration: (@MainActor () -> Void)?
        coach.continueInBackground(begin: { begins += 1; expiration = $0; return outcome == "expired" }, end: {})
        #expect(begins == 1, "The fixture must exercise the actual denied/granted lease branch")
        if outcome == "expired" { expiration?() }
        // This is the same callback used by a local capture that completes after the lease ends.
        model.resumeWorker()
        await model.waitForWorker()
        #expect(try await f.store.meal(id: saved.id, expectedProfileID: f.profile.id).state == .captured)
        // A newly granted lease can resume the still-durable sample normally.
        coach.continueInBackground(begin: { _ in true }, end: {})
        await coach.waitForBackgroundCompletion()
        #expect(try await f.store.meal(id: saved.id, expectedProfileID: f.profile.id).state == .awaitingReview)
    }

    @Test func completedSampleBackgroundDrainBlocksLaterCaptureWake() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let model = DiaryViewModel(store: f.store, sampleMode: true)
        await model.load(createDefaultProfile: false); await model.waitForWorker()
        let coach = CoachViewModel(diary: model, connection: ChatGPTConnection())
        defer { coach.cancel(); model.enterBackground() }
        let owner = try #require(model.selection)
        let first = try await f.store.captureProjection(text: "Synthetic first sample", photos: [], reviewFirst: true,
            dayID: f.today.id, at: f.now, expectedSelection: owner, expectedProfileID: f.profile.id)
        try await model.refresh(profileID: f.profile.id)
        var begins = 0, ends = 0
        coach.continueInBackground(begin: { _ in begins += 1; return true }, end: { ends += 1 })
        await coach.waitForBackgroundCompletion()
        #expect(begins == 1 && ends == 1)
        #expect(try await f.store.meal(id: first.id, expectedProfileID: f.profile.id).state == .awaitingReview)
        let late = try await f.store.captureProjection(text: "Synthetic late sample", photos: [], reviewFirst: true,
            dayID: f.historical.id, at: f.now, expectedSelection: owner, expectedProfileID: f.profile.id)
        model.resumeWorker(); await model.waitForWorker()
        #expect(try await f.store.meal(id: late.id, expectedProfileID: f.profile.id).state == .captured)
    }

    @Test func backgroundWithoutKnownPendingWorkStillBlocksLateSampleWake() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let model = DiaryViewModel(store: f.store, sampleMode: true)
        await model.load(createDefaultProfile: false); await model.waitForWorker()
        let coach = CoachViewModel(diary: model, connection: ChatGPTConnection())
        defer { coach.cancel(); model.enterBackground() }
        var begins = 0
        coach.continueInBackground(begin: { _ in begins += 1; return true }, end: {})
        #expect(begins == 0)
        let owner = try #require(model.selection)
        let saved = try await f.store.captureProjection(text: "Synthetic late sample", photos: [], reviewFirst: true,
            dayID: f.historical.id, at: f.now, dateOnly: true, expectedSelection: owner, expectedProfileID: f.profile.id)
        #expect(try await f.store.meal(id: saved.id, expectedProfileID: f.profile.id).state == .captured)
        model.resumeWorker(); await model.waitForWorker()
        #expect(try await f.store.meal(id: saved.id, expectedProfileID: f.profile.id).state == .captured)
    }

    private func fixture() async throws -> (path: URL, store: DiaryStore, profile: DiaryProfile, historical: TrackingDay, today: TrackingDay, now: Date, metrics: DiaryQueryDiagnostics) {
        let path = URL.temporaryDirectory.appending(path: "HistoricalReceipt-" + UUID().uuidString)
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: path, diagnostics: metrics)
        let profile = adultProfile(name: "Synthetic historical receipt", timeZoneID: "UTC")
        _ = try await store.createProfile(profile)
        let now = Date(timeIntervalSince1970: 1_792_411_200)
        let historical = try await store.startDay(at: now.addingTimeInterval(-86_400))
        let today = try await store.startDay(at: now)
        return (path, store, profile, historical, today, now, metrics)
    }
}

private actor HistoricalReceiptGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var used = false
    func pauseOnce() async {
        guard !used else { return }; used = true
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilPaused() async throws {
        for _ in 0..<1000 {
            if continuation != nil { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw DiaryError.persistenceFailed
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor private final class HistoricalProtectionProbe {
    var begun = 0, ended = 0
    func begin() -> (@MainActor () -> Void) { begun += 1; return { self.ended += 1 } }
}
@MainActor private final class HistoricalLeaseProbe {
    var begun = 0, ended = 0
    func begin(_ expire: @escaping @MainActor () -> Void) -> Bool { begun += 1; return true }
    func end() { ended += 1 }
}
