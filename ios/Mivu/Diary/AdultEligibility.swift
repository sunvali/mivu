import Foundation

enum AdultEligibility {
    static func canConfirm(birthYear: Int?, at date: Date = Date()) -> Bool {
        guard let birthYear else { return true }
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        return (1900...(year - 18)).contains(birthYear)
    }
    static func isEligible(_ profile: DiaryProfile, at date: Date = Date()) -> Bool {
        profile.adultConfirmed == true && canConfirm(birthYear: profile.about?.birthYear, at: date)
    }
    static func lockedKey(_ profileID: UUID) -> String { "adultEligible-" + profileID.uuidString }
}
