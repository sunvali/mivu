import Foundation
import Testing
@testable import Mivu

private actor PartialModel {
    var inputs: [[CoachInferenceInput]] = []
    var results: [CoachInferenceResult]
    let failure: Error?
    init(_ results: [CoachInferenceResult], then failure: Error? = nil) { self.results = results; self.failure = failure }
    func infer(_ input: [CoachInferenceInput]) throws -> CoachInferenceResult {
        inputs.append(input)
        if results.isEmpty, let failure { throw failure }
        guard !results.isEmpty else { throw CoachError.limitExceeded }
        return results.removeFirst()
    }
}

/// A failure after a committed write completes the turn as incomplete; reopening it exercises receipt replay.
func interruptAfterWrite<R>(_ store: DiaryStore, _ profileID: UUID, _ turnID: UUID, isolation: isolated (any Actor)? = #isolation, _ run: () async throws -> R) async throws {
    _ = try await run()
    try await store.setCoachTurnState(turnID: turnID, state: .captured, expectedProfileID: profileID)
}

@Suite @MainActor struct CoachPartialSuccessTests {
    private func log(_ date: String = "2027-01-15") -> String { #"{"target_local_date":"\#(date)","items":[{"name":"Eggs","quantity":2,"unit":"egg","kcal":140,"carbs":1,"protein":12,"fat":10}]}"# }
    private func call(_ name: String, _ args: String, id: String) -> CoachToolCall {
        CoachToolCall(id: id, callID: id, name: name, namespace: "mivu", arguments: args)
    }
    private func result(_ calls: [CoachToolCall] = [], text: String = "") -> CoachInferenceResult {
        CoachInferenceResult(model: "fixture", text: text, calls: calls, outputItems: [])
    }

    @Test func writeThenFailureCompletesIncomplete() async throws {
        let root = URL.temporaryDirectory.appending(path: "CoachPartial-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = DiaryStore(directory: root, currentTime: { now }); let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay(at: now)
        let turn = try await capturedTurn(store, text: "Eggs and a thing", photos: [], at: now, expectedProfileID: profile.id)
        let model = PartialModel([result([call("log_food", log(), id: "a")]), result([call("no_such_tool", "{}", id: "b")])])
        let finished = try await CoachEngine(store: store, infer: { input, _ in try await model.infer(input) }).run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(finished.state == .completed && finished.receipts.count == 1 && finished.assistantText?.contains("140") == true)
        let page = try await store.coachPage(.latest, expectedProfileID: profile.id)
        #expect(page.exchanges.first { $0.id == turn.id }?.incomplete == true)
    }

    @Test func retryDoesNotReapplyReceipts() async throws {
        let root = URL.temporaryDirectory.appending(path: "CoachPartial-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root); _ = try await store.createProfile(DiaryProfile(name: "Synthetic coach"))
        _ = try await store.startDay(at: Date())
        let today = diaryDateLabel(Date(), zone: TimeZone.current.identifier)
        let diary = DiaryViewModel(store: store); await diary.load(createDefaultProfile: false)
        let model = PartialModel([result([call("log_food", log(today), id: "a")]), result([call("no_such_tool", "{}", id: "b")]), result(text: "Nothing else to do.")])
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { input, _ in try await model.infer(input) } })
        coach.draft.text = "Eggs and a thing"
        #expect(await coach.send()); await coach.waitForWorker()
        let owner = try #require(diary.selection).identity.profileID
        let first = try #require(try await store.coachPage(.latest, expectedProfileID: owner).exchanges.last)
        #expect(first.incomplete == true)
        await coach.finishRest(of: first); await coach.waitForWorker()
        let inputs = await model.inputs
        let tail = try #require(inputs.last?.compactMap { entry -> String? in if case .message(role: .developer, let text, _) = entry { return text }; return nil }.last)
        let context = try JSONDecoder().decode(CoachContext.self, from: Data(try #require(tail.range(of: "Context: ").map { String(tail[$0.upperBound...]) }).utf8))
        #expect(context.replyTo?.turn?.receipts?.isEmpty == false)
        let page = try await store.coachPage(.latest, expectedProfileID: owner)
        #expect(page.exchanges.count == 2 && page.exchanges.last?.reply?.target == .message(turnID: first.id, fromPip: true))
        #expect(try await store.coachContext(turnID: first.id, expectedProfileID: owner).meals.count == 1)
    }

    @Test(arguments: [0, 1]) func cancellationAfterWriteKeepsFailurePath(kind: Int) async throws {
        let root = URL.temporaryDirectory.appending(path: "CoachPartial-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = DiaryStore(directory: root, currentTime: { now }); let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay(at: now)
        let turn = try await capturedTurn(store, text: "Eggs and a thing", photos: [], at: now, expectedProfileID: profile.id)
        let error: Error = kind == 0 ? URLError(.cancelled) : SessionError.sessionChanged
        let model = PartialModel([result([call("log_food", log(), id: "a")])], then: error)
        await #expect(throws: (any Error).self) {
            _ = try await CoachEngine(store: store, infer: { input, _ in try await model.infer(input) }).run(turnID: turn.id, expectedProfileID: profile.id)
        }
        let stored = try await exportedTurn(store, turnID: turn.id, expectedProfileID: profile.id)
        #expect(stored.state != .completed && stored.incomplete == nil)
    }

    @Test func photoOnlyRetrySendsFinishTheRest() async throws {
        let root = URL.temporaryDirectory.appending(path: "CoachPartial-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root); _ = try await store.createProfile(DiaryProfile(name: "Synthetic coach"))
        _ = try await store.startDay(at: Date())
        let today = diaryDateLabel(Date(), zone: TimeZone.current.identifier)
        let diary = DiaryViewModel(store: store); await diary.load(createDefaultProfile: false)
        let model = PartialModel([result([call("log_food", log(today), id: "a")]), result([call("no_such_tool", "{}", id: "b")]), result(text: "Nothing else to do.")])
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { input, _ in try await model.infer(input) } })
        coach.draft.photos = [SyntheticConnectionProbe.image]
        #expect(await coach.send()); await coach.waitForWorker()
        let owner = try #require(diary.selection).identity.profileID
        let first = try #require(try await store.coachPage(.latest, expectedProfileID: owner).exchanges.last)
        #expect(first.incomplete == true && first.text.isEmpty)
        await coach.finishRest(of: first); await coach.waitForWorker()
        let page = try await store.coachPage(.latest, expectedProfileID: owner)
        #expect(page.exchanges.count == 2 && page.exchanges.last?.text == "Finish the rest")
        #expect(page.exchanges.last?.reply?.target == .message(turnID: first.id, fromPip: true))
    }
}
