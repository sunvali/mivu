import Foundation
import CryptoKit

enum CoachTurnState: String, Codable, Sendable { case captured, analyzing, waitingForConnection, waitingForNetwork, needsRetry, needsClarification, completed }
enum MealTimePrecision: String, Codable, Sendable { case exact, dateOnly }
enum CoachActivity: String, Sendable { case preparingPhotos, thinking, reading, saving }
enum CoachDestination: String, Codable, CaseIterable, Sendable { case settings, profiles, connection, nutritionSource, backup }

/// Engine acknowledgement contains no original photo payloads.
struct CoachTurnResult: Equatable, Sendable {
    var id: UUID
    var text: String
    var state: CoachTurnState
    var assistantText: String?
    var receipts: [CoachReceipt]
    var pendingMealID: UUID?
    init(_ turn: CoachTurn) {
        id = turn.id; text = turn.text; state = turn.state; assistantText = turn.assistantText; receipts = turn.receipts; pendingMealID = turn.pendingMealID
    }
    init(_ work: CoachWorkItem) {
        id = work.id; text = work.text; state = work.state; assistantText = work.assistantText; receipts = work.receipts; pendingMealID = work.pendingMealID
    }
}

/// Durable worker metadata; originals are fetched separately for the selected job.
struct CoachWorkItem: Equatable, Sendable, Identifiable {
    var id: UUID
    var sequence: Int64
    var capturedAt: Date
    var text: String
    var state: CoachTurnState
    var assistantText: String?
    var receipts: [CoachReceipt]
    var captureTimeZoneID: String
    var activeDayID: UUID?
    var resolvedDayID: UUID?
    var needsDayChoice: Bool?
    var pendingMealID: UUID?
    var pendingMealRevision: Int?
    var photos: [DiaryPhotoReference]
}

struct PendingSubmissionReference: Equatable, Sendable {
    var mealID: UUID
    var submissionID: UUID
    var mealRevision: Int
    var baseRevision: Int
    var capturedAt: Date
    var text: String
    var state: SubmissionState
    var dayID: UUID
    var timeZoneID: String
    var photos: [DiaryPhotoReference]
}

struct CoachMealCandidate: Codable, Equatable, Sendable, Identifiable {
    struct Item: Codable, Equatable, Sendable {
        var id: UUID
        var name: String
        var quantity: Double
        var unit: String
    }
    var id: UUID
    var dayID: UUID
    var localDate: String
    var timeZoneID: String
    var revision: Int
    var eatenAt: Date
    var timePrecision: MealTimePrecision?
    var items: [Item]
    var omittedItemCount: Int
    var capturedDescription: String
    var descriptionTruncated: Bool
}

struct CoachMealCandidatePage: Codable, Equatable, Sendable {
    var localDate: String
    var meals: [CoachMealCandidate]
    var hasMore: Bool
    var nextAfterMealID: UUID?
}

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
    var commandFingerprint: String? = nil
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
    var submissionManifest: CoachSubmissionManifest? = nil
    var captureSegmentID: UUID? = nil
    /// Set when this turn ended with a question the next reply answers.
    var question: CoachQuestion? = nil
    /// True when saved food was kept but the rest of the request failed.
    var incomplete: Bool? = nil
    /// Error case or domain/code from the last failed run; never user or model text.
    var failureReason: String? = nil
}

struct CoachCaptureContext: Codable, Equatable, Sendable {
    var capturedAt: Date
    var timeZoneID: String
    var activeDayID: UUID?
    var previousDayConfirmedAt: Date?
    var activeConversationSegmentID: UUID? = nil
}

struct CoachSubmissionManifest: Codable, Equatable, Sendable {
    struct Attachment: Codable, Equatable, Sendable {
        var id: UUID
        var role: PhotoRole
        var createdAt: Date
        var contentFingerprint: String
    }
    var submissionID: UUID
    var context: CoachCaptureContext
    var textFingerprint: String
    var attachments: [Attachment]
    var pendingMealID: UUID?
    var pendingMealRevision: Int?
    var reply: CoachReply? = nil
}

/// What a turn replies to: an earlier message or a Diary record. The excerpt is the quote shown when it was sent.
struct CoachReply: Codable, Equatable, Sendable {
    enum Target: Codable, Equatable, Sendable {
        case message(turnID: UUID, fromPip: Bool)
        case meal(mealID: UUID)
        case item(mealID: UUID, itemID: UUID)
        case day(dayID: UUID)
    }
    var target: Target
    var excerpt: String
    var isValid: Bool { excerpt.count <= 280 && !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct CoachSubmissionPayload: Sendable {
    let submissionID: UUID
    let text: String
    let attachments: [MealPhoto]
    let context: CoachCaptureContext
    let manifest: CoachSubmissionManifest
    init(submissionID: UUID, text: String, attachments: [MealPhoto], context: CoachCaptureContext,
         pendingMealID: UUID? = nil, pendingMealRevision: Int? = nil, reply: CoachReply? = nil) throws {
        guard attachments.count <= 8, reply?.isValid != false, Set(attachments.map(\.id)).count == attachments.count, text.count <= 20_000,
              context.capturedAt.timeIntervalSince1970.isFinite,
              TimeZone(identifier: context.timeZoneID) != nil,
              context.previousDayConfirmedAt == nil || context.previousDayConfirmedAt!.timeIntervalSince1970.isFinite,
              (pendingMealID == nil) == (pendingMealRevision == nil),
              pendingMealRevision == nil || pendingMealRevision! >= 0 else { throw DiaryError.invalidData }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { throw DiaryError.emptyCapture }
        for photo in attachments { try validatePhotoFields(photo, byteCount: photo.data.count) }
        func fingerprint(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
        self.submissionID = submissionID; self.text = text; self.attachments = attachments; self.context = context
        manifest = CoachSubmissionManifest(submissionID: submissionID, context: context,
            textFingerprint: fingerprint(Data(text.utf8)), attachments: attachments.map {
                CoachSubmissionManifest.Attachment(id: $0.id, role: $0.role, createdAt: $0.createdAt, contentFingerprint: fingerprint($0.data))
            }, pendingMealID: pendingMealID, pendingMealRevision: pendingMealRevision, reply: reply)
    }
}

enum CoachCaptureReconciliation: Equatable, Sendable {
    case absent, accepted(CoachExchangeSummary), conflictingPayload
}

struct CoachContext: Codable, Equatable, Sendable {
    struct Turn: Codable, Equatable, Sendable {
        var id: UUID
        var capturedAt: Date
        var text: String
        var assistantText: String?
        var receipts: String? = nil
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
    var committedReceipts: [CoachCommittedReceipt]? = nil
    var omittedReceiptCount: Int? = nil
    /// What the person is replying to, resolved to current content for this turn only.
    var replyTo: Reply? = nil
    struct Focus: Codable, Equatable, Sendable {
        struct LastChanged: Codable, Equatable, Sendable { var mealID: UUID; var itemNames: [String]; var localDate: String; var revision: Int }
        var lastChanged: LastChanged? = nil
        var pendingQuestion: CoachQuestion? = nil
    }
    /// Conversation focus for resolving "it"/"that"; nil when nothing applies.
    var focus: Focus? = nil
    struct Reply: Codable, Equatable, Sendable {
        var target: CoachReply.Target
        var excerpt: String
        var turn: Turn? = nil
        var meal: Meal? = nil
        var unavailable: Bool? = nil
    }
}

extension CoachContext {
    mutating func includeCommittedReceipts(_ receipts: [CoachCommittedReceipt]) throws {
        committedReceipts = []
        for receipt in receipts {
            if try JSONEncoder().encode(committedReceipts! + [receipt]).count > 8192 { break }
            committedReceipts!.append(receipt)
        }
        omittedReceiptCount = receipts.count - committedReceipts!.count
    }
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
    var dailyReports: [DailyProgress]? = nil
    var displayWeights: [CoachWeightReference]? = nil
    var latestWeight: CoachWeightReference? = nil
    var workoutTotal: Int? = nil
    var savedFoodDates: [String]? = nil
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

/// An unanswered Coach question; the next reply is resolved against it.
struct CoachQuestion: Codable, Equatable, Sendable {
    var kind: CoachClarification
    var candidates: [CoachReply.Target]
    var originalText: String
}
