import Foundation

enum CoachTurnState: String, Codable, Sendable { case captured, analyzing, waitingForConnection, waitingForNetwork, needsRetry, needsClarification, completed }
enum MealTimePrecision: String, Codable, Sendable { case exact, dateOnly }

struct CoachReceipt: Codable, Equatable, Sendable {
    var operationKey: String
    var turnID: UUID
    var dayID: UUID
    var mealID: UUID? = nil
    var itemID: UUID? = nil
    var committedRevision: Int
    var resultJSON: String
}

struct CoachTurn: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var capturedAt: Date
    var text: String
    var photos: [MealPhoto] = []
    var state: CoachTurnState = .captured
    var assistantText: String? = nil
    var receipts: [CoachReceipt] = []
    var captureTimeZoneID: String
    var activeDayID: UUID? = nil
    var photoIDs: [UUID] = []
    var needsDayChoice: Bool? = nil
    var resolvedDayID: UUID? = nil
    var pendingMealID: UUID? = nil
    var pendingMealRevision: Int? = nil
}

struct CoachContext: Codable, Equatable, Sendable {
    struct Turn: Codable, Equatable, Sendable {
        var id: UUID
        var capturedAt: Date
        var text: String
        var assistantText: String?
    }
    struct MealReference: Codable, Equatable, Sendable {
        var id: UUID
        var dayID: UUID
        var revision: Int
        var itemCount: Int
    }
    struct Meal: Codable, Equatable, Sendable {
        var id: UUID
        var dayID: UUID
        var revision: Int
        var eatenAt: Date
        var timePrecision: MealTimePrecision?
        var items: [FoodItem]
        var state: SubmissionState = .saved
        var omittedItemCount = 0
    }
    var profile: DiaryProfile
    var capturedAt: Date
    var captureTimeZoneID: String
    var activeDayID: UUID?
    var days: [TrackingDay]
    var meals: [Meal]
    var weights: [WeightEntry]
    var recentTurns: [Turn]
    var pendingMealID: UUID? = nil
    var pendingMealRevision: Int? = nil
    var additionalMealCount = 0
    var omittedMeals: [MealReference] = []
    var truncated = false
}

enum CoachError: Error, Equatable { case invalidTool, invalidArguments, limitExceeded, ungroundedConfirmation, connectionRequired }

func coachJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(value)
    guard data.count <= 65_536, let text = String(data: data, encoding: .utf8) else { throw DiaryError.invalidData }
    return text
}
