import Foundation
import FoundationModels
import ImageIO
import Synchronization

/// Apple Intelligence behind the same inference boundary as the ChatGPT plan.
@available(iOS 27.0, *)
enum AppleInference {
    static let continuation = "Continue the captured turn using the tool results above."

    /// One stateless step: Mivu tools only report the calls the model chose; CoachEngine executes them.
    static func respond(_ input: [CoachInferenceInput], namespace: Data?, model: some LanguageModel = SystemLanguageModel.default) async throws -> CoachInferenceResult {
        let definitions = try namespace.map(toolDefinitions) ?? []
        var entries = Array(try transcript(input, tools: definitions))
        // Every respond needs a prompt: the trailing capture is one; after tool outputs a fixed continuation stands in.
        // shortcut: the continuation adds a synthetic user line per step; drop it if FoundationModels can resume without a prompt.
        var segments = [Transcript.Segment.text(.init(content: continuation))]
        if case .prompt(let last)? = entries.last { segments = last.segments; entries.removeLast() }
        let capture = Capture()
        let session = LanguageModelSession(model: model, tools: definitions.map { CaptureTool(definition: $0, capture: capture) },
                                           transcript: Transcript(entries: entries))
        capture.session.withLock { $0 = session }
        do {
            let response = try await session.respond {
                for segment in segments {
                    if case .attachment(let attachment) = segment, case .image(let image) = attachment.content { Attachment(image.cgImage) }
                    else if case .text(let text) = segment { text.content }
                    else { "" }
                }
            }
            return try result(text: response.content, calls: [])
        } catch let error as LanguageModelSession.ToolCallError where error.underlyingError is Captured {
            return try result(text: "", calls: capture.calls.withLock { $0 })
        }
    }

    static func result(text: String, calls: [Transcript.ToolCall]) throws -> CoachInferenceResult {
        let toolCalls = calls.map { CoachToolCall(id: "fc_" + $0.id, callID: $0.id, name: $0.toolName, namespace: CoachTools.namespace, arguments: $0.arguments.jsonString) }
        let items: [[String: Any]] = toolCalls.isEmpty
            ? [["type": "message", "role": "assistant", "content": [["type": "output_text", "text": text]]]]
            : toolCalls.map { ["type": "function_call", "id": $0.id, "call_id": $0.callID, "name": $0.name, "namespace": CoachTools.namespace,
                               "arguments": $0.arguments, "status": "completed"] }
        return CoachInferenceResult(model: "apple-intelligence", text: text, calls: toolCalls,
                                    outputItems: try items.map { try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) })
    }

    private struct Captured: Error {}
    private final class Capture: Sendable {
        let session = Mutex<LanguageModelSession?>(nil)
        let calls = Mutex<[Transcript.ToolCall]>([])
    }
    private struct CaptureTool: Tool {
        let definition: Transcript.ToolDefinition
        let capture: Capture
        var name: String { definition.name }
        var description: String { definition.description }
        var parameters: GenerationSchema { definition.parameters }
        func call(arguments: GeneratedContent) async throws -> String {
            // While a tool runs, the transcript's last entry is the whole parallel batch; a throw rolls it back.
            if case .toolCalls(let calls)? = capture.session.withLock({ $0?.transcript.last }) { capture.calls.withLock { $0 = Array(calls) } }
            throw Captured()
        }
    }

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
                case .developer where entries.isEmpty: entries.append(.instructions(.init(segments: segments, toolDefinitions: tools)))
                case .assistant: entries.append(.response(.init(assetIDs: [], segments: segments)))
                case .user, .developer: // Instructions lead the transcript, so per-turn context joins the captured prompt.
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
