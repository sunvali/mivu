import Foundation
import FoundationModels
import ImageIO

/// On-device Apple Intelligence behind the same inference boundary as the ChatGPT plan.
@available(iOS 27.0, *)
enum AppleInference {
    /// Output items use the ChatGPT item shape that `CoachInferenceInput.priorOutput` already validates.
    static func result(text: String, calls: [Transcript.ToolCall]) throws -> CoachInferenceResult {
        let toolCalls = calls.map { CoachToolCall(id: "fc_" + $0.id, callID: $0.id, name: $0.toolName, namespace: CoachTools.namespace, arguments: $0.arguments.jsonString) }
        let items: [[String: Any]] = toolCalls.isEmpty
            ? [["type": "message", "role": "assistant", "content": [["type": "output_text", "text": text]]]]
            : toolCalls.map { ["type": "function_call", "id": $0.id, "call_id": $0.callID, "name": $0.name, "namespace": CoachTools.namespace,
                               "arguments": $0.arguments, "status": "completed"] }
        return CoachInferenceResult(model: "apple-intelligence", text: text, calls: toolCalls,
                                    outputItems: try items.map { try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) })
    }

    static func attachment(_ data: Data) throws -> Transcript.ImageAttachment {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ResponsesClient.Failure.invalidInput }
        return Transcript.ImageAttachment(image)
    }
}
