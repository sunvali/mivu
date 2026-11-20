import Foundation
import SQLite3
import Testing
@testable import Mivu

@Suite struct DiaryDatabaseLockTests {
    /// Each read opens its own connection; one that meets a brief write lock waits instead of reporting invalid data.
    @Test func readWaitsForAWriteThatEndsSoon() throws {
        let source = ChatHistoryFixture.lunchCorrectionSnapshot()
        let root = URL.temporaryDirectory.appending(path: "DiaryLock-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "diary.sqlite")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try DiaryDatabase(url: url, create: true).write(source, expected: nil, maximumBytes: ChatHistoryFixture.maximumBytes)

        var writer: OpaquePointer?
        #expect(sqlite3_open(url.path, &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        #expect(sqlite3_exec(writer, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
        let held = writer
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { sqlite3_exec(held, "COMMIT", nil, nil, nil) }

        #expect(try DiaryDatabase(url: url).read(maximumBytes: ChatHistoryFixture.maximumBytes).profile.id == source.profile.id)
    }
}
