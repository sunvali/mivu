import Foundation
import Testing
@testable import Mivu

@Suite(.serialized) struct KeyServiceClientTests {
    @Test func claudeSendsItsOwnHeadersAndNoBearer() async throws {
        let capture = RequestCapture()
        let reply = Data(#"{"model":"claude-haiku-5-5","stop_reason":"end_turn","content":[{"type":"text","text":"Hi"}]}"#.utf8)
        let result = try await KeyServiceClient(session: sessionReturning(status: 200, body: reply, capture: capture))
            .respond(.claude, model: "claude-haiku-5-5", input: [.message(role: .user, text: "hi")], toolNamespace: nil, key: "fixture-key")
        #expect(result.text == "Hi")
        let request = try #require(capture.request)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "fixture-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test(arguments: [(KeyService.gemini, "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"),
                      (KeyService.openRouter, "https://openrouter.ai/api/v1/chat/completions")])
    func chatServicesUseBearerAtTheirOwnAddress(service: KeyService, url: String) async throws {
        let capture = RequestCapture()
        let reply = Data(#"{"model":"m","choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Hi"}}]}"#.utf8)
        _ = try await KeyServiceClient(session: sessionReturning(status: 200, body: reply, capture: capture))
            .respond(service, model: "m", input: [.message(role: .user, text: "hi")], toolNamespace: nil, key: "fixture-key")
        #expect(capture.request?.url?.absoluteString == url)
        #expect(capture.request?.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
    }

    @Test(arguments: [(401, ResponsesClient.Failure.unauthorized), (402, .quotaReached), (429, .quotaReached),
                      (529, .usageUnavailable), (500, .http(status: 500))])
    func statusesMapToTheFailuresCoachAlreadyHandles(status: Int, failure: ResponsesClient.Failure) async {
        // The fixture session answers one request, so each call gets its own.
        await #expect(throws: failure) {
            try await KeyServiceClient(session: sessionReturning(status: status, body: Data("{}".utf8)))
                .respond(.claude, model: "m", input: [.message(role: .user, text: "hi")], toolNamespace: nil, key: "fixture-key") }
        await #expect(throws: failure) {
            try await KeyServiceClient(session: sessionReturning(status: status, body: Data("{}".utf8))).models(.gemini, key: "fixture-key") }
    }

    /// Observed on 2026-11-14: Google answers a made-up key with 400 "Please pass a valid API key", not 401.
    @Test func geminiKeyCheckTreatsItsBadKeyStatusAsRejected() async {
        await #expect(throws: ResponsesClient.Failure.unauthorized) {
            try await KeyServiceClient(session: sessionReturning(status: 400, body: Data("{}".utf8))).models(.gemini, key: "fixture-key") }
        await #expect(throws: ResponsesClient.Failure.http(status: 400)) {
            try await KeyServiceClient(session: sessionReturning(status: 400, body: Data("{}".utf8))).models(.openAI, key: "fixture-key") }
    }

    @Test func modelListsAreFilteredToChatModels() async throws {
        let body = Data(#"{"data":[{"id":"gpt-fixture-mini"},{"id":"text-embedding-3-small"},{"id":"gpt-fixture-tts"}]}"#.utf8)
        let models = try await KeyServiceClient(session: sessionReturning(status: 200, body: body)).models(.openAI, key: "fixture-key")
        #expect(models == [AvailableModel(slug: "gpt-fixture-mini", displayName: "gpt-fixture-mini")])
    }

    @Test func geminiModelIdsLoseTheirListPrefix() async throws {
        let body = Data(#"{"data":[{"id":"models/gemini-fixture-flash"},{"id":"models/gemini-embedding-2"}]}"#.utf8)
        let models = try await KeyServiceClient(session: sessionReturning(status: 200, body: body)).models(.gemini, key: "fixture-key")
        #expect(models == [AvailableModel(slug: "gemini-fixture-flash", displayName: "gemini-fixture-flash")])
    }

    @Test func claudeModelsKeepTheirDisplayNames() async throws {
        let capture = RequestCapture()
        let body = Data(#"{"data":[{"id":"claude-haiku-5-5","display_name":"Claude Haiku 5.5"}]}"#.utf8)
        let models = try await KeyServiceClient(session: sessionReturning(status: 200, body: body, capture: capture)).models(.claude, key: "fixture-key")
        #expect(models == [AvailableModel(slug: "claude-haiku-5-5", displayName: "Claude Haiku 5.5")])
        #expect(capture.request?.url?.absoluteString == "https://api.anthropic.com/v1/models?limit=100")
        #expect(capture.request?.value(forHTTPHeaderField: "x-api-key") == "fixture-key")
    }

    @Test func openRouterChecksTheKeyAndReturnsItsShortlist() async throws {
        let capture = RequestCapture()
        let models = try await KeyServiceClient(session: sessionReturning(status: 200, body: Data("{}".utf8), capture: capture)).models(.openRouter, key: "fixture-key")
        #expect(capture.request?.url?.absoluteString == "https://openrouter.ai/api/v1/key")
        #expect(models == KeyService.openRouter.shortlist && !models.isEmpty)
    }
}
