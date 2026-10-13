import Foundation

struct AvailableModel: Equatable, Sendable {
    let slug: String
    let displayName: String
}

struct ResponsesClient: Sendable {
    enum Failure: Error, Equatable {
        case unauthorized, forbidden, quotaReached, usageUnavailable
        case http(status: Int)
        case malformedResponse, incompleteResponse, responseFailed, limitExceeded, invalidInput
    }

    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func models(accessToken: String) async throws -> [AvailableModel] {
        let request = try request(path: "models", accessToken: accessToken)
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        try await check(response, bytes: bytes)
        var body = Data()
        for try await byte in bytes {
            guard body.count < 1_048_576 else { throw Failure.limitExceeded }
            body.append(byte)
        }
        struct Catalog: Decodable {
            struct Model: Decodable {
                let slug: String
                let display_name: String
                let visibility: String
            }
            let models: [Model]
        }
        guard let catalog = try? JSONDecoder().decode(Catalog.self, from: body),
              catalog.models.allSatisfy({ !$0.slug.isEmpty && !$0.display_name.isEmpty }) else {
            throw Failure.malformedResponse
        }
        return catalog.models.filter { $0.visibility == "list" }.map {
            AvailableModel(slug: $0.slug, displayName: $0.display_name)
        }
    }

    func run(model: String, text: String, image: Data?, accessToken: String) async throws -> ProbeResult {
        let result = try await respond(model: model, input: [.message(role: .user, text: text, images: image.map { [$0] } ?? [])], toolNamespace: nil, accessToken: accessToken)
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.malformedResponse }
        return ProbeResult(model: result.model, outputText: result.text)
    }

    func respond(model: String, input: [CoachInferenceInput], toolNamespace: Data?, accessToken: String) async throws -> CoachInferenceResult {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, model.utf8.count <= 256,
              !input.isEmpty, input.count <= 128 else { throw Failure.invalidInput }
        // Bound the aggregate before allocating base64 strings or serialized history.
        var inputBytes = 0
        for item in input {
            switch item {
            case let .message(_, text, images):
                guard text.utf8.count <= 65_536, images.count <= 8 else { throw Failure.invalidInput }
                inputBytes += text.utf8.count
                for image in images {
                    guard image.count <= 5_242_880 else { throw Failure.invalidInput }
                    inputBytes += ((image.count + 2) / 3) * 4
                    guard inputBytes <= 8_388_608 else { throw Failure.invalidInput }
                }
            case let .priorOutput(data): inputBytes += data.count
            case let .functionOutput(callID, output): inputBytes += callID.utf8.count + output.utf8.count
            }
            guard inputBytes <= 8_388_608 else { throw Failure.invalidInput }
        }
        var payload: [String: Any] = ["model": model, "input": try input.map { try $0.object() }, "store": false, "stream": true]
        if let toolNamespace {
            guard toolNamespace.count <= 65_536,
                  let namespace = try? JSONSerialization.jsonObject(with: toolNamespace) as? [String: Any],
                  namespace["type"] as? String == "namespace",
                  Set(namespace.keys).isSubset(of: ["type", "name", "description", "tools"]),
                  let name = namespace["name"] as? String, !name.isEmpty, name.utf8.count <= 256,
                  namespace["description"] == nil || namespace["description"] is String,
                  let tools = namespace["tools"] as? [[String: Any]], !tools.isEmpty, tools.count <= 16 else { throw Failure.invalidInput }
            var names = Set<String>()
            for tool in tools {
                guard tool["type"] as? String == "function",
                      Set(tool.keys).isSubset(of: ["type", "name", "description", "parameters", "strict"]),
                      let name = tool["name"] as? String, !name.isEmpty, name.utf8.count <= 256,
                      tool["description"] == nil || tool["description"] is String,
                      tool["strict"] == nil || tool["strict"] is Bool,
                      names.insert(name).inserted, let parameters = tool["parameters"] as? [String: Any],
                      parameters["type"] as? String == "object" else { throw Failure.invalidInput }
            }
            payload["tools"] = [namespace]
        }
        var request = try request(path: "responses", accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let body = try JSONSerialization.data(withJSONObject: payload)
        guard body.count <= 8_388_608 else { throw Failure.invalidInput }
        request.httpBody = body
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        try await check(response, bytes: bytes)
        var stream = ResponseEventStream()
        for try await byte in bytes { try stream.append(byte) }
        return try stream.finishInference()
    }

    private func request(path: String, accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty, !accessToken.contains(where: { $0.isWhitespace }) else { throw Failure.invalidInput }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/" + path)!)
        request.timeoutInterval = 60
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        return request
    }

    private func check(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let response = response as? HTTPURLResponse else { throw Failure.malformedResponse }
        switch response.statusCode {
        case 200: return
        case 401: throw Failure.unauthorized
        case 403: throw Failure.forbidden
        case 429: throw Failure.quotaReached
        case 503:
            var body = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard body.count < 65_536 else { throw Failure.http(status: 503) }
                body.append(byte)
            }
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            let code = (object?["error"] as? [String: Any])?["code"] as? String
            switch code {
            case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable": throw Failure.usageUnavailable
            default: throw Failure.http(status: 503)
            }
        default: throw Failure.http(status: response.statusCode)
        }
    }
}

// Parse bytes before decoding UTF-8 so network chunk boundaries cannot corrupt text.
struct ResponseEventStream {
    private var line = Data()
    private var eventData = Data()
    private var eventName: String?
    private var skipLF = false
    private var totalBytes = 0
    private var completed: CoachInferenceResult?

    mutating func append(_ data: Data) throws {
        for byte in data { try append(byte) }
    }

    mutating func append(_ byte: UInt8) throws {
        totalBytes += 1
        guard totalBytes <= 8_388_608 else { throw ResponsesClient.Failure.limitExceeded }
        if skipLF { skipLF = false; if byte == 10 { return } }
        if byte == 10 || byte == 13 {
            try processLine()
            line.removeAll(keepingCapacity: true)
            skipLF = byte == 13
        } else {
            guard line.count < 1_048_576 else { throw ResponsesClient.Failure.limitExceeded }
            line.append(byte)
        }
    }

    func finish() throws -> ProbeResult {
        let result = try finishInference()
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ResponsesClient.Failure.malformedResponse }
        return ProbeResult(model: result.model, outputText: result.text)
    }

    func finishInference() throws -> CoachInferenceResult {
        guard line.isEmpty, eventData.isEmpty, eventName == nil, let completed else {
            throw ResponsesClient.Failure.incompleteResponse
        }
        return completed
    }

    private mutating func processLine() throws {
        guard let text = String(data: line, encoding: .utf8) else { throw ResponsesClient.Failure.malformedResponse }
        if text.isEmpty {
            if !eventData.isEmpty { try processEvent() }
            eventData.removeAll(keepingCapacity: true)
            eventName = nil
            return
        }
        if text.hasPrefix(":") { return }
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        var value = parts.count == 2 ? String(parts[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        switch parts[0] {
        case "data":
            guard eventData.count + value.utf8.count + 1 <= 1_048_576 else { throw ResponsesClient.Failure.limitExceeded }
            eventData.append(contentsOf: value.utf8)
            eventData.append(10)
        case "event": eventName = value
        default: break
        }
    }

    private mutating func processEvent() throws {
        if eventData == Data("[DONE]\n".utf8) {
            guard completed != nil else { throw ResponsesClient.Failure.incompleteResponse }
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
              let type = object["type"] as? String, !type.isEmpty,
              eventName == nil || eventName == type else { throw ResponsesClient.Failure.malformedResponse }
        if type == "error" || type == "response.failed" {
            let response = object["response"] as? [String: Any]
            let error = response?["error"] as? [String: Any] ?? object["error"] as? [String: Any]
            let code = error?["code"] as? String ?? object["code"] as? String
            switch code {
            case "subscription_sharing_usage_limit_exceeded": throw ResponsesClient.Failure.quotaReached
            case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable": throw ResponsesClient.Failure.usageUnavailable
            default: throw ResponsesClient.Failure.responseFailed
            }
        }
        if type == "response.incomplete" { throw ResponsesClient.Failure.incompleteResponse }
        guard completed == nil else { throw ResponsesClient.Failure.malformedResponse }
        if type == "response.output_text.delta", !(object["delta"] is String) { throw ResponsesClient.Failure.malformedResponse }
        guard type == "response.completed" else { return }
        guard let response = object["response"] as? [String: Any],
              response["status"] as? String == "completed",
              response["error"] == nil || response["error"] is NSNull,
              let model = response["model"] as? String, !model.isEmpty,
              let output = response["output"] as? [[String: Any]], output.count <= 128 else { throw ResponsesClient.Failure.malformedResponse }
        guard output.allSatisfy({ item in
            ["message", "reasoning", "function_call"].contains(item["type"] as? String ?? "")
        }) else { throw ResponsesClient.Failure.malformedResponse }
        var texts: [String] = []
        for item in output where item["type"] as? String == "message" {
            guard let content = item["content"] as? [[String: Any]] else { throw ResponsesClient.Failure.malformedResponse }
            for part in content where part["type"] as? String == "output_text" {
                guard let text = part["text"] as? String else { throw ResponsesClient.Failure.malformedResponse }
                texts.append(text)
            }
        }
        let text = texts.joined(separator: "\n")
        guard text.utf8.count <= 65_536 else { throw ResponsesClient.Failure.limitExceeded }
        var calls: [CoachToolCall] = []
        var ids = Set<String>()
        var callIDs = Set<String>()
        for item in output where item["type"] as? String == "function_call" {
            guard let id = item["id"] as? String, !id.isEmpty, id.utf8.count <= 256,
                  let callID = item["call_id"] as? String, !callID.isEmpty, callID.utf8.count <= 256,
                  ids.insert(id).inserted, callIDs.insert(callID).inserted,
                  let name = item["name"] as? String, !name.isEmpty, name.utf8.count <= 256,
                  item["namespace"] == nil || ((item["namespace"] as? String).map { !$0.isEmpty && $0.utf8.count <= 256 } ?? false),
                  item["status"] == nil || item["status"] as? String == "completed",
                  let arguments = item["arguments"] as? String, arguments.utf8.count <= 65_536,
                  let data = arguments.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data)) is [String: Any], calls.count < 16 else { throw ResponsesClient.Failure.malformedResponse }
            calls.append(CoachToolCall(id: id, callID: callID, name: name, namespace: item["namespace"] as? String, arguments: arguments))
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !calls.isEmpty else { throw ResponsesClient.Failure.malformedResponse }
        completed = CoachInferenceResult(model: model, text: text, calls: calls, outputItems: try output.map { try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) })
    }
}
enum SyntheticConnectionProbe {
    static let prompt = "Synthetic connection test. Briefly describe the image."
    // A generated 32x32 orange square on a neutral background, containing no personal data.
    static let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAM0lEQVR4nGN4/foZTRHDqAWjFgxhCz70uJGERi0YtWDUglELRi0YnhZQC41aMGrBELAAAK8p9oiZspxQAAAAAElFTkSuQmCC")!
}
