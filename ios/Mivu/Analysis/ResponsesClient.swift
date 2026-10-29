import Foundation
import CoreFoundation

struct AvailableModel: Equatable, Sendable {
    let slug: String
    let displayName: String
}

// Diagnostic text is built only from local classifications and finite provider allowlists.
struct ResponseFailureDiagnostic: Equatable, Sendable {
    struct StreamCounts: Equatable, Sendable {
        var doneItems = 0, doneMessages = 0, doneFunctions = 0, doneReasoning = 0
        var textDeltas = 0
        var terminalItems = 0, terminalMessages = 0, terminalFunctions = 0, terminalReasoning = 0, terminalRefusals = 0
        var summary: String {
            "done: \(doneItems) (message/function/reasoning \(doneMessages)/\(doneFunctions)/\(doneReasoning)) · deltas: \(textDeltas) · terminal: \(terminalItems) (message/function/reasoning/refusal \(terminalMessages)/\(terminalFunctions)/\(terminalReasoning)/\(terminalRefusals))"
        }
    }
    enum ParserReason: String, Sendable {
        case eventUTF8, eventJSON, eventType, eventNameMismatch, trailingEvent, deltaSchema
        case completedEnvelope, completedStatus, completedError, completedModel, completedOutput
        case outputType, contentSchema, functionSchema, emptyOutput
        case doneItemSchema, doneItemIndex, doneItemConflict
    }
    let classification: String
    let httpStatus: Int?
    let providerCode: String?
    let parameter: String?
    let bodyShape: String?
    let parserReason: ParserReason?
    let streamCounts: StreamCounts?
    var summary: String {
        ([classification] + (httpStatus.map { ["HTTP \($0)"] } ?? []))
            .joined(separator: " · ")
            + [providerCode, parameter.map { "parameter: " + $0 }, bodyShape.map { "body: " + $0 }, parserReason.map { "parser: " + $0.rawValue }, streamCounts?.summary]
                .compactMap { $0 }.map { " · " + $0 }.joined()
    }

    init(error: any Error, httpStatus: Int? = nil, object: [String: Any]? = nil, bodyShape: String? = nil, parserReason: ParserReason? = nil, streamCounts: StreamCounts? = nil) {
        self.httpStatus = httpStatus
        self.bodyShape = bodyShape
        self.parserReason = parserReason
        self.streamCounts = streamCounts
        if let failure = error as? ResponsesClient.Failure {
            classification = switch failure {
            case .unauthorized: "unauthorized"
            case .forbidden: "forbidden"
            case .quotaReached: "quotaReached"
            case .usageUnavailable: "usageUnavailable"
            case .http: "http"
            case .malformedResponse: "malformedResponse"
            case .incompleteResponse: "incompleteResponse"
            case .responseFailed: "responseFailed"
            case .limitExceeded: "limitExceeded"
            case .invalidInput: "invalidInput"
            }
        } else if let error = error as? URLError {
            classification = switch error.code {
            case .timedOut: "transportTimedOut"
            case .cannotFindHost: "transportCannotFindHost"
            case .cannotConnectToHost: "transportCannotConnectToHost"
            case .networkConnectionLost: "transportConnectionLost"
            case .dnsLookupFailed: "transportDNSLookupFailed"
            case .notConnectedToInternet: "transportOffline"
            case .cancelled: "transportCancelled"
            default: "transportOther(\(error.code.rawValue))"
            }
        } else { classification = error is CancellationError ? "cancelled" : "localFailure" }
        let errorObject = object?["error"] as? [String: Any] ?? object
        let code = errorObject?["code"] as? String
        let codes: Set<String> = ["subscription_sharing_user_not_eligible", "subscription_sharing_usage_limit_exceeded",
            "subscription_sharing_usage_unavailable", "subscription_sharing_unsupported_capability",
            "subscription_sharing_route_not_supported", "subscription_sharing_invalid_user", "subscription_sharing_user_unavailable",
            "chatpass_v2_scope_not_authorized", "chatpass_v2_invalid_authorization_context",
            "unsupported_parameter", "invalid_value", "invalid_json", "model_not_found", "rate_limit_exceeded", "insufficient_quota", "server_error"]
        providerCode = code.flatMap { codes.contains($0) ? $0 : nil }
        let param = errorObject?["param"] as? String
        let parameters = ["model", "input", "tools", "store", "stream", "prompt", "instructions", "reasoning", "service_tier",
            "previous_response_id", "conversation", "text", "temperature", "top_p", "max_output_tokens", "include", "parallel_tool_calls"]
        parameter = param.flatMap { value in
            parameters.first { value == $0 || value.hasPrefix($0 + ".") || value.hasPrefix($0 + "[") }
        }
    }
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
        let (bytes, response) = try await session.bytes(for: request, delegate: RejectAuthRedirects())
        defer { bytes.task.cancel() }
        var diagnostic: ResponseFailureDiagnostic?
        try await check(response, bytes: bytes, diagnostic: &diagnostic)
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

    func run(model: String, text: String, image: Data?, accessToken: String,
             diagnostic: (@Sendable (ResponseFailureDiagnostic) async -> Void)? = nil) async throws -> ProbeResult {
        let result = try await respond(model: model, input: [.message(role: .user, text: text, images: image.map { [$0] } ?? [])], toolNamespace: nil, accessToken: accessToken, diagnostic: diagnostic)
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.malformedResponse }
        return ProbeResult(model: result.model, outputText: result.text)
    }

    func respond(model: String, input: [CoachInferenceInput], toolNamespace: Data?, accessToken: String,
                 diagnostic: (@Sendable (ResponseFailureDiagnostic) async -> Void)? = nil) async throws -> CoachInferenceResult {
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
                  let tools = namespace["tools"] as? [[String: Any]], !tools.isEmpty, tools.count <= 40 else { throw Failure.invalidInput }
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
        var stream = ResponseEventStream()
        var failureDiagnostic: ResponseFailureDiagnostic?
        var httpStatus: Int?
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: RejectAuthRedirects())
            defer { bytes.task.cancel() }
            httpStatus = (response as? HTTPURLResponse)?.statusCode
            try await check(response, bytes: bytes, diagnostic: &failureDiagnostic, captureDiagnostic: diagnostic != nil)
            for try await byte in bytes { try stream.append(byte) }
            return try stream.finishInference()
        } catch {
            let metadata = failureDiagnostic ?? stream.failureDiagnostic ?? ResponseFailureDiagnostic(error: error, httpStatus: httpStatus)
            await diagnostic?(metadata)
            throw error
        }
    }

    private func request(path: String, accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty, !accessToken.contains(where: { $0.isWhitespace }) else { throw Failure.invalidInput }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/" + path)!)
        request.timeoutInterval = 60
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        return request
    }

    private func check(_ response: URLResponse, bytes: URLSession.AsyncBytes, diagnostic: inout ResponseFailureDiagnostic?, captureDiagnostic: Bool = false) async throws {
        guard let response = response as? HTTPURLResponse else { throw Failure.malformedResponse }
        let failure: Failure
        switch response.statusCode {
        case 200: return
        case 401: failure = .unauthorized
        case 403: failure = .forbidden
        case 429: failure = .quotaReached
        default: failure = .http(status: response.statusCode)
        }
        diagnostic = ResponseFailureDiagnostic(error: failure, httpStatus: response.statusCode)
        guard captureDiagnostic || response.statusCode == 503 else { throw failure }
        var body = Data()
        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                guard body.count < 65_536 else {
                    diagnostic = ResponseFailureDiagnostic(error: failure, httpStatus: response.statusCode, bodyShape: "oversized")
                    throw failure
                }
                body.append(byte)
            }
        } catch {
            // Keep the existing status failure even when an admission body cannot be read.
            if response.statusCode == 503 { throw error }
            throw failure
        }
        let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let shape = body.isEmpty ? "empty" : object == nil ? "nonJSON" : object?["error"] != nil ? "error" : object?["detail"] != nil ? "detail" : "json"
        var classified = failure
        if response.statusCode == 503 {
            let code = (object?["error"] as? [String: Any])?["code"] as? String
            switch code {
            case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable": classified = .usageUnavailable
            default: break
            }
        }
        diagnostic = ResponseFailureDiagnostic(error: classified, httpStatus: response.statusCode, object: object, bodyShape: shape)
        throw classified
    }
}

// Parse bytes before decoding UTF-8 so network chunk boundaries cannot corrupt text.
struct ResponseEventStream {
    private(set) var failureDiagnostic: ResponseFailureDiagnostic?
    private var streamCounts = ResponseFailureDiagnostic.StreamCounts()
    private var doneItems: [Int: Data] = [:]
    private var doneItemIDs = Set<String>()
    private var doneItemBytes = 0
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
        guard let text = String(data: line, encoding: .utf8) else { throw malformed(.eventUTF8) }
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
        guard let object = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else { throw malformed(.eventJSON) }
        guard let type = object["type"] as? String, !type.isEmpty else { throw malformed(.eventType) }
        guard eventName == nil || eventName == type else { throw malformed(.eventNameMismatch) }
        if type == "error" || type == "response.failed" {
            let response = object["response"] as? [String: Any]
            let error = response?["error"] as? [String: Any] ?? object["error"] as? [String: Any]
            let code = error?["code"] as? String ?? object["code"] as? String
            let failure: ResponsesClient.Failure = switch code {
            case "subscription_sharing_usage_limit_exceeded": .quotaReached
            case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable": .usageUnavailable
            default: .responseFailed
            }
            failureDiagnostic = ResponseFailureDiagnostic(error: failure, httpStatus: 200, object: error ?? object, bodyShape: "streamError")
            throw failure
        }
        if type == "response.incomplete" { throw ResponsesClient.Failure.incompleteResponse }
        guard completed == nil else { throw malformed(.trailingEvent) }
        if type == "response.output_text.delta", !(object["delta"] is String) { throw malformed(.deltaSchema) }
        if type == "response.output_text.delta" { streamCounts.textDeltas += 1 }
        if type == "response.output_item.done" {
            streamCounts.doneItems += 1
            let item = object["item"] as? [String: Any]
            switch item?["type"] as? String {
            case "message": streamCounts.doneMessages += 1
            case "function_call": streamCounts.doneFunctions += 1
            case "reasoning": streamCounts.doneReasoning += 1
            default: break
            }
            guard let rawIndex = object["output_index"] as? NSNumber,
                  CFGetTypeID(rawIndex) != CFBooleanGetTypeID(),
                  let index = object["output_index"] as? Int, (0..<128).contains(index) else { throw malformed(.doneItemIndex) }
            guard let item, ["message", "reasoning", "function_call"].contains(item["type"] as? String ?? ""),
                  let id = item["id"] as? String, !id.isEmpty, id.utf8.count <= 256,
                  item["status"] == nil || item["status"] as? String == "completed" else { throw malformed(.doneItemSchema) }
            guard doneItems[index] == nil, doneItemIDs.insert(id).inserted else { throw malformed(.doneItemConflict) }
            let data = try JSONSerialization.data(withJSONObject: item, options: .sortedKeys)
            guard data.count <= 1_048_576, doneItemBytes + data.count <= 8_388_608 else { throw ResponsesClient.Failure.limitExceeded }
            doneItems[index] = data
            doneItemBytes += data.count
        }
        guard type == "response.completed" else { return }
        guard let response = object["response"] as? [String: Any] else { throw malformed(.completedEnvelope) }
        guard response["status"] as? String == "completed" else { throw malformed(.completedStatus) }
        guard response["error"] == nil || response["error"] is NSNull else { throw malformed(.completedError) }
        guard let model = response["model"] as? String, !model.isEmpty else { throw malformed(.completedModel) }
        guard var output = response["output"] as? [[String: Any]], output.count <= 128 else { throw malformed(.completedOutput) }
        streamCounts.terminalItems = output.count
        for item in output {
            switch item["type"] as? String {
            case "message": streamCounts.terminalMessages += 1
            case "function_call": streamCounts.terminalFunctions += 1
            case "reasoning": streamCounts.terminalReasoning += 1
            default: break
            }
            if let parts = item["content"] as? [[String: Any]] {
                streamCounts.terminalRefusals += parts.filter { $0["type"] as? String == "refusal" }.count
            }
        }
        if output.isEmpty, !doneItems.isEmpty {
            guard doneItems.keys.sorted() == Array(0..<doneItems.count) else { throw malformed(.doneItemIndex) }
            // Some direct streams carry final items only in done events, with an empty terminal output.
            output = try (0..<doneItems.count).map { index in
                guard let item = try JSONSerialization.jsonObject(with: doneItems[index]!) as? [String: Any] else { throw malformed(.doneItemSchema) }
                return item
            }
        } else {
            for (index, data) in doneItems {
                guard index < output.count,
                      let item = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      item as NSDictionary == output[index] as NSDictionary else { throw malformed(.doneItemConflict) }
            }
        }
        guard output.allSatisfy({ item in
            ["message", "reasoning", "function_call"].contains(item["type"] as? String ?? "")
        }) else { throw malformed(.outputType) }
        var texts: [String] = []
        for item in output where item["type"] as? String == "message" {
            guard let content = item["content"] as? [[String: Any]] else { throw malformed(.contentSchema) }
            for part in content where part["type"] as? String == "output_text" {
                guard let text = part["text"] as? String else { throw malformed(.contentSchema) }
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
                  (try? JSONSerialization.jsonObject(with: data)) is [String: Any], calls.count < 16 else { throw malformed(.functionSchema) }
            calls.append(CoachToolCall(id: id, callID: callID, name: name, namespace: item["namespace"] as? String, arguments: arguments))
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !calls.isEmpty else { throw malformed(.emptyOutput) }
        completed = CoachInferenceResult(model: model, text: text, calls: calls, outputItems: try output.map { try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) })
    }

    private mutating func malformed(_ reason: ResponseFailureDiagnostic.ParserReason) -> ResponsesClient.Failure {
        failureDiagnostic = ResponseFailureDiagnostic(error: ResponsesClient.Failure.malformedResponse, httpStatus: 200, parserReason: reason, streamCounts: streamCounts)
        return .malformedResponse
    }
}
enum SyntheticConnectionProbe {
    static let prompt = "Synthetic connection test. Briefly describe the image."
    // A generated 32x32 orange square on a neutral background, containing no personal data.
    static let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAM0lEQVR4nGN4/foZTRHDqAWjFgxhCz70uJGERi0YtWDUglELRi0YnhZQC41aMGrBELAAAK8p9oiZspxQAAAAAElFTkSuQmCC")!
}
