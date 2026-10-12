import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct DiaryFlowTests {
    private func directory() -> URL { URL.temporaryDirectory.appending(path: "MivuFlow-" + UUID().uuidString) }
    @Test func captureAllowsTextOrPhotoButRejectsBlankInput() {
        var draft = MealDraft()
        #expect(!draft.isValid)
        draft.text = "   \n "
        #expect(!draft.isValid)
        draft.text = "Synthetic lunch"
        #expect(draft.isValid)
        draft.text = ""; draft.photos = [Data([1])]
        #expect(draft.isValid)
    }
    @Test func failedPersistencePreservesComposerInputAndDoesNotAcknowledge() async throws {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = DiaryStore(directory: path)
        let profile = DiaryProfile(name: "Synthetic profile")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay()
        let model = DiaryViewModel(store: store); model.snapshot = try await store.snapshot()
        try FileManager.default.removeItem(at: path); try Data([1]).write(to: path)
        var draft = MealDraft(); draft.text = "Synthetic lunch"; draft.photos = [Data([1, 2, 3])]; draft.reviewFirst = true
        #expect(!(await model.capture(draft, dayID: day.id)))
        #expect(model.errorMessage != nil)
        #expect(draft.text == "Synthetic lunch")
        #expect(draft.photos == [Data([1, 2, 3])])
        #expect(model.snapshot?.meals.isEmpty == true)
        #expect(model.captureReceipt == nil)
    }
    @Test func repeatedSendUsesStableSubmissionAndReviewDoesNotCount() async throws {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = DiaryStore(directory: path)
        let profile = DiaryProfile(name: "Synthetic profile")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay()
        let model = DiaryViewModel(store: store); model.snapshot = try await store.snapshot()
        var draft = MealDraft(); draft.text = "Synthetic dinner"; draft.reviewFirst = true
        #expect(model.captureReceipt == nil)
        #expect(await model.capture(draft, dayID: day.id))
        #expect(model.captureReceipt == draft.submissionID)
        let acknowledgedReceipt = model.captureReceipt
        model.enterBackground()
        #expect(await model.capture(draft, dayID: day.id))
        #expect(model.captureReceipt == acknowledgedReceipt)
        model.enterBackground()
        try await store.processPending(expectedProfileID: profile.id)
        try await model.refresh(profileID: profile.id)
        #expect(model.snapshot?.meals.count == 1)
        #expect(model.snapshot?.meals.first?.submissions.first?.id == draft.submissionID)
        #expect(model.snapshot?.meals.first?.state == .awaitingReview)
        #expect(model.snapshot?.totals(dayID: day.id).kcal == nil)
        #expect(model.captureReceipt == acknowledgedReceipt)
    }
    @Test func profileSwitchAndSignOutHideOtherPrivateRecords() async throws {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = DiaryStore(directory: path)
        let first = DiaryProfile(name: "Synthetic A"), second = DiaryProfile(name: "Synthetic B")
        _ = try await store.createProfile(first); let day = try await store.startDay()
        _ = try await store.capture(text: "Synthetic meal", photos: [], reviewFirst: false, dayID: day.id)
        _ = try await store.createProfile(second)
        let model = DiaryViewModel(store: store); model.snapshot = try await store.selectProfile(first.id)
        await model.switchProfile(second.id)
        #expect(model.snapshot?.profile.id == second.id)
        #expect(model.snapshot?.meals.isEmpty == true)
        await model.signOut()
        #expect(model.snapshot == nil)
        await model.switchProfile(first.id)
        #expect(model.snapshot?.meals.count == 1)
        model.enterBackground()
    }
    @Test func correctionUpdatesSameMealAndBackgroundRetainsPhotoCapture() async throws {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = DiaryStore(directory: path)
        let profile = DiaryProfile(name: "Synthetic profile")
        _ = try await store.createProfile(profile); let day = try await store.startDay()
        let model = DiaryViewModel(store: store); model.snapshot = try await store.snapshot()
        var draft = MealDraft(); draft.photos = [Data([1, 2, 3])]
        #expect(await model.capture(draft, dayID: day.id)); model.enterBackground()
        try await store.processPending(expectedProfileID: profile.id); try await model.refresh(profileID: profile.id)
        let id = try #require(model.snapshot?.meals.first?.id)
        #expect(await model.change { _ = try await store.correctMeal(mealID: id, text: "half", expectedProfileID: profile.id) })
        try await store.processPending(expectedProfileID: profile.id); try await model.refresh(profileID: profile.id)
        #expect(model.snapshot?.meals.count == 1)
        #expect(model.snapshot?.meals.first?.id == id)
        #expect(model.snapshot?.meals.first?.totals.kcal == 47.5)
        let recovered = try await DiaryStore(directory: path).selectProfile(profile.id)
        #expect(recovered.meals.first?.photos.first?.data == Data([1, 2, 3]))
    }
}

#if canImport(UIKit)
import UIKit
import ImageIO

@Suite @MainActor struct DiaryPhotoTests {
    @Test func importedPhotosAreBoundedAndRemoveLocationMetadata() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1800), format: format).image { context in
            UIColor.systemRed.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1800))
        }
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(image.cgImage), [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 31.0, kCGImagePropertyGPSLongitude: 35.0]] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let stripped = try #require(PhotoImport.jpeg(bytes as Data))
        let source = try #require(CGImageSourceCreateWithData(stripped as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        #expect(properties[kCGImagePropertyGPSDictionary as String] == nil)
        #expect((properties[kCGImagePropertyPixelWidth as String] as? Int ?? Int.max) <= 1600)
        #expect(stripped.count <= 5_000_000)
    }
    @Test func invalidOrOversizedPhotoDoesNotSilentlyImport() {
        #expect(PhotoImport.jpeg(Data([1, 2, 3])) == nil)
        #expect(PhotoImport.jpeg(Data(repeating: 0, count: 40_000_001)) == nil)
        #expect(PhotoImport.jpeg(UIImage()) == nil)
    }
}
#endif

@Suite @MainActor struct DiaryRecoveryFlowTests {
    @Test func signOutRemainsSignedOutAfterRelaunchAndPreservesProfile() async throws {
        let name = "MivuFlow-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        let path = URL.temporaryDirectory.appending(path: name)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: path) }
        let first = DiaryViewModel(store: DiaryStore(directory: path), preferences: defaults)
        await first.load()
        let id = try #require(first.snapshot?.profile.id)
        await first.signOut()
        let relaunched = DiaryViewModel(store: DiaryStore(directory: path), preferences: defaults)
        await relaunched.load()
        #expect(relaunched.snapshot == nil)
        #expect(relaunched.profiles.count == 1)
        await relaunched.switchProfile(id)
        #expect(relaunched.snapshot?.profile.id == id)
        relaunched.enterBackground()
    }

    @Test func acknowledgedMutationsAutomaticallyReachBackupIncludingDeletion() async throws {
        let root = URL.temporaryDirectory.appending(path: "MivuFlow-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "Destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let store = DiaryStore(directory: root.appending(path: "Diary"))
        let backup = FolderBackup(directory: root.appending(path: "BackupSettings"))
        let model = DiaryViewModel(store: store, backup: backup)
        await model.load()
        let owner = try #require(model.snapshot?.profile.id)
        await model.selectBackupFolder(destination)
        await model.waitForBackup()
        let day = try await store.startDay(expectedProfileID: owner)
        try await model.refresh(profileID: owner)
        var draft = MealDraft(); draft.text = "Synthetic photo lunch"; draft.photos = [Data([1, 2, 3])]
        #expect(await model.capture(draft, dayID: day.id))
        await model.waitForWorker(); await model.waitForBackup()
        let file = destination.appending(path: FolderBackup.filename(profileID: owner))
        let saved = try DiaryArchive.read(file, expectedProfileID: owner)
        let meal = try #require(saved.meals.first)
        #expect(meal.photos.first?.data == Data([1, 2, 3]))
        #expect(meal.isSaved)
        #expect(model.backupStatus.savedAt != nil)
        #expect(await model.change { try await store.deleteMeal(meal.id, expectedProfileID: owner) })
        await model.waitForBackup()
        let deleted = try DiaryArchive.read(file, expectedProfileID: owner)
        #expect(deleted.meals.isEmpty)
        #expect(deleted.deletedMealIDs.contains(meal.id))
    }
}
