import Foundation
import SQLite3
import Testing
@testable import Mivu

@Suite @MainActor struct DiaryDatabaseTests {
    @Test func newProfileCreationAndSelectionUseProjectionStorage() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root), profile = adultProfile(name: "Synthetic staged storage")
        _ = try await store.createProfile(profile)
        _ = try await store.selectProfile(profile.id)
        #expect(try ChatHistoryFixture.strings(file(root, profile.id), "PRAGMA user_version") == [["1"]])
        #expect(try ChatHistoryFixture.strings(file(root, profile.id), "SELECT name FROM sqlite_master WHERE name = 'storage_head'").count == 1)
    }
    private func directory() -> URL { URL.temporaryDirectory.appending(path: "Database-" + UUID().uuidString) }
    private func file(_ root: URL, _ id: UUID, _ ext: String = "sqlite") -> URL { ext == "sqlite" ? root.appendingPathComponent(id.uuidString + ".sqlite").appendingPathComponent("diary.sqlite") : root.appendingPathComponent(id.uuidString + "." + ext) }
    private func legacy(_ root: URL) throws -> DiarySnapshot {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var snapshot = DiarySnapshot(profile: adultProfile(name: "Synthetic legacy", language: "he"))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let day = TrackingDay(localDate: "2027-01-15", timeZoneID: "Asia/Jerusalem", startAt: date)
        let photo = MealPhoto(data: Data([0, 1, 255, 2]), createdAt: date, role: .after)
        let item = FoodItem(name: "Synthetic", nutrition: NutritionValues(kcal: 42), provenance: .user)
        snapshot.days = [day]; snapshot.activeDayID = day.id; snapshot.revision = 9; snapshot.lineage = [UUID(), UUID()]
        snapshot.meals = [DiaryMeal(dayID: day.id, capturedAt: date, eatenAt: date, revision: 1, items: [item], photos: [photo], submissions: [MealSubmission(baseRevision: 0, text: "Synthetic", photoIDs: [photo.id], reviewFirst: false, state: .saved)])]
        snapshot.weights = [WeightEntry(dayID: day.id, measuredAt: date, value: 70)]
        snapshot.deletedMealIDs = [UUID()]
        try JSONEncoder().encode(snapshot).write(to: file(root, snapshot.profile.id, "json"))
        return snapshot
    }
    @Test func legacyMigrationRetainsExactSnapshotAndPhotos() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try legacy(root)
        let legacyBytes = try Data(contentsOf: file(root, snapshot.profile.id, "json"))
        let store = DiaryStore(directory: root)
        #expect(try await selectedSnapshot(store, snapshot.profile.id) == snapshot)
        #expect(FileManager.default.fileExists(atPath: file(root, snapshot.profile.id).path))
        #expect(try Data(contentsOf: file(root, snapshot.profile.id, "json")) == legacyBytes)
        #expect(try await store.profiles() == [snapshot.profile])
        #expect(try await selectedSnapshot(DiaryStore(directory: root), snapshot.profile.id) == snapshot)
    }
    @Test func migrationFailureLeavesLegacySelectable() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try legacy(root)
        let bytes = try Data(contentsOf: file(root, snapshot.profile.id, "json"))
        // A selected-path collision cannot overwrite another filesystem object.
        try FileManager.default.createDirectory(at: file(root, snapshot.profile.id), withIntermediateDirectories: true)
        await #expect(throws: DiaryError.persistenceFailed) { try await DiaryStore(directory: root).selectProfile(snapshot.profile.id) }
        #expect(try Data(contentsOf: file(root, snapshot.profile.id, "json")) == bytes)
        try FileManager.default.removeItem(at: file(root, snapshot.profile.id).deletingLastPathComponent())
        #expect(try await selectedSnapshot(DiaryStore(directory: root), snapshot.profile.id) == snapshot)
    }
    @Test func corruptDatabaseNeverFallsBackToLegacy() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try legacy(root)
        _ = try await DiaryStore(directory: root).selectProfile(snapshot.profile.id)
        let corrupt = Data("broken database".utf8)
        try corrupt.write(to: file(root, snapshot.profile.id))
        await #expect(throws: DiaryError.invalidData) { try await DiaryStore(directory: root).selectProfile(snapshot.profile.id) }
        #expect(try Data(contentsOf: file(root, snapshot.profile.id)) == corrupt)
    }
    @Test func failedDatabaseCommitPreservesMemoryAndReceipt() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root)
        let profile = adultProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); let day = try await store.startDay()
        let before = try await store.snapshotForExport()
        var db: OpaquePointer?
        #expect(sqlite3_open(file(root, profile.id).path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TRIGGER reject_save BEFORE UPDATE ON storage_head BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END", nil, nil, nil) == SQLITE_OK)
        let model = DiaryViewModel(store: store); await model.load(createDefaultProfile: false)
        var draft = MealDraft(); draft.text = "Synthetic food"
        #expect(!(await model.capture(draft, dayID: day.id)))
        #expect(model.captureReceipt == nil)
        #expect(try await store.snapshotForExport() == before)
        #expect(try await selectedSnapshot(DiaryStore(directory: root), profile.id) == before)
    }
    @Test func staleDatabaseWriterCannotOverwriteNewerHead() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let first = DiaryStore(directory: root); let profile = adultProfile(name: "Synthetic")
        _ = try await first.createProfile(profile); let day = try await first.startDay()
        let stale = DiaryStore(directory: root); let old = try await stale.selectProfile(profile.id)
        _ = try await capturedMeal(first, text: "New head", photos: [], reviewFirst: false, dayID: day.id)
        let head = try await first.snapshotForExport()
        await #expect(throws: DiaryError.staleRevision) { try await capturedMeal(stale, text: "Stale", photos: [], reviewFirst: false, dayID: day.id) }
        #expect(try await stale.diaryHead(expectedProfileID: profile.id) == old.head)
        #expect(try await selectedSnapshot(DiaryStore(directory: root), profile.id) == head)
    }
    @Test func removedDatabaseDoesNotAcknowledgeSave() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root); let profile = adultProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); let day = try await store.startDay()
        let old = try await store.snapshotForExport()
        let db = file(root, profile.id), retained = root.appendingPathComponent("retained.sqlite")
        let bytes = try Data(contentsOf: db)
        try FileManager.default.moveItem(at: db, to: retained)
        await #expect(throws: DiaryError.persistenceFailed) { try await capturedMeal(store, text: "Unsaved", photos: [], reviewFirst: false, dayID: day.id) }
        await #expect(throws: DiaryError.persistenceFailed) { try await store.snapshotForExport() }
        #expect(try Data(contentsOf: retained) == bytes)
        let recovery = try ChatHistoryFixture.completeReference(databaseURL: retained)
        try recovery.validate()
        #expect(recovery == old)
        #expect(!FileManager.default.fileExists(atPath: db.path))
    }
    @Test func replacedDatabaseDoesNotAcknowledgeSave() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root); let profile = adultProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); let day = try await store.startDay()
        let old = try await store.snapshotForExport()
        let db = file(root, profile.id), replacement = root.appendingPathComponent("replacement")
        let bytes = try Data(contentsOf: db)
        try FileManager.default.copyItem(at: db, to: replacement)
        try FileManager.default.removeItem(at: db)
        try FileManager.default.moveItem(at: replacement, to: db)
        await #expect(throws: DiaryError.persistenceFailed) { try await capturedMeal(store, text: "Unsaved", photos: [], reviewFirst: false, dayID: day.id) }
        await #expect(throws: DiaryError.persistenceFailed) { try await store.snapshotForExport() }
        #expect(try Data(contentsOf: db) == bytes)
        #expect(try await selectedSnapshot(DiaryStore(directory: root), profile.id) == old)
    }
    @Test func missingSelectedDatabaseNeverResurrectsLegacy() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let old = try legacy(root)
        let store = DiaryStore(directory: root)
        _ = try await store.selectProfile(old.profile.id)
        try await store.deleteMeal(old.meals[0].id)
        let committed = try await store.snapshotForExport()
        let retained = root.appendingPathComponent("retained.sqlite")
        let bytes = try Data(contentsOf: file(root, old.profile.id))
        let legacyBytes = try Data(contentsOf: file(root, old.profile.id, "json"))
        try FileManager.default.moveItem(at: file(root, old.profile.id), to: retained)
        await #expect(throws: DiaryError.persistenceFailed) { try await DiaryStore(directory: root).selectProfile(old.profile.id) }
        await #expect(throws: DiaryError.persistenceFailed) { try await store.updateProfile(old.profile) }
        await #expect(throws: DiaryError.persistenceFailed) { try await store.snapshotForExport() }
        #expect(try Data(contentsOf: retained) == bytes)
        let recovery = try ChatHistoryFixture.completeReference(databaseURL: retained)
        try recovery.validate()
        #expect(recovery == committed)
        #expect(try Data(contentsOf: file(root, old.profile.id, "json")) == legacyBytes)
        #expect(!FileManager.default.fileExists(atPath: file(root, old.profile.id).path))
        #expect(FileManager.default.fileExists(atPath: file(root, old.profile.id).deletingLastPathComponent().path))
    }
    @Test func profileEditDoesNotRewritePhotoBlob() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let old = try legacy(root), store = DiaryStore(directory: root)
        _ = try await store.selectProfile(old.profile.id)
        var db: OpaquePointer?
        #expect(sqlite3_open(file(root, old.profile.id).path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TRIGGER reject_photo_update BEFORE UPDATE ON photo BEGIN SELECT RAISE(ABORT, 'photo changed'); END", nil, nil, nil) == SQLITE_OK)
        var profile = old.profile; profile.preferences = "Synthetic owner's preference"
        try await store.updateProfile(profile)
        let expected = try await store.snapshotForExport()
        #expect(expected.meals == old.meals)
        #expect(expected.deletedMealIDs == old.deletedMealIDs)
        #expect(try await selectedSnapshot(DiaryStore(directory: root), old.profile.id) == expected)
    }

    @Test(arguments: ["payload", "orphan"]) func corruptWorkoutRowFailsRead(kind: String) async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        var before = try legacy(root)
        before.workouts = [WorkoutSession(dayID: before.days[0].id, performedAt: before.days[0].startAt,
            timePrecision: .dateOnly, revision: 1, kind: .cardio, durationMinutes: 25,
            exercises: [], estimatedBurnKcal: nil, burnSource: nil)]
        try seedVersionZero(before, in: root)
        let path = file(root, before.profile.id)
        if kind == "payload" {
            try mutate(path, sql: "UPDATE workout SET payload = x'00'")
        } else {
            try mutate(path, sql: "PRAGMA foreign_keys = OFF; UPDATE workout SET parent = '00000000-0000-0000-0000-000000000000'")
        }
        try await rejectsCorruptStorage(root, store: DiaryStore(directory: root), before: before)
    }

    private func seedVersionZero(_ snapshot: DiarySnapshot, in root: URL) throws {
        try snapshot.validate()
        let path = file(root, snapshot.profile.id)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DiaryDatabase(url: path, create: true).write(snapshot, expected: nil, maximumBytes: 350_000_000)
        try JSONEncoder().encode(snapshot).write(to: file(root, snapshot.profile.id, "json"))
        try #require(try ChatHistoryFixture.strings(path, "PRAGMA user_version") == [["0"]])
    }

    private func mutate(_ url: URL, sql: String) throws {
        var db: OpaquePointer?
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }
    private func rejectsCorruptStorage(_ root: URL, store: DiaryStore, before: DiarySnapshot) async throws {
        let bytes = try Data(contentsOf: file(root, before.profile.id))
        let recovery = try Data(contentsOf: file(root, before.profile.id, "json"))
        await #expect(throws: DiaryError.invalidData) { try await DiaryStore(directory: root).selectProfile(before.profile.id) }
        let model = DiaryViewModel(store: store); await model.load(createDefaultProfile: false)
        var draft = MealDraft(); draft.text = "Synthetic retained input"
        #expect(!(await model.capture(draft, dayID: before.days[0].id)))
        #expect(model.captureReceipt == nil)
        #expect(model.readModel == nil)
        await #expect(throws: DiaryError.noProfile) { try await store.snapshotForExport() }
        #expect(try Data(contentsOf: file(root, before.profile.id)) == bytes)
        #expect(try Data(contentsOf: file(root, before.profile.id, "json")) == recovery)
        let archive = try JSONDecoder().decode(DiarySnapshot.self, from: recovery)
        try archive.validate()
        #expect(archive == before)
        #expect(try ChatHistoryFixture.strings(file(root, before.profile.id), "PRAGMA user_version") == [["0"]])
        #expect(try ChatHistoryFixture.strings(file(root, before.profile.id), "SELECT name FROM sqlite_master WHERE name = 'storage_head'").isEmpty)
    }
    @Test(arguments: ["orphanPhoto", "photoIdentity", "mealParent"])
    func corruptRelationalRowsNeverDisappear(kind: String) async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        var before = try legacy(root)
        let store = DiaryStore(directory: root)
        let unreferenced = MealPhoto(data: Data([9, 8, 7]))
        before.meals[0].photos.append(unreferenced)
        let otherDay = TrackingDay(localDate: "2027-01-16", timeZoneID: before.profile.timeZoneID,
            startAt: Date(timeIntervalSince1970: 1_800_100_000))
        before.days.append(otherDay); before.activeDayID = otherDay.id
        try seedVersionZero(before, in: root)
        let mealID = before.meals[0].id.uuidString
        let sql: String
        switch kind {
        case "orphanPhoto": sql = "UPDATE photo SET parent = '\(UUID().uuidString)' WHERE id = '\(mealID)/\(unreferenced.id.uuidString)'"
        case "photoIdentity": sql = "UPDATE photo SET id = '\(mealID)/\(UUID().uuidString)' WHERE id = '\(mealID)/\(unreferenced.id.uuidString)'"
        default: sql = "UPDATE meal SET parent = '\(otherDay.id.uuidString)' WHERE id = '\(mealID)'"
        }
        try mutate(file(root, before.profile.id), sql: sql)
        try await rejectsCorruptStorage(root, store: store, before: before)
    }
    @Test func oversizedPhotoMetadataIsRejectedBeforeLoadingRecords() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let old = try legacy(root)
        try seedVersionZero(old, in: root)
        // A foreign orphan is still part of the predecode budget, despite never entering a snapshot.
        try mutate(file(root, old.profile.id), sql: "INSERT INTO photo SELECT substr(id, 1, 37) || '\(UUID().uuidString)', '\(UUID().uuidString)', ordinal, payload, zeroblob(4096) FROM photo")
        let before = try Data(contentsOf: file(root, old.profile.id))
        let recovery = try Data(contentsOf: file(root, old.profile.id, "json"))
        await #expect(throws: DiaryError.invalidData) { try await DiaryStore(directory: root, maximumFileBytes: 2048).selectProfile(old.profile.id) }
        #expect(try Data(contentsOf: file(root, old.profile.id)) == before)
        #expect(try Data(contentsOf: file(root, old.profile.id, "json")) == recovery)
        #expect(try ChatHistoryFixture.strings(file(root, old.profile.id), "PRAGMA user_version") == [["0"]])
        #expect(try ChatHistoryFixture.strings(file(root, old.profile.id), "SELECT name FROM sqlite_master WHERE name = 'storage_head'").isEmpty)
    }
    @Test func excessRowsAreRejectedBeforePayloadDecoding() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let old = try legacy(root)
        try seedVersionZero(old, in: root)
        // Empty malformed blobs are individually tiny but exceed the bounded table cardinality.
        try mutate(file(root, old.profile.id), sql: "WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<10001) INSERT INTO day SELECT 'extra-' || x, x, x'7b7d' FROM n")
        let before = try Data(contentsOf: file(root, old.profile.id))
        let recovery = try Data(contentsOf: file(root, old.profile.id, "json"))
        await #expect(throws: DiaryError.invalidData) { try await DiaryStore(directory: root, maximumFileBytes: 2048).selectProfile(old.profile.id) }
        #expect(try Data(contentsOf: file(root, old.profile.id)) == before)
        #expect(try Data(contentsOf: file(root, old.profile.id, "json")) == recovery)
        #expect(try ChatHistoryFixture.strings(file(root, old.profile.id), "PRAGMA user_version") == [["0"]])
        #expect(try ChatHistoryFixture.strings(file(root, old.profile.id), "SELECT name FROM sqlite_master WHERE name = 'storage_head'").isEmpty)
    }

}


private func selectedSnapshot(_ store: DiaryStore, _ id: UUID) async throws -> DiarySnapshot {
    _ = try await store.selectProfile(id)
    return try await store.snapshotForExport(expectedProfileID: id)
}
