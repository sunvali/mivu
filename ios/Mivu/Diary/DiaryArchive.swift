import Foundation

/// Portable profile data and inline photos; credentials and folder bookmarks never enter this envelope.
enum DiaryArchive {
    static let maximumBytes = 350_000_000
    private struct Envelope: Codable {
        var format = "mivu-diary"
        var version = 2
        var profileID: UUID
        var snapshot: DiarySnapshot
    }

    static func encode(_ snapshot: DiarySnapshot) throws -> Data {
        try snapshot.validate()
        do {
            let data = try JSONEncoder().encode(Envelope(profileID: snapshot.profile.id, snapshot: snapshot))
            guard data.count <= maximumBytes else { throw DiaryError.invalidData }
            return data
        } catch { throw DiaryError.invalidData }
    }

    static func decode(_ data: Data, expectedProfileID: UUID? = nil) throws -> DiarySnapshot {
        guard !data.isEmpty, data.count <= maximumBytes else { throw DiaryError.invalidData }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.format == "mivu-diary", [1, 2].contains(envelope.version) else { throw DiaryError.invalidData }
            guard envelope.profileID == envelope.snapshot.profile.id,
                  expectedProfileID == nil || expectedProfileID == envelope.profileID else { throw DiaryError.wrongOwner }
            try envelope.snapshot.validate()
            return envelope.snapshot
        } catch let error as DiaryError { throw error }
        catch { throw DiaryError.invalidData }
    }

    static func readContents(_ url: URL, expectedProfileID: UUID? = nil) throws -> DiarySnapshot {
        let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, let count = size.fileSize, count <= maximumBytes else { throw DiaryError.invalidData }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(1_000_000, maximumBytes + 1 - data.count)), !chunk.isEmpty {
            guard data.count + chunk.count <= maximumBytes else { throw DiaryError.invalidData }
            data.append(chunk)
        }
        return try decode(data, expectedProfileID: expectedProfileID)
    }

    static func read(_ url: URL, expectedProfileID: UUID? = nil) throws -> DiarySnapshot {
        try BackupFileAccess.withAccess(to: url) {
            var result: Result<DiarySnapshot, Error> = .failure(DiaryError.persistenceFailed)
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinated in
                result = Result {
                    try readContents(coordinated, expectedProfileID: expectedProfileID)
                }
            }
            if coordinationError != nil { throw DiaryError.persistenceFailed }
            return try result.get()
        }
    }
}

/// The only security-scoped access boundary; the resource is held through synchronous file coordination.
enum BackupFileAccess {
    static func withAccess<T>(to url: URL, _ operation: () throws -> T) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        let path = url.standardizedFileURL.path
        let ownedRoots = [NSHomeDirectory(), FileManager.default.temporaryDirectory.standardizedFileURL.path]
        let owned = ownedRoots.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        return try withAccess(acquired: accessed, requiresAccess: !owned,
            stop: { url.stopAccessingSecurityScopedResource() }, operation)
    }

    static func withAccess<T>(acquired: Bool, requiresAccess: Bool, stop: () -> Void, _ operation: () throws -> T) throws -> T {
        guard acquired || !requiresAccess else { throw DiaryError.persistenceFailed }
        defer { if acquired { stop() } }
        return try operation()
    }
}
