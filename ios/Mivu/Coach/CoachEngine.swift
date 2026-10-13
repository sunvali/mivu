import Foundation

struct CoachEngine: Sendable {
    let store: DiaryStore
    let infer: @Sendable ([CoachInferenceInput], Data) async throws -> CoachInferenceResult
    let prepareImages: @Sendable ([Data]) async throws -> [Data]
    let lookup: @Sendable (String) async throws -> [FoodEvidenceRecord]
    init(store: DiaryStore, infer: @escaping @Sendable ([CoachInferenceInput], Data) async throws -> CoachInferenceResult, lookup: @escaping @Sendable (String) async throws -> [FoodEvidenceRecord] = { _ in throw FoodEvidenceClient.Failure.notConfigured }, prepareImages: @escaping @Sendable ([Data]) async throws -> [Data] = { $0 }) {
        self.store = store; self.infer = infer; self.lookup = lookup; self.prepareImages = prepareImages
    }
    func run(turnID: UUID, expectedProfileID: UUID) async throws -> CoachTurn {
        let epoch = try await store.selectionEpoch(expectedProfileID: expectedProfileID)
        let turn = try await store.coachTurn(turnID: turnID, expectedProfileID: expectedProfileID)
        if turn.state == .completed { return turn }
        try await store.failCoachTurn(turnID: turnID, state: .analyzing, epoch: epoch, expectedProfileID: expectedProfileID)
        do {
            let context = try await store.coachContext(turnID: turnID, expectedProfileID: expectedProfileID)
            let photos = try await store.coachPhotos(turnID: turnID, expectedProfileID: expectedProfileID)
            let images = try await prepareImages(photos.map(\.data))
            guard images.count == photos.count, images.count <= 30,
                  images.reduce(0, { $0 + $1.count }) <= 4_194_304 else { throw ResponsesClient.Failure.invalidInput }
            for image in images { _ = try CoachInferenceInput.imageMIME(image) }
            var input: [CoachInferenceInput] = [
                .message(role: .developer, text: "Contiguous user text chunks and image groups form one captured turn. Context omissions are explicit; omitted items are not empty intake. Use get_meal or manual review for missing detail. Use only mivu tools and real retrieved IDs/revisions. Persisted capture clock/timezone resolves relative dates. Ask when waking day is ambiguous. Never claim food saved without a successful receipt. Nutrition is uncertain unless actual lookup evidence selected; portion remains uncertain. Goals are explicit native settings; never change or prescribe them. Use get_progress for actual requested windows and historical weight/workout IDs. Use get_workout before editing a complete workout; preserve unseen sets. Group all foods for each turn/date into one log_food call. Group one weight and one workout create per turn/date; another workout session needs another turn. measured_at and performed_at are unconfirmed; persisted chat time is date-only. Never claim weight or workout saved without a receipt. Correct existing items rather than compensating entries. Context: " + (try coachJSON(context)))
            ] + capturedInput(text: turn.text, images: images)
            var knownMeals = context.meals
            var knownWorkouts: [WorkoutSession] = []
            var requestedProgress: [(String, Int)] = []
            var requestedWorkouts: [UUID] = []
            var evidence: [Int: FoodEvidenceRecord] = [:]
            let tools = try CoachTools.declarations()
            var callCount = 0
            for _ in 0..<8 {
                try Task.checkCancellation()
                try await store.validateSelection(epoch: epoch, expectedProfileID: expectedProfileID)
                let response = try await infer(input, tools)
                try Task.checkCancellation()
                try await store.validateSelection(epoch: epoch, expectedProfileID: expectedProfileID)
                callCount += response.calls.count
                guard callCount <= 16 else { throw CoachError.limitExceeded }
                if response.calls.isEmpty {
                    let stored = try await store.coachTurn(turnID: turnID, expectedProfileID: expectedProfileID)
                    var text: String
                    if !stored.receipts.isEmpty {
                        text = try await store.coachCommittedSummary(turnID: turnID, expectedProfileID: expectedProfileID)
                    } else {
                        // Read-only prose must not claim a food mutation the diary never acknowledged.
                        let lowered = response.text.lowercased()
                        let actions = ["saved", "logged", "recorded", "updated", "deleted", "closed", "added"]
                        let subjects = ["i ", "i've ", "i have ", "we ", "we've ", "we have "]
                        guard !subjects.contains(where: { subject in actions.contains { lowered.contains(subject + $0) } }) else { throw CoachError.ungroundedConfirmation }
                        guard !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CoachError.ungroundedConfirmation }
                        text = try await store.coachRecordedSummary(expectedProfileID: expectedProfileID)
                    }
                    if !requestedProgress.isEmpty || !requestedWorkouts.isEmpty {
                        var actual: [String] = []
                        for (date, days) in requestedProgress {
                            actual.append(try await store.coachProgressSummary(endingOn: date, days: days, finalizingTurnID: turnID, expectedProfileID: expectedProfileID))
                        }
                        for id in requestedWorkouts {
                            actual.append(try await store.coachWorkoutSummary(id: id, expectedProfileID: expectedProfileID))
                        }
                        text = ((stored.receipts.isEmpty ? [] : [text]) + actual).joined(separator: "\n")
                    }
                    try await store.finishCoachTurn(turnID: turnID, assistantText: text, epoch: epoch, expectedProfileID: expectedProfileID)
                    return try await store.coachTurn(turnID: turnID, expectedProfileID: expectedProfileID)
                }
                guard Set(response.calls.map(\.callID)).count == response.calls.count,
                      response.calls.allSatisfy({ !$0.callID.isEmpty && $0.callID.utf8.count <= 256 }) else { throw CoachError.invalidArguments }
                let currentTurn = try await store.coachTurn(turnID: turnID, expectedProfileID: expectedProfileID)
                let commands = try response.calls.map { try CoachTools.parse($0, meals: knownMeals, evidence: evidence, receipts: currentTurn.receipts, workouts: knownWorkouts) }
                let writes = commands.compactMap { command -> CoachWrite? in if case .write(let write) = command { return write }; return nil }
                guard Set(writes.map(\.target)).count == writes.count else { throw CoachError.invalidArguments }
                // Validate the whole batch before awaiting lookups or committing any food.
                try await store.validateCoachWrites(writes, turnID: turnID, epoch: epoch, expectedProfileID: expectedProfileID)
                var outputs: [String?] = Array(repeating: nil, count: commands.count)
                for (index, command) in commands.enumerated() {
                    switch command {
                    case .context:
                        outputs[index] = try coachJSON(await store.coachContext(turnID: turnID, expectedProfileID: expectedProfileID))
                    case .meal(let id):
                        let meal = try await store.coachMeal(id: id, expectedProfileID: expectedProfileID)
                        knownMeals.removeAll { $0.id == id }; knownMeals.append(meal)
                        outputs[index] = try coachJSON(meal)
                    case .progress(let date, let days):
                        outputs[index] = try coachJSON(await store.coachProgress(endingOn: date, days: days, expectedProfileID: expectedProfileID))
                        if !requestedProgress.contains(where: { $0.0 == date && $0.1 == days }) { requestedProgress.append((date, days)) }
                    case .workout(let id):
                        let workout = try await store.coachWorkout(id: id, expectedProfileID: expectedProfileID)
                        knownWorkouts.removeAll { $0.id == id }; knownWorkouts.append(workout)
                        outputs[index] = try coachJSON(workout)
                        if !requestedWorkouts.contains(id) { requestedWorkouts.append(id) }
                    case .lookup(let query):
                        do {
                            let records = try await lookup(query)
                            guard records.count <= 10 else { throw CoachError.invalidArguments }
                            for record in records { evidence[record.id] = record }
                            outputs[index] = try coachJSON(records)
                        } catch is CancellationError { throw CancellationError() }
                        catch { outputs[index] = "{\"available\":false,\"reason\":\"Nutrition lookup unavailable. Use clearly uncertain estimates.\"}" }
                    case .write: break
                    }
                }
                try Task.checkCancellation()
                let receipts = try await store.applyCoachWrites(writes, turnID: turnID, epoch: epoch, expectedProfileID: expectedProfileID)
                let updated = try await store.coachContext(turnID: turnID, expectedProfileID: expectedProfileID)
                for meal in updated.meals { knownMeals.removeAll { $0.id == meal.id }; knownMeals.append(meal) }
                var nextReceipt = 0
                for (index, command) in commands.enumerated() {
                    if case .write = command { outputs[index] = receipts[nextReceipt].resultJSON; nextReceipt += 1 }
                }
                input += response.outputItems.map { .priorOutput($0) }
                // Fixtures and transport use the same function-output boundary.
                for (index, call) in response.calls.enumerated() {
                    input.append(.functionOutput(callID: call.callID, output: outputs[index]!))
                }
                guard input.count <= 128 else { throw CoachError.limitExceeded }
            }
            throw CoachError.limitExceeded
        } catch {
            // A late account/profile response cannot even change the original turn's state.
            if (try? await store.validateSelection(epoch: epoch, expectedProfileID: expectedProfileID)) != nil {
                let state: CoachTurnState
                if error as? DiaryError == .ambiguousDay || error as? CoachError == .ungroundedConfirmation { state = .needsClarification }
                else if error as? CoachError == .connectionRequired || error as? ResponsesClient.Failure == .unauthorized ||
                    error as? ResponsesClient.Failure == .forbidden ||
                    error as? SessionError == .noActiveSession || error as? SessionError == .planPermissionMissing { state = .waitingForConnection }
                else if error as? ResponsesClient.Failure == .usageUnavailable { state = .needsRetry }
                else if ProbeRunner.isTransient(error) { state = .waitingForNetwork }
                else { state = .needsRetry }
                try? await store.failCoachTurn(turnID: turnID, state: state, needsDayChoice: error as? DiaryError == .ambiguousDay, epoch: epoch, expectedProfileID: expectedProfileID)
            }
            throw error
        }
    }
    private func capturedInput(text: String, images: [Data]) -> [CoachInferenceInput] {
        var texts: [String] = [], chunk = "", chunkBytes = 0
        for scalar in text.unicodeScalars {
            let piece = String(scalar), bytes = piece.utf8.count
            if chunkBytes + bytes > 60_000 { texts.append(chunk); chunk = ""; chunkBytes = 0 }
            chunk += piece; chunkBytes += bytes
        }
        if !chunk.isEmpty { texts.append(chunk) }
        let imageGroups = stride(from: 0, to: images.count, by: 8).map { Array(images[$0..<min($0 + 8, images.count)]) }
        return (0..<max(texts.count, imageGroups.count)).map { index in
            .message(role: .user, text: index < texts.count ? texts[index] : "", images: index < imageGroups.count ? imageGroups[index] : [])
        }
    }

}
