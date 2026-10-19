import Foundation
import Darwin

enum DiaryProfileMigrationStage: Sendable { case beforeCommit, beforeInstall }

/// Selected metadata and one serialized writer; complete graphs exist only during explicit interchange.
actor DiaryStore {
    private let directory: URL
    private var pagedHead: DiaryHead?
    private var profileSelectionEpoch: UInt64 = 0
    private var fileIdentities: [UUID: UInt64] = [:]
    private var subscribers: [UUID: AsyncStream<DiaryChanges>.Continuation] = [:]
    private let currentTime: @Sendable () -> Date
    private let diagnostics: DiaryQueryDiagnostics?
    private let maximumFileBytes: Int
    private let migrationCheckpoint: @Sendable (DiaryProfileMigrationStage, URL) throws -> Void
    init(directory: URL, maximumFileBytes: Int = 350_000_000, currentTime: @escaping @Sendable () -> Date = { Date() }, diagnostics: DiaryQueryDiagnostics? = nil,
         migrationCheckpoint: @escaping @Sendable (DiaryProfileMigrationStage, URL) throws -> Void = { _, _ in }) {
        self.directory = directory; self.currentTime = currentTime; self.diagnostics = diagnostics
        self.maximumFileBytes = min(maximumFileBytes, 350_000_000)
        self.migrationCheckpoint = migrationCheckpoint
    }

    func selectionOwnership(expectedProfileID: UUID? = nil) throws -> DiarySelectionOwnership {
        let owner = try selectedOwner(expectedProfileID), head = try diaryHead(expectedProfileID: owner)
        return DiarySelectionOwnership(identity: CoachTimelineIdentity(profileID: owner, timelineGeneration: head.timelineGeneration), selectionEpoch: profileSelectionEpoch)
    }
    private func validateOwnership(_ expected: DiarySelectionOwnership, profileID: UUID) throws {
        guard expected == (try selectionOwnership(expectedProfileID: profileID)) else { throw DiaryError.wrongOwner }
    }
    func validateSelectionOwnership(_ expected: DiarySelectionOwnership) throws {
        try validateOwnership(expected, profileID: expected.identity.profileID)
    }
    func coachCapturePreparation(at: Date, expectedProfileID: UUID) throws -> CoachCapturePreparation {
        let ownership = try selectionOwnership(expectedProfileID: expectedProfileID)
        let head = try diaryHead(expectedProfileID: expectedProfileID)
        return CoachCapturePreparation(ownership: ownership, context: CoachCaptureContext(capturedAt: at,
            timeZoneID: head.profile.timeZoneID, activeDayID: head.activeDayID,
            previousDayConfirmedAt: head.previousDayConfirmedAt, activeConversationSegmentID: head.effectiveConversationSegmentID))
    }
    func captureCoachSubmission(_ payload: CoachSubmissionPayload, expectedSelection: DiarySelectionOwnership,
                                expectedProfileID: UUID) throws -> CoachExchangeSummary {
        try validateOwnership(expectedSelection, profileID: expectedProfileID)
        return try pagedMutation(expectedProfileID) { try $0.captureCoachSubmission(payload, expected: $1, maximumBytes: maximumFileBytes) }
    }
    func reconcileCoachCapture(submissionID: UUID, expectedManifest: CoachSubmissionManifest,
                               expectedSelection: DiarySelectionOwnership, expectedProfileID: UUID) throws -> CoachCaptureReconciliation {
        try validateOwnership(expectedSelection, profileID: expectedProfileID)
        return try pagedConnection(expectedProfileID: expectedProfileID).database.reconcileCoachCapture(
            submissionID: submissionID, expectedManifest: expectedManifest, expectedProfileID: expectedProfileID)
    }
    func changes(expectedProfileID: UUID) -> AsyncStream<DiaryChanges> {
        guard pagedHead?.profile.id == expectedProfileID else { return AsyncStream { $0.finish() } }
        let id = UUID(), pair = AsyncStream<DiaryChanges>.makeStream()
        subscribers[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in Task { await self?.removeSubscriber(id) } }
        return pair.stream
    }
    private func removeSubscriber(_ id: UUID) { subscribers[id] = nil }
    private func finishSubscribers() {
        let old = subscribers.values; subscribers = [:]
        for subscriber in old { subscriber.finish() }
    }
    private func publish<Value: Sendable>(_ commit: DiaryCommit<Value>, database: DiaryDatabase) throws {
        try database.validateFileIdentity()
        pagedHead = commit.head
        // Empty ID sets still represent committed goal/profile metadata changes.
        for subscriber in subscribers.values { subscriber.yield(commit.changes) }
    }
    private func pagedMutation<Value: Sendable>(_ owner: UUID?, _ body: (DiaryDatabase, DiaryHead) throws -> DiaryCommit<Value>) throws -> Value {
        let selected = try selectedOwner(owner)
        let (database, head) = try pagedConnection(expectedProfileID: selected)
        let commit = try body(database, head)
        try publish(commit, database: database)
        return commit.value
    }
    private func selectedOwner(_ owner: UUID?) throws -> UUID {
        guard let selected = pagedHead?.profile.id else { throw DiaryError.noProfile }
        guard owner == nil || owner == selected else { throw DiaryError.wrongOwner }
        return selected
    }
    private func refreshCoachHead(expectedProfileID: UUID) throws {
        let selected = try diaryHead(expectedProfileID: expectedProfileID)
        let (database, _) = try pagedConnection(expectedProfileID: expectedProfileID)
        let current = try database.readHead(expectedProfileID: expectedProfileID)
        guard current.timelineGeneration == selected.timelineGeneration, current.revision >= selected.revision else { throw DiaryError.staleRevision }
        if current.revision != selected.revision, let token = selected.lineage?.last {
            guard current.lineage?.contains(token) == true else { throw DiaryError.staleRevision }
        }
        pagedHead = current
    }
    func profiles() throws -> [DiaryProfile] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let ids = Set(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["sqlite", "json"].contains($0.pathExtension) }.compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) })
        return try ids.map { id in
            try ensureDatabase(for: id)
            return try DiaryDatabase(url: file(id), diagnostics: diagnostics).profileMetadata(expectedProfileID: id)
        }.sorted { $0.name < $1.name }
    }
    func selectProfile(_ id: UUID) throws -> DiaryReadModel {
        try ensureDatabase(for: id)
        let identity = try fileIdentity(file(id))
        let database = try DiaryDatabase(url: file(id), diagnostics: diagnostics, expectedFileIdentity: identity)
        if try database.mutationInteger("PRAGMA user_version") != 1 {
            let checkpoint = migrationCheckpoint, source = file(id)
            try database.migrateForPagedStorage(maximumBytes: maximumFileBytes, beforeCommit: {
                try checkpoint(.beforeCommit, source)
            })
        }
        let projection = try database.diaryReadModel(expectedProfileID: id)
        try database.validateFileIdentity()
        finishSubscribers(); profileSelectionEpoch &+= 1
        pagedHead = projection.head; fileIdentities[id] = identity
        return projection
    }
    func selectPagedProfile(_ id: UUID) throws -> DiaryHead { try selectProfile(id).head }
    func createProfile(_ profile: DiaryProfile) throws -> DiaryReadModel {
        var snapshot = DiarySnapshot(profile: profile); snapshot.lineage = [UUID()]
        return try importProfile(snapshot)
    }
    func importProfile(_ incoming: DiarySnapshot) throws -> DiaryReadModel {
        guard !exists(incoming.profile.id) else { throw DiaryError.invalidData }
        try incoming.validate(); try createDatabase(incoming)
        return try selectProfile(incoming.profile.id)
    }
    func signOut() { finishSubscribers(); pagedHead = nil; profileSelectionEpoch &+= 1 }
    func diaryHead(expectedProfileID: UUID) throws -> DiaryHead {
        guard let head = pagedHead else { throw DiaryError.noProfile }
        guard head.profile.id == expectedProfileID else { throw DiaryError.wrongOwner }
        guard try fileIdentity(file(expectedProfileID)) == fileIdentities[expectedProfileID] else { throw DiaryError.persistenceFailed }
        return head
    }
    func pagedConnection(expectedProfileID: UUID) throws -> (database: DiaryDatabase, head: DiaryHead) {
        let head = try diaryHead(expectedProfileID: expectedProfileID)
        guard let identity = fileIdentities[expectedProfileID] else { throw DiaryError.persistenceFailed }
        return (try DiaryDatabase(url: file(expectedProfileID), diagnostics: diagnostics, expectedFileIdentity: identity), head)
    }
    func diaryReadModel(expectedProfileID: UUID) throws -> DiaryReadModel { try pagedConnection(expectedProfileID: expectedProfileID).database.diaryReadModel(expectedProfileID: expectedProfileID) }
    func diaryDay(id: UUID, expectedProfileID: UUID) throws -> DiaryDayReadModel { try pagedConnection(expectedProfileID: expectedProfileID).database.diaryDay(id: id, expectedProfileID: expectedProfileID) }
    func meal(id: UUID, expectedProfileID: UUID) throws -> MealReadModel { try pagedConnection(expectedProfileID: expectedProfileID).database.meal(id: id, expectedProfileID: expectedProfileID) }
    func photoContent(_ reference: DiaryPhotoReference, expectedProfileID: UUID) throws -> Data { try pagedConnection(expectedProfileID: expectedProfileID).database.photoContent(reference, expectedProfileID: expectedProfileID) }
    func coachPage(_ request: CoachPageRequest, expectedProfileID: UUID) throws -> CoachPage { try pagedConnection(expectedProfileID: expectedProfileID).database.coachPage(request, expectedProfileID: expectedProfileID) }
    func coachPage(_ request: CoachPageRequest, expectedSelection: DiarySelectionOwnership) throws -> CoachPage {
        try validateOwnership(expectedSelection, profileID: expectedSelection.identity.profileID)
        let page = try coachPage(request, expectedProfileID: expectedSelection.identity.profileID)
        guard page.identity == expectedSelection.identity else { throw CoachQueryError.wrongTimeline }
        try validateOwnership(expectedSelection, profileID: expectedSelection.identity.profileID)
        return page
    }
    func coachTimelineRefresh(ids: Set<UUID>, expectedSelection: DiarySelectionOwnership) throws -> CoachTimelineRefresh {
        try validateOwnership(expectedSelection, profileID: expectedSelection.identity.profileID)
        let result = try pagedConnection(expectedProfileID: expectedSelection.identity.profileID).database.coachTimelineRefresh(
            ids: ids, expectedIdentity: expectedSelection.identity)
        try validateOwnership(expectedSelection, profileID: expectedSelection.identity.profileID)
        return result
    }
    func coachOperationMetadata(turnID: UUID? = nil, expectedSelection: DiarySelectionOwnership) throws -> CoachOperationMetadata? {
        try validateOwnership(expectedSelection, profileID: expectedSelection.identity.profileID)
        let value = try pagedConnection(expectedProfileID: expectedSelection.identity.profileID).database.coachOperationMetadata(
            turnID: turnID, expectedIdentity: expectedSelection.identity)
        try validateOwnership(expectedSelection, profileID: expectedSelection.identity.profileID)
        return value
    }
    func coachLatestExchange(expectedSelection: DiarySelectionOwnership) throws -> CoachExchangeSummary? {
        try validateOwnership(expectedSelection, profileID: expectedSelection.identity.profileID)
        let value = try pagedConnection(expectedProfileID: expectedSelection.identity.profileID).database.coachLatestExchange(expectedIdentity: expectedSelection.identity)
        try validateOwnership(expectedSelection, profileID: expectedSelection.identity.profileID)
        return value
    }
    func coachExchange(turnID: UUID, expectedSelection: DiarySelectionOwnership) throws -> CoachExchangeSummary {
        try validateOwnership(expectedSelection, profileID: expectedSelection.identity.profileID)
        let database = try pagedConnection(expectedProfileID: expectedSelection.identity.profileID).database
        let result = try database.domainRead(expectedProfileID: expectedSelection.identity.profileID) { head in
            guard head.timelineGeneration == expectedSelection.identity.timelineGeneration else { throw CoachQueryError.wrongTimeline }
            return try database.coachExchangeSummary(turnID: turnID, expectedProfileID: expectedSelection.identity.profileID)
        }
        try validateOwnership(expectedSelection, profileID: expectedSelection.identity.profileID)
        return result
    }
    func coachCapturedDayLabels(ids: Set<UUID>, expectedSelection: DiarySelectionOwnership) throws -> [UUID: String] {
        guard ids.count <= CoachPagedHistoryWindow.maximumExchanges else { throw DiaryError.invalidData }
        try validateOwnership(expectedSelection, profileID: expectedSelection.identity.profileID)
        let database = try pagedConnection(expectedProfileID: expectedSelection.identity.profileID).database
        let labels = try database.domainRead(expectedProfileID: expectedSelection.identity.profileID) { head in
            guard head.timelineGeneration == expectedSelection.identity.timelineGeneration else { throw CoachQueryError.wrongTimeline }
            return try Dictionary(uniqueKeysWithValues: ids.map { ($0, try database.trackingDay(id: $0).localDate) })
        }
        try validateOwnership(expectedSelection, profileID: expectedSelection.identity.profileID)
        return labels
    }
    func coachReceiptTargets(exchanges: [CoachExchangeSummary], expectedSelection: DiarySelectionOwnership) throws -> [UUID: CoachReceiptTarget] {
        guard exchanges.count <= CoachPagedHistoryWindow.maximumExchanges else { throw DiaryError.invalidData }
        try validateOwnership(expectedSelection, profileID: expectedSelection.identity.profileID)
        let database = try pagedConnection(expectedProfileID: expectedSelection.identity.profileID).database
        let targets = try database.domainRead(expectedProfileID: expectedSelection.identity.profileID) { head in
            guard head.timelineGeneration == expectedSelection.identity.timelineGeneration else { throw CoachQueryError.wrongTimeline }
            let transaction = DiaryTransaction(database: database, head: head)
            var targets: [UUID: CoachReceiptTarget] = [:]
            for exchange in exchanges {
                for id in Set(exchange.receipts.compactMap(\.mealID) + (exchange.pendingMealID.map { [$0] } ?? [])) where targets[id] == nil {
                    do {
                        let meal = try transaction.mealProjection(id: id)
                        let day = try database.trackingDay(id: meal.dayID)
                        targets[id] = .meal(meal, localDate: day.localDate)
                    } catch DiaryError.notFound { targets[id] = .unavailable }
                }
                for id in Set(exchange.receipts.compactMap(\.workoutID)) where targets[id] == nil {
                    do {
                        let workout = try transaction.workout(id: id)
                        let day = try database.trackingDay(id: workout.dayID)
                        targets[id] = .workout(workout, localDate: day.localDate)
                    } catch DiaryError.notFound { targets[id] = .unavailable }
                }
            }
            return targets
        }
        try validateOwnership(expectedSelection, profileID: expectedSelection.identity.profileID)
        return targets
    }
    func coachDays(before: CoachDayCursor? = nil, expectedSelection: DiarySelectionOwnership, expectedProfileID: UUID) throws -> CoachDayPage {
        try validateOwnership(expectedSelection, profileID: expectedProfileID)
        return try pagedConnection(expectedProfileID: expectedProfileID).database.coachDays(before: before, expectedProfileID: expectedProfileID)
    }
    func coachSegments(displayLocalDate: String, before: CoachDayCursor? = nil, expectedSelection: DiarySelectionOwnership, expectedProfileID: UUID) throws -> CoachDayPage {
        try validateOwnership(expectedSelection, profileID: expectedProfileID)
        return try pagedConnection(expectedProfileID: expectedProfileID).database.coachSegments(displayLocalDate: displayLocalDate, before: before, expectedIdentity: expectedSelection.identity)
    }
    func diaryHistory(before: DiaryHistoryCursor? = nil, limit: Int = 30, recordedOnly: Bool = false, localDate: String? = nil, expectedProfileID: UUID) throws -> DiaryHistoryPage { try pagedConnection(expectedProfileID: expectedProfileID).database.diaryHistory(before: before, limit: limit, recordedOnly: recordedOnly, localDate: localDate, expectedProfileID: expectedProfileID) }
    func nextPendingCoachTurn(includeWaitingForConnection: Bool, expectedProfileID: UUID) throws -> CoachWorkItem? { try pagedConnection(expectedProfileID: expectedProfileID).database.nextPendingCoachTurn(includeWaitingForConnection: includeWaitingForConnection, expectedProfileID: expectedProfileID) }
    func nextUnlinkedPendingSubmission(expectedProfileID: UUID) throws -> PendingSubmissionReference? { try pagedConnection(expectedProfileID: expectedProfileID).database.nextUnlinkedPendingSubmission(expectedProfileID: expectedProfileID) }
    func coachWorkItem(turnID: UUID, expectedProfileID: UUID) throws -> CoachWorkItem { try pagedConnection(expectedProfileID: expectedProfileID).database.coachWorkItem(turnID: turnID, expectedProfileID: expectedProfileID) }
    func nextCoachResult(includeWaitingForConnection: Bool, expectedProfileID: UUID) throws -> CoachTurnResult? { try nextPendingCoachTurn(includeWaitingForConnection: includeWaitingForConnection, expectedProfileID: expectedProfileID).map(CoachTurnResult.init) }
    func nextLegacyCaptureID(expectedProfileID: UUID) throws -> UUID? { try nextUnlinkedPendingSubmission(expectedProfileID: expectedProfileID)?.submissionID }
    func coachResult(turnID: UUID, expectedProfileID: UUID) throws -> CoachTurnResult { CoachTurnResult(try coachWorkItem(turnID: turnID, expectedProfileID: expectedProfileID)) }
    func selectionEpoch(expectedProfileID: UUID) throws -> UInt64 { try selectionOwnership(expectedProfileID: expectedProfileID).selectionEpoch }
    func validateSelection(epoch: UInt64, expectedProfileID: UUID) throws {
        guard epoch == (try selectionEpoch(expectedProfileID: expectedProfileID)) else { throw DiaryError.wrongOwner }
    }
    func coachInferencePhotos(turnID: UUID, expectedProfileID: UUID) throws -> [Data] {
        let work = try coachWorkItem(turnID: turnID, expectedProfileID: expectedProfileID)
        guard work.receipts.isEmpty else { return [] }
        guard work.photos.count <= 30 else { throw CoachError.limitExceeded }
        return try work.photos.map { try photoContent($0, expectedProfileID: expectedProfileID) }
    }
    func capturedMeal(submissionID: UUID, expectedSelection: DiarySelectionOwnership, expectedProfileID: UUID) throws -> MealReadModel? {
        try validateOwnership(expectedSelection, profileID: expectedProfileID)
        let (database, _) = try pagedConnection(expectedProfileID: expectedProfileID)
        return try database.domainRead(expectedProfileID: expectedProfileID) { head in
            let transaction = DiaryTransaction(database: database, head: head)
            return try transaction.submissionParent(id: submissionID).map { try transaction.mealProjection(id: $0) }
        }
    }
    func setCoachTurnState(turnID: UUID, state: CoachTurnState, needsDayChoice: Bool = false, expectedProfileID: UUID) throws {
        _ = try pagedMutation(expectedProfileID) { database, head in
            let text = state == .completed ? try database.coachExchangeSummary(turnID: turnID, expectedProfileID: expectedProfileID).assistantText : nil
            return try database.updateCoachTurn(turnID: turnID, state: state, assistantText: text, needsDayChoice: needsDayChoice, expected: head, maximumBytes: maximumFileBytes)
        }
    }
    func completeCoachTurn(turnID: UUID, assistantText: String, expectedProfileID: UUID) throws {
        _ = try pagedMutation(expectedProfileID) { try $0.updateCoachTurn(turnID: turnID, state: .completed, assistantText: assistantText, needsDayChoice: false, expected: $1, maximumBytes: maximumFileBytes) }
    }
    func coachPreferenceSummary(expectedProfileID: UUID) throws -> String {
        let profile = try diaryHead(expectedProfileID: expectedProfileID).profile
        return "Timezone: \(profile.timeZoneID). Dietary preferences: \(profile.preferences.isEmpty ? "not set" : profile.preferences)."
    }
    func coachWorkoutSummary(id: UUID, expectedProfileID: UUID) throws -> String {
        let workout: WorkoutSession, day: TrackingDay
        do {
            workout = try coachWorkout(id: id, expectedProfileID: expectedProfileID)
            day = try pagedConnection(expectedProfileID: expectedProfileID).database.trackingDay(id: workout.dayID)
        } catch DiaryError.notFound { return "This workout was deleted." }
        var facts = ["\(day.localDate): recorded \(workout.kind.rawValue), \(workout.durationMinutes) minutes; revision \(workout.revision)."]
        for exercise in workout.exercises { facts.append(exercise.name + ": " + exercise.sets.map { "\($0.repetitions) reps" + ($0.loadKg.map { " at \(coachNumber($0)) kg" } ?? " (load unset)") }.joined(separator: ", ")) }
        facts.append("Estimated burn: " + (workout.estimatedBurnKcal.map { "\(coachNumber($0)) kcal (\(workout.burnSource?.rawValue ?? "source unset"))." } ?? "unknown."))
        return facts.joined(separator: "\n")
    }
    func deleteProfile(_ id: UUID) throws {
        do { for url in [legacyFile(id), selectedFile(id)] where FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
        catch { throw DiaryError.persistenceFailed }
        if pagedHead?.profile.id == id { signOut() }
    }
    func snapshotForExport(expectedProfileID: UUID? = nil) async throws -> DiarySnapshot {
        let request = try exportRequest(expectedProfileID: selectedOwner(expectedProfileID))
        let coordinator = DiaryExportCoordinator(store: self)
        let ticket = try await coordinator.makeClone(request)
        do { let result = try await coordinator.completeSnapshot(ticket); try await coordinator.release(ticket); return result }
        catch { try? await coordinator.release(ticket); throw error }
    }
    func exportData(expectedProfileID: UUID? = nil) async throws -> Data {
        let coordinator = DiaryExportCoordinator(store: self)
        let ticket = try await coordinator.makeClone(exportRequest(expectedProfileID: selectedOwner(expectedProfileID)))
        do { let data = try await coordinator.portableData(ticket); try await coordinator.release(ticket); return data }
        catch { try? await coordinator.release(ticket); throw error }
    }
    func exportRequest(expectedProfileID: UUID, backupGeneration: UUID? = nil) throws -> DiaryExportRequest {
        let head = try diaryHead(expectedProfileID: expectedProfileID)
        guard let identity = fileIdentities[expectedProfileID] else { throw DiaryError.persistenceFailed }
        return DiaryExportRequest(operationID: UUID(), profileID: expectedProfileID, head: head, selectionEpoch: profileSelectionEpoch,
            sourceURL: file(expectedProfileID), sourceFileIdentity: identity, backupGeneration: backupGeneration, storageVersion: 1, maximumBytes: maximumFileBytes)
    }
    func restore(_ incoming: DiarySnapshot, expectedProfileID: UUID? = nil) async throws {
        let request = try exportRequest(expectedProfileID: selectedOwner(expectedProfileID))
        let coordinator = DiaryExportCoordinator(store: self), ticket = try await coordinator.makeClone(request)
        do { let prepared = try await coordinator.prepareReplacement(incoming, replacing: ticket); _ = try installReplacement(prepared); try await coordinator.release(ticket) }
        catch { try? await coordinator.release(ticket); throw error }
    }
    private func file(_ id: UUID) -> URL { selectedFile(id).appendingPathComponent("diary.sqlite") }
    private func legacyFile(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    private func selectedFile(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".sqlite") }
    private func exists(_ id: UUID) -> Bool { FileManager.default.fileExists(atPath: selectedFile(id).path) || FileManager.default.fileExists(atPath: legacyFile(id).path) }

    func startDay(at: Date = Date(), expectedSelection: DiarySelectionOwnership, expectedProfileID: UUID) throws -> TrackingDay {
        try validateOwnership(expectedSelection, profileID: expectedProfileID)
        return try startDay(at: at, expectedProfileID: expectedProfileID)
    }
    func confirmPreviousDay(at: Date = Date(), expectedSelection: DiarySelectionOwnership, expectedProfileID: UUID) throws {
        try validateOwnership(expectedSelection, profileID: expectedProfileID)
        try confirmPreviousDay(at: at, expectedProfileID: expectedProfileID)
    }
    func dayAssignment(at: Date = Date(), expectedSelection: DiarySelectionOwnership, expectedProfileID: UUID) throws -> DayAssignment {
        try validateOwnership(expectedSelection, profileID: expectedProfileID)
        return try dayAssignment(at: at, expectedProfileID: expectedProfileID)
    }
    func startDay(at: Date = Date(), expectedProfileID: UUID? = nil) throws -> TrackingDay {
        return try pagedMutation(expectedProfileID) { try $0.startDay(at: at, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func dayAssignment(at: Date = Date(), expectedProfileID: UUID? = nil) throws -> DayAssignment {
        guard let selected = pagedHead else { throw DiaryError.noProfile }
        let head = try diaryHead(expectedProfileID: expectedProfileID ?? selected.profile.id)
        guard let id = head.activeDayID else { return .newDay }
        let day = try pagedConnection(expectedProfileID: head.profile.id).database.trackingDay(id: id)
        let localDate = diaryDateLabel(at, zone: head.profile.timeZoneID)
        if let confirmed = head.previousDayConfirmedAt, at >= confirmed, at.timeIntervalSince(confirmed) < 4 * 3600,
           diaryDateLabel(confirmed, zone: head.profile.timeZoneID) == localDate { return .existing(id) }
        return day.timeZoneID == head.profile.timeZoneID && day.localDate == localDate ? .existing(id) : .ask(id)

    }

    func confirmPreviousDay(at: Date = Date(), expectedProfileID: UUID? = nil) throws {
        return try pagedMutation(expectedProfileID) { try $0.confirmPreviousDay(at: at, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func processPending(expectedProfileID: UUID? = nil) throws {
        guard let selected = pagedHead else { throw DiaryError.noProfile }
        let owner = expectedProfileID ?? selected.profile.id
        while !Task.isCancelled {
            let (database, _) = try pagedConnection(expectedProfileID: owner)
            guard let job = try database.nextPendingMealSubmission(expectedProfileID: owner) else { return }
            try pagedMutation(owner) { try $0.prepareAnalysis(mealID: job.mealID, submissionID: job.submissionID, expected: $1, maximumBytes: maximumFileBytes) }
            let input = try analysisInput(mealID: job.mealID, submissionID: job.submissionID, expectedProfileID: owner)
            do { try applyAnalysis(SampleAnalyzer().analyze(input), expectedProfileID: owner) }
            catch {
                try pagedMutation(owner) { database, head in
                    try database.transaction(expected: head, maximumBytes: maximumFileBytes) { try $0.setSubmissionState(mealID: job.mealID, submissionID: job.submissionID, state: .needsRetry) }
                }
                throw error
            }
        }
        return

    }

    func analysisInput(mealID: UUID, submissionID: UUID, expectedProfileID: UUID? = nil) throws -> AnalysisInput {
        guard let selected = pagedHead else { throw DiaryError.noProfile }
        let owner = expectedProfileID ?? selected.profile.id
        return try pagedConnection(expectedProfileID: owner).database.analysisInput(mealID: mealID, submissionID: submissionID, expectedProfileID: owner)

    }

    func applyAnalysis(_ output: AnalysisOutput, expectedProfileID: UUID? = nil) throws {
        return try pagedMutation(expectedProfileID) { try $0.applyAnalysis(output, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func acceptReview(mealID: UUID, submissionID: UUID, expectedProfileID: UUID? = nil) throws {
        return try pagedMutation(expectedProfileID) { try $0.acceptReview(mealID: mealID, submissionID: submissionID, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func editItem(mealID: UUID, item: FoodItem, reviewSubmissionID: UUID? = nil, expectedRevision: Int? = nil, expectedProfileID: UUID? = nil) throws {
        return try pagedMutation(expectedProfileID) { try $0.editItem(mealID: mealID, item: item, reviewSubmissionID: reviewSubmissionID, expectedRevision: expectedRevision, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func addPhotos(mealID: UUID, photos: [MealPhoto], expectedProfileID: UUID? = nil) throws {
        return try pagedMutation(expectedProfileID) { try $0.addPhotos(mealID: mealID, photos: photos, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func deletePhoto(mealID: UUID, photoID: UUID, expectedProfileID: UUID? = nil) throws {
        return try pagedMutation(expectedProfileID) { try $0.deletePhoto(mealID: mealID, photoID: photoID, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func deleteMeal(_ mealID: UUID, expectedProfileID: UUID? = nil) throws {
        return try pagedMutation(expectedProfileID) { try $0.deleteMeal(mealID, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func moveMeal(_ mealID: UUID, to dayID: UUID, eatenAt: Date? = nil, expectedRevision: Int? = nil, expectedDayID: UUID? = nil, expectedProfileID: UUID? = nil) throws {
        return try pagedMutation(expectedProfileID) { try $0.moveMeal(mealID, to: dayID, eatenAt: eatenAt, expectedRevision: expectedRevision, expectedDayID: expectedDayID, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func setCompleteness(dayID: UUID, _ completeness: DayCompleteness, expectedProfileID: UUID? = nil) throws {
        return try pagedMutation(expectedProfileID) { try $0.setCompleteness(dayID: dayID, completeness, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func recordWeight(value: Double, unit: String = "kg", at: Date = Date(), startNewDay: Bool = true, expectedProfileID: UUID? = nil) throws -> WeightEntry {
        return try pagedMutation(expectedProfileID) { database, head in
        try database.transaction(expected: head, maximumBytes: maximumFileBytes) { transaction in
            let dayID = try startNewDay ? transaction.startDay(at: at).id : transaction.head.activeDayID
            if let dayID {
                let previous = try transaction.weight(on: dayID)
                return try transaction.setWeight(dayID: dayID, value: value, unit: unit, expectedRevision: previous?.revision, measuredAt: at, precision: .exact)
            }
            let weight = WeightEntry(dayID: nil, measuredAt: at, value: value, unit: unit)
            try transaction.saveWeight(weight); return weight
        }
        }
    }

    func setGoals(_ goal: GoalRecord, expectedRevision: Int?, expectedProfileID: UUID) throws -> GoalRecord {
        return try pagedMutation(expectedProfileID) { try $0.setGoals(goal, expectedRevision: expectedRevision, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func updateWeight(id: UUID, value: Double, expectedRevision: Int, expectedProfileID: UUID) throws -> WeightEntry {
        return try pagedMutation(expectedProfileID) { try $0.updateWeight(id: id, value: value, expectedRevision: expectedRevision, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func deleteWeight(id: UUID, expectedRevision: Int, expectedProfileID: UUID) throws {
        return try pagedMutation(expectedProfileID) { try $0.deleteWeight(id: id, expectedRevision: expectedRevision, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func createWorkout(localDate: String, draft: WorkoutDraft, performedAt: Date?, expectedProfileID: UUID) throws -> WorkoutSession {
        return try pagedMutation(expectedProfileID) { database, head in
        try database.transaction(expected: head, maximumBytes: maximumFileBytes) { transaction in
            let day = try transaction.resolveDay(localDate: localDate, timeZoneID: head.profile.timeZoneID, at: diaryDateOnlyInstant(localDate, zone: head.profile.timeZoneID))
            return try transaction.createWorkout(dayID: day.id, draft: draft, performedAt: performedAt)
        }
        }
    }

    func updateWorkout(_ session: WorkoutSession, expectedRevision: Int, expectedProfileID: UUID) throws -> WorkoutSession {
        return try pagedMutation(expectedProfileID) { try $0.updateWorkout(session, expectedRevision: expectedRevision, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func deleteWorkout(id: UUID, expectedRevision: Int, expectedProfileID: UUID) throws {
        return try pagedMutation(expectedProfileID) { try $0.deleteWorkout(id: id, expectedRevision: expectedRevision, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func updateProfile(_ profile: DiaryProfile, expectedProfile: DiaryProfile? = nil, expectedProfileID: UUID? = nil) throws {
        return try pagedMutation(expectedProfileID) { try $0.updateProfile(profile, expectedProfile: expectedProfile, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func preparePendingCoachTurn(turnID: UUID, expectedProfileID: UUID) throws -> CoachTurnResult {
        try pagedMutation(expectedProfileID) { try $0.prepareCoachWork(turnID: turnID, at: currentTime(), expected: $1, maximumBytes: maximumFileBytes) }
        return try coachResult(turnID: turnID, expectedProfileID: expectedProfileID)

    }

    func coachMeals(on date: String, afterMealID: UUID? = nil, expectedProfileID: UUID) throws -> CoachMealCandidatePage {
        return try pagedConnection(expectedProfileID: expectedProfileID).database.coachMeals(on: date, afterMealID: afterMealID, expectedProfileID: expectedProfileID)
    }

    func coachContext(turnID: UUID, expectedProfileID: UUID) throws -> CoachContext {
        return try pagedConnection(expectedProfileID: expectedProfileID).database.coachInferenceContext(turnID: turnID, expectedProfileID: expectedProfileID)
    }

    func applyCoachFood(turnID: UUID, targetLocalDate: String, items: [FoodItem], eatenAt: Date? = nil, reviewFirst: Bool = false, expectedProfileID: UUID) throws -> CoachReceipt {
        return try applyCoachWrites([.food(date: targetLocalDate, items: items, eatenAt: eatenAt, reviewFirst: reviewFirst)], turnID: turnID, epoch: selectionEpoch(expectedProfileID: expectedProfileID), expectedProfileID: expectedProfileID)[0]
    }

    func applyCoachItemCorrection(turnID: UUID, mealID: UUID, item: FoodItem, expectedRevision: Int, expectedProfileID: UUID) throws -> CoachReceipt {
        return try applyCoachWrites([.correction(mealID: mealID, item: item, revision: expectedRevision)], turnID: turnID, epoch: selectionEpoch(expectedProfileID: expectedProfileID), expectedProfileID: expectedProfileID)[0]
    }

    func closeCoachDay(turnID: UUID, localDate: String, completeness: DayCompleteness, expectedProfileID: UUID) throws -> CoachReceipt {
        return try applyCoachWrites([.close(date: localDate, completeness: completeness)], turnID: turnID, epoch: selectionEpoch(expectedProfileID: expectedProfileID), expectedProfileID: expectedProfileID)[0]
    }

    func coachMeal(id: UUID, expectedProfileID: UUID) throws -> CoachContext.Meal {
        return try pagedConnection(expectedProfileID: expectedProfileID).database.coachMealDetail(id: id, expectedProfileID: expectedProfileID)
    }

    func coachGoals(localDate: String, expectedProfileID: UUID) throws -> String {
        let (database, _) = try pagedConnection(expectedProfileID: expectedProfileID)
        return try database.domainRead(expectedProfileID: expectedProfileID) { head in
            let transaction = DiaryTransaction(database: database, head: head)
            struct Goals: Encodable { var exact: GoalRecord?; var effective: GoalRecord?; var diaryRevision: Int }
            return try coachJSON(Goals(exact: transaction.exactGoal(on: localDate), effective: transaction.goal(on: localDate), diaryRevision: head.revision))
        }

    }

    func coachPreferences(expectedProfileID: UUID) throws -> String {
        return try pagedConnection(expectedProfileID: expectedProfileID).database.domainRead(expectedProfileID: expectedProfileID) { head in
            struct Preferences: Encodable { var profile: DiaryProfile; var diaryRevision: Int }
            return try coachJSON(Preferences(profile: head.profile, diaryRevision: head.revision))
        }

    }

    func validateCoachWrites(_ writes: [CoachWrite], turnID: UUID, epoch: UInt64, expectedProfileID: UUID, mode: CoachWriteMode = .uninterrupted) throws {
        try validateSelection(epoch: epoch, expectedProfileID: expectedProfileID)
        try refreshCoachHead(expectedProfileID: expectedProfileID)
        try pagedConnection(expectedProfileID: expectedProfileID).database.validateCoachWrites(writes, turnID: turnID, mode: mode, at: currentTime(), expectedProfileID: expectedProfileID)
        return

    }

    func applyCoachWrites(_ writes: [CoachWrite], turnID: UUID, epoch: UInt64, expectedProfileID: UUID, mode: CoachWriteMode = .uninterrupted) throws -> [CoachReceipt] {
        try validateSelection(epoch: epoch, expectedProfileID: expectedProfileID)
        try refreshCoachHead(expectedProfileID: expectedProfileID)
        return try pagedMutation(expectedProfileID) { try $0.applyCoachWrites(writes, turnID: turnID, mode: mode, at: currentTime(), expected: $1, maximumBytes: maximumFileBytes) }

    }

    func coachCommittedSummary(turnID: UUID, expectedProfileID: UUID) throws -> String {
        return try pagedConnection(expectedProfileID: expectedProfileID).database.coachReceiptSummary(turnID: turnID, expectedProfileID: expectedProfileID)
    }

    func coachGoalSummary(localDate: String, expectedProfileID: UUID) throws -> String {
        struct Goals: Decodable { var effective: GoalRecord? }
        let facts = try JSONDecoder().decode(Goals.self, from: Data(coachGoals(localDate: localDate, expectedProfileID: expectedProfileID).utf8))
        return facts.effective.map(coachGoalDescription) ?? "No goals are set for \(localDate)."

    }

    func coachWorkout(id: UUID, expectedProfileID: UUID) throws -> WorkoutSession {
        let (database, _) = try pagedConnection(expectedProfileID: expectedProfileID)
        return try database.domainRead(expectedProfileID: expectedProfileID) { head in
            let workout = try DiaryTransaction(database: database, head: head).workout(id: id)
            guard try JSONEncoder().encode(workout).count <= 48_000 else { throw CoachError.limitExceeded }; return workout
        }

    }

    func coachProgress(endingOn: String, days: Int, finalizingTurnID: UUID? = nil, expectedProfileID: UUID) throws -> CoachProgress {
        return try pagedConnection(expectedProfileID: expectedProfileID).database.progressRange(endingOn: endingOn, days: days, finalizingTurnID: finalizingTurnID, expectedProfileID: expectedProfileID)
    }

    func coachRecordedSummary(expectedProfileID: UUID) throws -> String {
        let page = try diaryHistory(limit: 14, recordedOnly: true, expectedProfileID: expectedProfileID)
        let facts = page.days.reversed().map { summary in
            "\(summary.day.localDate): " + (summary.totals.kcal.map { "\(Int($0.rounded())) kcal" } ?? "calories incomplete") + "."
        }
        return "No new food was saved in this turn.\n" + (facts.isEmpty ? "There are no recorded food totals yet." : facts.joined(separator: "\n"))

    }

    func chooseCoachDay(turnID: UUID, usePrevious: Bool, at: Date = Date(), expectedProfileID: UUID) throws {
        return try pagedMutation(expectedProfileID) { try $0.chooseCoachDay(turnID: turnID, usePrevious: usePrevious, at: at, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func setWeight(dayLocalDate: String, value: Double, unit: String, measuredAt: Date?, expectedRevision: Int?, expectedProfileID: UUID) throws -> WeightEntry {
        return try pagedMutation(expectedProfileID) { database, head in
        try database.transaction(expected: head, maximumBytes: maximumFileBytes) { transaction in
            let day = try transaction.resolveDay(localDate: dayLocalDate, timeZoneID: head.profile.timeZoneID, at: diaryDateOnlyInstant(dayLocalDate, zone: head.profile.timeZoneID))
            if let measuredAt { guard measuredAt.timeIntervalSince1970.isFinite, diaryDateLabel(measuredAt, zone: day.timeZoneID) == day.localDate else { throw DiaryError.invalidData } }
            return try transaction.setWeight(dayID: day.id, value: value, unit: unit, expectedRevision: expectedRevision, measuredAt: measuredAt ?? diaryDateOnlyInstant(day.localDate, zone: day.timeZoneID), precision: measuredAt == nil ? .dateOnly : .exact)
        }
        }
    }

    func setWeight(dayID: UUID, value: Double, unit: String = "kg", expectedRevision: Int?, expectedProfileID: UUID) throws -> WeightEntry {
        return try pagedMutation(expectedProfileID) { try $0.setWeight(dayID: dayID, value: value, unit: unit, expectedRevision: expectedRevision, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func createWorkout(dayID: UUID, draft: WorkoutDraft, expectedProfileID: UUID) throws -> WorkoutSession {
        return try pagedMutation(expectedProfileID) { try $0.createWorkout(dayID: dayID, draft: draft, expected: $1, maximumBytes: maximumFileBytes) }
    }

    func captureProjection(text: String, photos: [MealPhoto], reviewFirst: Bool, dayID: UUID, at: Date = Date(), dateOnly: Bool = false, submissionID: UUID = UUID(), forCoach: Bool = false,
                           expectedSelection: DiarySelectionOwnership, expectedProfileID: UUID) throws -> MealReadModel {
        try validateOwnership(expectedSelection, profileID: expectedProfileID)
        return try pagedMutation(expectedProfileID) { database, head in
            try database.captureProjection(text: text, photos: photos, reviewFirst: reviewFirst, dayID: dayID, at: at, dateOnly: dateOnly, submissionID: submissionID, forCoach: forCoach, expected: head, maximumBytes: maximumFileBytes)
        }
    }
    func correctMealProjection(mealID: UUID, text: String, photos: [MealPhoto] = [], reviewFirst: Bool = false, submissionID: UUID = UUID(), forCoach: Bool = false,
                               expectedSelection: DiarySelectionOwnership, expectedProfileID: UUID) throws -> MealReadModel {
        try validateOwnership(expectedSelection, profileID: expectedProfileID)
        return try pagedMutation(expectedProfileID) { database, head in
            try database.correctMealProjection(mealID: mealID, text: text, photos: photos, reviewFirst: reviewFirst, submissionID: submissionID, forCoach: forCoach, at: currentTime(), expected: head, maximumBytes: maximumFileBytes)
        }
    }

    func finishCoachTurn(turnID: UUID, assistantText: String, epoch: UInt64, expectedProfileID: UUID) throws {
        try validateSelection(epoch: epoch, expectedProfileID: expectedProfileID)
        try completeCoachTurn(turnID: turnID, assistantText: assistantText, expectedProfileID: expectedProfileID)
    }

    func failCoachTurn(turnID: UUID, state: CoachTurnState, needsDayChoice: Bool = false, epoch: UInt64, expectedProfileID: UUID) throws {
        try validateSelection(epoch: epoch, expectedProfileID: expectedProfileID)
        try setCoachTurnState(turnID: turnID, state: state, needsDayChoice: needsDayChoice, expectedProfileID: expectedProfileID)
    }

    private func coachGoalDescription(_ goal: GoalRecord) -> String {
        var parts = ["Effective \(goal.effectiveLocalDate)."]
        for (name, value, unit) in [("Calories", goal.targets.kcal, "kcal"), ("Carbs", goal.targets.carbs, "g"), ("Protein", goal.targets.protein, "g"), ("Fat", goal.targets.fat, "g"), ("Goal weight", goal.goalWeightKg, "kg")] {
            parts.append("\(name): \(value.map { coachNumber($0) + " " + unit } ?? "not set").")
        }
        parts.append("Workout energy adjustment \(goal.exerciseCreditEnabled ? "enabled" : "disabled"); estimated burn remains separate.")
        return parts.joined(separator: " ")
    }

    private func coachNumber(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US")))
    }

    func coachProgressSummary(endingOn: String, days: Int, finalizingTurnID: UUID? = nil, expectedProfileID: UUID) throws -> String {
        let report = try coachProgress(endingOn: endingOn, days: days, finalizingTurnID: finalizingTurnID, expectedProfileID: expectedProfileID)
        var facts = ["\(report.startLocalDate) through \(report.endLocalDate)."]
        let daily = report.daily
        facts.append("Recorded food: " + (daily.foodTotals?.kcal.map { "\(coachNumber($0)) kcal." } ?? "calories unknown."))
        facts.append("Remaining from recorded food: " + (daily.remainingFromRecorded.kcal.map { "\(coachNumber($0)) kcal." } ?? "unknown (target or intake missing)."))
        if let goal = daily.goal {
            facts.append("Configured target: " + (goal.targets.kcal.map { "\(coachNumber($0)) kcal." } ?? "calories unset."))
        }
        for (name, field) in [("carbs", \NutritionValues.carbs), ("protein", \NutritionValues.protein), ("fat", \NutritionValues.fat)] {
            facts.append("Remaining \(name) from recorded food: " + (daily.remainingFromRecorded[keyPath: field].map { "\(coachNumber($0)) g." } ?? "unknown."))
        }
        facts.append("Recorded workouts: \(daily.workoutCount).")
        facts.append("Estimated exercise burn: " + (daily.estimatedBurnKcal.map { "\(coachNumber($0)) kcal." } ?? "unknown."))
        if let adjusted = daily.exerciseAdjustedKcalRemaining { facts.append("Explicit exercise-adjusted remaining: \(coachNumber(adjusted)) kcal.") }
        if let period = report.period {
            facts.append("Coverage: \(period.completeDayCount) complete, \(period.partialDayCount) partial, \(period.untrackedDayCount) untracked, \(period.unknownDayCount) unknown, \(period.missingDayCount) missing, \(period.pendingDayCount) pending days.")
            facts.append("Average recorded intake: " + (period.averageIntake.kcal.map { "\(coachNumber($0)) kcal from \(period.knownIntakeSamples.kcal) complete known days." } ?? "unknown."))
            for (name, field, count) in [("carbs", \NutritionValues.carbs, period.knownIntakeSamples.carbs), ("protein", \NutritionValues.protein, period.knownIntakeSamples.protein), ("fat", \NutritionValues.fat, period.knownIntakeSamples.fat)] {
                facts.append("Average \(name): " + (period.averageIntake[keyPath: field].map { "\(coachNumber($0)) g from \(count) complete known days." } ?? "unknown."))
            }
            facts.append("Period recorded workouts: \(period.workoutCount).")
            facts.append("Within 10% of target: \(period.adherenceNumerator)/\(period.adherenceDenominator) eligible days.")
        } else { facts.append("Day coverage: \(daily.completeness?.rawValue ?? "missing"); pending: \(daily.hasPending).") }
        facts.append("Weight average: " + (report.weight.currentSevenDayAverageKg.map { "\(coachNumber($0)) kg" } ?? "unknown") + " from \(report.weight.currentSevenDayObservedCount) measured dates.")
        facts.append("Weight change versus prior 7-day window: " + (report.weight.changeFromSevenDaysAgoKg.map { "\(coachNumber($0)) kg." } ?? "insufficient data."))
        facts.append("Weight change versus 30 days ago: " + (report.weight.changeFromThirtyDaysAgoKg.map { "\(coachNumber($0)) kg." } ?? "insufficient data."))
        facts.append("Observed plateau readiness: \(report.weight.plateau.rawValue).")
        facts.append("Record references omitted: \(report.omittedWeightCount) weights, \(report.omittedWorkoutCount) workouts.")
        return facts.joined(separator: "\n")
    }
    func validateExportRequest(_ request: DiaryExportRequest, cloneHead: DiaryHead? = nil) throws {
        guard request.selectionEpoch == profileSelectionEpoch else { throw DiaryError.wrongOwner }
        let current = try exportRequest(expectedProfileID: request.profileID)
        guard current.sourceFileIdentity == request.sourceFileIdentity,
              current.storageVersion == request.storageVersion,
              current.head.timelineGeneration == request.head.timelineGeneration else { throw DiaryError.wrongOwner }
        func succeeds(_ newer: DiaryHead, _ older: DiaryHead) -> Bool {
            guard newer.profile.id == older.profile.id, newer.revision >= older.revision else { return false }
            if newer.revision == older.revision { return newer.lineage == older.lineage }
            guard let token = older.lineage?.last else { return false }
            return newer.lineage?.dropLast().contains(token) == true
        }
        guard succeeds(current.head, request.head) else { throw DiaryError.staleRevision }
        if let cloneHead {
            guard cloneHead.timelineGeneration == request.head.timelineGeneration,
                  succeeds(cloneHead, request.head), succeeds(current.head, cloneHead) else { throw DiaryError.staleRevision }
        }
    }

    func acknowledgeExport(_ request: DiaryExportRequest, cloneHead: DiaryHead,
                           acknowledgement: FolderBackupAcknowledgement) throws {
        try Task.checkCancellation()
        try validateExportRequest(request, cloneHead: cloneHead)
        try acknowledgement.commit()
    }

    func installReplacement(_ replacement: DiaryPreparedReplacement,
                            beforeSwitch: @Sendable () throws -> Void = {}) throws -> DiaryHead {
        try Task.checkCancellation()
        try validateExportRequest(replacement.request, cloneHead: replacement.originalHead)
        let selected = try exportRequest(expectedProfileID: replacement.request.profileID)
        guard selected.head == replacement.originalHead else { throw DiaryError.staleRevision }
        let root = replacement.protectedDatabaseURL.deletingLastPathComponent()
        guard root.lastPathComponent.hasPrefix("diary-replacement-"),
              root.deletingLastPathComponent() == replacement.request.sourceURL.deletingLastPathComponent().deletingLastPathComponent(),
              replacement.protectedDatabaseURL.lastPathComponent == "diary.sqlite" else { throw DiaryError.wrongOwner }
        let identity = try fileIdentity(replacement.protectedDatabaseURL)
        try beforeSwitch()
        guard rename(replacement.protectedDatabaseURL.path, replacement.request.sourceURL.path) == 0 else { throw DiaryError.persistenceFailed }
        fileIdentities[replacement.request.profileID] = identity
        profileSelectionEpoch &+= 1
        finishSubscribers()
        pagedHead = replacement.head
        try? FileManager.default.removeItem(at: root)
        return replacement.head
    }

    private func fileIdentity(_ url: URL) throws -> UInt64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let inode = attributes[.systemFileNumber] as? NSNumber else { throw DiaryError.persistenceFailed }
            return inode.uint64Value
        } catch { throw DiaryError.persistenceFailed }
    }

    private func ensureDatabase(for id: UUID) throws {
        // A selected directory is authoritative even if damaged; never resurrect its old JSON source.
        if FileManager.default.fileExists(atPath: selectedFile(id).path) {
            _ = try fileIdentity(file(id)); return
        }
        let source = legacyFile(id), identity = try fileIdentity(source)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= maximumFileBytes else { throw DiaryError.invalidData }
            let data = try Data(contentsOf: source)
            guard data.count <= maximumFileBytes else { throw DiaryError.invalidData }
            let snapshot = try JSONDecoder().decode(DiarySnapshot.self, from: data)
            guard snapshot.profile.id == id else { throw DiaryError.wrongOwner }
            try snapshot.validate()
            guard try fileIdentity(source) == identity else { throw DiaryError.persistenceFailed }
            try createDatabase(snapshot, beforeInstall: {
                try self.migrationCheckpoint(.beforeInstall, source)
                guard try self.fileIdentity(source) == identity else { throw DiaryError.persistenceFailed }
            })
        } catch let error as DiaryError { throw error }
        catch { throw DiaryError.invalidData }
    }

    private func createDatabase(_ snapshot: DiarySnapshot, beforeInstall: () throws -> Void = {}) throws {
        let temporary = directory.appendingPathComponent("migration-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            #if os(iOS)
            for url in [directory, temporary] {
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
            }
            #endif
            do {
                let database = try DiaryDatabase(url: temporary.appendingPathComponent("diary.sqlite"), create: true)
                try database.write(snapshot, expected: nil, maximumBytes: maximumFileBytes)
                try database.migrateForPagedStorage(maximumBytes: maximumFileBytes)
            }
            // The atomic directory switch is also the durable selection fence if its database is removed.
            try beforeInstall()
            try FileManager.default.moveItem(at: temporary, to: selectedFile(snapshot.profile.id))
            fileIdentities[snapshot.profile.id] = try fileIdentity(file(snapshot.profile.id))
        } catch let error as DiaryError { throw error }
        catch { throw DiaryError.persistenceFailed }
    }
    func trackingDay(id: UUID, expectedProfileID: UUID) throws -> TrackingDay {
        let (database, _) = try pagedConnection(expectedProfileID: expectedProfileID)
        return try database.domainRead(expectedProfileID: expectedProfileID) { _ in try database.trackingDay(id: id) }
    }
    func goal(on date: String, exact: Bool = false, expectedProfileID: UUID) throws -> GoalRecord? {
        let (database, _) = try pagedConnection(expectedProfileID: expectedProfileID)
        return try database.domainRead(expectedProfileID: expectedProfileID) { head in
            let transaction = DiaryTransaction(database: database, head: head)
            return try exact ? transaction.exactGoal(on: date) : transaction.goal(on: date)
        }
    }
    func weightHistory(before: Int? = nil, expectedProfileID: UUID) throws -> DiaryRecordPage<WeightEntry> { try pagedConnection(expectedProfileID: expectedProfileID).database.screenRecords(WeightEntry.self, table: "weight", before: before, expectedProfileID: expectedProfileID) }
    func workoutHistory(before: Int? = nil, expectedProfileID: UUID) throws -> DiaryRecordPage<WorkoutSession> { try pagedConnection(expectedProfileID: expectedProfileID).database.screenRecords(WorkoutSession.self, table: "workout", before: before, expectedProfileID: expectedProfileID) }
    func goalHistory(before: Int? = nil, expectedProfileID: UUID) throws -> DiaryRecordPage<GoalRecord> { try pagedConnection(expectedProfileID: expectedProfileID).database.screenRecords(GoalRecord.self, table: "goal", before: before, expectedProfileID: expectedProfileID) }
    func coachWorkStatus(expectedProfileID: UUID) throws -> CoachWorkStatus { try pagedConnection(expectedProfileID: expectedProfileID).database.coachWorkStatus(expectedProfileID: expectedProfileID) }
    func coachTurnForMeal(_ id: UUID, expectedProfileID: UUID) throws -> UUID? { try pagedConnection(expectedProfileID: expectedProfileID).database.coachTurnForMeal(id, expectedProfileID: expectedProfileID) }
    func historyCoverage(expectedProfileID: UUID) throws -> [DayCompleteness: Int] { try pagedConnection(expectedProfileID: expectedProfileID).database.historyCoverage(expectedProfileID: expectedProfileID) }
    func progressForDisplay(endingOn: String, days: Int, expectedProfileID: UUID) throws -> CoachProgress { try pagedConnection(expectedProfileID: expectedProfileID).database.progressRange(endingOn: endingOn, days: days, includeDailyReports: true, expectedProfileID: expectedProfileID) }
    func weight(id: UUID, expectedProfileID: UUID) throws -> WeightEntry {
        let (database, _) = try pagedConnection(expectedProfileID: expectedProfileID)
        return try database.domainRead(expectedProfileID: expectedProfileID) { head in try DiaryTransaction(database: database, head: head).weight(id: id) }
    }

}
