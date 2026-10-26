import Foundation

/// Siri prompts spoken while the phone is locked, when the diary file cannot open.
/// Readable after the first unlock since restart; the app captures them into Coach history later.
struct CoachInbox: Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let id: UUID
        let profileID: UUID
        let text: String
        let capturedAt: Date
    }

    let directory: URL
    private let legacyDirectory: URL?
    init(directory: URL, legacyDirectory: URL? = nil) { self.directory = directory; self.legacyDirectory = legacyDirectory }
    static var local: CoachInbox {
        // Beside the diary folder, never inside it; each UI test run gets its own.
        let name = DiaryLaunch.testID.map { "CoachInbox-" + $0.uuidString } ?? "CoachInbox"
        return CoachInbox(directory: DiaryLaunch.directory.deletingLastPathComponent().appending(path: name, directoryHint: .isDirectory),
            legacyDirectory: DiaryLaunch.isUITest ? nil : LocalDiaryFiles.local.documents.appending(path: "CoachInbox"))
    }

    static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    func add(_ entry: Entry) throws {
        if let legacyDirectory { try LocalDiaryFiles.prepareInbox(from: legacyDirectory, to: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try LocalDiaryFiles.excludeFromBackup(directory)
        try JSONEncoder().encode(entry).write(to: file(entry.id), options: Self.writeOptions)
        try LocalDiaryFiles.excludeFromBackup(file(entry.id))
    }

    /// Oldest first. A file that cannot be read is left in place rather than lost.
    func entries() -> [Entry] {
        do { if let legacyDirectory { try LocalDiaryFiles.prepareInbox(from: legacyDirectory, to: directory) } } catch { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Entry.self, from: Data(contentsOf: $0)) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    func remove(_ id: UUID) throws { try FileManager.default.removeItem(at: file(id)) }

    private func file(_ id: UUID) -> URL { directory.appending(path: id.uuidString + ".json") }
}
