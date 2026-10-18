import Foundation
import Testing
@testable import Mivu

struct DiaryTests {
    static func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    static func ready() async throws -> (DiaryStore, DiaryProfile, TrackingDay) {
        let store = DiaryStore(directory: directory())
        let profile = DiaryProfile(name: "Synthetic owner")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay(at: Date(timeIntervalSince1970: 1_800_000_000))
        return (store, profile, day)
    }
    @Test func captureIsDurableBeforeAnalysisAndRetryKeepsIdentity() async throws {
        let directory = Self.directory()
        let store = DiaryStore(directory: directory)
        let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay()
        let submission = UUID()
        let photo = MealPhoto(data: Data([1, 2, 3]), role: .before)
        let meal = try await capturedMeal(store, text: "lunch", photos: [photo], reviewFirst: false, dayID: day.id, submissionID: submission)
        let again = try await capturedMeal(store, text: "lunch", photos: [photo], reviewFirst: false, dayID: day.id, submissionID: submission)
        #expect(meal.id == again.id)
        let restored = try await completeSelectedProfile(DiaryStore(directory: directory), profile.id)
        #expect(restored.meals.count == 1)
        #expect(restored.meals[0].photos == [photo])
        #expect(restored.pendingCount == 1)
        #expect(restored.meals[0].revision == 0)
    }
    @Test func diskFailureNeverAcknowledgesOrChangesMemory() async throws {
        let directory = Self.directory()
        let retained = Self.directory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: retained)
        }
        let store = DiaryStore(directory: directory)
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic"))
        let day = try await store.startDay()
        let before = try await store.snapshotForExport()
        let ownership = try await store.selectionOwnership(expectedProfileID: before.profile.id)
        let relativePath = before.profile.id.uuidString + ".sqlite/diary.sqlite"
        let bytes = try Data(contentsOf: directory.appendingPathComponent(relativePath))
        try FileManager.default.moveItem(at: directory, to: retained)
        let obstruction = Data([0]); try obstruction.write(to: directory)
        await #expect(throws: DiaryError.persistenceFailed) { try await capturedMeal(store, text: "apple", photos: [], reviewFirst: false, dayID: day.id) }
        await #expect(throws: DiaryError.persistenceFailed) { try await store.snapshotForExport() }
        #expect(try Data(contentsOf: directory) == obstruction)
        #expect(try Data(contentsOf: retained.appendingPathComponent(relativePath)) == bytes)
        #expect(try await completeSelectedProfile(DiaryStore(directory: retained), before.profile.id) == before)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: retained, to: directory)
        #expect(try await store.selectionOwnership(expectedProfileID: before.profile.id) == ownership)
        #expect(try await store.snapshotForExport() == before)
    }
    @Test func reviewDoesNotContributeUntilExplicitSave() async throws {
        let (store, _, day) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "food", photos: [], reviewFirst: true, dayID: day.id)
        try await store.processPending()
        let waiting = try await store.snapshotForExport()
        #expect(waiting.meals[0].state == .awaitingReview)
        #expect(waiting.totals(dayID: day.id).kcal == nil)
        try await store.acceptReview(mealID: meal.id, submissionID: meal.submissions[0].id)
        #expect(try await store.snapshotForExport().totals(dayID: day.id).kcal == 95)
        try await store.acceptReview(mealID: meal.id, submissionID: meal.submissions[0].id)
        #expect(try await store.snapshotForExport().meals[0].revision == 1)
    }
    @Test func sampleIsLabeledAndHalfRetryCannotApplyTwice() async throws {
        let (store, _, day) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "something entirely different", photos: [], reviewFirst: false, dayID: day.id)
        try await store.processPending()
        let initial = try await store.snapshotForExport().meals[0]
        #expect(initial.items[0].name == "Apple (sample)")
        #expect(initial.items[0].provenance == .sample)
        let submissionID = UUID()
        _ = try await correctedMeal(store, mealID: meal.id, text: "I ate half", submissionID: submissionID)
        let input = try await store.analysisInput(mealID: meal.id, submissionID: submissionID)
        let result = try SampleAnalyzer().analyze(input)
        try await store.applyAnalysis(result)
        try await store.applyAnalysis(result)
        #expect(try await store.snapshotForExport().totals(dayID: day.id).kcal == 47.5)
        _ = try await correctedMeal(store, mealID: meal.id, text: "quantity 2")
        try await store.processPending()
        #expect(try await store.snapshotForExport().totals(dayID: day.id).kcal == 190)
        #expect(try await store.snapshotForExport().meals.count == 1)
    }
    @Test func staleCorrectionDoesNotOverwriteNewerDirectEdit() async throws {
        let (store, _, day) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "apple", photos: [], reviewFirst: false, dayID: day.id)
        try await store.processPending()
        let pending = try await correctedMeal(store, mealID: meal.id, text: "half")
        let input = try await store.analysisInput(mealID: meal.id, submissionID: pending.submissions.last!.id)
        var item = try await store.snapshotForExport().meals[0].items[0]
        item.nutrition.kcal = 123
        try await store.editItem(mealID: meal.id, item: item)
        await #expect(throws: DiaryError.staleRevision) { try await store.applyAnalysis(SampleAnalyzer().analyze(input)) }
        #expect(try await store.snapshotForExport().totals(dayID: day.id).kcal == 123)
        #expect(try await store.snapshotForExport().meals[0].items[0].provenance == .user)
    }
    @Test func staleMovePreservesDayAndNewerIngredientEdit() async throws {
        let (store, profile, originalDay) = try await Self.ready()
        let captured = try await capturedMeal(store, text: "Synthetic apple", photos: [], reviewFirst: false, dayID: originalDay.id)
        try await store.processPending()
        let originalMeal = try #require(try await store.snapshotForExport().meals.first)
        let destination = try await store.startDay(at: originalDay.startAt.addingTimeInterval(86_400))
        var item = try #require(originalMeal.items.first); item.nutrition.kcal = 123
        try await store.editItem(mealID: captured.id, item: item, expectedRevision: originalMeal.revision, expectedProfileID: profile.id)
        let before = try await store.snapshotForExport()
        await #expect(throws: DiaryError.staleRevision) {
            try await store.moveMeal(captured.id, to: destination.id, expectedRevision: originalMeal.revision,
                                     expectedDayID: originalDay.id, expectedProfileID: profile.id)
        }
        let after = try await store.snapshotForExport()
        #expect(after == before)
        #expect(after.meals.first?.dayID == originalDay.id)
        #expect(after.meals.first?.totals.kcal == 123)
    }
    @Test func staleMoveCannotOverrideAnotherMoveOrMarkPendingNutritionSaved() async throws {
        let (store, profile, originalDay) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "Synthetic pending meal", photos: [], reviewFirst: true, dayID: originalDay.id)
        let firstDestination = try await store.startDay(at: originalDay.startAt.addingTimeInterval(86_400))
        let secondDestination = try await store.startDay(at: originalDay.startAt.addingTimeInterval(172_800))
        try await store.moveMeal(meal.id, to: firstDestination.id, expectedRevision: meal.revision,
                                 expectedDayID: originalDay.id, expectedProfileID: profile.id)
        let before = try await store.snapshotForExport()
        #expect(before.meals.first?.dayID == firstDestination.id)
        #expect(before.meals.first?.revision == 0)
        #expect(before.meals.first?.isSaved == false)
        await #expect(throws: DiaryError.staleRevision) {
            try await store.moveMeal(meal.id, to: secondDestination.id, expectedRevision: meal.revision,
                                     expectedDayID: originalDay.id, expectedProfileID: profile.id)
        }
        #expect(try await store.snapshotForExport() == before)
    }
    @Test func deleteRejectsLateResultAndOlderRestore() async throws {
        let (store, profile, day) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "apple", photos: [], reviewFirst: false, dayID: day.id)
        let input = try await store.analysisInput(mealID: meal.id, submissionID: meal.submissions[0].id)
        let old = try await store.snapshotForExport()
        try await store.deleteMeal(meal.id)
        await #expect(throws: DiaryError.notFound) { try await store.applyAnalysis(SampleAnalyzer().analyze(input)) }
        await #expect(throws: DiaryError.staleArchive) { try await store.restore(old, expectedProfileID: profile.id) }
        #expect(try await store.snapshotForExport().meals.isEmpty)
        #expect(try await store.snapshotForExport().deletedMealIDs.contains(meal.id))
    }
    @Test func photosRemainAttachedUntilExplicitDelete() async throws {
        let (store, _, day) = try await Self.ready()
        let before = MealPhoto(data: Data([1]), role: .before)
        let after = MealPhoto(data: Data([2]), role: .after)
        let meal = try await capturedMeal(store, text: "apple", photos: [before], reviewFirst: false, dayID: day.id)
        try await store.processPending()
        _ = try await correctedMeal(store, mealID: meal.id, text: "half", photos: [after])
        try await store.processPending()
        #expect(try await store.snapshotForExport().meals[0].photos == [before, after])
        try await store.deletePhoto(mealID: meal.id, photoID: before.id)
        #expect(try await store.snapshotForExport().meals[0].photos == [after])
        #expect(try await store.snapshotForExport().meals[0].submissions.flatMap(\.photoIDs) == [after.id])
    }
    @Test func nullableComponentsAreNeverConvertedToZero() throws {
        let items = [FoodItem(name: "A", nutrition: NutritionValues(kcal: 10, carbs: 1, protein: nil, fat: 0)), FoodItem(name: "B", nutrition: NutritionValues(kcal: 20, carbs: 2, protein: 3, fat: 4))]
        let totals = nutritionTotals(items)
        #expect(totals.kcal == 30)
        #expect(totals.protein == nil)
        #expect(totals.unknownItemCount == 1)
        #expect(nutritionTotals([]).kcal == nil)
    }
    @Test func profileSwitchRejectsWorkFromFormerOwner() async throws {
        let (store, profile, day) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "apple", photos: [], reviewFirst: false, dayID: day.id)
        let input = try await store.analysisInput(mealID: meal.id, submissionID: meal.submissions[0].id)
        let other = DiaryProfile(name: "Other synthetic")
        _ = try await store.createProfile(other)
        #expect(try await store.snapshotForExport().meals.isEmpty)
        await #expect(throws: DiaryError.wrongOwner) { try await store.processPending(expectedProfileID: profile.id) }
        await #expect(throws: DiaryError.wrongOwner) { try await store.applyAnalysis(SampleAnalyzer().analyze(input)) }
        _ = try await store.selectProfile(profile.id)
        #expect(try await store.snapshotForExport().meals.count == 1)
    }
    @Test func malformedRestorePreservesCurrentDiary() async throws {
        let (store, _, _) = try await Self.ready()
        let old = try await store.snapshotForExport()
        var invalid = old
        invalid.schemaVersion = 99
        await #expect(throws: DiaryError.invalidData) { try await store.restore(invalid) }
        #expect(try await store.snapshotForExport() == old)
        invalid = old
        invalid.weights = [WeightEntry(dayID: old.activeDayID, measuredAt: Date(), value: .nan)]
        #expect(throws: DiaryError.invalidData) { try invalid.validate() }
    }
    @Test func corruptDiskIsRejectedWithoutReplacement() async throws {
        let directory = Self.directory()
        let store = DiaryStore(directory: directory)
        let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile)
        let url = directory.appendingPathComponent(profile.id.uuidString + ".sqlite").appendingPathComponent("diary.sqlite")
        let bad = Data("not a diary".utf8)
        try bad.write(to: url)
        await #expect(throws: DiaryError.invalidData) { try await DiaryStore(directory: directory).selectProfile(profile.id) }
        #expect(try Data(contentsOf: url) == bad)
    }
    @Test func missingPhotoAndForeignDayReferencesFailValidation() async throws {
        let (store, _, day) = try await Self.ready()
        var snapshot = try await store.snapshotForExport()
        snapshot.meals = [DiaryMeal(dayID: UUID(), capturedAt: Date(), eatenAt: Date())]
        #expect(throws: DiaryError.invalidData) { try snapshot.validate() }
        snapshot.meals = [DiaryMeal(dayID: day.id, capturedAt: Date(), eatenAt: Date(), submissions: [MealSubmission(baseRevision: 0, text: "food", photoIDs: [UUID()], reviewFirst: false)])]
        #expect(throws: DiaryError.invalidData) { try snapshot.validate() }
    }
    @Test func retryReanalyzesStaleQueuedCorrectionAgainstCurrentValues() async throws {
        let (store, _, day) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "apple", photos: [], reviewFirst: false, dayID: day.id)
        try await store.processPending()
        _ = try await correctedMeal(store, mealID: meal.id, text: "half")
        var item = try await store.snapshotForExport().meals[0].items[0]
        item.nutrition.kcal = 200
        try await store.editItem(mealID: meal.id, item: item)
        try await store.processPending()
        #expect(try await store.snapshotForExport().totals(dayID: day.id).kcal == 100)
        #expect(try await store.snapshotForExport().pendingCount == 0)
    }
    @Test func reviewProposalCanBeEditedBeforeSaveWithoutEarlyTotals() async throws {
        let (store, _, day) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "food", photos: [], reviewFirst: true, dayID: day.id)
        try await store.processPending()
        var item = try await store.snapshotForExport().meals[0].submissions[0].proposal!.items[0]
        item.nutrition.kcal = 50
        try await store.editItem(mealID: meal.id, item: item, reviewSubmissionID: meal.submissions[0].id)
        #expect(try await store.snapshotForExport().totals(dayID: day.id).kcal == nil)
        try await store.acceptReview(mealID: meal.id, submissionID: meal.submissions[0].id)
        #expect(try await store.snapshotForExport().totals(dayID: day.id).kcal == 50)
        #expect(try await store.snapshotForExport().meals[0].items[0].provenance == .user)
    }
    @Test func wrongOwnerRestoreAndInvalidOutputNeverMutateDiary() async throws {
        let (store, _, day) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "apple", photos: [], reviewFirst: false, dayID: day.id)
        let before = try await store.snapshotForExport()
        var foreign = before
        foreign.profile.id = UUID()
        await #expect(throws: DiaryError.wrongOwner) { try await store.restore(foreign) }
        let input = try await store.analysisInput(mealID: meal.id, submissionID: meal.submissions[0].id)
        var malformed = try SampleAnalyzer().analyze(input)
        malformed.items[0].nutrition.kcal = -1
        await #expect(throws: DiaryError.invalidData) { try await store.applyAnalysis(malformed) }
        #expect(try await store.snapshotForExport() == before)
    }
    @Test func attachmentsExportAndSignoutKeepPrivateRecords() async throws {
        let (store, profile, day) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "apple", photos: [], reviewFirst: false, dayID: day.id)
        let photo = MealPhoto(data: Data([3, 4]))
        try await store.addPhotos(mealID: meal.id, photos: [photo])
        let export = try await store.exportData(expectedProfileID: profile.id)
        #expect(try JSONDecoder().decode(DiarySnapshot.self, from: export).meals[0].photos == [photo])
        await store.signOut()
        await #expect(throws: DiaryError.noProfile) { try await store.snapshotForExport() }
        _ = try await store.selectProfile(profile.id)
        #expect(try await store.profiles().contains(profile))
        #expect(try await store.snapshotForExport().meals[0].photos == [photo])
        try await store.deleteProfile(profile.id)
        #expect(try await store.profiles().isEmpty)
    }

    @Test func invalidCommittedMealAndRevisionOverflowAreRejected() async throws {
        let (store, _, day) = try await Self.ready()
        var snapshot = try await store.snapshotForExport()
        snapshot.revision = Int.max
        #expect(throws: DiaryError.invalidData) { try snapshot.validate() }
        snapshot.revision = 1
        snapshot.meals = [DiaryMeal(dayID: day.id, capturedAt: Date(), eatenAt: Date(), revision: 1)]
        #expect(throws: DiaryError.invalidData) { try snapshot.validate() }
    }

    @Test func directQuantityEditScalesNutritionAndKeepsItsSource() async throws {
        let (store, _, day) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "apple", photos: [], reviewFirst: false, dayID: day.id)
        try await store.processPending()
        var item = try await store.snapshotForExport().meals[0].items[0]
        item.quantity = 0
        try await store.editItem(mealID: meal.id, item: item)
        #expect(try await store.snapshotForExport().totals(dayID: day.id).kcal == 0)
        item = try await store.snapshotForExport().meals[0].items[0]
        item.quantity = 2
        try await store.editItem(mealID: meal.id, item: item)
        #expect(try await store.snapshotForExport().totals(dayID: day.id).kcal == 190)
    }

    @Test func nutrientEditPreservesSourcesOfUnchangedValues() async throws {
        let (store, _, day) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "apple", photos: [], reviewFirst: false, dayID: day.id)
        try await store.processPending()
        var item = try await store.snapshotForExport().meals[0].items[0]
        item.nutrition.kcal = 123
        try await store.editItem(mealID: meal.id, item: item)
        let edited = try await store.snapshotForExport().meals[0].items[0]
        #expect(edited.nutrientSources["kcal"] == .user)
        #expect(edited.nutrientSources["protein"] == .sample)
        #expect(edited.uncertain)
    }

    @Test func analysisCarriesOnlySelectedMealAndProfileContext() async throws {
        let (store, profile, day) = try await Self.ready()
        var updated = profile
        updated.language = "he"
        updated.preferences = "Synthetic preference"
        try await store.updateProfile(updated)
        let meal = try await capturedMeal(store, text: "apple", photos: [], reviewFirst: false, dayID: day.id)
        _ = try await capturedMeal(store, text: "unrelated synthetic meal", photos: [], reviewFirst: false, dayID: day.id)
        let input = try await store.analysisInput(mealID: meal.id, submissionID: meal.submissions[0].id)
        #expect(input.language == "he")
        #expect(input.preferences == updated.preferences)
        let encoded = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        #expect(!encoded.contains("unrelated synthetic meal"))
        #expect(!encoded.contains("token"))
    }
    @Test func freshImportPreservesIdentityAndRefusesSilentReplacement() async throws {
        let (source, profile, day) = try await Self.ready()
        let meal = try await capturedMeal(source, text: "apple", photos: [], reviewFirst: false, dayID: day.id)
        try await source.processPending()
        let backup = try await source.snapshotForExport()
        let fresh = DiaryStore(directory: Self.directory())
        _ = try await fresh.importProfile(backup)
        #expect(try await fresh.snapshotForExport() == backup)
        #expect(try await fresh.snapshotForExport().profile.id == profile.id)
        #expect(try await fresh.snapshotForExport().meals[0].id == meal.id)
        await #expect(throws: DiaryError.invalidData) { try await fresh.importProfile(backup) }
        #expect(try await fresh.snapshotForExport() == backup)
    }
    @Test func failedFreshImportDoesNotChangeSelection() async throws {
        let directory = Self.directory()
        let retained = Self.directory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: retained)
        }
        let store = DiaryStore(directory: directory)
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic"))
        let old = try await store.snapshotForExport()
        let ownership = try await store.selectionOwnership(expectedProfileID: old.profile.id)
        let relativePath = old.profile.id.uuidString + ".sqlite/diary.sqlite"
        let bytes = try Data(contentsOf: directory.appendingPathComponent(relativePath))
        let incoming = DiarySnapshot(profile: DiaryProfile(name: "Imported"))
        try FileManager.default.moveItem(at: directory, to: retained)
        let obstruction = Data([0]); try obstruction.write(to: directory)
        await #expect(throws: DiaryError.persistenceFailed) { try await store.importProfile(incoming) }
        await #expect(throws: DiaryError.persistenceFailed) { try await store.snapshotForExport() }
        await #expect(throws: DiaryError.wrongOwner) { try await store.snapshotForExport(expectedProfileID: incoming.profile.id) }
        #expect(try Data(contentsOf: directory) == obstruction)
        #expect(try Data(contentsOf: retained.appendingPathComponent(relativePath)) == bytes)
        #expect(try await completeSelectedProfile(DiaryStore(directory: retained), old.profile.id) == old)
        #expect(!FileManager.default.fileExists(atPath: retained.appendingPathComponent(incoming.profile.id.uuidString + ".sqlite").path))
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: retained, to: directory)
        #expect(try await store.selectionOwnership(expectedProfileID: old.profile.id) == ownership)
        #expect(try await store.snapshotForExport() == old)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(incoming.profile.id.uuidString + ".sqlite").path))
    }

    @Test func photoDeletionCancelsPendingResultAndAwaitingReview() async throws {
        let (store, _, day) = try await Self.ready()
        let photo = MealPhoto(data: Data([1]))
        let meal = try await capturedMeal(store, text: "apple", photos: [photo], reviewFirst: false, dayID: day.id)
        let input = try await store.analysisInput(mealID: meal.id, submissionID: meal.submissions[0].id)
        let output = try SampleAnalyzer().analyze(input)
        try await store.deletePhoto(mealID: meal.id, photoID: photo.id)
        await #expect(throws: DiaryError.notFound) { try await store.applyAnalysis(output) }
        #expect(try await store.snapshotForExport().meals[0].items.isEmpty)
        try await store.processPending()
        #expect(try await store.snapshotForExport().meals[0].items.isEmpty)
        let otherPhoto = MealPhoto(data: Data([2]))
        let other = try await capturedMeal(store, text: "food", photos: [otherPhoto], reviewFirst: true, dayID: day.id)
        try await store.processPending()
        try await store.deletePhoto(mealID: other.id, photoID: otherPhoto.id)
        await #expect(throws: DiaryError.invalidData) { try await store.acceptReview(mealID: other.id, submissionID: other.submissions[0].id) }
        let snapshot = try await store.snapshotForExport()
        let deletedReview = snapshot.meals.first { $0.id == other.id }!
        #expect(deletedReview.submissions[0].state == .cancelled)
        #expect(deletedReview.submissions[0].proposal == nil)
    }
    @Test func savedAndReviewEditsHaveExplicitIndependentTargets() async throws {
        let (store, _, day) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "apple", photos: [], reviewFirst: false, dayID: day.id)
        try await store.processPending()
        let correction = try await correctedMeal(store, mealID: meal.id, text: "half", reviewFirst: true)
        try await store.processPending()
        let reviewID = correction.submissions.last!.id
        var committed = try await store.snapshotForExport().meals[0].items[0]
        committed.nutrition.kcal = 150
        try await store.editItem(mealID: meal.id, item: committed)
        let saved = try await store.snapshotForExport().meals[0]
        #expect(saved.totals.kcal == 150)
        #expect(saved.submissions.first { $0.id == reviewID }!.proposal!.items[0].nutrition.kcal == 47.5)
        var reviewItem = saved.submissions.first { $0.id == reviewID }!.proposal!.items[0]
        reviewItem.nutrition.kcal = 30
        await #expect(throws: DiaryError.staleRevision) { try await store.editItem(mealID: meal.id, item: reviewItem, reviewSubmissionID: reviewID) }
        committed.nutrition.kcal = 160
        try await store.editItem(mealID: meal.id, item: committed)
        #expect(try await store.snapshotForExport().meals[0].totals.kcal == 160)
    }
    @Test func editorRevisionGuardRejectsStaleDirectEdit() async throws {
        let (store, _, day) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "apple", photos: [], reviewFirst: false, dayID: day.id)
        try await store.processPending()
        let original = try await store.snapshotForExport().meals[0]
        var item = original.items[0]
        item.nutrition.kcal = 200
        try await store.editItem(mealID: meal.id, item: item, expectedRevision: original.revision)
        item.nutrition.kcal = 50
        await #expect(throws: DiaryError.staleRevision) { try await store.editItem(mealID: meal.id, item: item, expectedRevision: original.revision) }
        #expect(try await store.snapshotForExport().meals[0].totals.kcal == 200)
    }
    @Test func encodedSizeRejectionPreservesFileMemoryAndReopenability() async throws {
        let directory = Self.directory()
        let store = DiaryStore(directory: directory, maximumFileBytes: 2000)
        let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay()
        let before = try await store.snapshotForExport()
        let url = directory.appendingPathComponent(profile.id.uuidString + ".sqlite").appendingPathComponent("diary.sqlite")
        let fileBefore = try Data(contentsOf: url)
        await #expect(throws: DiaryError.invalidData) {
            try await capturedMeal(store, text: String(repeating: "x", count: 3000), photos: [], reviewFirst: false, dayID: day.id)
        }
        #expect(try await store.snapshotForExport() == before)
        #expect(try Data(contentsOf: url) == fileBefore)
        #expect(try await completeSelectedProfile(DiaryStore(directory: directory, maximumFileBytes: 2000), profile.id) == before)
    }
    @Test func directEditKeepsSpecificSourceReference() async throws {
        let (store, _, day) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "apple", photos: [], reviewFirst: false, dayID: day.id)
        try await store.processPending()
        var item = try await store.snapshotForExport().meals[0].items[0]
        let originalReference = item.reference
        item.nutrition.kcal = 110
        try await store.editItem(mealID: meal.id, item: item)
        #expect(try await store.snapshotForExport().meals[0].items[0].reference == originalReference)
    }

}
