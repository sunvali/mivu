import Foundation
import ImageIO
import SQLite3
import Testing
@testable import Mivu

@Suite @MainActor struct DiaryProjectionIntegrationTests {
    @Test(arguments: [100, 10_000])
    func productionStartupCaptureAndWorkerRemainBounded(exchanges: Int) async throws {
        let f = try ProjectionIntegrationFixture(exchanges: exchanges - 1, pending: true)
        defer { f.remove() }
        let store = f.store(), model = DiaryViewModel(store: store), transport = ProjectionInference()
        let coach = f.coach(model, transport: transport)
        defer { coach.enterBackground(); model.enterBackground() }
        f.metrics.reset()
        await model.load(createDefaultProfile: false)
        let startup = f.metrics.counters
        #expect(startup.completeReads == 0 && startup.completeReconciles == 0)
        #expect(startup.decodedTurnPayloads <= 20 && startup.originalPhotoBytes == 0)
        let initial = try #require(model.readModel)
        #expect(initial.head.profile.id == f.owner)
        #expect(coach.exchanges.count == 20)
        #expect(!coach.exchanges.contains { $0.id == f.pendingID })
        #expect(coach.hasPendingWork, "Off-page accepted work must remain discoverable")
        coach.resume(); await coach.waitForWorker()
        #expect(try await store.coachResult(turnID: f.pendingID, expectedProfileID: f.owner).state == .completed)
        coach.draft.text = "Synthetic ambiguous portion after reopening"
        let acceptedID = coach.draft.submissionID
        #expect(await coach.send())
        await coach.waitForWorker()
        #expect(try await store.coachResult(turnID: acceptedID, expectedProfileID: f.owner).state == .completed)
        #expect(coach.captureReceipt == acceptedID && coach.draft.text.isEmpty)
        #expect(try f.rows("SELECT COUNT(*) FROM coach_turn") == [[String(exchanges)]])
        f.assertHotReads()
        #expect(await transport.count == 2)
        let after = try f.complete()
        #expect(Set(after.coachTurns.map(\.id)).isSuperset(of: Set(f.source.coachTurns.map(\.id))))
    }

    @Test(arguments: [100, 10_000])
    func productionProfileListingSelectionAndCorrectionAvoidCompleteReads(exchanges: Int) async throws {
        let f = try ProjectionIntegrationFixture(exchanges: exchanges)
        defer { f.remove() }
        let other = try f.addProfile(), store = f.store()
        let suite = "ProjectionSignedOut-" + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(true, forKey: "diarySignedOut")
        let model = DiaryViewModel(store: store, preferences: preferences)
        f.metrics.reset()
        await model.load(createDefaultProfile: false)
        #expect(model.profiles.count == 2 && model.readModel == nil)
        f.assertHotReads()
        await model.switchProfile(f.owner)
        #expect(try #require(model.readModel).head.profile.id == f.owner)
        let before = try await store.meal(id: f.mealID, expectedProfileID: f.owner)
        #expect(!model.todaysMeals.contains { $0.id == f.mealID })
        #expect(await model.change {
            _ = try await store.correctMealProjection(mealID: f.mealID, text: "Synthetic historical correction",
                reviewFirst: true, expectedSelection: try await store.selectionOwnership(expectedProfileID: f.owner), expectedProfileID: f.owner)
        })
        let after = try await store.meal(id: f.mealID, expectedProfileID: f.owner)
        #expect(after.id == before.id && after.items == before.items && after.photos == before.photos)
        #expect(after.submissions.last?.text == "Synthetic historical correction")
        await model.switchProfile(other)
        #expect(try #require(model.readModel).head.profile.id == other)
        await model.switchProfile(f.owner)
        try await model.refresh(profileID: f.owner)
        #expect(try #require(model.readModel).head.profile.id == f.owner)
        f.assertHotReads()
        #expect(f.metrics.counters.originalPhotoBytes == 0)
    }

    @Test(arguments: [100, 10_000])
    func allMutationFamiliesPreserveUnloadedHistory(exchanges: Int) async throws {
        let f = try ProjectionIntegrationFixture(exchanges: exchanges - 1, extraMeals: true)
        defer { f.remove() }
        let store = f.store(), model = DiaryViewModel(store: store)
        await model.load(createDefaultProfile: false)
        _ = try #require(model.readModel)
        let unaffected = Array(f.source.meals.dropFirst())
        var stage = "capture review"
        do {
        f.metrics.reset()
        let captured = try await store.captureProjection(text: "Synthetic review", photos: [f.photo()], reviewFirst: true,
            dayID: f.dayID, at: f.instant, submissionID: UUID(), expectedSelection: try await store.selectionOwnership(expectedProfileID: f.owner), expectedProfileID: f.owner)
        let submission = try #require(captured.submissions.first)
        let item = FoodItem(name: "Synthetic reviewed apple", nutrition: NutritionValues(kcal: 80))
        stage = "apply analysis"
        try await store.applyAnalysis(AnalysisOutput(profileID: f.owner, mealID: captured.id, submissionID: submission.id,
            baseRevision: 0, items: [item]), expectedProfileID: f.owner)
        #expect(await model.acceptReview(mealID: captured.id, submissionID: submission.id, expectedProfileID: f.owner))
        stage = "edit item"
        var edited = item; edited.name = "Synthetic user correction"
        var current = try await store.meal(id: captured.id, expectedProfileID: f.owner)
        try await store.editItem(mealID: current.id, item: edited, expectedRevision: current.revision, expectedProfileID: f.owner)
        stage = "correct note"
        let note = try await store.correctMealProjection(mealID: captured.id, text: "Synthetic note", reviewFirst: true, expectedSelection: try await store.selectionOwnership(expectedProfileID: f.owner), expectedProfileID: f.owner)
        #expect(note.items.first?.name == edited.name)
        stage = "photos"
        let added = f.photo()
        try await store.addPhotos(mealID: captured.id, photos: [added], expectedProfileID: f.owner)
        try await store.deletePhoto(mealID: captured.id, photoID: added.id, expectedProfileID: f.owner)
        stage = "move meal"
        current = try await store.meal(id: captured.id, expectedProfileID: f.owner)
        try await store.moveMeal(current.id, to: f.source.days[1].id, expectedRevision: current.revision,
            expectedDayID: current.dayID, expectedProfileID: f.owner)
        stage = "day completeness"
        try await store.setCompleteness(dayID: f.dayID, .complete, expectedProfileID: f.owner)
        stage = "start day"
        _ = try await store.startDay(at: f.instant, expectedProfileID: f.owner)
        stage = "confirm previous day"
        try await store.confirmPreviousDay(at: f.instant, expectedProfileID: f.owner)
        stage = "goals"
        var goal = f.source.goals[0]; goal.targets.kcal = 2300
        _ = try await store.setGoals(goal, expectedRevision: goal.revision, expectedProfileID: f.owner)
        stage = "profile"
        var profile = f.source.profile; profile.name = "Synthetic renamed profile"
        try await store.updateProfile(profile, expectedProfile: f.source.profile, expectedProfileID: f.owner)
        stage = "weight update"
        let weight = f.source.weights[0]
        _ = try await store.updateWeight(id: weight.id, value: 71, expectedRevision: weight.revision, expectedProfileID: f.owner)
        stage = "weight create/delete"
        let newWeight = try await store.setWeight(dayID: f.source.days[1].id, value: 72, expectedRevision: nil, expectedProfileID: f.owner)
        try await store.deleteWeight(id: newWeight.id, expectedRevision: newWeight.revision, expectedProfileID: f.owner)
        stage = "workout update"
        var workout = f.source.workouts[0]; workout.durationMinutes = 5
        _ = try await store.updateWorkout(workout, expectedRevision: workout.revision, expectedProfileID: f.owner)
        stage = "workout create/delete"
        let created = try await store.createWorkout(dayID: f.dayID, draft: f.workout, expectedProfileID: f.owner)
        try await store.deleteWorkout(id: created.id, expectedRevision: created.revision, expectedProfileID: f.owner)
        stage = "capture atomic batch"
        let preparation = try await store.coachCapturePreparation(at: f.instant, expectedProfileID: f.owner)
        let payload = try f.payload(preparation, text: "Synthetic atomic progress batch")
        let turn = try await store.captureCoachSubmission(payload, expectedSelection: preparation.ownership, expectedProfileID: f.owner)
        stage = "atomic mixed batch"
        let receipts = try await store.applyCoachWrites([.close(date: f.source.days[0].localDate, completeness: .partial),
            .workout(date: f.source.days[1].localDate, draft: f.workout)], turnID: turn.id,
            epoch: preparation.ownership.selectionEpoch, expectedProfileID: f.owner)
        #expect(receipts.count == 2 && Set(receipts.map(\.operationKey)).count == 2)
        stage = "turn state"
        try await store.setCoachTurnState(turnID: turn.id, state: .needsRetry, expectedProfileID: f.owner)
        stage = "turn completion"
        try await store.completeCoachTurn(turnID: turn.id, assistantText: "Synthetic committed result", expectedProfileID: f.owner)
        stage = "meal deletion"
        try await store.deleteMeal(captured.id, expectedProfileID: f.owner)
        stage = "final refresh"
        try await model.refresh(profileID: f.owner)
        f.assertHotReads()
        #expect(f.metrics.counters.originalPhotoBytes == 0)
        stage = "complete export oracle"
        let after = try f.complete()
        #expect(after.meals.filter { $0.id != f.mealID } == unaffected)
        #expect(after.coachTurns.filter { $0.id != turn.id } == f.source.coachTurns)
        #expect(after.meals.first { $0.id == f.mealID } == f.source.meals.first)
        #expect(after.deletedMealIDs.contains(captured.id))
        } catch {
            Issue.record("Mutation stage \(stage), exchanges \(exchanges): \(error)")
            throw error
        }
    }

    @Test(arguments: [false, true])
    func newLegacyWriterRefusesMigratedDatabase(withExpected: Bool) throws {
        let f = try ProjectionIntegrationFixture(exchanges: 100)
        defer { f.remove() }
        let before = try f.durableRows(), database = try DiaryDatabase(url: f.url, diagnostics: f.metrics)
        f.metrics.reset()
        #expect(throws: DiaryError.invalidData) {
            try database.write(f.source, expected: withExpected ? f.source : nil, maximumBytes: ChatHistoryFixture.maximumBytes)
        }
        #expect(f.metrics.counters.completeReads == 0 && f.metrics.counters.completeReconciles == 0)
        #expect(try f.durableRows() == before)
        #expect(try DiaryDatabase(url: f.url).readHead(expectedProfileID: f.owner).revision == f.source.revision)
    }

    @Test func postActivationFailurePreservesMigratedDataForCompatibleRecovery() async throws {
        let f = try ProjectionIntegrationFixture(exchanges: 100)
        defer { f.remove() }
        let store = f.store(), model = DiaryViewModel(store: store)
        await model.load(createDefaultProfile: false)
        _ = try #require(model.readModel)
        let before = try f.complete(), rows = try f.durableRows()
        try f.execute("CREATE TRIGGER fail_projection_commit BEFORE UPDATE ON storage_head BEGIN SELECT RAISE(ABORT, 'synthetic commit failure'); END")
        var draft = MealDraft(); draft.text = "Synthetic failed durable capture"
        #expect(!(await model.capture(draft, dayID: f.dayID, at: f.instant)))
        #expect(model.captureReceipt == nil && model.errorMessage != nil)
        #expect(try f.durableRows() == rows && f.complete() == before)
        try f.execute("DROP TRIGGER fail_projection_commit")
        let compatible = DiaryViewModel(store: f.store())
        await compatible.load(createDefaultProfile: false)
        #expect(try #require(compatible.readModel).head.profile.id == f.owner)
        #expect(try f.rows("PRAGMA user_version") == [["1"]])
        #expect(try f.complete() == before)
        var retry = MealDraft(); retry.text = "Synthetic compatible recovery"
        #expect(await compatible.capture(retry, dayID: f.dayID, at: f.instant))
        #expect(try f.complete().meals.count == before.meals.count + 1)
    }

    @Test(arguments: ["reselect", "signOut", "restore"])
    func actorCaptureAndReconciliationRejectObsoleteSelectionBeforeAcknowledgement(transition: String) async throws {
        let f = try ProjectionIntegrationFixture(exchanges: 100)
        defer { f.remove() }
        let other = try f.addProfile(), store = f.store()
        _ = try await store.selectPagedProfile(f.owner)
        let original = try await store.coachCapturePreparation(at: f.instant, expectedProfileID: f.owner)
        let accepted = try f.payload(original), unsent = try f.payload(original, text: "Synthetic old unsent draft")
        _ = try await store.captureCoachSubmission(accepted, expectedSelection: original.ownership, expectedProfileID: f.owner)
        switch transition {
        case "reselect":
            _ = try await store.selectPagedProfile(other); _ = try await store.selectPagedProfile(f.owner)
        case "signOut":
            await store.signOut(); _ = try await store.selectPagedProfile(f.owner)
        default:
            try await store.restore(f.complete(), expectedProfileID: f.owner)
        }
        let before = try f.durableRows()
        await #expect(throws: DiaryError.wrongOwner) {
            try await store.captureCoachSubmission(unsent, expectedSelection: original.ownership, expectedProfileID: f.owner)
        }
        await #expect(throws: DiaryError.wrongOwner) {
            try await store.captureCoachSubmission(accepted, expectedSelection: original.ownership, expectedProfileID: f.owner)
        }
        await #expect(throws: DiaryError.wrongOwner) {
            try await store.reconcileCoachCapture(submissionID: accepted.submissionID, expectedManifest: accepted.manifest,
                expectedSelection: original.ownership, expectedProfileID: f.owner)
        }
        #expect(try f.durableRows() == before)
        let fresh = try await store.selectionOwnership(expectedProfileID: f.owner)
        #expect(fresh != original.ownership)
        let reconciled = try await store.reconcileCoachCapture(submissionID: accepted.submissionID, expectedManifest: accepted.manifest,
            expectedSelection: fresh, expectedProfileID: f.owner)
        guard case .accepted(let summary) = reconciled else { Issue.record("Durable input must recover under fresh ownership"); return }
        #expect(summary.id == accepted.submissionID)
        #expect(try await store.nextPendingCoachTurn(includeWaitingForConnection: false, expectedProfileID: f.owner)?.id == accepted.submissionID)
    }

    @Test func committedChangesIncludeEmptyGoalAndProfileInvalidationsAndFinishOldSubscriptions() async throws {
        let f = try ProjectionIntegrationFixture(exchanges: 100)
        defer { f.remove() }
        let store = f.store(); _ = try await store.selectPagedProfile(f.owner)
        let changes = await store.changes(expectedProfileID: f.owner)
        var iterator = changes.makeAsyncIterator()
        var goal = f.source.goals[0]; goal.targets.kcal = 2400
        _ = try await store.setGoals(goal, expectedRevision: goal.revision, expectedProfileID: f.owner)
        _ = try #require(await iterator.next(), "A goal-only durable commit must not disappear as empty")
        #expect(try await store.diaryReadModel(expectedProfileID: f.owner).activeGoal?.targets.kcal == 2400)
        var profile = f.source.profile; profile.name = "Synthetic profile-only commit"
        try await store.updateProfile(profile, expectedProfile: f.source.profile, expectedProfileID: f.owner)
        _ = try #require(await iterator.next(), "A profile-only durable commit must publish")
        #expect(try await store.diaryHead(expectedProfileID: f.owner).profile.name == profile.name)
        try f.execute("CREATE TRIGGER fail_change_commit BEFORE UPDATE ON storage_head BEGIN SELECT RAISE(ABORT, 'synthetic rollback'); END")
        await #expect(throws: DiaryError.persistenceFailed) {
            try await store.setCompleteness(dayID: f.dayID, .complete, expectedProfileID: f.owner)
        }
        try f.execute("DROP TRIGGER fail_change_commit")
        await store.signOut()
        #expect(await iterator.next() == nil, "Rollback must not publish; obsolete stream must finish")
    }

    @Test func delayedProjectionCannotOverwriteSameProfileReselectionOrNewGoal() async throws {
        let f = try ProjectionIntegrationFixture(exchanges: 100)
        defer { f.remove() }
        let other = try f.addProfile(), store = f.store(), gate = ProjectionReadGate()
        let model = DiaryViewModel(store: store, actionReadModelLoading: { owner in
            let value = try await store.diaryReadModel(expectedProfileID: owner)
            await gate.pauseIfArmed()
            return value
        })
        await model.load(createDefaultProfile: false)
        _ = try #require(model.readModel)
        await gate.arm()
        let oldRefresh = Task { try await model.refresh(profileID: f.owner) }
        do { try await boundedWait { try await gate.waitUntilReached() } }
        catch { await gate.release(); _ = try? await oldRefresh.value; throw error }
        var goal = f.source.goals[0]; goal.targets.kcal = 2500
        _ = try await store.setGoals(goal, expectedRevision: goal.revision, expectedProfileID: f.owner)
        await model.switchProfile(other); await model.switchProfile(f.owner)
        #expect(try #require(model.readModel).activeGoal?.targets.kcal == 2500)
        await gate.release(); try await oldRefresh.value
        #expect(try #require(model.readModel).activeGoal?.targets.kcal == 2500)
        let currentHead = try await store.diaryHead(expectedProfileID: f.owner)
        #expect(try #require(model.readModel).head.revision == currentHead.revision)
    }

    @Test func unconfiguredBackupDoesNoExportDuringActivityRefresh() async throws {
        let f = try ProjectionIntegrationFixture(exchanges: 100)
        defer { f.remove() }
        let store = f.store(), stages = ProjectionExportGate()
        let backup = FolderBackup(directory: f.root.appending(path: "backup-settings"))
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root,
            checkpoint: { stage, _ in await stages.observe(stage) })
        let model = DiaryViewModel(store: store, backup: backup, exportCoordinator: coordinator)
        await model.load(createDefaultProfile: false)
        _ = try #require(model.readModel)
        f.metrics.reset()
        for _ in 0..<5 { try await model.refresh(profileID: f.owner) }
        #expect(await model.change { try await store.setCompleteness(dayID: f.dayID, .partial, expectedProfileID: f.owner) })
        await model.waitForBackup()
        #expect(!(await backup.status(profileID: f.owner)).configured)
        #expect(await stages.cloneCount == 0)
        f.assertHotReads()
        #expect(f.metrics.counters.originalPhotoBytes == 0)
    }

    @Test func configuredBackupCoalescesRefreshAndSavesOneLatestSuccessor() async throws {
        let f = try ProjectionIntegrationFixture(exchanges: 100)
        defer { f.remove() }
        let store = f.store(), gate = ProjectionExportGate()
        let folder = f.root.appending(path: "provider", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let backup = FolderBackup(directory: f.root.appending(path: "backup-settings"))
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root,
            checkpoint: { stage, _ in await gate.observe(stage) })
        let model = DiaryViewModel(store: store, backup: backup, exportCoordinator: coordinator)
        await model.load(createDefaultProfile: false)
        _ = try #require(model.readModel)
        await model.selectBackupFolder(folder); await model.waitForBackup()
        let target = folder.appending(path: FolderBackup.filename(profileID: f.owner))
        #expect(FileManager.default.fileExists(atPath: target.path))
        await gate.arm()
        #expect(await model.change { try await store.setCompleteness(dayID: f.dayID, .complete, expectedProfileID: f.owner) })
        do { try await boundedWait { try await gate.waitUntilReached() } }
        catch { await gate.release(); await model.waitForBackup(); throw error }
        for _ in 0..<10 { try await model.refresh(profileID: f.owner) }
        #expect(await model.change { try await store.setCompleteness(dayID: f.dayID, .partial, expectedProfileID: f.owner) })
        let newest = try await store.diaryHead(expectedProfileID: f.owner)
        await gate.release(); await model.waitForBackup()
        let exported = try DiaryArchive.decode(Data(contentsOf: target))
        #expect(exported.revision == newest.revision && exported.coachTurns.count == 100)
        #expect(await gate.cloneCount == 2, "Activity refresh coalesces; one new commit schedules one successor")
        #expect((await backup.status(profileID: f.owner)).savedAt != nil)
        #expect((await backup.status(profileID: f.owner)).pendingError == nil)
        f.assertHotReads()
    }

    @Test func applicationSharesTwoPhotoPermitsAcrossDisplayImportAndExistingWorker() async throws {
        let f = try ProjectionIntegrationFixture(exchanges: 100, pending: true, workerPhoto: true)
        defer { f.remove() }
        let observed = AsyncStream<PhotoWorkLimiter.Statistics>.makeStream()
        let limiter = PhotoWorkLimiter(observe: { observed.continuation.yield($0) })
        defer { observed.continuation.finish() }
        let store = f.store(), model = DiaryViewModel(store: store, photoWorkLimiter: limiter)
        let coach = f.coach(model, transport: ProjectionInference())
        defer { coach.enterBackground(); model.enterBackground() }
        await model.load(createDefaultProfile: false)
        _ = try #require(model.readModel)
        let loader = try #require(model.photoLoader)
        let ref = try #require(try await store.meal(id: f.mealID, expectedProfileID: f.owner).photos.first)
        let blockers = ProjectionPermitGate()
        let first = Task { try await limiter.withPermit { await blockers.hold() } }
        let second = Task { try await limiter.withPermit { await blockers.hold() } }
        do { try await boundedWait { try await blockers.waitForTwo() } }
        catch { await blockers.release(); _ = try? await first.value; _ = try? await second.value; throw error }
        let display = Task { try await loader.thumbnail(for: ref, pixelSize: 16) }
        let preparation = PhotoPreparation(limiter: model.photoWorkLimiter), generation = preparation.begin()
        let data = SyntheticConnectionProbe.image
        let imported = Task { try await preparation.load(generation) { try #require(PhotoImport.jpeg(data)) } }
        coach.resume()
        do {
            try await boundedWait {
                for await state in observed.stream { if state.queued >= 3 { return } }
                throw ProjectionTestFailure.closed
            }
        } catch {
            await blockers.release(); _ = try? await first.value; _ = try? await second.value
            _ = try? await display.value; _ = try? await imported.value
            await coach.waitForWorker(); throw error
        }
        #expect(await limiter.statistics().active == 2)
        await blockers.release()
        try await first.value; try await second.value
        // Worker status commits invalidate queued display work. An obsolete thumbnail must never publish.
        let displayResult = await display.result
        #expect(try await imported.value?.isEmpty == false)
        await coach.waitForWorker()
        switch displayResult {
        case .success(let thumbnail): #expect(thumbnail.decodedCost > 0)
        case .failure(let error): #expect(error as? DiaryPhotoError == .staleRequest)
        }
        // The same unchanged reference must load again under the final application request generation.
        #expect(try await loader.thumbnail(for: ref, pixelSize: 16).decodedCost > 0)
        #expect(try await store.coachResult(turnID: f.pendingID, expectedProfileID: f.owner).state == .completed)
        let finalWork = await limiter.statistics()
        #expect(finalWork.active == 0 && finalWork.peakActive == 2)
    }

    @Test func photoInvalidationReissuesSameReferenceAndResetsScopeBeforeSelectionPublication() async throws {
        let f = try ProjectionIntegrationFixture(exchanges: 100)
        defer { f.remove() }
        let other = try f.addProfile(), store = f.store(), model = DiaryViewModel(store: store)
        await model.load(createDefaultProfile: false)
        _ = try #require(model.readModel)
        let loader = try #require(model.photoLoader)
        let reference = try #require(try await store.meal(id: f.mealID, expectedProfileID: f.owner).photos.first)
        _ = try await loader.thumbnail(for: reference, pixelSize: 16)
        let request = model.photoRequestGeneration
        #expect(await model.change {
            _ = try await store.correctMealProjection(mealID: f.mealID, text: "Synthetic same-photo note", expectedSelection: try await store.selectionOwnership(expectedProfileID: f.owner), expectedProfileID: f.owner)
        })
        #expect(model.photoRequestGeneration > request)
        #expect(await loader.statistics().cachedCount == 0)
        let unchanged = try #require(try await store.meal(id: f.mealID, expectedProfileID: f.owner).photos.first)
        #expect(unchanged == reference)
        #expect(try await loader.thumbnail(for: unchanged, pixelSize: 16).decodedCost > 0)
        let beforeSwitch = model.photoRequestGeneration
        await model.switchProfile(other)
        #expect(try #require(model.readModel).head.profile.id == other)
        #expect(model.photoRequestGeneration > beforeSwitch)
        await #expect(throws: DiaryError.wrongOwner) { try await loader.thumbnail(for: reference, pixelSize: 16) }
    }
    @Test(arguments: ["reselect", "restore"], ["capture", "correction"])
    func manualCaptureAndCorrectionRejectObsoleteActorOwnership(transition: String, operation: String) async throws {
        let f = try ProjectionIntegrationFixture(exchanges: 100); defer { f.remove() }
        let other = try f.addProfile(), store = f.store(), acceptedID = UUID()
        _ = try await store.selectProfile(f.owner)
        let token = try await store.selectionOwnership(expectedProfileID: f.owner)
        if operation == "capture" {
            _ = try await store.captureProjection(text: "Synthetic accepted manual capture", photos: [], reviewFirst: true,
                dayID: f.dayID, at: f.instant, submissionID: acceptedID, expectedSelection: try await store.selectionOwnership(expectedProfileID: f.owner), expectedProfileID: f.owner)
        } else {
            _ = try await store.correctMealProjection(mealID: f.mealID, text: "Synthetic accepted manual correction",
                reviewFirst: true, submissionID: acceptedID, expectedSelection: try await store.selectionOwnership(expectedProfileID: f.owner), expectedProfileID: f.owner)
        }
        if transition == "reselect" { _ = try await store.selectProfile(other); _ = try await store.selectProfile(f.owner) }
        else {
            let archive = try await store.snapshotForExport(expectedProfileID: f.owner)
            try await store.restore(archive, expectedProfileID: f.owner)
        }
        let before = try await store.snapshotForExport(expectedProfileID: f.owner)
        f.metrics.reset()
        await #expect(throws: DiaryError.wrongOwner) { try await store.dayAssignment(expectedSelection: token, expectedProfileID: f.owner) }
        await #expect(throws: DiaryError.wrongOwner) { try await store.startDay(at: f.instant, expectedSelection: token, expectedProfileID: f.owner) }
        await #expect(throws: DiaryError.wrongOwner) { try await store.confirmPreviousDay(at: f.instant, expectedSelection: token, expectedProfileID: f.owner) }
        await #expect(throws: DiaryError.wrongOwner) { try await store.capturedMeal(submissionID: acceptedID, expectedSelection: token, expectedProfileID: f.owner) }
        for submissionID in [UUID(), acceptedID] {
            await #expect(throws: DiaryError.wrongOwner) {
                if operation == "capture" {
                    _ = try await store.captureProjection(text: "Synthetic accepted manual capture", photos: [], reviewFirst: true,
                        dayID: f.dayID, at: f.instant, submissionID: submissionID, expectedSelection: token, expectedProfileID: f.owner)
                } else {
                    _ = try await store.correctMealProjection(mealID: f.mealID, text: "Synthetic accepted manual correction",
                        reviewFirst: true, submissionID: submissionID, expectedSelection: token, expectedProfileID: f.owner)
                }
            }
        }
        f.assertHotReads()
        #expect(try await store.snapshotForExport(expectedProfileID: f.owner) == before)
    }

    @Test(arguments: ["sqlite", "json"], [100, 10_000])
    func existingProfileStartupDiscoversAndAutomaticallyMigrates(format: String, exchanges: Int) async throws {
        let f = try AutomaticMigrationFixture(format: format, exchanges: exchanges); defer { f.remove() }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: f.root, diagnostics: metrics)
        let model = DiaryViewModel(store: store)
        await model.load(createDefaultProfile: false)
        #expect(model.profiles.map(\.id) == [f.source.profile.id])
        #expect(try #require(model.readModel).head.profile == f.source.profile)
        #expect(try ChatHistoryFixture.strings(f.database, "PRAGMA user_version") == [["1"]])
        #expect(try await store.snapshotForExport(expectedProfileID: f.source.profile.id) == f.source)
        if format == "json" { #expect(try Data(contentsOf: f.original) == f.originalBytes) }
        metrics.reset()
        let reopened = DiaryViewModel(store: DiaryStore(directory: f.root, diagnostics: metrics))
        await reopened.load(createDefaultProfile: false)
        #expect(try #require(reopened.readModel).head.profile.id == f.source.profile.id)
        #expect(reopened.profiles.count == 1 && reopened.latestCoachPage?.exchanges.count == 20)
        #expect(metrics.counters.completeReads == 0 && metrics.counters.completeReconciles == 0)
        #expect(metrics.counters.decodedTurnPayloads <= 20 && metrics.counters.originalPhotoBytes == 0)
    }

    @Test(arguments: ["sqlite", "json"], [100, 10_000])
    func existingProfileDirectSelectionMigratesAndMetadataListingRemainsBounded(format: String, exchanges: Int) async throws {
        let f = try AutomaticMigrationFixture(format: format, exchanges: exchanges); defer { f.remove() }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: f.root, diagnostics: metrics)
        let selected = try await store.selectProfile(f.source.profile.id)
        #expect(selected.head.profile == f.source.profile && selected.head.revision == f.source.revision)
        #expect(try await store.snapshotForExport(expectedProfileID: f.source.profile.id) == f.source)
        metrics.reset()
        #expect(try await store.profiles() == [f.source.profile])
        _ = try await store.selectProfile(f.source.profile.id)
        #expect(metrics.counters.completeReads == 0 && metrics.counters.completeReconciles == 0)
        #expect(metrics.counters.decodedTurnPayloads == 0 && metrics.counters.originalPhotoBytes == 0)
    }

    @Test(arguments: ["sqlite", "json"])
    func automaticMigrationFailureRetainsOriginalAndCompatibleRetryRecovers(format: String) async throws {
        let f = try AutomaticMigrationFixture(format: format, exchanges: 100); defer { f.remove() }
        let store = DiaryStore(directory: f.root, migrationCheckpoint: { _, _ in throw DiaryError.persistenceFailed })
        await #expect(throws: DiaryError.persistenceFailed) { try await store.selectProfile(f.source.profile.id) }
        #expect(try Data(contentsOf: f.original) == f.originalBytes)
        if format == "sqlite" { #expect(try ChatHistoryFixture.strings(f.database, "PRAGMA user_version") == [["0"]]) }
        else { #expect(!FileManager.default.fileExists(atPath: f.database.deletingLastPathComponent().path)) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.path).allSatisfy { !$0.hasPrefix("migration-") })
        await #expect(throws: DiaryError.noProfile) { try await store.diaryHead(expectedProfileID: f.source.profile.id) }
        let recovered = DiaryStore(directory: f.root)
        _ = try await recovered.selectProfile(f.source.profile.id)
        #expect(try await recovered.snapshotForExport(expectedProfileID: f.source.profile.id) == f.source)
        #expect(try ChatHistoryFixture.strings(f.database, "PRAGMA user_version") == [["1"]])
    }

    @Test func existingProjectionReadOpenDoesNotAcquireSchemaWriteLock() throws {
        let f = try ProjectionIntegrationFixture(exchanges: 100); defer { f.remove() }
        let held = try DiaryDatabase(url: f.url)
        try held.execute("BEGIN IMMEDIATE")
        defer { try? held.execute("ROLLBACK") }
        let cursor = try held.domainStatement("SELECT revision FROM storage_head WHERE id = 1")
        defer { sqlite3_finalize(cursor) }
        #expect(try held.mutationStep(cursor))
        let schema = try held.mutationInteger("PRAGMA schema_version")
        // An existing reserved writer still permits ordinary readers in DELETE-journal mode.
        let reader = try DiaryDatabase(url: f.url, diagnostics: f.metrics)
        #expect(try reader.diaryReadModel(expectedProfileID: f.owner).head.revision == f.source.revision)
        #expect(try reader.mutationInteger("PRAGMA schema_version") == schema)
        f.assertHotReads()
    }

    @Test func explicitBackupRetryReschedulesFailedUnchangedRevision() async throws {
        let f = try ProjectionIntegrationFixture(exchanges: 100); defer { f.remove() }
        let store = f.store(), failure = ProjectionExportFailureOnce()
        let folder = f.root.appending(path: "retry-provider", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let backup = FolderBackup(directory: f.root.appending(path: "retry-settings"))
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root,
            checkpoint: { stage, _ in try await failure.observe(stage) })
        let model = DiaryViewModel(store: store, backup: backup, exportCoordinator: coordinator)
        await model.load(createDefaultProfile: false)
        _ = try #require(model.readModel)
        await model.selectBackupFolder(folder); await model.waitForBackup()
        let revision = try await store.diaryHead(expectedProfileID: f.owner).revision
        #expect(model.backupStatus.pendingError != nil)
        #expect(await failure.cloneCount == 1)
        model.retryBackup(); await model.waitForBackup()
        #expect(await failure.cloneCount == 2)
        #expect(model.backupStatus.pendingError == nil && model.backupStatus.savedAt != nil)
        let saved = try DiaryArchive.read(folder.appending(path: FolderBackup.filename(profileID: f.owner)))
        #expect(saved.revision == revision && saved.coachTurns.count == 100)
    }

    @Test(arguments: [false, true])
    func repeatedManualCapturePreservesFeedbackAndOriginalFacts(withPhoto: Bool) async throws {
        let f = try ProjectionIntegrationFixture(exchanges: 100); defer { f.remove() }
        let store = f.store(), model = DiaryViewModel(store: store)
        await model.load(createDefaultProfile: false)
        var draft = MealDraft(); draft.text = "Synthetic manual idempotent capture"
        if withPhoto { draft.photos = [SyntheticConnectionProbe.image] }
        #expect(await model.capture(draft, dayID: f.dayID, at: f.instant))
        let event = try #require(model.companionCaptureEvent), mealID = try #require(model.savedMealID)
        #expect(await model.capture(draft, dayID: f.dayID, at: f.instant))
        #expect(model.companionCaptureEvent == event && model.savedMealID == mealID)
        let saved = try await store.snapshotForExport(expectedProfileID: f.owner)
        #expect(saved.meals.count == f.source.meals.count + 1)
        let meal = try #require(saved.meals.first { $0.id == mealID })
        #expect(meal.submissions.map(\.id) == [draft.submissionID])
        #expect(meal.photos.map(\.data) == draft.photos)
    }

    @Test(arguments: ["weight", "workout", "goal"])
    func chronologicalLedgersPageBackdatedAndEqualTimeRecordsWithoutLoss(kind: String) async throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 100)
        let clock = source.days[0].startAt
        var expected: [(UUID, Double, Int)] = []
        if kind == "weight" {
            source.weights = (0..<65).map { index in
                let time = clock.addingTimeInterval(Double((index * 17) % 11) * 60)
                let value = WeightEntry(dayID: nil, measuredAt: time, value: 70 + Double(index) / 100)
                expected.append((value.id, time.timeIntervalSinceReferenceDate, index)); return value
            }
        } else if kind == "workout" {
            source.workouts = (0..<65).map { index in
                let time = clock.addingTimeInterval(Double((index * 17) % 11) * 60)
                let value = WorkoutSession(dayID: source.days[0].id, performedAt: time, timePrecision: .exact,
                    revision: 1, kind: .other, durationMinutes: index + 1, exercises: [], estimatedBurnKcal: nil, burnSource: nil)
                expected.append((value.id, time.timeIntervalSinceReferenceDate, index)); return value
            }
        } else {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: source.profile.timeZoneID)!
            source.goals = (0..<65).map { index in
                let offset = (index * 17) % 65
                let date = calendar.date(byAdding: .day, value: offset, to: clock)!
                let value = GoalRecord(effectiveLocalDate: ProgressDate.label(date, zone: source.profile.timeZoneID),
                    timeZoneID: source.profile.timeZoneID, targets: NutritionValues(kcal: Double(1800 + index)), goalWeightKg: nil, exerciseCreditEnabled: false)
                expected.append((value.id, Double(offset), index)); return value
            }
        }
        let fixture = try CaptureFixture(snapshot: source); defer { fixture.remove() }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: fixture.root, diagnostics: metrics)
        _ = try await store.selectPagedProfile(source.profile.id)
        let wanted = expected.sorted { $0.1 == $1.1 ? $0.2 > $1.2 : $0.1 > $1.1 }.map(\.0)
        metrics.reset()
        func page(_ before: Int?) async throws -> ([UUID], Int?, Bool) {
            if kind == "weight" {
                let result = try await store.weightHistory(before: before, expectedProfileID: source.profile.id)
                return (result.values.map(\.id), result.cursor, result.hasMore)
            }
            if kind == "workout" {
                let result = try await store.workoutHistory(before: before, expectedProfileID: source.profile.id)
                return (result.values.map(\.id), result.cursor, result.hasMore)
            }
            let result = try await store.goalHistory(before: before, expectedProfileID: source.profile.id)
            return (result.values.map(\.id), result.cursor, result.hasMore)
        }
        let latest = try await page(nil)
        #expect(latest.0 == Array(wanted.prefix(30)) && latest.2)
        let latestCursor = try #require(latest.1)
        let older = try await page(latestCursor)
        #expect(older.0 == Array(wanted[30..<60]) && older.2)
        let olderCursor = try #require(older.1)
        let oldest = try await page(olderCursor)
        #expect(oldest.0 == Array(wanted.suffix(5)) && !oldest.2 && oldest.1 == nil)
        let actual = latest.0 + older.0 + oldest.0
        #expect(actual == wanted && Set(actual).count == 65)
        #expect(try await page(nil).0 == latest.0, "Latest must return the same chronological boundary")
        if kind == "workout" {
            let stored = try await store.coachWorkout(id: wanted[0], expectedProfileID: source.profile.id)
            #expect(stored.dayID == source.days[0].id)
            #expect(try await store.trackingDay(id: stored.dayID, expectedProfileID: source.profile.id).timeZoneID == source.days[0].timeZoneID)
        }
        #expect(metrics.counters.completeReads == 0 && metrics.counters.completeReconciles == 0 && metrics.counters.originalPhotoBytes == 0)
    }
}

private struct ProjectionIntegrationFixture: Sendable {
    let capture: CaptureFixture
    let metrics = DiaryQueryDiagnostics()
    var root: URL { capture.root }
    var url: URL { capture.url }
    var source: DiarySnapshot { capture.before }
    var owner: UUID { source.profile.id }
    var mealID: UUID { source.meals[0].id }
    var dayID: UUID { source.days[0].id }
    var pendingID: UUID { source.coachTurns[7].id }
    var instant: Date { source.days[0].startAt }
    var workout: WorkoutDraft { WorkoutDraft(kind: .other, durationMinutes: 4, exercises: [], estimatedBurnKcal: nil, burnSource: nil) }
    init(exchanges: Int, pending: Bool = false, workerPhoto: Bool = false, extraMeals: Bool = false) throws {
        var value = ChatHistoryFixture.snapshot(exchanges: exchanges)
        for index in value.coachTurns.indices {
            value.coachTurns[index].state = .completed
            for photo in value.coachTurns[index].photos.indices { value.coachTurns[index].photos[photo].data = SyntheticConnectionProbe.image }
        }
        for index in value.meals.indices {
            for photo in value.meals[index].photos.indices { value.meals[index].photos[photo].data = SyntheticConnectionProbe.image }
        }
        if pending {
            value.coachTurns[7].state = .captured
            if workerPhoto {
                let photo = MealPhoto(data: SyntheticConnectionProbe.image, createdAt: value.coachTurns[7].capturedAt)
                value.coachTurns[7].photos = [photo]; value.coachTurns[7].photoIDs = [photo.id]
            }
        }
        if extraMeals {
            for _ in 0..<8 { var meal = value.meals[0]; meal.id = UUID(); value.meals.append(meal) }
        }
        guard CGImageSourceCreateWithData(SyntheticConnectionProbe.image as CFData, nil) != nil else { throw ProjectionTestFailure.invalidFixture }
        capture = try CaptureFixture(snapshot: value)
    }
    func remove() { capture.remove() }
    func store() -> DiaryStore { let clock = instant; return DiaryStore(directory: root, currentTime: { clock }, diagnostics: metrics) }
    @MainActor func coach(_ diary: DiaryViewModel, transport: ProjectionInference) -> CoachViewModel {
        let connection = ChatGPTConnection(auth: AuthSession(store: CredentialStore(service: "Projection-" + UUID().uuidString)),
            jobStore: ProbeJobStore(directory: root.appending(path: "probe-jobs")))
        return CoachViewModel(diary: diary, connection: connection, inference: { { input, tools in try await transport.infer(input, tools) } })
    }
    func photo() -> MealPhoto { MealPhoto(data: SyntheticConnectionProbe.image, createdAt: instant) }
    func payload(_ preparation: CoachCapturePreparation, text: String = "Synthetic accepted draft") throws -> CoachSubmissionPayload {
        try CoachSubmissionPayload(submissionID: UUID(), text: text, attachments: [], context: preparation.context)
    }
    func addProfile() throws -> UUID {
        var other = source; other.profile.id = UUID(); other.profile.name = "ZZ synthetic other profile"
        let target = root.appending(path: other.profile.id.uuidString + ".sqlite/diary.sqlite")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DiaryDatabase(url: target, create: true).write(other, expected: nil, maximumBytes: ChatHistoryFixture.maximumBytes)
        try DiaryDatabase(url: target).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        return other.profile.id
    }
    func rows(_ sql: String) throws -> [[String]] { try capture.rows(sql) }
    func execute(_ sql: String) throws { try capture.execute(sql) }
    func complete() throws -> DiarySnapshot { try ChatHistoryFixture.completeReference(databaseURL: url) }
    func durableRows() throws -> [[[String]]] { try capture.durableState() }
    func assertHotReads() {
        #expect(metrics.counters.completeReads == 0 && metrics.counters.completeReconciles == 0)
    }
}

private actor ProjectionInference {
    private(set) var count = 0
    func infer(_ input: [CoachInferenceInput], _ tools: Data) throws -> CoachInferenceResult {
        count += 1
        return CoachInferenceResult(model: "synthetic", text: "", calls: [CoachToolCall(id: "clarify", callID: "clarify",
            name: "ask_clarification", namespace: "mivu", arguments: "{\"kind\":\"portion\"}")], outputItems: [])
    }
}

private actor ProjectionReadGate {
    private var armed = false
    private var reached = false
    private let entered = AsyncStream<Void>.makeStream()
    private var resume: CheckedContinuation<Void, Never>?
    func arm() { armed = true }
    func pauseIfArmed() async {
        guard armed else { return }; armed = false; reached = true; entered.continuation.yield(())
        await withCheckedContinuation { resume = $0 }
    }
    func waitUntilReached() async throws {
        if reached { return }
        for await _ in entered.stream { return }
        throw CancellationError()
    }
    func release() { resume?.resume(); resume = nil }
}

private actor ProjectionExportGate {
    private var armed = false
    private var reached = false
    private let entered = AsyncStream<Void>.makeStream()
    private var resume: CheckedContinuation<Void, Never>?
    private(set) var cloneCount = 0
    func arm() { armed = true; cloneCount = 0 }
    func observe(_ stage: DiaryExportStage) async {
        if stage == .cloneReady { cloneCount += 1 }
        guard armed, stage == .providerWritten else { return }
        armed = false; reached = true; entered.continuation.yield(())
        await withCheckedContinuation { resume = $0 }
    }
    func waitUntilReached() async throws {
        if reached { return }
        for await _ in entered.stream { return }
        throw CancellationError()
    }
    func release() { resume?.resume(); resume = nil }
}

private actor ProjectionPermitGate {
    private var held: [CheckedContinuation<Void, Never>] = []
    private let entered = AsyncStream<Void>.makeStream()
    func hold() async {
        await withCheckedContinuation { continuation in
            held.append(continuation)
            if held.count == 2 { entered.continuation.yield(()) }
        }
    }
    func waitForTwo() async throws {
        if held.count >= 2 { return }
        for await _ in entered.stream { return }
        throw CancellationError()
    }
    func release() { let waiting = held; held = []; waiting.forEach { $0.resume() } }
}

private enum ProjectionTestFailure: Error { case timeout, closed, invalidFixture }

// The deadline only fails a missing entry; ordering comes from explicit actor signals.
private func boundedWait(_ operation: @escaping @Sendable () async throws -> Void) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await operation() }
        group.addTask { try await Task.sleep(for: .seconds(10)); throw ProjectionTestFailure.timeout }
        defer { group.cancelAll() }
        _ = try await group.next()
    }
}

private actor ProjectionExportFailureOnce {
    private var failed = false
    private(set) var cloneCount = 0
    func observe(_ stage: DiaryExportStage) throws {
        if stage == .cloneReady { cloneCount += 1 }
        if stage == .providerWrite, !failed { failed = true; throw DiaryError.persistenceFailed }
    }
}

private struct AutomaticMigrationFixture {
    let root: URL
    let source: DiarySnapshot
    let database: URL
    let original: URL
    let originalBytes: Data
    init(format: String, exchanges: Int) throws {
        root = URL.temporaryDirectory.appending(path: "AutomaticMigration-" + UUID().uuidString)
        var value = ChatHistoryFixture.snapshot(exchanges: exchanges)
        for index in value.coachTurns.indices {
            value.coachTurns[index].state = .completed
            for photo in value.coachTurns[index].photos.indices { value.coachTurns[index].photos[photo].data = SyntheticConnectionProbe.image }
        }
        for index in value.meals.indices {
            for photo in value.meals[index].photos.indices { value.meals[index].photos[photo].data = SyntheticConnectionProbe.image }
        }
        source = value
        database = root.appending(path: value.profile.id.uuidString + ".sqlite/diary.sqlite")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if format == "sqlite" {
            try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
            try DiaryDatabase(url: database, create: true).write(value, expected: nil, maximumBytes: ChatHistoryFixture.maximumBytes)
            original = database
        } else {
            original = root.appending(path: value.profile.id.uuidString + ".json")
            try JSONEncoder().encode(value).write(to: original)
        }
        originalBytes = try Data(contentsOf: original)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
