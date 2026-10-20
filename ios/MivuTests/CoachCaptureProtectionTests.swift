import Foundation
import Testing
import UIKit
@testable import Mivu

@Suite @MainActor struct CoachCaptureProtectionTests {
    // Missing acquisition before the first preparation await leaves local Send unprotected.
    @Test(arguments: ["prepare", "capture", "refresh"])
    func admittedSendProtectsEveryCaptureBoundary(boundary: String) async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let gate = Task10Gate(), protection = Task9ProtectionProbe()
        var dependencies = Task10Fixture.dependencies(f.diary)
        let prepare = dependencies.prepare, capture = dependencies.capture, refresh = dependencies.refresh
        if boundary == "prepare" { dependencies.prepare = { manifest, owner in await gate.hold(0); return try await prepare(manifest, owner) } }
        if boundary == "capture" { dependencies.capture = { payload, owner in await gate.hold(0); return try await capture(payload, owner) } }
        if boundary == "refresh" { dependencies.refresh = { owner in await gate.hold(0); try await refresh(owner) } }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection(), attachmentDependencies: dependencies, beginCaptureProtection: protection.begin)
        defer { coach.cancel() }
        coach.pauseForInactiveScene()
        #expect(!(await coach.send()))
        #expect(protection.begun == 0)
        coach.draft.text = "Protected local Send"
        let id = coach.draft.submissionID
        let sending = Task10Fixture.operation(gate: gate) { await coach.send() }
        do {
            try await gate.waitForArrivals(1)
            #expect(protection.begun == 1 && protection.ended == 0)
            #expect(!(await coach.send()))
            #expect(protection.begun == 1)
            sending.cancel()
            #expect(protection.ended == 0)
            await gate.releaseAll()
            #expect(try await sending.value)
            #expect(protection.ended == 1)
            #expect(coach.captureReceipt == id && coach.errorMessage == nil)
            #expect(try await f.diary.store.snapshotForExport().coachTurns.map(\.id) == [id])
        } catch { await gate.releaseAll(); _ = try? await sending.value; throw error }
    }

    // Every admitted exit must release capture protection, including failed writes and ownership loss.
    @Test(arguments: ["writeFailure", "wrongOwner"])
    func unsuccessfulSendReleasesProtection(outcome: String) async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let gate = Task10Gate(), protection = Task9ProtectionProbe()
        var dependencies = Task10Fixture.dependencies(f.diary)
        let capture = dependencies.capture
        dependencies.capture = { payload, owner in
            await gate.hold(0)
            if outcome == "writeFailure" { throw DiaryError.persistenceFailed }
            return try await capture(payload, owner)
        }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection(), attachmentDependencies: dependencies, beginCaptureProtection: protection.begin)
        defer { coach.cancel() }
        coach.pauseForInactiveScene()
        coach.draft.text = "Keep failed input"
        let sending = Task10Fixture.operation(gate: gate) { await coach.send() }
        do {
            try await gate.waitForArrivals(1)
            #expect(protection.begun == 1 && protection.ended == 0)
            if outcome == "wrongOwner" { _ = try await f.diary.store.createProfile(DiaryProfile(name: "Other owner", timeZoneID: "UTC")) }
            await gate.releaseAll()
            #expect(!(try await sending.value))
            #expect(protection.ended == 1)
            #expect(coach.captureReceipt == nil)
        } catch { await gate.releaseAll(); _ = try? await sending.value; throw error }
    }

    // Expiring capture runtime must never cancel an admitted durable write or alter saving state.
    @Test(arguments: ["denied", "expired", "synchronousExpiry"])
    func unavailableCaptureProtectionStillSaves(outcome: String) async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let gate = Task10Gate()
        var expiration: (@MainActor () -> Void)?
        var ended: [UIBackgroundTaskIdentifier] = []
        let id = UIBackgroundTaskIdentifier(rawValue: 49)
        var dependencies = Task10Fixture.dependencies(f.diary)
        let capture = dependencies.capture
        dependencies.capture = { payload, owner in await gate.hold(0); return try await capture(payload, owner) }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection(), attachmentDependencies: dependencies, beginCaptureProtection: {
            CoachCaptureProtection.begin(begin: { expire in
                expiration = expire
                if outcome == "synchronousExpiry" { expire() }
                return outcome == "denied" ? .invalid : id
            }, end: { ended.append($0) })
        })
        defer { coach.cancel() }
        coach.pauseForInactiveScene()
        coach.draft.text = "Save when runtime is unavailable"
        let submissionID = coach.draft.submissionID
        let sending = Task10Fixture.operation(gate: gate) { await coach.send() }
        do {
            try await gate.waitForArrivals(1)
            if outcome == "expired" { expiration?() }
            #expect(coach.isSending && f.diary.isSaving && !coach.isWorking)
            #expect(ended == (outcome == "denied" ? [] : [id]))
            await gate.releaseAll()
            #expect(try await sending.value)
            #expect(coach.captureReceipt == submissionID && coach.errorMessage == nil)
            #expect(ended == (outcome == "denied" ? [] : [id]))
            #expect(try await f.diary.store.snapshotForExport().coachTurns.map(\.id) == [submissionID])
        } catch { await gate.releaseAll(); _ = try? await sending.value; throw error }
    }

    // Native denial must be harmless; expiration and cleanup must end each granted identifier once.
    @Test(arguments: ["granted", "denied", "expired", "synchronousExpiry"])
    func nativeAssertionBalancesExactlyOnce(outcome: String) {
        var expiration: (@MainActor () -> Void)?
        var ended: [UIBackgroundTaskIdentifier] = []
        let id = UIBackgroundTaskIdentifier(rawValue: 37)
        let cleanup = CoachCaptureProtection.begin(begin: { expire in
            expiration = expire
            if outcome == "synchronousExpiry" { expire() }
            return outcome == "denied" ? .invalid : id
        }, end: { ended.append($0) })
        #expect(ended == (outcome == "synchronousExpiry" ? [id] : []))
        if outcome == "expired" || outcome == "synchronousExpiry" { expiration?(); expiration?() }
        if outcome == "expired" { #expect(ended == [id]) }
        cleanup(); cleanup(); expiration?()
        #expect(ended == (outcome == "denied" ? [] : [id]))
    }
}

@MainActor private final class Task9ProtectionProbe {
    var begun = 0
    var ended = 0
    func begin() -> @MainActor () -> Void {
        begun += 1
        return { self.ended += 1 }
    }
}
