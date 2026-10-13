import Foundation
import ImageIO
import Testing
@testable import Mivu

@Suite(.serialized)
struct ResponsesClientTests {
    @Test func acceptsJPEGInput() async throws {
        let capture = RequestCapture()
        let client = ResponsesClient(session: sessionReturning(status: 200, body: completed(), capture: capture))
        _ = try await client.run(model: "fixture-model", text: "Synthetic", image: Data([0xff, 0xd8, 0xff, 0xe0]), accessToken: "fixture-token")
        let payload = try #require(capture.request?.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let input = try #require(object["input"] as? [[String: Any]])
        let content = try #require(input[0]["content"] as? [[String: String]])
        #expect(content[1]["image_url"] == "data:image/jpeg;base64,/9j/4A==")
    }

    @Test func toolOnlyCompletionPreservesCallsReasoningAndUTF8() throws {
        let items: [[String: Any]] = [
            ["type": "reasoning", "id": "reason", "encrypted_content": "synthetic", "summary": []],
            toolCall(id: "one", callID: "first", arguments: #"{"text":"שלום"}"#),
            toolCall(id: "two", callID: "second", arguments: #"{"quantity":2}"#)
        ]
        let bytes = toolCompletion(items)
        for split in 0...bytes.count {
            var stream = ResponseEventStream()
            try stream.append(bytes.prefix(split))
            try stream.append(bytes.dropFirst(split))
            let result = try stream.finishInference()
            #expect(result.text.isEmpty)
            #expect(result.calls.map(\.callID) == ["first", "second"])
            #expect(result.calls[0].namespace == "diary")
            #expect(result.calls[0].arguments == #"{"text":"שלום"}"#)
            #expect(try result.outputItems.map { try JSONSerialization.jsonObject(with: $0) as! NSDictionary } == items.map { $0 as NSDictionary })
        }
    }

    @Test func sendsStatelessContinuationAndLocalNamespace() async throws {
        let capture = RequestCapture()
        let output = toolCall(id: "one", callID: "first", arguments: "{}")
        let outputData = try JSONSerialization.data(withJSONObject: output)
        let namespace = Data(#"{"type":"namespace","name":"diary","tools":[{"type":"function","name":"record","parameters":{"type":"object","properties":{},"additionalProperties":false}}]}"#.utf8)
        let result = try await ResponsesClient(session: sessionReturning(status: 200, body: completed(), capture: capture)).respond(
            model: "fixture-model", input: [.message(role: .developer, text: "Use saved facts"), .message(role: .user, text: "Synthetic", images: [SyntheticConnectionProbe.image]), .priorOutput(outputData), .functionOutput(callID: "first", output: #"{"saved":true}"#), .message(role: .assistant, text: "Earlier reply")], toolNamespace: namespace, accessToken: "fixture-token")
        #expect(result.text == "Synthetic output שלום")
        let body = try #require(capture.request?.httpBody)
        let object = try JSONSerialization.jsonObject(with: body)
        let payload = try #require(object as? [String: Any])
        #expect(Set(payload.keys) == ["model", "input", "tools", "store", "stream"])
        #expect(payload["store"] as? Bool == false && payload["stream"] as? Bool == true)
        let input = try #require(payload["input"] as? [[String: Any]])
        #expect(input[0]["role"] as? String == "developer")
        #expect(input[2] as NSDictionary == output as NSDictionary)
        #expect(input[3]["type"] as? String == "function_call_output")
        #expect(input[3]["call_id"] as? String == "first")
    }

    @Test func rejectsInvalidArgumentsDuplicateCallsAndOversizedArguments() throws {
        for items in [
            [toolCall(id: "one", callID: "first", arguments: "[]")],
            [toolCall(id: "one", callID: "first", arguments: "{bad}")],
            [toolCall(id: "one", callID: "first", arguments: #"{"text":""# + String(repeating: "a", count: 65_536) + #""}"#)],
            [toolCall(id: "one", callID: "first", arguments: "{}"), toolCall(id: "two", callID: "first", arguments: "{}")],
            [toolCall(id: "one", callID: "first", arguments: "{}"), toolCall(id: "one", callID: "second", arguments: "{}")]
        ] {
            var stream = ResponseEventStream()
            #expect(throws: ResponsesClient.Failure.malformedResponse) { try stream.append(toolCompletion(items)) }
        }
    }

    @Test func partialToolCallCannotCompleteAndQuotaDiscardsIt() throws {
        let partial = event(["type": "response.output_item.added", "item": toolCall(id: "one", callID: "first", arguments: "{}")])
        var stream = ResponseEventStream()
        try stream.append(partial)
        #expect(throws: ResponsesClient.Failure.incompleteResponse) { try stream.finishInference() }
        #expect(throws: ResponsesClient.Failure.quotaReached) { try stream.append(event(["type": "error", "code": "subscription_sharing_usage_limit_exceeded"])) }
    }

    @Test func rejectsInvalidStructuredInputBeforeNetwork() async {
        let capture = RequestCapture()
        let client = ResponsesClient(session: sessionReturning(status: 200, body: completed(), capture: capture))
        let invalidInputs: [[CoachInferenceInput]] = [
            [.message(role: .user, text: "", images: [Data([255, 216])])],
            [.message(role: .developer, text: "Synthetic", images: [SyntheticConnectionProbe.image])],
            [.priorOutput(Data(#"{"type":"computer_call"}"#.utf8))],
            [.functionOutput(callID: "", output: "{}")],
            [.message(role: .user, text: String(repeating: "x", count: 65_537))]
        ]
        for input in invalidInputs {
            await #expect(throws: ResponsesClient.Failure.invalidInput) { try await client.respond(model: "fixture-model", input: input, toolNamespace: nil, accessToken: "fixture-token") }
        }
        await #expect(throws: ResponsesClient.Failure.invalidInput) { try await client.respond(model: "fixture-model", input: [.message(role: .user, text: "Synthetic")], toolNamespace: Data(#"{"type":"mcp"}"#.utf8), accessToken: "fixture-token") }
        #expect(capture.request == nil)
    }

    @Test func rejectsAggregateImagesAndHostedOutputItems() async {
        let capture = RequestCapture()
        let client = ResponsesClient(session: sessionReturning(status: 200, body: completed(), capture: capture))
        let image = Data([255, 216, 255, 224]) + Data(repeating: 0, count: 4_000_000)
        await #expect(throws: ResponsesClient.Failure.invalidInput) {
            try await client.respond(model: "fixture-model", input: [.message(role: .user, text: "Synthetic", images: [image, image])], toolNamespace: nil, accessToken: "fixture-token")
        }
        #expect(capture.request == nil)
        var stream = ResponseEventStream()
        #expect(throws: ResponsesClient.Failure.malformedResponse) {
            try stream.append(toolCompletion([["type": "web_search_call", "id": "hosted"], toolCall(id: "one", callID: "first", arguments: "{}")]))
        }
    }

    @Test func syntheticFixtureIsDecodablePNG() throws {
        let source = try #require(CGImageSourceCreateWithData(SyntheticConnectionProbe.image as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 32 && image.height == 32)
    }
    @Test func discoversVisibleAccountModelsInServerOrder() async throws {
        let capture = RequestCapture()
        let session = sessionReturning(status: 200, body: Data(#"{"models":[{"slug":"second","display_name":"Second","visibility":"list"},{"slug":"hidden","display_name":"Hidden","visibility":"hide"},{"slug":"first","display_name":"First","visibility":"list"}]}"#.utf8), capture: capture)
        #expect(try await ResponsesClient(session: session).models(accessToken: "fixture-token") == [AvailableModel(slug: "second", displayName: "Second"), AvailableModel(slug: "first", displayName: "First")])
        #expect(capture.request?.url?.absoluteString == "https://api.openai.com/v1/models")
        #expect(capture.request?.httpMethod == "GET")
        #expect(capture.request?.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
    }

    @Test func sendsImageAndFullTextWithOnlySupportedFields() async throws {
        let capture = RequestCapture()
        let session = sessionReturning(status: 200, body: completed(), capture: capture)
        let result = try await ResponsesClient(session: session).run(model: "fixture-model", text: "Synthetic context שלום", image: SyntheticConnectionProbe.image, accessToken: "fixture-token")
        #expect(result == ProbeResult(model: "fixture-model", outputText: "Synthetic output שלום"))
        let request = try #require(capture.request)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(payload.keys) == ["model", "input", "store", "stream"])
        #expect(payload["store"] as? Bool == false)
        #expect(payload["stream"] as? Bool == true)
        let input = try #require(payload["input"] as? [[String: Any]])
        #expect(input.count == 1)
        #expect(input[0]["role"] as? String == "user")
        let content = try #require(input[0]["content"] as? [[String: String]])
        #expect(content == [["type": "input_text", "text": "Synthetic context שלום"], ["type": "input_image", "image_url": "data:image/png;base64," + SyntheticConnectionProbe.image.base64EncodedString()]])
    }

    @Test func parsesEveryByteBoundaryIncludingUTF8() throws {
        let bytes = completed()
        for split in 0...bytes.count {
            var stream = ResponseEventStream()
            try stream.append(bytes.prefix(split))
            try stream.append(bytes.dropFirst(split))
            #expect(try stream.finish().outputText == "Synthetic output שלום")
        }
        var stream = ResponseEventStream()
        for byte in bytes { try stream.append(Data([byte])) }
        #expect(try stream.finish().outputText == "Synthetic output שלום")
    }

    @Test func acceptsCRLFAndMultilineEventData() throws {
        let body = "event: response.completed\r\ndata: {\r\ndata: \"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"model\":\"fixture-model\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"OK\"}]}]}}\r\n\r\n"
        var stream = ResponseEventStream()
        try stream.append(Data(body.utf8))
        #expect(try stream.finish().outputText == "OK")
    }

    @Test func rejectsHttpSuccessWithoutCompletedEvent() async {
        let client = ResponsesClient(session: sessionReturning(status: 200, body: Data()))
        await #expect(throws: ResponsesClient.Failure.incompleteResponse) {
            try await client.run(model: "fixture-model", text: "Synthetic test", image: nil, accessToken: "fixture-token")
        }
    }

    @Test(arguments: [Data("data: {bad}\n\n".utf8), Data("data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n".utf8), Data("data: {\"type\":\"response.completed\"}".utf8), Data("data: [DONE]\n\n".utf8)])
    func rejectsMalformedOrTruncatedStreams(body: Data) async {
        await #expect(throws: (any Error).self) {
            try await ResponsesClient(session: sessionReturning(status: 200, body: body)).run(model: "fixture-model", text: "Synthetic", image: nil, accessToken: "fixture-token")
        }
    }

    @Test(arguments: ["response.failed", "response.incomplete", "error"])
    func rejectsFailuresBeforeAndAfterCompletion(type: String) throws {
        let failure = event(["type": type, "response": ["status": "failed"]])
        for prefix in [Data(), completed()] {
            var stream = ResponseEventStream()
            #expect(throws: (any Error).self) { try stream.append(prefix + failure); return try stream.finish() }
        }
    }

    @Test(arguments: [401, 403, 429, 503])
    func mapsHTTPFailures(status: Int) async {
        let expected: ResponsesClient.Failure = switch status { case 401: .unauthorized; case 403: .forbidden; case 429: .quotaReached; default: .http(status: status) }
        await #expect(throws: expected) {
            try await ResponsesClient(session: sessionReturning(status: status, body: Data(#"{"detail":"Synthetic restriction"}"#.utf8))).run(model: "fixture-model", text: "Synthetic", image: nil, accessToken: "fixture-token")
        }
    }

    @Test(arguments: ["subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable"])
    func classifiesTemporaryHTTP503ErrorsBeforeStreaming(code: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["error": ["code": code, "message": "Synthetic temporary outage", "type": "server_error", "param": NSNull()]])
        await #expect(throws: ResponsesClient.Failure.usageUnavailable) {
            try await ResponsesClient(session: sessionReturning(status: 503, body: body)).run(model: "fixture-model", text: "Synthetic", image: nil, accessToken: "fixture-token")
        }
    }

    @Test(arguments: [Data(), Data(#"{"detail":"Synthetic restriction"}"#.utf8),
                      Data(#"{"error":{"code":"unknown_synthetic_code"}}"#.utf8), Data("{bad".utf8),
                      Data(#"{"error":{"code":"subscription_sharing_usage_unavailable"}}"#.utf8) + Data(repeating: 32, count: 65_537)])
    func unknownMalformedOrOversizedHTTP503RetainsGenericFailure(body: Data) async {
        await #expect(throws: ResponsesClient.Failure.http(status: 503)) {
            try await ResponsesClient(session: sessionReturning(status: 503, body: body)).run(model: "fixture-model", text: "Synthetic", image: nil, accessToken: "fixture-token")
        }
    }

    @Test(arguments: ["subscription_sharing_usage_limit_exceeded", "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable"])
    func mapsQuotaErrorsAfterHTTP200(code: String) async {
        let failure = event(["type": "response.failed", "response": ["error": ["code": code]]])
        let expected: ResponsesClient.Failure = code.hasSuffix("exceeded") ? .quotaReached : .usageUnavailable
        await #expect(throws: expected) {
            try await ResponsesClient(session: sessionReturning(status: 200, body: failure)).run(model: "fixture-model", text: "Synthetic", image: nil, accessToken: "fixture-token")
        }
    }

    @Test func rejectsInvalidCompletionAndEventNameMismatch() throws {
        for body in [event(["type": "response.completed", "response": ["status": "incomplete", "model": "fixture-model", "output": []]]), Data("event: error\n".utf8) + completed(), completed() + completed(), completed() + Data("data: {".utf8)] {
            var stream = ResponseEventStream()
            #expect(throws: (any Error).self) { try stream.append(body); return try stream.finish() }
        }
    }

    @Test func rejectsOversizedEventAndInvalidUTF8() throws {
        for body in [Data("data: ".utf8) + Data(repeating: 65, count: 1_048_577), Data([0xFF, 0x0A])] {
            var stream = ResponseEventStream()
            #expect(throws: (any Error).self) { try stream.append(body) }
        }
    }

    @Test func rejectsInvalidInputBeforeNetwork() async {
        let capture = RequestCapture()
        let client = ResponsesClient(session: sessionReturning(status: 200, body: completed(), capture: capture))
        await #expect(throws: ResponsesClient.Failure.invalidInput) { try await client.run(model: "", text: "Synthetic", image: nil, accessToken: "fixture-token") }
        await #expect(throws: ResponsesClient.Failure.invalidInput) { try await client.models(accessToken: "") }
        #expect(capture.request == nil)
    }

    @Test(arguments: [#"{"data":[{"id":"public-api-model"}]}"#, #"{"models":[{"slug":"","display_name":"Invalid","visibility":"list"}]}"#, #"{"models":null}"#])
    func rejectsMalformedCatalog(body: String) async {
        await #expect(throws: ResponsesClient.Failure.malformedResponse) {
            try await ResponsesClient(session: sessionReturning(status: 200, body: Data(body.utf8))).models(accessToken: "fixture-token")
        }
    }

    @Test func omitsImageForTextOnlyInputAndUsesFinalOutput() async throws {
        let capture = RequestCapture()
        let delta = event(["type": "response.output_text.delta", "delta": "untrusted partial"])
        let session = sessionReturning(status: 200, body: delta + completed() + Data("data: [DONE]\n\n".utf8), capture: capture)
        let result = try await ResponsesClient(session: session).run(model: "fixture-model", text: "Synthetic history", image: nil, accessToken: "fixture-token")
        #expect(result.outputText == "Synthetic output שלום")
        let body = try #require(capture.request?.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try #require(payload["input"] as? [[String: Any]])
        #expect(input[0]["content"] as? [[String: String]] == [["type": "input_text", "text": "Synthetic history"]])
    }

    @Test func rejectsInvalidImageAndOversizedInputBeforeNetwork() async {
        let capture = RequestCapture()
        let client = ResponsesClient(session: sessionReturning(status: 200, body: completed(), capture: capture))
        await #expect(throws: ResponsesClient.Failure.invalidInput) { try await client.run(model: "fixture-model", text: "Synthetic", image: Data("not a PNG".utf8), accessToken: "fixture-token") }
        await #expect(throws: ResponsesClient.Failure.invalidInput) { try await client.run(model: "fixture-model", text: String(repeating: "a", count: 65_537), image: nil, accessToken: "fixture-token") }
        #expect(capture.request == nil)
    }

    @Test func rejectsMalformedEventAfterCompletionAndErrorAtTopLevel() throws {
        var malformed = ResponseEventStream()
        #expect(throws: ResponsesClient.Failure.malformedResponse) { try malformed.append(completed() + Data("data: {bad}\n\n".utf8)) }
        var topLevel = ResponseEventStream()
        #expect(throws: ResponsesClient.Failure.quotaReached) { try topLevel.append(event(["type": "error", "code": "subscription_sharing_usage_limit_exceeded"])) }
    }
}

private func toolCall(id: String, callID: String, arguments: String) -> [String: Any] {
    ["type": "function_call", "id": id, "call_id": callID, "name": "record", "namespace": "diary", "arguments": arguments, "status": "completed"]
}
private func toolCompletion(_ items: [[String: Any]]) -> Data {
    event(["type": "response.completed", "response": ["status": "completed", "model": "fixture-model", "output": items]])
}

private func event(_ object: [String: Any]) -> Data {
    Data("data: ".utf8) + (try! JSONSerialization.data(withJSONObject: object)) + Data("\n\n".utf8)
}
private func completed() -> Data {
    event(["type": "response.completed", "response": ["status": "completed", "model": "fixture-model", "output": [["type": "message", "content": [["type": "output_text", "text": "Synthetic output שלום"]]]]]])
}

private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var value: URLRequest?
    var request: URLRequest? { lock.withLock { value } }
    func record(_ request: URLRequest) {
        var recorded = request
        if recorded.httpBody == nil, let stream = recorded.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            recorded.httpBody = body
        }
        lock.withLock { value = recorded }
    }
}

private final class ResponseFixtureProtocol: URLProtocol, @unchecked Sendable {
    struct Fixture: Sendable { let status: Int; let body: Data; let capture: RequestCapture? }
    final class Fixtures: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Fixture] = [:]
        func add(_ fixture: Fixture, id: String) { lock.withLock { values[id] = fixture } }
        func take(_ id: String) -> Fixture? { lock.withLock { values.removeValue(forKey: id) } }
    }
    static let fixtures = Fixtures()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "Fixture-ID"), let fixture = Self.fixtures.take(id), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return
        }
        fixture.capture?.record(request)
        let response = HTTPURLResponse(url: url, statusCode: fixture.status, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for byte in fixture.body { client?.urlProtocol(self, didLoad: Data([byte])) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func sessionReturning(status: Int, body: Data, capture: RequestCapture? = nil) -> URLSession {
    let id = UUID().uuidString
    ResponseFixtureProtocol.fixtures.add(.init(status: status, body: body, capture: capture), id: id)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResponseFixtureProtocol.self]
    configuration.httpAdditionalHeaders = ["Fixture-ID": id]
    return URLSession(configuration: configuration)
}
