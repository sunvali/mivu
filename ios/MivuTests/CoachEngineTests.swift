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
        #expect(tools.count <= 40)
        #expect(tools.contains { $0["name"] as? String == "ask_clarification" })
        let clarification = try #require(tools.first { $0["name"] as? String == "ask_clarification" })
        let clarificationParameters = try #require(clarification["parameters"] as? [String: Any])
        let clarificationProperties = try #require(clarificationParameters["properties"] as? [String: [String: Any]])
        #expect(clarificationProperties["kind"]?["enum"] as? [String] == ["portion", "food", "day", "meal", "workout", "confirm"])
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
        let snapshot = try await store.snapshotForExport()
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
        let snapshot = try await store.snapshotForExport()
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
        let turn = try await capturedTurn(store, text: "Two eggs, three bread slices and salad", photos: [], at: now, expectedProfileID: profile.id)
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
        let snapshot = try await store.snapshotForExport()
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
        #expect(try await store.snapshotForExport().meals.isEmpty)
        #expect(try await exportedTurn(store, turnID: turn.id, expectedProfileID: profile.id).receipts.isEmpty)
    }
    @Test func unsupportedVerifiedArgumentsFailBeforeWrite() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let arguments = logArgs.replacingOccurrences(of: "\"kcal\":140", with: "\"verified\":true,\"kcal\":140")
        let replies = CoachFixture([result([call("log_food", arguments)])])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
        await #expect(throws: CoachError.invalidArguments) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        #expect(try await store.snapshotForExport().meals.isEmpty)
    }
    @Test func readOnlyInventedSaveClaimRequiresClarification() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let replies = CoachFixture([result(text: "I saved your meal, 9999 calories")])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
        await #expect(throws: CoachError.ungroundedConfirmation) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        let stored = try await exportedTurn(store, turnID: turn.id, expectedProfileID: profile.id)
        #expect(stored.state == .needsClarification); #expect(stored.assistantText == nil)
    }

    @Test func explicitFoodClarificationPersistsAndFollowupLeavesEarlierReviewUnaccepted() async throws {
        let (store, profile, previous, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let reviewArgs = "{\"target_local_date\":\"2027-01-14\",\"review_first\":true,\"items\":[{\"name\":\"Synthetic yogurt\",\"quantity\":50,\"unit\":\"g\",\"kcal\":30}]}"
        let reviewReplies = CoachFixture([result([call("log_food", reviewArgs)]), result(text: "Review ready")])
        _ = try await CoachEngine(store: store, infer: { try await reviewReplies.infer($0, $1) }).run(turnID: previous.id, expectedProfileID: profile.id)
        let refusal = try await capturedTurn(store, text: "Do not accept that yogurt review", photos: [], at: now, expectedProfileID: profile.id)
        try await store.completeCoachTurn(turnID: refusal.id, assistantText: "The earlier yogurt remains in review.", expectedProfileID: profile.id)
        let turn = try await capturedTurn(store, text: "I ate another yogurt", photos: [], at: now, expectedProfileID: profile.id)
        let before = try await store.snapshotForExport()
        let question = "How much did you eat? Give grams, a serving size, or a container size."
        let clarification = CoachFixture([result([call("ask_clarification", "{\"kind\":\"portion\"}")], text: "I logged 9999 calories")])
        let finished = try await CoachEngine(store: store, infer: { try await clarification.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        let persisted = try await completeSelectedProfile(DiaryStore(directory: root), profile.id)
        #expect(finished.state == .completed && finished.receipts.isEmpty)
        #expect(finished.assistantText == question)
        #expect(persisted.coachTurns.first { $0.id == turn.id }?.assistantText == question)
        #expect(persisted.meals == before.meals && persisted.days == before.days)
        #expect(persisted.goals == before.goals && persisted.weights == before.weights && persisted.workouts == before.workouts)
        #expect(persisted.profile == before.profile)
        let followup = try await capturedTurn(store, text: "One 150 g container today", photos: [], at: now, expectedProfileID: profile.id)
        #expect(try await store.coachContext(turnID: followup.id, expectedProfileID: profile.id).recentTurns.contains { $0.id == turn.id && $0.assistantText == question })
        let foodArgs = "{\"target_local_date\":\"2027-01-15\",\"items\":[{\"name\":\"Synthetic yogurt\",\"quantity\":150,\"unit\":\"g\",\"kcal\":90}]}"
        let interrupted = CoachFixture([result([call("log_food", foodArgs)])])
        try await interruptAfterWrite(store, profile.id, followup.id) { try await CoachEngine(store: store, infer: { try await interrupted.infer($0, $1) }).run(turnID: followup.id, expectedProfileID: profile.id) }
        let committed = try await store.snapshotForExport()
        let retry = CoachFixture([result([call("log_food", foodArgs, id: "retry")]), result(text: "Saved")])
        let saved = try await CoachEngine(store: store, infer: { try await retry.infer($0, $1) }).run(turnID: followup.id, expectedProfileID: profile.id)
        let after = try await store.snapshotForExport()
        #expect(after.meals == committed.meals && after.meals.count == before.meals.count + 1)
        #expect(after.meals.first { $0.id == before.meals[0].id } == before.meals[0])
        #expect(before.meals[0].state == .awaitingReview)
        let newMeal = try #require(after.meals.first { $0.id != before.meals[0].id })
        #expect(newMeal.isSaved && newMeal.items[0].quantity == 150)
        #expect(newMeal.items[0].uncertain && newMeal.items[0].provenance == .estimate)
        #expect(saved.receipts.count == 1 && saved.receipts[0].mealID == newMeal.id)
    }

    @Test func committedHistoricalPortionReachesInferenceAndRepeatRetryPreservesReview() async throws {
        let (store, profile, original, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await store.applyCoachFood(turnID: original.id, targetLocalDate: "2027-01-10",
            items: [FoodItem(name: "Synthetic yogurt", quantity: 150, unit: "g", nutrition: NutritionValues(kcal: 90), provenance: .estimate)], expectedProfileID: profile.id)
        try await store.completeCoachTurn(turnID: original.id, assistantText: "Recorded synthetic yogurt", expectedProfileID: profile.id)
        let proposal = try await capturedTurn(store, text: "Review a synthetic yogurt", photos: [], at: now, expectedProfileID: profile.id)
        _ = try await store.applyCoachFood(turnID: proposal.id, targetLocalDate: "2027-01-14",
            items: [FoodItem(name: "Synthetic yogurt", quantity: 50, unit: "g", nutrition: NutritionValues(kcal: 30), provenance: .estimate)], reviewFirst: true, expectedProfileID: profile.id)
        try await store.completeCoachTurn(turnID: proposal.id, assistantText: "Review remains unaccepted", expectedProfileID: profile.id)
        let before = try await store.snapshotForExport()
        let turn = try await capturedTurn(store, text: "I ate another synthetic yogurt", photos: [], at: now, expectedProfileID: profile.id)
        let captured = CoachInputFixture()
        _ = try await CoachEngine(store: store, infer: { try await captured.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        let developer = try #require(await captured.input.compactMap { item -> String? in
            if case .message(role: .developer, text: let text, images: _) = item { return text }; return nil
        }.last)
        let contextJSON = try #require(developer.components(separatedBy: "Context: ").last)
        let context = try JSONDecoder().decode(CoachContext.self, from: Data(contextJSON.utf8))
        #expect(context.meals.contains { $0.state == .saved && $0.items.contains { $0.name == "Synthetic yogurt" && $0.quantity == 150 && $0.unit == "g" } })
        // Fixture tool selection checks persistence only; live inference must separately choose the historical portion.
        let intake = try await capturedTurn(store, text: "One more synthetic yogurt", photos: [], at: now, expectedProfileID: profile.id)
        let args = #"{"target_local_date":"2027-01-15","items":[{"name":"Synthetic yogurt","quantity":150,"unit":"g","kcal":90}]}"#
        let interrupted = CoachFixture([result([call("log_food", args)])])
        try await interruptAfterWrite(store, profile.id, intake.id) { try await CoachEngine(store: store, infer: { try await interrupted.infer($0, $1) }).run(turnID: intake.id, expectedProfileID: profile.id) }
        let committed = try await store.snapshotForExport()
        let retry = CoachFixture([result([call("log_food", args, id: "retry")]), result(text: "Done")])
        let finished = try await CoachEngine(store: store, infer: { try await retry.infer($0, $1) }).run(turnID: intake.id, expectedProfileID: profile.id)
        let persisted = try await completeSelectedProfile(DiaryStore(directory: root), profile.id)
        #expect(persisted.meals == committed.meals && persisted.meals.count == before.meals.count + 1)
        #expect(before.meals.allSatisfy { old in persisted.meals.contains(old) })
        let added = try #require(persisted.meals.first { meal in !before.meals.contains { $0.id == meal.id } })
        #expect(added.isSaved && added.items[0].quantity == 150 && added.items[0].unit == "g")
        #expect(added.items[0].uncertain && added.items[0].provenance == .estimate)
        #expect(finished.receipts.count == 1 && finished.receipts[0].mealID == added.id)
    }

    @Test func photoAndDescriptionShareCaptureAndCocktailComponentsStayUncertain() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let photo = MealPhoto(data: Data([255, 216, 255, 0]))
        let text = "Synthetic gin and tonic; estimate this visible glass. Mixer ratio is unknown."
        let turn = try await capturedTurn(store, text: text, photos: [photo], at: now, expectedProfileID: profile.id)
        let captured = CoachInputFixture()
        let args = #"{"target_local_date":"2027-01-15","items":[{"name":"Synthetic gin, typical cocktail estimate","quantity":1,"unit":"estimated serving","kcal":100},{"name":"Synthetic tonic, typical cocktail estimate","quantity":1,"unit":"estimated mixer serving","kcal":80}]}"#
        let replies = CoachFixture([result([call("log_food", args)]), result(text: "Verified ratio and 9999 calories")])
        let finished = try await CoachEngine(store: store, infer: { inputs, tools in
            _ = try await captured.infer(inputs, tools)
            return try await replies.infer(inputs, tools)
        }).run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(await captured.input.contains { item in
            if case .message(role: .user, text: let sentText, images: let images) = item { return sentText == text && images == [photo.data] }; return false
        })
        let persisted = try await completeSelectedProfile(DiaryStore(directory: root), profile.id)
        let meal = try #require(persisted.meals.first)
        #expect(meal.items.count == 2 && meal.isSaved)
        #expect(meal.items.allSatisfy { $0.uncertain && $0.provenance == .estimate })
        #expect(meal.totals.kcal == 180 && finished.receipts.count == 1)
        #expect(finished.assistantText?.contains("Verified ratio") == false)
        #expect(finished.assistantText?.contains("9999") == false)
        #expect(try await exportedCoachPhotos(store, turnID: turn.id, expectedProfileID: profile.id) == [photo])
    }

    @Test func clarificationCannotMixWithCurrentTurnWrites() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = try await store.snapshotForExport()
        let replies = CoachFixture([result([call("log_food", logArgs), call("ask_clarification", "{\"kind\":\"portion\"}", id: "question")])])
        await #expect(throws: CoachError.invalidArguments) {
            try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        }
        let after = try await store.snapshotForExport()
        #expect(after.meals == before.meals)
        #expect(after.coachTurns[0].receipts == before.coachTurns[0].receipts)
    }

    @Test(arguments: [
        #"{"question":"Saved the yogurt. What portion did you eat?"}"#,
        #"{"question":"The yogurt was logged. How much?"}"#,
        #"{"kind":"portion","question":"Saved 9999 calories."}"#,
        #"{"kind":"unknown"}"#, #"{"kind":""}"#, #"{"kind":null}"#, #"{}"#
    ]) func clarificationRejectsRawQuestionsAndInvalidKinds(_ arguments: String) throws {
        #expect(throws: CoachError.invalidArguments) {
            try CoachTools.parse(call("ask_clarification", arguments), meals: [], evidence: [:], receipts: [])
        }
    }

    @Test func clarificationKindsRenderOnlyNativeQuestions() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = try await store.snapshotForExport()
        for (kind, question) in [
            ("portion", "How much did you eat? Give grams, a serving size, or a container size."),
            ("food", "What food did you eat?"), ("day", "Which day should this be recorded on?"),
            ("meal", "Which meal do you mean?"), ("workout", "Which workout do you mean?")
        ] {
            let turn = try await capturedTurn(store, text: "Synthetic missing detail", photos: [], at: now, expectedProfileID: profile.id)
            let replies = CoachFixture([result([call("ask_clarification", "{\"kind\":\"\(kind)\"}")], text: "Saved 9999 calories")])
            let finished = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
            #expect(finished.state == .completed && finished.receipts.isEmpty)
            #expect(finished.assistantText == question)
        }
        #expect(try await store.snapshotForExport().meals == before.meals)
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
        #expect(try await store.snapshotForExport().meals.isEmpty)
        #expect(try await store.snapshotForExport().weights.isEmpty)
        #expect(try await store.snapshotForExport().coachTurns[0].receipts.isEmpty)
    }
    @Test func retrievalFailureKeepsEstimatedFoodLoggable() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let replies = CoachFixture([result([call("lookup_nutrition", "{\"query\":\"Eggs\"}")]), result([call("log_food", logArgs, id: "food")]), result(text: "Done")])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
        _ = try await engine.run(turnID: turn.id, expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport()
        let items = try #require(snapshot.meals.first).items
        #expect(items.allSatisfy { $0.provenance == .estimate && $0.uncertain })
    }
    @Test func retryWithRegeneratedCallIDUsesStoredReceipt() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = CoachFixture([result([call("log_food", logArgs)])])
        let failed = CoachEngine(store: store, infer: { try await first.infer($0, $1) })
        try await interruptAfterWrite(store, profile.id, turn.id) { try await failed.run(turnID: turn.id, expectedProfileID: profile.id) }
        let before = try await store.snapshotForExport(); #expect(before.meals.count == 1)
        #expect(before.coachTurns[0].state == .captured)
        let retry = CoachFixture([result([call("log_food", logArgs, id: "regenerated")]), result(text: "Done")])
        let engine = CoachEngine(store: store, infer: { try await retry.infer($0, $1) })
        let done = try await engine.run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(done.receipts.count == 1); #expect(try await store.snapshotForExport().meals == before.meals)
    }
    @Test func retrievedValuesReplaceModelGuessAndKeepPortionUncertain() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let record = FoodEvidenceRecord(id: 1, name: "Synthetic cocoa", brand: nil, per100Grams: NutritionValues(kcal: 500, carbs: 50), reference: "https://fdc.nal.usda.gov/food-details/1/nutrients", fetchedAt: now)
        let food = "{\"target_local_date\":\"2027-01-14\",\"items\":[{\"name\":\"Chocolate\",\"quantity\":30,\"unit\":\"g\",\"kcal\":9999,\"evidence_id\":1}]}"
        let replies = CoachFixture([result([call("lookup_nutrition", "{\"query\":\"Cocoa\"}")]), result([call("log_food", food, id: "food")]), result(text: "Done")])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) }, lookup: { _ in [record] })
        _ = try await engine.run(turnID: turn.id, expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport(); let item = try #require(snapshot.meals.first?.items.first)
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
        #expect(try await exportedTurn(store, turnID: turn.id, expectedProfileID: profile.id).text == turn.text)
        #expect(try await store.snapshotForExport().meals.isEmpty)
    }

    @Test func foreignCorrectionInReturnedBatchDoesNotPartiallyLogFood() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let args = "{\"meal_id\":\"\(UUID().uuidString)\",\"item_id\":\"\(UUID().uuidString)\",\"expected_revision\":1,\"quantity\":0.5}"
        let replies = CoachFixture([result([call("log_food", logArgs), call("correct_item", args, id: "foreign")])])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
        await #expect(throws: CoachError.invalidArguments) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        #expect(try await store.snapshotForExport().meals.isEmpty)
    }
    @Test func oversizedEvidenceIDFailsInsteadOfIntegerConversionTrap() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let args = "{\"target_local_date\":\"2027-01-14\",\"items\":[{\"name\":\"Food\",\"quantity\":30,\"unit\":\"g\",\"evidence_id\":9223372036854775808}]}"
        let replies = CoachFixture([result([call("log_food", args)])])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
        await #expect(throws: CoachError.invalidArguments) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        #expect(try await store.snapshotForExport().meals.isEmpty)
    }

    @Test func currentUnicodeCaptureIsSentCompletelyInTransportSafeChunks() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let raw = String(repeating: "😀", count: 20_000)
        let turn = try await capturedTurn(store, text: raw, photos: [], at: now, expectedProfileID: profile.id)
        let fixture = CoachInputFixture()
        let engine = CoachEngine(store: store, infer: { try await fixture.infer($0, $1) })
        let completed = try await engine.run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(completed.state == .completed)
        let messages = await fixture.input.suffix(from: await fixture.input.lastIndex { if case .message(.developer, _, _) = $0 { return true }; return false }!).compactMap { item -> String? in
            if case .message(role: .user, text: let text, images: _) = item { return text }; return nil
        }
        #expect(messages.joined() == raw)
        #expect(messages.allSatisfy { $0.utf8.count <= 60_000 })
        #expect(try await exportedTurn(store, turnID: turn.id, expectedProfileID: profile.id).text == raw)
    }

    @Test func allLegacyPhotosUsePrivateInferenceCopiesWithoutChangingOriginals() async throws {
        let root = URL.temporaryDirectory.appending(path: "CoachLegacyPhotos-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = DiaryProfile(name: "Synthetic")
        let photos = (0..<30).map { MealPhoto(data: Data([255,216,255,UInt8($0)])) }
        let turn = CoachTurn(capturedAt: now, text: "Many photos", photos: photos,
            captureTimeZoneID: profile.timeZoneID, photoIDs: photos.map(\.id))
        let directory = root.appendingPathComponent(profile.id.uuidString + ".sqlite")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("diary.sqlite")
        try DiaryDatabase(url: file, create: true).write(DiarySnapshot(profile: profile, coachTurns: [turn]),
            expected: nil, maximumBytes: ChatHistoryFixture.maximumBytes)
        #expect(try ChatHistoryFixture.strings(file, "PRAGMA user_version") == [["0"]])
        let clock = now
        let store = DiaryStore(directory: root, currentTime: { clock })
        _ = try await store.selectProfile(profile.id)
        #expect(try await store.coachWorkItem(turnID: turn.id, expectedProfileID: profile.id).photos.count == 30)
        let fixture = CoachInputFixture()
        let engine = CoachEngine(store: store, infer: { try await fixture.infer($0, $1) }, prepareImages: { originals in originals.map { $0 + Data([9]) } })
        _ = try await engine.run(turnID: turn.id, expectedProfileID: profile.id)
        let groups = await fixture.input.compactMap { item -> [Data]? in
            if case .message(role: .user, text: _, images: let images) = item { return images }; return nil
        }
        #expect(groups.flatMap { $0 }.count == 30)
        #expect(groups.allSatisfy { $0.count <= 8 })
        #expect(groups.flatMap { $0 }.allSatisfy { $0.last == 9 })
        #expect(try await exportedCoachPhotos(store, turnID: turn.id, expectedProfileID: profile.id) == photos)
    }

    @Test(arguments: [ResponsesClient.Failure.unauthorized, ResponsesClient.Failure.forbidden,
                      SessionError.noActiveSession,
                      SessionError.planPermissionMissing] as [any Error])
    func permissionFailuresKeepCapturedTurnWaiting(_ error: any Error) async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let engine = CoachEngine(store: store, infer: { _, _ in throw error })
        await #expect(throws: (any Error).self) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        let captured = try await exportedTurn(store, turnID: turn.id, expectedProfileID: profile.id)
        #expect(captured.state == .waitingForConnection); #expect(captured.text == turn.text)
        #expect(captured.assistantText == nil); #expect(try await store.snapshotForExport().meals.isEmpty)
    }

    @Test func exhaustedUsageCheckKeepsCapturedTurnRetryableWithoutReauthorization() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let engine = CoachEngine(store: store, infer: { _, _ in throw ResponsesClient.Failure.usageUnavailable })
        await #expect(throws: ResponsesClient.Failure.usageUnavailable) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        let captured = try await exportedTurn(store, turnID: turn.id, expectedProfileID: profile.id)
        #expect(captured.state == .needsRetry)
        #expect(captured.text == turn.text)
        #expect(captured.assistantText == nil)
        #expect(try await store.snapshotForExport().meals.isEmpty)
    }

    @Test(arguments: [false, true]) func noToolInventedTotalsUseOnlyRecordedIntake(hasFood: Bool) async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        if hasFood {
            let previous = try await capturedTurn(store, text: "Previous", photos: [], at: now, expectedProfileID: profile.id)
            _ = try await store.applyCoachFood(turnID: previous.id, targetLocalDate: "2027-01-14", items: [FoodItem(name: "Synthetic", nutrition: NutritionValues(kcal: 420), provenance: .estimate)], expectedProfileID: profile.id)
        }
        let question = try await capturedTurn(store, text: "How many calories did I eat today?", photos: [], at: now, expectedProfileID: profile.id)
        let replies = CoachFixture([result(text: "About 1,800 kcal today. Yesterday was 2,100 kcal.")])
        let completed = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: question.id, expectedProfileID: profile.id)
        #expect(completed.assistantText == "There's no food recorded for 2027-01-15 yet.")
        #expect(completed.receipts.isEmpty)
    }
    @Test func unsolicitedModelTimestampCannotEstablishExactMealTime() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await capturedTurn(store, text: "I had chocolate yesterday", photos: [], at: now, expectedProfileID: profile.id)
        let args = "{\"target_local_date\":\"2027-01-14\",\"eaten_at\":\"2027-01-14T12:34:00Z\",\"items\":[{\"name\":\"Chocolate\",\"quantity\":1,\"unit\":\"piece\",\"kcal\":50}]}"
        let replies = CoachFixture([result([call("log_food", args)]), result(text: "Saved")])
        _ = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(try await store.snapshotForExport().meals.last?.timePrecision == .dateOnly)
    }
    @Test func groundedReadonlyHistoryUsesSavedFactsWithoutNewReceipt() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let previous = try await capturedTurn(store, text: "Previous", photos: [], at: now, expectedProfileID: profile.id)
        _ = try await store.applyCoachFood(turnID: previous.id, targetLocalDate: "2027-01-14", items: [FoodItem(name: "Synthetic", nutrition: NutritionValues(kcal: 420), provenance: .estimate)], expectedProfileID: profile.id)
        let question = try await capturedTurn(store, text: "What did I log yesterday?", photos: [], at: now, expectedProfileID: profile.id)
        let replies = CoachFixture([result(text: "You logged 420 kcal yesterday.")])
        let engine = CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
        let completed = try await engine.run(turnID: question.id, expectedProfileID: profile.id)
        #expect(completed.state == .completed); #expect(completed.receipts.isEmpty)
        #expect(completed.assistantText?.contains("420") == true)
        #expect(try await store.snapshotForExport().meals.count == 1)
    }
    @Test(arguments: [URLError(.timedOut), ResponsesClient.Failure.http(status: 503)] as [any Error])
    func exhaustedTransientInferenceWaitsForNetwork(_ error: any Error) async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let engine = CoachEngine(store: store, infer: { _, _ in throw error })
        await #expect(throws: (any Error).self) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        #expect(try await exportedTurn(store, turnID: turn.id, expectedProfileID: profile.id).state == .waitingForNetwork)
        #expect(try await store.snapshotForExport().meals.isEmpty)
    }

    @Test func conversationalWeightAndWorkoutReturnActualReceipts() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let replies = CoachFixture([
            result([call("log_weight", "{\"local_date\":\"2027-01-15\",\"value\":70,\"unit\":\"kg\"}"),
                    call("log_workout", "{\"local_date\":\"2027-01-14\",\"kind\":\"cardio\",\"duration_minutes\":45,\"exercises\":[]}", id: "cardio")]),
            result(text: "Saved 9999 kg")])
        let completed = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.weights.first?.value == 70)
        #expect(snapshot.workouts.first?.durationMinutes == 45)
        #expect(completed.receipts.count == 2)
        #expect(completed.assistantText?.contains("70 kg") == true)
        #expect(completed.assistantText?.contains("9999") == false)
    }
    @Test func weightAndWorkoutReceiptsCarryCommittedValues() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let replies = CoachFixture([
            result([call("log_weight", "{\"local_date\":\"2027-01-15\",\"value\":70,\"unit\":\"kg\"}"),
                    call("log_workout", "{\"local_date\":\"2027-01-14\",\"kind\":\"cardio\",\"duration_minutes\":45,\"exercises\":[]}", id: "cardio")]),
            result(text: "Done")])
        let completed = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        let weight = DiaryDatabase.coachCommittedReceipt(try #require(completed.receipts.first { $0.weightID != nil }))
        let workout = DiaryDatabase.coachCommittedReceipt(try #require(completed.receipts.first { $0.workoutID != nil }))
        #expect(weight.weightValue == 70 && weight.weightUnit == "kg")
        #expect(workout.workoutKind == "cardio" && workout.workoutMinutes == 45)
        #expect(try await store.coachCommittedSummary(turnID: turn.id, expectedProfileID: profile.id) == "Weight saved: **70 kg**. Everything is in the cards below.")
    }

    @Test func mealTemplateUsesCommittedCaloriesRoundedToTen() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let food = #"{"target_local_date":"2027-01-15","items":[{"name":"Synthetic eggs","quantity":2,"unit":"egg","kcal":143,"carbs":1,"protein":12,"fat":10},{"name":"Synthetic toast","quantity":1,"unit":"slice","kcal":80,"carbs":15,"protein":3,"fat":1}]}"#
        let replies = CoachFixture([result([call("log_food", food, id: "food")]), result(text: "Done")])
        _ = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(try await store.coachCommittedSummary(turnID: turn.id, expectedProfileID: profile.id) == "Saved — about **220** kcal.")
    }

    @Test func legacyReceiptWithoutFactsHasNoCommittedValues() {
        let legacy = DiaryDatabase.coachCommittedReceipt(CoachReceipt(operationKey: "legacy", turnID: UUID(), dayID: UUID(), weightID: UUID(), committedRevision: 1, resultJSON: "{}"))
        #expect(legacy.weightValue == nil && legacy.weightUnit == nil && legacy.workoutMinutes == nil)
    }

    @Test func progressQuestionKeepsGroundedProse() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await store.setGoals(GoalRecord(effectiveLocalDate: "2027-01-15", timeZoneID: profile.timeZoneID, targets: NutritionValues(kcal: 2000), exerciseCreditEnabled: false), expectedRevision: nil, expectedProfileID: profile.id)
        _ = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-15", items: [FoodItem(name: "Synthetic meal", nutrition: NutritionValues(kcal: 500), provenance: .estimate, reference: "Fixture")], expectedProfileID: profile.id)
        let query = try await capturedTurn(store, text: "How am I doing?", photos: [], at: now, expectedProfileID: profile.id)
        let prose = "You're at **500** kcal, so about 1,500 left. A protein-rich dinner fits well."
        let replies = CoachFixture([result([call("get_progress", "{\"ending_on\":\"2027-01-15\",\"days\":1}")]), result(text: prose)])
        let completed = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: query.id, expectedProfileID: profile.id)
        #expect(completed.assistantText == prose)
    }

    @Test func mealProseMayStateTheDaysNewTotal() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await store.setGoals(GoalRecord(effectiveLocalDate: "2027-01-15", timeZoneID: profile.timeZoneID, targets: NutritionValues(kcal: 2000), exerciseCreditEnabled: false), expectedRevision: nil, expectedProfileID: profile.id)
        let earlier = try await capturedTurn(store, text: "Synthetic breakfast", photos: [], at: now, expectedProfileID: profile.id)
        _ = try await store.applyCoachFood(turnID: earlier.id, targetLocalDate: "2027-01-15", items: [FoodItem(name: "Synthetic breakfast", nutrition: NutritionValues(kcal: 500), provenance: .estimate)], expectedProfileID: profile.id)
        let food = #"{"target_local_date":"2027-01-15","items":[{"name":"Synthetic eggs","quantity":2,"unit":"egg","kcal":140,"carbs":1,"protein":12,"fat":10}]}"#
        let prose = "Saved, about **140** kcal. You're at 640 of 2,000 kcal today, so 1,360 to go."
        let replies = CoachFixture([result([call("log_food", food, id: "food")]), result(text: prose)])
        let completed = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(completed.assistantText == prose)
    }

    @Test func multiDishPhotoMealIsOneMessageWithGroundedProse() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let names = ["chicken", "rice", "hummus", "salad", "pita", "tahini", "pickles"]
        let items = names.map { #"{"name":"Synthetic \#($0)","quantity":1,"unit":"serving","kcal":100,"carbs":10,"protein":5,"fat":4}"# }.joined(separator: ",")
        let prose = "That's a feast! Dinner is saved at about **700** kcal."
        let replies = CoachFixture([result([call("log_food", #"{"target_local_date":"2027-01-15","items":["# + items + "]}")]), result(text: prose)])
        let completed = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(completed.receipts.count == 1)
        #expect(DiaryDatabase.coachCommittedReceipt(completed.receipts[0]).items.count == 7)
        #expect(completed.assistantText == prose)
    }

    @Test func progressAnswerUsesRequestedActualBudget() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await store.setGoals(GoalRecord(effectiveLocalDate: "2027-01-15", timeZoneID: profile.timeZoneID, targets: NutritionValues(kcal: 2000), exerciseCreditEnabled: false), expectedRevision: nil, expectedProfileID: profile.id)
        _ = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-15", items: [FoodItem(name: "Synthetic meal", nutrition: NutritionValues(kcal: 500), provenance: .estimate, reference: "Fixture")], expectedProfileID: profile.id)
        let query = try await capturedTurn(store, text: "What is my remaining budget?", photos: [], at: now, expectedProfileID: profile.id)
        let replies = CoachFixture([result([call("get_progress", "{\"ending_on\":\"2027-01-15\",\"days\":1}")]), result(text: "9999 remaining")])
        let completed = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: query.id, expectedProfileID: profile.id)
        #expect(completed.assistantText == "Today: 500 of 2,000 kcal, about 1,500 left.")
        #expect(completed.assistantText?.contains("9999") == false)
    }

    @Test func regeneratedProgressCallsReplayStoredReceipts() async throws {
        let (store, profile, turn, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let args = "{\"local_date\":\"2027-01-15\",\"value\":70,\"unit\":\"kg\",\"measured_at\":\"2027-01-15T08:00:00Z\"}"
        let first = CoachFixture([result([call("log_weight", args)])])
        try await interruptAfterWrite(store, profile.id, turn.id) { try await CoachEngine(store: store, infer: { try await first.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id) }
        let before = try await store.snapshotForExport()
        let retry = CoachFixture([result([call("log_weight", args, id: "regenerated")]), result(text: "Done")])
        let completed = try await CoachEngine(store: store, infer: { try await retry.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(completed.receipts == before.coachTurns[0].receipts)
        #expect(try await store.snapshotForExport().weights == before.weights)
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
        #expect(try await store.snapshotForExport().weights.isEmpty)
        #expect(try await store.snapshotForExport().coachTurns[0].assistantText == nil)
        #expect(try await store.snapshotForExport().coachTurns[0].receipts.isEmpty)
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
        let query = try await capturedTurn(store, text: "Current progress", photos: [], at: now, expectedProfileID: profile.id)
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
        #expect(completed.assistantText == "Today: 500 of 1,800 kcal, about 1,300 left.")
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
        #expect(completed.assistantText == "Workout saved: strength, 45 minutes.")
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
            guard sqlite3_exec(db, "CREATE TRIGGER reject_coach_progress BEFORE UPDATE OF revision ON storage_head BEGIN SELECT RAISE(ABORT, 'synthetic'); END", nil, nil, nil) == SQLITE_OK else { throw DiaryError.persistenceFailed }
            return output
        })
        await #expect(throws: DiaryError.persistenceFailed) { try await engine.run(turnID: turn.id, expectedProfileID: profile.id) }
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.weights.isEmpty); #expect(snapshot.coachTurns[0].receipts.isEmpty)
        #expect(snapshot.coachTurns[0].assistantText == nil)
        let reloaded = try await completeSelectedProfile(DiaryStore(directory: root), profile.id)
        #expect(reloaded.weights.isEmpty); #expect(reloaded.coachTurns[0].assistantText == nil)
    }

    @Test(arguments: [false, true]) func finishedProgressQuestionDoesNotCountItselfAsPending(otherCapture: Bool) async throws {
        let (store, profile, existing, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await store.completeCoachTurn(turnID: existing.id, assistantText: "Synthetic previous turn", expectedProfileID: profile.id)
        let day = try await store.snapshotForExport().days[0]
        try await store.setCompleteness(dayID: day.id, .complete)
        if otherCapture { _ = try await capturedTurn(store, text: "Unresolved synthetic food", photos: [], at: now, expectedProfileID: profile.id) }
        let question = try await capturedTurn(store, text: "What is my daily progress?", photos: [], at: now, expectedProfileID: profile.id)
        let replies = CoachFixture([result([call("get_progress", "{\"ending_on\":\"2027-01-15\",\"days\":1}")]), result(text: "Read complete")])
        let finished = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: question.id, expectedProfileID: profile.id)
        let report = try await store.coachProgress(endingOn: day.localDate, days: 1, expectedProfileID: profile.id)
        #expect(finished.state == .completed)
        #expect(report.daily.hasPending == otherCapture)
        #expect(report.daily.foodTotals?.kcal == (otherCapture ? nil : 0))
        #expect(finished.assistantText == "Read complete")
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
        let question = try await capturedTurn(store, text: "Show saved goals, preferences, weight and workouts. Read only.",
            photos: [], at: now, expectedProfileID: profile.id)
        let before = try await store.snapshotForExport()
        let replies = CoachFixture([result([
            call("get_progress", "{\"ending_on\":\"2027-01-15\",\"days\":1}", id: "progress"),
            call("get_workout", "{\"workout_id\":\"\(workout.id)\"}", id: "workout"),
            call("get_goals", "{\"local_date\":\"2027-01-15\"}", id: "goals"),
            call("get_preferences", "{}", id: "preferences")
        ]), result(text: "You have 9999 kcal left.")])
        let finished = try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) })
            .run(turnID: question.id, expectedProfileID: profile.id)
        let persisted = try await completeSelectedProfile(DiaryStore(directory: root), profile.id)
        let text = try #require(persisted.coachTurns.first { $0.id == question.id }?.assistantText)
        #expect(finished.state == .completed && finished.receipts.isEmpty)
        #expect(text == finished.assistantText)
        // Invented prose falls back to an app-written line from the reads, capped at two sentences.
        #expect(text == "There's no food recorded for 2027-01-15 yet. Goal: 2,000 kcal a day, 100 g protein.")
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
        try await interruptAfterWrite(store, profile.id, turn.id) { try await CoachEngine(store: store, infer: { try await first.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id) }
        let before = try await store.snapshotForExport(), receipt = try #require(before.coachTurns[0].receipts.first)
        #expect(receipt.operationKey == "\(turn.id)/correct_weight/\(weight.id)")
        if currentRevision {
            let changed = CoachFixture([result([call("log_weight", arguments(byID: !idFirst, revision: 2), id: "changed-revision")])])
            try await interruptAfterWrite(store, profile.id, turn.id) { try await CoachEngine(store: store, infer: { try await changed.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id) }
            #expect(try await store.snapshotForExport().weights == before.weights)
            #expect(try await exportedTurn(store, turnID: turn.id, expectedProfileID: profile.id).receipts == [receipt])
        }
        let retry = CoachFixture([result([call("log_weight", arguments(byID: !idFirst, revision: 1), id: "regenerated")]), result(text: "Done")])
        let finished = try await CoachEngine(store: store, infer: { try await retry.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(finished.receipts == [receipt]); #expect(try await store.snapshotForExport().weights == before.weights)
        #expect(try await store.snapshotForExport().weights[0].revision == 2)
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
        #expect(try await store.snapshotForExport().workouts == [revised])
        let fresh = try await store.coachWorkout(id: original.id, expectedProfileID: profile.id)
        let arguments = staleArguments.replacingOccurrences(of: "\"exercises\":[{\"name\":\"Squat\",\"sets\":[{\"repetitions\":8,\"load_kg\":40}]}]", with: "\"exercises\":[{\"name\":\"Squat\",\"sets\":[{\"repetitions\":8,\"load_kg\":40}]},{\"name\":\"Deadlift\",\"sets\":[{\"repetitions\":5,\"load_kg\":60}]}]")
        let parsed = try CoachTools.parse(call("edit_workout", arguments), meals: [], evidence: [:], receipts: [], workouts: [fresh])
        guard case .write(let write) = parsed else { throw CoachError.invalidArguments }
        let receipts = try await store.applyCoachWrites([write], turnID: turn.id, epoch: store.selectionEpoch(expectedProfileID: profile.id), expectedProfileID: profile.id)
        #expect(try await store.snapshotForExport().workouts[0].exercises == [squat, deadlift])
        #expect(receipts[0].workoutID == original.id)
    }

}
