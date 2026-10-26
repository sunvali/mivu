import Foundation
@testable import Mivu

/// Synthetic adult fixtures exercise the real eligibility rule; legacy/minor tests use DiaryProfile directly.
func adultProfile(id: UUID = UUID(), name: String, language: String = "en", timeZoneID: String = TimeZone.current.identifier,
                  preferences: String = "", about: ProfileAbout? = nil) -> DiaryProfile {
    DiaryProfile(id: id, name: name, language: language, timeZoneID: timeZoneID, preferences: preferences, about: about, adultConfirmed: true)
}

// Import synthetic fixture content, then explicitly attest on this device through the real API.
extension DiaryStore {
    func importAdultFixture(_ snapshot: DiarySnapshot) throws -> DiaryReadModel {
        let imported = try importProfile(snapshot)
        if snapshot.profile.adultConfirmed == true && AdultEligibility.canConfirm(birthYear: snapshot.profile.about?.birthYear) {
            try confirmAdultEligibility(expectedProfileID: imported.profile.id)
        }
        return try diaryReadModel(expectedProfileID: imported.profile.id)
    }
    func restoreAdultFixture(_ snapshot: DiarySnapshot, expectedProfileID: UUID? = nil) async throws {
        try await restore(snapshot, expectedProfileID: expectedProfileID)
        if snapshot.profile.adultConfirmed == true && AdultEligibility.canConfirm(birthYear: snapshot.profile.about?.birthYear) {
            try confirmAdultEligibility(expectedProfileID: snapshot.profile.id)
        }
    }
}
