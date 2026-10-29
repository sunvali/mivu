import Foundation
import SQLite3

/// What a destructive Coach write removed, held briefly so Undo can recreate it under new IDs.
enum CoachDeletedSnapshot: Codable, Sendable {
    case meal(DiaryMeal, items: [FoodItem], photos: [MealPhoto])
    case photo(mealID: UUID, MealPhoto)
    case weight(WeightEntry)
    case workout(WorkoutSession)
}

extension DiaryTransaction {
    /// Nil for writes that delete nothing; an undo of a logged meal deletes the whole meal.
    func deletedSnapshot(_ write: CoachWrite) throws -> CoachDeletedSnapshot? {
        switch write {
        case .manual(.deleteMeal(let id, _), _): return try mealSnapshot(id)
        case .manual(.deletePhoto(let id, let photoID, _), _): return try mealPhoto(id, photoID).map { .photo(mealID: id, $0) }
        case .deleteWeight(let id, _): return .weight(try weight(id: id))
        case .deleteWorkout(let id, _): return .workout(try workout(id: id))
        case .manual(.undo(let key), _):
            guard let undo = try coachUndo(key), undo.before == nil else { return nil }
            return try mealSnapshot(undo.mealID)
        default: return nil
        }
    }
    func saveDeletedUndo(key: String, turnID: UUID, snapshot: CoachDeletedSnapshot, at: Date) throws {
        try database.execute("INSERT OR IGNORE INTO coach_undo_deleted(operationKey, turnID, payload, createdAt) VALUES (?, ?, ?, ?)",
            [.text(key), .text(turnID.uuidString), .blob(try JSONEncoder().encode(snapshot)), .real(at.timeIntervalSinceReferenceDate)])
    }
    func deletedUndoState(_ key: String) throws -> CoachUndoState? {
        let statement = try database.mutationStatement("SELECT undone FROM coach_undo_deleted WHERE operationKey = ?", [.text(key)])
        defer { sqlite3_finalize(statement) }
        guard try database.mutationStep(statement) else { return nil }
        return sqlite3_column_int64(statement, 0) != 0 ? .undone : .available
    }
    private func mealSnapshot(_ id: UUID) throws -> CoachDeletedSnapshot {
        let photos = try photoReferences(owner: .meal(id)).compactMap { try mealPhoto(id, $0.photoID) }
        return .meal(try mealRecord(id: id), items: try mealItems(id: id), photos: photos)
    }
    private func mealPhoto(_ mealID: UUID, _ photoID: UUID) throws -> MealPhoto? {
        guard var photo = try photoMetadata(photoID: photoID, owner: .meal(mealID))?.photo else { return nil }
        let statement = try database.mutationStatement("SELECT bytes FROM photo WHERE id = ?", [.text(mealID.uuidString + "/" + photoID.uuidString)])
        defer { sqlite3_finalize(statement) }
        guard try database.mutationStep(statement) else { return nil }
        photo.data = try database.mutationBlob(statement, 0)
        return photo
    }
}
