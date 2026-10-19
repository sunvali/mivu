import Foundation
import Testing
@testable import Mivu

@Suite struct DiaryProjectionMutationTests {
    @Test func projectionMutationPreservesUnloadedRecords() throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 100)
        for _ in 0..<100 { var meal = source.meals[0]; meal.id = UUID(); source.meals.append(meal) }
        let f = try MealProjectionFixture(source); defer { f.remove() }
        let unloaded = Array(source.meals.dropFirst())
        let active = try f.database.diaryReadModel(expectedProfileID: f.owner)
        #expect(active.head.activeDayID == source.activeDayID && active.meals.isEmpty)
        let selected = try f.database.diaryDay(id: source.days[1].id, expectedProfileID: f.owner)
        #expect(selected.meals.count == 101)
        var item = source.meals[0].items[0]; item.quantity = 2
        let commit = try f.database.editItem(mealID: f.mealID, item: item, expectedRevision: 1, expected: f.head(), maximumBytes: f.maximum)
        #expect(commit.changes.mealIDs == [f.mealID])
        #expect(f.diagnostics.counters.originalPhotoBytes == 0 && f.diagnostics.counters.completeReads == 0 && f.diagnostics.counters.completeReconciles == 0)
        #expect(try ChatHistoryFixture.completeReference(databaseURL: f.url).meals.filter { $0.id != f.mealID } == unloaded)
        #expect(throws: DiaryError.wrongOwner) { try f.database.meal(id: f.mealID, expectedProfileID: UUID()) }
        #expect(throws: DiaryError.staleRevision) { try f.database.setCompleteness(dayID: source.days[0].id, .complete, expected: active.head, maximumBytes: f.maximum) }
        try f.assertAccounting()
    }

    @Test func collidingParentPhotoIDsResolveExactly() throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 1)
        var other = source.meals[0]; other.id = UUID(); other.photos[0].data = Data([1, 2, 3]); source.meals.append(other)
        let f = try MealProjectionFixture(source); defer { f.remove() }
        let first = try #require(f.database.meal(id: f.mealID, expectedProfileID: f.owner).photos.first)
        let second = try #require(f.database.meal(id: other.id, expectedProfileID: f.owner).photos.first)
        let direct = try #require(f.database.coachPage(.latest, expectedProfileID: f.owner).exchanges.first?.photos.first)
        #expect(first.photoID == second.photoID && first.contentToken != second.contentToken)
        #expect(f.diagnostics.counters.originalPhotoBytes == 0)
        #expect(try f.database.photoContent(first, expectedProfileID: f.owner) == source.meals[0].photos[0].data)
        #expect(try f.database.photoContent(second, expectedProfileID: f.owner) == other.photos[0].data)
        #expect(try f.database.photoContent(direct, expectedProfileID: f.owner) == source.coachTurns[0].photos[0].data)
        var invalid = first; invalid.contentToken = second.contentToken
        #expect(throws: DiaryError.notFound) { try f.database.photoContent(invalid, expectedProfileID: f.owner) }
        invalid = first; invalid.profileID = UUID()
        #expect(throws: DiaryError.wrongOwner) { try f.database.photoContent(invalid, expectedProfileID: f.owner) }
        _ = try f.database.deletePhoto(mealID: f.mealID, photoID: first.photoID, expected: f.head(), maximumBytes: f.maximum)
        #expect(throws: DiaryError.notFound) { try f.database.photoContent(first, expectedProfileID: f.owner) }
        #expect(try f.database.photoContent(second, expectedProfileID: f.owner) == other.photos[0].data)
    }

    @Test func staleReviewAndQuotaFailurePreserveCommittedMeal() throws {
        let f = try MealProjectionFixture(); defer { f.remove() }
        let correction = try f.database.correctMealProjection(mealID: f.mealID, text: "review", reviewFirst: true, at: f.instant, expected: f.head(), maximumBytes: f.maximum).value
        let submission = try #require(correction.submissions.last)
        let proposal = AnalysisOutput(profileID: f.owner, mealID: f.mealID, submissionID: submission.id, baseRevision: correction.revision,
            items: [FoodItem(name: "unknown", nutrition: NutritionValues(carbs: 2), provenance: .identifiedSource, reference: "kept source")])
        _ = try f.database.applyAnalysis(proposal, expected: f.head(), maximumBytes: f.maximum)
        #expect(try f.database.meal(id: f.mealID, expectedProfileID: f.owner).items == f.source.meals[0].items)
        var changed = f.source.meals[0].items[0]; changed.quantity = 2
        _ = try f.database.editItem(mealID: f.mealID, item: changed, expectedRevision: 1, expected: f.head(), maximumBytes: f.maximum)
        let before = try f.durableState()
        #expect(throws: DiaryError.staleRevision) { try f.database.acceptReview(mealID: f.mealID, submissionID: submission.id, expected: f.head(), maximumBytes: f.maximum) }
        #expect(throws: DiaryError.invalidData) { try f.database.addPhotos(mealID: f.mealID, photos: [f.photo()], expected: f.head(), maximumBytes: 1) }
        #expect(try f.durableState() == before)
        let meal = try f.database.meal(id: f.mealID, expectedProfileID: f.owner)
        #expect(meal.items[0].quantity == 2 && meal.items[0].reference == changed.reference)
        #expect(meal.submissions.first { $0.id == submission.id }?.proposal == proposal)
        try f.assertAccounting()
    }

    @Test func backdatedRecordDoesNotActivateChatDay() throws {
        let f = try MealProjectionFixture(); defer { f.remove() }
        let before = try f.head(), oldIndex = try f.rows("SELECT * FROM coach_index")
        let capture = try f.database.captureProjection(text: "backdated", photos: [], reviewFirst: true, dayID: f.source.days[1].id,
            at: f.instant, dateOnly: true, expected: before, maximumBytes: f.maximum)
        #expect(capture.value.eatenAt == f.source.days[1].startAt && capture.value.timePrecision == .dateOnly)
        _ = try f.database.moveMeal(capture.value.id, to: f.source.days[0].id, expectedRevision: 0, expectedDayID: f.source.days[1].id, expected: f.head(), maximumBytes: f.maximum)
        _ = try f.database.setCompleteness(dayID: f.source.days[1].id, .partial, expected: f.head(), maximumBytes: f.maximum)
        let after = try f.head()
        #expect(after.activeDayID == before.activeDayID && after.activeConversationSegmentID == before.activeConversationSegmentID)
        #expect(after.effectiveConversationSegmentID == before.effectiveConversationSegmentID && after.previousDayConfirmedAt == before.previousDayConfirmedAt)
        #expect(try f.rows("SELECT * FROM coach_index") == oldIndex)
        #expect(f.diagnostics.counters.originalPhotoBytes == 0)
        try f.assertAccounting()
    }

    @Test func deletingMealDoesNotTouchAnotherOwnersCollidingPhoto() throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 1)
        var other = source.meals[0]; other.id = UUID(); other.photos[0].data = Data([9, 8]); source.meals.append(other)
        source.coachTurns[0].photos = []
        let turnID = source.coachTurns[0].id
        source.coachTurns[0].receipts.append(CoachReceipt(operationKey: "\(turnID)/food/second", turnID: turnID, dayID: other.dayID, mealID: other.id, committedRevision: 1, resultJSON: "{}"))
        let f = try MealProjectionFixture(source); defer { f.remove() }
        let unrelated = try #require(f.database.meal(id: other.id, expectedProfileID: f.owner).photos.first)
        #expect(try f.database.coachPage(.latest, expectedProfileID: f.owner).exchanges.first?.photos.count == 2)
        _ = try f.database.deleteMeal(f.mealID, expected: f.head(), maximumBytes: f.maximum)
        #expect(throws: DiaryError.notFound) { try f.database.meal(id: f.mealID, expectedProfileID: f.owner) }
        #expect(try f.database.meal(id: other.id, expectedProfileID: f.owner).photos.first == unrelated)
        #expect(try f.database.coachPage(.latest, expectedProfileID: f.owner).exchanges.first?.photos == [unrelated])
        #expect(try ChatHistoryFixture.completeReference(databaseURL: f.url).coachTurns[0].photoIDs == [unrelated.photoID])
        #expect(try f.rows("SELECT COUNT(*) FROM photo_consumer WHERE parentID = '\(other.id.uuidString)' AND turnID = '\(turnID.uuidString)'") == [["1"]])
        #expect(f.diagnostics.counters.originalPhotoBytes == 0)
        let complete = try ChatHistoryFixture.completeReference(databaseURL: f.url)
        #expect(complete.deletedMealIDs.contains(f.mealID) && complete.meals == [other])
        try f.assertAccounting()
    }

    @Test func deletingMealWithSurvivingProgressReceiptRetainsEvidence() throws {
        for mode in 0..<5 {
            let source = MealProjectionFixture.sharedProgress(mode: mode)
            let f = try MealProjectionFixture(source); defer { f.remove() }
            let old = try #require(f.database.meal(id: f.mealID, expectedProfileID: f.owner).photos.first)
            let failedBefore = try f.durableState()
            try f.execute("CREATE TRIGGER fail_transfer BEFORE INSERT ON coach_photo BEGIN SELECT RAISE(ABORT, 'transfer failure'); END")
            if mode != 3 {
                #expect(throws: DiaryError.persistenceFailed) { try f.database.deleteMeal(f.mealID, expected: f.head(), maximumBytes: f.maximum) }
                #expect(try f.durableState() == failedBefore)
            }
            try f.execute("DROP TRIGGER fail_transfer")
            let commit = try f.database.deleteMeal(f.mealID, expected: f.head(), maximumBytes: f.maximum)
            #expect(f.diagnostics.counters.originalPhotoBytes == 0)
            let page = try f.database.coachPage(.latest, expectedProfileID: f.owner)
            for exchange in page.exchanges {
                if mode == 3 { #expect(exchange.photos.isEmpty) }
                else {
                    let reference = try #require(exchange.photos.first)
                    #expect(reference.owner == .coachTurn(exchange.id) && reference.contentToken != old.contentToken)
                    #expect(try f.database.photoContent(reference, expectedProfileID: f.owner) == source.meals[0].photos[0].data)
                    #expect(commit.changes.turnIDs.contains(exchange.id))
                }
            }
            #expect(throws: DiaryError.notFound) { try f.database.photoContent(old, expectedProfileID: f.owner) }
            let complete = try ChatHistoryFixture.completeReference(databaseURL: f.url)
            #expect(complete.weights == source.weights && complete.workouts == source.workouts)
            #expect(complete.coachTurns.map(\.receipts) == source.coachTurns.map(\.receipts))
            try f.assertAccounting()
        }
    }

    @Test func explicitPhotoRemovalDoesNotRetainHiddenContent() throws {
        var source = MealProjectionFixture.sharedProgress(mode: 2)
        let submissionID = source.coachTurns[0].id
        source.meals[0].submissions = [MealSubmission(id: submissionID, baseRevision: 1, text: "pending", photoIDs: source.coachTurns[0].photoIDs, reviewFirst: true)]
        let f = try MealProjectionFixture(source); defer { f.remove() }
        let reference = try #require(f.database.meal(id: f.mealID, expectedProfileID: f.owner).photos.first)
        _ = try f.database.deletePhoto(mealID: f.mealID, photoID: reference.photoID, expected: f.head(), maximumBytes: f.maximum)
        #expect(try f.rows("SELECT COUNT(*) FROM photo_content") == [["0"]])
        #expect(try f.rows("SELECT COUNT(*) FROM photo_consumer") == [["0"]])
        let complete = try ChatHistoryFixture.completeReference(databaseURL: f.url)
        #expect(complete.coachTurns[0].photos.isEmpty && complete.coachTurns[0].photoIDs.isEmpty)
        #expect(complete.meals[0].submissions[0].state == .cancelled && complete.meals[0].submissions[0].photoIDs.isEmpty)
        #expect(complete.weights == source.weights && complete.workouts == source.workouts)
        #expect(complete.coachTurns[0].receipts == source.coachTurns[0].receipts)
        #expect(throws: DiaryError.notFound) { try f.database.photoContent(reference, expectedProfileID: f.owner) }
        try f.assertAccounting()
    }

    @Test func seededMealPhotoMutationsMatchReferenceAccounting() throws {
        for seed in [UInt64(42), UInt64(20261018), UInt64(0xC0FFEE)] {
            let f = try MealProjectionFixture(); defer { f.remove() }
            var random = ChatHistoryFixture.Generator(seed: seed)
            for index in 0..<36 {
                let text = random.encodingEdge(), id = random.uuid()
                let photo = MealPhoto(id: id, data: Data(repeating: UInt8(random.next() % 256), count: index % 7 + 1), createdAt: Date(timeIntervalSinceReferenceDate: -0.125), role: .before)
                let capture = try f.database.captureProjection(text: text, photos: [photo], reviewFirst: index.isMultiple(of: 2), dayID: f.source.days[1].id,
                    at: f.instant, submissionID: random.uuid(), expected: f.head(), maximumBytes: f.maximum).value
                let output = AnalysisOutput(profileID: f.owner, mealID: capture.id, submissionID: capture.submissions[0].id, baseRevision: 0,
                    items: [FoodItem(id: random.uuid(), name: text.isEmpty ? "food" : text, nutrition: NutritionValues(kcal: Double(index), protein: nil))])
                _ = try f.database.applyAnalysis(output, expected: f.head(), maximumBytes: f.maximum)
                if index.isMultiple(of: 2) { _ = try f.database.acceptReview(mealID: capture.id, submissionID: capture.submissions[0].id, expected: f.head(), maximumBytes: f.maximum) }
                var replacement = photo; replacement.data = Data([255, 255, 255, UInt8(index)])
                _ = try f.database.transaction(expected: f.head(), maximumBytes: f.maximum) { try $0.replacePhoto(replacement, mealID: capture.id) }
                _ = try f.database.transaction(expected: f.head(), maximumBytes: f.maximum) { try $0.updatePhotoRole(mealID: capture.id, photoID: id, role: .after) }
                _ = try f.database.moveMeal(capture.id, to: f.source.days[0].id, expected: f.head(), maximumBytes: f.maximum)
                let before = try f.durableState()
                #expect(throws: DiaryError.invalidData) { try f.database.addPhotos(mealID: capture.id, photos: [f.photo()], expected: f.head(), maximumBytes: 1) }
                #expect(try f.durableState() == before, "seed \(seed), command \(index)")
                if index.isMultiple(of: 3) { _ = try f.database.deleteMeal(capture.id, expected: f.head(), maximumBytes: f.maximum) }
                else { _ = try f.database.deletePhoto(mealID: capture.id, photoID: id, expected: f.head(), maximumBytes: f.maximum) }
                try f.assertAccounting()
            }
            #expect(f.diagnostics.counters.originalPhotoBytes == 0)
        }
    }

    @Test func actualDayTransitionsRotateOnlyCurrentBoundary() throws {
        let f = try MealProjectionFixture(); defer { f.remove() }
        let a1 = try f.head().effectiveConversationSegmentID
        let oldIndex = try f.rows("SELECT * FROM coach_index")
        let b = try f.database.startDay(at: f.instant.addingTimeInterval(86400), expected: f.head(), maximumBytes: f.maximum)
        let boundaryB = try #require(b.head.activeConversationSegmentID)
        #expect(boundaryB != a1 && b.changes.coachLatestChanged)
        let repeated = try f.database.startDay(at: f.instant.addingTimeInterval(86400), expected: f.head(), maximumBytes: f.maximum)
        #expect(repeated.head == b.head && repeated.head.activeConversationSegmentID == boundaryB)
        let a = try f.database.startDay(at: f.instant, expected: f.head(), maximumBytes: f.maximum)
        let a2 = try #require(a.head.activeConversationSegmentID)
        #expect(a.value.id == f.source.days[0].id && a2 != a1 && a2 != boundaryB)
        #expect(try f.rows("SELECT * FROM coach_index") == oldIndex)
        let empty = try f.database.coachPage(.latest, expectedProfileID: f.owner).latestEmptySegment
        #expect(empty?.segmentID == a2)
        let payload = try CoachSubmissionPayload(submissionID: UUID(), text: "first A2", attachments: [], context: CoachCaptureContext(capturedAt: f.instant,
            timeZoneID: a.head.profile.timeZoneID, activeDayID: a.head.activeDayID, previousDayConfirmedAt: a.head.previousDayConfirmedAt, activeConversationSegmentID: a.head.effectiveConversationSegmentID))
        let captured = try f.database.captureCoachSubmission(payload, expected: a.head, maximumBytes: f.maximum)
        #expect(captured.value.segmentID == a2 && captured.value.sequence == 2)
        #expect(try f.database.coachPage(.latest, expectedProfileID: f.owner).latestEmptySegment == nil)
        try f.assertAccounting()
    }

    @Test func failedDayTransitionPreservesBoundaryAndCounters() throws {
        let f = try MealProjectionFixture(); defer { f.remove() }
        let before = try f.durableState()
        #expect(throws: DiaryError.invalidData) { try f.database.startDay(at: f.instant.addingTimeInterval(86400), expected: f.head(), maximumBytes: 1) }
        #expect(try f.durableState() == before)
        try f.execute("CREATE TRIGGER fail_day BEFORE INSERT ON day BEGIN SELECT RAISE(ABORT, 'day failure'); END")
        #expect(throws: DiaryError.persistenceFailed) { try f.database.startDay(at: f.instant.addingTimeInterval(86400), expected: f.head(), maximumBytes: f.maximum) }
        #expect(try f.durableState() == before)
        try f.execute("DROP TRIGGER fail_day")
        _ = try f.database.confirmPreviousDay(at: f.instant.addingTimeInterval(60), expected: f.head(), maximumBytes: f.maximum)
        #expect(try f.head().activeConversationSegmentID == nil)
        try f.assertAccounting()
    }

    @Test func metadataEditsDoNotRewriteOriginalPhotoBytes() throws {
        let f = try MealProjectionFixture(); defer { f.remove() }
        let reference = try #require(f.database.meal(id: f.mealID, expectedProfileID: f.owner).photos.first)
        for table in ["photo", "coach_photo"] { try f.execute("CREATE TRIGGER guard_\(table) BEFORE UPDATE OF bytes ON \(table) BEGIN SELECT RAISE(ABORT, 'unexpected blob write'); END") }
        _ = try f.database.transaction(expected: f.head(), maximumBytes: f.maximum) { try $0.updatePhotoRole(mealID: f.mealID, photoID: reference.photoID, role: .after) }
        var item = f.source.meals[0].items[0]; item.quantity = 3
        _ = try f.database.editItem(mealID: f.mealID, item: item, expected: f.head(), maximumBytes: f.maximum)
        let after = try #require(f.database.meal(id: f.mealID, expectedProfileID: f.owner).photos.first)
        #expect(after.contentToken == reference.contentToken && after.role == .after)
        #expect(f.diagnostics.counters.originalPhotoBytes == 0)
        try f.assertAccounting()
    }

    @Test func manualMealCaptureAndCorrectionAreAtomicWithSourceTurn() async throws {
        let f = try MealProjectionFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.capture.root, diagnostics: f.diagnostics)
        _ = try await store.selectPagedProfile(f.owner)
        let id = UUID(), photo = f.photo()
        let accepted = try await store.captureProjection(text: "manual", photos: [photo], reviewFirst: true, dayID: f.source.days[1].id,
            at: f.instant, submissionID: id, forCoach: true, expectedSelection: try await store.selectionOwnership(expectedProfileID: f.owner), expectedProfileID: f.owner)
        #expect(accepted.sourceTurnID == id && accepted.photos.first?.owner == .meal(accepted.id))
        let original = try f.database.coachExchangeSummary(turnID: id, expectedProfileID: f.owner)
        #expect(original.photos.first?.owner == .meal(accepted.id))
        let retry = try await store.captureProjection(text: "manual", photos: [photo], reviewFirst: true, dayID: f.source.days[1].id,
            at: f.instant, submissionID: id, forCoach: true, expectedSelection: try await store.selectionOwnership(expectedProfileID: f.owner), expectedProfileID: f.owner)
        #expect(retry == accepted && f.diagnostics.counters.originalPhotoBytes == 0)
        await #expect(throws: DiaryError.staleRevision) { try await store.captureProjection(text: "changed accepted input", photos: [photo], reviewFirst: true,
            dayID: f.source.days[1].id, at: f.instant, submissionID: id, forCoach: true, expectedSelection: try await store.selectionOwnership(expectedProfileID: f.owner), expectedProfileID: f.owner) }
        let correction = try await store.correctMealProjection(mealID: accepted.id, text: "different serving", forCoach: true, expectedSelection: try await store.selectionOwnership(expectedProfileID: f.owner), expectedProfileID: f.owner)
        #expect(correction.items == accepted.items && correction.submissions.count == 2)
        #expect(try f.database.coachExchangeSummary(turnID: id, expectedProfileID: f.owner) == original)
        let before = try f.durableState()
        try f.execute("CREATE TRIGGER fail_meal BEFORE INSERT ON meal BEGIN SELECT RAISE(ABORT, 'meal failure'); END")
        await #expect(throws: DiaryError.persistenceFailed) { try await store.captureProjection(text: "failed", photos: [f.photo()], reviewFirst: false,
            dayID: f.source.days[0].id, forCoach: true, expectedSelection: try await store.selectionOwnership(expectedProfileID: f.owner), expectedProfileID: f.owner) }
        #expect(try f.durableState() == before)
        try f.execute("DROP TRIGGER fail_meal")
        let manifest = try ChatHistoryFixture.completeReference(databaseURL: f.url).coachTurns.first { $0.id == id }?.submissionManifest
        try await store.deletePhoto(mealID: accepted.id, photoID: photo.id, expectedProfileID: f.owner)
        let removed = try ChatHistoryFixture.completeReference(databaseURL: f.url).coachTurns.first { $0.id == id }
        #expect(manifest != nil && removed?.submissionManifest == manifest && removed?.photoIDs.isEmpty == true)
        try f.assertAccounting()
    }

    @Test func targetedDayHistoryUsesBoundedPhotoFreeKeysets() throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 0)
        for index in 0..<40 {
            source.days.append(TrackingDay(localDate: "2027-01-15", timeZoneID: index.isMultiple(of: 2) ? "UTC" : "Asia/Jerusalem", startAt: source.days[0].startAt, completeness: .complete))
        }
        let f = try MealProjectionFixture(source); defer { f.remove() }
        let first = try f.database.diaryHistory(expectedProfileID: f.owner)
        #expect(first.days.count == 30 && first.hasMore)
        let second = try f.database.diaryHistory(before: first.cursor, expectedProfileID: f.owner)
        #expect(second.days.count == 12 && !second.hasMore)
        #expect(Set((first.days + second.days).map { $0.day.id }).count == 42)
        #expect(first.days.allSatisfy { $0.day.localDate == "2027-01-15" })
        let recorded = try f.database.diaryHistory(limit: 14, recordedOnly: true, expectedProfileID: f.owner)
        #expect(recorded.days.count == 14)
        var invalid = try #require(first.cursor); invalid.identity = CoachTimelineIdentity(profileID: f.owner, timelineGeneration: UUID())
        #expect(throws: CoachQueryError.wrongTimeline) { try f.database.diaryHistory(before: invalid, expectedProfileID: f.owner) }
        #expect(f.diagnostics.counters.originalPhotoBytes == 0 && f.diagnostics.counters.completeReads == 0)
    }

    @Test func seventyFiveDayKeysetsAreReversibleWithoutCompleteReads() throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 0)
        let instant = source.days[0].startAt
        source.days = (0..<75).map { index in
            TrackingDay(localDate: "2027-01-15", timeZoneID: "UTC", startAt: instant.addingTimeInterval(Double(-index) * 86400), completeness: .complete)
        }
        source.activeDayID = source.days[0].id
        source.meals = []; source.weights = []; source.workouts = []
        let f = try MealProjectionFixture(source); defer { f.remove() }
        // Equal date labels exercise the ordinal/id keyset rather than date-only paging.
        let latest = try f.database.diaryHistory(limit: 30, expectedProfileID: f.owner)
        let middle = try f.database.diaryHistory(before: latest.cursor, limit: 30, expectedProfileID: f.owner)
        let oldest = try f.database.diaryHistory(before: middle.cursor, limit: 30, expectedProfileID: f.owner)
        #expect(latest.days.count == 30 && middle.days.count == 30 && oldest.days.count == 15)
        #expect(latest.hasMore && middle.hasMore && !oldest.hasMore)
        let allIDs = (latest.days + middle.days + oldest.days).map(\.day.id)
        #expect(Set(allIDs) == Set(source.days.map(\.id)) && Set(allIDs).count == 75)
        let newer = try f.database.diaryHistory(before: latest.cursor, limit: 30, expectedProfileID: f.owner)
        #expect(newer.days.map(\.day.id) == middle.days.map(\.day.id))
        let reset = try f.database.diaryHistory(limit: 30, expectedProfileID: f.owner)
        #expect(reset.days.map(\.day.id) == latest.days.map(\.day.id))
        #expect(f.diagnostics.counters.completeReads == 0)
        #expect(f.diagnostics.counters.completeReconciles == 0)
        #expect(f.diagnostics.counters.originalPhotoBytes == 0)
    }

    @Test func targetedParentLimitsRejectAtomically() throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 0)
        source.meals[0].photos = (0..<30).map { _ in MealPhoto(data: Data([1]), createdAt: source.days[0].startAt) }
        source.meals[0].submissions = (0..<1000).map { _ in MealSubmission(baseRevision: 1, text: "pending", photoIDs: [], reviewFirst: false) }
        source.meals[0].items = (0..<200).map { _ in FoodItem(name: "bounded", nutrition: NutritionValues()) }
        let f = try MealProjectionFixture(source); defer { f.remove() }
        let before = try f.durableState()
        #expect(throws: DiaryError.invalidData) { try f.database.addPhotos(mealID: f.mealID, photos: [f.photo()], expected: f.head(), maximumBytes: f.maximum) }
        #expect(throws: DiaryError.invalidData) { try f.database.correctMealProjection(mealID: f.mealID, text: "overflow", at: f.instant, expected: f.head(), maximumBytes: f.maximum) }
        #expect(try f.durableState() == before)
        let selected = source.meals[0].submissions[0]
        _ = try f.database.prepareAnalysis(mealID: f.mealID, submissionID: selected.id, expected: f.head(), maximumBytes: f.maximum)
        let input = try f.database.analysisInput(mealID: f.mealID, submissionID: selected.id, expectedProfileID: f.owner)
        #expect(input.photos.isEmpty && input.currentItems.count == 200)
        try f.assertAccounting()
    }
}

private struct MealProjectionFixture {
    let capture: CaptureFixture
    let diagnostics = DiaryQueryDiagnostics()
    let database: DiaryDatabase
    var source: DiarySnapshot { capture.before }
    var owner: UUID { capture.profileID }
    var mealID: UUID { source.meals[0].id }
    var url: URL { capture.url }
    let maximum = ChatHistoryFixture.maximumBytes
    var instant: Date { source.days[0].startAt }
    init(_ snapshot: DiarySnapshot = ChatHistoryFixture.snapshot(exchanges: 1)) throws {
        capture = try CaptureFixture(snapshot: snapshot)
        database = try DiaryDatabase(url: capture.url, diagnostics: diagnostics)
    }
    func remove() { capture.remove() }
    func head() throws -> DiaryHead { try database.readHead(expectedProfileID: owner) }
    func rows(_ sql: String) throws -> [[String]] { try capture.rows(sql) }
    func execute(_ sql: String) throws { try capture.execute(sql) }
    func photo() -> MealPhoto { capture.photo() }
    func durableState() throws -> [[[String]]] {
        try capture.durableState() + ["day", "meal", "submission", "item", "tombstone", "record_source"].map { try rows("SELECT * FROM \($0) ORDER BY rowid") }
    }
    func assertAccounting() throws {
        let full = try ChatHistoryFixture.completeReference(databaseURL: url)
        #expect(try rows("SELECT portableBytes FROM storage_quota") == [[String(try JSONEncoder().encode(full).count)]])
        let originals = full.meals.flatMap(\.photos).reduce(0) { $0 + $1.data.count } + full.coachTurns.flatMap(\.photos).reduce(0) { $0 + $1.data.count }
        #expect(try rows("SELECT originalPhotoBytes FROM storage_quota") == [[String(originals)]])
    }
    static func sharedProgress(mode: Int) -> DiarySnapshot {
        var source = ChatHistoryFixture.snapshot(exchanges: mode == 4 ? 2 : 1)
        for index in source.coachTurns.indices {
            source.coachTurns[index].photos = []
            source.coachTurns[index].photoIDs = source.meals[0].photos.map(\.id)
            let id = source.coachTurns[index].id
            source.coachTurns[index].receipts = [CoachReceipt(operationKey: "\(id)/food/2027-01-14", turnID: id, dayID: source.days[1].id,
                mealID: source.meals[0].id, committedRevision: 1, resultJSON: "{}")]
            if mode == 0 || mode == 2 || mode == 4 {
                source.coachTurns[index].receipts.append(CoachReceipt(operationKey: "\(id)/weight/2027-01-15", turnID: id, dayID: source.days[0].id,
                    weightID: source.weights[0].id, committedRevision: 1, resultJSON: "{}"))
            }
            if mode == 1 || mode == 2 {
                source.coachTurns[index].receipts.append(CoachReceipt(operationKey: "\(id)/workout/2027-01-15", turnID: id, dayID: source.days[0].id,
                    workoutID: source.workouts[0].id, committedRevision: 1, resultJSON: "{}"))
            }
        }
        return source
    }
}
