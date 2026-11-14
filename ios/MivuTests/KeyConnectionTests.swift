import Foundation
import Testing
@testable import Mivu

@Suite(.serialized) @MainActor struct KeyConnectionTests {
    @Test func aKeyIsCheckedBeforeItIsSavedAndThenBecomesTheActiveAI() async throws {
        let f = Fixture(); defer { f.cleanup() }
        f.reply(200, modelsReply)
        await #expect(throws: KeyConnectionError.consentRequired) { try await f.connection.saveKey("fixture-key", for: .claude) }
        #expect(f.requests.isEmpty)                                   // nothing sent before consent
        f.connection.recordConsent(to: .claude)
        try await f.connection.saveKey("  fixture-key\n", for: .claude)
        #expect(try f.keyStore.load(.claude) == "fixture-key")
        #expect(f.connection.provider == .claude && f.connection.canInfer && f.connection.tunesTargets)
        #expect(f.connection.selectedModel(for: .claude) == "claude-haiku-5-5")
        #expect(f.connection.activeName == "Claude")
        #expect(f.connection.activeUsagePage == KeyService.claude.usagePage)
        #expect(!f.preferences.dictionaryRepresentation().values.contains { "\($0)".contains("fixture-key") })
    }

    @Test func aRejectedKeyIsNotSaved() async throws {
        let f = Fixture(); defer { f.cleanup() }
        f.connection.recordConsent(to: .gemini); f.reply(401, "{}")
        await #expect(throws: KeyConnectionError.rejected) { try await f.connection.saveKey("fixture-key", for: .gemini) }
        #expect(try f.keyStore.load(.gemini) == nil)
        #expect(!f.connection.available(.gemini))
        await #expect(throws: KeyConnectionError.invalidKey) { try await f.connection.saveKey("has space", for: .gemini) }
        f.reply(500, "{}")
        await #expect(throws: KeyConnectionError.unavailable) { try await f.connection.saveKey("fixture-key", for: .gemini) }
        #expect(try f.keyStore.load(.gemini) == nil)
    }

    @Test func consentIsPerService() {
        let f = Fixture(); defer { f.cleanup() }
        f.connection.recordConsent(to: .openAI)
        #expect(f.connection.sharingConsented)                        // same preference as ChatGPT
        #expect(!f.connection.consented(to: .claude))
    }

    @Test func replacingOrRemovingTheKeyEndsARequestInFlight() async throws {
        let f = try await Fixture.connected(.claude); defer { f.cleanup() }
        let respond = try f.connection.inference()
        f.connection.removeKey(for: .claude)
        await #expect(throws: SessionError.sessionChanged) { _ = try await respond([.message(role: .user, text: "hi")], nil) }
        #expect(f.requests.count == 1)                                // only the earlier key check
        #expect(try f.keyStore.load(.claude) == nil)
        #expect(throws: SessionError.noActiveSession) { _ = try f.connection.inference() }
    }

    @Test func switchingProviderOrModelEndsARequestBoundToTheOldOne() async throws {
        let f = try await Fixture.connected(.claude); defer { f.cleanup() }
        let boundToHaiku = try f.connection.inference()
        f.connection.selectModel("claude-opus-5-5", for: .claude)
        await #expect(throws: SessionError.sessionChanged) { _ = try await boundToHaiku([.message(role: .user, text: "hi")], nil) }
        let boundToClaude = try f.connection.inference()
        f.connection.provider = .chatGPT
        await #expect(throws: SessionError.sessionChanged) { _ = try await boundToClaude([.message(role: .user, text: "hi")], nil) }
        #expect(f.requests.count == 1)
    }

    @Test func aBoundRequestReachesTheServiceWithItsKeyAndModel() async throws {
        let f = try await Fixture.connected(.claude); defer { f.cleanup() }
        f.reply(200, #"{"model":"claude-haiku-5-5","stop_reason":"end_turn","content":[{"type":"text","text":"Hi"}]}"#)
        let result = try await f.connection.inference()([.message(role: .user, text: "hi")], nil)
        #expect(result.text == "Hi")
        let request = try #require(f.requests.last)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "fixture-key")
        let body = try #require(request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["model"] as? String == "claude-haiku-5-5")
    }

    @Test func aVanishedModelFallsBackToTheDefaultThenTheFirstListed() async throws {
        let f = try await Fixture.connected(.claude); defer { f.cleanup() }
        f.connection.selectModel("claude-opus-5-5", for: .claude)
        #expect(f.connection.selectedModel(for: .claude) == "claude-opus-5-5")
        f.reply(200, #"{"data":[{"id":"claude-sonnet-5-5","display_name":"Claude Sonnet 5.5"}]}"#)
        let restored = f.relaunched(); await restored.restore()
        #expect(restored.selectedModel(for: .claude) == "claude-sonnet-5-5")
    }

    @Test func savedKeysSurviveSwitchingAndRelaunchEvenOffline() async throws {
        let f = try await Fixture.connected(.claude); defer { f.cleanup() }
        f.connection.provider = .chatGPT
        #expect(f.connection.connectedServices == [.claude])
        f.connection.provider = .claude; f.reply(503, "{}")           // the model list cannot load
        let restored = f.relaunched()
        #expect(restored.provider == .claude)                         // known before restore, so launch does not flicker
        await restored.restore()
        #expect(restored.provider == .claude && restored.canInfer)
        #expect(restored.selectedModel(for: .claude) == "claude-haiku-5-5")
        _ = try restored.inference()
    }

    @Test func noCreditAndABadKeySetTheirOwnNotices() async throws {
        let f = try await Fixture.connected(.claude); defer { f.cleanup() }
        f.reply(402, "{}")
        await #expect(throws: ResponsesClient.Failure.quotaReached) { _ = try await f.connection.inference()([.message(role: .user, text: "hi")], nil) }
        #expect(f.connection.notice == .keyQuota)
        f.reply(401, "{}")
        await #expect(throws: ResponsesClient.Failure.unauthorized) { _ = try await f.connection.inference()([.message(role: .user, text: "hi")], nil) }
        #expect(f.connection.notice == .keyRejected)
    }

    @Test func failureCopyNamesTheActiveService() {
        #expect(coachFailureText(ResponsesClient.Failure.quotaReached, serviceName: "Claude")
            == "Your Claude account is out of credit or over its limit. Your message is saved; see Manage usage in Settings.")
        #expect(coachFailureText(ResponsesClient.Failure.quotaReached, serviceName: nil)
            == "You've reached your ChatGPT usage limit. Your message is saved; see Manage usage in Settings.")
        #expect(coachFailureText(ResponsesClient.Failure.usageUnavailable, serviceName: "Gemini")
            == "Gemini is busy right now. Your message is saved; try again soon.")
        #expect(coachFailureText(ResponsesClient.Failure.unauthorized, serviceName: "Gemini")
            == "Gemini rejected your key. Your message is saved; replace the key in Settings.")
        #expect(coachFailureText(ResponsesClient.Failure.malformedResponse, serviceName: "Gemini") == nil)
    }

    @Test func openRouterSignInTradesTheCallbackCodeForAKey() async throws {
        let f = Fixture(); defer { f.cleanup() }
        f.reply(200, #"{"key":"fixture-or-key"}"#)
        await f.connection.signInOpenRouter { _ in Issue.record("Opened a browser before consent") }
        #expect(f.requests.isEmpty)
        f.connection.recordConsent(to: .openRouter)
        await f.connection.signInOpenRouter { url in
            let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            let returnAddress = try #require(query.first { $0.name == "callback_url" }?.value)
            var callback = try #require(URLComponents(string: returnAddress))
            callback.queryItems = [URLQueryItem(name: "code", value: "synthetic-code"), URLQueryItem(name: "state", value: query.first { $0.name == "state" }?.value)]
            _ = try await URLSession.shared.data(from: #require(callback.url))
            throw CancellationError()
        }
        #expect(try f.keyStore.load(.openRouter) == "fixture-or-key")
        #expect(f.connection.provider == .openRouter && f.connection.canInfer && !f.connection.isConnecting)
        #expect(f.requests.map { $0.url?.path } == ["/api/v1/auth/keys", "/api/v1/key"])
    }

    @Test func cancelledOpenRouterSignInSavesNothing() async throws {
        let f = Fixture(); defer { f.cleanup() }
        f.connection.recordConsent(to: .openRouter)
        await f.connection.signInOpenRouter { _ in throw CancellationError() }
        #expect(f.requests.isEmpty && f.connection.notice == .cancelled && !f.connection.isConnecting)
        #expect(try f.keyStore.load(.openRouter) == nil)
    }
}

private let modelsReply = #"{"data":[{"id":"claude-haiku-5-5","display_name":"Claude Haiku 5.5"},{"id":"claude-opus-5-5","display_name":"Claude Opus 5.5"}]}"#

private final class Replies: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200, body = "{}", seen: [URLRequest] = []
    func set(_ status: Int, _ body: String) { lock.withLock { self.status = status; self.body = body } }
    func answer(_ request: URLRequest) -> SessionReply { lock.withLock { seen.append(request); return SessionReply(status: status, data: Data(body.utf8)) } }
    var requests: [URLRequest] { lock.withLock { seen } }
}

@MainActor private final class Fixture {
    let directory = URL.temporaryDirectory.appending(path: "KeyConnection-" + UUID().uuidString)
    let preferencesName = "KeyConnection-" + UUID().uuidString
    let preferences: UserDefaults
    let keyStore = AIKeyStore(service: "Mivu.AIKeysTest." + UUID().uuidString)
    private let replies = Replies()
    private let session: URLSession
    private(set) var connection: ChatGPTConnection!

    init() {
        preferences = UserDefaults(suiteName: preferencesName)!
        let replies = replies
        session = syntheticSession { replies.answer($0) }
        connection = relaunched()
    }

    static func connected(_ service: KeyService) async throws -> Fixture {
        let fixture = Fixture()
        fixture.reply(200, modelsReply)
        fixture.connection.recordConsent(to: service)
        try await fixture.connection.saveKey("fixture-key", for: service)
        return fixture
    }

    /// A second connection over the same Keychain and preferences, as after the app is reopened.
    func relaunched() -> ChatGPTConnection {
        ChatGPTConnection(auth: AuthSession(session: session, store: MemoryCredentialStore()), client: ResponsesClient(session: session),
                          jobStore: ProbeJobStore(directory: directory), preferences: preferences, appleModelAvailable: { false },
                          keyStore: keyStore, keyClient: KeyServiceClient(session: session))
    }

    func reply(_ status: Int, _ body: String) { replies.set(status, body) }
    var requests: [URLRequest] { replies.requests }

    func cleanup() {
        for service in KeyService.allCases { try? keyStore.remove(service) }
        preferences.removePersistentDomain(forName: preferencesName)
        try? FileManager.default.removeItem(at: directory)
    }
}
