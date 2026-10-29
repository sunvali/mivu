import Foundation
import SQLite3

/// What a destructive Coach write removed, held briefly so Undo can recreate it under new IDs.
enum CoachDeletedSnapshot: Codable, Sendable {
    case meal(DiaryMeal, items: [FoodItem], photos: [MealPhoto])
    case photo(mealID: UUID, MealPhoto)
    case weight(WeightEntry)
    case workout(WorkoutSession)
}

let coachDeletedUndoSeconds: TimeInterval = 600

extension DiaryDatabase {
    /// Erases held copies past the window; with `newestTurnID`, also those older than the turn before it.
    func purgeDeletedUndo(now: Date, newestTurnID: UUID? = nil) throws {
        try execute("DELETE FROM coach_undo_deleted WHERE createdAt < ?", [.real(now.timeIntervalSinceReferenceDate - coachDeletedUndoSeconds)])
        guard let newestTurnID else { return }
        try execute("""
            DELETE FROM coach_undo_deleted WHERE turnID IN (SELECT turnID FROM coach_index WHERE sequence <
                (SELECT MAX(sequence) FROM coach_index WHERE turnID != ?))
            """, [.text(newestTurnID.uuidString)])
    }
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
    /// The card offers Undo only until the next message or ten minutes; an undone copy still reads as undone.
    func deletedUndoState(_ key: String, now: Date) throws -> CoachUndoState? {
        let statement = try database.mutationStatement("""
            SELECT d.undone, d.createdAt, EXISTS(SELECT 1 FROM coach_index t JOIN coach_index n ON n.sequence > t.sequence WHERE t.turnID = d.turnID)
            FROM coach_undo_deleted d WHERE d.operationKey = ?
            """, [.text(key)])
        defer { sqlite3_finalize(statement) }
        guard try database.mutationStep(statement) else { return nil }
        if sqlite3_column_int64(statement, 0) != 0 { return .undone }
        let fresh = now.timeIntervalSinceReferenceDate - sqlite3_column_double(statement, 1) <= coachDeletedUndoSeconds
        return fresh && sqlite3_column_int64(statement, 2) == 0 ? .available : nil
    }
    func isHeldDelete(_ key: String) throws -> Bool {
        try database.mutationInteger("SELECT COUNT(*) FROM coach_undo_deleted WHERE operationKey = ?", [.text(key)]) == 1
    }
    /// Asking Pip may still undo from the very next message, after the card's button has gone.
    func deletedUndoUsable(_ key: String, now: Date, turn: CoachTurn) throws -> Bool {
        try database.mutationInteger("""
            SELECT COUNT(*) FROM coach_undo_deleted d JOIN coach_index t ON t.turnID = d.turnID JOIN coach_index c ON c.turnID = ?
            WHERE d.operationKey = ? AND d.undone = 0 AND d.createdAt >= ?
              AND NOT EXISTS (SELECT 1 FROM coach_index m WHERE m.sequence > t.sequence AND m.sequence < c.sequence)
            """, [.text(turn.id.uuidString), .text(key), .real(now.timeIntervalSinceReferenceDate - coachDeletedUndoSeconds)]) == 1
    }
    enum Restored { case meal(UUID), weight(UUID), workout(UUID) }
    /// Recreates the held record under new IDs, so tombstones never shrink; never overwrites what exists now.
    func undoDeleted(_ key: String) throws -> Restored {
        let statement = try database.mutationStatement("SELECT payload, undone FROM coach_undo_deleted WHERE operationKey = ?", [.text(key)])
        defer { sqlite3_finalize(statement) }
        guard try database.mutationStep(statement) else { throw DiaryError.notFound }
        guard sqlite3_column_int64(statement, 1) == 0 else { throw DiaryError.staleRevision }
        let restored: Restored
        switch try JSONDecoder().decode(CoachDeletedSnapshot.self, from: database.mutationBlob(statement, 0)) {
        case .meal(var meal, let items, let photos):
            // A meal row starts itemless at revision 0; items come next, then its own revision.
            let revision = meal.revision; meal.id = UUID(); meal.revision = 0
            try insertMeal(meal); try replaceItems(items, mealID: meal.id)
            meal.revision = revision; try saveMeal(meal)
            for photo in photos { try insertPhoto(photo, owner: .meal(meal.id)) }
            restored = .meal(meal.id)
        case .photo(let mealID, let photo):
            try insertPhoto(photo, owner: .meal(mealID)); restored = .meal(mealID)
        case .weight(var weight):
            if let dayID = weight.dayID, try self.weight(on: dayID) != nil { throw DiaryError.staleRevision }
            weight.id = UUID(); try saveWeight(weight); restored = .weight(weight.id)
        case .workout(var workout):
            workout.id = UUID(); try saveWorkout(workout); restored = .workout(workout.id)
        }
        let id: UUID = switch restored { case .meal(let id), .weight(let id), .workout(let id): id }
        try database.execute("UPDATE coach_undo_deleted SET undone = 1, restoredID = ? WHERE operationKey = ?", [.text(id.uuidString), .text(key)])
        return restored
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
