import Foundation
import Testing
@testable import Mivu

@Suite struct AdultEligibilityTests {
    private func store() -> DiaryStore {
        DiaryStore(directory: URL.temporaryDirectory.appending(path: "AdultEligibility-" + UUID().uuidString))
    }

    @Test func legacyProfileCannotCaptureBeforeConfirmation() async throws {
        let store = store(), profile = DiaryProfile(name: "Synthetic legacy adult")
        _ = try await store.createProfile(profile)
        await #expect(throws: DiaryError.self) { try await store.startDay(expectedProfileID: profile.id) }
        #expect(try await store.diaryReadModel(expectedProfileID: profile.id).profile == profile)
        #expect(try await store.snapshotForExport(expectedProfileID: profile.id).profile == profile)
    }

    @Test func knownMinorCannotChangeGoals() async throws {
        let store = store()
        var profile = DiaryProfile(name: "Synthetic minor")
        profile.about = ProfileAbout(heightCm: 150, birthYear: 2013)
        _ = try await store.createProfile(profile)
        let goal = GoalRecord(effectiveLocalDate: "2026-10-26", timeZoneID: profile.timeZoneID, targets: NutritionValues(kcal: 1200), exerciseCreditEnabled: false)
        await #expect(throws: DiaryError.self) { try await store.setGoals(goal, expectedRevision: nil, expectedProfileID: profile.id) }
    }
    @Test func attestationAndBirthYearMustBothAllowAdultUse() {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        var profile = DiaryProfile(name: "Synthetic")
        #expect(!AdultEligibility.isEligible(profile, at: now))
        profile.adultConfirmed = true
        #expect(AdultEligibility.isEligible(profile, at: now))
        profile.about = ProfileAbout(heightCm: 170, birthYear: 2008)
        #expect(AdultEligibility.isEligible(profile, at: now))
        profile.about?.birthYear = 2009
        #expect(!AdultEligibility.isEligible(profile, at: now))
        profile.about?.birthYear = 2027
        #expect(!AdultEligibility.isEligible(profile, at: now))
    }

    @Test func confirmationIsPerProfileAndRejectsKnownMinors() async throws {
        let store = store(), first = DiaryProfile(name: "Synthetic first"), second = DiaryProfile(name: "Synthetic second")
        _ = try await store.createProfile(first)
        try await store.confirmAdultEligibility(expectedProfileID: first.id)
        try await store.requireAdultEligibility(expectedProfileID: first.id)
        _ = try await store.createProfile(second)
        await #expect(throws: DiaryError.adultConfirmationRequired) { try await store.requireAdultEligibility(expectedProfileID: second.id) }
        var minor = DiaryProfile(name: "Synthetic minor")
        minor.about = ProfileAbout(heightCm: 150, birthYear: 2013)
        _ = try await store.createProfile(minor)
        await #expect(throws: DiaryError.adultConfirmationRequired) { try await store.confirmAdultEligibility(expectedProfileID: minor.id) }
    }

    @Test func portableImportDoesNotTrustAdultConfirmation() async throws {
        let store = store()
        var profile = DiaryProfile(name: "Synthetic imported adult")
        profile.adultConfirmed = true
        let imported = try await store.importProfile(DiarySnapshot(profile: profile))
        #expect(imported.profile.adultConfirmed == nil)
        await #expect(throws: DiaryError.adultConfirmationRequired) { try await store.requireAdultEligibility(expectedProfileID: profile.id) }
        try await store.confirmAdultEligibility(expectedProfileID: profile.id)
        _ = try await store.startDay(expectedProfileID: profile.id)
    }

    @Test func gatedPendingCoachTurnIsPreservedWithoutInference() async throws {
        let store = store(), profile = DiaryProfile(name: "Synthetic waiting adult")
        let turn = CoachTurn(capturedAt: Date(), text: "Synthetic retained prompt", photos: [], captureTimeZoneID: profile.timeZoneID)
        _ = try await store.importProfile(DiarySnapshot(profile: profile, coachTurns: [turn]))
        let engine = CoachEngine(store: store, infer: { _, _ in
            Issue.record("A gated profile must never reach inference")
            throw DiaryError.invalidData
        })
        await #expect(throws: DiaryError.adultConfirmationRequired) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        let retained = try await store.snapshotForExport(expectedProfileID: profile.id)
        #expect(retained.coachTurns == [turn])
    }

    @Test func confirmationPreservesPortableAccountingWithoutAnActiveDay() async throws {
        let store = store(), profile = DiaryProfile(name: "Synthetic archive confirmation")
        _ = try await store.createProfile(profile)
        let original = try await store.snapshotForExport(expectedProfileID: profile.id)
        try await store.confirmAdultEligibility(expectedProfileID: profile.id)
        let confirmed = try await store.snapshotForExport(expectedProfileID: profile.id)
        #expect(confirmed.profile.adultConfirmed == true)
        #expect(confirmed.revision == original.revision)
        #expect(confirmed.activeDayID == nil)
    }

    @Test func restoredHealthDataRequiresFreshAttestationWithoutAFalseConflict() async throws {
        let store = store(), profile = DiaryProfile(name: "Synthetic restored adult")
        _ = try await store.createProfile(profile)
        let beforeAttestation = try await store.snapshotForExport(expectedProfileID: profile.id)
        try await store.confirmAdultEligibility(expectedProfileID: profile.id)
        try await store.restore(beforeAttestation, expectedProfileID: profile.id)
        let restored = try await store.snapshotForExport(expectedProfileID: profile.id)
        #expect(restored.profile.adultConfirmed == nil)
        await #expect(throws: DiaryError.adultConfirmationRequired) { try await store.requireAdultEligibility(expectedProfileID: profile.id) }
    }

}
