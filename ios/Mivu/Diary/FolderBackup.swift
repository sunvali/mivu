import Foundation

struct FolderBackupStatus: Equatable, Sendable {
    var configured = false
    var savedAt: Date? = nil
    var pendingError: String? = nil
}

/// Synchronous actor operations serialize profile switching, deletion and coordinated file work.
actor FolderBackup {
    private struct Configuration: Codable {
        var bookmark: Data?
        var previousBookmarks: [Data]? = nil
        var generation: UUID? = UUID()
        var savedAt: Date? = nil
        var revision: Int? = nil
        var deletedMealIDs: [UUID] = []
        var pendingError: String? = nil
        var retired = false
        var destinations: [Data] { (bookmark.map { [$0] } ?? []) + (previousBookmarks ?? []) }
    }
    private let directory: URL
    private var selectedProfileID: UUID?
    private var configurations: [UUID: Configuration] = [:]
    init(directory: URL) { self.directory = directory }

    static func filename(profileID: UUID) -> String { "mivu-" + profileID.uuidString + ".json" }
    func selectProfile(_ profileID: UUID?) { selectedProfileID = profileID }

    /// Capture this token with the snapshot before scheduling work, never inside an already queued job.
    func generation(profileID: UUID) throws -> UUID {
        guard selectedProfileID == profileID else { throw DiaryError.wrongOwner }
        var configuration = try self.configuration(profileID) ?? Configuration()
        guard !configuration.retired else { throw DiaryError.wrongOwner }
        if configuration.generation == nil { configuration.generation = UUID() }
        try persist(configuration, profileID: profileID)
        configurations[profileID] = configuration
        return configuration.generation!
    }

    /// Only the explicitly confirmed, durable fresh-import path may reopen a deleted identity.
    func authorizeRestoredProfile(_ profileID: UUID) throws -> UUID {
        guard selectedProfileID == profileID else { throw DiaryError.wrongOwner }
        var configuration = try self.configuration(profileID) ?? Configuration()
        if configuration.retired {
            try removeProfile(profileID)
            configuration = Configuration()
        }
        configuration.generation = UUID()
        try persist(configuration, profileID: profileID)
        configurations[profileID] = configuration
        return configuration.generation!
    }

    func status(profileID: UUID) -> FolderBackupStatus {
        do {
            guard let configuration = try configuration(profileID) else { return FolderBackupStatus() }
            return FolderBackupStatus(configured: configuration.bookmark != nil && !configuration.retired,
                savedAt: configuration.savedAt, pendingError: configuration.pendingError)
        } catch { return FolderBackupStatus(pendingError: DiaryError.persistenceFailed.localizedDescription) }
    }

    func selectFolder(_ url: URL, profileID: UUID) throws {
        guard selectedProfileID == profileID else { throw DiaryError.wrongOwner }
        try BackupFileAccess.withAccess(to: url) {
            guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw DiaryError.invalidData }
            var configuration = try self.configuration(profileID) ?? Configuration()
            guard !configuration.retired else { throw DiaryError.wrongOwner }
            if let prior = configuration.bookmark,
               (try? resolve(prior).standardizedFileURL) != url.standardizedFileURL {
                configuration.previousBookmarks = (configuration.previousBookmarks ?? []) + [prior]
            }
            configuration.previousBookmarks = (configuration.previousBookmarks ?? []).filter {
                (try? resolve($0).standardizedFileURL) != url.standardizedFileURL
            }
            // Former destinations are cleanup-only; new records go only to the currently selected folder.
            guard configuration.destinations.count <= 100 else { throw DiaryError.invalidData }
            #if os(macOS)
            configuration.bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            configuration.bookmark = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
            #endif
            configuration.pendingError = "Backup to the selected folder is pending."
            try persist(configuration, profileID: profileID)
            configurations[profileID] = configuration
        }
    }

    func save(_ snapshot: DiarySnapshot, generation: UUID) throws {
        let profileID = snapshot.profile.id
        guard selectedProfileID == profileID else { throw DiaryError.wrongOwner }
        guard var configuration = try configuration(profileID), !configuration.retired,
              configuration.generation == generation else { throw DiaryError.wrongOwner }
        guard configuration.bookmark != nil else { return }
        let previousSavedAt = configuration.savedAt
        do {
            let data = try DiaryArchive.encode(snapshot)
            guard snapshot.revision >= (configuration.revision ?? 0),
                  Set(snapshot.meals.map(\.id)).isDisjoint(with: configuration.deletedMealIDs),
                  Set(snapshot.deletedMealIDs).isSuperset(of: configuration.deletedMealIDs) else { throw DiaryError.staleArchive }
            // Persist deletion/highwater intent before provider work so a failed copy cannot reopen stale jobs after restart.
            configuration.revision = snapshot.revision
            configuration.deletedMealIDs = Array(Set(configuration.deletedMealIDs + snapshot.deletedMealIDs))
            configuration.pendingError = "Backup to the selected folder is pending."
            try persist(configuration, profileID: profileID)
            configurations[profileID] = configuration
            try write(data, snapshot: snapshot, folder: resolve(configuration.bookmark!))
            var firstError: Error?
            for bookmark in configuration.previousBookmarks ?? [] {
                do { try delete(profileID: profileID, folder: resolve(bookmark)) }
                catch { if firstError == nil { firstError = error } }
            }
            if let firstError { throw firstError }
            configuration.previousBookmarks = nil
            configuration.savedAt = Date()
            configuration.pendingError = nil
            try persist(configuration, profileID: profileID)
            configurations[profileID] = configuration
        } catch {
            configuration.savedAt = previousSavedAt
            configuration.pendingError = error.localizedDescription
            configurations[profileID] = configuration
            try? persist(configuration, profileID: profileID)
            throw error
        }
    }

    func removeProfile(_ profileID: UUID) throws {
        var configuration = try self.configuration(profileID) ?? Configuration()
        configuration.retired = true
        configuration.generation = UUID()
        configurations[profileID] = configuration
        try persist(configuration, profileID: profileID)
        do {
            var firstError: Error?
            for bookmark in configuration.destinations {
                do { try delete(profileID: profileID, folder: resolve(bookmark)) }
                catch { if firstError == nil { firstError = error } }
            }
            if let firstError { throw firstError }
            configuration.bookmark = nil
            configuration.previousBookmarks = nil
            configuration.savedAt = nil
            configuration.pendingError = nil
            try persist(configuration, profileID: profileID)
            configurations[profileID] = configuration
        } catch {
            configuration.pendingError = error.localizedDescription
            configurations[profileID] = configuration
            try? persist(configuration, profileID: profileID)
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
                              snapshot.revision != prior.revision || snapshot == prior else { throw DiaryError.staleArchive }
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

    private func delete(profileID: UUID, folder: URL) throws {
        try BackupFileAccess.withAccess(to: folder) {
            let target = folder.appendingPathComponent(Self.filename(profileID: profileID))
            var operationError: Error?, coordinationError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: target, options: .forDeleting, error: &coordinationError) { coordinated in
                do {
                    if FileManager.default.fileExists(atPath: coordinated.path) {
                        _ = try DiaryArchive.readContents(coordinated, expectedProfileID: profileID)
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
        guard loaded.destinations.count <= 101, loaded.deletedMealIDs.count <= 50_000 else { throw DiaryError.invalidData }
        configurations[profileID] = loaded
        return loaded
    }

    private func persist(_ configuration: Configuration, profileID: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(configuration)
        guard data.count <= 5_000_000 else { throw DiaryError.invalidData }
        #if os(iOS)
        try data.write(to: metadataFile(profileID), options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try data.write(to: metadataFile(profileID), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadataFile(profileID).path)
        #endif
    }

    private func metadataFile(_ profileID: UUID) -> URL { directory.appendingPathComponent(profileID.uuidString + ".backup.json") }
}
