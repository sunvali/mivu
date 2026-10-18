import Foundation

struct CoachTimelineIdentity: Equatable, Hashable, Sendable {
    var profileID: UUID
    var timelineGeneration: UUID
}

struct CoachCursor: Equatable, Sendable {
    var identity: CoachTimelineIdentity
    var sequence: Int64
    var turnID: UUID
}

struct CoachCommittedItem: Equatable, Sendable {
    var itemID: UUID
    var name: String
    var quantity: Double
    var unit: String
}

/// Committed linkage for presentation. Replay continues to use CoachReceipt.
struct CoachCommittedReceipt: Equatable, Sendable {
    var operationKey: String
    var turnID: UUID
    var dayID: UUID?
    var mealID: UUID?
    var itemID: UUID?
    var weightID: UUID?
    var workoutID: UUID?
    var goalID: UUID?
    var destination: CoachDestination?
    var committedRevision: Int
    var targetLocalDate: String? = nil
    var items: [CoachCommittedItem] = []
}

struct CoachExchangeSummary: Equatable, Sendable, Identifiable {
    var id: UUID
    var sequence: Int64
    var capturedAt: Date
    var captureTimeZoneID: String
    var segmentID: UUID
    var trackingDayID: UUID?
    var displayLocalDate: String
    var displayTimeZoneID: String
    var text: String
    var assistantText: String?
    var state: CoachTurnState
    var photos: [DiaryPhotoReference]
    var receipts: [CoachCommittedReceipt]
}

enum CoachPageRequest: Equatable, Sendable {
    case latest, before(CoachCursor), after(CoachCursor), aroundTurn(UUID), atDay(UUID)
}

struct CoachPage: Equatable, Sendable {
    var identity: CoachTimelineIdentity
    var exchanges: [CoachExchangeSummary]
    var before: CoachCursor?
    var after: CoachCursor?
    var hasEarlier: Bool
    var hasLater: Bool
    var earlierSegment: CoachSegmentSummary?
    var laterSegment: CoachSegmentSummary?
}

struct CoachSegmentSummary: Equatable, Sendable, Identifiable {
    var segmentID: UUID
    var trackingDayID: UUID?
    var displayLocalDate: String
    var displayTimeZoneID: String
    var firstExchangeID: UUID
    var firstCapturedAt: Date
    var firstSequence: Int64
    var lastSequence: Int64
    var preview: String
    var id: UUID { segmentID }
}

struct CoachDayCursor: Equatable, Sendable {
    var identity: CoachTimelineIdentity
    var lastSequence: Int64
    var segmentID: UUID
    var dateFilterScope: String?
}

struct CoachDayPage: Equatable, Sendable {
    var identity: CoachTimelineIdentity
    var segments: [CoachSegmentSummary]
    var cursor: CoachDayCursor?
    var hasMore: Bool
}

enum CoachQueryError: Error, Equatable, Sendable {
    case wrongTimeline, invalidCursor, invalidDateFilter, noChatForDay(UUID), missingTurn(UUID)
}
enum CoachSeekTarget: Equatable, Sendable { case day(UUID), turn(UUID) }
struct CoachNavigationRequest: Equatable, Sendable {
    var identity: CoachTimelineIdentity
    var target: CoachSeekTarget
    var requestID: UUID
}
