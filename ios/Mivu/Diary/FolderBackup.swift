import Foundation

struct FolderBackupStatus: Equatable, Sendable {
    var configured = false
    var savedAt: Date? = nil
    var pendingError: String? = nil
}

/// The lock covers metadata eligibility and persistence, never provider access or an await.
fileprivate final class FolderBackupFence: @unchecked Sendable {
    let lock = NSRecursiveLock()
    var version: UInt64 = 0
    var acknowledged: (UUID, FolderBackup.Configuration)?
}

struct FolderBackupAcknowledgement: Sendable {
    fileprivate let fence: FolderBackupFence
    fileprivate let version: UInt64
    fileprivate let profileID: UUID
    fileprivate let configuration: FolderBackup.Configuration
    fileprivate let directory: URL
    fileprivate let beforeWrite: @Sendable (URL) throws -> Void

    func commit() throws {
        fence.lock.lock(); defer { fence.lock.unlock() }
        guard fence.version == version else { throw DiaryError.wrongOwner }
        try Task.checkCancellation()
        try beforeWrite(directory.appendingPathComponent(profileID.uuidString + ".backup.json"))
        try FolderBackup.persistConfiguration(configuration, profileID: profileID, directory: directory)
        fence.acknowledged = (profileID, configuration)
        fence.version &+= 1
    }
}

actor FolderBackup {
    fileprivate struct Configuration: Codable, Sendable {
        var bookmark: Data?
        var previousBookmarks: [Data]? = nil
        var generation: UUID? = UUID()
        var savedAt: Date? = nil
        var acknowledgedBookmark: Data? = nil
        var acknowledgedHeads: [String: UUID]? = nil
        var revision: Int? = nil
        var deletedMealIDs: [UUID] = []
        var pendingError: String? = nil
        var retired = false
        var destinations: [Data] { (bookmark.map { [$0] } ?? []) + (previousBookmarks ?? []) }
    }
    private struct Intent {
        var snapshot: DiarySnapshot
        var configuration: Configuration
        var version: UInt64
    }
    private let directory: URL
    private let fence = FolderBackupFence()
    private var selectedProfileID: UUID?
    private var configurations: [UUID: Configuration] = [:]
    private let beforeAcknowledgementWrite: @Sendable (URL) throws -> Void
    init(directory: URL, beforeAcknowledgementWrite: @escaping @Sendable (URL) throws -> Void = { _ in }) {
        self.directory = directory; self.beforeAcknowledgementWrite = beforeAcknowledgementWrite
    }

    private func metadata<Value>(_ operation: () throws -> Value) rethrows -> Value {
        fence.lock.lock(); defer { fence.lock.unlock() }
        if let (profileID, configuration) = fence.acknowledged {
            configurations[profileID] = configuration
            fence.acknowledged = nil
        }
        return try operation()
    }

    static func filename(profileID: UUID) -> String { "mivu-" + profileID.uuidString + ".json" }
    func selectProfile(_ profileID: UUID?) {
        metadata {
            if selectedProfileID != profileID { fence.version &+= 1 }
            selectedProfileID = profileID
        }
    }

    /// Capture this token before scheduling work, never inside an already queued job.
    func generation(profileID: UUID) throws -> UUID {
        try metadata {
            guard selectedProfileID == profileID else { throw DiaryError.wrongOwner }
            var configuration = try self.configuration(profileID) ?? Configuration()
            guard !configuration.retired else { throw DiaryError.wrongOwner }
            if configuration.generation == nil { configuration.generation = UUID(); fence.version &+= 1 }
            try persist(configuration, profileID: profileID)
            configurations[profileID] = configuration
            return configuration.generation!
        }
    }

    func authorizeRestoredProfile(_ profileID: UUID) throws -> UUID {
        let retired = try metadata {
            guard selectedProfileID == profileID else { throw DiaryError.wrongOwner }
            return try configuration(profileID)?.retired == true
        }
        if retired { try removeProfile(profileID) }
        return try metadata {
            var configuration = try self.configuration(profileID) ?? Configuration()
            if retired { configuration = Configuration() }
            configuration.generation = UUID()
            try persist(configuration, profileID: profileID)
            configurations[profileID] = configuration; fence.version &+= 1
            return configuration.generation!
        }
    }

    func status(profileID: UUID) -> FolderBackupStatus {
        do {
            return try metadata {
                guard let configuration = try configuration(profileID) else { return FolderBackupStatus() }
                let acknowledged = !configuration.retired && configuration.bookmark.flatMap { try? resolve($0).standardizedFileURL }
                    == configuration.acknowledgedBookmark.flatMap { try? resolve($0).standardizedFileURL }
                    && configuration.acknowledgedBookmark != nil
                return FolderBackupStatus(configured: configuration.bookmark != nil && !configuration.retired,
                    savedAt: acknowledged ? configuration.savedAt : nil, pendingError: configuration.pendingError)
            }
        } catch { return FolderBackupStatus(pendingError: DiaryError.persistenceFailed.localizedDescription) }
    }

    func selectFolder(_ url: URL, profileID: UUID) throws {
        let bookmark = try BackupFileAccess.withAccess(to: url) {
            guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw DiaryError.invalidData }
            #if os(macOS)
            return try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            return try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
            #endif
        }
        try metadata {
            guard selectedProfileID == profileID else { throw DiaryError.wrongOwner }
            var configuration = try self.configuration(profileID) ?? Configuration()
            guard !configuration.retired else { throw DiaryError.wrongOwner }
            let sameFolder = configuration.bookmark.flatMap { try? resolve($0).standardizedFileURL } == url.standardizedFileURL
            if let prior = configuration.bookmark, !sameFolder {
                configuration.previousBookmarks = (configuration.previousBookmarks ?? []) + [prior]
            }
            configuration.previousBookmarks = (configuration.previousBookmarks ?? []).filter { (try? resolve($0).standardizedFileURL) != url.standardizedFileURL }
            guard configuration.destinations.count <= 100 else { throw DiaryError.invalidData }
            let formerBookmark = configuration.bookmark
            configuration.bookmark = bookmark
            if sameFolder, let formerBookmark, let head = configuration.acknowledgedHeads?[formerBookmark.base64EncodedString()] {
                configuration.acknowledgedHeads?[bookmark.base64EncodedString()] = head
            }
            let retainedKeys = Set(configuration.destinations.map { $0.base64EncodedString() })
            configuration.acknowledgedHeads = configuration.acknowledgedHeads?.filter { retainedKeys.contains($0.key) }
            if !sameFolder {
                configuration.savedAt = nil; configuration.acknowledgedBookmark = nil
                configuration.pendingError = "Backup to the selected folder is pending."
            }
            try persist(configuration, profileID: profileID)
            configurations[profileID] = configuration; fence.version &+= 1
        }
    }

    private func selectedConfiguration(_ profileID: UUID, generation: UUID) throws -> Configuration {
        try metadata {
            guard selectedProfileID == profileID, let configuration = try configuration(profileID),
                  !configuration.retired, configuration.generation == generation else { throw DiaryError.wrongOwner }
            return configuration
        }
    }

    private func beginSave(_ snapshot: DiarySnapshot, generation: UUID) throws -> Intent {
        try metadata {
            var configuration = try selectedConfiguration(snapshot.profile.id, generation: generation)
            guard configuration.bookmark != nil else { throw DiaryError.wrongOwner }
            guard snapshot.revision >= (configuration.revision ?? 0),
                  Set(snapshot.meals.map(\.id)).isDisjoint(with: configuration.deletedMealIDs),
                  Set(snapshot.deletedMealIDs).isSuperset(of: configuration.deletedMealIDs) else { throw DiaryError.staleArchive }
            configuration.revision = snapshot.revision
            configuration.deletedMealIDs = Array(Set(configuration.deletedMealIDs + snapshot.deletedMealIDs))
            configuration.pendingError = "Backup to the selected folder is pending."
            // A failed metadata write must not reopen older queued copies in this process.
            configurations[snapshot.profile.id] = configuration; fence.version &+= 1
            try persist(configuration, profileID: snapshot.profile.id)
            return Intent(snapshot: snapshot, configuration: configuration, version: fence.version)
        }
    }

    private func validate(_ intent: Intent) throws {
        try metadata {
            let current = try selectedConfiguration(intent.snapshot.profile.id, generation: intent.configuration.generation!)
            guard fence.version == intent.version, current.bookmark == intent.configuration.bookmark,
                  current.revision == intent.snapshot.revision else { throw DiaryError.wrongOwner }
        }
    }

    private func acknowledgement(_ intent: Intent) throws -> FolderBackupAcknowledgement {
        try metadata {
            try validate(intent)
            var configuration = try self.configuration(intent.snapshot.profile.id)!
            let key = configuration.bookmark!.base64EncodedString()
            if let head = intent.snapshot.lineage?.last {
                configuration.acknowledgedHeads = (configuration.acknowledgedHeads ?? [:]).merging([key: head]) { _, new in new }
            } else { configuration.acknowledgedHeads?.removeValue(forKey: key) }
            configuration.savedAt = Date(); configuration.acknowledgedBookmark = configuration.bookmark
            configuration.pendingError = (configuration.previousBookmarks ?? []).isEmpty ? nil : "Previous folder cleanup is pending."
            return FolderBackupAcknowledgement(fence: fence, version: intent.version, profileID: intent.snapshot.profile.id,
                configuration: configuration, directory: directory, beforeWrite: beforeAcknowledgementWrite)
        }
    }

    private func recordFailure(_ error: Error, profileID: UUID, generation: UUID, bookmark: Data?) {
        try? metadata {
            guard var current = try configuration(profileID), !current.retired,
                  current.generation == generation, current.bookmark == bookmark else { return }
            current.pendingError = error.localizedDescription
            configurations[profileID] = current
            try persist(current, profileID: profileID)
        }
    }

    private func acknowledgedConfiguration(_ intent: Intent) throws -> Configuration {
        try metadata {
            let current = try selectedConfiguration(intent.snapshot.profile.id, generation: intent.configuration.generation!)
            let key = intent.configuration.bookmark!.base64EncodedString()
            guard fence.version == intent.version &+ 1,
                  current.bookmark == intent.configuration.bookmark,
                  current.revision == intent.snapshot.revision,
                  current.savedAt != nil, current.acknowledgedBookmark == current.bookmark,
                  current.acknowledgedHeads?[key] == intent.snapshot.lineage?.last else { throw DiaryError.wrongOwner }
            return current
        }
    }

    private func cleanFormerDestinations(_ intent: Intent) throws {
        let profileID = intent.snapshot.profile.id
        let current = try acknowledgedConfiguration(intent)
        for bookmark in current.previousBookmarks ?? [] {
            try delete(profileID: profileID, folder: resolve(bookmark), expectedHead: current.acknowledgedHeads?[bookmark.base64EncodedString()])
        }
        try metadata {
            var latest = try acknowledgedConfiguration(intent)
            latest.previousBookmarks = nil
            let key = latest.bookmark!.base64EncodedString()
            latest.acknowledgedHeads = latest.acknowledgedHeads?.filter { $0.key == key }
            latest.pendingError = nil
            try persist(latest, profileID: profileID); configurations[profileID] = latest
        }
    }

    func save(_ snapshot: DiarySnapshot, generation: UUID) throws {
        let selection = try selectedConfiguration(snapshot.profile.id, generation: generation)
        guard selection.bookmark != nil else { return }
        do {
            let data = try DiaryArchive.encode(snapshot)
            let intent = try beginSave(snapshot, generation: generation)
            try write(data, snapshot: snapshot, folder: resolve(intent.configuration.bookmark!))
            try acknowledgement(intent).commit()
            try cleanFormerDestinations(intent)
        } catch {
            recordFailure(error, profileID: snapshot.profile.id, generation: generation, bookmark: selection.bookmark)
            throw error
        }
    }

    func save(_ request: DiaryExportRequest, coordinator: DiaryExportCoordinator) async throws {
        guard let generation = request.backupGeneration else { throw DiaryError.wrongOwner }
        let selection = try selectedConfiguration(request.profileID, generation: generation)
        guard selection.bookmark != nil else { return }
        var ticket: DiaryExportTicket?
        do {
            let cloned = try await coordinator.makeClone(request); ticket = cloned
            let archive = try await coordinator.archiveContent(cloned)
            let intent = try beginSave(archive.snapshot, generation: generation)
            let folder = try resolve(intent.configuration.bookmark!)
            let target = folder.appendingPathComponent(Self.filename(profileID: request.profileID))
            try await coordinator.checkpoint(.providerWrite, target)
            try Task.checkCancellation()
            try await coordinator.store.validateExportRequest(request, cloneHead: cloned.head)
            try validate(intent)
            try write(archive.data, snapshot: archive.snapshot, folder: folder)
            try await coordinator.checkpoint(.providerWritten, target)
            try Task.checkCancellation()
            try await coordinator.checkpoint(.acknowledgement, target)
            try Task.checkCancellation()
            let pending = try acknowledgement(intent)
            try await coordinator.store.acknowledgeExport(request, cloneHead: cloned.head, acknowledgement: pending)
            try await coordinator.checkpoint(.acknowledged, target)
            try cleanFormerDestinations(intent)
            try await coordinator.release(cloned); ticket = nil
        } catch {
            if let ticket { try? await coordinator.release(ticket) }
            recordFailure(error, profileID: request.profileID, generation: generation, bookmark: selection.bookmark)
            throw error
        }
    }

    func removeProfile(_ profileID: UUID) throws {
        let recoverable = try metadata {
            var configuration = try self.configuration(profileID) ?? Configuration()
            configuration.generation = UUID(); configuration.savedAt = nil; configuration.acknowledgedBookmark = nil
            configuration.pendingError = "Profile deletion is pending."
            try persist(configuration, profileID: profileID)
            configurations[profileID] = configuration; fence.version &+= 1
            return configuration
        }
        do {
            var firstError: Error?
            for bookmark in recoverable.destinations {
                do { try delete(profileID: profileID, folder: resolve(bookmark), expectedHead: recoverable.acknowledgedHeads?[bookmark.base64EncodedString()]) }
                catch { if firstError == nil { firstError = error } }
            }
            if let firstError { throw firstError }
            try metadata {
                var configuration = recoverable
                configuration.retired = true; configuration.bookmark = nil; configuration.previousBookmarks = nil
                configuration.savedAt = nil; configuration.acknowledgedBookmark = nil; configuration.acknowledgedHeads = nil; configuration.pendingError = nil
                try persist(configuration, profileID: profileID)
                configurations[profileID] = configuration; fence.version &+= 1
            }
        } catch {
            recordFailure(error, profileID: profileID, generation: recoverable.generation!, bookmark: recoverable.bookmark)
            throw error
        }
    }

    private func write(_ data: Data, snapshot: DiarySnapshot, folder: URL) throws {
        try BackupFileAccess.withAccess(to: folder) {
            let target = folder.appendingPathComponent(Self.filename(profileID: snapshot.profile.id))
            var operationError: Error?, coordinationError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { coordinated in
                do {
                    if FileManager.default.fileExists(atPath: coordinated.path) {
                        let prior = try DiaryArchive.readContents(coordinated, expectedProfileID: snapshot.profile.id)
                        guard snapshot.revision >= prior.revision,
                              Set(snapshot.meals.map(\.id)).isDisjoint(with: prior.deletedMealIDs),
                              Set(snapshot.deletedMealIDs).isSuperset(of: prior.deletedMealIDs),
                              snapshot == prior || (snapshot.revision > prior.revision && snapshot.isVerifiedSuccessor(of: prior))
                        else { throw DiaryError.staleArchive }
                    }
                    #if os(iOS)
                    try data.write(to: coordinated, options: [.atomic, .completeFileProtectionUnlessOpen])
                    #else
                    try data.write(to: coordinated, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: coordinated.path)
                    #endif
                } catch { operationError = error }
            }
            if let operationError { throw operationError }
            if coordinationError != nil { throw DiaryError.persistenceFailed }
        }
    }

    private func delete(profileID: UUID, folder: URL, expectedHead: UUID?) throws {
        try BackupFileAccess.withAccess(to: folder) {
            let target = folder.appendingPathComponent(Self.filename(profileID: profileID))
            var operationError: Error?, coordinationError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: target, options: .forDeleting, error: &coordinationError) { coordinated in
                do {
                    if FileManager.default.fileExists(atPath: coordinated.path) {
                        let prior = try DiaryArchive.readContents(coordinated, expectedProfileID: profileID)
                        guard let expectedHead, prior.lineage?.last == expectedHead else { throw DiaryError.staleArchive }
                        try FileManager.default.removeItem(at: coordinated)
                    }
                } catch { operationError = error }
            }
            if let operationError { throw operationError }
            if coordinationError != nil { throw DiaryError.persistenceFailed }
        }
    }

    private func resolve(_ bookmark: Data) throws -> URL {
        var stale = false
        #if os(macOS)
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        #else
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        #endif
        guard !stale else { throw DiaryError.persistenceFailed }
        return url
    }

    private func configuration(_ profileID: UUID) throws -> Configuration? {
        if let cached = configurations[profileID] { return cached }
        let file = metadataFile(profileID)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 5_000_000 else { throw DiaryError.invalidData }
        let loaded = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: file))
        guard loaded.destinations.count <= 101, loaded.deletedMealIDs.count <= 50_000,
              (loaded.acknowledgedHeads?.count ?? 0) <= 101 else { throw DiaryError.invalidData }
        configurations[profileID] = loaded
        return loaded
    }

    private func persist(_ configuration: Configuration, profileID: UUID) throws {
        try Self.persistConfiguration(configuration, profileID: profileID, directory: directory)
    }

    fileprivate static func persistConfiguration(_ configuration: Configuration, profileID: UUID, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(configuration)
        guard data.count <= 5_000_000 else { throw DiaryError.invalidData }
        let file = directory.appendingPathComponent(profileID.uuidString + ".backup.json")
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #endif
    }

    private func metadataFile(_ profileID: UUID) -> URL { directory.appendingPathComponent(profileID.uuidString + ".backup.json") }
}
