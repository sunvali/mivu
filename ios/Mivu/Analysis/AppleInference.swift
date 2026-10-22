import Foundation
import FoundationModels
import ImageIO

/// Apple Private Cloud Compute behind the same inference boundary as the ChatGPT plan.
@available(iOS 27.0, *)
enum AppleInference {
    static func toolDefinitions(_ namespace: Data) throws -> [Transcript.ToolDefinition] {
        guard let tools = (try JSONSerialization.jsonObject(with: namespace) as? [String: Any])?["tools"] as? [[String: Any]] else {
            throw ResponsesClient.Failure.invalidInput
        }
        return try tools.map { tool in
            guard let name = tool["name"] as? String, let description = tool["description"] as? String,
                  let parameters = tool["parameters"] as? [String: Any] else { throw ResponsesClient.Failure.invalidInput }
            let schema = try JSONSerialization.data(withJSONObject: appleSchema(parameters, title: name))
            return Transcript.ToolDefinition(name: name, description: description,
                                             parameters: try JSONDecoder().decode(GenerationSchema.self, from: schema))
        }
    }

    /// Replays the stateless Coach input as an Apple transcript; prior items use the ChatGPT item shape so both providers replay alike.
    static func transcript(_ input: [CoachInferenceInput], tools: [Transcript.ToolDefinition]) throws -> Transcript {
        var entries: [Transcript.Entry] = []
        var toolNames: [String: String] = [:]
        for item in input {
            let object = try item.object()
            switch item {
            case let .message(role, text, images):
                var segments: [Transcript.Segment] = text.isEmpty ? [] : [.text(.init(content: text))]
                for image in images { segments.append(.attachment(.init(content: .image(try attachment(image))))) }
                switch role {
                case .developer: entries.append(.instructions(.init(segments: segments, toolDefinitions: tools)))
                case .assistant: entries.append(.response(.init(assetIDs: [], segments: segments)))
                case .user:
                    if case .prompt(var prompt) = entries.last {
                        prompt.segments += segments
                        entries[entries.count - 1] = .prompt(prompt)
                    } else { entries.append(.prompt(.init(segments: segments))) }
                }
            case .priorOutput:
                switch object["type"] as? String {
                case "function_call":
                    guard let callID = object["call_id"] as? String, let name = object["name"] as? String,
                          let arguments = object["arguments"] as? String else { throw ResponsesClient.Failure.invalidInput }
                    let call = Transcript.ToolCall(id: callID, toolName: name, arguments: try GeneratedContent(json: arguments))
                    toolNames[callID] = name
                    if case .toolCalls(let calls) = entries.last {
                        entries[entries.count - 1] = .toolCalls(.init(id: calls.id, Array(calls) + [call]))
                    } else { entries.append(.toolCalls(.init([call]))) }
                case "message":
                    let text = (object["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
                    entries.append(.response(.init(assetIDs: [], segments: [.text(.init(content: text))])))
                default: break // Reasoning items carry nothing the Apple model can read.
                }
            case let .functionOutput(callID, output):
                guard let name = toolNames[callID] else { throw ResponsesClient.Failure.invalidInput }
                entries.append(.toolOutput(.init(id: callID, toolName: name, segments: [.text(.init(content: output))])))
            }
        }
        return Transcript(entries: entries)
    }

    private static func attachment(_ data: Data) throws -> Transcript.ImageAttachment {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ResponsesClient.Failure.invalidInput }
        return Transcript.ImageAttachment(image)
    }

    // CoachTools emits strict JSON Schema; FoundationModels wants optional instead of null and titled, ordered objects.
    // shortcut: the decoder drops integer enums, so CoachTools.parse alone enforces them; revisit if Apple keeps them.
    private static func appleSchema(_ source: [String: Any], title: String) -> [String: Any] {
        var schema = source
        if let types = source["type"] as? [String] { schema["type"] = types.first { $0 != "null" } }
        if let values = source["enum"] as? [Any] { schema["enum"] = values.filter { !($0 is NSNull) } }
        if let items = source["items"] as? [String: Any] { schema["items"] = appleSchema(items, title: title + ".items") }
        if let properties = source["properties"] as? [String: [String: Any]] {
            let keys = properties.keys.sorted()
            schema["properties"] = properties.reduce(into: [String: Any]()) { $0[$1.key] = appleSchema($1.value, title: title + "." + $1.key) }
            schema["required"] = keys.filter { !((properties[$0]?["type"] as? [String])?.contains("null") ?? false) }
            schema["title"] = title
            schema["x-order"] = keys
        }
        return schema
    }
}
