import Foundation
import SQLite3
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
    @Test func toolSchemasRequireDeclaredPropertiesAndKeepOriginalOptionalsNullable() throws {
        let declarations = try #require(JSONSerialization.jsonObject(with: CoachTools.declarations()) as? [String: Any])
        let tools = try #require(declarations["tools"] as? [[String: Any]])
        func checkObject(_ schema: [String: Any]) throws {
            if schema["type"] as? String == "object" {
                let properties = try #require(schema["properties"] as? [String: [String: Any]])
                let required = try #require(schema["required"] as? [String])
                #expect(Set(required) == Set(properties.keys))
                #expect(schema["additionalProperties"] as? Bool == false)
                for child in properties.values { try checkObject(child) }
            }
            if let item = schema["items"] as? [String: Any] { try checkObject(item) }
        }
        for tool in tools {
            #expect(tool["strict"] as? Bool == true)
            try checkObject(try #require(tool["parameters"] as? [String: Any]))
        }
        let expected: [String: [String]] = ["log_food": ["eaten_at"], "log_weight": ["weight_id", "expected_revision", "measured_at"], "log_workout": ["performed_at", "estimated_burn_kcal", "burn_source"]]
        for (name, fields) in expected {
            let tool = try #require(tools.first { $0["name"] as? String == name })
            let parameters = try #require(tool["parameters"] as? [String: Any])
            let properties = try #require(parameters["properties"] as? [String: [String: Any]])
            for field in fields { #expect((properties[field]?["type"] as? [String])?.contains("null") == true) }
        }
    }

    @Test func nullOptionalMealWeightAndWorkoutFieldsCommitWithoutInventingExactTimes() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let food = #"{"target_local_date":"2027-01-15","eaten_at":null,"items":[{"name":"Synthetic eggs","quantity":2,"unit":"egg","kcal":140,"carbs":1,"protein":12,"fat":10,"evidence_id":null}]}"#
        let weight = #"{"local_date":"2027-01-15","value":70,"unit":"kg","weight_id":null,"expected_revision":null,"measured_at":null}"#
        let workout = #"{"local_date":"2027-01-15","kind":"cardio","duration_minutes":30,"exercises":[],"performed_at":null,"estimated_burn_kcal":null,"burn_source":null}"#
        let replies = CoachFixture([result([call("log_food", food, id: "food"), call("log_weight", weight, id: "weight"), call("log_workout", workout, id: "workout")]), result(text: "Done")])
        let completed = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        let snapshot = try await store.snapshot()
        #expect(completed.state == .completed && completed.receipts.count == 3)
        #expect(snapshot.meals.count == 1 && snapshot.weights.count == 1 && snapshot.workouts.count == 1)
        #expect(snapshot.meals[0].timePrecision == .dateOnly)
        #expect(snapshot.weights[0].timePrecision == .dateOnly)
        #expect(snapshot.workouts[0].timePrecision == .dateOnly)
    }

    @Test(arguments: ["log_food", "log_weight", "log_workout"], ["2027-01-14T08:00:00.123Z", "2027-01-14"])
    func modelTimeSyntaxKeepsDateOnlyPrecisionAndRequestedDay(operation: String, timestamp: String) async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let arguments = timestampArguments(operation: operation, timestamp: timestamp)
        let replies = CoachFixture([result([call(operation, arguments)]), result(text: "Done")])
        _ = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        let snapshot = try await store.snapshot()
        switch operation {
        case "log_food":
            #expect(snapshot.meals.first?.timePrecision == .dateOnly)
            #expect(snapshot.days.first { $0.id == snapshot.meals.first?.dayID }?.localDate == "2027-01-15")
        case "log_weight":
            #expect(snapshot.weights.first?.timePrecision == .dateOnly)
            #expect(snapshot.days.first { $0.id == snapshot.weights.first?.dayID }?.localDate == "2027-01-15")
        default:
            #expect(snapshot.workouts.first?.timePrecision == .dateOnly)
            #expect(snapshot.days.first { $0.id == snapshot.workouts.first?.dayID }?.localDate == "2027-01-15")
        }
    }

    @Test(arguments: ["log_food", "log_weight", "log_workout"], ["", "not-a-timestamp", "2027-02-30"])
    func presentMalformedOptionalTimestampsStillReject(operation: String, timestamp: String) throws {
        #expect(throws: CoachError.invalidArguments) {
            try CoachTools.parse(call(operation, timestampArguments(operation: operation, timestamp: timestamp)), meals: [], evidence: [:], receipts: [])
        }
    }

    @Test func correctionIDStillRequiresNonNullRevision() throws {
        let id = UUID().uuidString
        let args = "{\"local_date\":\"2027-01-15\",\"value\":70,\"unit\":\"kg\",\"weight_id\":\"\(id)\",\"expected_revision\":null,\"measured_at\":null}"
        #expect(throws: CoachError.invalidArguments) { try CoachTools.parse(call("log_weight", args), meals: [], evidence: [:], receipts: []) }
    }

    private func timestampArguments(operation: String, timestamp: String) -> String {
        switch operation {
        case "log_food": "{\"target_local_date\":\"2027-01-15\",\"eaten_at\":\"\(timestamp)\",\"items\":[{\"name\":\"Synthetic eggs\",\"quantity\":2,\"unit\":\"egg\",\"kcal\":140}]}"
        case "log_weight": "{\"local_date\":\"2027-01-15\",\"value\":70,\"unit\":\"kg\",\"measured_at\":\"\(timestamp)\"}"
        default: "{\"local_date\":\"2027-01-15\",\"kind\":\"cardio\",\"duration_minutes\":30,\"exercises\":[],\"performed_at\":\"\(timestamp)\"}"
        }
    }

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture() async throws -> (DiaryStore, DiaryProfile, CoachTurn, URL) {
        let root = URL.temporaryDirectory.appending(path: "CoachEngine-" + UUID().uuidString)
        let clock = now
        let store = DiaryStore(directory: root, currentTime: { clock }); let profile = DiaryProfile(name: "Synthetic")
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
    @Test(arguments: [false, true]) func profileSwitchAwayAndBackFencesSuspendedResult(progress: Bool) async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let suspension = CoachSuspension()
        let engine = CoachEngine(store: store, infer: { _,_ in await suspension.infer() })
        let task = Task { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        for _ in 0..<1000 { if await suspension.started { break }; await Task.yield() }
        try #require(await suspension.started)
        _ = try await store.createProfile(DiaryProfile(name: "Other synthetic")); _ = try await store.selectProfile(profile.id)
        await suspension.finish(result([progress ? call("log_weight", "{\"local_date\":\"2027-01-15\",\"value\":70,\"unit\":\"kg\"}") : call("log_food", logArgs)]))
        await #expect(throws: DiaryError.wrongOwner) { try await task.value }
        #expect(try await store.snapshot().meals.isEmpty)
        #expect(try await store.snapshot().weights.isEmpty)
        #expect(try await store.snapshot().coachTurns[0].receipts.isEmpty)
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
                      SessionError.noActiveSession,
                      SessionError.planPermissionMissing] as [any Error])
    func permissionFailuresKeepCapturedTurnWaiting(_ error: any Error) async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let engine = CoachEngine(store: store, infer: { _, _ in throw error })
        await #expect(throws: (any Error).self) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        let captured = try await store.coachTurn(turnID: turn.id, expectedProfileID: profile.id)
        #expect(captured.state == .waitingForConnection); #expect(captured.text == turn.text)
        #expect(captured.assistantText == nil); #expect(try await store.snapshot().meals.isEmpty)
    }

    @Test func exhaustedUsageCheckKeepsCapturedTurnRetryableWithoutReauthorization() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let engine = CoachEngine(store: store, infer: { _, _ in throw ResponsesClient.Failure.usageUnavailable })
        await #expect(throws: ResponsesClient.Failure.usageUnavailable) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        let captured = try await store.coachTurn(turnID: turn.id, expectedProfileID: profile.id)
        #expect(captured.state == .needsRetry)
        #expect(captured.text == turn.text)
        #expect(captured.assistantText == nil)
        #expect(try await store.snapshot().meals.isEmpty)
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

    @Test func conversationalWeightAndWorkoutReturnActualReceipts() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let replies = CoachFixture([
            result([call("log_weight", "{\"local_date\":\"2027-01-15\",\"value\":70,\"unit\":\"kg\"}"),
                    call("log_workout", "{\"local_date\":\"2027-01-14\",\"kind\":\"cardio\",\"duration_minutes\":45,\"exercises\":[]}", id: "cardio")]),
            result(text: "Saved 9999 kg")])
        let completed = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        let snapshot = try await store.snapshot()
        #expect(snapshot.weights.first?.value == 70)
        #expect(snapshot.workouts.first?.durationMinutes == 45)
        #expect(completed.receipts.count == 2)
        #expect(completed.assistantText?.contains("70 kg") == true)
        #expect(completed.assistantText?.contains("9999") == false)
    }
    @Test func progressAnswerUsesRequestedActualBudget() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await store.setGoals(GoalRecord(effectiveLocalDate: "2027-01-15", timeZoneID: profile.timeZoneID, targets: NutritionValues(kcal: 2000), exerciseCreditEnabled: false), expectedRevision: nil, expectedProfileID: profile.id)
        _ = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-15", items: [FoodItem(name: "Synthetic meal", nutrition: NutritionValues(kcal: 500), provenance: .estimate, reference: "Fixture")], expectedProfileID: profile.id)
        let query = try await store.captureCoachTurn(text: "What is my remaining budget?", photos: [], at: now, expectedProfileID: profile.id)
        let replies = CoachFixture([result([call("get_progress", "{\"ending_on\":\"2027-01-15\",\"days\":1}")]), result(text: "9999 remaining")])
        let completed = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: query.id, expectedProfileID: profile.id)
        #expect(completed.assistantText?.contains("1500") == true)
        #expect(completed.assistantText?.contains("9999") == false)
    }

    @Test func regeneratedProgressCallsReplayStoredReceipts() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let args = "{\"local_date\":\"2027-01-15\",\"value\":70,\"unit\":\"kg\",\"measured_at\":\"2027-01-15T08:00:00Z\"}"
        let first = CoachFixture([result([call("log_weight", args)])])
        await #expect(throws: CoachError.limitExceeded) { try await CoachEngine(store: store, infer: { try await first.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id) }
        let before = try await store.snapshot()
        let retry = CoachFixture([result([call("log_weight", args, id: "regenerated")]), result(text: "Done")])
        let completed = try await CoachEngine(store: store, infer: { try await retry.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(completed.receipts == before.coachTurns[0].receipts)
        #expect(try await store.snapshot().weights == before.weights)
        #expect(before.weights[0].timePrecision == .dateOnly)
    }
    @Test(arguments: [
        "{\"local_date\":\"2027-02-30\",\"value\":70,\"unit\":\"kg\"}",
        "{\"local_date\":\"2027-01-15\",\"value\":true,\"unit\":\"kg\"}",
        "{\"local_date\":\"2027-01-15\",\"value\":70,\"unit\":\"kg\",\"profile_id\":\"foreign\"}",
        "{\"local_date\":\"2027-01-15\",\"value\":-70,\"unit\":\"kg\"}",
        "{\"local_date\":\"2027-01-15\",\"value\":70,\"unit\":\"stone\"}"
    ]) func invalidProgressArgumentsNeverCommit(args: String) async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let replies = CoachFixture([result([call("log_weight", args)])])
        await #expect(throws: CoachError.invalidArguments) { try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id) }
        #expect(try await store.snapshot().weights.isEmpty)
        #expect(try await store.snapshot().coachTurns[0].assistantText == nil)
        #expect(try await store.snapshot().coachTurns[0].receipts.isEmpty)
    }
    @Test func workoutEditRequiresCompleteRetrievedRecord() throws {
        let id = UUID()
        let arguments = "{\"workout_id\":\"\(id)\",\"expected_revision\":1,\"kind\":\"strength\",\"duration_minutes\":30,\"exercises\":[]}"
        #expect(throws: CoachError.invalidArguments) { try CoachTools.parse(call("edit_workout", arguments), meals: [], evidence: [:], receipts: []) }
    }

    @Test func requestedProgressRereadsFactsAfterSuspendedInference() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let goal = try await store.setGoals(GoalRecord(effectiveLocalDate: "2027-01-15", timeZoneID: profile.timeZoneID, targets: NutritionValues(kcal: 2000), exerciseCreditEnabled: false), expectedRevision: nil, expectedProfileID: profile.id)
        _ = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-15", items: [FoodItem(name: "Synthetic", nutrition: NutritionValues(kcal: 500), provenance: .estimate)], expectedProfileID: profile.id)
        let query = try await store.captureCoachTurn(text: "Current progress", photos: [], at: now, expectedProfileID: profile.id)
        let replies = CoachFixture([result([call("get_progress", "{\"ending_on\":\"2027-01-15\",\"days\":1}")])]), suspended = CoachSuspension()
        let engine = CoachEngine(store: store, infer: { input, tools in
            if await replies.calls == 1 { return await suspended.infer() }
            return try await replies.infer(input, tools)
        })
        let task = Task { try await engine.run(turnID: query.id, expectedProfileID: profile.id) }
        for _ in 0..<1000 { if await suspended.started { break }; await Task.yield() }
        try #require(await suspended.started)
        var revised = goal; revised.targets.kcal = 1800
        _ = try await store.setGoals(revised, expectedRevision: goal.revision, expectedProfileID: profile.id)
        await suspended.finish(result(text: "1500 remaining"))
        let completed = try await task.value
        #expect(completed.assistantText?.contains("1300 kcal") == true)
        #expect(completed.assistantText?.contains("1500") == false)
    }
    @Test func retrievedHistoricalWorkoutEditsCompleteSetsAndReturnsActualRecord() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let draft = WorkoutDraft(kind: .strength, durationMinutes: 30, exercises: [WorkoutExercise(name: "Squat", sets: [WorkoutSet(repetitions: 8, loadKg: 40)])], estimatedBurnKcal: nil, burnSource: nil)
        let original = try await store.createWorkout(localDate: "2026-12-01", draft: draft, performedAt: nil, expectedProfileID: profile.id)
        let get = "{\"workout_id\":\"\(original.id)\"}"
        let edit = "{\"workout_id\":\"\(original.id)\",\"expected_revision\":1,\"kind\":\"strength\",\"duration_minutes\":45,\"exercises\":[{\"name\":\"Squat\",\"sets\":[{\"repetitions\":8,\"load_kg\":40}]}]}"
        let replies = CoachFixture([result([call("get_progress", "{\"ending_on\":\"2026-12-01\",\"days\":1}"), call("get_workout", get, id: "retrieve")]), result([call("edit_workout", edit, id: "edit")]), result(text: "Saved 9999 minutes")])
        let completed = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        let receipt = try #require(completed.receipts.first)
        let returned = try JSONDecoder().decode(WorkoutSession.self, from: Data(receipt.resultJSON.utf8))
        #expect(returned.id == original.id); #expect(returned.revision == 2)
        #expect(returned.durationMinutes == 45); #expect(returned.exercises == original.exercises)
        #expect(returned.performedAt == original.performedAt); #expect(returned.dayID == original.dayID)
        #expect(completed.assistantText?.contains("9999") == false)
        #expect(completed.assistantText?.contains("8 reps at 40 kg") == true)
    }
    @Test func failedProgressCommitNeverProducesSavedAssistantText() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let args = "{\"local_date\":\"2027-01-15\",\"value\":70,\"unit\":\"kg\"}"
        let output = result([call("log_weight", args)])
        let file = root.appendingPathComponent(profile.id.uuidString + ".sqlite").appendingPathComponent("diary.sqlite")
        let engine = CoachEngine(store: store, infer: { _, _ in
            var db: OpaquePointer?
            guard sqlite3_open(file.path, &db) == SQLITE_OK else { throw DiaryError.persistenceFailed }
            defer { sqlite3_close(db) }
            guard sqlite3_exec(db, "CREATE TRIGGER reject_coach_progress BEFORE UPDATE ON meta BEGIN SELECT RAISE(ABORT, 'synthetic'); END", nil, nil, nil) == SQLITE_OK else { throw DiaryError.persistenceFailed }
            return output
        })
        await #expect(throws: DiaryError.persistenceFailed) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        let snapshot = try await store.snapshot()
        #expect(snapshot.weights.isEmpty); #expect(snapshot.coachTurns[0].receipts.isEmpty)
        #expect(snapshot.coachTurns[0].assistantText == nil)
        let reloaded = try await DiaryStore(directory: root).selectProfile(profile.id)
        #expect(reloaded.weights.isEmpty); #expect(reloaded.coachTurns[0].assistantText == nil)
    }

    @Test(arguments: [false, true]) func finishedProgressQuestionDoesNotCountItselfAsPending(otherCapture: Bool) async throws {
        let (store, profile, existing, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await store.completeCoachTurn(turnID: existing.id, assistantText: "Synthetic previous turn", expectedProfileID: profile.id)
        let day = try await store.snapshot().days[0]
        try await store.setCompleteness(dayID: day.id, .complete)
        if otherCapture { _ = try await store.captureCoachTurn(text: "Unresolved synthetic food", photos: [], at: now, expectedProfileID: profile.id) }
        let question = try await store.captureCoachTurn(text: "What is my daily progress?", photos: [], at: now, expectedProfileID: profile.id)
        let replies = CoachFixture([result([call("get_progress", "{\"ending_on\":\"2027-01-15\",\"days\":1}")]), result(text: "Read complete")])
        let finished = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: question.id, expectedProfileID: profile.id)
        let report = try await store.coachProgress(endingOn: day.localDate, days: 1, expectedProfileID: profile.id)
        #expect(finished.state == .completed)
        #expect(report.daily.hasPending == otherCapture)
        #expect(report.daily.foodTotals?.kcal == (otherCapture ? nil : 0))
        #expect(finished.assistantText?.contains(otherCapture ? "calories unknown" : "Recorded food: 0 kcal") == true)
        #expect(finished.assistantText?.contains(otherCapture ? "pending: true" : "complete; pending: false") == true)
    }

    @Test func combinedReadOnlySettingsPreserveWeightAndWorkoutFacts() async throws {
        let (store, profile, existing, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await store.completeCoachTurn(turnID: existing.id, assistantText: "Synthetic previous turn", expectedProfileID: profile.id)
        var preferences = profile
        preferences.preferences = "Quick vegetarian meals"
        try await store.updateProfile(preferences, expectedProfileID: profile.id)
        _ = try await store.setGoals(GoalRecord(effectiveLocalDate: "2027-01-15", timeZoneID: profile.timeZoneID,
            targets: NutritionValues(kcal: 2000, carbs: 200, protein: 100, fat: 70), goalWeightKg: 68,
            exerciseCreditEnabled: false), expectedRevision: nil, expectedProfileID: profile.id)
        _ = try await store.recordWeight(value: 70, at: now, expectedProfileID: profile.id)
        let workout = try await store.createWorkout(localDate: "2027-01-15",
            draft: WorkoutDraft(kind: .cardio, durationMinutes: 30, exercises: [], estimatedBurnKcal: 120,
                burnSource: .userEstimate), performedAt: nil, expectedProfileID: profile.id)
        let question = try await store.captureCoachTurn(text: "Show saved goals, preferences, weight and workouts. Read only.",
            photos: [], at: now, expectedProfileID: profile.id)
        let before = try await store.snapshot()
        let replies = CoachFixture([result([
            call("get_progress", "{\"ending_on\":\"2027-01-15\",\"days\":1}", id: "progress"),
            call("get_workout", "{\"workout_id\":\"\(workout.id)\"}", id: "workout"),
            call("get_goals", "{\"local_date\":\"2027-01-15\"}", id: "goals"),
            call("get_preferences", "{}", id: "preferences")
        ]), result(text: "Read complete")])
        let finished = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
            .run(turnID: question.id, expectedProfileID: profile.id)
        let persisted = try await DiaryStore(directory: root).selectProfile(profile.id)
        let text = try #require(persisted.coachTurns.first { $0.id == question.id }?.assistantText)
        #expect(finished.state == .completed && finished.receipts.isEmpty)
        #expect(text == finished.assistantText)
        #expect(text.contains("Calories: 2000 kcal"))
        #expect(text.contains("Quick vegetarian meals"))
        #expect(text.contains("Weight average: 70 kg"))
        #expect(text.contains("recorded cardio, 30 minutes"))
        #expect(text.contains("Estimated burn: 120 kcal"))
        #expect(persisted.profile == before.profile)
        #expect(persisted.days == before.days && persisted.meals == before.meals)
        #expect(persisted.goals == before.goals && persisted.weights == before.weights)
        #expect(persisted.workouts == before.workouts)
        #expect(persisted.coachTurns.first { $0.id == question.id }?.receipts.isEmpty == true)
    }

    @Test(arguments: [false, true], [false, true]) func correctionRetryCanonicalizesDateAndIDForms(idFirst: Bool, currentRevision: Bool) async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let weight = try await store.recordWeight(value: 70, at: now)
        func arguments(byID: Bool, revision: Int) -> String {
            "{\"local_date\":\"2027-01-15\",\"value\":71,\"unit\":\"kg\",\"expected_revision\":\(revision)" + (byID ? ",\"weight_id\":\"\(weight.id)\"}" : "}")
        }
        let first = CoachFixture([result([call("log_weight", arguments(byID: idFirst, revision: 1))])])
        await #expect(throws: CoachError.limitExceeded) { try await CoachEngine(store: store, infer: { try await first.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id) }
        let before = try await store.snapshot(), receipt = try #require(before.coachTurns[0].receipts.first)
        #expect(receipt.operationKey == "\(turn.id)/correct_weight/\(weight.id)")
        let retry = CoachFixture([result([call("log_weight", arguments(byID: !idFirst, revision: currentRevision ? 2 : 1), id: "regenerated")]), result(text: "Done")])
        let finished = try await CoachEngine(store: store, infer: { try await retry.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(finished.receipts == [receipt]); #expect(try await store.snapshot().weights == before.weights)
        #expect(try await store.snapshot().weights[0].revision == 2)
    }
    @Test func newerWorkoutReferenceCannotAuthorizeReplacementFromOlderFullRecord() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let squat = WorkoutExercise(name: "Squat", sets: [WorkoutSet(repetitions: 8, loadKg: 40)])
        let deadlift = WorkoutExercise(name: "Deadlift", sets: [WorkoutSet(repetitions: 5, loadKg: 60)])
        let original = try await store.createWorkout(localDate: "2027-01-14", draft: WorkoutDraft(kind: .strength, durationMinutes: 30, exercises: [squat], estimatedBurnKcal: nil, burnSource: nil), performedAt: nil, expectedProfileID: profile.id)
        let oldFull = try await store.coachWorkout(id: original.id, expectedProfileID: profile.id)
        var nativeEdit = original; nativeEdit.exercises.append(deadlift)
        let revised = try await store.updateWorkout(nativeEdit, expectedRevision: 1, expectedProfileID: profile.id)
        let reference = try await store.coachProgress(endingOn: "2027-01-15", days: 7, expectedProfileID: profile.id).workouts.first { $0.id == original.id }
        #expect(reference?.revision == 2)
        let staleArguments = "{\"workout_id\":\"\(original.id)\",\"expected_revision\":2,\"kind\":\"strength\",\"duration_minutes\":45,\"exercises\":[{\"name\":\"Squat\",\"sets\":[{\"repetitions\":8,\"load_kg\":40}]}]}"
        #expect(throws: CoachError.invalidArguments) { try CoachTools.parse(call("edit_workout", staleArguments), meals: [], evidence: [:], receipts: [], workouts: [oldFull]) }
        #expect(try await store.snapshot().workouts == [revised])
        let fresh = try await store.coachWorkout(id: original.id, expectedProfileID: profile.id)
        let arguments = staleArguments.replacingOccurrences(of: "\"exercises\":[{\"name\":\"Squat\",\"sets\":[{\"repetitions\":8,\"load_kg\":40}]}]", with: "\"exercises\":[{\"name\":\"Squat\",\"sets\":[{\"repetitions\":8,\"load_kg\":40}]},{\"name\":\"Deadlift\",\"sets\":[{\"repetitions\":5,\"load_kg\":60}]}]")
        let parsed = try CoachTools.parse(call("edit_workout", arguments), meals: [], evidence: [:], receipts: [], workouts: [fresh])
        guard case .write(let write) = parsed else { throw CoachError.invalidArguments }
        let receipts = try await store.applyCoachWrites([write], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        #expect(try await store.snapshot().workouts[0].exercises == [squat, deadlift])
        #expect(receipts[0].workoutID == original.id)
    }

}
