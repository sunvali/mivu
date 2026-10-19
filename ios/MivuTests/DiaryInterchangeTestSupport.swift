import Foundation
import Testing
@testable import Mivu

// Legacy assertions inspect complete portable facts explicitly; production workers use work items.
func exportedTurn(_ store: DiaryStore, turnID: UUID, expectedProfileID: UUID) async throws -> CoachTurn {
    let archive = try await store.snapshotForExport(expectedProfileID: expectedProfileID)
    return try #require(archive.coachTurns.first { $0.id == turnID })
}

func exportedCoachPhotos(_ store: DiaryStore, turnID: UUID, expectedProfileID: UUID) async throws -> [MealPhoto] {
    let work = try await store.coachWorkItem(turnID: turnID, expectedProfileID: expectedProfileID)
    var result: [MealPhoto] = []
    for reference in work.photos {
        let data = try await store.photoContent(reference, expectedProfileID: expectedProfileID)
        result.append(MealPhoto(id: reference.photoID, data: data, createdAt: reference.createdAt, role: reference.role))
    }
    return result
}

func capturedTurn(_ store: DiaryStore, text: String, photos: [MealPhoto], at: Date = Date(), turnID: UUID = UUID(), pendingMealID: UUID? = nil, expectedProfileID: UUID) async throws -> CoachTurn {
    if pendingMealID != nil {
        _ = try await store.preparePendingCoachTurn(turnID: turnID, expectedProfileID: expectedProfileID)
    } else {
        let prepared = try await store.coachCapturePreparation(at: at, expectedProfileID: expectedProfileID)
        let payload = try CoachSubmissionPayload(submissionID: turnID, text: text, attachments: photos, context: prepared.context)
        _ = try await store.captureCoachSubmission(payload, expectedSelection: prepared.ownership, expectedProfileID: expectedProfileID)
    }
    return try await exportedTurn(store, turnID: turnID, expectedProfileID: expectedProfileID)
}

func completeSelectedProfile(_ store: DiaryStore, _ id: UUID) async throws -> DiarySnapshot {
    _ = try await store.selectProfile(id)
    return try await store.snapshotForExport(expectedProfileID: id)
}

func capturedSubmission(_ store: DiaryStore, _ payload: CoachSubmissionPayload, expectedProfileID: UUID) async throws -> CoachExchangeSummary {
    let ownership = try await store.selectionOwnership(expectedProfileID: expectedProfileID)
    return try await store.captureCoachSubmission(payload, expectedSelection: ownership, expectedProfileID: expectedProfileID)
}

func reconciledSubmission(_ store: DiaryStore, submissionID: UUID, expectedManifest: CoachSubmissionManifest, expectedProfileID: UUID) async throws -> CoachCaptureReconciliation {
    let ownership = try await store.selectionOwnership(expectedProfileID: expectedProfileID)
    return try await store.reconcileCoachCapture(submissionID: submissionID, expectedManifest: expectedManifest, expectedSelection: ownership, expectedProfileID: expectedProfileID)
}

func capturedMeal(_ store: DiaryStore, text: String, photos: [MealPhoto], reviewFirst: Bool, dayID: UUID, at: Date = Date(), dateOnly: Bool = false, submissionID: UUID = UUID(), forCoach: Bool = false, expectedProfileID: UUID? = nil) async throws -> DiaryMeal {
    let ownership = try await store.selectionOwnership(expectedProfileID: expectedProfileID)
    let result = try await store.captureProjection(text: text, photos: photos, reviewFirst: reviewFirst, dayID: dayID, at: at,
        dateOnly: dateOnly, submissionID: submissionID, forCoach: forCoach, expectedSelection: ownership, expectedProfileID: ownership.identity.profileID)
    let archive = try await store.snapshotForExport(expectedProfileID: expectedProfileID)
    return try #require(archive.meals.first { $0.id == result.id })
}

func correctedMeal(_ store: DiaryStore, mealID: UUID, text: String, photos: [MealPhoto] = [], reviewFirst: Bool = false, submissionID: UUID = UUID(), forCoach: Bool = false, expectedProfileID: UUID? = nil) async throws -> DiaryMeal {
    let ownership = try await store.selectionOwnership(expectedProfileID: expectedProfileID)
    let result = try await store.correctMealProjection(mealID: mealID, text: text, photos: photos, reviewFirst: reviewFirst,
        submissionID: submissionID, forCoach: forCoach, expectedSelection: ownership, expectedProfileID: ownership.identity.profileID)
    let archive = try await store.snapshotForExport(expectedProfileID: expectedProfileID)
    return try #require(archive.meals.first { $0.id == result.id })
}
