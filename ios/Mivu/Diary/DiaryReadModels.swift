import Foundation
import os

struct DiaryHead: Equatable, Sendable {
    var profile: DiaryProfile
    var revision: Int
    var lineage: [UUID]?
    var activeDayID: UUID?
    var previousDayConfirmedAt: Date?
    var timelineGeneration: UUID
    var activeConversationSegmentID: UUID? = nil
    /// Derived capture context only; never encoded or persisted as portable metadata by a read/status.
    var effectiveConversationSegmentID: UUID? = nil
}

struct DiarySelectionOwnership: Equatable, Sendable {
    let identity: CoachTimelineIdentity
    let selectionEpoch: UInt64
}

struct CoachCapturePreparation: Equatable, Sendable {
    let ownership: DiarySelectionOwnership
    let context: CoachCaptureContext
}

enum DiaryPhotoOwner: Hashable, Sendable { case meal(UUID), coachTurn(UUID) }

struct DiaryPhotoReference: Equatable, Sendable, Identifiable {
    struct Identity: Hashable, Sendable {
        var profileID: UUID
        var owner: DiaryPhotoOwner
        var photoID: UUID
        var contentToken: UUID
    }
    var profileID: UUID
    var owner: DiaryPhotoOwner
    var photoID: UUID
    var createdAt: Date
    var role: PhotoRole
    var contentToken: UUID
    var id: Identity { Identity(profileID: profileID, owner: owner, photoID: photoID, contentToken: contentToken) }
}

struct MealReadModel: Equatable, Sendable, Identifiable {
    var id: UUID
    var dayID: UUID
    var capturedAt: Date
    var eatenAt: Date
    var revision: Int
    var timePrecision: MealTimePrecision?
    var items: [FoodItem]
    var submissions: [MealSubmission]
    var photos: [DiaryPhotoReference]
    var sourceTurnID: UUID?
    var totals: NutritionTotals { nutritionTotals(items) }
    var isSaved: Bool { revision > 0 }
    var state: SubmissionState { submissions.last?.state ?? .saved }
    var hasUnresolvedInput: Bool {
        (!isSaved && submissions.isEmpty) || submissions.contains { $0.state != .saved && $0.state != .cancelled }
    }
}

struct DiaryReadModel: Equatable, Sendable {
    var head: DiaryHead
    var activeDay: TrackingDay?
    var meals: [MealReadModel]
    var weight: WeightEntry?
    var workouts: [WorkoutSession]
    var activeGoal: GoalRecord?
    var pendingAnalysisCount: Int
    var hasPendingOnActiveDay: Bool = false
}

struct DiaryDayReadModel: Equatable, Sendable {
    var head: DiaryHead
    var day: TrackingDay
    var meals: [MealReadModel]
    var weight: WeightEntry?
    var workouts: [WorkoutSession]
    var goal: GoalRecord?
}

struct DiaryChanges: Equatable, Sendable {
    var dayIDs: Set<UUID> = []
    var mealIDs: Set<UUID> = []
    var turnIDs: Set<UUID> = []
    var weightIDs: Set<UUID> = []
    var workoutIDs: Set<UUID> = []
    var profileReset = false
    var timelineReset = false
    var coachLatestChanged = false
}

struct DiaryCommit<Value: Sendable>: Sendable {
    var value: Value
    var head: DiaryHead
    var changes: DiaryChanges
}

/// Counts only work and query plans; never stores submitted text or bound values.
final class DiaryQueryDiagnostics: Sendable {
    struct Counters: Equatable, Sendable {
        var decodedTurnPayloads = 0
        var originalPhotoBytes = 0
        var maximumPhotoReadChunkBytes = 0
        var completeReads = 0
        var completeReconciles = 0
        var coachPageReads = 0
        var queryPlans: [String] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: Counters())
    var counters: Counters { state.withLock { $0 } }
    func reset() { state.withLock { $0 = Counters() } }
    func recordTurnDecode() { state.withLock { $0.decodedTurnPayloads += 1 } }
    func recordPhotoRead(bytes: Int) {
        state.withLock { $0.originalPhotoBytes += bytes; $0.maximumPhotoReadChunkBytes = max($0.maximumPhotoReadChunkBytes, bytes) }
    }
    func recordCompleteRead() { state.withLock { $0.completeReads += 1 } }
    func recordCompleteReconcile() { state.withLock { $0.completeReconciles += 1 } }
    func recordCoachPageRead() { state.withLock { $0.coachPageReads += 1 } }
    func recordQueryPlan(_ plan: String) { state.withLock { $0.queryPlans.append(plan) } }
}

struct DiaryHistoryCursor: Equatable, Sendable {
    var identity: CoachTimelineIdentity
    var ordinal: Int
    var dayID: UUID
    var recordedOnly: Bool
    var localDate: String? = nil
}
struct DiaryDaySummary: Equatable, Sendable {
    var mealCount: Int
    var day: TrackingDay
    var totals: NutritionTotals
    var savedMealCount: Int
    var pendingMealCount: Int
}
struct DiaryWeekPage: Equatable, Sendable {
    var days: [DiaryDaySummary]
    var earliestLocalDate: String?
}

struct DiaryHistoryPage: Equatable, Sendable {
    var days: [DiaryDaySummary]
    var cursor: DiaryHistoryCursor?
    var hasMore: Bool
}


extension DiaryReadModel {
    var profile: DiaryProfile { head.profile }
    var revision: Int { head.revision }
    var activeDayID: UUID? { head.activeDayID }
    var previousDayConfirmedAt: Date? { head.previousDayConfirmedAt }
    var pendingCount: Int { pendingAnalysisCount }
    var totals: NutritionTotals {
        dayNutritionTotals(meals: meals, complete: activeDay?.completeness == .complete, hasPending: hasPendingOnActiveDay)
    }
}

extension DiaryDayReadModel {
    var totals: NutritionTotals {
        dayNutritionTotals(meals: meals, complete: day.completeness == .complete, hasPending: false)
    }
}

private func dayNutritionTotals(meals: [MealReadModel], complete: Bool, hasPending: Bool) -> NutritionTotals {
    let items = meals.filter(\.isSaved).flatMap(\.items)
    if items.isEmpty, complete, !hasPending, !meals.contains(where: \.hasUnresolvedInput) {
        return NutritionTotals(kcal: 0, carbs: 0, protein: 0, fat: 0, unknownItemCount: 0)
    }
    return nutritionTotals(items)
}
