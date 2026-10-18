import Foundation
import Observation
import Network

@MainActor @Observable final class CoachViewModel {
    typealias Inference = @Sendable ([CoachInferenceInput], Data) async throws -> CoachInferenceResult
    let diary: DiaryViewModel
    let connection: ChatGPTConnection
    var draft = MealDraft()
    var exchanges: [CoachExchangeSummary] { diary.latestCoachPage?.exchanges ?? [] }
    private(set) var captureReceipt: UUID?
    private(set) var companionCaptureEvent: CompanionEvent?
    private(set) var companionSubmission: CompanionSubmission?
    private(set) var isSending = false
    private(set) var isWorking = false
    private(set) var activity: CoachActivity?
    private(set) var activityTurnID: UUID?
    var errorMessage: String? {
        didSet { if errorMessage != nil { errorRevision += 1 } }
    }
    private var errorRevision = 0
    private var sendingErrorRevision = 0
    @ObservationIgnored private let inference: () throws -> Inference
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let lookup: @Sendable (String) async throws -> [FoodEvidenceRecord]
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var workerID: UUID?
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var monitoring = false
    @ObservationIgnored private var active = true
    @ObservationIgnored private var presentationActive = true

    init(diary: DiaryViewModel, connection: ChatGPTConnection, inference: (() throws -> Inference)? = nil,
         lookup: @escaping @Sendable (String) async throws -> [FoodEvidenceRecord] = { _ in throw FoodEvidenceClient.Failure.notConfigured },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.diary = diary; self.connection = connection
        self.inference = inference ?? { try connection.coachInference() }
        self.lookup = lookup; self.sleep = sleep
    }

    var turns: [CoachExchangeSummary] { exchanges }
    var canSend: Bool { draft.isValid && !isSending && !diary.isSaving && !diary.isChangingProfile && diary.readModel != nil }
    var hasPendingWork: Bool { diary.workStatus.pendingTurnID != nil }
    private var companionTurn: CoachExchangeSummary? {
        if let latest = turns.last, latest.id == companionSubmission?.operationID { return latest }
        return turns.first { $0.id == activityTurnID } ?? turns.last
    }
    var companionNeedsRecovery: Bool {
        if isSending { return errorMessage != nil && errorRevision != sendingErrorRevision }
        return errorMessage != nil || companionTurn.map {
            [.waitingForConnection, .waitingForNetwork, .needsRetry, .needsClarification].contains($0.state)
        } == true
    }
    var companionIsProcessing: Bool {
        !companionNeedsRecovery && (isSending || (isWorking &&
            (activity != nil || companionTurn?.state == .analyzing || companionTurn?.state == .captured)))
    }

    private var attemptedCapture: (draft: MealDraft, preparation: CoachCapturePreparation, payload: CoachSubmissionPayload)?
    @discardableResult func send() async -> Bool {
        guard canSend, let token = diary.selection else { return false }
        let owner = token.identity.profileID
        sendingErrorRevision = errorRevision; isSending = true; diary.isSaving = true
        defer { isSending = false; diary.isSaving = false }
        let captured = draft
        companionSubmission = CompanionSubmission(profileID: owner, operationID: captured.submissionID, acceptedAt: Date())
        do {
            let attempt: (draft: MealDraft, preparation: CoachCapturePreparation, payload: CoachSubmissionPayload)
            if let previous = attemptedCapture, previous.draft.submissionID == captured.submissionID {
                guard previous.draft == captured else {
                    let prior = try await diary.store.reconcileCoachCapture(submissionID: previous.payload.submissionID,
                        expectedManifest: previous.payload.manifest, expectedSelection: previous.preparation.ownership, expectedProfileID: owner)
                    if case .accepted = prior { draft.submissionID = UUID() }
                    attemptedCapture = nil
                    return false
                }
                attempt = previous
            } else {
                let prepared = try await diary.store.coachCapturePreparation(at: Date(), expectedProfileID: owner)
                guard diary.selection == token, prepared.ownership == token else { return false }
                let payload = try CoachSubmissionPayload(submissionID: captured.submissionID, text: captured.text,
                    attachments: captured.photos.map { MealPhoto(data: $0) }, context: prepared.context)
                attempt = (captured, prepared, payload); attemptedCapture = attempt
            }
            let result = try await diary.store.captureCoachSubmission(attempt.payload, expectedSelection: attempt.preparation.ownership, expectedProfileID: owner)
            try await diary.refresh(profileID: owner)
            guard !Task.isCancelled, diary.selection == token, !diary.isChangingProfile, draft == captured else { return false }
            captureReceipt = result.id
            if companionCaptureEvent?.profileID != owner || companionCaptureEvent?.operationID != result.id {
                companionCaptureEvent = CompanionEvent(profileID: owner, operationID: result.id, kind: .saved, committedAt: Date())
            }
            draft = MealDraft()
            if errorRevision == sendingErrorRevision { errorMessage = nil }
            resume(); return true
        } catch {
            if diary.selection == token, !diary.isChangingProfile { errorMessage = "Could not save on this iPhone. Your input is still here." }
            return false
        }
    }

    func resume() {
        guard active, worker == nil, !diary.isChangingProfile, let selected = diary.selection else { return }
        let owner = selected.identity.profileID
        let id = UUID(); workerID = id; isWorking = true
        worker = Task {
            defer { if workerID == id { worker = nil; workerID = nil; isWorking = false; activity = nil; activityTurnID = nil } }
            do {
                try await recoverLegacyCaptures(owner: owner)
                while !Task.isCancelled {
                    guard let turn = try await diary.store.nextCoachResult(includeWaitingForConnection: connection.planAuthorized, expectedProfileID: owner) else { break }
                    activity = nil; activityTurnID = nil
                    if turn.state == .analyzing {
                        try await diary.store.setCoachTurnState(turnID: turn.id, state: .captured, expectedProfileID: owner)
                    }
                    if turn.pendingMealID != nil, turn.receipts.isEmpty {
                        _ = try await diary.store.preparePendingCoachTurn(turnID: turn.id, expectedProfileID: owner)
                    }
                    let bound: Inference
                    do { bound = try inference() }
                    catch {
                        try await diary.store.setCoachTurnState(turnID: turn.id, state: .waitingForConnection, expectedProfileID: owner)
                        try await diary.refresh(profileID: owner)
                        break
                    }
                    let sleep = sleep
                    let store = diary.store
                    let epoch = try await store.selectionEpoch(expectedProfileID: owner)
                    let resilient: Inference = { input, tools in
                        func validate() async throws {
                            try Task.checkCancellation()
                            try await store.validateSelection(epoch: epoch, expectedProfileID: owner)
                        }
                        let delays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]
                        var attempt = 0
                        while true {
                            try await validate()
                            do {
                                let result = try await bound(input, tools)
                                try await validate()
                                return result
                            }
                            catch {
                                try await validate()
                                guard attempt < delays.count, ProbeRunner.isTransient(error) else { throw error }
                                try await sleep(delays[attempt])
                                try await validate()
                                attempt += 1
                            }
                        }
                    }
                    let photoLimiter = diary.photoWorkLimiter
                    do {
                        _ = try await CoachEngine(store: diary.store, infer: resilient, lookup: lookup, prepareImages: { originals in
                            try await photoLimiter.withPermit { try PhotoImport.visionCopies(originals) }
                        }, onActivity: { phase in
                            await self.reportActivity(phase, workerID: id, owner: owner, turnID: turn.id)
                        }).run(turnID: turn.id, expectedProfileID: owner)
                    } catch {
                        guard !Task.isCancelled, diary.selection == selected else { break }
                        errorMessage = message(for: error)
                        break
                    }
                    guard !Task.isCancelled, diary.selection == selected else { break }
                    try await diary.refresh(profileID: owner)
                }
            } catch { if !Task.isCancelled, diary.selection == selected { errorMessage = message(for: error) } }
            if diary.selection == selected, !diary.isChangingProfile { try? await diary.refresh(profileID: owner) }
        }
    }

    func chooseDay(_ turnID: UUID, usePrevious: Bool) async {
        guard !diary.isChangingProfile, let selected = diary.selection else { return }
        let owner = selected.identity.profileID
        do {
            try await diary.store.chooseCoachDay(turnID: turnID, usePrevious: usePrevious, expectedProfileID: owner)
            await retry(turnID)
        } catch { errorMessage = message(for: error) }
    }
    func captureDate(_ turn: CoachExchangeSummary) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: turn.captureTimeZoneID); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: turn.capturedAt)
    }
    func previousDayDate(_ turn: CoachExchangeSummary) -> String? { turn.trackingDayID.flatMap { diary.day($0)?.localDate } }
    func retry(_ turnID: UUID) async {
        guard !diary.isChangingProfile, let selected = diary.selection else { return }
        let owner = selected.identity.profileID
        cancel(); await waitForWorker()
        guard !diary.isChangingProfile, diary.selection == selected else { return }
        do {
            try await diary.store.setCoachTurnState(turnID: turnID, state: .captured, expectedProfileID: owner)
            try await diary.refresh(profileID: owner)
            errorMessage = nil; resume()
        } catch { errorMessage = message(for: error) }
    }
    private func recoverLegacyCaptures(owner: UUID) async throws {
        guard !diary.isSaving, !diary.isChangingProfile else { return }
        diary.isSaving = true
        defer { diary.isSaving = false }
        while let submissionID = try await diary.store.nextLegacyCaptureID(expectedProfileID: owner) {
            try Task.checkCancellation()
            _ = try await diary.store.preparePendingCoachTurn(turnID: submissionID, expectedProfileID: owner)
        }
        try await diary.refresh(profileID: owner)
    }
    func retryMeal(_ mealID: UUID) async {
        guard !diary.isChangingProfile, let selected = diary.selection else { return }
        let owner = selected.identity.profileID
        cancel(); await waitForWorker()
        guard !diary.isChangingProfile, diary.selection == selected else { return }
        do {
            try await recoverLegacyCaptures(owner: owner)
            guard let turnID = try await diary.store.coachTurnForMeal(mealID, expectedProfileID: owner) else {
                errorMessage = "This meal changed. Review it before retrying its earlier input."; return
            }
            await retry(turnID)
        } catch { errorMessage = message(for: error) }
    }
    func startMonitoring() {
        guard !monitoring else { return }
        monitoring = true
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor in self?.resume() } }
        }
        monitor.start(queue: DispatchQueue(label: "Mivu.CoachConnectivity"))
    }
    func pauseActivity() { presentationActive = false; activity = nil; activityTurnID = nil }
    func enterBackground() { active = false; pauseActivity(); cancel() }
    func enterForeground() { active = true; presentationActive = true; resume() }
    func cancel() { activity = nil; activityTurnID = nil; worker?.cancel() }
    deinit { monitor.cancel() }
    func waitForWorker() async { await worker?.value }
    private func reportActivity(_ phase: CoachActivity, workerID id: UUID, owner: UUID, turnID: UUID) async {
        guard active, presentationActive, !Task.isCancelled, workerID == id, diary.readModel?.head.profile.id == owner, !diary.isChangingProfile else { return }
        activity = phase; activityTurnID = turnID
        try? await diary.refresh(profileID: owner)
    }
    private var linksSelection: DiarySelectionOwnership?
    private var linksGeneration: UInt64 = 0
    private var linksRequest = UUID()
    private var mealsByTurn: [UUID: [MealReadModel]] = [:]
    private var workoutsByTurn: [UUID: [WorkoutSession]] = [:]
    func refreshLinks() async {
        guard let token = diary.selection else { mealsByTurn = [:]; workoutsByTurn = [:]; linksSelection = nil; return }
        let generation = diary.changeGeneration, request = UUID(); linksRequest = request
        var meals: [UUID: [MealReadModel]] = [:], workouts: [UUID: [WorkoutSession]] = [:]
        for turn in turns {
            let ids = Set(turn.receipts.compactMap(\.mealID) + (turn.pendingMealID.map { [$0] } ?? []))
            for id in ids { do { meals[turn.id, default: []].append(try await diary.store.meal(id: id, expectedProfileID: token.identity.profileID)) } catch DiaryError.notFound {} catch { return } }
            for id in Set(turn.receipts.compactMap(\.workoutID)) { do { workouts[turn.id, default: []].append(try await diary.store.coachWorkout(id: id, expectedProfileID: token.identity.profileID)) } catch DiaryError.notFound {} catch { return } }
            if let dayID = turn.trackingDayID { await diary.loadDay(dayID) }
        }
        guard diary.selection == token, diary.changeGeneration == generation, linksRequest == request else { return }
        linksSelection = token; linksGeneration = generation; mealsByTurn = meals; workoutsByTurn = workouts
    }
    func linkedMeals(_ turn: CoachExchangeSummary) -> [MealReadModel] {
        guard linksSelection == diary.selection, linksGeneration == diary.changeGeneration else { return [] }
        return mealsByTurn[turn.id] ?? []
    }
    func linkedWorkouts(_ turn: CoachExchangeSummary) -> [WorkoutSession] {
        guard linksSelection == diary.selection, linksGeneration == diary.changeGeneration else { return [] }
        return workoutsByTurn[turn.id] ?? []
    }
    private func message(for error: Error) -> String {
        if error as? ResponsesClient.Failure == .usageUnavailable { return "ChatGPT is temporarily unavailable. Your input is saved. Retry when usage is available." }
        if ProbeRunner.isTransient(error) { return "The network is unavailable. Your input is saved and analysis will resume when the connection returns." }
        if error is CancellationError || error as? SessionError == .sessionChanged { return "Analysis paused after the connection changed. Your input is saved. Retry when ready." }
        if error as? ResponsesClient.Failure == .quotaReached { return "Your ChatGPT usage limit was reached. Your input is saved. Check ChatGPT usage settings in Settings and retry when usage is available." }
        if error as? DiaryError == .staleRevision { return "A meal, weigh-in or workout changed while analysis was running. Review the latest record before retrying." }
        if error as? DiaryError == .ambiguousDay { return "Choose which waking day this capture belongs to. Your input is saved." }
        if error as? CoachError == .ungroundedConfirmation { return "More details are needed before a meal, weigh-in or workout can be logged. Your input is saved." }
        if error as? DiaryError == .persistenceFailed { return "Could not update the diary on this iPhone. Your captured input is saved; retry when ready." }
        return "Analysis could not finish. Your input is saved. Check your connection or retry when ready." }
}
