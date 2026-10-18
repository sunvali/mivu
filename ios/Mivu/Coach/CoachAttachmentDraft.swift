import Foundation
import Observation

@MainActor @Observable final class CoachAttachmentDraft {
    enum Failure: Error, Equatable, Sendable { case conflictingPayload, stalePresentation, busy }
    enum PhotoSource: Equatable, Sendable { case camera, library }
    struct Selection: Sendable {
        let id: UUID
        let load: @Sendable () async throws -> Data
        init(id: UUID = UUID(), load: @escaping @Sendable () async throws -> Data) { self.id = id; self.load = load }
    }
    struct Attempt: Sendable {
        let ownership: DiarySelectionOwnership
        let payload: CoachSubmissionPayload
        let snapshot: Snapshot
    }
    struct Snapshot: Equatable, Sendable {
        let submissionID: UUID
        let text: String
        let attachments: [MealPhoto]
    }
    struct Dependencies: Sendable {
        var prepare: @Sendable (Date, DiarySelectionOwnership) async throws -> CoachCapturePreparation
        var capture: @Sendable (CoachSubmissionPayload, DiarySelectionOwnership) async throws -> CoachExchangeSummary
        var reconcile: @Sendable (UUID, CoachSubmissionManifest, DiarySelectionOwnership) async throws -> CoachCaptureReconciliation
        var refresh: @Sendable (DiarySelectionOwnership) async throws -> Void
        var validate: @Sendable (DiarySelectionOwnership) async throws -> Void
        var normalize: @Sendable (Data, PhotoSource) async throws -> Data

        init(store: DiaryStore, refresh: @escaping @Sendable (DiarySelectionOwnership) async throws -> Void = { _ in }) {
            prepare = { at, owner in try await store.coachCapturePreparation(at: at, expectedProfileID: owner.identity.profileID) }
            capture = { payload, owner in
                try await store.captureCoachSubmission(payload, expectedSelection: owner, expectedProfileID: owner.identity.profileID)
            }
            reconcile = { id, manifest, owner in
                try await store.reconcileCoachCapture(submissionID: id, expectedManifest: manifest,
                    expectedSelection: owner, expectedProfileID: owner.identity.profileID)
            }
            self.refresh = refresh
            validate = { owner in
                guard try await store.selectionOwnership(expectedProfileID: owner.identity.profileID) == owner else { throw DiaryError.wrongOwner }
            }
            normalize = { bytes, source in try await CoachAttachmentDraft.normalize(bytes, source: source) }
        }
    }

    private(set) var ownership: DiarySelectionOwnership?
    var text: String
    private(set) var attachments: [MealPhoto]
    private(set) var submissionID: UUID
    private(set) var uncertainAttempt: Attempt?
    private(set) var captureReceipt: UUID?
    private(set) var isSending = false
    private var lastAcceptedAttempt: Attempt?
    private var generation: UInt64 = 0
    private var presentationID: UUID?
    private struct Reservation { let id: UUID; let replacement: Bool }
    private var reservations: [UUID: Reservation] = [:]
    private var order: [UUID: Int] = [:]
    private var nextOrder = 0
    @ObservationIgnored private let limiter: PhotoWorkLimiter
    @ObservationIgnored private let dependencies: Dependencies

    init(ownership: DiarySelectionOwnership?, limiter: PhotoWorkLimiter, dependencies: Dependencies,
         text: String = "", attachments: [MealPhoto] = [], submissionID: UUID = UUID()) {
        self.ownership = ownership; self.limiter = limiter; self.dependencies = dependencies
        self.text = text; self.attachments = attachments; self.submissionID = submissionID
        for (index, photo) in attachments.enumerated() { order[photo.id] = index }; nextOrder = attachments.count
    }

    var reservedAttachmentCount: Int { reservations.values.filter { !$0.replacement }.count }
    var isPreparing: Bool { !reservations.isEmpty }
    var isValid: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty }
    private var snapshot: Snapshot { Snapshot(submissionID: submissionID, text: text, attachments: attachments) }

    func synchronizeOwnership(_ selected: DiarySelectionOwnership?) {
        guard ownership != selected else { return }
        generation &+= 1; presentationID = nil; reservations = [:]
        ownership = selected; text = ""; attachments = []; order = [:]; nextOrder = 0
        submissionID = UUID(); uncertainAttempt = nil; lastAcceptedAttempt = nil; captureReceipt = nil
    }

    // Older direct callers still exchange MealDraft; the byte-bearing owner remains this object.
    var legacyDraft: MealDraft {
        get { MealDraft(submissionID: submissionID, text: text, photos: attachments.map(\.data)) }
        set {
            let prior = lastAcceptedAttempt?.payload.submissionID == newValue.submissionID ? lastAcceptedAttempt?.payload.attachments ?? [] : attachments
            text = newValue.text; submissionID = newValue.submissionID
            attachments = newValue.photos.enumerated().map { index, data in
                if prior.indices.contains(index), prior[index].data == data { return prior[index] }
                return MealPhoto(data: data)
            }
            order = Dictionary(uniqueKeysWithValues: attachments.enumerated().map { ($0.element.id, $0.offset) }); nextOrder = attachments.count
            if let accepted = lastAcceptedAttempt, accepted.snapshot == snapshot { uncertainAttempt = accepted }
        }
    }

    func beginPresentation() throws -> UUID {
        guard ownership != nil else { throw DiaryError.noProfile }
        generation &+= 1; reservations = [:]
        let id = UUID(); presentationID = id; return id
    }
    func isPresentationCurrent(_ id: UUID) -> Bool { presentationID == id }
    func endPresentation(_ id: UUID) async throws {
        guard presentationID == id else { return }
        presentationID = nil; try await cancelPendingImports()
    }
    func cancelPendingImports() async throws { generation &+= 1; reservations = [:] }
    func remove(_ id: UUID) async throws { attachments.removeAll { $0.id == id }; reservations[id] = nil; order[id] = nil }

    private func validate(_ owner: DiarySelectionOwnership, generation expected: UInt64, presentation: UUID?) async throws {
        try Task.checkCancellation()
        guard ownership == owner, generation == expected,
              presentation == nil || presentationID == presentation else { throw Failure.stalePresentation }
        try await dependencies.validate(owner)
        try Task.checkCancellation()
        guard ownership == owner, generation == expected,
              presentation == nil || presentationID == presentation else { throw Failure.stalePresentation }
    }

    private func prepared(_ selection: Selection, source: PhotoSource, owner: DiarySelectionOwnership,
                          generation expected: UInt64, presentation: UUID?) async throws -> Data {
        let limiter = limiter, normalize = dependencies.normalize
        return try await limiter.withPermit {
            let work = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let bytes = try await selection.load()
                try Task.checkCancellation()
                guard bytes.count <= 40_000_000 else { throw DiaryError.invalidData }
                try await self.validate(owner, generation: expected, presentation: presentation)
                let result = try await normalize(bytes, source)
                try Task.checkCancellation()
                try await self.validate(owner, generation: expected, presentation: presentation)
                return result
            }
            return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
        }
    }

    func importSelections(_ selections: [Selection], presentationID: UUID? = nil) async throws -> [UUID] {
        try await importPhotos(selections, source: .library, presentationID: presentationID)
    }
    private func importPhotos(_ selections: [Selection], source: PhotoSource, presentationID: UUID?) async throws -> [UUID] {
        guard let owner = ownership else { throw DiaryError.noProfile }
        let expected = generation
        try await validate(owner, generation: expected, presentation: presentationID)
        let count = max(0, 8 - attachments.count - reservedAttachmentCount)
        let admitted = Array(selections.prefix(count))
        var failed = selections.dropFirst(count).map(\.id)
        var jobs: [(Selection, UUID)] = []
        for selection in admitted {
            guard reservations[selection.id] == nil, !attachments.contains(where: { $0.id == selection.id }) else { failed.append(selection.id); continue }
            let id = UUID(); reservations[selection.id] = Reservation(id: id, replacement: false)
            order[selection.id] = nextOrder; nextOrder += 1; jobs.append((selection, id))
        }
        await withTaskGroup(of: (UUID, UUID, Result<Data, Error>).self) { group in
            for (selection, jobID) in jobs {
                group.addTask {
                    do { return (selection.id, jobID, .success(try await self.prepared(selection, source: source, owner: owner, generation: expected, presentation: presentationID))) }
                    catch { return (selection.id, jobID, .failure(error)) }
                }
            }
            for await (id, jobID, result) in group {
                guard reservations[id]?.id == jobID else { continue }
                do {
                    try await validate(owner, generation: expected, presentation: presentationID)
                    guard reservations[id]?.id == jobID else { continue }
                    switch result {
                    case .success(let bytes):
                        attachments.append(MealPhoto(id: id, data: bytes))
                        attachments.sort { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
                    case .failure: failed.append(id)
                    }
                } catch { }
                reservations[id] = nil
            }
        }
        return selections.map(\.id).filter { failed.contains($0) }
    }

    func retake(_ id: UUID, selection: Selection, presentationID: UUID? = nil, source: PhotoSource = .library) async throws {
        guard let owner = ownership else { throw DiaryError.noProfile }
        guard let previous = attachments.first(where: { $0.id == id }), reservations[id] == nil else { throw DiaryError.notFound }
        let expected = generation, jobID = UUID()
        reservations[id] = Reservation(id: jobID, replacement: true)
        defer { if reservations[id]?.id == jobID { reservations[id] = nil } }
        let data = try await prepared(selection, source: source, owner: owner, generation: expected, presentation: presentationID)
        try await validate(owner, generation: expected, presentation: presentationID)
        guard reservations[id]?.id == jobID, let index = attachments.firstIndex(where: { $0.id == id }) else { throw Failure.stalePresentation }
        attachments[index] = MealPhoto(id: id, data: data, createdAt: previous.createdAt, role: previous.role)
    }

    func capture(using camera: CoachCameraSession, presentationID: UUID, replacing id: UUID? = nil) async throws {
        let selection = Selection { try await camera.capture() }
        if let id { try await retake(id, selection: selection, presentationID: presentationID, source: .camera) }
        else {
            let failed = try await importPhotos([selection], source: .camera, presentationID: presentationID)
            if !failed.isEmpty { throw DiaryError.invalidData }
        }
    }

    private func validateSend(_ owner: DiarySelectionOwnership) async throws {
        try Task.checkCancellation()
        guard ownership == owner else { throw DiaryError.wrongOwner }
        try await dependencies.validate(owner)
        try Task.checkCancellation()
        guard ownership == owner else { throw DiaryError.wrongOwner }
    }
    private func accepted(_ attempt: Attempt, result: CoachExchangeSummary) {
        lastAcceptedAttempt = attempt; uncertainAttempt = nil
        if snapshot == attempt.snapshot {
            text = ""; attachments = []; order = [:]; nextOrder = 0; submissionID = UUID(); captureReceipt = result.id
        } else if submissionID == attempt.payload.submissionID { submissionID = UUID() }
    }

    func send() async throws -> CoachExchangeSummary? {
        guard !isSending, !isPreparing else { throw Failure.busy }
        guard let owner = ownership else { throw DiaryError.noProfile }
        guard isValid else { throw DiaryError.emptyCapture }
        isSending = true; defer { isSending = false }
        try await validateSend(owner)
        var frozen: Attempt?
        if let previous = uncertainAttempt {
            guard previous.ownership == owner else { throw DiaryError.wrongOwner }
            let prior = try await dependencies.reconcile(previous.payload.submissionID, previous.payload.manifest, previous.ownership)
            try await validateSend(owner)
            switch prior {
            case .conflictingPayload: throw Failure.conflictingPayload
            case .accepted(let result):
                if snapshot == previous.snapshot {
                    try await dependencies.refresh(owner); try await validateSend(owner)
                    accepted(previous, result: result); return result
                }
                uncertainAttempt = nil
                if submissionID == previous.payload.submissionID { submissionID = UUID() }
            case .absent:
                if snapshot == previous.snapshot { frozen = previous }
                else { uncertainAttempt = nil; if submissionID == previous.payload.submissionID { submissionID = UUID() } }
            }
        }
        let attempt: Attempt
        if let frozen { attempt = frozen }
        else {
            let input = snapshot
            let preparation = try await dependencies.prepare(Date(), owner)
            try await validateSend(owner)
            guard preparation.ownership == owner else { throw DiaryError.wrongOwner }
            let payload = try CoachSubmissionPayload(submissionID: input.submissionID, text: input.text, attachments: input.attachments, context: preparation.context)
            attempt = Attempt(ownership: owner, payload: payload, snapshot: input)
        }
        uncertainAttempt = attempt
        let result = try await dependencies.capture(attempt.payload, attempt.ownership)
        try await validateSend(owner)
        try await dependencies.refresh(owner)
        try await validateSend(owner)
        accepted(attempt, result: result)
        return result
    }
    nonisolated static func normalize(_ data: Data, source: PhotoSource) async throws -> Data {
        let work = Task.detached(priority: .userInitiated) { try PhotoImport.normalize(data) }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
}
