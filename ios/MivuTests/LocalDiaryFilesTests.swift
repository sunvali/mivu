import Foundation
import Testing
@testable import Mivu

@Suite struct LocalDiaryFilesTests {
    @Test func externalFolderOutsideOwnedRootIsRejected() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let external = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: external) }
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let backup = FolderBackup(directory: root.appending(path: "Settings")), profile = UUID()
        await backup.selectProfile(profile)
        await #expect(throws: DiaryError.self) { try await backup.selectFolder(external, profileID: profile) }
    }
    private func layout(_ root: URL) -> LocalDiaryFiles {
        LocalDiaryFiles(documents: root.appending(path: "Documents"), support: root.appending(path: "Support"))
    }
    private func excluded(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }
    @Test func firstLaunchKeepsOperationalStoragePrivate() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = layout(root)
        try files.prepare()
        #expect(try excluded(files.support))
        #expect(!LocalDiaryFiles.contains(files.diary, in: files.documents))
        #expect(!FileManager.default.fileExists(atPath: files.documents.appending(path: "Diary").path))
        try files.prepare()
    }
    @Test func migrationMovesDiaryMetadataAndInboxWithoutChangingBytes() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = layout(root), payload = Data("synthetic private content".utf8)
        for name in ["Diary", "BackupSettings", "CoachInbox"] {
            let old = files.documents.appending(path: name)
            try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
            try payload.write(to: old.appending(path: "private.json"))
        }
        try files.prepare()
        for name in ["Diary", "BackupSettings", "CoachInbox"] {
            let target = files.support.appending(path: name).appending(path: "private.json")
            #expect(try Data(contentsOf: target) == payload)
            #expect(try excluded(target))
            #expect(!FileManager.default.fileExists(atPath: files.documents.appending(path: name).path))
        }
        try files.prepare()
    }
    @Test func conflictingRootsStopAllMigrationAndPreserveBothStores() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = layout(root)
        for folder in [files.documents.appending(path: "Diary"), files.diary, files.documents.appending(path: "CoachInbox")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(folder.path.utf8).write(to: folder.appending(path: "sentinel"))
        }
        #expect(throws: LocalDiaryFiles.Failure.self) { try files.prepare() }
        for folder in [files.documents.appending(path: "Diary"), files.diary, files.documents.appending(path: "CoachInbox")] {
            #expect(try Data(contentsOf: folder.appending(path: "sentinel")) == Data(folder.path.utf8))
        }
        #expect(!FileManager.default.fileExists(atPath: files.support.appending(path: "CoachInbox").path))
    }
    @Test func failedMigrationPreservesLegacyFiles() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = layout(root), old = files.documents.appending(path: "Diary")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let payload = Data([1, 2, 3])
        try payload.write(to: old.appending(path: "sentinel"))
        try payload.write(to: files.support)
        #expect(throws: LocalDiaryFiles.Failure.self) { try files.prepare() }
        #expect(try Data(contentsOf: old.appending(path: "sentinel")) == payload)
        #expect(try Data(contentsOf: files.support) == payload)
    }
    @Test func atomicReplacementsReapplyExclusionAndKeepProtection() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString), file = root.appending(path: "health.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try LocalDiaryFiles.write(Data([1]), to: file, root: root)
        var mutable = file, values = URLResourceValues(); values.isExcludedFromBackup = false
        try mutable.setResourceValues(values)
        try LocalDiaryFiles.write(Data([2]), to: file, root: root)
        #expect(try Data(contentsOf: file) == Data([2]))
        #expect(try excluded(file) && excluded(root))
        #expect(LocalDiaryFiles.healthWriteOptions.contains(.atomic))
        #expect(LocalDiaryFiles.healthWriteOptions.contains(.completeFileProtectionUnlessOpen))
        #if os(iOS) && !targetEnvironment(simulator)
        let protection = try FileManager.default.attributesOfItem(atPath: file.path)[.protectionKey]
        let raw = (protection as? FileProtectionType)?.rawValue ?? protection as? String
        #expect(raw == FileProtectionType.completeUnlessOpen.rawValue)
        #endif
    }
    @Test func symlinkCannotRedirectOwnedWritesToExternalFolder() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let external = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: external) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let link = root.appending(path: "redirect")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        #expect(throws: DiaryError.self) { try LocalDiaryFiles.write(Data([1]), to: link.appending(path: "health.json"), root: root) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: external.path).isEmpty)
    }
    @Test func portableArchiveRetainsPhotosAndDeletionRemovesOnlyOwnedExports() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = layout(root), profile = adultProfile(name: "Synthetic local export")
        let day = TrackingDay(localDate: "2026-10-26", timeZoneID: "UTC", startAt: Date())
        let photo = MealPhoto(data: Data([1, 2, 3]))
        let meal = DiaryMeal(dayID: day.id, capturedAt: day.startAt, eatenAt: day.startAt, photos: [photo],
            submissions: [MealSubmission(baseRevision: 0, text: "Synthetic", photoIDs: [photo.id], reviewFirst: true)])
        let snapshot = DiarySnapshot(profile: profile, days: [day], meals: [meal], activeDayID: day.id)
        let archive = try files.writeArchive(DiaryArchive.encode(snapshot), profileID: profile.id)
        #expect(try DiaryArchive.read(archive) == snapshot)
        #expect(try excluded(archive) && excluded(archive.deletingLastPathComponent()))
        let other = try files.writeArchive(Data([0]), profileID: UUID())
        try files.removeExports(profileID: profile.id)
        #expect(!FileManager.default.fileExists(atPath: archive.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }
    @Test func failedLocalExportPreservesExistingPortableFiles() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = layout(root), profileID = UUID()
        try LocalDiaryFiles.createDirectory(files.exports)
        let blocker = files.exports.appending(path: profileID.uuidString), bytes = Data([4, 5, 6])
        try bytes.write(to: blocker)
        #expect(throws: (any Error).self) { try files.writeArchive(Data([9]), profileID: profileID) }
        #expect(try Data(contentsOf: blocker) == bytes)
    }
    @Test func resumedExternalBackupCannotWriteOrDeleteAndLocalBackupStarts() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let owned = root.appending(path: "Owned"), external = root.appending(path: "External")
        let metadata = owned.appending(path: "Settings"), local = owned.appending(path: "Backups")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        var snapshot = DiarySnapshot(profile: adultProfile(name: "Synthetic legacy backup")); snapshot.lineage = [UUID()]
        let legacy = FolderBackup(directory: metadata, allowedRoot: root)
        await legacy.selectProfile(snapshot.profile.id)
        try await legacy.selectFolder(external, profileID: snapshot.profile.id)
        let generation = try await legacy.generation(profileID: snapshot.profile.id)
        try await legacy.save(snapshot, generation: generation)
        let externalFile = external.appending(path: FolderBackup.filename(profileID: snapshot.profile.id))
        let originalBytes = try Data(contentsOf: externalFile)
        let worker = FolderBackup(directory: metadata, allowedRoot: owned, localFolder: local)
        await worker.selectProfile(snapshot.profile.id)
        let stopped = await worker.status(profileID: snapshot.profile.id)
        #expect(!stopped.configured && stopped.externalFoldersStopped && stopped.savedAt == nil)
        await #expect(throws: DiaryError.self) { try await worker.save(snapshot, generation: generation) }
        #expect(try Data(contentsOf: externalFile) == originalBytes)
        try await worker.configureLocal(profileID: snapshot.profile.id)
        try await worker.save(snapshot, generation: generation)
        let localFile = local.appending(path: FolderBackup.filename(profileID: snapshot.profile.id))
        #expect(try DiaryArchive.read(localFile) == snapshot)
        #expect(try excluded(localFile) && excluded(local))
        let settingsFile = metadata.appending(path: snapshot.profile.id.uuidString + ".backup.json")
        #expect(try excluded(settingsFile))
        #expect(await worker.status(profileID: snapshot.profile.id).externalFoldersStopped)
        try await worker.removeProfile(snapshot.profile.id)
        #expect(!FileManager.default.fileExists(atPath: localFile.path))
        #expect(try Data(contentsOf: externalFile) == originalBytes)
        let retained = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settingsFile)) as? [String: Any])
        #expect((retained["previousBookmarks"] as? [String])?.isEmpty == false)
    }
    @Test func externalOnlyDeletionRetainsArchiveAndBookmark() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let owned = root.appending(path: "Owned"), external = root.appending(path: "External"), metadata = owned.appending(path: "Settings")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        var snapshot = DiarySnapshot(profile: adultProfile(name: "Synthetic deletion")); snapshot.lineage = [UUID()]
        let old = FolderBackup(directory: metadata, allowedRoot: root)
        await old.selectProfile(snapshot.profile.id)
        try await old.selectFolder(external, profileID: snapshot.profile.id)
        let generation = try await old.generation(profileID: snapshot.profile.id)
        try await old.save(snapshot, generation: generation)
        let file = external.appending(path: FolderBackup.filename(profileID: snapshot.profile.id)), prior = try Data(contentsOf: file)
        let current = FolderBackup(directory: metadata, allowedRoot: owned)
        try await current.removeProfile(snapshot.profile.id)
        #expect(try Data(contentsOf: file) == prior)
        #expect(await current.status(profileID: snapshot.profile.id).externalFoldersStopped)
        #expect(!(await current.status(profileID: snapshot.profile.id).configured))
    }

    @Test func liveDatabaseAndExportCloneStayExcluded() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root), profile = adultProfile(name: "Synthetic protected diary")
        _ = try await store.createProfile(profile)
        _ = try await store.startDay()
        let file = root.appending(path: profile.id.uuidString + ".sqlite/diary.sqlite")
        #expect(try excluded(root) && excluded(file.deletingLastPathComponent()) && excluded(file))
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: root)
        let request = try await store.exportRequest(expectedProfileID: profile.id)
        let ticket = try await coordinator.makeClone(request)
        #expect(try excluded(ticket.protectedCloneURL) && excluded(ticket.protectedCloneURL.deletingLastPathComponent()))
        try await coordinator.release(ticket)
    }
    @Test func pendingOwnersKeepExclusionAfterReplacement() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = CoachInbox(directory: root.appending(path: "Inbox"))
        let entry = CoachInbox.Entry(id: UUID(), profileID: UUID(), text: "Synthetic pending prompt", capturedAt: Date())
        for _ in 0..<2 { try inbox.add(entry) }
        #expect(try excluded(inbox.directory) && excluded(inbox.directory.appending(path: entry.id.uuidString + ".json")))
        #expect(inbox.entries() == [entry])
        let jobs = ProbeJobStore(directory: root.appending(path: "Proof"))
        let job = ProbeJob(text: "Synthetic proof", image: nil, model: "synthetic", registrationID: "synthetic")
        for _ in 0..<2 { try jobs.save(job) }
        #expect(try jobs.load() == job)
        #expect(try excluded(jobs.directory) && excluded(jobs.directory.appending(path: "probe-job.json")))
    }

    @Test func firstSiriCaptureMigratesOnlyInboxBeforePrivateFolderCreation() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = layout(root), legacyFolder = files.documents.appending(path: "CoachInbox")
        let legacyInbox = CoachInbox(directory: legacyFolder)
        let old = CoachInbox.Entry(id: UUID(), profileID: UUID(), text: "Synthetic earlier prompt", capturedAt: Date(timeIntervalSince1970: 1))
        let new = CoachInbox.Entry(id: UUID(), profileID: old.profileID, text: "Synthetic locked Siri prompt", capturedAt: Date(timeIntervalSince1970: 2))
        try legacyInbox.add(old)
        let legacyDiary = files.documents.appending(path: "Diary")
        try FileManager.default.createDirectory(at: legacyDiary, withIntermediateDirectories: true)
        let sentinel = legacyDiary.appending(path: "protected-diary"), bytes = Data([7, 8, 9])
        try bytes.write(to: sentinel, options: .completeFileProtection)
        let inbox = CoachInbox(directory: files.support.appending(path: "CoachInbox"), legacyDirectory: legacyFolder)
        try inbox.add(new)
        #expect(inbox.entries() == [old, new])
        #expect(!FileManager.default.fileExists(atPath: legacyFolder.path))
        #expect(try Data(contentsOf: sentinel) == bytes)
        #expect(!FileManager.default.fileExists(atPath: files.diary.path))
        try files.prepare()
        #expect(inbox.entries() == [old, new])
        #expect(try Data(contentsOf: files.diary.appending(path: "protected-diary")) == bytes)
    }

    @Test func deletionWithoutAnyExportsIsANoOp() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let files = LocalDiaryFiles(documents: root.appending(path: "Documents"), support: root.appending(path: "Support"))
        try files.removeExports(profileID: UUID())
        #expect(!FileManager.default.fileExists(atPath: files.exports.path))
    }

    @Test func upgradeCannotExposeOperationalDocumentsThroughFileSharing() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool != true)
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool != true)
    }

}
