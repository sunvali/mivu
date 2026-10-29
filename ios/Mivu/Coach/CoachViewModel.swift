import Foundation
import UIKit
import Observation
import Network
import os

private final class CoachNavigationReadFence: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: true)
    var isValid: Bool { state.withLock { $0 } }
    func cancel() { state.withLock { $0 = false } }
}

@MainActor private final class CoachNavigationReadState {
    var request: CoachPageRequest?
    var fence: CoachNavigationReadFence?
    weak var timeline: CoachTimelineViewModel?
}

@MainActor @Observable final class CoachViewModel {
    typealias Inference = @Sendable ([CoachInferenceInput], Data) async throws -> CoachInferenceResult
    let diary: DiaryViewModel
    let connection: ChatGPTConnection
    let attachmentDraft: CoachAttachmentDraft
    var draft: MealDraft {
        get { attachmentDraft.legacyDraft }
        set { synchronizeDraftOwnership(); attachmentDraft.legacyDraft = newValue }
    }
    var exchanges: [CoachExchangeSummary] { timeline?.exchanges ?? [] }
    private(set) var captureReceipt: UUID?
    private(set) var companionCaptureEvent: CompanionEvent?
    private(set) var companionSubmission: CompanionSubmission?
    private(set) var companionPhotoEvent: CompanionEvent?
    private(set) var isSending = false
    private(set) var isWorking = false
    private(set) var activity: CoachActivity?
    private(set) var activityTurnID: UUID?
    var errorMessage: String? {
        didSet { if errorMessage != nil { errorRevision += 1 } }
    }
    private var errorRevision = 0
    private var sendingErrorRevision = 0
    @ObservationIgnored private let timelinePageLoading: (@Sendable (CoachPageRequest, DiarySelectionOwnership) async throws -> CoachPage)?
    @ObservationIgnored private let beginCaptureProtection: @MainActor () -> (@MainActor () -> Void)
    @ObservationIgnored private let captureDependencies: CoachAttachmentDraft.Dependencies
    @ObservationIgnored private let inference: () throws -> Inference
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let lookup: @Sendable (String) async throws -> [FoodEvidenceRecord]
    @ObservationIgnored private var sending: Task<Bool, Never>?
    @ObservationIgnored private var captureNeedsProcessing = false
    @ObservationIgnored private var acceptedDiaryCapture: UUID?
    @ObservationIgnored private var acceptedDiaryCaptureOwner: DiarySelectionOwnership?
    @ObservationIgnored private var backgroundCompletion: Task<Void, Never>?
    @ObservationIgnored private var backgroundGeneration: UUID?
    @ObservationIgnored private var backgroundEnd: (@MainActor () -> Void)?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var workerID: UUID?
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var monitoring = false
    @ObservationIgnored private var active = true
    @ObservationIgnored private var presentationActive = true

    init(diary: DiaryViewModel, connection: ChatGPTConnection, inference: (() throws -> Inference)? = nil,
         lookup: @escaping @Sendable (String) async throws -> [FoodEvidenceRecord] = { _ in throw FoodEvidenceClient.Failure.notConfigured },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         timelinePageLoading: (@Sendable (CoachPageRequest, DiarySelectionOwnership) async throws -> CoachPage)? = nil,
         attachmentDependencies: CoachAttachmentDraft.Dependencies? = nil,
         beginCaptureProtection: @escaping @MainActor () -> (@MainActor () -> Void) = { CoachCaptureProtection.begin() }) {
        self.diary = diary; self.connection = connection; self.timelinePageLoading = timelinePageLoading
        var dependencies = CoachAttachmentDraft.Dependencies(store: diary.store,
            refresh: { selected in try await diary.refresh(profileID: selected.identity.profileID) })
        #if DEBUG
        if DiaryLaunch.isCoachHistoryFixture {
            dependencies.prepare = { _, owner in
                try await diary.store.coachCapturePreparation(at: CoachCorrectionUITestFixture.isEnabled ? CoachCorrectionUITestFixture.captureInstant : CoachUITestInference.historyCaptureInstant, expectedProfileID: owner.identity.profileID)
            }
        }
        #endif
        captureDependencies = attachmentDependencies ?? dependencies
        attachmentDraft = CoachAttachmentDraft(ownership: diary.selection, limiter: diary.photoWorkLimiter, dependencies: captureDependencies)
        self.inference = inference ?? { try connection.coachInference() }
        self.lookup = lookup; self.sleep = sleep
        self.beginCaptureProtection = beginCaptureProtection
        attachmentDraft.onPhotoAccepted = { [weak self] in
            guard let self, let owner = self.diary.selection?.identity.profileID else { return }
            let operation = self.attachmentDraft.submissionID
            if self.companionPhotoEvent?.profileID != owner || self.companionPhotoEvent?.operationID != operation {
                self.companionPhotoEvent = CompanionEvent(profileID: owner, operationID: operation, kind: .photoAdded, committedAt: Date())
            }
        }
    }

    private(set) var timeline: CoachTimelineViewModel?
    private(set) var receiptTargets: [UUID: CoachReceiptTarget] = [:]
    private(set) var undoStates: [String: CoachUndoState] = [:]
    @ObservationIgnored private var timelineLoadingTask: Task<Void, Never>?
    private var timelineOwnership: DiarySelectionOwnership?
    private var seekGeneration = UUID()
    @ObservationIgnored private let navigationReadState = CoachNavigationReadState()
    private(set) var highlightedTurnID: UUID?
    var turns: [CoachExchangeSummary] { exchanges }

    /// One fixed source owner per selection; never rebind a suspended source to a new epoch.
    func loadTimelineIfNeeded() async {
        guard let owner = diary.selection, !diary.isChangingProfile else { return }
        if timelineOwnership == owner, timeline != nil { await timelineLoadingTask?.value; return }
        let store = diary.store, pageLoading = timelinePageLoading, navigation = navigationReadState
        let source: CoachTimelineViewModel.PageSource = { [diary] request, sourceGeneration in
            guard await MainActor.run(body: { diary.selection == owner && diary.isChangingProfile == false }) else { throw DiaryError.wrongOwner }
            let fence = await MainActor.run { navigation.request == request ? navigation.fence : nil }
            if fence?.isValid == false {
                await MainActor.run { navigation.timeline?.abandonReplacement(sourceGeneration: sourceGeneration) }
                throw CancellationError()
            }
            // The injected transport may suspend, but actor validation keeps ownership fixed.
            try await store.validateSelectionOwnership(owner)
            let page: CoachPage
            do {
                if let pageLoading { page = try await pageLoading(request, owner) }
                else { page = try await store.coachPage(request, expectedSelection: owner) }
            } catch {
                if fence?.isValid == false {
                    await MainActor.run { navigation.timeline?.abandonReplacement(sourceGeneration: sourceGeneration) }
                }
                throw error
            }
            try await store.validateSelectionOwnership(owner)
            guard await MainActor.run(body: { diary.selection == owner && diary.isChangingProfile == false }), !Task.isCancelled else { throw DiaryError.wrongOwner }
            if fence?.isValid == false {
                await MainActor.run { navigation.timeline?.abandonReplacement(sourceGeneration: sourceGeneration) }
                throw CancellationError()
            }
            return page
        }
        let refresh: CoachTimelineViewModel.RefreshSource = { [diary] ids, identity, _ in
            guard identity == owner.identity,
                  await MainActor.run(body: { diary.selection == owner && diary.isChangingProfile == false }) else { throw DiaryError.wrongOwner }
            let value = try await store.coachTimelineRefresh(ids: ids, expectedSelection: owner)
            guard await MainActor.run(body: { diary.selection == owner && diary.isChangingProfile == false }), !Task.isCancelled else { throw DiaryError.wrongOwner }
            return value
        }
        timelineLoadingTask?.cancel()
        let model: CoachTimelineViewModel
        if let timeline {
            timeline.rebind(identity: owner.identity, source: source, refreshSource: refresh)
            model = timeline
        } else { model = CoachTimelineViewModel(source: source, refreshSource: refresh) }
        timeline = model; navigation.timeline = model; timelineOwnership = owner; receiptTargets = [:]
        let loading = Task<Void, Never> {
            await model.loadLatest()
            guard diary.selection == owner, !Task.isCancelled else { return }
            await refreshLinks()
        }
        timelineLoadingTask = loading
        await loading.value
        if timelineOwnership == owner { timelineLoadingTask = nil }
    }

    func connectTimeline() async {
        guard let owner = diary.selection, !diary.isChangingProfile else { return }
        // Subscribe before the initial read so an accepted mutation cannot fall in the gap.
        let stream = await diary.store.changes(expectedProfileID: owner.identity.profileID)
        let reusingTimeline = timelineOwnership == owner && timeline != nil
        await loadTimelineIfNeeded()
        guard diary.selection == owner, let model = timeline, !Task.isCancelled else { return }
        if reusingTimeline {
            let changed = Set(model.exchanges.map(\.id))
            await model.apply(DiaryChanges(turnIDs: changed, coachLatestChanged: true))?.value
            guard diary.selection == owner, !diary.isChangingProfile, !Task.isCancelled else { return }
            await refreshLinks()
        }
        for await changes in stream {
            guard diary.selection == owner, !diary.isChangingProfile, !Task.isCancelled else { return }
            model.apply(changes)
            await refreshLinks()
        }
    }

    /// Starts an unsent message for the person to finish; never replaces text they already typed.
    @discardableResult func prefill(_ text: String) -> Bool {
        guard draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        draft.text = text
        return true
    }
    /// Quotes an earlier message, replacing any quote already in the composer.
    func reply(to turn: CoachExchangeSummary, fromPip: Bool) {
        // A quote changed mid-send would keep the sent text in the composer for a second send.
        guard !isSending else { return }
        synchronizeDraftOwnership()
        attachmentDraft.reply = Self.quote(turn, fromPip: fromPip)
    }
    private static func quote(_ turn: CoachExchangeSummary, fromPip: Bool) -> CoachReply {
        let text = (fromPip ? turn.assistantText ?? "" : turn.text).trimmingCharacters(in: .whitespacesAndNewlines)
        return CoachReply(target: .message(turnID: turn.id, fromPip: fromPip), excerpt: text.isEmpty ? "Photo" : String(text.prefix(280)))
    }
    /// Asks Coach to finish what an incomplete exchange could not, quoting what already saved.
    func finishRest(of turn: CoachExchangeSummary) async {
        await sendTap(turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Finish the rest" : turn.text, reply: Self.quote(turn, fromPip: true))
    }
    /// Answers Coach's question with one tap: the chosen record is quoted and the label is the message.
    func answer(_ target: CoachReply.Target, label: String, excerpt: String? = nil) async {
        await sendTap(label, reply: CoachReply(target: target, excerpt: String((excerpt ?? label).prefix(280))))
    }
    /// Sends a one-tap message; anything the person was composing is set aside and put back afterwards.
    private func sendTap(_ text: String, reply: CoachReply) async {
        synchronizeDraftOwnership()
        guard !isSending, !attachmentDraft.isPreparing else { return }
        let kept = draft, keptReply = attachmentDraft.reply, owner = diary.selection
        let composing = attachmentDraft.isValid || keptReply != nil
        if composing { draft = MealDraft(submissionID: UUID(), text: text, photos: []) } else { draft.text = text }
        attachmentDraft.reply = reply
        await send()
        // The set-aside draft belongs to its profile; after a profile change it is dropped, like any unsent draft.
        if composing, diary.selection == owner, !diary.isChangingProfile { draft = kept; attachmentDraft.reply = keptReply }
    }
    /// A Diary handoff quote; never replaces a message the person already started.
    @discardableResult func startReply(_ reply: CoachReply) -> Bool {
        synchronizeDraftOwnership()
        guard reply.isValid, attachmentDraft.reply == nil, attachmentDraft.attachments.isEmpty,
              draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        attachmentDraft.reply = reply
        return true
    }
    func seek(_ request: CoachNavigationRequest) async -> Bool {
        guard let target = request.target else { return false }
        traceHistoryNavigation("entered", request)
        await loadTimelineIfNeeded()
        traceHistoryNavigation("ready", request)
        guard let owner = diary.selection, owner == timelineOwnership,
              request.identity == owner.identity, let timeline, !diary.isChangingProfile else { return false }
        let generation = UUID(); seekGeneration = generation
        navigationReadState.fence?.cancel()
        let fence = CoachNavigationReadFence(); navigationReadState.fence = fence
        navigationReadState.request = switch target { case .turn(let id): .aroundTurn(id); case .day(let id): .atDay(id) }
        do {
            try await diary.store.validateSelectionOwnership(owner)
            guard generation == seekGeneration, diary.selection == owner, !Task.isCancelled else { return false }
            traceHistoryNavigation("beforeTimeline", request, generation: generation, fence: fence)
            await withTaskCancellationHandler(operation: { await timeline.seek(target) }, onCancel: { fence.cancel() })
            traceHistoryNavigation("afterTimeline", request, generation: generation, fence: fence)
            try await diary.store.validateSelectionOwnership(owner)
            guard generation == seekGeneration, diary.selection == owner, !diary.isChangingProfile, !Task.isCancelled else { return false }
            await refreshLinks()
            traceHistoryNavigation("afterLinks", request, generation: generation, fence: fence)
            guard fence.isValid else { return false }
            if timeline.error == nil, !timeline.isLoadDeferred {
                highlightedTurnID = switch target {
                case .turn(let id): id
                case .day(let id): timeline.exchanges.first(where: { $0.trackingDayID == id })?.id
                }
                traceHistoryNavigation("accepted", request, generation: generation, fence: fence)
                return true
            }
            traceHistoryNavigation("rejected", request, generation: generation, fence: fence)
            return false
        } catch {
            traceHistoryNavigation("catch", request, generation: generation, fence: fence)
            guard generation == seekGeneration, diary.selection == owner, !Task.isCancelled else { return false }
            errorMessage = "This conversation is unavailable for the current diary."
            return false
        }
    }

    #if DEBUG
    @ObservationIgnored private var historyNavigationTrace: [[String: String]] = []
    var historyNavigationSnapshot: [String: Any] {
        ["modelID": String(describing: ObjectIdentifier(self)), "highlightedTurnID": highlightedTurnID?.uuidString ?? "",
         "timelineID": timeline.map { String(describing: ObjectIdentifier($0)) } ?? "", "events": historyNavigationTrace,
         "ownerMatches": diary.selection == timelineOwnership, "changingProfile": diary.isChangingProfile,
         "fenceValid": navigationReadState.fence?.isValid as Any? ?? NSNull(),
         "request": navigationReadState.request.map { String(describing: $0) } ?? "",
         "loadDeferred": timeline?.isLoadDeferred ?? false, "timelineError": timeline?.error ?? "",
         "queryError": timeline?.queryError.map { String(describing: $0) } ?? ""]
    }
    #endif
    private func traceHistoryNavigation(_ phase: String, _ request: CoachNavigationRequest,
                                        generation: UUID? = nil, fence: CoachNavigationReadFence? = nil) {
        #if DEBUG
        guard DiaryLaunch.isCoachHistoryFixture else { return }
        let resident: Bool = switch request.target {
        case .turn(let id): timeline?.exchanges.contains { $0.id == id } ?? false
        case .day(let id): timeline?.exchanges.contains { $0.trackingDayID == id } ?? false
        case nil: false
        }
        if historyNavigationTrace.count == 32 { historyNavigationTrace.removeFirst() }
        historyNavigationTrace.append(["phase": phase, "requestID": request.requestID.uuidString,
            "target": String(describing: request.target), "cancelled": String(Task.isCancelled),
            "generationMatches": String(generation == nil || generation == seekGeneration),
            "ownerMatches": String(diary.selection == timelineOwnership), "changingProfile": String(diary.isChangingProfile),
            "fenceValid": fence.map { String($0.isValid) } ?? "unset", "resident": String(resident),
            "highlighted": highlightedTurnID?.uuidString ?? "", "deferred": String(timeline?.isLoadDeferred ?? false),
            "error": timeline?.error ?? "", "restoration": timeline.map { String(describing: $0.restoration) } ?? ""])
        #endif
    }

    var canSend: Bool { attachmentDraft.isValid && !attachmentDraft.isPreparing && !isSending && !diary.isSaving && !diary.isChangingProfile && diary.readModel != nil }
    var hasPendingWork: Bool { diary.workStatus.pendingTurnID != nil }
    private(set) var activeOperationTurn: CoachOperationMetadata?
    private var activeOperationOwnership: DiarySelectionOwnership?
    private var activeOperationRead = UUID()
    var companionTurn: CoachOperationMetadata? {
        guard activeOperationOwnership == diary.selection else { return nil }
        return activeOperationTurn
    }
    func refreshActiveOperation() async {
        guard let owner = diary.selection else { activeOperationTurn = nil; activeOperationOwnership = nil; return }
        let operation = activityTurnID ?? companionSubmission.flatMap { $0.profileID == owner.identity.profileID ? $0.operationID : nil } ?? diary.workStatus.pendingTurnID
        let request = UUID(); activeOperationRead = request
        do {
            var turn: CoachOperationMetadata?
            if let operation { turn = try await diary.store.coachOperationMetadata(turnID: operation, expectedSelection: owner) }
            if turn == nil || turn?.state == .completed {
                if let pending = diary.workStatus.pendingTurnID, pending != turn?.id {
                    turn = try await diary.store.coachOperationMetadata(turnID: pending, expectedSelection: owner)
                } else { turn = try await diary.store.coachOperationMetadata(expectedSelection: owner) }
            }
            guard diary.selection == owner, !diary.isChangingProfile, activeOperationRead == request, !Task.isCancelled else { return }
            activeOperationTurn = turn; activeOperationOwnership = owner
        } catch {
            guard diary.selection == owner, activeOperationRead == request, !Task.isCancelled else { return }
            activeOperationTurn = nil; activeOperationOwnership = owner
        }
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

    func synchronizeDraftOwnership() { attachmentDraft.synchronizeOwnership(diary.selection) }
    @discardableResult func send() async -> Bool {
        guard sending == nil else { return false }
        let task = Task { await performSend() }
        sending = task
        defer { sending = nil }
        return await task.value
    }
    private func performSend() async -> Bool {
        synchronizeDraftOwnership()
        guard canSend, let token = diary.selection else { return false }
        let endCaptureProtection = beginCaptureProtection()
        defer { endCaptureProtection() }
        let owner = token.identity.profileID
        let followsLatest = timeline.map { if case .latest = $0.window.viewport { true } else { false } } ?? true
        sendingErrorRevision = errorRevision; isSending = true; diary.isSaving = true
        defer { isSending = false; diary.isSaving = false }
        companionSubmission = CompanionSubmission(profileID: owner, operationID: attachmentDraft.submissionID, acceptedAt: Date())
        do {
            guard let result = try await attachmentDraft.send(onAccepted: { result in
                guard diary.selection == token, !diary.isChangingProfile else { return }
                captureNeedsProcessing = true
                resume()
                guard attachmentDraft.captureReceipt == result.id else { return }
                captureReceipt = result.id
                if companionSubmission?.operationID != result.id {
                    companionSubmission = CompanionSubmission(profileID: owner, operationID: result.id, acceptedAt: Date())
                }
                if companionCaptureEvent?.profileID != owner || companionCaptureEvent?.operationID != result.id {
                    companionCaptureEvent = CompanionEvent(profileID: owner, operationID: result.id, kind: .saved, committedAt: Date())
                }
                if errorRevision == sendingErrorRevision { errorMessage = nil }
            }) else { return false }
            guard diary.selection == token, !diary.isChangingProfile, captureReceipt == result.id else { return false }
            if followsLatest, let timeline { await timeline.jumpToLatest() }
            return true
        } catch {
            if diary.selection == token, !diary.isChangingProfile { errorMessage = "Could not save on this iPhone. Your input is still here." }
            return false
        }
    }

    /// Captures a message from outside the composer (Siri) without touching `draft`; the turn ID is `submissionID`.
    /// Each message gets its own ID, so an existing turn with that ID is this message, already saved.
    /// The message belongs to `profileID`, fixed when it was spoken; it is never captured into another diary.
    func captureExternal(profileID: UUID, _ text: String, submissionID: UUID, capturedAt: Date) async throws {
        guard let owner = diary.selection, !diary.isChangingProfile else { throw DiaryError.noProfile }
        guard owner.identity.profileID == profileID else { throw DiaryError.wrongOwner }
        let endCaptureProtection = beginCaptureProtection()
        defer { endCaptureProtection() }
        var dependencies = captureDependencies
        dependencies.prepare = { [store = diary.store] _, owner in
            try await store.coachCapturePreparation(at: capturedAt, expectedProfileID: owner.identity.profileID)
        }
        let context = try await dependencies.prepare(capturedAt, owner).context
        let manifest = try CoachSubmissionPayload(submissionID: submissionID, text: text, attachments: [], context: context).manifest
        if case .absent = try await dependencies.reconcile(submissionID, manifest, owner) {
            let message = CoachAttachmentDraft(ownership: owner, limiter: diary.photoWorkLimiter, dependencies: dependencies,
                                               text: text, submissionID: submissionID)
            _ = try await message.send()
        }
        captureNeedsProcessing = true
        resume()
    }
    /// Siri text saved while the phone was locked; it reaches the Coach only after the person sends it.
    private var waitingSiri: [CoachInbox.Entry] = []
    /// Follows the selected profile, so a profile switch never shows another diary's message.
    var queuedSiri: [CoachInbox.Entry] { waitingSiri.filter { $0.profileID == diary.selection?.identity.profileID } }
    var inbox: CoachInbox?
    func loadQueuedSiri() {
        guard let inbox, !diary.profiles.isEmpty else { waitingSiri = []; return }
        let profiles = Set(diary.profiles.map(\.id))
        for entry in inbox.entries() where !profiles.contains(entry.profileID) { try? inbox.remove(entry.id) }
        waitingSiri = inbox.entries()
    }
    /// The entry ID is the submission ID, so a send after a crash reconciles instead of saving twice.
    func sendQueued(_ entry: CoachInbox.Entry) async {
        do {
            try await captureExternal(profileID: entry.profileID, entry.text, submissionID: entry.id, capturedAt: entry.capturedAt)
            try inbox?.remove(entry.id)
        } catch { errorMessage = "Could not save on this iPhone. Your input is still here." }
        loadQueuedSiri()
    }
    func discardQueued(_ entry: CoachInbox.Entry) {
        try? inbox?.remove(entry.id); loadQueuedSiri()
    }
    func resume() {
        if let receipt = diary.captureReceipt, let owner = diary.selection, !diary.isChangingProfile,
           diary.companionCaptureEvent?.profileID == owner.identity.profileID,
           receipt != acceptedDiaryCapture || owner != acceptedDiaryCaptureOwner {
            acceptedDiaryCapture = receipt; acceptedDiaryCaptureOwner = owner; captureNeedsProcessing = true
        }
        guard active, worker == nil, !diary.isChangingProfile, let selected = diary.selection else { return }
        let owner = selected.identity.profileID
        let id = UUID(); workerID = id; isWorking = true
        worker = Task {
            defer { if workerID == id { worker = nil; workerID = nil; isWorking = false; activity = nil; activityTurnID = nil } }
            var capturedOnly = false
            repeat {
                guard active, !Task.isCancelled, diary.selection == selected, !diary.isChangingProfile else { break }
                let acceptedCaptureAtPassStart = captureReceipt
                let acceptedDiaryCaptureAtPassStart = diary.captureReceipt
                var processingFailed = false
                var unfinished: (turnID: UUID, error: any Error)?
                do {
                    try await recoverLegacyCaptures(owner: owner)
                    while !Task.isCancelled {
                        guard active, diary.selection == selected, !diary.isChangingProfile else { break }
                        let pendingCaptureWake = captureNeedsProcessing
                        captureNeedsProcessing = false
                        let next: CoachTurnResult?
                        do {
                            next = try await diary.store.nextCoachResult(includeWaitingForConnection: connection.canInfer, capturedOnly: capturedOnly, expectedProfileID: owner)
                        } catch {
                            captureNeedsProcessing = captureNeedsProcessing || pendingCaptureWake
                            throw error
                        }
                        guard let turn = next else {
                            if captureNeedsProcessing { continue }
                            break
                        }
                        activity = nil; activityTurnID = nil
                        do {
                            if turn.state == .analyzing {
                                try await diary.store.setCoachTurnState(turnID: turn.id, state: .captured, expectedProfileID: owner)
                            }
                            if turn.pendingMealID != nil, turn.receipts.isEmpty {
                                _ = try await diary.store.preparePendingCoachTurn(turnID: turn.id, expectedProfileID: owner)
                            }
                        } catch { unfinished = (turn.id, error); throw error }
                        let bound: Inference
                        do { bound = try inference() }
                        catch {
                            processingFailed = true
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
                            processingFailed = true
                            unfinished = (turn.id, error)
                            break
                        }
                        guard !Task.isCancelled, diary.selection == selected else { break }
                        try await diary.refresh(profileID: owner)
                        if let mealID = turn.pendingMealID {
                            await diary.loadMeal(mealID)
                            if let meal = diary.meal(mealID) { MealNotification.post(meal) }
                        }
                    }
                } catch {
                    processingFailed = true
                    CoachEngine.logger.error("Coach worker failed: \(CoachEngine.failureReason(error), privacy: .public)")
                    if !Task.isCancelled, diary.selection == selected { errorMessage = message(for: error) }
                }
                if let unfinished, !Task.isCancelled, diary.selection == selected, !diary.isChangingProfile {
                    await settle(unfinished.turnID, after: unfinished.error, owner: owner)
                }
                if diary.selection == selected, !diary.isChangingProfile { try? await diary.refresh(profileID: owner) }
                if processingFailed {
                    guard captureReceipt != acceptedCaptureAtPassStart || diary.captureReceipt != acceptedDiaryCaptureAtPassStart else { break }
                    capturedOnly = true
                }
                // A capture can arrive during the final refresh while this worker is still owned.
            } while captureNeedsProcessing && active && !Task.isCancelled && diary.selection == selected && !diary.isChangingProfile
        }
    }

    /// The engine records a failure only while its selection epoch holds. A turn it left unfinished still ends with its
    /// saved-food summary or a Try again, never "Thinking…" with no way out.
    private func settle(_ turnID: UUID, after error: any Error, owner: UUID) async {
        let store = diary.store
        guard let stored = try? await store.coachResult(turnID: turnID, expectedProfileID: owner),
              [.captured, .analyzing].contains(stored.state) else { return }
        // Saved food is never reported as a failure; the person can ask for the rest.
        if !stored.receipts.isEmpty, let text = try? await store.coachCommittedSummary(turnID: turnID, expectedProfileID: owner),
           (try? await store.completeCoachTurn(turnID: turnID, assistantText: text, incomplete: true, expectedProfileID: owner)) != nil {
            errorMessage = nil
            return
        }
        let reason = CoachEngine.failureReason(error)
        CoachEngine.logger.error("Coach turn left unfinished: \(reason, privacy: .public)")
        try? await store.setCoachTurnState(turnID: turnID, state: .needsRetry, failureReason: reason, expectedProfileID: owner)
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
    func previousDayDate(_ turn: CoachExchangeSummary) -> String? {
        guard linksSelection == diary.selection else { return nil }
        return turn.trackingDayID.flatMap { capturedDayLabels[$0] }
    }
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
    func continueInBackground(begin: (@escaping @MainActor () -> Void) -> Bool,
                              end: @escaping @MainActor () -> Void,
                              onWorkerDrain: @escaping @MainActor () -> Void = {}) {
        pauseActivity()
        endBackgroundLease()
        guard diary.hasCaptureInFlight || sending != nil || isSending || captureNeedsProcessing || hasPendingWork || (diary.readModel?.pendingCount ?? 0) > 0,
              let owner = diary.selection else { diary.enterBackground(); enterBackground(); connection.enterBackground(); return }
        let generation = UUID()
        backgroundGeneration = generation
        guard begin({ [weak self] in
            guard let self, backgroundGeneration == generation else { return }
            guard diary.selection == owner, !diary.isChangingProfile else { endBackgroundLease(); return }
            diary.enterBackground(); enterBackground(); connection.enterBackground(); endBackgroundLease()
        }) else {
            backgroundGeneration = nil
            diary.enterBackground(); enterBackground(); connection.enterBackground()
            return
        }
        backgroundEnd = end
        active = true
        diary.resumeWorker(allowProcessing: true)
        backgroundCompletion = Task {
            _ = await sending?.value
            await diary.waitForCapture()
            guard backgroundGeneration == generation else { return }
            guard diary.selection == owner, !diary.isChangingProfile else { endBackgroundLease(); return }
            if captureNeedsProcessing { resume() }
            await diary.waitForWorker()
            guard backgroundGeneration == generation else { return }
            guard diary.selection == owner, !diary.isChangingProfile else { endBackgroundLease(); return }
            onWorkerDrain()
            await waitForWorker()
            guard backgroundGeneration == generation else { return }
            if diary.selection == owner, !diary.isChangingProfile { diary.enterBackground(); enterBackground(); connection.enterBackground() }
            endBackgroundLease()
        }
    }
    func endBackgroundLease() {
        backgroundGeneration = nil
        backgroundCompletion?.cancel(); backgroundCompletion = nil
        let end = backgroundEnd; backgroundEnd = nil
        end?()
    }
    func waitForBackgroundCompletion() async { await backgroundCompletion?.value }
    func pauseForInactiveScene() { active = false; pauseActivity() }
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
        await refreshActiveOperation()
    }
    private var capturedDayLabels: [UUID: String] = [:]
    private var linksSelection: DiarySelectionOwnership?
    private var linksGeneration: UInt64?
    private var linksAreCurrent: Bool { !diary.isChangingProfile && linksSelection == diary.selection && linksGeneration == diary.changeGeneration }
    private var linksRequest = UUID()
    private(set) var linksRevision = 0
    private(set) var historyFixtureFacts = ""
    struct FixtureReplyStatus: Equatable {
        var id: UUID
        var state: CoachTurnState
        var assistantText: String?
    }
    private(set) var historyFixtureLatest: FixtureReplyStatus?
    func refreshLinks() async {
        await refreshActiveOperation()
        await refreshHistoryFixtureFacts()
        guard let token = diary.selection else { receiptTargets = [:]; undoStates = [:]; capturedDayLabels = [:]; linksSelection = nil; return }
        let request = UUID(), rows = turns, generation = diary.changeGeneration; linksRequest = request
        let ids = Set(rows.flatMap { Array($0.linkedMealIDs) + $0.receipts.compactMap(\.workoutID) })
        receiptTargets = receiptTargets.filter { ids.contains($0.key) }
        do {
            let values = try await diary.store.coachReceiptTargets(exchanges: rows, expectedSelection: token)
            let undo = try await diary.store.coachUndoStates(keys: rows.flatMap { $0.receipts.map(\.operationKey) }, expectedProfileID: token.identity.profileID)
            let dayIDs = Set(rows.filter(\.needsDayChoice).compactMap(\.trackingDayID))
            let labels: [UUID: String]
            if dayIDs.isEmpty { labels = [:] }
            else { labels = try await diary.store.coachCapturedDayLabels(ids: dayIDs, expectedSelection: token) }
            guard diary.selection == token, !diary.isChangingProfile, linksRequest == request, diary.changeGeneration == generation, !Task.isCancelled else { return }
            linksSelection = token; linksGeneration = generation; receiptTargets = values; undoStates = undo; capturedDayLabels = labels; linksRevision += 1
        } catch {
            guard diary.selection == token, linksRequest == request, diary.changeGeneration == generation, !Task.isCancelled else { return }
            linksSelection = token; linksGeneration = generation; receiptTargets = Dictionary(uniqueKeysWithValues: ids.map { ($0, .failed) }); undoStates = [:]; capturedDayLabels = [:]; linksRevision += 1
        }
    }
    private func refreshHistoryFixtureFacts() async {
        #if DEBUG
        guard DiaryLaunch.isCoachHistoryFixture, let owner = diary.selection else { return }
        do {
            let meal = try await diary.store.meal(id: CoachUITestInference.historyID(910), expectedProfileID: owner.identity.profileID)
            let meals = try await diary.store.coachMeals(on: "2027-01-15", expectedProfileID: owner.identity.profileID)
            let latest = try await diary.store.coachLatestExchange(expectedSelection: owner)
            guard diary.selection == owner, !Task.isCancelled else { return }
            historyFixtureLatest = latest.map { FixtureReplyStatus(id: $0.id, state: $0.state, assistantText: $0.assistantText) }
            let receipt = latest?.receipts.first { $0.itemID == CoachUITestInference.historyID(920) }
            let facts: [String: Any] = ["mealIDs": meals.meals.map { $0.id.uuidString }.sorted(), "hasMoreMeals": meals.hasMore,
                "sourceTurnID": meal.sourceTurnID?.uuidString ?? "", "chickenQuantity": meal.items.first { $0.id == CoachUITestInference.historyID(920) }?.quantity as Any? ?? NSNull(),
                "latestTurnID": latest?.id.uuidString ?? "", "latestText": latest?.text ?? "", "latestState": latest?.state.rawValue ?? "", "latestReply": latest?.assistantText ?? "", "receiptKey": receipt?.operationKey ?? "",
                "receiptDate": receipt?.targetLocalDate ?? "", "receiptQuantity": receipt?.items.first?.quantity as Any? ?? NSNull(),
                "capturedAt": latest?.capturedAt.timeIntervalSince1970 as Any? ?? NSNull(), "trackingDayID": latest?.trackingDayID?.uuidString ?? ""]
            historyFixtureFacts = String(decoding: try JSONSerialization.data(withJSONObject: facts, options: .sortedKeys), as: UTF8.self)
        } catch { }
        #endif
    }
    func receiptTarget(_ receipt: CoachCommittedReceipt) -> CoachReceiptTarget {
        guard linksAreCurrent else { return .loading }
        guard let id = receipt.mealID ?? receipt.workoutID else { return .unavailable }
        let value = receiptTargets[id] ?? .loading
        if let itemID = receipt.itemID, case .meal(let meal, _) = value,
           !(meal.items + meal.submissions.flatMap { $0.proposal?.items ?? [] }).contains(where: { $0.id == itemID }) { return .unavailable }
        return value
    }
    private var undoing: Set<String> = []
    /// Hidden while its undo runs, so a second tap cannot race the first.
    func undoState(_ receipt: CoachCommittedReceipt) -> CoachUndoState? {
        linksAreCurrent && !undoing.contains(receipt.operationKey) ? undoStates[receipt.operationKey] : nil
    }
    /// A direct diary edit, not a chat exchange; the card re-reads availability afterwards.
    func undo(_ receipt: CoachCommittedReceipt) async {
        guard let owner = diary.selection?.identity.profileID, undoing.insert(receipt.operationKey).inserted else { return }
        defer { undoing.remove(receipt.operationKey) }
        await diary.change { try await self.diary.store.undoCoachChange(operationKey: receipt.operationKey, expectedProfileID: owner) }
        await refreshLinks()
    }
    func linkedMeals(_ turn: CoachExchangeSummary) -> [MealReadModel] {
        guard linksAreCurrent else { return [] }
        return turn.linkedMealIDs.compactMap { if case .meal(let meal, _) = receiptTargets[$0] { meal } else { nil } }
    }
    func linkedWorkouts(_ turn: CoachExchangeSummary) -> [WorkoutSession] {
        guard linksAreCurrent else { return [] }
        return Set(turn.receipts.compactMap(\.workoutID)).compactMap { if case .workout(let workout, _) = receiptTargets[$0] { workout } else { nil } }
    }
    private func message(for error: Error) -> String {
        if error as? ResponsesClient.Failure == .usageUnavailable { return "ChatGPT is busy right now. Your message is saved; try again soon." }
        if ProbeRunner.isTransient(error) { return "You're offline. Your message is saved and I'll reply when you're back online." }
        if error is CancellationError || error as? SessionError == .sessionChanged { return "The connection changed. Your message is saved; tap Try again." }
        if error as? ResponsesClient.Failure == .quotaReached { return "You've reached your ChatGPT usage limit. Your message is saved; see Manage usage in Settings." }
        if error as? DiaryError == .staleRevision { return "Something changed while I was working. Check it, then try again." }
        if error as? DiaryError == .invalidAmountUnitChange { return error.localizedDescription }
        if error as? DiaryError == .ambiguousDay { return "Which day is this for?" }
        if error as? CoachError == .ungroundedConfirmation { return "I need a little more detail to log that." }
        if error as? DiaryError == .persistenceFailed { return "Couldn't save that. Your message is kept; tap Try again." }
        return "Something went wrong. Your message is saved; tap Try again." }
}

@MainActor enum CoachCaptureProtection {
    static func begin(
        begin: (@escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier = { expire in
            UIApplication.shared.beginBackgroundTask(withName: "Save Coach input") {
                expire()
            }
        },
        end: @escaping @MainActor (UIBackgroundTaskIdentifier) -> Void = { UIApplication.shared.endBackgroundTask($0) }
    ) -> @MainActor () -> Void {
        var identifier = UIBackgroundTaskIdentifier.invalid
        var finished = false
        func finish() {
            guard !finished else { return }
            finished = true
            guard identifier != .invalid else { return }
            let ending = identifier; identifier = .invalid
            end(ending)
        }
        identifier = begin(finish)
        // Expiration may arrive before acquisition returns its identifier.
        if finished, identifier != .invalid {
            let ending = identifier; identifier = .invalid
            end(ending)
        }
        return finish
    }
}
