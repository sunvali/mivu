import Foundation
import Testing
@testable import Mivu

struct ArchiveTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixture() -> DiarySnapshot {
        let profile = DiaryProfile(name: "Synthetic backup profile")
        let day = TrackingDay(localDate: "2026-10-12", timeZoneID: "Asia/Jerusalem", startAt: Date(timeIntervalSince1970: 1_792_000_000))
        let photo = MealPhoto(data: Data([1, 2, 3, 4]))
        let meal = DiaryMeal(dayID: day.id, capturedAt: day.startAt, eatenAt: day.startAt,
            photos: [photo], submissions: [MealSubmission(baseRevision: 0, text: "Synthetic apple", photoIDs: [photo.id], reviewFirst: true)])
        var snapshot = DiarySnapshot(revision: 3, profile: profile, days: [day], meals: [meal], activeDayID: day.id)
        snapshot.lineage = [UUID()]
        return snapshot
    }

    private func nextRevision(_ original: DiarySnapshot) -> DiarySnapshot {
        var next = original
        next.revision += 1
        next.lineage = Array((original.lineage ?? []).suffix(255)) + [UUID()]
        return next
    }

    @Test func archiveRoundTripRetainsPhotoPendingAndRevision() throws {
        let snapshot = fixture()
        let data = try DiaryArchive.encode(snapshot)
        #expect(try DiaryArchive.decode(data, expectedProfileID: snapshot.profile.id) == snapshot)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("bookmark"))
        #expect(!json.contains("accessToken"))
        #expect(!json.contains("refreshToken"))
    }

    @Test func malformedVersionOwnerAndReferencesAreRejected() throws {
        let snapshot = fixture()
        let encoded = try DiaryArchive.encode(snapshot)
        #expect(throws: DiaryError.invalidData) { try DiaryArchive.decode(Data(encoded.prefix(encoded.count / 2))) }
        #expect(throws: DiaryError.wrongOwner) { try DiaryArchive.decode(encoded, expectedProfileID: UUID()) }
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["version"] = 2
        #expect(throws: DiaryError.invalidData) { try DiaryArchive.decode(JSONSerialization.data(withJSONObject: object)) }
        var wrong = snapshot
        wrong.meals[0].dayID = UUID()
        #expect(throws: DiaryError.invalidData) { try DiaryArchive.encode(wrong) }
        wrong = snapshot
        wrong.meals[0].submissions[0].photoIDs = [UUID()]
        #expect(throws: DiaryError.invalidData) { try DiaryArchive.encode(wrong) }
        wrong = snapshot
        wrong.profile.id = UUID()
        object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["profileID"] = UUID().uuidString
        #expect(throws: DiaryError.wrongOwner) { try DiaryArchive.decode(JSONSerialization.data(withJSONObject: object)) }
    }

    @Test func invalidNutritionAndInputBoundsAreRejected() throws {
        var snapshot = fixture()
        snapshot.meals[0].revision = 1
        snapshot.meals[0].items = [FoodItem(name: "Synthetic apple", nutrition: NutritionValues(kcal: -1))]
        #expect(throws: DiaryError.invalidData) { try DiaryArchive.encode(snapshot) }
        snapshot.meals[0].items[0].nutrition.kcal = .infinity
        #expect(throws: DiaryError.invalidData) { try DiaryArchive.encode(snapshot) }
        snapshot.meals[0].items[0].nutrition.kcal = 1
        snapshot.meals[0].submissions[0].text = String(repeating: "a", count: 20_001)
        #expect(throws: DiaryError.invalidData) { try DiaryArchive.encode(snapshot) }
    }

    @Test func oversizedFileRejectedBeforeReading() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("oversized.json")
        #expect(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(DiaryArchive.maximumBytes + 1))
        try handle.close()
        #expect(throws: DiaryError.invalidData) { try DiaryArchive.read(file) }
    }

    @Test func securityScopeEndsExactlyOnceOnFailureAndDenialNeverRunsOperation() throws {
        var stops = 0, ran = false
        #expect(throws: DiaryError.invalidData) {
            try BackupFileAccess.withAccess(acquired: true, requiresAccess: true, stop: { stops += 1 }) {
                ran = true
                throw DiaryError.invalidData
            }
        }
        #expect(stops == 1 && ran)
        ran = false
        #expect(throws: DiaryError.persistenceFailed) {
            try BackupFileAccess.withAccess(acquired: false, requiresAccess: true, stop: { stops += 1 }) { ran = true }
        }
        #expect(stops == 1 && !ran)
        try BackupFileAccess.withAccess(acquired: false, requiresAccess: false, stop: { stops += 1 }) { ran = true }
        #expect(stops == 1 && ran)
    }

    @Test func freshStoreImportRetainsPhotosAndPending() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = fixture()
        let restored = try DiaryArchive.decode(DiaryArchive.encode(snapshot))
        let store = DiaryStore(directory: directory)
        _ = try await store.importProfile(restored)
        #expect(try await store.snapshot() == restored)
        let reopened = DiaryStore(directory: directory)
        #expect(try await reopened.selectProfile(snapshot.profile.id) == snapshot)
    }

    @Test func restoreRejectsOldSnapshotAndDeletedMeal() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiaryStore(directory: directory)
        let initial = fixture()
        _ = try await store.importProfile(initial)
        try await store.deleteMeal(initial.meals[0].id)
        await #expect(throws: DiaryError.staleArchive) { try await store.restore(initial) }
        var newer = initial
        newer.revision = 100
        await #expect(throws: DiaryError.staleArchive) { try await store.restore(newer) }
        #expect(try await store.snapshot().meals.isEmpty)
    }

    @Test func folderBackupPropagatesDeletionAndRejectsStaleQueuedWrite() async throws {
        let privateDirectory = try temporaryDirectory(), folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: privateDirectory); try? FileManager.default.removeItem(at: folder) }
        let backup = FolderBackup(directory: privateDirectory)
        let initial = fixture()
        await backup.selectProfile(initial.profile.id)
        try await backup.selectFolder(folder, profileID: initial.profile.id)
        let generation = try await backup.generation(profileID: initial.profile.id)
        try await backup.save(initial, generation: generation)
        var deleted = nextRevision(initial)
        deleted.deletedMealIDs = [initial.meals[0].id]
        deleted.meals = []
        try await backup.save(deleted, generation: generation)
        await #expect(throws: DiaryError.staleArchive) { try await backup.save(initial, generation: generation) }
        #expect(try DiaryArchive.read(folder.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id))) == deleted)
        #expect(await backup.status(profileID: initial.profile.id).savedAt != nil)
    }

    @Test func profileSwitchRejectsWrongOwnerAndKeepsStatusesSeparate() async throws {
        let privateDirectory = try temporaryDirectory(), folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: privateDirectory); try? FileManager.default.removeItem(at: folder) }
        let backup = FolderBackup(directory: privateDirectory), initial = fixture()
        await backup.selectProfile(initial.profile.id)
        try await backup.selectFolder(folder, profileID: initial.profile.id)
        let generation = try await backup.generation(profileID: initial.profile.id)
        try await backup.save(initial, generation: generation)
        let other = UUID()
        await backup.selectProfile(other)
        await #expect(throws: DiaryError.wrongOwner) { try await backup.save(initial, generation: generation) }
        #expect(!(await backup.status(profileID: other).configured))
        #expect(await backup.status(profileID: initial.profile.id).savedAt != nil)
    }

    @Test func failedWritePreservesPreviousArchiveAndStatus() async throws {
        let privateDirectory = try temporaryDirectory(), folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: privateDirectory); try? FileManager.default.removeItem(at: folder) }
        let backup = FolderBackup(directory: privateDirectory), initial = fixture()
        await backup.selectProfile(initial.profile.id)
        try await backup.selectFolder(folder, profileID: initial.profile.id)
        let generation = try await backup.generation(profileID: initial.profile.id)
        try await backup.save(initial, generation: generation)
        let priorStatus = await backup.status(profileID: initial.profile.id)
        let file = folder.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id))
        let prior = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        let next = nextRevision(initial)
        await #expect(throws: (any Error).self) { try await backup.save(next, generation: generation) }
        #expect(try Data(contentsOf: file) == prior)
        let status = await backup.status(profileID: initial.profile.id)
        #expect(status.savedAt == priorStatus.savedAt)
        #expect(status.pendingError != nil)
    }

    @Test func restartRejectsOldAndForgedHigherRevisionResurrection() async throws {
        let privateDirectory = try temporaryDirectory(), folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: privateDirectory); try? FileManager.default.removeItem(at: folder) }
        let backup = FolderBackup(directory: privateDirectory), initial = fixture()
        await backup.selectProfile(initial.profile.id)
        try await backup.selectFolder(folder, profileID: initial.profile.id)
        let generation = try await backup.generation(profileID: initial.profile.id)
        var deleted = nextRevision(initial); deleted.deletedMealIDs = [initial.meals[0].id]; deleted.meals = []
        try await backup.save(deleted, generation: generation)
        let restarted = FolderBackup(directory: privateDirectory)
        await restarted.selectProfile(initial.profile.id)
        var forged = initial; forged.revision = 100
        await #expect(throws: DiaryError.staleArchive) { try await restarted.save(forged, generation: generation) }
        #expect(try DiaryArchive.read(folder.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id))) == deleted)
    }

    @Test func metadataFailurePreservesAcknowledgementAndBlocksStaleOverwrite() async throws {
        let privateDirectory = try temporaryDirectory(), folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: privateDirectory); try? FileManager.default.removeItem(at: folder) }
        let backup = FolderBackup(directory: privateDirectory), initial = fixture()
        await backup.selectProfile(initial.profile.id)
        try await backup.selectFolder(folder, profileID: initial.profile.id)
        let generation = try await backup.generation(profileID: initial.profile.id)
        try await backup.save(initial, generation: generation)
        let priorStatus = await backup.status(profileID: initial.profile.id)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: privateDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: privateDirectory.path) }
        var deleted = nextRevision(initial); deleted.meals = []; deleted.deletedMealIDs = [initial.meals[0].id]
        await #expect(throws: (any Error).self) { try await backup.save(deleted, generation: generation) }
        let status = await backup.status(profileID: initial.profile.id)
        #expect(status.savedAt == priorStatus.savedAt)
        #expect(status.pendingError != nil)
        await #expect(throws: DiaryError.staleArchive) { try await backup.save(initial, generation: generation) }
        #expect(try DiaryArchive.read(folder.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id))) == initial)
        let reopened = FolderBackup(directory: privateDirectory)
        await reopened.selectProfile(initial.profile.id)
        await #expect(throws: (any Error).self) { try await reopened.save(initial, generation: generation) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: privateDirectory.path)
        try await backup.save(deleted, generation: generation)
        await #expect(throws: DiaryError.staleArchive) { try await reopened.save(initial, generation: generation) }
    }

    @Test func decodeRejectsInvalidNumbersReferencesAndNestedVersionBeforeRestore() async throws {
        let initial = fixture()
        let encoded = try DiaryArchive.encode(initial)
        let base = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var object = base
        var snapshot = try #require(object["snapshot"] as? [String: Any])
        snapshot["schemaVersion"] = 2; object["snapshot"] = snapshot
        #expect(throws: DiaryError.invalidData) { try DiaryArchive.decode(JSONSerialization.data(withJSONObject: object)) }
        object = base; snapshot = try #require(object["snapshot"] as? [String: Any])
        var meals = try #require(snapshot["meals"] as? [[String: Any]])
        meals[0]["dayID"] = UUID().uuidString; snapshot["meals"] = meals; object["snapshot"] = snapshot
        #expect(throws: DiaryError.invalidData) { try DiaryArchive.decode(JSONSerialization.data(withJSONObject: object)) }
        object = base; snapshot = try #require(object["snapshot"] as? [String: Any])
        snapshot["weights"] = [["id": UUID().uuidString, "dayID": initial.days[0].id.uuidString,
            "measuredAt": 1.0, "value": -1.0, "unit": "kg"]]
        object["snapshot"] = snapshot
        #expect(throws: DiaryError.invalidData) { try DiaryArchive.decode(JSONSerialization.data(withJSONObject: object)) }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiaryStore(directory: directory)
        _ = try await store.importProfile(initial)
        var malformed = initial; malformed.meals[0].dayID = UUID()
        await #expect(throws: DiaryError.invalidData) { try await store.restore(malformed) }
        #expect(try await store.snapshot() == initial)
    }

    @Test func photoDeletionReplacesInlineMediaAndSameRevisionConflictIsRejected() async throws {
        let privateDirectory = try temporaryDirectory(), folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: privateDirectory); try? FileManager.default.removeItem(at: folder) }
        let backup = FolderBackup(directory: privateDirectory), initial = fixture()
        await backup.selectProfile(initial.profile.id)
        try await backup.selectFolder(folder, profileID: initial.profile.id)
        let generation = try await backup.generation(profileID: initial.profile.id)
        try await backup.save(initial, generation: generation)
        var conflicting = initial; conflicting.profile.preferences = "Conflict"
        await #expect(throws: DiaryError.staleArchive) { try await backup.save(conflicting, generation: generation) }
        var deleted = nextRevision(initial); deleted.meals[0].photos = []
        deleted.meals[0].submissions[0].photoIDs = []
        try await backup.save(deleted, generation: generation)
        let recovered = try DiaryArchive.read(folder.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id)))
        #expect(recovered.meals[0].photos.isEmpty)
        await #expect(throws: DiaryError.staleArchive) { try await backup.save(initial, generation: generation) }
    }

    @Test func concurrentWriterFinishesAtHighestRevision() async throws {
        let privateDirectory = try temporaryDirectory(), folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: privateDirectory); try? FileManager.default.removeItem(at: folder) }
        let backup = FolderBackup(directory: privateDirectory), initial = fixture()
        await backup.selectProfile(initial.profile.id)
        try await backup.selectFolder(folder, profileID: initial.profile.id)
        let generation = try await backup.generation(profileID: initial.profile.id)
        var snapshots = [initial]
        for revision in 4...14 {
            var snapshot = nextRevision(snapshots.last!)
            snapshot.profile.preferences = String(revision)
            snapshots.append(snapshot)
        }
        await withTaskGroup(of: Void.self) { group in
            for snapshot in snapshots { group.addTask { try? await backup.save(snapshot, generation: generation) } }
        }
        let recovered = try DiaryArchive.read(folder.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id)))
        #expect(recovered.revision == 14)
        #expect(recovered.profile.preferences == "14")
    }

    @Test func configuredFolderHistoryReceivesPhotoMealAndProfileDeletion() async throws {
        let privateDirectory = try temporaryDirectory(), first = try temporaryDirectory(), second = try temporaryDirectory()
        defer { for folder in [privateDirectory, first, second] { try? FileManager.default.removeItem(at: folder) } }
        let backup = FolderBackup(directory: privateDirectory), initial = fixture()
        await backup.selectProfile(initial.profile.id)
        try await backup.selectFolder(first, profileID: initial.profile.id)
        let generation = try await backup.generation(profileID: initial.profile.id)
        try await backup.save(initial, generation: generation)
        try await backup.selectFolder(second, profileID: initial.profile.id)
        #expect(await backup.status(profileID: initial.profile.id).savedAt == nil)
        var photoDeleted = nextRevision(initial)
        photoDeleted.meals[0].photos = []; photoDeleted.meals[0].submissions[0].photoIDs = []
        try await backup.save(photoDeleted, generation: generation)
        #expect(!FileManager.default.fileExists(atPath: first.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id)).path))
        #expect(try DiaryArchive.read(second.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id))) == photoDeleted)
        var deleted = nextRevision(photoDeleted); deleted.meals = []; deleted.deletedMealIDs = [initial.meals[0].id]
        try await backup.save(deleted, generation: generation)
        #expect(try DiaryArchive.read(second.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id))) == deleted)
        for folder in [first, second] { try Data([9]).write(to: folder.appendingPathComponent("unrelated.txt")) }
        try await backup.removeProfile(initial.profile.id)
        for folder in [first, second] {
            #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id)).path))
            #expect(try Data(contentsOf: folder.appendingPathComponent("unrelated.txt")) == Data([9]))
        }
    }

    @Test func migrationWriteFailurePreservesPriorArchiveUntilDestinationAcknowledges() async throws {
        let privateDirectory = try temporaryDirectory(), first = try temporaryDirectory(), second = try temporaryDirectory()
        defer { for folder in [privateDirectory, first, second] { try? FileManager.default.removeItem(at: folder) } }
        let backup = FolderBackup(directory: privateDirectory), initial = fixture()
        await backup.selectProfile(initial.profile.id)
        try await backup.selectFolder(first, profileID: initial.profile.id)
        let generation = try await backup.generation(profileID: initial.profile.id)
        try await backup.save(initial, generation: generation)
        try await backup.selectFolder(second, profileID: initial.profile.id)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: second.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: second.path) }
        var deleted = nextRevision(initial); deleted.meals = []; deleted.deletedMealIDs = [initial.meals[0].id]
        await #expect(throws: (any Error).self) { try await backup.save(deleted, generation: generation) }
        #expect(try DiaryArchive.read(first.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id))) == initial)
        #expect(await backup.status(profileID: initial.profile.id).savedAt == nil)
        #expect(await backup.status(profileID: initial.profile.id).pendingError != nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: second.path)
        let restarted = FolderBackup(directory: privateDirectory)
        await restarted.selectProfile(initial.profile.id)
        await #expect(throws: DiaryError.staleArchive) { try await restarted.save(initial, generation: generation) }
        try await restarted.save(deleted, generation: generation)
        #expect(!FileManager.default.fileExists(atPath: first.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id)).path))
        #expect(try DiaryArchive.read(second.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id))) == deleted)
    }

    @Test func priorFolderCleanupFailureKeepsRetryHistoryAfterRestart() async throws {
        let privateDirectory = try temporaryDirectory(), first = try temporaryDirectory(), second = try temporaryDirectory()
        defer { for folder in [privateDirectory, first, second] { try? FileManager.default.removeItem(at: folder) } }
        let backup = FolderBackup(directory: privateDirectory), initial = fixture()
        await backup.selectProfile(initial.profile.id)
        try await backup.selectFolder(first, profileID: initial.profile.id)
        let generation = try await backup.generation(profileID: initial.profile.id)
        try await backup.save(initial, generation: generation)
        try await backup.selectFolder(second, profileID: initial.profile.id)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: first.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: first.path) }
        await #expect(throws: (any Error).self) { try await backup.save(initial, generation: generation) }
        #expect(try DiaryArchive.read(second.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id))) == initial)
        await #expect(throws: (any Error).self) { try await backup.removeProfile(initial.profile.id) }
        #expect(await backup.status(profileID: initial.profile.id).pendingError != nil)
        #expect(try DiaryArchive.read(first.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id))) == initial)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: first.path)
        let restarted = FolderBackup(directory: privateDirectory)
        try await restarted.removeProfile(initial.profile.id)
        for folder in [first, second] {
            #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id)).path))
        }
    }

    @Test func explicitRestoredIdentityCanChooseFolderAgain() async throws {
        let privateDirectory = try temporaryDirectory(), first = try temporaryDirectory(), second = try temporaryDirectory()
        defer { for folder in [privateDirectory, first, second] { try? FileManager.default.removeItem(at: folder) } }
        let backup = FolderBackup(directory: privateDirectory), initial = fixture()
        await backup.selectProfile(initial.profile.id)
        try await backup.selectFolder(first, profileID: initial.profile.id)
        let generation = try await backup.generation(profileID: initial.profile.id)
        try await backup.save(initial, generation: generation)
        try await backup.removeProfile(initial.profile.id)
        let store = DiaryStore(directory: privateDirectory.appendingPathComponent("Diary"))
        _ = try await store.importProfile(initial)
        await backup.selectProfile(initial.profile.id)
        let restoredGeneration = try await backup.authorizeRestoredProfile(initial.profile.id)
        #expect(restoredGeneration != generation)
        try await backup.selectFolder(second, profileID: initial.profile.id)
        await #expect(throws: DiaryError.wrongOwner) { try await backup.save(initial, generation: generation) }
        try await backup.save(initial, generation: restoredGeneration)
        let restarted = FolderBackup(directory: privateDirectory)
        await restarted.selectProfile(initial.profile.id)
        await #expect(throws: DiaryError.wrongOwner) { try await restarted.save(initial, generation: generation) }
        try await restarted.save(initial, generation: restoredGeneration)
        #expect(try DiaryArchive.read(second.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id))) == initial)
    }

    @Test func removeProfileDeletesBackupAndPreventsDelayedResurrection() async throws {
        let privateDirectory = try temporaryDirectory(), folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: privateDirectory); try? FileManager.default.removeItem(at: folder) }
        let backup = FolderBackup(directory: privateDirectory), initial = fixture()
        await backup.selectProfile(initial.profile.id)
        try await backup.selectFolder(folder, profileID: initial.profile.id)
        let generation = try await backup.generation(profileID: initial.profile.id)
        try await backup.save(initial, generation: generation)
        try await backup.removeProfile(initial.profile.id)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(FolderBackup.filename(profileID: initial.profile.id)).path))
        await backup.selectProfile(initial.profile.id)
        await #expect(throws: DiaryError.wrongOwner) { try await backup.save(initial, generation: generation) }
        #expect(!(await backup.status(profileID: initial.profile.id).configured))
        let restarted = FolderBackup(directory: privateDirectory)
        await restarted.selectProfile(initial.profile.id)
        await #expect(throws: DiaryError.wrongOwner) { try await restarted.save(initial, generation: generation) }
    }

    @Test func twoInstallationsCannotOverwriteDivergentSharedFolder() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Shared", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let oldStore = DiaryStore(directory: root.appendingPathComponent("OldDiary"))
        let newStore = DiaryStore(directory: root.appendingPathComponent("NewDiary"))
        let profile = DiaryProfile(name: "Synthetic shared owner")
        _ = try await oldStore.createProfile(profile)
        let day = try await oldStore.startDay()
        let baseline = try await oldStore.snapshot()
        let oldBackup = FolderBackup(directory: root.appendingPathComponent("OldBackup"))
        let newBackup = FolderBackup(directory: root.appendingPathComponent("NewBackup"))
        await oldBackup.selectProfile(profile.id)
        await newBackup.selectProfile(profile.id)
        try await oldBackup.selectFolder(folder, profileID: profile.id)
        try await newBackup.selectFolder(folder, profileID: profile.id)
        let oldGeneration = try await oldBackup.generation(profileID: profile.id)
        let newGeneration = try await newBackup.generation(profileID: profile.id)
        try await oldBackup.save(baseline, generation: oldGeneration)
        _ = try await newStore.importProfile(baseline)
        let newMeal = try await newStore.capture(text: "replacement phone meal", photos: [], reviewFirst: false, dayID: day.id)
        let newBranch = try await newStore.snapshot()
        try await newBackup.save(newBranch, generation: newGeneration)
        let newFile = root.appendingPathComponent("NewDiary").appendingPathComponent(profile.id.uuidString + ".json")
        let newBytes = try Data(contentsOf: newFile)
        let restingStore = DiaryStore(directory: root.appendingPathComponent("MatchingDiary"))
        _ = try await restingStore.importProfile(baseline)
        try await restingStore.restore(newBranch, expectedProfileID: profile.id)
        #expect(try await restingStore.snapshot().meals.map(\.id).contains(newMeal.id))
        let file = folder.appendingPathComponent(FolderBackup.filename(profileID: profile.id))
        let providerBytes = try Data(contentsOf: file)
        _ = try await oldStore.capture(text: "old phone meal one", photos: [], reviewFirst: false, dayID: day.id)
        _ = try await oldStore.capture(text: "old phone meal two", photos: [], reviewFirst: false, dayID: day.id)
        let oldBranch = try await oldStore.snapshot()
        let oldBytes = try Data(contentsOf: root.appendingPathComponent("OldDiary").appendingPathComponent(profile.id.uuidString + ".json"))
        #expect(oldBranch.revision > newBranch.revision)
        await #expect(throws: DiaryError.staleArchive) { try await oldBackup.save(oldBranch, generation: oldGeneration) }
        #expect(try Data(contentsOf: file) == providerBytes)
        #expect(try Data(contentsOf: root.appendingPathComponent("OldDiary").appendingPathComponent(profile.id.uuidString + ".json")) == oldBytes)
        #expect(await oldBackup.status(profileID: profile.id).pendingError != nil)
        await #expect(throws: DiaryError.staleArchive) { try await newStore.restore(oldBranch, expectedProfileID: profile.id) }
        #expect(try Data(contentsOf: newFile) == newBytes)
        #expect(try await newStore.snapshot().meals.map(\.id).contains(newMeal.id))
        let descendant = try await newStore.capture(text: "follow-up on replacement phone", photos: [], reviewFirst: false, dayID: day.id)
        try await newBackup.save(try await newStore.snapshot(), generation: newGeneration)
        #expect(try DiaryArchive.read(file).meals.map(\.id).contains(descendant.id))
    }

    @Test func changingDestinationClearsAckUntilSuccessfulWriteAndSameFolderKeepsIt() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let backup = FolderBackup(directory: root.appendingPathComponent("Metadata"))
        let snapshot = fixture()
        await backup.selectProfile(snapshot.profile.id)
        try await backup.selectFolder(first, profileID: snapshot.profile.id)
        let generation = try await backup.generation(profileID: snapshot.profile.id)
        try await backup.save(snapshot, generation: generation)
        let ack = try #require(await backup.status(profileID: snapshot.profile.id).savedAt)
        try await backup.selectFolder(first, profileID: snapshot.profile.id)
        #expect(await backup.status(profileID: snapshot.profile.id).savedAt == ack)
        try await backup.selectFolder(second, profileID: snapshot.profile.id)
        #expect(await backup.status(profileID: snapshot.profile.id).savedAt == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: second.path)
        await #expect(throws: (any Error).self) { try await backup.save(snapshot, generation: generation) }
        #expect(await backup.status(profileID: snapshot.profile.id).savedAt == nil)
        #expect(await backup.status(profileID: snapshot.profile.id).pendingError != nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: second.path)
        try await backup.save(snapshot, generation: generation)
        #expect(await backup.status(profileID: snapshot.profile.id).savedAt != nil)
        try await backup.removeProfile(snapshot.profile.id)
        #expect(!FileManager.default.fileExists(atPath: second.appendingPathComponent(FolderBackup.filename(profileID: snapshot.profile.id)).path))
    }

    @Test func legacyMetadataTimestampCannotClaimCurrentFolder() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let metadata = root.appendingPathComponent("Metadata")
        let backup = FolderBackup(directory: metadata)
        let snapshot = fixture()
        await backup.selectProfile(snapshot.profile.id)
        try await backup.selectFolder(first, profileID: snapshot.profile.id)
        let generation = try await backup.generation(profileID: snapshot.profile.id)
        try await backup.save(snapshot, generation: generation)
        let file = metadata.appendingPathComponent(snapshot.profile.id.uuidString + ".backup.json")
        let former = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        try await backup.selectFolder(second, profileID: snapshot.profile.id)
        var legacy = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        legacy["savedAt"] = former["savedAt"]
        legacy.removeValue(forKey: "acknowledgedBookmark")
        try JSONSerialization.data(withJSONObject: legacy).write(to: file)
        let restarted = FolderBackup(directory: metadata)
        #expect(await restarted.status(profileID: snapshot.profile.id).savedAt == nil)
    }

    @Test func legacySnapshotCannotReplaceProviderBytes() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Shared", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var legacyJSON = try #require(JSONSerialization.jsonObject(with: DiaryArchive.encode(fixture())) as? [String: Any])
        var legacySnapshot = try #require(legacyJSON["snapshot"] as? [String: Any])
        legacySnapshot.removeValue(forKey: "lineage")
        legacyJSON["snapshot"] = legacySnapshot
        let legacy = try DiaryArchive.decode(JSONSerialization.data(withJSONObject: legacyJSON))
        #expect(legacy.lineage == nil)
        let backup = FolderBackup(directory: root.appendingPathComponent("Metadata"))
        await backup.selectProfile(legacy.profile.id)
        try await backup.selectFolder(folder, profileID: legacy.profile.id)
        let generation = try await backup.generation(profileID: legacy.profile.id)
        try await backup.save(legacy, generation: generation)
        let file = folder.appendingPathComponent(FolderBackup.filename(profileID: legacy.profile.id))
        let providerBytes = try Data(contentsOf: file)
        let store = DiaryStore(directory: root.appendingPathComponent("Diary"))
        _ = try await store.importProfile(legacy)
        try await store.updateProfile(DiaryProfile(id: legacy.profile.id, name: "Edited synthetic"))
        await #expect(throws: DiaryError.staleArchive) { try await backup.save(try await store.snapshot(), generation: generation) }
        #expect(try Data(contentsOf: file) == providerBytes)
        var unproven = legacy
        unproven.revision += 2
        await #expect(throws: DiaryError.staleArchive) { try await store.restore(unproven) }
        await #expect(throws: DiaryError.staleArchive) { try await backup.removeProfile(legacy.profile.id) }
        #expect(try Data(contentsOf: file) == providerBytes)
    }

    @Test func prunedLineageFailsClosed() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Shared", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let backup = FolderBackup(directory: root.appendingPathComponent("Metadata"))
        let original = fixture()
        await backup.selectProfile(original.profile.id)
        try await backup.selectFolder(folder, profileID: original.profile.id)
        let generation = try await backup.generation(profileID: original.profile.id)
        try await backup.save(original, generation: generation)
        let file = folder.appendingPathComponent(FolderBackup.filename(profileID: original.profile.id))
        let priorBytes = try Data(contentsOf: file)
        var pruned = original
        pruned.revision += 257
        pruned.lineage = (0..<256).map { _ in UUID() }
        pruned.profile.preferences = "Many later edits"
        await #expect(throws: DiaryError.staleArchive) { try await backup.save(pruned, generation: generation) }
        #expect(try Data(contentsOf: file) == priorBytes)
    }

    @Test func migrationCleanupPreservesAnotherInstallationsAdvance() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let oldStore = DiaryStore(directory: root.appendingPathComponent("OldDiary"))
        let newStore = DiaryStore(directory: root.appendingPathComponent("NewDiary"))
        let profile = DiaryProfile(name: "Synthetic cleanup owner")
        _ = try await oldStore.createProfile(profile)
        let day = try await oldStore.startDay()
        let baseline = try await oldStore.snapshot()
        let oldBackup = FolderBackup(directory: root.appendingPathComponent("OldBackup"))
        let newBackup = FolderBackup(directory: root.appendingPathComponent("NewBackup"))
        await oldBackup.selectProfile(profile.id)
        await newBackup.selectProfile(profile.id)
        try await oldBackup.selectFolder(first, profileID: profile.id)
        let oldGeneration = try await oldBackup.generation(profileID: profile.id)
        try await oldBackup.save(baseline, generation: oldGeneration)
        _ = try await newStore.importProfile(baseline)
        try await newBackup.selectFolder(first, profileID: profile.id)
        let newGeneration = try await newBackup.generation(profileID: profile.id)
        _ = try await newStore.capture(text: "new phone meal", photos: [], reviewFirst: false, dayID: day.id)
        try await newBackup.save(try await newStore.snapshot(), generation: newGeneration)
        let firstFile = first.appendingPathComponent(FolderBackup.filename(profileID: profile.id))
        let advancedBytes = try Data(contentsOf: firstFile)
        try await oldBackup.selectFolder(second, profileID: profile.id)
        await #expect(throws: DiaryError.staleArchive) { try await oldBackup.save(baseline, generation: oldGeneration) }
        #expect(try Data(contentsOf: firstFile) == advancedBytes)
        #expect(try DiaryArchive.read(second.appendingPathComponent(FolderBackup.filename(profileID: profile.id))) == baseline)
        let status = await oldBackup.status(profileID: profile.id)
        #expect(status.savedAt != nil && status.pendingError != nil)
        let restarted = FolderBackup(directory: root.appendingPathComponent("OldBackup"))
        await restarted.selectProfile(profile.id)
        await #expect(throws: DiaryError.staleArchive) { try await restarted.save(baseline, generation: oldGeneration) }
        #expect(try Data(contentsOf: firstFile) == advancedBytes)
    }

    @Test func profileDeletionPreservesUnseenSharedFolderAdvanceAndLocalDiary() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = root.appendingPathComponent("Shared", isDirectory: true)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        let oldStore = DiaryStore(directory: root.appendingPathComponent("OldDiary"))
        let newStore = DiaryStore(directory: root.appendingPathComponent("NewDiary"))
        let profile = DiaryProfile(name: "Synthetic deletion owner")
        _ = try await oldStore.createProfile(profile)
        let day = try await oldStore.startDay()
        let baseline = try await oldStore.snapshot()
        let oldBackup = FolderBackup(directory: root.appendingPathComponent("OldBackup"))
        let newBackup = FolderBackup(directory: root.appendingPathComponent("NewBackup"))
        await oldBackup.selectProfile(profile.id)
        await newBackup.selectProfile(profile.id)
        try await oldBackup.selectFolder(shared, profileID: profile.id)
        let oldGeneration = try await oldBackup.generation(profileID: profile.id)
        try await oldBackup.save(baseline, generation: oldGeneration)
        _ = try await newStore.importProfile(baseline)
        try await newBackup.selectFolder(shared, profileID: profile.id)
        let newGeneration = try await newBackup.generation(profileID: profile.id)
        _ = try await newStore.capture(text: "retained on new phone", photos: [], reviewFirst: false, dayID: day.id)
        try await newBackup.save(try await newStore.snapshot(), generation: newGeneration)
        let file = shared.appendingPathComponent(FolderBackup.filename(profileID: profile.id))
        let providerBytes = try Data(contentsOf: file)
        let localFile = root.appendingPathComponent("OldDiary").appendingPathComponent(profile.id.uuidString + ".json")
        let localBytes = try Data(contentsOf: localFile)
        await #expect(throws: DiaryError.staleArchive) { try await oldBackup.removeProfile(profile.id) }
        #expect(try Data(contentsOf: file) == providerBytes)
        #expect(try Data(contentsOf: localFile) == localBytes)
        let failedStatus = await oldBackup.status(profileID: profile.id)
        #expect(failedStatus.configured && failedStatus.savedAt == nil && failedStatus.pendingError != nil)
        let restarted = FolderBackup(directory: root.appendingPathComponent("OldBackup"))
        await restarted.selectProfile(profile.id)
        let recoveredGeneration = try await restarted.generation(profileID: profile.id)
        #expect(recoveredGeneration != oldGeneration)
        await #expect(throws: DiaryError.wrongOwner) { try await restarted.save(baseline, generation: oldGeneration) }
        let freshFolder = root.appendingPathComponent("Fresh", isDirectory: true)
        try FileManager.default.createDirectory(at: freshFolder, withIntermediateDirectories: true)
        try await restarted.selectFolder(freshFolder, profileID: profile.id)
        await #expect(throws: DiaryError.staleArchive) { try await restarted.save(baseline, generation: recoveredGeneration) }
        let freshFile = freshFolder.appendingPathComponent(FolderBackup.filename(profileID: profile.id))
        #expect(try DiaryArchive.read(freshFile) == baseline)
        let currentStatus = await restarted.status(profileID: profile.id)
        #expect(currentStatus.savedAt != nil && currentStatus.pendingError != nil)
        let restartedAgain = FolderBackup(directory: root.appendingPathComponent("OldBackup"))
        await restartedAgain.selectProfile(profile.id)
        #expect(try await restartedAgain.generation(profileID: profile.id) == recoveredGeneration)
        await #expect(throws: DiaryError.wrongOwner) { try await restartedAgain.save(baseline, generation: oldGeneration) }
        await #expect(throws: DiaryError.staleArchive) { try await restartedAgain.save(baseline, generation: recoveredGeneration) }
        #expect(try DiaryArchive.read(freshFile) == baseline)
        #expect(try Data(contentsOf: file) == providerBytes)
        #expect(try Data(contentsOf: localFile) == localBytes)
    }
}
