import Foundation

enum CoachTurnState: String, Codable, Sendable { case captured, analyzing, waitingForConnection, waitingForNetwork, needsRetry, needsClarification, completed }
enum MealTimePrecision: String, Codable, Sendable { case exact, dateOnly }
enum CoachActivity: String, Sendable { case preparingPhotos, thinking, reading, saving }
enum CoachDestination: String, Codable, CaseIterable, Sendable { case settings, profiles, connection, nutritionSource, backup }

struct CoachReceipt: Codable, Equatable, Sendable {
    var operationKey: String
    var turnID: UUID
    var dayID: UUID?
    var mealID: UUID? = nil
    var itemID: UUID? = nil
    var weightID: UUID? = nil
    var workoutID: UUID? = nil
    var goalID: UUID? = nil
    var destination: CoachDestination? = nil
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
        struct Photo: Codable, Equatable, Sendable { var id: UUID; var role: PhotoRole }
        struct Review: Codable, Equatable, Sendable {
            var submissionID: UUID
            var baseRevision: Int
            var items: [FoodItem]
        }
        var id: UUID
        var dayID: UUID
        var revision: Int
        var eatenAt: Date
        var timePrecision: MealTimePrecision?
        var items: [FoodItem]
        var state: SubmissionState = .saved
        var omittedItemCount = 0
        var photos: [Photo]? = nil
        var review: Review? = nil
        var omittedPhotoCount: Int? = nil
    }
    var profile: DiaryProfile
    var capturedAt: Date
    var captureTimeZoneID: String
    var activeDayID: UUID?
    var days: [TrackingDay]
    var meals: [Meal]
    var weights: [WeightEntry]
    var recentTurns: [Turn]
    var goal: GoalRecord? = nil
    var workouts: [WorkoutReference]? = nil
    var omittedWorkoutCount: Int? = nil
    var omittedWeightCount: Int? = nil
    var pendingMealID: UUID? = nil
    var pendingMealRevision: Int? = nil
    var additionalMealCount = 0
    var omittedMeals: [MealReference] = []
    var truncated = false
    var diaryRevision: Int? = nil
    var preferencesTruncated: Bool? = nil
    var attachedPhotoIDs: [UUID]? = nil
}

enum CoachError: Error, Equatable { case invalidTool, invalidArguments, limitExceeded, ungroundedConfirmation, connectionRequired }

func coachJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(value)
    guard data.count <= 65_536, let text = String(data: data, encoding: .utf8) else { throw DiaryError.invalidData }
    return text
}

struct WorkoutReference: Codable, Equatable, Sendable {
    var id: UUID
    var dayID: UUID
    var localDate: String
    var revision: Int
    var kind: WorkoutKind
    var durationMinutes: Int
}

struct CoachWeightReference: Codable, Equatable, Sendable {
    var localDate: String
    var record: WeightEntry
}

struct CoachProgress: Codable, Equatable, Sendable {
    var startLocalDate: String
    var endLocalDate: String
    var daily: DailyProgress
    var period: PeriodProgress?
    var weight: WeightProgress
    var weights: [CoachWeightReference]
    var workouts: [WorkoutReference]
    var omittedWeightCount: Int
    var omittedWorkoutCount: Int
    var truncated: Bool
}

extension NutritionTotals: Codable {
    enum CodingKeys: String, CodingKey { case kcal, carbs, protein, fat, unknownItemCount }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kcal: try c.decodeIfPresent(Double.self, forKey: .kcal),
                  carbs: try c.decodeIfPresent(Double.self, forKey: .carbs),
                  protein: try c.decodeIfPresent(Double.self, forKey: .protein),
                  fat: try c.decodeIfPresent(Double.self, forKey: .fat),
                  unknownItemCount: try c.decode(Int.self, forKey: .unknownItemCount))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(kcal, forKey: .kcal); try c.encodeIfPresent(carbs, forKey: .carbs)
        try c.encodeIfPresent(protein, forKey: .protein); try c.encodeIfPresent(fat, forKey: .fat)
        try c.encode(unknownItemCount, forKey: .unknownItemCount)
    }
}
