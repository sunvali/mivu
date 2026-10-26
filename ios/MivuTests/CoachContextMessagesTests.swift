import Foundation
import Testing
@testable import Mivu

private actor InputLog {
    var inputs: [[CoachInferenceInput]] = []
    var replies: [CoachInferenceResult]
    init(_ replies: CoachInferenceResult...) { self.replies = replies }
    func infer(_ input: [CoachInferenceInput]) -> CoachInferenceResult { inputs.append(input); return replies.count > 1 ? replies.removeFirst() : replies[0] }
}

@Suite @MainActor struct CoachContextMessagesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func store() async throws -> (DiaryStore, DiaryProfile, URL) {
        let root = URL.temporaryDirectory.appending(path: "CoachMessages-" + UUID().uuidString)
        let clock = now, store = DiaryStore(directory: root, currentTime: { clock }), profile = adultProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay(at: now)
        return (store, profile, root)
    }
    private func text(_ item: CoachInferenceInput) -> String? { if case .message(_, let text, _) = item { return text }; return nil }
    private func role(_ item: CoachInferenceInput) -> CoachInferenceInput.Role? { if case .message(let role, _, _) = item { return role }; return nil }
    private func exchange(_ store: DiaryStore, _ profile: DiaryProfile, _ prompt: String, reply: String, at: Date) async throws -> CoachTurn {
        let turn = try await capturedTurn(store, text: prompt, photos: [], at: at, expectedProfileID: profile.id)
        let replies = InputLog(CoachInferenceResult(model: "fixture", text: reply, calls: [], outputItems: []))
        _ = try await CoachEngine(store: store, infer: { input, _ in await replies.infer(input) }).run(turnID: turn.id, expectedProfileID: profile.id)
        return turn
    }

    @Test func historyBecomesMessagesBeforeContext() async throws {
        let (store, profile, root) = try await store(); defer { try? FileManager.default.removeItem(at: root) }
        let args = #"{"target_local_date":"2027-01-15","items":[{"name":"Synthetic eggs","quantity":2,"unit":"egg","kcal":140}]}"#
        let log = CoachToolCall(id: "c1", callID: "c1", name: "log_food", namespace: "mivu", arguments: args)
        let first = InputLog(CoachInferenceResult(model: "fixture", text: "", calls: [log], outputItems: []), CoachInferenceResult(model: "fixture", text: "Logged.", calls: [], outputItems: []))
        let turn1 = try await capturedTurn(store, text: "Two synthetic eggs", photos: [], at: now, expectedProfileID: profile.id)
        _ = try await CoachEngine(store: store, infer: { input, _ in await first.infer(input) }).run(turnID: turn1.id, expectedProfileID: profile.id)
        _ = try await exchange(store, profile, "Thanks", reply: "Welcome.", at: now.addingTimeInterval(60))
        let current = try await capturedTurn(store, text: "What did I eat?", photos: [], at: now.addingTimeInterval(120), expectedProfileID: profile.id)
        let seen = InputLog(CoachInferenceResult(model: "fixture", text: "Eggs.", calls: [], outputItems: []))
        _ = try await CoachEngine(store: store, infer: { input, _ in await seen.infer(input) }).run(turnID: current.id, expectedProfileID: profile.id)
        let input = try #require(await seen.inputs.first)
        #expect(role(input[0]) == .developer && text(input[0]) == CoachEngine.stableRules)
        #expect((1...4).map { role(input[$0]) } == [.user, .assistant, .user, .assistant])
        let receiptReply = try #require(text(input[2]))
        #expect(receiptReply.contains("meal="))
        let tail = try #require(text(input[5]))
        #expect(role(input[5]) == .developer && tail.contains("Context: ") && tail.contains("\"recentTurns\":[]"))
        #expect(role(input[6]) == .user && text(input[6]) == "What did I eat?" && input.count == 7)
    }

    @Test func stablePrefixIsIdenticalAcrossTurns() async throws {
        let (store, profile, root) = try await store(); defer { try? FileManager.default.removeItem(at: root) }
        var prefixes: [String] = []
        for offset: TimeInterval in [0, 86_400 * 3] {
            let turn = try await capturedTurn(store, text: "Hello", photos: [], at: now.addingTimeInterval(offset), expectedProfileID: profile.id)
            let seen = InputLog(CoachInferenceResult(model: "fixture", text: "Hi", calls: [], outputItems: []))
            _ = try await CoachEngine(store: store, infer: { input, _ in await seen.infer(input) }).run(turnID: turn.id, expectedProfileID: profile.id)
            let first = try #require(await seen.inputs.first)
            prefixes.append(try #require(text(first[0])))
        }
        #expect(prefixes[0] == prefixes[1])
    }

    @Test func historyRespects8KBCap() async throws {
        let (store, profile, root) = try await store(); defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<12 {
            _ = try await exchange(store, profile, String(index % 10) + String(repeating: "a", count: 1023), reply: "ok", at: now.addingTimeInterval(Double(index) * 60))
        }
        let current = try await capturedTurn(store, text: "Now", photos: [], at: now.addingTimeInterval(1_000), expectedProfileID: profile.id)
        let seen = InputLog(CoachInferenceResult(model: "fixture", text: "Hi", calls: [], outputItems: []))
        _ = try await CoachEngine(store: store, infer: { input, _ in await seen.infer(input) }).run(turnID: current.id, expectedProfileID: profile.id)
        let input = try #require(await seen.inputs.first)
        let history = input.dropFirst().dropLast(2).compactMap(text)
        #expect(history.joined().utf8.count <= 8192)
        #expect(history.count >= 2 && history.count < 24)
        #expect(role(input[input.count - 3]) == .assistant && history.first?.hasPrefix("a") == false)
    }
}
