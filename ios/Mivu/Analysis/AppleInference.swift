import Foundation
import FoundationModels

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
