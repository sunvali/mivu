import Foundation

/// Operational files stay private; Documents contains only portable copies.
struct LocalDiaryFiles: Sendable {
    let documents: URL
    let support: URL
    static var local: Self { Self(documents: .documentsDirectory, support: .applicationSupportDirectory.appending(path: "Mivu")) }
    var diary: URL { support.appending(path: "Diary") }
    var backupSettings: URL { support.appending(path: "BackupSettings") }
    var backups: URL { documents.appending(path: "Backups") }
    var exports: URL { documents.appending(path: "Exports") }
    private static let migrationLock = NSRecursiveLock()

    enum Failure: LocalizedError {
        case recoveryRequired
        var errorDescription: String? { "Private storage needs recovery. Existing files are preserved. Contact support@mivuapp.com before moving or replacing either diary." }
    }

    func prepare() throws {
        try Self.migrationLock.withLock {
            let names = ["Diary", "BackupSettings", "CoachInbox"]
            let moves = names.map { (documents.appending(path: $0), support.appending(path: $0)) }
            // Preflight every root before moving anything; never merge two stores.
            var conflicting = false
            for (old, new) in moves where FileManager.default.fileExists(atPath: old.path) {
                try Self.excludeTree(old)
                if FileManager.default.fileExists(atPath: new.path) {
                    try Self.excludeTree(new); conflicting = true
                }
            }
            guard !conflicting else { throw Failure.recoveryRequired }
            do {
                try Self.createDirectory(support)
                for (old, new) in moves where FileManager.default.fileExists(atPath: old.path) {
                    try FileManager.default.moveItem(at: old, to: new)
                    try Self.excludeTree(new)
                }
                for name in ["Diary", "BackupSettings", "CoachInbox", "ConnectionProof"] {
                    let root = support.appending(path: name)
                    if FileManager.default.fileExists(atPath: root.path) {
                        if name == "ConnectionProof" { try Self.excludeTree(root) }
                        else { try Self.excludeFromBackup(root) }
                    }
                }
            } catch let error as Failure { throw error }
            catch { throw Failure.recoveryRequired }
        }
    }

    /// A locked Siri capture can migrate its first-unlock inbox without touching the protected diary.
    static func prepareInbox(from legacy: URL, to directory: URL) throws {
        try migrationLock.withLock {
            if FileManager.default.fileExists(atPath: legacy.path) {
                try excludeTree(legacy)
                guard !FileManager.default.fileExists(atPath: directory.path) else { throw Failure.recoveryRequired }
                try createDirectory(directory.deletingLastPathComponent())
                try FileManager.default.moveItem(at: legacy, to: directory)
                try excludeTree(directory)
            }
        }
    }

    static func prepareIfLive(_ directory: URL) throws {
        if directory.standardizedFileURL == local.diary.standardizedFileURL { try local.prepare() }
    }
    static func createDirectory(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw Failure.recoveryRequired }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try excludeFromBackup(directory)
    }
    static func excludeFromBackup(_ url: URL) throws {
        var url = url, values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    static func excludeTree(_ root: URL) throws {
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw Failure.recoveryRequired }
        try excludeFromBackup(root)
        guard values.isDirectory == true else { return }
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) { try excludeTree(file) }
    }
    static func contains(_ url: URL, in root: URL) -> Bool {
        guard url.isFileURL, root.isFileURL else { return false }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        return path == base || path.hasPrefix(base + "/")
    }
    static func requireOwned(_ url: URL, root: URL) throws {
        if FileManager.default.fileExists(atPath: root.path) {
            guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw DiaryError.invalidData }
        }
        guard contains(url, in: root) else { throw DiaryError.invalidData }
        // A nonexistent leaf may hide a redirect from resolvingSymlinksInPath.
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        var ancestor = url.standardizedFileURL
        while ancestor.path != "/" {
            if ancestor.path == root.standardizedFileURL.path { break }
            if FileManager.default.fileExists(atPath: ancestor.path) {
                guard contains(ancestor, in: root),
                      try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw DiaryError.invalidData }
                if ancestor.resolvingSymlinksInPath().path == canonicalRoot.path { break }
            }
            ancestor.deleteLastPathComponent()
        }
    }
    static let healthWriteOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUnlessOpen]
    static func write(_ data: Data, to file: URL, root: URL) throws {
        try requireOwned(file, root: root)
        try createDirectory(file.deletingLastPathComponent())
        #if os(iOS)
        try data.write(to: file, options: healthWriteOptions)
        #else
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #endif
        // Atomic replacement can clear resource values. The flag is advisory, not an OS guarantee.
        try excludeFromBackup(file)
    }
    func writeArchive(_ data: Data, profileID: UUID) throws -> URL {
        try Self.createDirectory(exports)
        let file = exports.appending(path: profileID.uuidString).appending(path: "Mivu diary " + UUID().uuidString + ".json")
        try Self.write(data, to: file, root: exports)
        return file
    }
    func removeExports(profileID: UUID) throws {
        let folder = exports.appending(path: profileID.uuidString)
        try Self.requireOwned(folder, root: exports)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }
}
