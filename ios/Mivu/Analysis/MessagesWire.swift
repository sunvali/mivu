import Foundation

/// What the Claude and Chat Completions translators share.
enum KeyServiceWire {
    static let refusal = "I can't help with that one."

    /// Coach tools arrive as one Responses `namespace` object; other services take a flat function list, without `strict`.
    static func functions(_ namespace: Data?) throws -> [(name: String, description: String, parameters: [String: Any])] {
        guard let namespace else { return [] }
        guard let object = try? JSONSerialization.jsonObject(with: namespace) as? [String: Any],
              let tools = object["tools"] as? [[String: Any]] else { throw ResponsesClient.Failure.invalidInput }
        return try tools.map {
            guard let name = $0["name"] as? String, let parameters = $0["parameters"] as? [String: Any] else { throw ResponsesClient.Failure.invalidInput }
            return (name, $0["description"] as? String ?? "", parameters)
        }
    }

    /// The assistant turn a translator stored under `key`, to send back unchanged. Another service's item is refused.
    static func kept(_ item: Data, _ key: String) throws -> Any {
        guard let object = try? JSONSerialization.jsonObject(with: item) as? [String: Any], let value = object[key] else { throw ResponsesClient.Failure.invalidInput }
        return value
    }

    static func keep(_ value: Any, _ key: String) throws -> [Data] {
        [try JSONSerialization.data(withJSONObject: ["type": "message", "role": "assistant", key: value], options: .sortedKeys)]
    }

    static func serialized(_ payload: [String: Any]) throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: payload)
        guard body.count <= 8_388_608 else { throw ResponsesClient.Failure.invalidInput }
        return body
    }
}

/// Anthropic Messages API, in Claude's native format.
enum MessagesWire {
    static func body(model: String, input: [CoachInferenceInput], toolNamespace: Data?) throws -> Data {
        guard !model.isEmpty, !input.isEmpty, input.count <= 128 else { throw ResponsesClient.Failure.invalidInput }
        var system: [[String: String]] = [], messages: [[String: Any]] = []
        for item in input {
            switch item {
            case let .message(role, text, images):
                if role == .developer { system.append(["type": "text", "text": text]); continue }
                guard images.isEmpty || role == .user else { throw ResponsesClient.Failure.invalidInput }
                var content: [[String: Any]] = try images.map {
                    ["type": "image", "source": ["type": "base64", "media_type": try CoachInferenceInput.imageMIME($0), "data": $0.base64EncodedString()]]
                }
                if !text.isEmpty { content.append(["type": "text", "text": text]) }
                guard !content.isEmpty else { throw ResponsesClient.Failure.invalidInput }
                messages.append(["role": role.rawValue, "content": content])
            case let .priorOutput(data):
                messages.append(["role": "assistant", "content": try KeyServiceWire.kept(data, "claude")])
            case let .functionOutput(callID, output):
                let result: [String: Any] = ["type": "tool_result", "tool_use_id": callID, "content": output]
                // Results of one assistant turn must share a single user message.
                if let last = messages.last, last["role"] as? String == "user", let results = last["content"] as? [[String: Any]],
                   results.allSatisfy({ $0["type"] as? String == "tool_result" }) {
                    messages[messages.count - 1]["content"] = results + [result]
                } else { messages.append(["role": "user", "content": [result]]) }
            }
        }
        var payload: [String: Any] = ["model": model, "max_tokens": 16000, "messages": messages, "cache_control": ["type": "ephemeral"]]
        if !system.isEmpty { payload["system"] = system }
        let tools = try KeyServiceWire.functions(toolNamespace).map { ["name": $0.name, "description": $0.description, "input_schema": $0.parameters] as [String: Any] }
        if !tools.isEmpty { payload["tools"] = tools }
        return try KeyServiceWire.serialized(payload)
    }

    static func result(_ reply: Data) throws -> CoachInferenceResult {
        guard let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
              let model = object["model"] as? String, let content = object["content"] as? [[String: Any]] else { throw ResponsesClient.Failure.malformedResponse }
        switch object["stop_reason"] as? String {
        case "refusal": return CoachInferenceResult(model: model, text: KeyServiceWire.refusal, calls: [], outputItems: [])
        case "max_tokens": throw ResponsesClient.Failure.incompleteResponse
        default: break
        }
        let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        let calls = try content.filter { $0["type"] as? String == "tool_use" }.map { block in
            guard let id = block["id"] as? String, let name = block["name"] as? String, let input = block["input"] as? [String: Any],
                  let arguments = String(data: try JSONSerialization.data(withJSONObject: input, options: .sortedKeys), encoding: .utf8) else { throw ResponsesClient.Failure.malformedResponse }
            return CoachToolCall(id: id, callID: id, name: name, namespace: CoachTools.namespace, arguments: arguments)
        }
        guard !calls.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ResponsesClient.Failure.malformedResponse }
        // Thinking blocks ride along untouched: Claude rejects a tool loop whose earlier turn was edited.
        return CoachInferenceResult(model: model, text: text, calls: calls, outputItems: try KeyServiceWire.keep(content, "claude"))
    }
}
