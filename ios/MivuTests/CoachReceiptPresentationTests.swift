import Foundation
import Testing
import SwiftUI
import UIKit
@testable import Mivu

@Suite struct CoachReceiptPresentationTests {
    private func receipt() -> CoachCommittedReceipt {
        CoachCommittedReceipt(operationKey: "original", turnID: UUID(), dayID: UUID(), mealID: UUID(),
            committedRevision: 900, targetLocalDate: "2026-10-17",
            items: [CoachCommittedItem(itemID: UUID(), name: "Chicken", quantity: 3, unit: "piece",
                nutrition: NutritionValues(kcal: nil, carbs: 0), provenance: .estimate, uncertain: true)], submissionState: .saved)
    }

    @Test func originalFactsSurviveLaterEditMoveAndDeletion() {
        let receipt = receipt()
        let meal = MealReadModel(id: receipt.mealID!, dayID: UUID(), capturedAt: Date(), eatenAt: Date(), revision: 1,
            items: [FoodItem(name: "Chicken", quantity: 1, unit: "piece", nutrition: NutritionValues(kcal: 150))], submissions: [], photos: [])
        let changed = CoachReceiptPresentation(receipt: receipt, target: .meal(meal, localDate: "2026-10-18"))
        #expect(changed.committedDate == "2026-10-17")
        #expect(changed.committedItems == ["Chicken · 3 piece"])
        #expect(changed.currentDate == "2026-10-18")
        #expect(changed.currentNutrition == "150 kcal")
        #expect(changed.canOpenTarget)
        let deleted = CoachReceiptPresentation(receipt: receipt, target: .unavailable)
        #expect(deleted.committedItems == changed.committedItems)
        #expect(deleted.committedDate == changed.committedDate)
        #expect(!deleted.canOpenTarget)
        #expect(deleted.currentStatus == "Record unavailable")
    }

    @Test func unknownEstimatesStayUnknownAndRealZeroStaysZero() {
        var receipt = receipt()
        var value = CoachReceiptPresentation(receipt: receipt, target: .loading)
        #expect(value.committedNutrition == "Energy unknown")
        #expect(value.estimateLabel == "Estimated nutrition")
        receipt.items[0].nutrition?.kcal = 0
        value = CoachReceiptPresentation(receipt: receipt, target: .failed)
        #expect(value.committedNutrition == "0 kcal")
        #expect(value.currentStatus == "Could not load current record")
    }

    @Test func committedMacrosKeepKnownZeroAndRequireEveryItemForEachNutrient() {
        var receipt = receipt()
        receipt.items[0].nutrition = NutritionValues(kcal: 100, carbs: 0, protein: 10.5, fat: 2)
        var other = receipt.items[0]; other.itemID = UUID(); other.nutrition = NutritionValues(kcal: 50, carbs: 0, protein: 4.5, fat: 3)
        receipt.items.append(other)
        let current = MealReadModel(id: receipt.mealID!, dayID: UUID(), capturedAt: Date(), eatenAt: Date(), revision: 2,
            items: [FoodItem(name: "Edited", nutrition: NutritionValues(kcal: 500, carbs: 60, protein: 30, fat: 20))], submissions: [], photos: [])
        var value = CoachReceiptPresentation(receipt: receipt, target: .meal(current, localDate: "2026-10-18"))
        #expect(value.committedNutrition == "150 kcal")
        #expect(value.committedMacros == "Carbs 0 g · Protein 15 g · Fat 5 g")
        #expect(value.currentMacros == "Carbs 60 g · Protein 30 g · Fat 20 g")
        #expect(value.nutritionCompleteness == nil)
        receipt.items[1].nutrition?.protein = nil
        value = CoachReceiptPresentation(receipt: receipt, target: .unavailable)
        #expect(value.committedNutrition == "150 kcal")
        #expect(value.committedMacros == "Carbs 0 g · Protein unknown · Fat 5 g")
        #expect(value.nutritionCompleteness == "Some nutrients unknown")
        receipt.items[0].nutrition = nil
        value = CoachReceiptPresentation(receipt: receipt, target: .loading)
        #expect(value.committedNutrition == "Energy unknown")
        #expect(value.committedMacros == "Carbs unknown · Protein unknown · Fat unknown")
    }

    @Test func legacyAndAwaitingReviewDoNotClaimSavedFood() {
        var receipt = receipt()
        receipt.submissionState = .awaitingReview
        #expect(CoachReceiptPresentation(receipt: receipt, target: .loading).committedStatus == "Estimate awaiting review")
        receipt.submissionState = nil; receipt.items = []
        let legacy = CoachReceiptPresentation(receipt: receipt, target: .unavailable)
        #expect(legacy.committedStatus == "Recorded operation")
        #expect(legacy.committedNutrition == nil)
        #expect(legacy.committedMacros == nil)
        #expect(legacy.estimateLabel == nil)
    }
}

private actor PhotoPublicationSignal {
    private var signaled = false
    private var continuation: CheckedContinuation<Bool, Never>?
    func signal() { signaled = true; continuation?.resume(returning: true); continuation = nil }
    func wait() async -> Bool {
        if signaled { return true }
        let deadline = Task { try? await Task.sleep(for: .seconds(10)); if !Task.isCancelled { expire() } }
        defer { deadline.cancel() }
        return await withCheckedContinuation { continuation = $0 }
    }
    private func expire() { continuation?.resume(returning: false); continuation = nil }
}

private actor ReturnedPhotoGate {
    private var held: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private let returned = PhotoPublicationSignal()
    func hold() async {
        guard !released else { return }
        await withCheckedContinuation { continuation in
            held.append(continuation); Task { await returned.signal() }
        }
    }
    func waitUntilReturned() async -> Bool { await returned.wait() }
    func release() { released = true; held.forEach { $0.resume() }; held = [] }
}

@Suite @MainActor struct CoachMountedPhotoPublicationTests {
    @Test(arguments: [false, true]) func mountedPreviewRejectsReturnedOldCompletion(replaceScope: Bool) async throws {
        let directory = URL.temporaryDirectory.appending(path: "MountedPhoto-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiaryStore(directory: directory)
        let original = try CoachUITestInference.historySnapshot()
        _ = try await store.importProfile(original)
        let diary = DiaryViewModel(store: store); await diary.load(createDefaultProfile: false)
        let meal = try await store.meal(id: CoachUITestInference.historyID(910), expectedProfileID: original.profile.id)
        let reference = try #require(meal.photos.first)
        let oldRequest = DiaryPhotoRequest(profileID: diary.selection?.identity.profileID, epoch: diary.selection?.selectionEpoch,
            timeline: diary.selection?.identity.timelineGeneration, reference: reference.id, generation: diary.photoRequestGeneration)
        let gate = ReturnedPhotoGate(), currentPublished = PhotoPublicationSignal(), oldFinished = PhotoPublicationSignal(), wrongReferenceFinished = PhotoPublicationSignal(), replacementReturned = PhotoPublicationSignal()
        defer { Task { await gate.release() } }
        var assignments: [DiaryPhotoRequest] = []
        let hosting = UIHostingController(rootView: DiaryPhotoPreview(model: diary, reference: reference,
            afterLoad: { request, _ in
                if request != oldRequest { await replacementReturned.signal() }
                await gate.hold()
            }, onAssignment: { request, _ in assignments.append(request) },
            onCompletion: { request, accepted in
                if request == oldRequest { Task { await oldFinished.signal() } }
                if let profileID = request.profileID, profileID != request.reference.profileID {
                    #expect(!accepted)
                    Task { await wrongReferenceFinished.signal() }
                }
            }).id(UUID()))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 600); window.rootViewController = hosting
        window.makeKeyAndVisible(); defer { window.isHidden = true }
        let returned = await gate.waitUntilReturned()
        try #require(returned)
        var nextReference = reference
        if replaceScope {
            var other = original; other.profile.id = UUID(); other.profile.name = "Second synthetic profile"
            _ = try await store.importProfile(other)
            await diary.switchProfile(other.profile.id)
            let nextMeal = try await store.meal(id: meal.id, expectedProfileID: other.profile.id)
            nextReference = try #require(nextMeal.photos.first)
            let rejectedWrongReference = await wrongReferenceFinished.wait()
            #expect(rejectedWrongReference)
        } else {
            var profile = original.profile; profile.preferences = "Changed after returned thumbnail"
            try await store.updateProfile(profile, expectedProfileID: profile.id)
            // Wait for the real store subscriber's new mounted request; an additional
            // foreground refresh could legitimately publish the same revision again.
            let newRequestReturned = await replacementReturned.wait()
            try #require(newRequestReturned)
        }
        #expect(assignments.isEmpty)
        hosting.rootView = DiaryPhotoPreview(model: diary, reference: nextReference, onAssignment: { request, _ in
            assignments.append(request); Task { await currentPublished.signal() }
        }).id(UUID())
        let newPublished = await currentPublished.wait()
        try #require(newPublished)
        let current = try #require(assignments.last)
        await gate.release()
        let rejected = await oldFinished.wait()
        #expect(rejected)
        #expect(assignments == [current])
        #expect(current.reference == nextReference.id)
        #expect(current.epoch == diary.selection?.selectionEpoch)
        #expect(current.generation == diary.photoRequestGeneration)
    }
}

@Suite @MainActor struct CoachTimelineStoreAdapterTests {
    @Test(arguments: [CoachTurnState.needsRetry, .waitingForConnection])
    func freshRecoveryUsesOwnedMetadataWithoutDecodingAnExchange(state: CoachTurnState) async throws {
        let directory = URL.temporaryDirectory.appending(path: "OperationMetadata-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: directory, diagnostics: metrics)
        var original = try CoachUITestInference.historySnapshot()
        original.coachTurns[original.coachTurns.count - 1].state = state
        _ = try await store.importProfile(original)
        let diary = DiaryViewModel(store: store); await diary.load(createDefaultProfile: false)
        let owner = try #require(diary.selection), latest = try #require(original.coachTurns.last)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        metrics.reset()
        await coach.refreshActiveOperation()
        #expect(coach.activeOperationTurn == CoachOperationMetadata(id: latest.id, state: state, capturedAt: latest.capturedAt))
        #expect(coach.companionNeedsRecovery)
        #expect(metrics.counters.decodedTurnPayloads == 0 && metrics.counters.coachPageReads == 0)
        #expect(metrics.counters.completeReads == 0 && metrics.counters.originalPhotoBytes == 0)
        _ = try await store.selectProfile(owner.identity.profileID)
        await #expect(throws: DiaryError.wrongOwner) { try await store.coachOperationMetadata(expectedSelection: owner) }
    }

    @Test func residentRefreshIsBoundedConsistentAndRejectsOldSelection() async throws {
        let directory = URL.temporaryDirectory.appending(path: "TimelineAdapter-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: directory, diagnostics: metrics)
        let original = try CoachUITestInference.historySnapshot()
        _ = try await store.importProfile(original)
        let owner = try await store.selectionOwnership(expectedProfileID: original.profile.id)
        metrics.reset()
        let id = CoachUITestInference.historyID(140)
        try await store.completeCoachTurn(turnID: id, assistantText: "Updated resident reply", expectedProfileID: original.profile.id)
        let result = try await store.coachTimelineRefresh(ids: [id], expectedSelection: owner)
        #expect(result.exchanges.count == 1 && result.exchanges.first?.assistantText == "Updated resident reply")
        #expect(result.latestCursor?.turnID == id)
        #expect(result.latestEmptySegment?.trackingDayID == CoachUITestInference.historyID(904))
        #expect(metrics.counters.coachPageReads == 0 && metrics.counters.completeReads == 0 && metrics.counters.originalPhotoBytes == 0)
        _ = try await store.selectProfile(original.profile.id)
        await #expect(throws: DiaryError.wrongOwner) { try await store.coachTimelineRefresh(ids: [id], expectedSelection: owner) }
    }
}

@Suite @MainActor struct CoachHistoricalDayChoiceTests {
    @Test func coldReopenKeepsPreviousWakingDayChoiceWithoutLoadingDiaryDay() async throws {
        let directory = URL.temporaryDirectory.appending(path: "HistoricalDayChoice-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var original = try CoachUITestInference.historySnapshot()
        original.coachTurns[0].state = .needsClarification; original.coachTurns[0].needsDayChoice = true
        original.coachTurns[0].capturedAt = original.days[3].startAt
        let initial = DiaryStore(directory: directory)
        _ = try await initial.importProfile(original)
        // A genuinely reopened store/view model has no exact-day cache from the seed.
        let reopened = DiaryStore(directory: directory), diary = DiaryViewModel(store: reopened)
        await diary.load(createDefaultProfile: false)
        let owner = try #require(diary.selection), dayID = try #require(original.coachTurns[0].activeDayID)
        #expect(diary.day(dayID) == nil)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        let request = CoachNavigationRequest(identity: owner.identity, target: .turn(original.coachTurns[0].id), requestID: UUID())
        let found = await coach.seek(request)
        #expect(found)
        let turn = try #require(coach.turns.first { $0.id == original.coachTurns[0].id })
        #expect(turn.needsDayChoice)
        #expect(coach.previousDayDate(turn) == "2027-01-20")
        #expect(diary.day(dayID) == nil, "Coach's bounded label query must not require opening/loading the full diary day")
        _ = try await reopened.selectProfile(owner.identity.profileID)
        await #expect(throws: DiaryError.wrongOwner) {
            try await reopened.coachCapturedDayLabels(ids: [dayID], expectedSelection: owner)
        }
    }
}


@Suite @MainActor struct CoachCurrentTargetRefreshTests {
    private func waitFor(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition(), "Mounted Coach did not publish the expected current receipt target")
    }

    @Test func workoutOnlyChangeRefreshesAfterDiaryPublishesItsNewGeneration() async throws {
        let directory = URL.temporaryDirectory.appending(path: "CurrentTarget-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var original = ChatHistoryFixture.snapshot(exchanges: 1)
        original.coachTurns[0].state = .completed
        original.coachTurns[0].photos = []; original.coachTurns[0].photoIDs = []
        let workout = original.workouts[0], turnID = original.coachTurns[0].id
        original.coachTurns[0].receipts = [CoachReceipt(operationKey: turnID.uuidString + "/workout/original", turnID: turnID,
            dayID: workout.dayID, workoutID: workout.id, committedRevision: 1, resultJSON: try coachJSON(workout))]
        let store = DiaryStore(directory: directory)
        _ = try await store.importProfile(original)
        let gate = Task10Gate(), once = Task10Once()
        defer { Task { await gate.releaseAll() } }
        let diary = DiaryViewModel(store: store, subscriberReadModelLoading: { owner in
            let value = try await store.diaryReadModel(expectedProfileID: owner)
            if await once.claim() { await gate.hold(0) }
            return value
        })
        await diary.load(createDefaultProfile: false)
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        await coach.loadTimelineIfNeeded()
        let turn = try #require(coach.turns.first), receipt = try #require(turn.receipts.first)
        let initialLinksRevision = coach.linksRevision
        let runtime = CompanionRuntime()
        let output = CompanionOutput(pose: .resting, playback: .hidden, reactionID: nil, nextDeadline: nil)
        let hosting = UIHostingController(rootView: CoachView(coach: coach, companionOutput: output, companionRuntime: runtime,
            onCompanionContextChanged: { _ in }, openDestination: { _ in }))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        window.rootViewController = hosting; window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true; runtime.stop() }
        // The mounted view's initial refresh has finished before the controlled mutation.
        try await waitFor { coach.linksRevision > initialLinksRevision && coach.linkedWorkouts(turn).first == workout }
        let generation = diary.changeGeneration, timelineRevision = coach.timeline?.revision
        let linksBeforeChange = coach.linksRevision
        let stream = await store.changes(expectedProfileID: original.profile.id)
        var iterator = stream.makeAsyncIterator()
        var edited = workout; edited.durationMinutes = 25
        let saved = try await store.updateWorkout(edited, expectedRevision: workout.revision, expectedProfileID: original.profile.id)
        let change = try #require(await iterator.next())
        #expect(change.workoutIDs == [workout.id] && change.turnIDs.isEmpty && !change.coachLatestChanged)
        try await gate.waitForArrivals(1)
        // Coach's actual store-event consumer finishes at G; Diary is still held before G+1.
        try await waitFor { coach.linksRevision > linksBeforeChange && coach.linkedWorkouts(turn).first == saved }
        #expect(diary.changeGeneration == generation)
        #expect(diary.readModel?.workouts.first == workout)
        #expect(coach.timeline?.revision == timelineRevision)
        let earlyLinksRevision = coach.linksRevision
        await gate.release(0)
        // No manual refreshLinks, diary refresh, timeline page or second mutation may repair this.
        try await waitFor { diary.changeGeneration > generation && coach.linksRevision > earlyLinksRevision && coach.linkedWorkouts(turn).first == saved }
        #expect(diary.readModel?.workouts.first == saved)
        #expect(coach.timeline?.revision == timelineRevision)
        if case .workout(let current, _) = coach.receiptTarget(receipt) { #expect(current == saved) }
        else { Issue.record("Current workout receipt remained hidden after the new diary generation") }
    }
}

@Suite @MainActor struct CoachIntegratedBudgetTests {
    @Test func diaryStartupAndHistoricalWindowShareOneTranscriptBudget() async throws {
        let directory = URL.temporaryDirectory.appending(path: "IntegratedTranscript-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: directory, diagnostics: metrics)
        let original = try CoachUITestInference.historySnapshot()
        _ = try await store.importProfile(original)
        let diary = DiaryViewModel(store: store)
        let persistentCoach = CoachViewModel(diary: diary, connection: ChatGPTConnection())
        metrics.reset()
        await diary.load(createDefaultProfile: false)
        #expect(metrics.counters.decodedTurnPayloads == 0 && metrics.counters.coachPageReads == 0)
        await persistentCoach.loadTimelineIfNeeded()
        #expect(metrics.counters.decodedTurnPayloads == 20 && metrics.counters.coachPageReads == 1)
        #expect(metrics.counters.completeReads == 0 && metrics.counters.originalPhotoBytes == 0)
        let timeline = try #require(persistentCoach.timeline)
        for _ in 0..<6 {
            let first = try #require(timeline.exchanges.first)
            let anchor = CoachViewportAnchor(rowID: first.id, offset: 0)
            timeline.setViewport(.history(anchor), visibleIDs: [first.id], measuredAnchor: anchor)
            let loadingResult = timeline.loadEarlier(anchor: anchor)
            let loading = try #require(loadingResult)
            #expect(timeline.window.residentCount + timeline.window.reservedCapacity <= 100)
            await loading.value
        }
        let resident = Set(timeline.exchanges.map(\.id))
        #expect(resident.count == 100 && !resident.contains(CoachUITestInference.historyID(140)))
        #expect(Set(persistentCoach.exchanges.map(\.id)) == resident && Set(persistentCoach.turns.map(\.id)) == resident)
        #expect(timeline.window.residentCount + timeline.window.reservedCapacity <= 100 && timeline.peakCapacity <= 100)
        metrics.reset()
        var profile = original.profile; profile.preferences = "Metadata-only refresh with a full historical window"
        try await store.updateProfile(profile, expectedProfileID: profile.id)
        try await diary.refresh(profileID: profile.id)
        await persistentCoach.refreshActiveOperation()
        #expect(metrics.counters.decodedTurnPayloads == 0 && metrics.counters.coachPageReads == 0)
        #expect(metrics.counters.completeReads == 0 && metrics.counters.originalPhotoBytes == 0)
        #expect(Set(timeline.exchanges.map(\.id)) == resident)
        #expect(Set(persistentCoach.exchanges.map(\.id)).union(persistentCoach.turns.map(\.id)).count == 100)
    }
}
