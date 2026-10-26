import AppIntents
import Foundation
import Testing
@testable import Mivu

@Suite struct DiaryTransferTests {
    @Test func exportsRequireLocalDeviceAuthentication() {
        #expect(ExportDiaryIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
    }
    @Test(arguments: [DiaryTransferFormat.archive, .pdf, .csv]) func portableFilesAreOwnedAndExcluded(format: DiaryTransferFormat) async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root.appending(path: "Private")), profile = adultProfile(name: "Synthetic transfer")
        _ = try await store.createProfile(profile)
        let owner = try await store.selectionOwnership(expectedProfileID: profile.id)
        let layout = LocalDiaryFiles(documents: root.appending(path: "Documents"), support: root.appending(path: "Support"))
        let files = try await DiaryTransfer.files(store: store, owner: owner, format: format, layout: layout)
        #expect(files.count == (format == .csv ? 3 : 1))
        for file in files {
            #expect(LocalDiaryFiles.contains(file, in: layout.exports))
            #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
            #expect(try Data(contentsOf: file).count > 0)
        }
        if format == .archive { #expect(try DiaryArchive.read(files[0]).profile.id == profile.id) }
    }
    @Test func staleSelectionCannotExportAnotherProfile() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root.appending(path: "Private")), first = adultProfile(name: "Synthetic first")
        _ = try await store.createProfile(first)
        let owner = try await store.selectionOwnership(expectedProfileID: first.id)
        _ = try await store.createProfile(adultProfile(name: "Synthetic second"))
        let layout = LocalDiaryFiles(documents: root.appending(path: "Documents"), support: root.appending(path: "Support"))
        await #expect(throws: DiaryError.self) { try await DiaryTransfer.files(store: store, owner: owner, format: .archive, layout: layout) }
        #expect(!FileManager.default.fileExists(atPath: layout.exports.path))
    }
    @Test func switchAwayAndBackAfterWritingRejectsAndCleansOnlyNewFiles() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root.appending(path: "Private")), profile = adultProfile(name: "Synthetic current")
        _ = try await store.createProfile(profile)
        let owner = try await store.selectionOwnership(expectedProfileID: profile.id)
        let layout = LocalDiaryFiles(documents: root.appending(path: "Documents"), support: root.appending(path: "Support"))
        let existing = try layout.writeArchive(Data("Synthetic existing export".utf8), profileID: profile.id)
        await #expect(throws: DiaryError.wrongOwner) {
            try await DiaryTransfer.files(store: store, owner: owner, format: .csv, layout: layout, checkpoint: { files in
                #expect(files.count == 3)
                await store.signOut()
                _ = try await store.selectProfile(profile.id)
            })
        }
        let enumerator = try #require(FileManager.default.enumerator(at: layout.exports, includingPropertiesForKeys: [.isRegularFileKey]))
        let remaining = try enumerator.compactMap { $0 as? URL }.filter { try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true }
        #expect(remaining == [existing])
        #expect(try Data(contentsOf: existing) == Data("Synthetic existing export".utf8))
    }

}
