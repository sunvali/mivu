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
