import Foundation
import Testing
@testable import Mivu

@Suite struct CoachCorrectionJourneyTests {
    @Test func yesterdayLunchIncrementUsesCapturedContextAndUnloadedGroundedMeal() async throws {
        let f = try CoachLunchFixture(); defer { f.remove() }
        let store = try await f.store(), accepted = try await f.accept(store)
        let latest = try f.database.coachPage(.latest, expectedProfileID: f.owner)
        #expect(!latest.exchanges.contains { $0.id == f.source.coachTurns[0].id })
        let context = try await store.coachContext(turnID: accepted.id, expectedProfileID: f.owner)
        #expect(!context.meals.contains { $0.id == f.mealID })
        let original = try await store.meal(id: f.mealID, expectedProfileID: f.owner)
        let mealIDs = try f.rows("SELECT id FROM meal ORDER BY id")
        f.metrics.reset()
        let transport = CoachJourneyTransport()
        _ = try await f.run(store, accepted.id, transport)
        let corrected = try await store.meal(id: f.mealID, expectedProfileID: f.owner)
        #expect(corrected.id == original.id && corrected.dayID == original.dayID)
        #expect(corrected.items[0].id == original.items[0].id && corrected.items[0].quantity == 3 && corrected.items[0].unit == "piece")
        #expect(Array(corrected.items.dropFirst()) == Array(original.items.dropFirst()))
        #expect(corrected.eatenAt == original.eatenAt && corrected.capturedAt == original.capturedAt && corrected.timePrecision == original.timePrecision)
        #expect(corrected.photos == original.photos && corrected.sourceTurnID == original.sourceTurnID)
        #expect(corrected.items[0].nutritionBasis == original.items[0].nutritionBasis && corrected.items[0].reference == original.items[0].reference)
        #expect(corrected.items[0].nutrition.kcal == 300 && corrected.items[0].nutrition.carbs == nil)
        #expect(corrected.items[0].nutrientSources == original.items[0].nutrientSources)
        #expect(try f.rows("SELECT id FROM meal ORDER BY id") == mealIDs)
        let exchange = try f.database.coachExchangeSummary(turnID: accepted.id, expectedProfileID: f.owner)
        #expect(exchange.sequence == accepted.sequence && exchange.capturedAt == accepted.capturedAt)
        #expect(exchange.receipts.count == 1)
        let receipt = try #require(exchange.receipts.first)
        #expect(receipt.targetLocalDate == "2027-01-15")
        #expect(receipt.items.first?.quantity == 3 && receipt.items.first?.unit == "piece")
        #expect(exchange.assistantText?.contains("2027-01-15") == true && exchange.assistantText?.contains("3 piece") == true)
        try await transport.assertGroundedCorrection(date: "2027-01-15", meal: original.id, item: original.items[0].id, quantity: 3)
        #expect(try f.applications() == 1)
        f.assertOrdinaryReads()
    }

    @Test(arguments: ["meal", "item", "quantity", "description", "page", "itemsOmitted"])
    func ambiguousLunchItemOrAdditionalServingClarifiesBeforeWriting(ambiguity: String) async throws {
        let f = try CoachLunchFixture(ambiguity: ambiguity); defer { f.remove() }
        let store = try await f.store(), accepted = try await f.accept(store)
        let before = try f.businessRows()
        let transport = CoachJourneyTransport()
        _ = try await f.run(store, accepted.id, transport)
        let exchange = try f.database.coachExchangeSummary(turnID: accepted.id, expectedProfileID: f.owner)
        #expect(try f.businessRows() == before && f.applications() == 0)
        #expect(exchange.receipts.isEmpty && exchange.assistantText?.contains("?") == true)
        #expect(exchange.assistantText?.lowercased().contains("updated") != true)
        let calls = await transport.calls
        #expect(calls.first?.name == "get_meals_for_date" && calls.last?.name == "ask_clarification")
        #expect(calls.allSatisfy { !["correct_item", "log_food", "append_food"].contains($0.name) })
        f.assertOrdinaryReads()
    }

    @Test func delayedLunchCorrectionRetainsCapturedYesterdayAcrossTravelAndDST() async throws {
        // New York jumped forward on March 8: subtracting 86,400 seconds lands March 7.
        let capture = ISO8601DateFormatter().date(from: "2026-03-09T04:30:00Z")!
        let f = try CoachLunchFixture(capturedAt: capture, zone: "America/New_York"); defer { f.remove() }
        let initial = try await f.store(), accepted = try await f.accept(initial)
        try await initial.setCoachTurnState(turnID: accepted.id, state: .waitingForNetwork, expectedProfileID: f.owner)
        var profile = f.source.profile; profile.timeZoneID = "Asia/Tokyo"
        try await initial.updateProfile(profile, expectedProfileID: f.owner)
        let reopened = try await f.store()
        let job = try #require(try await reopened.nextPendingCoachTurn(includeWaitingForConnection: false, expectedProfileID: f.owner))
        #expect(job.id == accepted.id && job.capturedAt == capture && job.captureTimeZoneID == "America/New_York")
        let transport = CoachJourneyTransport()
        _ = try await f.run(reopened, job.id, transport)
        #expect(try await reopened.meal(id: f.mealID, expectedProfileID: f.owner).items[0].quantity == 3)
        #expect(try f.database.coachExchangeSummary(turnID: job.id, expectedProfileID: f.owner).receipts.first?.targetLocalDate == "2026-03-08")
        try await transport.assertGroundedCorrection(date: "2026-03-08", meal: f.mealID, item: f.source.meals[0].items[0].id, quantity: 3)
        f.assertOrdinaryReads()
    }

    @Test func manualEditDuringLunchInferenceRejectsStaleCorrection() async throws {
        let f = try CoachLunchFixture(); defer { f.remove() }
        let store = try await f.store(), accepted = try await f.accept(store)
        let transport = CoachJourneyTransport(beforeCorrection: {
            var item = try await store.meal(id: f.mealID, expectedProfileID: f.owner).items[0]; item.quantity = 5
            try await store.editItem(mealID: f.mealID, item: item, expectedRevision: 1, expectedProfileID: f.owner)
            try f.clearApplications()
        })
        await #expect(throws: DiaryError.staleRevision) { try await f.run(store, accepted.id, transport) }
        let meal = try await store.meal(id: f.mealID, expectedProfileID: f.owner)
        #expect(meal.items[0].quantity == 5 && meal.revision == 2)
        let exchange = try f.database.coachExchangeSummary(turnID: accepted.id, expectedProfileID: f.owner)
        #expect(exchange.receipts.isEmpty && exchange.assistantText == nil)
        #expect(try f.applications() == 0)
        try await transport.assertGroundedCorrection(date: "2027-01-15", meal: f.mealID, item: meal.items[0].id, quantity: 3)
        f.assertOrdinaryReads()
    }

    @Test func editBeforeGroundingUsesCurrentCommittedServing() async throws {
        let f = try CoachLunchFixture(); defer { f.remove() }
        let store = try await f.store(), accepted = try await f.accept(store)
        var item = try await store.meal(id: f.mealID, expectedProfileID: f.owner).items[0]; item.quantity = 4
        try await store.editItem(mealID: f.mealID, item: item, expectedRevision: 1, expectedProfileID: f.owner)
        try f.clearApplications()
        let transport = CoachJourneyTransport()
        _ = try await f.run(store, accepted.id, transport)
        #expect(try await store.meal(id: f.mealID, expectedProfileID: f.owner).items[0].quantity == 5)
        try await transport.assertGroundedCorrection(date: "2027-01-15", meal: f.mealID, item: item.id, quantity: 5, revision: 2)
        #expect(try f.applications() == 1)
    }

    @Test func lunchIncrementCrashAfterCommitReplaysOriginalResultOnce() async throws {
        let f = try CoachLunchFixture(); defer { f.remove() }
        let initial = try await f.store(), accepted = try await f.accept(initial)
        let transport = CoachJourneyTransport(interruptAfterCommit: true)
        await #expect(throws: CoachJourneyTransport.Interruption.afterCommit) { try await f.run(initial, accepted.id, transport) }
        let prior = try f.database.coachExchangeSummary(turnID: accepted.id, expectedProfileID: f.owner)
        #expect(prior.receipts.count == 1 && prior.assistantText == nil)
        #expect(try f.applications() == 1)
        #expect(try await initial.meal(id: f.mealID, expectedProfileID: f.owner).items[0].quantity == 3)
        let recovery = try await f.store()
        try await recovery.setCoachTurnState(turnID: accepted.id, state: .captured, expectedProfileID: f.owner)
        _ = try await f.run(recovery, accepted.id, CoachJourneyTransport())
        let replay = try f.database.coachExchangeSummary(turnID: accepted.id, expectedProfileID: f.owner)
        #expect(replay.receipts == prior.receipts)
        #expect(try f.applications() == 1)
        #expect(try await recovery.meal(id: f.mealID, expectedProfileID: f.owner).items[0].quantity == 3)
        // Historical result facts survive later manual edits and another lost notification.
        var manual = try await recovery.meal(id: f.mealID, expectedProfileID: f.owner).items[0]; manual.quantity = 5
        try await recovery.editItem(mealID: f.mealID, item: manual, expectedRevision: 2, expectedProfileID: f.owner)
        let applications = try f.applications()
        try await recovery.setCoachTurnState(turnID: accepted.id, state: .captured, expectedProfileID: f.owner)
        let again = try await f.store()
        _ = try await f.run(again, accepted.id, CoachJourneyTransport())
        #expect(try await again.meal(id: f.mealID, expectedProfileID: f.owner).items[0].quantity == 5)
        let final = try f.database.coachExchangeSummary(turnID: accepted.id, expectedProfileID: f.owner)
        #expect(final.receipts == prior.receipts)
        let finalReceipt = try #require(final.receipts.first)
        let finalItem = try #require(finalReceipt.items.first)
        #expect(finalItem.quantity == 3)
        #expect(final.assistantText?.contains("2027-01-15") == true && final.assistantText?.contains("3 piece") == true)
        #expect(try f.applications() == applications)
        f.assertOrdinaryReads()
    }
}

/// Reuses the app's synthetic adapter; records actual Engine tools and function outputs.
actor CoachJourneyTransport {
    enum Interruption: Error { case afterCommit }
    private(set) var calls: [CoachToolCall] = []
    private(set) var contexts: [CoachContext] = []
    private(set) var outputs: [String] = []
    private var observedOutputs = 0
    private let interruptAfterCommit: Bool
    private let mixedWrite: Bool
    private let beforeCorrection: (@Sendable () async throws -> Void)?
    init(interruptAfterCommit: Bool = false, mixedWrite: Bool = false, beforeCorrection: (@Sendable () async throws -> Void)? = nil) {
        self.interruptAfterCommit = interruptAfterCommit; self.mixedWrite = mixedWrite; self.beforeCorrection = beforeCorrection
    }
    func infer(_ input: [CoachInferenceInput], _ tools: Data) async throws -> CoachInferenceResult {
        for entry in input {
            if case .message(role: .developer, let text, _) = entry, let range = text.range(of: "Context: ") {
                contexts.append(try JSONDecoder().decode(CoachContext.self, from: Data(text[range.upperBound...].utf8)))
            }
        }
        let actual = input.compactMap { entry -> String? in if case .functionOutput(_, let output) = entry { return output }; return nil }
        outputs += actual.dropFirst(observedOutputs); observedOutputs = actual.count
        if interruptAfterCommit, let output = actual.last,
           let object = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
           object["item"] != nil, object["targetLocalDate"] != nil { throw Interruption.afterCommit }
        var response = try await CoachUITestInference.respond(input, tools)
        if mixedWrite, response.calls.contains(where: { $0.name == "correct_item" }) {
            let weight = CoachToolCall(id: "paired-weight", callID: "paired-weight", name: "log_weight", namespace: "mivu",
                arguments: "{\"local_date\":\"2027-01-15\",\"value\":70,\"unit\":\"kg\"}")
            response = CoachInferenceResult(model: response.model, text: response.text, calls: response.calls + [weight], outputItems: response.outputItems)
        }
        calls += response.calls
        if response.calls.contains(where: { $0.name == "correct_item" }) { try await beforeCorrection?() }
        return response
    }
    func assertGroundedCorrection(date: String, meal: UUID, item: UUID, quantity: Double, revision: Int = 1) throws {
        #expect(calls.map(\.name) == ["get_meals_for_date", "get_meal", "correct_item"])
        let dated = try #require(calls.first)
        let datedArgs = try #require(try JSONSerialization.jsonObject(with: Data(dated.arguments.utf8)) as? [String: Any])
        #expect(datedArgs["target_local_date"] as? String == date)
        let detail = try #require(calls.first { $0.name == "get_meal" })
        let detailArgs = try #require(try JSONSerialization.jsonObject(with: Data(detail.arguments.utf8)) as? [String: Any])
        #expect(detailArgs["meal_id"] as? String == meal.uuidString)
        let correction = try #require(calls.first { $0.name == "correct_item" })
        let args = try #require(try JSONSerialization.jsonObject(with: Data(correction.arguments.utf8)) as? [String: Any])
        #expect(args["meal_id"] as? String == meal.uuidString && args["item_id"] as? String == item.uuidString)
        #expect(args["quantity"] as? Double == quantity && args["expected_revision"] as? Int == revision)
        #expect(outputs.count >= 2)
        let page = try JSONDecoder().decode(CoachMealCandidatePage.self, from: Data(outputs[0].utf8))
        let grounded = try JSONDecoder().decode(CoachContext.Meal.self, from: Data(outputs[1].utf8))
        #expect(page.meals.contains { $0.id == meal } && grounded.id == meal && grounded.items.contains { $0.id == item })
    }
}

struct CoachLunchFixture: Sendable {
    let capture: CaptureFixture
    let metrics = DiaryQueryDiagnostics()
    let capturedAt: Date
    let processAt: Date
    var source: DiarySnapshot { capture.before }
    var owner: UUID { source.profile.id }
    var mealID: UUID { source.meals[0].id }
    var database: DiaryDatabase { get throws { try DiaryDatabase(url: capture.url, diagnostics: metrics) } }
    init(capturedAt: Date = ISO8601DateFormatter().date(from: "2027-01-16T10:00:00Z")!, zone: String = "UTC", ambiguity: String = "none") throws {
        self.capturedAt = capturedAt
        let snapshot = ChatHistoryFixture.lunchCorrectionSnapshot(capturedAt: capturedAt, zone: zone, ambiguity: ambiguity)
        self.processAt = snapshot.days.last!.startAt.addingTimeInterval(3600)
        capture = try CaptureFixture(snapshot: snapshot)
        try capture.execute("CREATE TABLE correction_audit(recordID TEXT, oldQuantity REAL, newQuantity REAL)")
        try capture.execute("CREATE TRIGGER observe_correction AFTER UPDATE ON item WHEN json_extract(CAST(NEW.payload AS TEXT), '$.quantity') != json_extract(CAST(OLD.payload AS TEXT), '$.quantity') BEGIN INSERT INTO correction_audit VALUES (NEW.id, json_extract(CAST(OLD.payload AS TEXT), '$.quantity'), json_extract(CAST(NEW.payload AS TEXT), '$.quantity')); END")
    }
    func remove() { capture.remove() }
    func store() async throws -> DiaryStore {
        let time = processAt, store = DiaryStore(directory: capture.root, currentTime: { time }, diagnostics: metrics)
        _ = try await store.selectPagedProfile(owner); return store
    }
    func accept(_ store: DiaryStore, text: String = "Please edit yesterday’s lunch because I ate one more chicken.") async throws -> CoachExchangeSummary {
        let head = try await store.diaryHead(expectedProfileID: owner)
        let context = CoachCaptureContext(capturedAt: capturedAt, timeZoneID: head.profile.timeZoneID, activeDayID: head.activeDayID,
            previousDayConfirmedAt: head.previousDayConfirmedAt, activeConversationSegmentID: head.effectiveConversationSegmentID)
        return try await capturedSubmission(store, CoachSubmissionPayload(submissionID: UUID(), text: text, attachments: [], context: context), expectedProfileID: owner)
    }
    @discardableResult func run(_ store: DiaryStore, _ id: UUID, _ transport: CoachJourneyTransport) async throws -> CoachTurnResult {
        let work = try #require(try await store.nextPendingCoachTurn(includeWaitingForConnection: false, expectedProfileID: owner))
        #expect(work.id == id && work.photos.isEmpty)
        return try await CoachEngine(store: store, infer: { try await transport.infer($0, $1) }).run(turnID: work.id, expectedProfileID: owner)
    }
    func rows(_ sql: String) throws -> [[String]] { try capture.rows(sql) }
    func applications() throws -> Int { Int(try rows("SELECT COUNT(*) FROM correction_audit")[0][0])! }
    func clearApplications() throws { try capture.execute("DELETE FROM correction_audit") }
    func businessRows() throws -> [[[String]]] {
        try ["meal", "item", "submission", "photo", "record_source", "photo_consumer"].map { try rows("SELECT * FROM \($0) ORDER BY rowid") }
    }
    func assertOrdinaryReads() {
        #expect(metrics.counters.completeReads == 0 && metrics.counters.completeReconciles == 0 && metrics.counters.originalPhotoBytes == 0)
        #expect(metrics.counters.coachPageReads == 0)
        #expect(!metrics.counters.queryPlans.contains { $0.contains("SCAN coach_index") || $0.contains("SCAN coach_turn") })
    }
}
