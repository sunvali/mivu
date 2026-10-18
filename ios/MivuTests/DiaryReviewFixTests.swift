import Foundation
import Testing
@testable import Mivu

private actor DelayedPhoto {
    private var continuation: CheckedContinuation<Data, Never>?
    private var requested = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func load() async -> Data {
        requested = true
        waiters.forEach { $0.resume() }; waiters = []
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilRequested() async {
        if !requested { await withCheckedContinuation { waiters.append($0) } }
    }
    func complete(_ data: Data) { continuation?.resume(returning: data); continuation = nil }
}

@Suite @MainActor struct DiaryReviewFixTests {
    @Test func selectedSlowPhotoPreventsTextCaptureUntilPhotoIsIncluded() async throws {
        let path = URL.temporaryDirectory.appending(path: "MivuReview-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = DiaryStore(directory: path)
        let model = DiaryViewModel(store: store); await model.load()
        let day = try await store.startDay(); try await model.refresh(profileID: try #require(model.readModel?.profile.id))
        var draft = MealDraft(); draft.text = "Synthetic text and selected photo"
        let preparation = PhotoPreparation(), loader = DelayedPhoto(), bytes = Data([10, 20, 30])
        let generation = preparation.begin()
        let importing = Task { @MainActor in
            if let photo = try await preparation.load(generation, using: { await loader.load() }) { draft.photos.append(photo) }
            preparation.finish(generation)
        }
        await loader.waitUntilRequested()
        #expect(preparation.isPreparing)
        #expect(!(await model.capture(draft, dayID: day.id, photoPreparation: preparation)))
        #expect(model.readModel?.meals.isEmpty == true)
        #expect(draft.text == "Synthetic text and selected photo")
        await loader.complete(bytes); try await importing.value
        #expect(!preparation.isPreparing)
        #expect(await model.capture(draft, dayID: day.id, photoPreparation: preparation))
        await model.waitForWorker()
        let saved = try await store.snapshotForExport()
        #expect(saved.meals.count == 1)
        #expect(saved.meals.first?.photos.first?.data == bytes)
        #expect(saved.meals.first?.submissions.first?.text == draft.text)
    }
    @Test func dismissedComposerCannotAppendLateSelectedPhoto() async throws {
        var photos: [Data] = []
        let preparation = PhotoPreparation(), loader = DelayedPhoto()
        let generation = preparation.begin()
        let importing = Task { @MainActor in
            if let photo = try await preparation.load(generation, using: { await loader.load() }) { photos.append(photo) }
            preparation.finish(generation)
        }
        await loader.waitUntilRequested()
        preparation.cancel()
        await loader.complete(Data([1, 2, 3])); try await importing.value
        #expect(photos.isEmpty)
        #expect(!preparation.isPreparing)
        #expect(!preparation.canCapture)
        let lateSelection = preparation.begin()
        #expect(try await preparation.load(lateSelection, using: { Data([9]) }) == nil)
    }
    @Test func sameOwnerRestoreRefreshesSettingsDraftsBeforeAnotherSave() async throws {
        let path = URL.temporaryDirectory.appending(path: "MivuReview-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = DiaryStore(directory: path), model = DiaryViewModel(store: store)
        await model.load()
        var fields = DiaryPreferencesDraft()
        fields.synchronize(model.readModel?.profile, restoreGeneration: model.restoreGeneration)
        fields.preferences = "Unsaved synthetic old preference"
        let replacement = DiaryStore(directory: path.appending(path: "Replacement"))
        _ = try await replacement.importProfile(try await store.snapshotForExport())
        var profileFromArchive = try await replacement.snapshotForExport().profile
        profileFromArchive.timeZoneID = "Europe/London"
        profileFromArchive.preferences = "Synthetic archived restriction"
        try await replacement.updateProfile(profileFromArchive, expectedProfileID: profileFromArchive.id)
        let archive = try await replacement.snapshotForExport()
        #expect(await model.importArchive(archive))
        fields.synchronize(model.readModel?.profile, restoreGeneration: model.restoreGeneration)
        #expect(fields.timezone == "Europe/London")
        #expect(fields.preferences == "Synthetic archived restriction")
        let profile = try #require(model.readModel?.profile)
        #expect(await model.change { try await store.updateProfile(fields.applying(to: profile), expectedProfileID: profile.id) })
        let saved = try await store.snapshotForExport()
        #expect(saved.profile.timeZoneID == "Europe/London")
        #expect(saved.profile.preferences == "Synthetic archived restriction")
        model.enterBackground()
    }
    @Test func ordinaryRefreshAndLanguageChangeKeepUnsavedSettingsDrafts() async throws {
        let path = URL.temporaryDirectory.appending(path: "MivuReview-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = DiaryStore(directory: path), model = DiaryViewModel(store: store)
        await model.load()
        var fields = DiaryPreferencesDraft()
        fields.synchronize(model.readModel?.profile, restoreGeneration: model.restoreGeneration)
        fields.timezone = "America/New_York"; fields.preferences = "Unsaved synthetic draft"
        var profile = try #require(model.readModel?.profile); profile.language = "he"
        #expect(await model.change { try await store.updateProfile(profile, expectedProfileID: profile.id) })
        _ = try await store.startDay(); try await model.refresh(profileID: profile.id)
        fields.synchronize(model.readModel?.profile, restoreGeneration: model.restoreGeneration)
        #expect(fields.timezone == "America/New_York")
        #expect(fields.preferences == "Unsaved synthetic draft")
        model.enterBackground()
    }
}
