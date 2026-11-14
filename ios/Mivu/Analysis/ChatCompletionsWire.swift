import Foundation

/// OpenAI-style Chat Completions, as Gemini's compatibility address and OpenRouter speak it.
enum ChatCompletionsWire {
    static func body(model: String, input: [CoachInferenceInput], toolNamespace: Data?) throws -> Data {
        guard !model.isEmpty, !input.isEmpty, input.count <= 128 else { throw ResponsesClient.Failure.invalidInput }
        let messages: [Any] = try input.map { item in
            switch item {
            case let .message(role, text, images):
                guard images.isEmpty || role == .user else { throw ResponsesClient.Failure.invalidInput }
                guard role == .user else { return ["role": role == .developer ? "system" : "assistant", "content": text] }
                var parts: [[String: Any]] = text.isEmpty ? [] : [["type": "text", "text": text]]
                for image in images {
                    let url = "data:\(try CoachInferenceInput.imageMIME(image));base64," + image.base64EncodedString()
                    parts.append(["type": "image_url", "image_url": ["url": url]])
                }
                guard !parts.isEmpty else { throw ResponsesClient.Failure.invalidInput }
                return ["role": "user", "content": parts]
            case let .priorOutput(data): return try KeyServiceWire.kept(data, "chat")
            case let .functionOutput(callID, output): return ["role": "tool", "tool_call_id": callID, "content": output]
            }
        }
        var payload: [String: Any] = ["model": model, "messages": messages]
        let tools = try KeyServiceWire.functions(toolNamespace).map {
            ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]] as [String: Any]
        }
        if !tools.isEmpty { payload["tools"] = tools }
        return try KeyServiceWire.serialized(payload)
    }

    static func result(_ reply: Data) throws -> CoachInferenceResult {
        guard let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
              let model = object["model"] as? String, let choice = (object["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else { throw ResponsesClient.Failure.malformedResponse }
        switch choice["finish_reason"] as? String {
        case "content_filter": return CoachInferenceResult(model: model, text: KeyServiceWire.refusal, calls: [], outputItems: [])
        case "length": throw ResponsesClient.Failure.incompleteResponse
        default: break
        }
        let text = message["content"] as? String ?? ""
        let calls = try (message["tool_calls"] as? [[String: Any]] ?? []).map { call in
            guard let id = call["id"] as? String, !id.isEmpty, let function = call["function"] as? [String: Any],
                  let name = function["name"] as? String, let arguments = function["arguments"] as? String else { throw ResponsesClient.Failure.malformedResponse }
            return CoachToolCall(id: id, callID: id, name: name, namespace: CoachTools.namespace, arguments: arguments)
        }
        guard !calls.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ResponsesClient.Failure.malformedResponse }
        // The whole message goes back unchanged: Gemini attaches signatures to tool calls that it expects to see again.
        return CoachInferenceResult(model: model, text: text, calls: calls, outputItems: try KeyServiceWire.keep(message, "chat"))
    }
}
