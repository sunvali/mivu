import Foundation
import FoundationModels
import Testing
import UIKit
@testable import Mivu

struct AppleInferenceTests {
    @Test func everyCoachToolBecomesAnAppleToolDefinition() throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let namespace = try CoachTools.declarations()
        let tools = try #require((try JSONSerialization.jsonObject(with: namespace) as? [String: Any])?["tools"] as? [[String: Any]])
        let definitions = try AppleInference.toolDefinitions(namespace)
        #expect(definitions.map(\.name) == tools.map { $0["name"] as? String })
        for (definition, tool) in zip(definitions, tools) {
            let source = try #require((tool["parameters"] as? [String: Any])?["properties"] as? [String: Any])
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(definition.parameters)) as? [String: Any]
            let properties = try #require(encoded?["properties"] as? [String: Any], "\(definition.name)")
            #expect(Set(properties.keys) == Set(source.keys), "\(definition.name)")
        }
    }

    @Test func coachInputBecomesAnAppleTranscriptInOrder() throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).jpegData(withCompressionQuality: 0.8) { $0.fill(CGRect(x: 0, y: 0, width: 4, height: 4)) }
        let call = try JSONSerialization.data(withJSONObject: ["type": "function_call", "id": "fc_1", "call_id": "call_1", "name": "get_meal",
                                                               "namespace": "mivu", "arguments": #"{"meal_id":"A"}"#], options: .sortedKeys)
        let tools = try AppleInference.toolDefinitions(CoachTools.declarations())
        let transcript = try AppleInference.transcript([
            .message(role: .developer, text: "Rules"),
            .message(role: .user, text: "Lunch", images: [jpeg]),
            .message(role: .user, text: "", images: [jpeg]),
            .priorOutput(call),
            .functionOutput(callID: "call_1", output: #"{"id":"A"}"#),
        ], tools: tools)
        guard transcript.count == 4, case .instructions(let instructions) = transcript[0], case .prompt(let prompt) = transcript[1],
              case .toolCalls(let calls) = transcript[2], case .toolOutput(let output) = transcript[3] else { Issue.record("\(transcript)"); return }
        #expect(describe(instructions.segments) == ["Rules"])
        #expect(instructions.toolDefinitions.map(\.name) == tools.map(\.name))
        // Contiguous user chunks and image groups are one captured turn.
        #expect(describe(prompt.segments) == ["Lunch", "image", "image"])
        #expect(calls.map(\.id) == ["call_1"])
        #expect(calls.first?.toolName == "get_meal")
        #expect(calls.first.map { try? JSONSerialization.jsonObject(with: Data($0.arguments.jsonString.utf8)) as? [String: String] } == ["meal_id": "A"])
        #expect(output.id == "call_1")
        #expect(output.toolName == "get_meal")
        #expect(describe(output.segments) == [#"{"id":"A"}"#])
    }

    @Test func perTurnDeveloperContextJoinsTheCapturedPrompt() throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let transcript = try AppleInference.transcript([
            .message(role: .developer, text: "Rules"),
            .message(role: .user, text: "Earlier"),
            .message(role: .assistant, text: "Saved"),
            .message(role: .developer, text: "Context: {}"),
            .message(role: .user, text: "Lunch"),
        ], tools: [])
        guard transcript.count == 4, case .instructions = transcript[0], case .prompt = transcript[1],
              case .response = transcript[2], case .prompt(let prompt) = transcript[3] else { Issue.record("\(transcript)"); return }
        #expect(describe(prompt.segments) == ["Context: {}", "Lunch"])
    }

    @Test func capturedCallsReplayAsTheSameToolCalls() throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let calls = [Transcript.ToolCall(id: "a", toolName: "lookup_nutrition", arguments: try GeneratedContent(json: #"{"query":"egg"}"#)),
                     Transcript.ToolCall(id: "b", toolName: "lookup_nutrition", arguments: try GeneratedContent(json: #"{"query":"toast"}"#))]
        let result = try AppleInference.result(text: "", calls: calls)
        #expect(result.calls.map(\.callID) == ["a", "b"])
        #expect(result.calls.allSatisfy { $0.namespace == CoachTools.namespace && $0.name == "lookup_nutrition" })
        #expect(result.calls.map { try? JSONSerialization.jsonObject(with: Data($0.arguments.utf8)) as? [String: String] } == [["query": "egg"], ["query": "toast"]])
        let replay = try AppleInference.transcript(result.outputItems.map { .priorOutput($0) }, tools: [])
        guard replay.count == 1, case .toolCalls(let replayed) = replay[0] else { Issue.record("\(replay)"); return }
        #expect(replayed.map(\.id) == ["a", "b"])

        let answer = try AppleInference.result(text: "Two eggs are about 155 kcal.", calls: [])
        #expect(answer.calls.isEmpty && answer.text == "Two eggs are about 155 kcal.")
        let replayedAnswer = try AppleInference.transcript(answer.outputItems.map { .priorOutput($0) }, tools: [])
        guard replayedAnswer.count == 1, case .response(let response) = replayedAnswer[0] else { Issue.record("\(replayedAnswer)"); return }
        #expect(describe(response.segments) == ["Two eggs are about 155 kcal."])
    }

    @Test @MainActor func appleAnswersWhenNoChatGPTPlanIsConnected() throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let apple = ChatGPTConnection(preferences: UserDefaults(suiteName: "AppleInference-" + UUID().uuidString)!, appleModelAvailable: { true })
        #expect(apple.provider == .apple)
        #expect(!apple.planAuthorized && apple.canInfer)
        #expect(throws: Never.self) { _ = try apple.inference() }
        let none = ChatGPTConnection(preferences: UserDefaults(suiteName: "AppleInference-" + UUID().uuidString)!, appleModelAvailable: { false })
        #expect(none.provider == .chatGPT)
        #expect(!none.canInfer)
        #expect(throws: SessionError.noActiveSession) { _ = try none.inference() }
    }

    @Test @MainActor func savedAppleChoiceUsesChatGPTWhileAppleIsUnavailable() throws {
        let preferences = UserDefaults(suiteName: "AppleInference-" + UUID().uuidString)!
        ChatGPTConnection(preferences: preferences, appleModelAvailable: { true }).provider = .apple
        let unavailable = ChatGPTConnection(preferences: preferences, appleModelAvailable: { false })
        #expect(unavailable.provider == .chatGPT)
        #expect(throws: SessionError.noActiveSession) { _ = try unavailable.inference() }
        #expect(ChatGPTConnection(preferences: preferences, appleModelAvailable: { true }).provider == .apple)
    }

    @Test @MainActor func chosenProviderPersistsAndChatGPTChoiceNeverFallsBackToApple() throws {
        let preferences = UserDefaults(suiteName: "AppleInference-" + UUID().uuidString)!
        let first = ChatGPTConnection(preferences: preferences, appleModelAvailable: { true })
        first.provider = .chatGPT
        let relaunched = ChatGPTConnection(preferences: preferences, appleModelAvailable: { true })
        #expect(relaunched.provider == .chatGPT)
        #expect(!relaunched.canInfer)
        #expect(throws: SessionError.noActiveSession) { _ = try relaunched.inference() }
    }

    @available(iOS 27.0, *)
    private func describe(_ segments: [Transcript.Segment]) -> [String] {
        segments.map {
            switch $0 {
            case .text(let text): text.content
            case .attachment: "image"
            case .structure: "structure"
            @unknown default: "unknown"
            }
        }
    }
}
