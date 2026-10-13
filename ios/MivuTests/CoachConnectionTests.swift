import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct CoachConnectionTests {
    @Test(arguments: [false, true])
    func clearsEarlierResponseDiagnosticAfterCatalogFailureOrDisconnect(disconnect: Bool) async throws {
        let fixture = try CoachConnectionFixture(catalogStatusAfterResponse: 401, response: {
            SessionReply(status: 400, data: Data(#"{"error":{"code":"subscription_sharing_unsupported_capability","param":"input"}}"#.utf8))
        })
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        let infer = try fixture.connection.coachInference()
        await #expect(throws: ResponsesClient.Failure.http(status: 400)) {
            try await infer([.message(role: .user, text: "Synthetic lunch")], Self.namespace)
        }
        #expect(fixture.connection.failureDiagnostic?.providerCode == "subscription_sharing_unsupported_capability")
        if disconnect {
            await fixture.connection.disconnect()
            #expect(fixture.connection.failureDiagnostic == nil)
        } else {
            await fixture.connection.loadModels()
            #expect(fixture.connection.failureDiagnostic?.classification == "unauthorized")
            #expect(fixture.connection.failureDiagnostic?.providerCode == nil)
            #expect(fixture.connection.notice == .revoked)
        }
    }

    @Test func providerDiagnosticPreservesAuthorizedSessionAndOriginalFailure() async throws {
        let fixture = try CoachConnectionFixture(response: {
            SessionReply(status: 400, data: Data(#"{"error":{"code":"subscription_sharing_unsupported_capability","param":"input","message":"private synthetic content"}}"#.utf8))
        })
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        let infer = try fixture.connection.coachInference()
        await #expect(throws: ResponsesClient.Failure.http(status: 400)) {
            try await infer([.message(role: .user, text: "Synthetic lunch")], Self.namespace)
        }
        #expect(fixture.connection.planAuthorized)
        #expect(fixture.connection.notice == .unavailable)
        #expect(fixture.connection.failureDiagnostic?.httpStatus == 400)
        #expect(fixture.connection.failureDiagnostic?.providerCode == "subscription_sharing_unsupported_capability")
        #expect(fixture.connection.failureDiagnostic?.summary.contains("private") == false)
        #expect(fixture.preferences.string(forKey: "pausedRegistrationID") == nil)
    }

    @Test func disconnectedDoesNotCreateInferenceOrSendRequests() async throws {
        let fixture = try CoachConnectionFixture()
        defer { fixture.cleanup() }
        #expect(throws: SessionError.noActiveSession) { try fixture.connection.coachInference() }
        #expect(fixture.requests.count == 0)
    }

    @Test func structuredResponseUsesSharedSelectedAccountAndModel() async throws {
        let fixture = try CoachConnectionFixture()
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        let infer = try fixture.connection.coachInference()
        let result = try await infer([.message(role: .user, text: "Synthetic lunch")], Self.namespace)
        #expect(result.text == "Synthetic guidance")
        #expect(result.calls.first?.namespace == "mivu")
        #expect(result.calls.first?.name == "get_context")
        #expect(fixture.requests.count == 1)
        #expect(fixture.connection.job == nil)
    }

    @Test func selectedModelChangeRejectsBoundInferenceBeforeTransport() async throws {
        let fixture = try CoachConnectionFixture()
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        let infer = try fixture.connection.coachInference()
        fixture.connection.selectedModel = "second-model"
        await #expect(throws: SessionError.sessionChanged) {
            try await infer([.message(role: .user, text: "Synthetic lunch")], Self.namespace)
        }
        #expect(fixture.requests.count == 0)
    }

    @Test(arguments: [false, true]) func delayedResponseCannotCrossModelOrAccountChange(disconnect: Bool) async throws {
        let release = DispatchSemaphore(value: 0)
        let fixture = try CoachConnectionFixture(response: {
            guard release.wait(timeout: .now() + 5) == .success else { throw URLError(.timedOut) }
            return coachConnectionCompletion()
        })
        defer { release.signal(); fixture.cleanup() }
        await fixture.connection.restore()
        let infer = try fixture.connection.coachInference()
        let task = Task { try await infer([.message(role: .user, text: "Synthetic lunch")], Self.namespace) }
        try await waitForCoachRequest(fixture.requests)
        let revision = fixture.connection.sessionRevision
        if disconnect {
            await fixture.connection.disconnect()
            #expect(fixture.connection.sessionRevision != revision)
        } else { fixture.connection.selectedModel = "second-model" }
        release.signal()
        await #expect(throws: SessionError.sessionChanged) { try await task.value }
        #expect(fixture.connection.lastCompletedProbe == nil)
    }

    @Test func permissionFailureUpdatesSharedSettingsSession() async throws {
        let fixture = try CoachConnectionFixture(response: { SessionReply(status: 403, data: Data()) })
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        let infer = try fixture.connection.coachInference()
        await #expect(throws: ResponsesClient.Failure.forbidden) {
            try await infer([.message(role: .user, text: "Synthetic lunch")], Self.namespace)
        }
        #expect(fixture.connection.accountState == .planPermissionMissing)
        #expect(fixture.connection.models.isEmpty)
        #expect(fixture.connection.notice == .permission)
    }

    @Test func temporaryUsageFailurePreservesAccountAndBoundInference() async throws {
        let fixture = try CoachConnectionFixture(usageFailures: 1)
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        let infer = try fixture.connection.coachInference()
        let owner = fixture.connection.activeRegistrationID
        let models = fixture.connection.models
        await #expect(throws: ResponsesClient.Failure.usageUnavailable) {
            try await infer([.message(role: .user, text: "Synthetic lunch")], Self.namespace)
        }
        #expect(fixture.connection.planAuthorized)
        #expect(fixture.connection.activeRegistrationID == owner)
        #expect(fixture.connection.models == models)
        #expect(fixture.preferences.string(forKey: "pausedRegistrationID") == nil)
        #expect(ProbeRunner.isTransient(ResponsesClient.Failure.usageUnavailable))
        _ = try await infer([.message(role: .user, text: "Synthetic lunch")], Self.namespace)
        #expect(fixture.requests.count == 2)
    }

    @Test(arguments: [3, 4], [200, 503])
    func usageOutageRetriesBoundedRoundAndKeepsSavedInput(failures: Int, status: Int) async throws {
        let fixture = try CoachConnectionFixture(usageFailures: failures, usageFailureStatus: status, response: coachConnectionTextCompletion)
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        let store = DiaryStore(directory: fixture.directory.appending(path: "Diary"))
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic usage recovery"))
        let diary = DiaryViewModel(store: store)
        diary.snapshot = try await store.snapshot()
        let delays = CoachUsageDelays()
        let coach = CoachViewModel(diary: diary, connection: fixture.connection, sleep: { duration in
            await delays.record(duration)
        })
        coach.draft.text = "Synthetic temporary usage outage"
        let id = coach.draft.submissionID
        #expect(await coach.send())
        await coach.waitForWorker()
        #expect(fixture.requests.count == 4)
        #expect(await delays.seconds == [1, 2, 4])
        #expect(fixture.connection.planAuthorized)
        #expect(diary.snapshot?.coachTurns.count == 1)
        #expect(diary.snapshot?.coachTurns.first?.id == id)
        #expect(diary.snapshot?.coachTurns.first?.text == "Synthetic temporary usage outage")
        #expect(diary.snapshot?.coachTurns.first?.state == (failures == 3 ? .completed : .needsRetry))
        if failures == 4 {
            coach.resume(); await coach.waitForWorker()
            #expect(fixture.requests.count == 4)
            await coach.retry(id)
            await coach.waitForWorker()
            #expect(fixture.requests.count == 5)
            #expect(diary.snapshot?.coachTurns.first?.state == .completed)
        }
    }

    @Test func profileChangeDuringUsageRetryDelayStopsBeforeAnotherRequest() async throws {
        let attempts = CoachConnectionRequests()
        let fixture = try CoachConnectionFixture(response: {
            attempts.append()
            return attempts.count == 1 ? SessionReply(status: 503, data: Data()) : coachConnectionTextCompletion()
        })
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        let store = DiaryStore(directory: fixture.directory.appending(path: "Diary"))
        let profile = DiaryProfile(name: "Synthetic original profile")
        _ = try await store.createProfile(profile)
        let diary = DiaryViewModel(store: store)
        diary.snapshot = try await store.snapshot()
        let coach = CoachViewModel(diary: diary, connection: fixture.connection, sleep: { _ in
            await diary.createProfile(name: "Synthetic other profile")
            await diary.switchProfile(profile.id)
        })
        coach.draft.text = "Synthetic profile-fenced retry"
        let id = coach.draft.submissionID
        #expect(await coach.send())
        await coach.waitForWorker()
        #expect(diary.snapshot?.profile.id == profile.id)
        #expect(fixture.requests.count == 1)
        let turn = try await store.coachTurn(turnID: id, expectedProfileID: profile.id)
        #expect(turn.assistantText == nil)
        #expect(turn.text == "Synthetic profile-fenced retry")
    }

    private static var namespace: Data {
        Data(#"{"type":"namespace","name":"mivu","tools":[{"type":"function","name":"get_context","parameters":{"type":"object","properties":{}}}]}"#.utf8)
    }
}

private actor CoachUsageDelays {
    var seconds: [Int64] = []
    func record(_ duration: Duration) { seconds.append(duration.components.seconds) }
}

private final class CoachConnectionRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var responses = 0
    var count: Int { lock.withLock { responses } }
    func append() { lock.withLock { responses += 1 } }
}

private final class CoachCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: Credentials?
    init() { credentials = savedCredentials(now: .now, expired: false) }
    func hostID() throws -> String { "urn:uuid:00000000-0000-4000-8000-000000000002" }
    func registrations() throws -> [AccountRegistration] { lock.withLock { credentials.map { [$0.registration] } ?? [] } }
    func load(registrationID: String) throws -> Credentials? { lock.withLock { credentials?.registrationID == registrationID ? credentials : nil } }
    func replace(_ value: Credentials) throws { lock.withLock { credentials = value } }
    func delete(registrationID: String) throws { lock.withLock { if credentials?.registrationID == registrationID { credentials = nil } } }
}

@MainActor private struct CoachConnectionFixture {
    let directory = URL.temporaryDirectory.appending(path: "CoachConnection-" + UUID().uuidString)
    let preferencesName = "CoachConnection-" + UUID().uuidString
    let preferences: UserDefaults
    let requests = CoachConnectionRequests()
    let connection: ChatGPTConnection
    init(usageFailures: Int? = nil, usageFailureStatus: Int = 200, catalogStatusAfterResponse: Int? = nil, response: @escaping @Sendable () throws -> SessionReply = coachConnectionCompletion) throws {
        let store = CoachCredentialStore()
        preferences = UserDefaults(suiteName: preferencesName)!
        preferences.set(try store.registrations().first?.id, forKey: "selectedRegistrationID")
        let requests = requests
        let session = syntheticSession { request in
            switch request.url?.path {
            case "/v1/models":
                if let catalogStatusAfterResponse, requests.count > 0 { return SessionReply(status: catalogStatusAfterResponse, data: Data()) }
                return SessionReply(status: 200, data: Data(#"{"models":[{"slug":"fixture-model","display_name":"Synthetic","visibility":"list"},{"slug":"second-model","display_name":"Second synthetic","visibility":"list"}]}"#.utf8))
            case "/v1/responses":
                requests.append()
                let body = try #require(request.httpBody)
                let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(payload["model"] as? String == "fixture-model")
                #expect(payload["store"] as? Bool == false)
                #expect(payload["tools"] != nil)
                if let usageFailures, requests.count <= usageFailures {
                    if usageFailureStatus == 503 {
                        return SessionReply(status: 503, data: Data(#"{"error":{"code":"subscription_sharing_usage_unavailable","message":"Synthetic temporary outage","type":"server_error","param":null}}"#.utf8))
                    }
                    return SessionReply(status: 200, data: Data("event: response.failed\ndata: {\"type\":\"response.failed\",\"response\":{\"status\":\"failed\",\"model\":\"fixture-model\",\"error\":{\"code\":\"subscription_sharing_usage_unavailable\",\"message\":\"Synthetic temporary outage\",\"param\":null}}}\n\n".utf8))
                }
                return try response()
            case "/api/accounts/oauth/revoke": return SessionReply(status: 200, data: Data())
            default: throw URLError(.badURL)
            }
        }
        connection = ChatGPTConnection(auth: AuthSession(session: session, store: store), client: ResponsesClient(session: session), jobStore: ProbeJobStore(directory: directory), preferences: preferences)
    }
    func cleanup() {
        preferences.removePersistentDomain(forName: preferencesName)
        try? FileManager.default.removeItem(at: directory)
    }
}

private func coachConnectionCompletion() -> SessionReply {
    SessionReply(status: 200, data: Data("event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"model\":\"fixture-model\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Synthetic guidance\"}]},{\"type\":\"function_call\",\"id\":\"synthetic-id\",\"call_id\":\"synthetic-call\",\"name\":\"get_context\",\"namespace\":\"mivu\",\"arguments\":\"{}\"}]}}\n\n".utf8))
}
private func coachConnectionTextCompletion() -> SessionReply {
    SessionReply(status: 200, data: Data("event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"model\":\"fixture-model\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Synthetic guidance\"}]}]}}\n\n".utf8))
}
private func waitForCoachRequest(_ requests: CoachConnectionRequests) async throws {
    for _ in 0..<2_000 {
        if requests.count > 0 { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw URLError(.timedOut)
}
