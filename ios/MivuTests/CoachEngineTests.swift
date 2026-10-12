import Foundation
import Testing
@testable import Mivu

private actor CoachFixture {
    var results: [CoachInferenceResult]
    var calls = 0
    init(_ results: [CoachInferenceResult]) { self.results = results }
    func infer(_ input: [CoachInferenceInput], _ tools: Data) throws -> CoachInferenceResult {
        calls += 1
        guard !results.isEmpty else { throw CoachError.limitExceeded }
        return results.removeFirst()
    }
}
private actor CoachSuspension {
    var continuation: CheckedContinuation<CoachInferenceResult, Never>?
    var started = false
    func infer() async -> CoachInferenceResult {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ result: CoachInferenceResult) { continuation?.resume(returning: result) }
}

private actor CoachInputFixture {
    var input: [CoachInferenceInput] = []
    func infer(_ inputs: [CoachInferenceInput], _ tools: Data) throws -> CoachInferenceResult {
        for item in inputs { _ = try item.object() }
        input = inputs
        return CoachInferenceResult(model: "fixture", text: "Nutrition remains uncertain.", calls: [], outputItems: [])
    }
}

@Suite @MainActor struct CoachEngineTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture() async throws -> (DiaryStore, DiaryProfile, CoachTurn, URL) {
        let root = URL.temporaryDirectory.appending(path: "CoachEngine-" + UUID().uuidString)
        let store = DiaryStore(directory: root); let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay(at: now)
        let turn = try await store.captureCoachTurn(text: "Two eggs, three bread slices and salad", photos: [], at: now, expectedProfileID: profile.id)
        return (store, profile, turn, root)
    }
    private func call(_ name: String, _ args: String, id: String = "call1") -> CoachToolCall {
        CoachToolCall(id: id, callID: id, name: name, namespace: "mivu", arguments: args)
    }
    private func result(_ calls: [CoachToolCall] = [], text: String = "") -> CoachInferenceResult {
        CoachInferenceResult(model: "fixture", text: text, calls: calls, outputItems: [])
    }
    private let logArgs = """
    {"target_local_date":"2027-01-15","items":[{"name":"Eggs","quantity":2,"unit":"egg","kcal":140,"carbs":1,"protein":12,"fat":10},{"name":"Bread","quantity":3,"unit":"slice","kcal":240,"carbs":45,"protein":9,"fat":3},{"name":"Salad","quantity":1,"unit":"bowl","kcal":40,"carbs":8,"protein":1,"fat":0}]}
    """
    @Test func ownerMealIsLoggedWithAppGeneratedSavedFacts() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let replies = CoachFixture([result([call("log_food", logArgs)]), result(text: "Saved 9999 calories")])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
        let completed = try await engine.run(turnID: turn.id, expectedProfileID: profile.id)
        let snapshot = try await store.snapshot()
        #expect(completed.state == .completed); #expect(completed.receipts.count == 1)
        #expect(snapshot.meals.first?.totals.kcal == 420)
        #expect(completed.assistantText?.contains("9999") == false)
        #expect(completed.assistantText?.contains("420") == true)
    }
    @Test func conflictingOrForeignBatchWritesNothing() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let replies = CoachFixture([result([call("log_food", logArgs), call("log_food", logArgs, id: "other")])])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
        await #expect(throws: CoachError.invalidArguments) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        #expect(try await store.snapshot().meals.isEmpty)
        #expect(try await store.coachTurn(turnID: turn.id, expectedProfileID: profile.id).receipts.isEmpty)
    }
    @Test func unsupportedVerifiedArgumentsFailBeforeWrite() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let arguments = logArgs.replacingOccurrences(of: "\"kcal\":140", with: "\"verified\":true,\"kcal\":140")
        let replies = CoachFixture([result([call("log_food", arguments)])])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
        await #expect(throws: CoachError.invalidArguments) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        #expect(try await store.snapshot().meals.isEmpty)
    }
    @Test func readOnlyInventedSaveClaimRequiresClarification() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let replies = CoachFixture([result(text: "I saved your meal, 9999 calories")])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
        await #expect(throws: CoachError.ungroundedConfirmation) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        let stored = try await store.coachTurn(turnID: turn.id, expectedProfileID: profile.id)
        #expect(stored.state == .needsClarification); #expect(stored.assistantText == nil)
    }
    @Test func profileSwitchAwayAndBackFencesSuspendedResult() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let suspension = CoachSuspension()
        let engine = CoachEngine(store: store, infer: { _,_ in await suspension.infer() })
        let task = Task { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        for _ in 0..<1000 { if await suspension.started { break }; await Task.yield() }
        try #require(await suspension.started)
        _ = try await store.createProfile(DiaryProfile(name: "Other synthetic")); _ = try await store.selectProfile(profile.id)
        await suspension.finish(result([call("log_food", logArgs)]))
        await #expect(throws: DiaryError.wrongOwner) { try await task.value }
        #expect(try await store.snapshot().meals.isEmpty)
    }
    @Test func retrievalFailureKeepsEstimatedFoodLoggable() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let replies = CoachFixture([result([call("lookup_nutrition", "{\"query\":\"Eggs\"}")]), result([call("log_food", logArgs, id: "food")]), result(text: "Done")])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
        _ = try await engine.run(turnID: turn.id, expectedProfileID: profile.id)
        let snapshot = try await store.snapshot()
        let items = try #require(snapshot.meals.first).items
        #expect(items.allSatisfy { $0.provenance == .estimate && $0.uncertain })
    }
    @Test func retryWithRegeneratedCallIDUsesStoredReceipt() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = CoachFixture([result([call("log_food", logArgs)])])
        let failed = CoachEngine(store: store, infer: { try await first.infer($0, $1) })
        await #expect(throws: CoachError.limitExceeded) { try await failed.run(turnID: turn.id, expectedProfileID: profile.id) }
        let before = try await store.snapshot(); #expect(before.meals.count == 1)
        #expect(before.coachTurns[0].state == .needsRetry)
        let retry = CoachFixture([result([call("log_food", logArgs, id: "regenerated")]), result(text: "Done")])
        let engine = CoachEngine(store: store, infer: { try await retry.infer($0, $1) })
        let done = try await engine.run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(done.receipts.count == 1); #expect(try await store.snapshot().meals == before.meals)
    }
    @Test func retrievedValuesReplaceModelGuessAndKeepPortionUncertain() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let record = FoodEvidenceRecord(id: 1, name: "Synthetic cocoa", brand: nil, per100Grams: NutritionValues(kcal: 500, carbs: 50), reference: "https://fdc.nal.usda.gov/food-details/1/nutrients", fetchedAt: now)
        let food = "{\"target_local_date\":\"2027-01-14\",\"items\":[{\"name\":\"Chocolate\",\"quantity\":30,\"unit\":\"g\",\"kcal\":9999,\"evidence_id\":1}]}"
        let replies = CoachFixture([result([call("lookup_nutrition", "{\"query\":\"Cocoa\"}")]), result([call("log_food", food, id: "food")]), result(text: "Done")])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) }, lookup: { _ in [record] })
        _ = try await engine.run(turnID: turn.id, expectedProfileID: profile.id)
        let snapshot = try await store.snapshot(); let item = try #require(snapshot.meals.first?.items.first)
        #expect(item.nutrition.kcal == 150); #expect(item.nutrition.protein == nil)
        #expect(item.provenance == .identifiedSource); #expect(item.uncertain)
        #expect(item.reference == record.reference)
    }
    @Test func inferenceLimitRetainsRawInputWithoutFood() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let replies = CoachFixture(Array(repeating: result([call("get_context", "{}")]), count: 9))
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
        await #expect(throws: CoachError.limitExceeded) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        #expect(await replies.calls == 8)
        #expect(try await store.coachTurn(turnID: turn.id, expectedProfileID: profile.id).text == turn.text)
        #expect(try await store.snapshot().meals.isEmpty)
    }

    @Test func foreignCorrectionInReturnedBatchDoesNotPartiallyLogFood() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let args = "{\"meal_id\":\"\(UUID().uuidString)\",\"item_id\":\"\(UUID().uuidString)\",\"expected_revision\":1,\"quantity\":0.5}"
        let replies = CoachFixture([result([call("log_food", logArgs), call("correct_item", args, id: "foreign")])])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
        await #expect(throws: CoachError.invalidArguments) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        #expect(try await store.snapshot().meals.isEmpty)
    }
    @Test func oversizedEvidenceIDFailsInsteadOfIntegerConversionTrap() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let args = "{\"target_local_date\":\"2027-01-14\",\"items\":[{\"name\":\"Food\",\"quantity\":30,\"unit\":\"g\",\"evidence_id\":9223372036854775808}]}"
        let replies = CoachFixture([result([call("log_food", args)])])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
        await #expect(throws: CoachError.invalidArguments) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        #expect(try await store.snapshot().meals.isEmpty)
    }

    @Test func currentUnicodeCaptureIsSentCompletelyInTransportSafeChunks() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let raw = String(repeating: "😀", count: 20_000)
        let turn = try await store.captureCoachTurn(text: raw, photos: [], at: now, expectedProfileID: profile.id)
        let fixture = CoachInputFixture()
        let engine = CoachEngine(store: store, infer: { try await fixture.infer($0, $1) })
        let completed = try await engine.run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(completed.state == .completed)
        let messages = await fixture.input.compactMap { item -> String? in
            if case .message(role: .user, text: let text, images: _) = item { return text }; return nil
        }
        #expect(messages.joined() == raw)
        #expect(messages.allSatisfy { $0.utf8.count <= 60_000 })
        #expect(try await store.coachTurn(turnID: turn.id, expectedProfileID: profile.id).text == raw)
    }

    @Test func allLegacyPhotosUsePrivateInferenceCopiesWithoutChangingOriginals() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let photos = (0..<30).map { MealPhoto(data: Data([255,216,255,UInt8($0)])) }
        let turn = try await store.captureCoachTurn(text: "Many photos", photos: photos, at: now, expectedProfileID: profile.id)
        let fixture = CoachInputFixture()
        let engine = CoachEngine(store: store, infer: { try await fixture.infer($0, $1) }, prepareImages: { originals in originals.map { $0 + Data([9]) } })
        _ = try await engine.run(turnID: turn.id, expectedProfileID: profile.id)
        let groups = await fixture.input.compactMap { item -> [Data]? in
            if case .message(role: .user, text: _, images: let images) = item { return images }; return nil
        }
        #expect(groups.flatMap { $0 }.count == 30)
        #expect(groups.allSatisfy { $0.count <= 8 })
        #expect(groups.flatMap { $0 }.allSatisfy { $0.last == 9 })
        #expect(try await store.coachPhotos(turnID: turn.id, expectedProfileID: profile.id) == photos)
    }

    @Test(arguments: [ResponsesClient.Failure.unauthorized, ResponsesClient.Failure.forbidden,
                      ResponsesClient.Failure.usageUnavailable, SessionError.noActiveSession,
                      SessionError.planPermissionMissing] as [any Error])
    func permissionFailuresKeepCapturedTurnWaiting(_ error: any Error) async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let engine = CoachEngine(store: store, infer: { _, _ in throw error })
        await #expect(throws: (any Error).self) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        let captured = try await store.coachTurn(turnID: turn.id, expectedProfileID: profile.id)
        #expect(captured.state == .waitingForConnection); #expect(captured.text == turn.text)
        #expect(captured.assistantText == nil); #expect(try await store.snapshot().meals.isEmpty)
    }

    @Test(arguments: [false, true]) func noToolInventedTotalsUseOnlyRecordedIntake(hasFood: Bool) async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        if hasFood {
            let previous = try await store.captureCoachTurn(text: "Previous", photos: [], at: now, expectedProfileID: profile.id)
            _ = try await store.applyCoachFood(turnID: previous.id, targetLocalDate: "2027-01-14", items: [FoodItem(name: "Synthetic", nutrition: NutritionValues(kcal: 420), provenance: .estimate)], expectedProfileID: profile.id)
        }
        let question = try await store.captureCoachTurn(text: "How many calories did I eat today?", photos: [], at: now, expectedProfileID: profile.id)
        let replies = CoachFixture([result(text: "About 1,800 kcal today. Yesterday was 2,100 kcal.")])
        let completed = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: question.id, expectedProfileID: profile.id)
        #expect(completed.assistantText == (try await store.coachRecordedSummary(expectedProfileID: profile.id)))
        #expect(completed.receipts.isEmpty)
    }
    @Test func unsolicitedModelTimestampCannotEstablishExactMealTime() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await store.captureCoachTurn(text: "I had chocolate yesterday", photos: [], at: now, expectedProfileID: profile.id)
        let args = "{\"target_local_date\":\"2027-01-14\",\"eaten_at\":\"2027-01-14T12:34:00Z\",\"items\":[{\"name\":\"Chocolate\",\"quantity\":1,\"unit\":\"piece\",\"kcal\":50}]}"
        let replies = CoachFixture([result([call("log_food", args)]), result(text: "Saved")])
        _ = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(try await store.snapshot().meals.last?.timePrecision == .dateOnly)
    }
    @Test func groundedReadonlyHistoryUsesSavedFactsWithoutNewReceipt() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let previous = try await store.captureCoachTurn(text: "Previous", photos: [], at: now, expectedProfileID: profile.id)
        _ = try await store.applyCoachFood(turnID: previous.id, targetLocalDate: "2027-01-14", items: [FoodItem(name: "Synthetic", nutrition: NutritionValues(kcal: 420), provenance: .estimate)], expectedProfileID: profile.id)
        let question = try await store.captureCoachTurn(text: "What did I log yesterday?", photos: [], at: now, expectedProfileID: profile.id)
        let replies = CoachFixture([result(text: "You logged 420 kcal yesterday.")])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
        let completed = try await engine.run(turnID: question.id, expectedProfileID: profile.id)
        #expect(completed.state == .completed); #expect(completed.receipts.isEmpty)
        #expect(completed.assistantText?.contains("420") == true)
        #expect(try await store.snapshot().meals.count == 1)
    }
    @Test(arguments: [URLError(.timedOut), ResponsesClient.Failure.http(status: 503)] as [any Error])
    func exhaustedTransientInferenceWaitsForNetwork(_ error: any Error) async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let engine = CoachEngine(store: store, infer: { _, _ in throw error })
        await #expect(throws: (any Error).self) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        #expect(try await store.coachTurn(turnID: turn.id, expectedProfileID: profile.id).state == .waitingForNetwork)
        #expect(try await store.snapshot().meals.isEmpty)
    }

}
