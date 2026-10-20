import Foundation
import CryptoKit

enum ManualNutritionOperation: String, Codable, Sendable { case create, append }
enum ManualNutritionDayChoice: Equatable, Sendable { case current, newCurrent, recorded(UUID) }
enum ManualNutritionTarget: Codable, Equatable, Sendable {
    case recorded(dayID: UUID, localDate: String, timeZoneID: String)
    case active(dayID: UUID, localDate: String, timeZoneID: String, confirmPrevious: Bool)
    case newCurrent(dayID: UUID, localDate: String, timeZoneID: String, previousActiveDayID: UUID?)
}
struct ManualNutritionPayload: Equatable, Sendable {
    let profileID: UUID
    let mealID: UUID
    let submissionID: UUID
    let operation: ManualNutritionOperation
    let target: ManualNutritionTarget
    let capturedAt: Date
    let eatenAt: Date
    let timePrecision: MealTimePrecision
    let expectedMealRevision: Int?
    let items: [FoodItem]
}
struct ManualNutritionAcceptance: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var operation: ManualNutritionOperation
    var payloadFingerprint: String
    var target: ManualNutritionTarget
    var capturedAt: Date
    var eatenAt: Date
    var timePrecision: MealTimePrecision
    var expectedMealRevision: Int?
    var enteredItemIDs: [UUID]
}
extension ManualNutritionTarget {
    var day: (id: UUID, localDate: String, timeZoneID: String) {
        switch self {
        case let .recorded(id, date, zone), let .active(id, date, zone, _), let .newCurrent(id, date, zone, _):
            return (id, date, zone)
        }
    }
}

func validateManualNutritionPayload(_ payload: ManualNutritionPayload) throws {
    try validateItems(payload.items)
    guard !payload.items.isEmpty,
          payload.items.allSatisfy({ $0.quantity > 0 && [$0.nutrition.kcal, $0.nutrition.carbs, $0.nutrition.protein, $0.nutrition.fat].contains(where: { $0 != nil }) }),
          payload.capturedAt.timeIntervalSinceReferenceDate.isFinite,
          payload.eatenAt.timeIntervalSinceReferenceDate.isFinite,
          validLocalDate(payload.target.day.localDate), TimeZone(identifier: payload.target.day.timeZoneID) != nil else { throw DiaryError.invalidData }
    switch payload.operation {
    case .create: guard payload.expectedMealRevision == nil else { throw DiaryError.invalidData }
    case .append: guard let revision = payload.expectedMealRevision, revision > 0, revision < 1_000_000 else { throw DiaryError.invalidData }
    }
    if case let .newCurrent(id, _, _, previous) = payload.target, id == previous { throw DiaryError.invalidData }
}

func manualNutritionFingerprint(_ payload: ManualNutritionPayload) throws -> String {
    try validateManualNutritionPayload(payload)
    func number(_ value: Double?) -> Any { value.map { $0 == 0 ? 0 : $0 } as Any? ?? NSNull() }
    func nutrition(_ value: NutritionValues) -> [String: Any] {
        ["kcal": number(value.kcal), "carbs": number(value.carbs), "protein": number(value.protein), "fat": number(value.fat)]
    }
    var target: [String: Any] = ["dayID": payload.target.day.id.uuidString, "localDate": payload.target.day.localDate,
                               "timeZoneID": payload.target.day.timeZoneID]
    switch payload.target {
    case .recorded: target["kind"] = "recorded"
    case let .active(_, _, _, confirm): target["kind"] = "active"; target["confirmPrevious"] = confirm
    case let .newCurrent(_, _, _, previous):
        target["kind"] = "newCurrent"; target["previousActiveDayID"] = previous?.uuidString as Any? ?? NSNull()
    }
    let items: [[String: Any]] = payload.items.map { item in
        ["id": item.id.uuidString, "name": item.name, "quantity": number(item.quantity), "unit": item.unit,
         "nutrition": nutrition(item.nutrition), "provenance": item.provenance.rawValue, "reference": item.reference,
         "uncertain": item.uncertain, "nutrientSources": item.nutrientSources.mapValues(\.rawValue),
         "nutritionBasis": item.nutritionBasis.map(nutrition) as Any? ?? NSNull()]
    }
    let object: [String: Any] = ["schemaVersion": 1, "profileID": payload.profileID.uuidString,
        "mealID": payload.mealID.uuidString, "submissionID": payload.submissionID.uuidString,
        "operation": payload.operation.rawValue, "target": target,
        "capturedAt": number(payload.capturedAt.timeIntervalSinceReferenceDate),
        "eatenAt": number(payload.eatenAt.timeIntervalSinceReferenceDate), "timePrecision": payload.timePrecision.rawValue,
        "expectedMealRevision": payload.expectedMealRevision as Any? ?? NSNull(), "items": items]
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

extension ManualNutritionAcceptance {
    init(payload: ManualNutritionPayload) throws {
        self.init(operation: payload.operation, payloadFingerprint: try manualNutritionFingerprint(payload),
            target: payload.target, capturedAt: payload.capturedAt, eatenAt: payload.eatenAt,
            timePrecision: payload.timePrecision, expectedMealRevision: payload.expectedMealRevision,
            enteredItemIDs: payload.items.map(\.id))
    }
}

extension ManualNutritionAcceptance {
    /// Compares stored fields directly; the fingerprint is write-only so a library change cannot lock out saved meals.
    func matches(_ payload: ManualNutritionPayload, proposal: AnalysisOutput?) -> Bool {
        operation == payload.operation && target == payload.target && capturedAt == payload.capturedAt
            && eatenAt == payload.eatenAt && timePrecision == payload.timePrecision
            && expectedMealRevision == payload.expectedMealRevision && enteredItemIDs == payload.items.map(\.id)
            && proposal?.items == payload.items
    }
}

func validateManualAcceptance(_ acceptance: ManualNutritionAcceptance,
                              submission: MealSubmission, mealID: UUID, profileID: UUID) throws {
    guard acceptance.schemaVersion == 1, submission.state == .saved, submission.photoIDs.isEmpty,
          let proposal = submission.proposal, proposal.schemaVersion == 1,
          proposal.profileID == profileID, proposal.mealID == mealID, proposal.submissionID == submission.id,
          proposal.baseRevision == submission.baseRevision, acceptance.enteredItemIDs == proposal.items.map(\.id),
          submission.baseRevision == (acceptance.expectedMealRevision ?? 0) else { throw DiaryError.invalidData }
}
