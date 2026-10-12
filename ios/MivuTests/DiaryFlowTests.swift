import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct DiaryFlowTests {
    private func directory() -> URL { URL.temporaryDirectory.appending(path: "MivuFlow-" + UUID().uuidString) }
    @Test func legacyHebrewPreferenceKeepsEnglishLaunchAndPreservesStoredDiary() async throws {
        let previousLanguage = DiaryLaunch.defaults.object(forKey: "appLanguage")
        DiaryLaunch.defaults.set("he", forKey: "appLanguage")
        defer { if let previousLanguage { DiaryLaunch.defaults.set(previousLanguage, forKey: "appLanguage") } else { DiaryLaunch.defaults.removeObject(forKey: "appLanguage") } }
        #expect(DiaryLaunch.language == "en")
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = DiaryStore(directory: path)
        let profile = DiaryProfile(name: "יומן סינתטי", language: "he", preferences: "Synthetic retained preference")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay()
        let meal = try await store.capture(text: "Synthetic retained meal", photos: [MealPhoto(data: Data([1, 2, 3]))], reviewFirst: true, dayID: day.id)
        let model = DiaryViewModel(store: DiaryStore(directory: path))
        await model.load(); model.enterBackground()
        let loaded = try #require(model.snapshot)
        #expect(loaded.profile == profile)
        #expect(loaded.meals.first?.id == meal.id)
        #expect(loaded.meals.first?.photos.first?.data == Data([1, 2, 3]))
        #expect(loaded.meals.first?.submissions.first?.text == "Synthetic retained meal")
    }
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
        let model = DiaryViewModel(store: store, sampleMode: true, backup: backup)
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

private actor SelectionDelay {
    private var suspended: CheckedContinuation<Void, Never>?
    private var started = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    func pause() async {
        started = true; observers.forEach { $0.resume() }; observers = []
        await withCheckedContinuation { suspended = $0 }
    }
    func waitUntilPaused() async { if !started { await withCheckedContinuation { observers.append($0) } } }
    func release() { suspended?.resume(); suspended = nil }
}

@Suite @MainActor struct DiaryProfileTransitionTests {
    @Test func delayedDoubleSelectionKeepsVisibleStoreAndBackupOwnersTogether() async throws {
        let directory = URL.temporaryDirectory.appending(path: "MivuProfile-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiaryStore(directory: directory.appending(path: "Diary"))
        let backup = FolderBackup(directory: directory.appending(path: "Backup"))
        let first = DiaryProfile(name: "Synthetic A"), second = DiaryProfile(name: "Synthetic B"), third = DiaryProfile(name: "Synthetic C")
        for profile in [first, second, third] { _ = try await store.createProfile(profile) }
        let delay = SelectionDelay()
        let model = DiaryViewModel(store: store, backup: backup, profileSelection: { id in
            let selected = try await store.selectProfile(id)
            if id == second.id { await delay.pause() }
            return selected
        })
        await model.switchProfile(first.id)
        let pending = Task { await model.switchProfile(second.id) }
        await delay.waitUntilPaused()
        #expect(model.snapshot?.profile.id == first.id)
        let rejectedWrite = await model.change { _ = try await store.startDay(expectedProfileID: first.id) }
        #expect(!rejectedWrite)
        await model.switchProfile(third.id)
        await delay.release(); await pending.value
        let visible = try #require(model.snapshot)
        let stored = try await store.snapshot()
        #expect(visible.profile.id == second.id)
        #expect(stored.profile.id == visible.profile.id)
        _ = try await backup.generation(profileID: visible.profile.id)
        await #expect(throws: DiaryError.wrongOwner) { _ = try await backup.generation(profileID: third.id) }
        #expect(await model.change { _ = try await store.startDay(expectedProfileID: visible.profile.id) })
        #expect(model.snapshot?.activeDayID != nil)
        model.enterBackground(); await model.waitForBackup()
    }

    @Test func profileCreationAndSignOutCannotOvertakeDelayedSelection() async throws {
        let directory = URL.temporaryDirectory.appending(path: "MivuProfile-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiaryStore(directory: directory.appending(path: "Diary"))
        let backup = FolderBackup(directory: directory.appending(path: "Backup"))
        let first = DiaryProfile(name: "Synthetic A"), second = DiaryProfile(name: "Synthetic B")
        _ = try await store.createProfile(first); _ = try await store.createProfile(second)
        let delay = SelectionDelay()
        let model = DiaryViewModel(store: store, backup: backup, profileSelection: { id in
            let selected = try await store.selectProfile(id)
            if id == second.id { await delay.pause() }
            return selected
        })
        await model.switchProfile(first.id)
        let pending = Task { await model.switchProfile(second.id) }
        await delay.waitUntilPaused()
        await model.createProfile(name: "Synthetic unexpected profile")
        await model.signOut()
        await delay.release(); await pending.value
        #expect(try await store.profiles().count == 2)
        #expect(model.snapshot?.profile.id == second.id)
        #expect(try await store.snapshot().profile.id == second.id)
        _ = try await backup.generation(profileID: second.id)
        await model.signOut()
        #expect(model.snapshot == nil)
        await #expect(throws: DiaryError.noProfile) { _ = try await store.snapshot() }
        await #expect(throws: DiaryError.wrongOwner) { _ = try await backup.generation(profileID: second.id) }
    }

    @Test func failedSelectionPreservesPriorDiaryAndBothActorOwners() async throws {
        let directory = URL.temporaryDirectory.appending(path: "MivuProfile-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiaryStore(directory: directory.appending(path: "Diary"))
        let backup = FolderBackup(directory: directory.appending(path: "Backup"))
        let profile = DiaryProfile(name: "Synthetic A")
        _ = try await store.createProfile(profile)
        let model = DiaryViewModel(store: store, backup: backup)
        await model.switchProfile(profile.id)
        await model.switchProfile(UUID())
        #expect(model.snapshot?.profile.id == profile.id)
        #expect(try await store.snapshot().profile.id == profile.id)
        _ = try await backup.generation(profileID: profile.id)
        #expect(model.errorMessage != nil)
        model.enterBackground(); await model.waitForBackup()
    }
}
