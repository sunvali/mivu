import Foundation
import Observation
import Network

@MainActor @Observable final class CoachViewModel {
    typealias Inference = @Sendable ([CoachInferenceInput], Data) async throws -> CoachInferenceResult
    let diary: DiaryViewModel
    let connection: ChatGPTConnection
    var draft = MealDraft()
    private(set) var captureReceipt: UUID?
    private(set) var isSending = false
    private(set) var isWorking = false
    var errorMessage: String?
    @ObservationIgnored private let inference: () throws -> Inference
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let lookup: @Sendable (String) async throws -> [FoodEvidenceRecord]
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var workerID: UUID?
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var monitoring = false
    @ObservationIgnored private var active = true

    init(diary: DiaryViewModel, connection: ChatGPTConnection, inference: (() throws -> Inference)? = nil,
         lookup: @escaping @Sendable (String) async throws -> [FoodEvidenceRecord] = { _ in throw FoodEvidenceClient.Failure.notConfigured },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.diary = diary; self.connection = connection
        self.inference = inference ?? { try connection.coachInference() }
        self.lookup = lookup; self.sleep = sleep
    }

    var turns: [CoachTurn] { diary.snapshot?.coachTurns ?? [] }
    var canSend: Bool { draft.isValid && !isSending && !diary.isSaving && !diary.isChangingProfile && diary.snapshot != nil }
    var hasPendingWork: Bool { turns.contains { [.captured, .analyzing, .waitingForNetwork].contains($0.state) } }

    @discardableResult func send() async -> Bool {
        guard canSend, let owner = diary.snapshot?.profile.id else { return false }
        isSending = true; diary.isSaving = true
        defer { isSending = false; diary.isSaving = false }
        let captured = draft
        do {
            _ = try await diary.store.captureCoachTurn(text: captured.text, photos: captured.photos.map { MealPhoto(data: $0) }, turnID: captured.submissionID, expectedProfileID: owner)
            try await diary.refresh(profileID: owner)
            guard diary.snapshot?.profile.id == owner else { return false }
            captureReceipt = captured.submissionID
            draft = MealDraft(); errorMessage = nil
            resume()
            return true
        } catch { errorMessage = "Could not save on this iPhone. Your input is still here."; return false }
    }

    func resume() {
        guard active, worker == nil, !diary.isChangingProfile, let owner = diary.snapshot?.profile.id else { return }
        let id = UUID(); workerID = id; isWorking = true
        worker = Task {
            defer { if workerID == id { worker = nil; workerID = nil; isWorking = false } }
            do {
                try await recoverLegacyCaptures(owner: owner)
                while !Task.isCancelled {
                    let snapshot = try await diary.store.snapshot(expectedProfileID: owner)
                    guard let turn = snapshot.coachTurns.first(where: {
                        [.captured, .analyzing, .waitingForNetwork].contains($0.state) || (connection.planAuthorized && $0.state == .waitingForConnection)
                    }) else { break }
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
                    do {
                        _ = try await CoachEngine(store: diary.store, infer: resilient, lookup: lookup, prepareImages: { originals in
                            try PhotoImport.visionCopies(originals)
                        }).run(turnID: turn.id, expectedProfileID: owner)
                    } catch {
                        guard !Task.isCancelled, diary.snapshot?.profile.id == owner else { break }
                        errorMessage = message(for: error)
                        break
                    }
                    guard !Task.isCancelled, diary.snapshot?.profile.id == owner else { break }
                    try await diary.refresh(profileID: owner)
                }
            } catch { if !Task.isCancelled, diary.snapshot?.profile.id == owner { errorMessage = message(for: error) } }
            if diary.snapshot?.profile.id == owner, !diary.isChangingProfile { try? await diary.refresh(profileID: owner) }
        }
    }

    func chooseDay(_ turnID: UUID, usePrevious: Bool) async {
        guard !diary.isChangingProfile, let owner = diary.snapshot?.profile.id else { return }
        do {
            try await diary.store.chooseCoachDay(turnID: turnID, usePrevious: usePrevious, expectedProfileID: owner)
            await retry(turnID)
        } catch { errorMessage = message(for: error) }
    }
    func captureDate(_ turn: CoachTurn) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: turn.captureTimeZoneID); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: turn.capturedAt)
    }
    func previousDayDate(_ turn: CoachTurn) -> String? {
        diary.snapshot?.days.first(where: { $0.id == turn.activeDayID })?.localDate
    }
    func retry(_ turnID: UUID) async {
        guard !diary.isChangingProfile, let owner = diary.snapshot?.profile.id else { return }
        cancel(); await waitForWorker()
        guard !diary.isChangingProfile, diary.snapshot?.profile.id == owner else { return }
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
        let snapshot = try await diary.store.snapshot(expectedProfileID: owner)
        let associated = Set(snapshot.coachTurns.map(\.id))
        for meal in snapshot.meals {
            for submission in meal.submissions where !associated.contains(submission.id) && [.captured, .waitingForConnection, .analyzing, .needsRetry].contains(submission.state) {
                try Task.checkCancellation()
                _ = try await diary.store.preparePendingCoachTurn(turnID: submission.id, expectedProfileID: owner)
            }
        }
        try await diary.refresh(profileID: owner)
    }
    func retryMeal(_ mealID: UUID) async {
        guard !diary.isChangingProfile, let owner = diary.snapshot?.profile.id else { return }
        cancel(); await waitForWorker()
        guard !diary.isChangingProfile, diary.snapshot?.profile.id == owner else { return }
        do {
            try await recoverLegacyCaptures(owner: owner)
            guard let turn = turns.last(where: { $0.pendingMealID == mealID }) else {
                errorMessage = "This meal changed. Review it before retrying its earlier input."; return
            }
            await retry(turn.id)
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
    func enterBackground() { active = false; cancel() }
    func enterForeground() { active = true; resume() }
    func cancel() { worker?.cancel() }
    deinit { monitor.cancel() }
    func waitForWorker() async { await worker?.value }
    func linkedMeals(_ turn: CoachTurn) -> [DiaryMeal] {
        let ids = Set(turn.receipts.compactMap(\.mealID) + (turn.pendingMealID.map { [$0] } ?? []))
        return diary.snapshot?.meals.filter { ids.contains($0.id) } ?? []
    }
    func linkedWorkouts(_ turn: CoachTurn) -> [WorkoutSession] {
        let ids = Set(turn.receipts.compactMap(\.workoutID))
        guard !ids.isEmpty else { return [] }
        return diary.snapshot?.workouts.filter { ids.contains($0.id) } ?? []
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
