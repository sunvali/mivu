import Foundation
import Testing
@testable import Mivu

struct ManualNutritionPayloadTests {
    static func fixture(kcal: Double? = 0, operation: ManualNutritionOperation = .create,
                        revision: Int? = nil) -> ManualNutritionPayload {
        func id(_ value: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))! }
        return ManualNutritionPayload(profileID: id(1), mealID: id(2), submissionID: id(3), operation: operation,
            target: .recorded(dayID: id(4), localDate: "2026-10-19", timeZoneID: "UTC"),
            capturedAt: Date(timeIntervalSinceReferenceDate: 800_000_000.25),
            eatenAt: Date(timeIntervalSinceReferenceDate: 799_999_900.5), timePrecision: .exact,
            expectedMealRevision: revision, items: [FoodItem(id: id(5), name: "Crème 🍎", quantity: 0.125,
                unit: "cup\"\\\n", nutrition: NutritionValues(kcal: kcal, protein: 1.25), provenance: .user,
                reference: "Entered", uncertain: false)])
    }
    @Test func canonicalFingerprintSeparatesUnknownAndZero() throws {
        let knownZero = Self.fixture(), unknown = Self.fixture(kcal: nil)
        #expect(try manualNutritionFingerprint(knownZero) != manualNutritionFingerprint(unknown))
    }
    @Test func createRejectsAppendRevision() throws {
        #expect(throws: DiaryError.invalidData) { try validateManualNutritionPayload(Self.fixture(revision: 1)) }
    }
    @Test func appendRequiresPositiveRevision() throws {
        #expect(throws: DiaryError.invalidData) { try validateManualNutritionPayload(Self.fixture(operation: .append)) }
        try validateManualNutritionPayload(Self.fixture(operation: .append, revision: 1))
    }
    static func snapshot() throws -> DiarySnapshot {
        let payload = fixture()
        let day = TrackingDay(id: payload.target.day.id, localDate: payload.target.day.localDate,
            timeZoneID: payload.target.day.timeZoneID, startAt: payload.capturedAt)
        let submission = MealSubmission(id: payload.submissionID, baseRevision: 0, text: "Manual", photoIDs: [],
            reviewFirst: false, state: .saved, proposal: AnalysisOutput(profileID: payload.profileID,
                mealID: payload.mealID, submissionID: payload.submissionID, baseRevision: 0, items: payload.items),
            manualAcceptance: try ManualNutritionAcceptance(payload: payload))
        return DiarySnapshot(profile: DiaryProfile(id: payload.profileID, name: "Synthetic"), days: [day],
            meals: [DiaryMeal(id: payload.mealID, dayID: day.id, capturedAt: payload.capturedAt,
                eatenAt: payload.eatenAt, revision: 1, items: payload.items, submissions: [submission])], activeDayID: day.id)
    }
    @Test func acceptanceReconstructsOriginalPayload() throws {
        var snapshot = try Self.snapshot()
        snapshot.meals[0].items[0].nutrition.kcal = 999
        try snapshot.validate()
        snapshot.meals[0].submissions[0].proposal!.items[0].nutrition.kcal = 999
        #expect(throws: DiaryError.invalidData) { try snapshot.validate() }
    }
    @Test func acceptanceRejectsTamperedMetadataAndAssociation() throws {
        let original = try Self.snapshot()
        for mutation in 0..<8 {
            var changed = original
            switch mutation {
            case 0: changed.meals[0].submissions[0].manualAcceptance!.schemaVersion = 2
            case 1: changed.meals[0].submissions[0].manualAcceptance!.enteredItemIDs = [UUID()]
            case 2: changed.meals[0].submissions[0].manualAcceptance!.payloadFingerprint = String(repeating: "0", count: 64)
            case 3: changed.meals[0].submissions[0].baseRevision = 1
            case 4: changed.meals[0].submissions[0].state = .captured
            case 5: changed.meals[0].submissions[0].proposal!.profileID = UUID()
            case 6: changed.meals[0].submissions[0].proposal!.mealID = UUID()
            default: changed.meals[0].submissions[0].proposal!.submissionID = UUID()
            }
            #expect(throws: DiaryError.invalidData) { try changed.validate() }
        }
    }
    @Test func originalTargetSurvivesMealMoveButMustRemainValid() throws {
        var snapshot = try Self.snapshot()
        let other = TrackingDay(localDate: "2026-10-20", timeZoneID: "UTC", startAt: Date())
        snapshot.days.append(other); snapshot.meals[0].dayID = other.id
        try snapshot.validate()
        snapshot.days[0].localDate = "2026-10-18"
        #expect(throws: DiaryError.invalidData) { try snapshot.validate() }
    }
    @Test func canonicalFingerprintNormalizesNegativeZeroAndIsStable() throws {
        #expect(try manualNutritionFingerprint(Self.fixture(kcal: -0.0)) == manualNutritionFingerprint(Self.fixture(kcal: 0)))
        #expect(try manualNutritionFingerprint(Self.fixture()) == manualNutritionFingerprint(Self.fixture()))
    }
    @Test func missingKnownNutritionAndNonpositiveQuantityReject() throws {
        let source = Self.fixture()
        for mutation in 0..<5 {
            var items = source.items
            switch mutation {
            case 0: items[0].nutrition = NutritionValues()
            case 1: items[0].quantity = 0
            case 2: items[0].quantity = .infinity
            case 3: items[0].nutrition.kcal = .nan
            default: items.append(items[0])
            }
            let payload = ManualNutritionPayload(profileID: source.profileID, mealID: source.mealID,
                submissionID: source.submissionID, operation: .create, target: source.target,
                capturedAt: source.capturedAt, eatenAt: source.eatenAt, timePrecision: .exact,
                expectedMealRevision: nil, items: items)
            #expect(throws: DiaryError.invalidData) { try validateManualNutritionPayload(payload) }
        }
    }

    @Test func canonicalFingerprintGoldenUnicodeEscapesFractionsAndNulls() throws {
        #expect(try manualNutritionFingerprint(Self.fixture()) == "37077a385a96311c22d56878164ca0fe940ffaf475f43e0d44dc8d3a196d56a4")
        #expect(try manualNutritionFingerprint(Self.fixture(kcal: nil)) == "4b901e00e9fcc6705c17a27d45ef091319b01f92a5077bbf7165b0aa44ccc9c6")
    }
    @Test func invalidClocksDatesZonesAndEmptyItemsReject() throws {
        let source = Self.fixture()
        for mutation in 0..<6 {
            let target: ManualNutritionTarget
            switch mutation {
            case 0: target = .recorded(dayID: source.target.day.id, localDate: "2026-02-30", timeZoneID: "UTC")
            case 1: target = .active(dayID: source.target.day.id, localDate: "2026-10-19", timeZoneID: "invalid-zone", confirmPrevious: false)
            case 2: target = .newCurrent(dayID: source.target.day.id, localDate: "2026-10-19", timeZoneID: "UTC", previousActiveDayID: source.target.day.id)
            default: target = source.target
            }
            let payload = ManualNutritionPayload(profileID: source.profileID, mealID: source.mealID,
                submissionID: source.submissionID, operation: .create, target: target,
                capturedAt: mutation == 3 ? Date(timeIntervalSinceReferenceDate: .infinity) : source.capturedAt,
                eatenAt: mutation == 4 ? Date(timeIntervalSinceReferenceDate: .nan) : source.eatenAt,
                timePrecision: .exact, expectedMealRevision: nil, items: mutation == 5 ? [] : source.items)
            #expect(throws: DiaryError.invalidData) { try validateManualNutritionPayload(payload) }
        }
        for revision in [0, -1, 1_000_000] {
            #expect(throws: DiaryError.invalidData) { try validateManualNutritionPayload(Self.fixture(operation: .append, revision: revision)) }
        }
        try validateManualNutritionPayload(source)
    }

    @Test func acceptanceCannotClaimUncommittedMealRevision() throws {
        var snapshot = try Self.snapshot()
        snapshot.meals[0].revision = 0
        #expect(throws: DiaryError.invalidData) { try snapshot.validate() }
    }

}
