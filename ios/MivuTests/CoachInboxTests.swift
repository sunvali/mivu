import Foundation
import Testing
@testable import Mivu

struct CoachInboxTests {
    private let directory = URL.temporaryDirectory.appending(path: "CoachInboxTests-" + UUID().uuidString, directoryHint: .isDirectory)
    private var inbox: CoachInbox { CoachInbox(directory: directory) }
    private func entry(_ seconds: TimeInterval, text: String = "Synthetic eggs") -> CoachInbox.Entry {
        CoachInbox.Entry(id: UUID(), profileID: UUID(), text: text, capturedAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func addThenReadReturnsEntry() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = entry(100)
        try inbox.add(saved)
        #expect(inbox.entries() == [saved])
    }
    @Test func entriesAreOldestFirst() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let later = entry(200), earlier = entry(100)
        try inbox.add(later); try inbox.add(earlier)
        #expect(inbox.entries() == [earlier, later])
    }
    @Test func removeDeletesOnlyThatEntry() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let kept = entry(100), removed = entry(200)
        try inbox.add(kept); try inbox.add(removed)
        try inbox.remove(removed.id)
        #expect(inbox.entries() == [kept])
    }
    @Test func unreadableEntryIsSkippedNotDeleted() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let valid = entry(100)
        try inbox.add(valid)
        let bad = directory.appending(path: UUID().uuidString + ".json")
        try Data([1]).write(to: bad)
        #expect(inbox.entries() == [valid])
        #expect(FileManager.default.fileExists(atPath: bad.path))
    }
    // The simulator does not report file protection attributes, so the write options are checked instead.
    @Test func fileUsesFirstUnlockProtection() {
        #expect(CoachInbox.writeOptions.contains(.completeFileProtectionUntilFirstUserAuthentication))
        #expect(CoachInbox.writeOptions.contains(.atomic))
    }
}
