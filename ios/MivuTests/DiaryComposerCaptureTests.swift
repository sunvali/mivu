import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct DiaryComposerCaptureTests {
    @Test func automaticTodayResolutionIsProtectedAndOwnedBeforeItsFirstAwait() async throws {
        let path = URL.temporaryDirectory.appending(path: "ComposerAutomatic-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = DiaryStore(directory: path), profile = DiaryProfile(name: "Synthetic automatic", timeZoneID: "UTC")
        _ = try await store.createProfile(profile)
        let gate = ComposerCaptureGate(), protection = ComposerProtectionProbe()
        let model = DiaryViewModel(store: store, beginCaptureProtection: protection.begin, captureDayAssignment: { _, _ in
            await gate.pause(); try Task.checkCancellation(); return .newDay
        })
        await model.load(createDefaultProfile: false)
        var draft = MealDraft(); draft.text = "Synthetic new Today"; draft.photos = [SyntheticConnectionProbe.image]
        let pending = Task { await model.capture(draft, destination: .automatic) }
        try await gate.waitUntilPaused()
        #expect(protection.begun == 1 && protection.ended == 0)
        #expect(model.hasCaptureInFlight && model.captureReceipt == nil)
        pending.cancel(); await gate.release()
        let result = await pending.value
        guard case .saved(let id) = result else { Issue.record("Admitted Today capture must survive the cancelled waiter"); return }
        #expect(model.captureReceipt == draft.submissionID && protection.ended == 1)
        #expect(model.meal(id)?.photos.count == 1 && model.meal(id)?.dayID == model.activeDay?.id)
        let owner = try #require(model.selection)
        #expect(try await store.capturedMeal(submissionID: draft.submissionID, expectedSelection: owner, expectedProfileID: profile.id)?.id == id)
    }

    @Test func existingMealPhotoAcknowledgesDurablyAndReplaysOriginalPhotoIdentity() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let protection = ComposerProtectionProbe()
        let model = DiaryViewModel(store: f.store, actionReadModelLoading: { _ in throw DiaryError.persistenceFailed }, beginCaptureProtection: protection.begin)
        await model.load(createDefaultProfile: false)
        var draft = MealDraft(); draft.text = "Synthetic extra photo"; draft.photos = [SyntheticConnectionProbe.image]; draft.reviewFirst = true
        #expect(await model.capture(draft, destination: .meal(f.meal.id), photoRole: .after) == .saved(f.meal.id))
        #expect(model.captureReceipt == draft.submissionID && model.companionCaptureEvent?.operationID == draft.submissionID)
        #expect(protection.begun == 1 && protection.ended == 1)
        #expect(model.errorMessage == "Saved on this iPhone. Reload the diary to refresh totals.")
        let first = try await f.store.meal(id: f.meal.id, expectedProfileID: f.profile.id)
        let photo = try #require(first.photos.last), event = model.companionCaptureEvent
        #expect(photo.role == .after && first.items == f.meal.items)
        #expect(first.submissions.last?.id == draft.submissionID && first.submissions.last?.reviewFirst == true)
        #expect(await model.capture(draft, destination: .meal(f.meal.id), photoRole: .after) == .saved(f.meal.id))
        let replay = try await f.store.meal(id: f.meal.id, expectedProfileID: f.profile.id)
        #expect(replay.photos == first.photos && replay.submissions.count == first.submissions.count && replay.revision == first.revision)
        #expect(model.companionCaptureEvent == event)
        #expect(try await f.store.photoContent(photo, expectedProfileID: f.profile.id) == draft.photos[0])
    }

    @Test func existingMealPhotoWaiterCancellationDoesNotCancelAcceptedOperation() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let gate = ComposerCaptureGate(), protection = ComposerProtectionProbe()
        let model = DiaryViewModel(store: f.store, actionReadModelLoading: { id in
            await gate.pause(); return try await f.store.diaryReadModel(expectedProfileID: id)
        }, beginCaptureProtection: protection.begin)
        await model.load(createDefaultProfile: false)
        var draft = MealDraft(); draft.text = "Synthetic cancelled extra photo"; draft.photos = [SyntheticConnectionProbe.image]
        let pending = Task { await model.capture(draft, destination: .meal(f.meal.id)) }
        try await gate.waitUntilPaused()
        #expect(model.captureReceipt == draft.submissionID && protection.begun == 1 && protection.ended == 0)
        pending.cancel(); await gate.release()
        #expect(await pending.value == .saved(f.meal.id))
        #expect(protection.ended == 1)
        #expect(try await f.store.meal(id: f.meal.id, expectedProfileID: f.profile.id).submissions.last?.id == draft.submissionID)
    }

    @Test func ambiguousDayEndsProtectionWithoutCapturingUntilUserChooses() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.path) }
        let protection = ComposerProtectionProbe()
        let model = DiaryViewModel(store: f.store, beginCaptureProtection: protection.begin, captureDayAssignment: { _, _ in .ask(f.meal.dayID) })
        await model.load(createDefaultProfile: false)
        var draft = MealDraft(); draft.text = "Synthetic ambiguous photo"; draft.photos = [SyntheticConnectionProbe.image]
        #expect(await model.capture(draft, destination: .automatic) == .needsDayChoice(f.meal.dayID))
        #expect(protection.begun == 1 && protection.ended == 1 && !model.hasCaptureInFlight)
        #expect(model.captureReceipt == nil && model.savedMealID == nil)
        let owner = try #require(model.selection)
        #expect(try await f.store.capturedMeal(submissionID: draft.submissionID, expectedSelection: owner, expectedProfileID: f.profile.id) == nil)
        #expect(await model.capture(draft, destination: .day(f.meal.dayID, dateOnly: false)) != .failed)
        #expect(protection.begun == 2 && protection.ended == 2 && model.captureReceipt == draft.submissionID)
    }

    @Test func correctionRetryKeepsOriginalCaptureClockAfterMidnight() async throws {
        let path = URL.temporaryDirectory.appending(path: "ComposerClock-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let beforeMidnight = try #require(ISO8601DateFormatter().date(from: "2026-10-19T23:59:00Z"))
        let afterMidnight = beforeMidnight.addingTimeInterval(120)
        let clock = ComposerCaptureClock(beforeMidnight)
        let store = DiaryStore(directory: path, currentTime: { clock.now() })
        let profile = DiaryProfile(name: "Synthetic correction clock", timeZoneID: "UTC")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay(at: beforeMidnight)
        let owner = try await store.selectionOwnership(expectedProfileID: profile.id)
        let original = try await store.captureProjection(text: "Synthetic original", photos: [], reviewFirst: false,
            dayID: day.id, at: beforeMidnight, expectedSelection: owner, expectedProfileID: profile.id)
        let model = DiaryViewModel(store: store)
        await model.load(createDefaultProfile: false)
        var draft = MealDraft(); draft.text = "Synthetic extra photo"; draft.photos = [SyntheticConnectionProbe.image]
        let database = path.appendingPathComponent(profile.id.uuidString + ".sqlite").appendingPathComponent("diary.sqlite")
        // Fail the real transaction after submission insertion, without changing production seams.
        try ChatHistoryFixture.execute(database, "CREATE TRIGGER reject_correction_clock BEFORE INSERT ON coach_turn BEGIN SELECT RAISE(ABORT, 'synthetic first persistence failure'); END")
        #expect(await model.capture(draft, destination: .meal(original.id), at: beforeMidnight) == .failed)
        #expect(model.captureReceipt == nil && model.errorMessage != nil)
        #expect(try await store.meal(id: original.id, expectedProfileID: profile.id).submissions.count == 1)
        try ChatHistoryFixture.execute(database, "DROP TRIGGER reject_correction_clock")
        clock.set(afterMidnight)
        #expect(await model.capture(draft, destination: .meal(original.id), at: afterMidnight) == .saved(original.id))
        let accepted = try await store.coachWorkItem(turnID: draft.submissionID, expectedProfileID: profile.id)
        #expect(accepted.capturedAt == beforeMidnight)
        #expect(accepted.captureTimeZoneID == "UTC" && accepted.pendingMealID == original.id)
        let meal = try await store.meal(id: original.id, expectedProfileID: profile.id)
        #expect(meal.submissions.count == 2 && meal.photos.count == 1)
        #expect(model.captureReceipt == draft.submissionID)
    }

    private func fixture() async throws -> (path: URL, store: DiaryStore, profile: DiaryProfile, meal: MealReadModel) {
        let path = URL.temporaryDirectory.appending(path: "ComposerExisting-" + UUID().uuidString)
        let store = DiaryStore(directory: path), profile = DiaryProfile(name: "Synthetic existing meal", timeZoneID: "UTC")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay(), owner = try await store.selectionOwnership(expectedProfileID: profile.id)
        let captured = try await store.captureProjection(text: "Synthetic original", photos: [], reviewFirst: false, dayID: day.id,
            expectedSelection: owner, expectedProfileID: profile.id)
        try await store.processPending(expectedProfileID: profile.id)
        return (path, store, profile, try await store.meal(id: captured.id, expectedProfileID: profile.id))
    }
}

private actor ComposerCaptureGate {
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
@MainActor private final class ComposerProtectionProbe {
    var begun = 0, ended = 0
    func begin() -> (@MainActor () -> Void) { begun += 1; return { self.ended += 1 } }
}

private final class ComposerCaptureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func now() -> Date { lock.withLock { value } }
    func set(_ date: Date) { lock.withLock { value = date } }
}
