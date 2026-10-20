import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct CoachAttachmentDraftTests {
    @Test func draftImportsAreOrderedBoundedAndPartiallyRecoverable() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let gate = Task10Gate(), bytes = try Task10JPEG.tagged()
        var dependencies = Task10Fixture.dependencies(f.diary)
        dependencies.normalize = { data, _ in data }
        let requiredOwner = try #require(f.diary.selection)
        let draft = CoachAttachmentDraft(ownership: requiredOwner, limiter: f.diary.photoWorkLimiter,
            dependencies: dependencies, text: "Preserve my note", attachments: (0..<5).map { _ in MealPhoto(data: bytes) })
        let existingIDs = draft.attachments.map(\.id)
        let first = CoachAttachmentDraft.Selection { await gate.hold(0); return bytes }
        let failed = CoachAttachmentDraft.Selection { throw DiaryError.invalidData }
        let third = CoachAttachmentDraft.Selection { bytes }
        let overflow = CoachAttachmentDraft.Selection { Issue.record("A ninth attachment must not transfer"); return bytes }
        let importing = Task10Fixture.operation(gate: gate) { try await draft.importSelections([first, failed, third, overflow]) }
        do {
            try await gate.waitForArrivals(1)
            #expect(draft.attachments.count + draft.reservedAttachmentCount <= 8)
            await gate.releaseAll()
            let failures = try await importing.value
            #expect(failures.contains(failed.id))
            #expect(draft.attachments.prefix(5).map(\.id) == existingIDs)
            #expect(draft.attachments.dropFirst(5).map(\.id) == [first.id, third.id])
            #expect(draft.attachments.count == 7 && draft.reservedAttachmentCount == 0)
            #expect(draft.text == "Preserve my note")
            let unsent = try await f.diary.store.snapshotForExport()
            #expect(unsent.meals.isEmpty && unsent.coachTurns.isEmpty)
        } catch { await gate.releaseAll(); _ = try? await importing.value; throw error }
    }

    @Test func retakePreservesStableIdentityAndFailedReplacementKeepsOriginal() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let original = MealPhoto(data: try Task10JPEG.tagged(), createdAt: Date(timeIntervalSinceReferenceDate: 100), role: .before)
        var dependencies = Task10Fixture.dependencies(f.diary); dependencies.normalize = { bytes, _ in bytes }
        let requiredOwner = try #require(f.diary.selection)
        let draft = CoachAttachmentDraft(ownership: requiredOwner, limiter: f.diary.photoWorkLimiter,
            dependencies: dependencies, text: "Keep", attachments: [original])
        let submissionID = draft.submissionID
        await #expect(throws: DiaryError.invalidData) {
            try await draft.retake(original.id, selection: .init { throw DiaryError.invalidData })
        }
        #expect(draft.attachments == [original] && draft.submissionID == submissionID)
        var replacement = try Task10JPEG.tagged(); replacement.append(0)
        let replacedBytes = replacement
        try await draft.retake(original.id, selection: .init { replacedBytes })
        #expect(draft.attachments.map(\.id) == [original.id])
        #expect(draft.attachments[0].data == replacedBytes && draft.attachments[0].role == .before)
        #expect(draft.attachments[0].createdAt == original.createdAt)
        #expect(draft.submissionID == submissionID && draft.text == "Keep")
    }

    @Test(arguments: ["remove", "cancel", "close"])
    func lateRetakeCannotRecreateRemovedOrCancelledAttachment(action: String) async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let original = MealPhoto(data: try Task10JPEG.tagged()), gate = Task10Gate()
        var dependencies = Task10Fixture.dependencies(f.diary); dependencies.normalize = { bytes, _ in bytes }
        let requiredOwner = try #require(f.diary.selection)
        let draft = CoachAttachmentDraft(ownership: requiredOwner, limiter: f.diary.photoWorkLimiter,
            dependencies: dependencies, text: "Keep", attachments: [original])
        let presentation = try draft.beginPresentation()
        let retaking = Task10Fixture.operation(gate: gate) {
            try await draft.retake(original.id, selection: .init { await gate.hold(0); return original.data }, presentationID: presentation)
        }
        do {
            try await gate.waitForArrivals(1)
            if action == "remove" { try await draft.remove(original.id) }
            else if action == "close" { try await draft.endPresentation(presentation) }
            else { try await draft.cancelPendingImports() }
            await gate.releaseAll()
            _ = try? await retaking.value
            #expect(draft.attachments == (action == "remove" ? [] : [original]))
            #expect(draft.text == "Keep" && draft.reservedAttachmentCount == 0)
        } catch { await gate.releaseAll(); _ = try? await retaking.value; throw error }
    }

    @Test(arguments: ["ABA", "restore", "presentation"])
    func lateProfileRestoreOrPresentationResultIsDiscarded(change: String) async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let gate = Task10Gate(), bytes = try Task10JPEG.tagged(), owner = try #require(f.diary.selection)
        var dependencies = Task10Fixture.dependencies(f.diary); dependencies.normalize = { bytes, _ in bytes }
        let draft = CoachAttachmentDraft(ownership: owner, limiter: f.diary.photoWorkLimiter, dependencies: dependencies, text: "Old profile input")
        let presentation = try draft.beginPresentation()
        let importing = Task10Fixture.operation(gate: gate) {
            try await draft.importSelections([.init { await gate.hold(0); return bytes }], presentationID: presentation)
        }
        do {
            try await gate.waitForArrivals(1)
            if change == "presentation" {
                try await draft.endPresentation(presentation)
                _ = try draft.beginPresentation()
            } else { try await changeOwner(f, kind: change, original: owner) }
            await gate.releaseAll()
            _ = try? await importing.value
            #expect(draft.attachments.isEmpty && draft.reservedAttachmentCount == 0)
            #expect(draft.captureReceipt == nil)
            #expect(try await f.diary.store.snapshotForExport().coachTurns.isEmpty)
        } catch { await gate.releaseAll(); _ = try? await importing.value; throw error }
    }

    @Test
    func failedSaveRetainsDraftAndOperationIdentity() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        var dependencies = Task10Fixture.dependencies(f.diary)
        dependencies.capture = { _, _ in throw DiaryError.persistenceFailed }
        let photos = [MealPhoto(data: try Task10JPEG.tagged())]
        let requiredOwner = try #require(f.diary.selection)
        let draft = CoachAttachmentDraft(ownership: requiredOwner, limiter: f.diary.photoWorkLimiter,
            dependencies: dependencies, text: "Keep after failed save", attachments: photos)
        let id = draft.submissionID
        await #expect(throws: DiaryError.persistenceFailed) { _ = try await draft.send() }
        #expect(draft.text == "Keep after failed save" && draft.attachments == photos)
        #expect(draft.submissionID == id && draft.captureReceipt == nil)
        #expect(draft.uncertainAttempt?.payload.submissionID == id)
        let actual = try await f.diary.store.snapshotForExport()
        #expect(actual.meals.isEmpty)
        #expect(actual.coachTurns.isEmpty)
    }

    @Test func newCaptureDuringFailedFinalRefreshRunsWithoutRetryingExhaustedTurn() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let gate = Task10Gate(), once = Task10Once(), replies = Task8FailedHandoffReplies()
        let store = f.diary.store
        let diary = DiaryViewModel(store: store, actionReadModelLoading: { owner in
            if await replies.oldCalls == 4, await once.claim() { await gate.hold(0) }
            return try await store.diaryReadModel(expectedProfileID: owner)
        })
        await diary.load(createDefaultProfile: false)
        var dependencies = Task10Fixture.dependencies(diary)
        dependencies.refresh = { _ in }
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { input, _ in
            try await replies.respond(input)
        } }, sleep: { _ in }, attachmentDependencies: dependencies)
        defer { coach.cancel(); diary.enterBackground() }
        coach.draft.text = "Synthetic exhausted capture"
        let oldID = coach.draft.submissionID
        #expect(await coach.send())
        do {
            try await gate.waitForArrivals(1)
            #expect(await replies.oldCalls == 4)
            #expect(try await store.snapshotForExport().coachTurns.first { $0.id == oldID }?.state == .waitingForNetwork)
            coach.draft.text = "Synthetic fresh capture"
            let newID = coach.draft.submissionID
            #expect(await coach.send())
            #expect(coach.captureReceipt == newID)
            await gate.releaseAll()
            await coach.waitForWorker()
            #expect(await replies.oldCalls == 4)
            #expect(await replies.newCalls == 1)
            let stored = try await store.snapshotForExport()
            #expect(stored.coachTurns.count == 2)
            #expect(stored.coachTurns.first { $0.id == newID }?.state == .completed)
            #expect(stored.coachTurns.first { $0.id == oldID }?.state == .waitingForNetwork)
            coach.resume()
            await coach.waitForWorker()
            #expect(await replies.oldCalls == 8, "A later explicit resume retains the normal four-attempt recovery budget")
            #expect(await replies.newCalls == 1)
        } catch { await gate.releaseAll(); await coach.waitForWorker(); throw error }
    }

    @Test func newDiaryCaptureDuringFailedFinalRefreshRunsWithoutRetryingExhaustedTurn() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let gate = Task10Gate(), once = Task10Once(), replies = Task8FailedHandoffReplies()
        let store = f.diary.store
        let diary = DiaryViewModel(store: store, actionReadModelLoading: { owner in
            if await replies.oldCalls == 4, await once.claim() { await gate.hold(0) }
            return try await store.diaryReadModel(expectedProfileID: owner)
        })
        await diary.load(createDefaultProfile: false)
        var dependencies = Task10Fixture.dependencies(diary)
        dependencies.refresh = { _ in }
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { input, _ in
            try await replies.respond(input)
        } }, sleep: { _ in }, attachmentDependencies: dependencies)
        defer { coach.cancel(); diary.enterBackground() }
        diary.resumeCoach = { coach.resume() }
        let day = try await store.startDay()
        coach.draft.text = "Synthetic exhausted capture"
        let oldID = coach.draft.submissionID
        #expect(await coach.send())
        do {
            try await gate.waitForArrivals(1)
            #expect(await replies.oldCalls == 4)
            #expect(try await store.snapshotForExport().coachTurns.first { $0.id == oldID }?.state == .waitingForNetwork)
            var draft = MealDraft(); draft.text = "Synthetic fresh Diary capture"
            let newID = draft.submissionID
            #expect(await diary.capture(draft, dayID: day.id))
            #expect(diary.captureReceipt == newID && coach.captureReceipt == oldID)
            await gate.releaseAll()
            await coach.waitForWorker()
            #expect(await replies.oldCalls == 4)
            #expect(await replies.newCalls == 1)
            let stored = try await store.snapshotForExport()
            #expect(stored.coachTurns.count == 2)
            #expect(stored.coachTurns.first { $0.id == newID }?.state == .completed)
            #expect(stored.coachTurns.first { $0.id == oldID }?.state == .waitingForNetwork)
            coach.resume()
            await coach.waitForWorker()
            #expect(await replies.oldCalls == 8, "A later explicit resume retains the normal four-attempt recovery budget")
            #expect(await replies.newCalls == 1)
        } catch { await gate.releaseAll(); await coach.waitForWorker(); throw error }
    }

    @Test(arguments: ["failedSend", "recovery"])
    func failedNewSendOrRecoveryRetainsAcceptedCaptureWake(boundary: String) async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let initial = try await f.diary.store.diaryReadModel(expectedProfileID: f.diary.selection!.identity.profileID)
        let store = f.diary.store
        let diary = DiaryViewModel(store: store, actionReadModelLoading: { owner in
            if boundary == "recovery" { throw DiaryError.persistenceFailed }
            return try await store.diaryReadModel(expectedProfileID: owner)
        }, subscriberReadModelLoading: { _ in initial })
        await diary.load(createDefaultProfile: false)
        let once = Task10Once(), lease = Task8LeaseProbe(), inference = Task8InferenceProbe()
        var dependencies = Task10Fixture.dependencies(diary)
        let capture = dependencies.capture
        dependencies.capture = { payload, owner in
            guard await once.claim() else { throw DiaryError.persistenceFailed }
            return try await capture(payload, owner)
        }
        dependencies.refresh = { _ in throw DiaryError.persistenceFailed }
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in await inference.respond() } }, attachmentDependencies: dependencies)
        defer { coach.cancel(); diary.enterBackground() }
        coach.pauseForInactiveScene()
        let photo = try Task10JPEG.tagged()
        coach.draft = MealDraft(text: "Accepted input must retain its wake", photos: [photo])
        let accepted = coach.draft.submissionID
        #expect(await coach.send())
        if boundary == "failedSend" {
            coach.draft.text = "New input that fails persistence"
            #expect(!(await coach.send()))
            #expect(coach.draft.text == "New input that fails persistence")
        } else {
            coach.enterForeground()
            await coach.waitForWorker()
            coach.pauseForInactiveScene()
        }
        #expect(diary.workStatus.pendingTurnID == nil && (diary.readModel?.pendingCount ?? 0) == 0)
        coach.continueInBackground(begin: lease.begin, end: lease.end)
        #expect(lease.begun == 1)
        await coach.waitForBackgroundCompletion()
        #expect(lease.ended == 1)
        #expect(await inference.calls == (boundary == "failedSend" ? 1 : 0))
        let stored = try await store.snapshotForExport()
        #expect(stored.coachTurns.map(\.id) == [accepted] && stored.coachTurns[0].photos.map(\.data) == [photo])
    }

    @Test(arguments: ["other", "ABA"])
    func expiredLeaseCannotPauseChangedSelection(change: String) async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let original = f.diary.selection!.identity.profileID
        let other = DiaryProfile(name: "Other synthetic lease owner")
        _ = try await f.diary.store.createProfile(other)
        await f.diary.switchProfile(original)
        let oldOwner = f.diary.selection
        let gate = Task10Gate(), draining = Task10Gate(), lease = Task8LeaseProbe()
        let inference = Task8OwnerInference(gate: gate)
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection(), inference: { { _, _ in await inference.respond() } })
        defer { coach.cancel() }
        coach.draft.text = "Old owner operation"
        #expect(await coach.send())
        do {
            try await gate.waitForArrivals(1)
            coach.continueInBackground(begin: lease.begin, end: lease.end, onWorkerDrain: { Task { await draining.hold(0) } })
            try await draining.waitForArrivals(1)
            await draining.releaseAll()
            await f.diary.switchProfile(other.id)
            if change == "ABA" { await f.diary.switchProfile(original) }
            #expect(f.diary.selection != oldOwner)
            coach.draft.text = "New selection operation"
            let newID = coach.draft.submissionID
            #expect(await coach.send())
            let resumeNewOwner = Task { await coach.waitForWorker(); coach.resume(); await coach.waitForWorker() }
            lease.expire?()
            #expect(lease.ended == 1)
            await gate.releaseAll()
            await resumeNewOwner.value
            #expect(await inference.calls == (change == "ABA" ? 3 : 2))
            #expect(coach.captureReceipt == newID)
            let selected = try await f.diary.store.snapshotForExport()
            #expect(selected.coachTurns.first { $0.id == newID }?.state == .completed)
        } catch { await draining.releaseAll(); await gate.releaseAll(); await coach.waitForWorker(); throw error }
    }

    @Test(arguments: ["capture", "refresh"])
    func backgroundLeaseAdmitsInFlightSendAndDrainsItsWorker(boundary: String) async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let gate = Task10Gate(), analysis = Task10Gate(), lease = Task8LeaseProbe()
        var dependencies = Task10Fixture.dependencies(f.diary)
        let capture = dependencies.capture
        if boundary == "capture" { dependencies.capture = { payload, owner in await gate.hold(0); return try await capture(payload, owner) } }
        else { dependencies.refresh = { _ in await gate.hold(0) } }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection(), inference: { { _, _ in
            await analysis.hold(0)
            return CoachInferenceResult(model: "fixture", text: "Synthetic result", calls: [], outputItems: [])
        } }, attachmentDependencies: dependencies)
        defer { coach.cancel() }
        let photo = try Task10JPEG.tagged()
        coach.draft = MealDraft(text: "Pocket photo", photos: [photo])
        let id = coach.draft.submissionID
        let sending = Task10Fixture.operation(gate: gate) { await coach.send() }
        do {
            try await gate.waitForArrivals(1)
            if boundary == "refresh" { #expect(coach.captureReceipt == id) }
            coach.continueInBackground(begin: lease.begin, end: lease.end)
            #expect(lease.begun == 1 && lease.ended == 0)
            await gate.releaseAll()
            #expect(try await sending.value)
            try await analysis.waitForArrivals(1)
            #expect(lease.ended == 0)
            await analysis.releaseAll()
            await coach.waitForBackgroundCompletion()
            #expect(lease.ended == 1)
            let stored = try await f.diary.store.snapshotForExport()
            #expect(stored.coachTurns.map(\.id) == [id])
            #expect(stored.coachTurns[0].photos.map(\.data) == [photo])
        } catch { await gate.releaseAll(); await analysis.releaseAll(); _ = try? await sending.value; throw error }
    }

    @Test(arguments: [false, true])
    func leaseStartsCaptureAcceptedWhileSceneWasInactive(refreshFails: Bool) async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let refresh = Task10Gate(), lease = Task8LeaseProbe(), inference = Task8InferenceProbe()
        var dependencies = Task10Fixture.dependencies(f.diary)
        dependencies.refresh = { _ in
            if refreshFails { throw DiaryError.persistenceFailed }
            await refresh.hold(0)
        }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection(), inference: { { _, _ in
            await inference.respond()
        } }, attachmentDependencies: dependencies)
        defer { coach.cancel() }
        coach.draft.text = "Accepted during inactive transition"
        coach.pauseForInactiveScene()
        let sending = Task10Fixture.operation(gate: refresh) { await coach.send() }
        do {
            if refreshFails { #expect(try await sending.value) }
            else { try await refresh.waitForArrivals(1) }
            #expect(coach.captureReceipt != nil && !coach.isWorking)
            coach.continueInBackground(begin: lease.begin, end: lease.end)
            #expect(lease.begun == 1)
            await refresh.releaseAll()
            #expect(try await sending.value)
            await coach.waitForBackgroundCompletion()
            #expect(await inference.calls == 1)
            #expect(lease.ended == 1)
        } catch { await refresh.releaseAll(); _ = try? await sending.value; throw error }
    }

    @Test(arguments: ["denied", "expired"])
    func unavailableBackgroundLeasePreservesAuthorizedLocalCapture(outcome: String) async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let gate = Task10Gate(), lease = Task8LeaseProbe(allowed: outcome != "denied")
        var dependencies = Task10Fixture.dependencies(f.diary)
        let capture = dependencies.capture
        dependencies.capture = { payload, owner in await gate.hold(0); return try await capture(payload, owner) }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection(), inference: { { _, _ in
            Issue.record("Denied or expired background time must not launch inference")
            return CoachInferenceResult(model: "fixture", text: "Synthetic result", calls: [], outputItems: [])
        } }, attachmentDependencies: dependencies)
        defer { coach.cancel() }
        let photo = try Task10JPEG.tagged()
        coach.draft = MealDraft(text: "Save despite expired time", photos: [photo])
        let id = coach.draft.submissionID
        let sending = Task10Fixture.operation(gate: gate) { await coach.send() }
        do {
            try await gate.waitForArrivals(1)
            coach.continueInBackground(begin: lease.begin, end: lease.end)
            #expect(lease.begun == 1)
            if outcome == "expired" { lease.expire?() }
            await gate.releaseAll()
            #expect(try await sending.value)
            await coach.waitForBackgroundCompletion(); await coach.waitForWorker()
            #expect(coach.captureReceipt == id && coach.errorMessage == nil)
            #expect(lease.ended == (outcome == "expired" ? 1 : 0))
            let reopened = DiaryStore(directory: f.root)
            _ = try await reopened.selectProfile(f.diary.selection!.identity.profileID)
            #expect(try await reopened.snapshotForExport().coachTurns.map(\.id) == [id])
            #expect(try await reopened.snapshotForExport().coachTurns[0].photos.map(\.data) == [photo])
        } catch { await gate.releaseAll(); _ = try? await sending.value; throw error }
    }

    @Test func acceptedCaptureAcknowledgesSentAttemptWithoutClearingNewerDraft() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let gate = Task10Gate()
        var dependencies = Task10Fixture.dependencies(f.diary)
        let capture = dependencies.capture
        dependencies.capture = { payload, owner in await gate.hold(0); return try await capture(payload, owner) }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection(), attachmentDependencies: dependencies)
        coach.pauseForInactiveScene()
        let photo = try Task10JPEG.tagged()
        coach.draft = MealDraft(text: "Sent photo", photos: [photo])
        let id = coach.draft.submissionID
        let sending = Task10Fixture.operation(gate: gate) { await coach.send() }
        do {
            try await gate.waitForArrivals(1)
            coach.draft = MealDraft(text: "Newer unsent draft", photos: [photo + Data([0])])
            let newer = coach.draft
            await gate.releaseAll()
            #expect(try await sending.value)
            #expect(coach.captureReceipt == id && coach.companionCaptureEvent?.operationID == id)
            #expect(coach.draft == newer)
            let stored = try await f.diary.store.snapshotForExport()
            #expect(stored.coachTurns.map(\.id) == [id])
            #expect(stored.coachTurns[0].text == "Sent photo" && stored.coachTurns[0].photos.map(\.data) == [photo])
        } catch { await gate.releaseAll(); _ = try? await sending.value; throw error }
    }

    @Test func backgroundDrainDoesNotRestartExhaustedRetriesDuringLongRefresh() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let refresh = Task10Gate(), lease = Task8LeaseProbe(), inference = Task8RetryProbe()
        var dependencies = Task10Fixture.dependencies(f.diary)
        dependencies.refresh = { _ in await refresh.hold(0) }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection(), inference: { { _, _ in
            try await inference.respond()
        } }, sleep: { _ in }, attachmentDependencies: dependencies)
        defer { coach.cancel() }
        coach.draft.text = "Keep bounded retry budget"
        let sending = Task10Fixture.operation(gate: refresh) { await coach.send() }
        do {
            try await refresh.waitForArrivals(1)
            coach.continueInBackground(begin: lease.begin, end: lease.end)
            await coach.waitForWorker()
            #expect(await inference.calls == 4)
            await refresh.releaseAll()
            #expect(try await sending.value)
            await coach.waitForBackgroundCompletion()
            #expect(await inference.calls == 4)
            #expect(lease.ended == 1)
        } catch { await refresh.releaseAll(); _ = try? await sending.value; throw error }
    }

    @Test(arguments: ["expire", "foreground", "replacement"])
    func backgroundCallbacksCannotInvalidateSavedInputOrNewerLease(transition: String) async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let captureGate = Task10Gate(), analysis = Task10Gate(), first = Task8LeaseProbe(), second = Task8LeaseProbe()
        var dependencies = Task10Fixture.dependencies(f.diary)
        let capture = dependencies.capture
        dependencies.capture = { payload, owner in await captureGate.hold(0); return try await capture(payload, owner) }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection(), inference: { { _, _ in
            await analysis.hold(0)
            return CoachInferenceResult(model: "fixture", text: "Synthetic result", calls: [], outputItems: [])
        } }, attachmentDependencies: dependencies)
        defer { coach.cancel() }
        let photo = try Task10JPEG.tagged()
        coach.draft = MealDraft(text: "Keep accepted input", photos: [photo])
        let id = coach.draft.submissionID
        let sending = Task10Fixture.operation(gate: captureGate) { await coach.send() }
        do {
            try await captureGate.waitForArrivals(1)
            coach.continueInBackground(begin: first.begin, end: first.end)
            let staleExpiration = first.expire
            if transition != "expire" {
                coach.endBackgroundLease()
                if transition == "foreground" { coach.enterForeground() }
                else { coach.continueInBackground(begin: second.begin, end: second.end) }
                staleExpiration?()
                #expect(first.ended == 1 && second.ended == 0)
            }
            await captureGate.releaseAll()
            #expect(try await sending.value)
            try await analysis.waitForArrivals(1)
            if transition == "expire" { first.expire?(); #expect(first.ended == 1) }
            if transition == "replacement" { #expect(second.ended == 0) }
            await analysis.releaseAll()
            await coach.waitForBackgroundCompletion(); await coach.waitForWorker()
            #expect(coach.captureReceipt == id)
            if transition == "replacement" { #expect(second.ended == 1) }
            let stored = try await f.diary.store.snapshotForExport()
            #expect(stored.coachTurns.map(\.id) == [id] && stored.coachTurns[0].photos.map(\.data) == [photo])
            if transition == "expire" { #expect(stored.coachTurns[0].state != .completed) }
        } catch {
            await captureGate.releaseAll(); await analysis.releaseAll(); _ = try? await sending.value; throw error }
    }

    @Test(arguments: [false, true])
    func committedPhotoAcknowledgesDespiteRefreshFailure(reconciled: Bool) async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        var dependencies = Task10Fixture.dependencies(f.diary)
        let once = Task10Once(), capture = dependencies.capture
        dependencies.capture = { payload, owner in
            let result = try await capture(payload, owner)
            if reconciled, await once.claim() { throw DiaryError.persistenceFailed }
            return result
        }
        dependencies.refresh = { _ in throw DiaryError.persistenceFailed }
        let photo = MealPhoto(data: try Task10JPEG.tagged())
        let draft = CoachAttachmentDraft(ownership: f.diary.selection, limiter: f.diary.photoWorkLimiter,
            dependencies: dependencies, text: "Durable photo", attachments: [photo])
        let id = draft.submissionID
        if reconciled {
            await #expect(throws: DiaryError.persistenceFailed) { _ = try await draft.send() }
            #expect(draft.captureReceipt == nil && draft.uncertainAttempt != nil)
        }
        #expect(try await draft.send()?.id == id)
        #expect(draft.captureReceipt == id && draft.text.isEmpty && draft.attachments.isEmpty)
        #expect(draft.uncertainAttempt == nil)
        let stored = try await f.diary.store.snapshotForExport()
        #expect(stored.coachTurns.map(\.id) == [id] && stored.coachTurns[0].photos == [photo])
    }

    @Test func uncertainSaveThenEditedDraftReconcilesBeforeNewSubmission() async throws {
        let once = Task10Once(), trace = Task10SubmissionTrace()
        let f = try await Task10Fixture.make(); defer { f.remove() }
        var dependencies = Task10Fixture.dependencies(f.diary)
        dependencies.normalize = { bytes, _ in bytes }
        let capture = dependencies.capture, reconcile = dependencies.reconcile
        dependencies.capture = { payload, owner in
            await trace.capture(payload)
            let result = try await capture(payload, owner)
            if await once.claim() { throw DiaryError.persistenceFailed }
            return result
        }
        dependencies.reconcile = { id, manifest, owner in await trace.reconcile(id, manifest); return try await reconcile(id, manifest, owner) }
        let originalPhoto = MealPhoto(data: try Task10JPEG.tagged(), createdAt: Date(timeIntervalSinceReferenceDate: 700), role: .before)
        let requiredOwner = try #require(f.diary.selection)
        let draft = CoachAttachmentDraft(ownership: requiredOwner, limiter: f.diary.photoWorkLimiter,
            dependencies: dependencies, text: "Original accepted input", attachments: [originalPhoto])
        let originalID = draft.submissionID
        await #expect(throws: DiaryError.persistenceFailed) { _ = try await draft.send() }
        let originalManifest = try #require(draft.uncertainAttempt?.payload.manifest)
        draft.text = "Edited new input"
        var replacement = originalPhoto.data; replacement.append(0)
        let editedBytes = replacement
        try await draft.retake(originalPhoto.id, selection: .init { editedBytes })
        #expect(draft.uncertainAttempt?.payload.manifest == originalManifest)
        let result = try #require(try await draft.send())
        #expect(result.id != originalID && draft.captureReceipt == result.id)
        let stored = try await f.diary.store.snapshotForExport()
        #expect(stored.coachTurns.count == 2 && stored.meals.isEmpty)
        let original = try #require(stored.coachTurns.first { $0.id == originalID })
        let edited = try #require(stored.coachTurns.first { $0.id == result.id })
        #expect(original.text == "Original accepted input" && original.photos == [originalPhoto])
        #expect(original.submissionManifest == originalManifest)
        #expect(edited.text == "Edited new input" && edited.photos.map(\.id) == [originalPhoto.id])
        #expect(edited.photos[0].data == editedBytes)
        #expect(await trace.events == [.capture(originalID), .reconcile(originalID), .capture(result.id)])
        #expect(await trace.reconciledManifests == [originalManifest])
        #expect(draft.text.isEmpty && draft.attachments.isEmpty)
    }

    @Test(arguments: ["failure", "conflict"])
    func unresolvedOriginalAttemptCannotMintEditedSubmission(outcome: String) async throws {
        let trace = Task10SubmissionTrace()
        let f = try await Task10Fixture.make(); defer { f.remove() }
        var dependencies = Task10Fixture.dependencies(f.diary)
        let capture = dependencies.capture
        dependencies.capture = { payload, owner in
            await trace.capture(payload)
            if outcome == "conflict" {
                let different = try CoachSubmissionPayload(submissionID: payload.submissionID, text: "Already accepted different input",
                    attachments: payload.attachments, context: payload.context)
                _ = try await capture(different, owner)
                throw DiaryError.persistenceFailed
            }
            _ = try await capture(payload, owner)
            throw DiaryError.persistenceFailed
        }
        if outcome == "failure" { dependencies.reconcile = { _, _, _ in throw DiaryError.persistenceFailed } }
        let requiredOwner = try #require(f.diary.selection)
        let draft = CoachAttachmentDraft(ownership: requiredOwner, limiter: f.diary.photoWorkLimiter,
            dependencies: dependencies, text: "Original")
        let id = draft.submissionID
        await #expect(throws: DiaryError.persistenceFailed) { _ = try await draft.send() }
        let manifest = try #require(draft.uncertainAttempt?.payload.manifest)
        draft.text = "Edited while uncertain"
        do { _ = try await draft.send(); Issue.record("Unresolved original cannot acknowledge edited input") } catch { }
        #expect(draft.submissionID == id && draft.text == "Edited while uncertain")
        #expect(draft.uncertainAttempt?.payload.manifest == manifest && draft.captureReceipt == nil)
        #expect(await trace.events == [.capture(id)])
        let stored = try await f.diary.store.snapshotForExport()
        #expect(stored.coachTurns.map(\.text) == [outcome == "conflict" ? "Already accepted different input" : "Original"])
    }

    @Test func absentOriginalIsReconciledBeforeEditedPayloadGetsNewIdentity() async throws {
        let once = Task10Once(), trace = Task10SubmissionTrace()
        let f = try await Task10Fixture.make(); defer { f.remove() }
        var dependencies = Task10Fixture.dependencies(f.diary)
        let capture = dependencies.capture, reconcile = dependencies.reconcile
        dependencies.capture = { payload, owner in
            await trace.capture(payload)
            if await once.claim() { throw DiaryError.persistenceFailed }
            return try await capture(payload, owner)
        }
        dependencies.reconcile = { id, manifest, owner in await trace.reconcile(id, manifest); return try await reconcile(id, manifest, owner) }
        let requiredOwner = try #require(f.diary.selection)
        let draft = CoachAttachmentDraft(ownership: requiredOwner, limiter: f.diary.photoWorkLimiter,
            dependencies: dependencies, text: "Never committed")
        let id = draft.submissionID
        await #expect(throws: DiaryError.persistenceFailed) { _ = try await draft.send() }
        draft.text = "Intentional edit"
        let accepted = try #require(try await draft.send())
        #expect(accepted.id != id)
        #expect(await trace.events == [.capture(id), .reconcile(id), .capture(accepted.id)])
        #expect(try await f.diary.store.snapshotForExport().coachTurns.map(\.text) == ["Intentional edit"])
    }

    @Test func uneditedRetryPreservesFrozenContextAttachmentIDsAndSubmissionID() async throws {
        let once = Task10Once(), trace = Task10SubmissionTrace()
        let f = try await Task10Fixture.make(); defer { f.remove() }
        var dependencies = Task10Fixture.dependencies(f.diary)
        let capture = dependencies.capture
        dependencies.capture = { payload, owner in
            await trace.capture(payload)
            if await once.claim() { throw DiaryError.persistenceFailed }
            return try await capture(payload, owner)
        }
        let photo = MealPhoto(data: try Task10JPEG.tagged())
        let requiredOwner = try #require(f.diary.selection)
        let draft = CoachAttachmentDraft(ownership: requiredOwner, limiter: f.diary.photoWorkLimiter,
            dependencies: dependencies, text: "Exact retry", attachments: [photo])
        let id = draft.submissionID
        await #expect(throws: DiaryError.persistenceFailed) { _ = try await draft.send() }
        let manifest = try #require(draft.uncertainAttempt?.payload.manifest)
        let accepted = try #require(try await draft.send())
        #expect(accepted.id == id)
        #expect(await trace.capturedManifests == [manifest, manifest])
        let actual = try await f.diary.store.snapshotForExport()
        #expect(actual.coachTurns.count == 1 && actual.coachTurns[0].photos == [photo])
        #expect(actual.coachTurns[0].submissionManifest == manifest)
    }

    @Test func actualCoachSendAcknowledgesCommittedOriginalDespiteRefreshFailure() async throws {
        let once = Task10Once()
        let f = try await Task10Fixture.make(actionLoading: { owner, store in
            let result = try await store.diaryReadModel(expectedProfileID: owner)
            if await once.claim() { throw DiaryError.persistenceFailed }; return result
        }); defer { f.remove() }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection())
        defer { coach.cancel() }
        coach.draft.text = "Actual original"
        let id = coach.draft.submissionID
        #expect(await coach.send())
        #expect(coach.captureReceipt == id && coach.draft.text.isEmpty && coach.errorMessage == nil)
        let first = try await f.diary.store.snapshotForExport()
        #expect(first.coachTurns.map(\.text) == ["Actual original"])
        coach.draft.text = "Actual edited input"
        #expect(await coach.send())
        await coach.waitForWorker()
        let stored = try await f.diary.store.snapshotForExport()
        #expect(stored.coachTurns.count == 2 && stored.meals.isEmpty)
        #expect(stored.coachTurns.first { $0.id == id }?.text == "Actual original")
        #expect(stored.coachTurns.contains { $0.id != id && $0.text == "Actual edited input" })
        #expect(coach.draft.text.isEmpty)
    }

    @Test func relaunchLosesUnsentDraftButRecoversAcceptedSubmission() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let owner = try #require(f.diary.selection)
        let unsent = CoachAttachmentDraft(ownership: owner, limiter: f.diary.photoWorkLimiter,
            dependencies: Task10Fixture.dependencies(f.diary), text: "Do not persist unsent")
        let acceptedDraft = CoachAttachmentDraft(ownership: owner, limiter: f.diary.photoWorkLimiter,
            dependencies: Task10Fixture.dependencies(f.diary), text: "Durable accepted input", attachments: [MealPhoto(data: try Task10JPEG.tagged())])
        let accepted = try #require(try await acceptedDraft.send())
        let reopened = DiaryStore(directory: f.root)
        _ = try await reopened.selectProfile(owner.identity.profileID)
        let newOwner = try await reopened.selectionOwnership(expectedProfileID: owner.identity.profileID)
        let relaunchedDraft = CoachAttachmentDraft(ownership: newOwner, limiter: PhotoWorkLimiter(),
            dependencies: .init(store: reopened))
        #expect(relaunchedDraft.text.isEmpty && relaunchedDraft.attachments.isEmpty)
        #expect(relaunchedDraft.uncertainAttempt == nil)
        let recoverable = try await reopened.nextCoachResult(includeWaitingForConnection: true, expectedProfileID: owner.identity.profileID)
        #expect(recoverable?.id == accepted.id)
        let stored = try await reopened.snapshotForExport()
        #expect(stored.coachTurns.map(\.id) == [accepted.id])
        #expect(!stored.coachTurns.contains { $0.id == unsent.submissionID })
    }

    @Test(arguments: ["ABA", "restore"], ["capture", "captureAcknowledgement", "reconcile", "reconcileAcknowledgement"])
    func storeEntryRejectsObsoleteDraftOwnership(change: String, boundary: String) async throws {
        let once = Task10Once(), gate = Task10Gate()
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let owner = try #require(f.diary.selection)
        var dependencies = Task10Fixture.dependencies(f.diary)
        let capture = dependencies.capture, reconcile = dependencies.reconcile
        if boundary.hasPrefix("reconcile") {
            dependencies.capture = { payload, owner in
                let result = try await capture(payload, owner)
                if await once.claim() { throw DiaryError.persistenceFailed }
                return result
            }
        }
        if boundary == "capture" { dependencies.capture = { payload, owner in await gate.hold(0); return try await capture(payload, owner) } }
        else if boundary == "captureAcknowledgement" { dependencies.capture = { payload, owner in let result = try await capture(payload, owner); await gate.hold(0); return result } }
        else if boundary == "reconcile" { dependencies.reconcile = { id, manifest, owner in await gate.hold(0); return try await reconcile(id, manifest, owner) } }
        else { dependencies.reconcile = { id, manifest, owner in let result = try await reconcile(id, manifest, owner); await gate.hold(0); return result } }
        let draft = CoachAttachmentDraft(ownership: owner, limiter: f.diary.photoWorkLimiter, dependencies: dependencies, text: "Old selection")
        let id = draft.submissionID
        if boundary.hasPrefix("reconcile") {
            await #expect(throws: DiaryError.persistenceFailed) { _ = try await draft.send() }
            draft.text = "Old selection edited"
        }
        let sending = Task10Fixture.operation(gate: gate) { try await draft.send() }
        do {
            try await gate.waitForArrivals(1)
            try await changeOwner(f, kind: change, original: owner)
            let before = try await f.diary.store.snapshotForExport()
            await gate.releaseAll()
            await #expect(throws: DiaryError.wrongOwner) { _ = try await sending.value }
            #expect(try await f.diary.store.snapshotForExport() == before)
            #expect(draft.submissionID == id && draft.captureReceipt == nil)
            #expect(!draft.text.isEmpty)
        } catch { await gate.releaseAll(); _ = try? await sending.value; throw error }
    }

    @Test func editingWhileAcceptedCaptureAwaitsRefreshDoesNotClearCurrentDraft() async throws {
        let gate = Task10Gate()
        let f = try await Task10Fixture.make(actionLoading: { owner, store in
            let result = try await store.diaryReadModel(expectedProfileID: owner); await gate.hold(0); return result
        }); defer { f.remove() }
        let photo = MealPhoto(data: try Task10JPEG.tagged())
        let requiredOwner = try #require(f.diary.selection)
        let draft = CoachAttachmentDraft(ownership: requiredOwner, limiter: f.diary.photoWorkLimiter,
            dependencies: Task10Fixture.dependencies(f.diary), text: "Pressed send", attachments: [photo])
        let id = draft.submissionID
        let sending = Task10Fixture.operation(gate: gate) { try await draft.send() }
        do {
            try await gate.waitForArrivals(1)
            #expect(draft.captureReceipt == id)
            #expect(draft.text.isEmpty && draft.attachments.isEmpty)
            draft.text = "Edited during acknowledgement"
            await gate.releaseAll(); _ = try await sending.value
            #expect(draft.text == "Edited during acknowledgement" && draft.attachments.isEmpty)
            #expect(draft.captureReceipt == id)
            let stored = try await f.diary.store.snapshotForExport()
            #expect(stored.coachTurns.map(\.id) == [id])
            #expect(stored.coachTurns[0].text == "Pressed send" && stored.coachTurns[0].photos == [photo])
        } catch { await gate.releaseAll(); _ = try? await sending.value; throw error }
    }

    @Test func oversizeTransferAndNormalizationFailurePublishNoAttachment() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let photo = MealPhoto(data: try Task10JPEG.tagged())
        let requiredOwner = try #require(f.diary.selection)
        let draft = CoachAttachmentDraft(ownership: requiredOwner, limiter: f.diary.photoWorkLimiter,
            dependencies: Task10Fixture.dependencies(f.diary), text: "Retain text", attachments: [photo])
        let id = draft.submissionID
        let oversize = CoachAttachmentDraft.Selection { Data(repeating: 0, count: 40_000_001) }
        let corrupt = CoachAttachmentDraft.Selection { Data([1, 2, 3]) }
        let failures = try await draft.importSelections([oversize, corrupt])
        #expect(Set(failures) == Set([oversize.id, corrupt.id]))
        #expect(draft.attachments == [photo] && draft.text == "Retain text")
        #expect(draft.submissionID == id && draft.reservedAttachmentCount == 0 && draft.captureReceipt == nil)
        #expect(try await f.diary.store.snapshotForExport().coachTurns.isEmpty)
    }

    @Test func sourcePhotoQuotaFailurePreservesDraftAndDurableFacts() async throws {
        let fixture = try CaptureFixture(exchanges: 0); defer { fixture.remove() }
        let store = DiaryStore(directory: fixture.root)
        _ = try await store.selectProfile(fixture.profileID)
        let diary = DiaryViewModel(store: store); await diary.load(createDefaultProfile: false)
        // Seed only the authoritative quota scalar; no 250 MB allocation or raised product limit.
        try fixture.execute("UPDATE storage_quota SET originalPhotoBytes = 250000000")
        let before = try fixture.durableState(), photo = MealPhoto(data: try Task10JPEG.tagged())
        let requiredOwner = try #require(diary.selection)
        let draft = CoachAttachmentDraft(ownership: requiredOwner, limiter: diary.photoWorkLimiter,
            dependencies: Task10Fixture.dependencies(diary), text: "Quota must not lose this", attachments: [photo])
        let id = draft.submissionID
        await #expect(throws: DiaryError.invalidData) { _ = try await draft.send() }
        #expect(try fixture.durableState() == before)
        #expect(draft.attachments == [photo] && draft.text == "Quota must not lose this")
        #expect(draft.submissionID == id && draft.captureReceipt == nil)
    }

    @Test func cancelledSynchronousNormalizationKeepsSharedPermitUntilItExits() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let stage = Task10SynchronousStage(), holderGate = Task10Gate(), bytes = try Task10JPEG.tagged()
        let statistics = AsyncStream<PhotoWorkLimiter.Statistics>.makeStream()
        let limiter = PhotoWorkLimiter(observe: { statistics.continuation.yield($0) })
        // This injected application instance is shared with its real photo loader and both drafts.
        let diary = DiaryViewModel(store: f.diary.store, photoWorkLimiter: limiter); await diary.load(createDefaultProfile: false)
        var dependencies = Task10Fixture.dependencies(diary)
        dependencies.normalize = { data, _ in
            try await withTaskCancellationHandler { try stage.run(data) } onCancel: { stage.cancelled.continuation.yield(()) }
        }
        let requiredOwner = try #require(diary.selection)
        let first = CoachAttachmentDraft(ownership: requiredOwner, limiter: diary.photoWorkLimiter, dependencies: dependencies)
        let second = CoachAttachmentDraft(ownership: requiredOwner, limiter: diary.photoWorkLimiter,
            dependencies: Task10Fixture.dependencies(diary))
        let importing = Task { do { let result = try await first.importSelections([.init { bytes }]); stage.entered.continuation.finish(); return result }
            catch { stage.entered.continuation.finish(); throw error } }
        var holder: Task<Void, Error>?, queued: Task<[UUID], Error>?
        do {
            var entered = false
            for await _ in stage.entered.stream { entered = true; break }
            try #require(entered)
            holder = Task10Fixture.operation(gate: holderGate) { try await limiter.withPermit { await holderGate.hold(0) } }
            try await holderGate.waitForArrivals(1)
            queued = Task { do { let result = try await second.importSelections([.init { bytes }]); statistics.continuation.finish(); return result }
                catch { statistics.continuation.finish(); throw error } }
            var sawQueued = false
            for await state in statistics.stream where state.queued == 1 { sawQueued = true; break }
            try #require(sawQueued)
            importing.cancel()
            for await _ in stage.cancelled.stream { break }
            let held = await limiter.statistics()
            #expect(held.active == 2 && held.queued == 1 && held.peakActive == 2)
            #expect(second.attachments.isEmpty)
            stage.release()
            _ = try? await importing.value
            _ = try await queued?.value
            await holderGate.releaseAll(); _ = try await holder?.value
            #expect(first.attachments.isEmpty && first.reservedAttachmentCount == 0)
            #expect(second.attachments.count == 1)
            #expect(await limiter.statistics().peakActive == 2)
        } catch {
            stage.release(); await holderGate.releaseAll(); importing.cancel(); queued?.cancel(); holder?.cancel()
            _ = try? await importing.value; _ = try? await queued?.value; _ = try? await holder?.value
            throw error
        }
    }

    private func changeOwner(_ f: Task10Fixture, kind: String, original: DiarySelectionOwnership) async throws {
        if kind == "ABA" {
            _ = try await f.diary.store.createProfile(DiaryProfile(name: "Other synthetic profile"))
            _ = try await f.diary.store.selectProfile(original.identity.profileID)
        } else {
            let archive = try await f.diary.store.snapshotForExport()
            try await f.diary.store.restore(archive, expectedProfileID: original.identity.profileID)
        }
        #expect(try await f.diary.store.selectionOwnership(expectedProfileID: original.identity.profileID) != original)
    }
}

private actor Task10SubmissionTrace {
    enum Event: Equatable, Sendable { case capture(UUID), reconcile(UUID) }
    private(set) var events: [Event] = []
    private(set) var capturedManifests: [CoachSubmissionManifest] = []
    private(set) var reconciledManifests: [CoachSubmissionManifest] = []
    func capture(_ payload: CoachSubmissionPayload) { events.append(.capture(payload.submissionID)); capturedManifests.append(payload.manifest) }
    func reconcile(_ id: UUID, _ manifest: CoachSubmissionManifest) { events.append(.reconcile(id)); reconciledManifests.append(manifest) }
}

private final class Task10SynchronousStage: Sendable {
    let entered = AsyncStream<Void>.makeStream()
    let cancelled = AsyncStream<Void>.makeStream()
    private let semaphore = DispatchSemaphore(value: 0)
    func run(_ data: Data) throws -> Data {
        #expect(!Thread.isMainThread)
        entered.continuation.yield(())
        guard semaphore.wait(timeout: .now() + 10) == .success else {
            Issue.record("Synchronous normalization fixture exceeded ten seconds")
            throw DiaryError.persistenceFailed
        }
        return data
    }
    func release() { semaphore.signal() }
}

@MainActor private final class Task8LeaseProbe {
    let allowed: Bool
    var begun = 0
    var ended = 0
    var expire: (@MainActor () -> Void)?
    init(allowed: Bool = true) { self.allowed = allowed }
    func begin(_ expire: @escaping @MainActor () -> Void) -> Bool { begun += 1; self.expire = expire; return allowed }
    func end() { ended += 1 }
}

private actor Task8InferenceProbe {
    private(set) var calls = 0
    func respond() -> CoachInferenceResult {
        calls += 1
        return CoachInferenceResult(model: "fixture", text: "Synthetic result", calls: [], outputItems: [])
    }
}

private actor Task8RetryProbe {
    private(set) var calls = 0
    func respond() throws -> CoachInferenceResult {
        calls += 1
        throw URLError(.notConnectedToInternet)
    }
}

private actor Task8OwnerInference {
    let gate: Task10Gate
    private(set) var calls = 0
    init(gate: Task10Gate) { self.gate = gate }
    func respond() async -> CoachInferenceResult {
        calls += 1
        if calls == 1 { await gate.hold(0) }
        return CoachInferenceResult(model: "fixture", text: "Synthetic result", calls: [], outputItems: [])
    }
}

private actor Task8FailedHandoffReplies {
    private(set) var oldCalls = 0
    private(set) var newCalls = 0
    func respond(_ input: [CoachInferenceInput]) throws -> CoachInferenceResult {
        if input.contains(where: {
            if case .message(role: .user, text: "Synthetic exhausted capture", images: _) = $0 { return true }
            return false
        }) {
            oldCalls += 1
            throw URLError(.notConnectedToInternet)
        }
        newCalls += 1
        return CoachInferenceResult(model: "fixture", text: "Synthetic result", calls: [], outputItems: [])
    }
}
