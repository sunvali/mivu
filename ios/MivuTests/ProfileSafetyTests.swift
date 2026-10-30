import Foundation
import Testing
@testable import Mivu

/// A diary that cannot be read right now (locked phone, failed upgrade) must never look like an empty phone.
@Suite @MainActor struct ProfileSafetyTests {
    @Test func unreadableDiaryNeverStartsANewOne() async throws {
        let root = URL.temporaryDirectory.appending(path: "ProfileSafety-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = try await DiaryStore(directory: root).createProfile(DiaryProfile(name: "Synthetic owner")).head.profile.id
        let file = root.appending(path: existing.uuidString + ".sqlite/diary.sqlite")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }

        let diary = DiaryViewModel(store: DiaryStore(directory: root))
        await diary.load(createDefaultProfile: false)
        await diary.createFirstProfile()
        #expect(diary.readModel == nil)
        #expect(try diaryFolders(root) == 1, "No second diary while the first cannot be read")

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        await diary.createFirstProfile()
        #expect(diary.readModel?.head.profile.id == existing, "Try again opens the existing diary")
        #expect(try diaryFolders(root) == 1)
    }

    @Test func lockedLaunchOpensTheSameDiaryOnceReadable() async throws {
        let root = URL.temporaryDirectory.appending(path: "ProfileSafety-" + UUID().uuidString)
        let suite = "ProfileSafety-" + UUID().uuidString, defaults = try #require(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let existing = try await DiaryStore(directory: root).createProfile(DiaryProfile(name: "Synthetic owner")).head.profile.id
        defaults.set(existing.uuidString, forKey: "diarySelectedProfile")
        let file = root.appending(path: existing.uuidString + ".sqlite/diary.sqlite")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }

        let diary = DiaryViewModel(store: DiaryStore(directory: root), preferences: defaults)
        await diary.load(createDefaultProfile: false)
        #expect(diary.readModel == nil)
        #expect(!defaults.bool(forKey: "diarySignedOut"), "A failed read is not a sign-out")
        #expect(defaults.string(forKey: "diarySelectedProfile") == existing.uuidString)

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        await diary.createFirstProfile()
        #expect(diary.readModel?.head.profile.id == existing, "Unlocking reopens the diary without the chooser")
        await diary.signOut()
        #expect(defaults.bool(forKey: "diarySignedOut"), "A real sign-out still sticks")
    }

    @Test func emptyPhoneStartsMyDiary() async throws {
        let root = URL.temporaryDirectory.appending(path: "ProfileSafety-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let diary = DiaryViewModel(store: DiaryStore(directory: root))
        await diary.load(createDefaultProfile: false)
        await diary.createFirstProfile()
        #expect(diary.readModel?.profile.name == "My diary")
        #expect(try diaryFolders(root) == 1)
    }

    private func diaryFolders(_ root: URL) throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".sqlite") }.count
    }
}
