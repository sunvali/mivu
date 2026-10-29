import Foundation
import Testing
@testable import Mivu

@Suite @MainActor
struct ConnectionTests {
    @Test func constructionDoesNotRestoreOrSendRequests() throws {
        let store = ConnectionCredentialStore()
        let requests = ConnectionRequests()
        let session = syntheticSession { request in requests.append(request); throw URLError(.badServerResponse) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preferences = UserDefaults(suiteName: UUID().uuidString)!
        preferences.set("synthetic-selected-registration", forKey: "selectedRegistrationID")
        let connection = ChatGPTConnection(auth: AuthSession(session: session, store: store),
            client: ResponsesClient(session: session), jobStore: ProbeJobStore(directory: directory), preferences: preferences)
        #expect(connection.state == .disconnected)
        #expect(connection.lastCompletedProbe == nil)
        #expect(store.loads == 0)
        #expect(requests.values.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func restoreWithoutSharingConsentLeavesSavedCredentialsUnused() async throws {
        let fixture = try ConnectionFixture()
        fixture.preferences.removeObject(forKey: "openAISharingConsent")
        await fixture.connection.restore()
        #expect(fixture.connection.accountState == .disconnected)
        #expect(fixture.store.loads == 0)
        #expect(fixture.requests.values.isEmpty)
    }

    @Test func connectWithoutSharingConsentNeverOpensTheBrowser() async {
        let connection = ChatGPTConnection(preferences: UserDefaults(suiteName: UUID().uuidString)!)
        var opened = false
        await connection.connect { _ in opened = true }
        #expect(!opened && !connection.isConnecting)
    }
    @Test func openAISharingConsentStartsUnsetAndPersists() {
        let preferences = UserDefaults(suiteName: UUID().uuidString)!
        let connection = ChatGPTConnection(preferences: preferences)
        #expect(!connection.sharingConsented)
        connection.recordSharingConsent()
        #expect(connection.sharingConsented)
        #expect(ChatGPTConnection(preferences: preferences).sharingConsented)
    }

    @Test(arguments: [false, true])
    func planWelcomeShowsOnceAfterPlanUseIsAuthorized(permission: Bool) async throws {
        let fixture = try ConnectionFixture(permission: permission)
        defer { fixture.cleanup() }
        #expect(!fixture.connection.showsPlanWelcome)
        await fixture.connection.restore()
        #expect(fixture.connection.showsPlanWelcome == permission)
        fixture.connection.acknowledgePlanWelcome()
        #expect(!fixture.connection.showsPlanWelcome)
        #expect(ChatGPTConnection(preferences: fixture.preferences).planWelcomeSeen)
    }
}

private final class ConnectionRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    func append(_ request: URLRequest) { lock.withLock { requests.append(request) } }
    var values: [URLRequest] { lock.withLock { requests } }
}

private final class ConnectionCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: Credentials] = [:]
    private var loadCount = 0
    private var deletionFailure = false
    var failDeletes: Bool {
        get { lock.withLock { deletionFailure } }
        set { lock.withLock { deletionFailure = newValue } }
    }
    var loads: Int { lock.withLock { loadCount } }
    func hostID() throws -> String { "urn:uuid:00000000-0000-4000-8000-000000000002" }
    func registrations() throws -> [AccountRegistration] { lock.withLock { records.values.map(\.registration) } }
    func load(registrationID: String) throws -> Credentials? {
        lock.withLock { loadCount += 1; return records[registrationID] }
    }
    func replace(_ credentials: Credentials) throws { lock.withLock { records[credentials.registrationID] = credentials } }
    func delete(registrationID: String) throws {
        try lock.withLock {
            if deletionFailure { throw CredentialStoreError.invalidRecord }
            records[registrationID] = nil
        }
    }
}

extension ConnectionTests {
    @Test(arguments: [false, true])
    func explicitMissingPlanActionRequestsConsentWithoutChangingRegistration(permission: Bool) async throws {
        let fixture = try ConnectionFixture(permission: permission)
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        let before = fixture.requests.values.count
        await fixture.connection.connect { url in
            let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            #expect(query.first { $0.name == "client_id" }?.value == fixture.credentials.registration.issuedClientID)
            #expect(query.first { $0.name == "prompt" }?.value == (permission ? nil : "consent"))
            #expect(!query.contains { $0.name == "force_reconsent" })
            #expect(query.first { $0.name == "scope" }?.value == "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct")
            throw CancellationError()
        }
        #expect(fixture.connection.activeRegistrationID == fixture.credentials.registrationID)
        #expect(fixture.connection.planAuthorized == permission)
        #expect(fixture.requests.values.count == before)
    }

    @Test func missingPlanPermissionSendsNeitherCatalogNorResponse() async throws {
        let fixture = try ConnectionFixture(permission: false)
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        await fixture.connection.loadModels()
        #expect(!fixture.connection.captureSample())
        fixture.connection.retry()
        await fixture.connection.waitForProbe()
        #expect(fixture.connection.accountState == .planPermissionMissing)
        #expect(fixture.requests.values.isEmpty)
        #expect(fixture.connection.lastCompletedProbe == nil)
    }

    @Test(arguments: [false, true])
    func cancellationAndDenialNeverExchangeOrChangeSelection(denied: Bool) async throws {
        let fixture = try ConnectionFixture()
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        let before = fixture.requests.values.count
        await fixture.connection.connect { url in
            if !denied { throw CancellationError() }
            let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            let redirect = try #require(query.first { $0.name == "redirect_uri" }?.value)
            let state = try #require(query.first { $0.name == "state" }?.value)
            var callback = try #require(URLComponents(string: redirect))
            callback.queryItems = [URLQueryItem(name: "state", value: state), URLQueryItem(name: "error", value: "access_denied")]
            _ = try await URLSession.shared.data(from: #require(callback.url))
        }
        #expect(fixture.requests.values.count == before)
        #expect(fixture.connection.activeRegistrationID == fixture.credentials.registrationID)
        #expect(fixture.preferences.string(forKey: "selectedRegistrationID") == fixture.credentials.registrationID)
        #expect(fixture.connection.accountState == .connected)
        #expect(fixture.connection.notice == (denied ? .denied : .cancelled))
    }

    @Test func catalogSelectionAndSamplePersistBeforeTransportAndCompletion() async throws {
        let fixture = try ConnectionFixture()
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        #expect(fixture.connection.models.map(\.slug) == ["fixture-model", "second-model"])
        #expect(fixture.connection.selectedModel == "fixture-model")
        #expect(fixture.connection.captureSample())
        let captured = try #require(try fixture.jobStore.load())
        #expect(captured.registrationID == fixture.credentials.registrationID)
        #expect(captured.image == SyntheticConnectionProbe.image)
        #expect(captured.text == SyntheticConnectionProbe.prompt)
        await fixture.connection.waitForProbe()
        #expect(fixture.connection.state == .completed)
        #expect(fixture.connection.lastCompletedProbe?.outputText == "Synthetic completion")
        #expect(try fixture.jobStore.load()?.state == .completed)
        #expect(fixture.requests.values.filter { $0.url?.path == "/v1/responses" }.count == 1)
    }

    @Test func persistenceFailureDoesNotAcknowledgeOrRequest() async throws {
        let fixture = try ConnectionFixture()
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        try Data("synthetic obstruction".utf8).write(to: fixture.directory)
        #expect(!fixture.connection.captureSample())
        await fixture.connection.waitForProbe()
        #expect(fixture.connection.job == nil)
        #expect(fixture.connection.notice == .saveFailed)
        #expect(!fixture.requests.values.contains { $0.url?.path == "/v1/responses" })
    }

    @Test func quotaPausesUntilExplicitRetryWithSameJobID() async throws {
        let responseCount = ConnectionRequests()
        let fixture = try ConnectionFixture(response: { request in
            responseCount.append(request)
            if responseCount.values.count == 1 { return SessionReply(status: 429, data: Data()) }
            return connectionCompletion()
        })
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        #expect(fixture.connection.captureSample())
        let id = try #require(fixture.connection.job?.id)
        await fixture.connection.waitForProbe()
        #expect(fixture.connection.state == .quotaReached)
        #expect(fixture.connection.job?.state == .needsRetry)
        #expect(fixture.connection.lastCompletedProbe == nil)
        await fixture.connection.enterForeground()
        await fixture.connection.waitForProbe()
        #expect(responseCount.values.count == 1)
        fixture.connection.retry()
        await fixture.connection.waitForProbe()
        #expect(fixture.connection.lastCompletedProbe != nil)
        #expect(fixture.connection.job?.id == id)
        #expect(responseCount.values.count == 2)
    }

    @Test func explicitRestoreResumesOnlyMatchingPendingOwner() async throws {
        let fixture = try ConnectionFixture()
        defer { fixture.cleanup() }
        let pending = ProbeJob(text: SyntheticConnectionProbe.prompt, image: SyntheticConnectionProbe.image,
            model: "fixture-model", registrationID: fixture.credentials.registrationID, state: .analyzing)
        try fixture.jobStore.save(pending)
        #expect(fixture.requests.values.isEmpty)
        await fixture.connection.restore()
        await fixture.connection.waitForProbe()
        #expect(fixture.connection.job?.id == pending.id)
        #expect(fixture.connection.lastCompletedProbe != nil)
    }

    @Test func restoredJobForOtherRegistrationRemainsSavedWithoutInference() async throws {
        let fixture = try ConnectionFixture()
        defer { fixture.cleanup() }
        let other = savedCredentials(now: .now, subject: "other-synthetic-account", expired: false)
        try fixture.store.replace(other)
        let pending = ProbeJob(text: "Synthetic test", image: nil, model: "fixture-model", registrationID: other.registrationID)
        try fixture.jobStore.save(pending)
        await fixture.connection.restore()
        await fixture.connection.waitForProbe()
        #expect(fixture.connection.activeRegistrationID == fixture.credentials.registrationID)
        #expect(fixture.connection.job?.id == pending.id)
        #expect(fixture.connection.lastCompletedProbe == nil)
        fixture.connection.retry()
        #expect(!fixture.requests.values.contains { $0.url?.path == "/v1/responses" })
    }

    @Test(arguments: [false, true])
    func lateCompletionCannotRecreateDeletedOrDisconnectedState(delete: Bool) async throws {
        let block = DispatchSemaphore(value: 0)
        let fixture = try ConnectionFixture(response: { _ in
            _ = block.wait(timeout: .now() + 5)
            return connectionCompletion()
        })
        defer { block.signal(); fixture.cleanup() }
        await fixture.connection.restore()
        #expect(fixture.connection.captureSample())
        try await waitForConnectionRequest(fixture.requests, path: "/v1/responses")
        let operation = Task { if delete { await fixture.connection.deleteSample() } else { await fixture.connection.disconnect() } }
        await Task.yield()
        block.signal()
        await operation.value
        await fixture.connection.waitForProbe()
        #expect(fixture.connection.lastCompletedProbe == nil)
        if delete { #expect(try fixture.jobStore.load() == nil); #expect(fixture.connection.job == nil) }
        else {
            #expect(fixture.connection.accountState == .disconnected)
            #expect(fixture.connection.activeRegistrationID == nil)
            #expect(try fixture.store.load(registrationID: fixture.credentials.registrationID) == nil)
            #expect(fixture.preferences.string(forKey: "selectedRegistrationID") == nil)
            #expect(fixture.connection.notice == .unconfirmed)
        }
    }

    @Test func backgroundCancelsAndForegroundResumesSavedInput() async throws {
        let responses = ConnectionRequests()
        let block = DispatchSemaphore(value: 0)
        let fixture = try ConnectionFixture(response: { request in
            responses.append(request)
            if responses.values.count == 1 { _ = block.wait(timeout: .now() + 5) }
            return connectionCompletion()
        })
        defer { block.signal(); fixture.cleanup() }
        await fixture.connection.restore()
        #expect(fixture.connection.captureSample())
        let id = try #require(fixture.connection.job?.id)
        try await waitForConnectionRequest(fixture.requests, path: "/v1/responses")
        fixture.connection.enterBackground()
        block.signal()
        await fixture.connection.waitForProbe()
        #expect(fixture.connection.lastCompletedProbe == nil)
        #expect(try fixture.jobStore.load()?.state == .pending)
        await fixture.connection.enterForeground()
        await fixture.connection.waitForProbe()
        #expect(fixture.connection.job?.id == id)
        #expect(fixture.connection.lastCompletedProbe != nil)
        #expect(responses.values.count == 2)
    }

    @Test func expiredTerminalRefreshRemovesPlanEnabledStateAndSendsNoCatalog() async throws {
        let requests = ConnectionRequests()
        let store = ConnectionCredentialStore()
        let credentials = savedCredentials(now: .now)
        try store.replace(credentials)
        let session = syntheticSession { request in
            requests.append(request)
            return SessionReply(status: 400, data: Data(#"{"error":"invalid_grant"}"#.utf8))
        }
        let preferences = UserDefaults(suiteName: UUID().uuidString)!
        preferences.set(credentials.registrationID, forKey: "selectedRegistrationID")
        preferences.set(true, forKey: "openAISharingConsent")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = ChatGPTConnection(auth: AuthSession(session: session, store: store),
            client: ResponsesClient(session: session), jobStore: ProbeJobStore(directory: directory), preferences: preferences)
        await connection.restore()
        #expect(connection.accountState == .disconnected)
        #expect(!connection.planAuthorized)
        #expect(!connection.captureSample())
        #expect(requests.values.count == 1)
        #expect(requests.values.first?.url?.path == "/api/accounts/oauth/token")
        #expect(try store.load(registrationID: credentials.registrationID) == nil)
    }

    @Test func selectedKeychainRegistrationRestoresWithoutChoosingAnother() async throws {
        let store = CredentialStore(service: "com.yakov103.mivu.tests.connection.\(UUID().uuidString)")
        let selected = savedCredentials(now: .now, expired: false)
        let other = savedCredentials(now: .now, subject: "other-synthetic-account", expired: false)
        try store.replace(selected); try store.replace(other)
        defer { try? store.delete(registrationID: selected.registrationID); try? store.delete(registrationID: other.registrationID) }
        let preferences = UserDefaults(suiteName: UUID().uuidString)!
        preferences.set(selected.registrationID, forKey: "selectedRegistrationID")
        preferences.set(true, forKey: "openAISharingConsent")
        let session = syntheticSession { _ in connectionCatalog() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = ChatGPTConnection(auth: AuthSession(session: session, store: store),
            client: ResponsesClient(session: session), jobStore: ProbeJobStore(directory: directory), preferences: preferences)
        #expect(connection.activeRegistrationID == nil)
        await connection.restore()
        #expect(connection.activeRegistrationID == selected.registrationID)
        #expect(connection.accountState == .connected)
        #expect(try store.load(registrationID: other.registrationID) != nil)
    }
}

@MainActor private final class ConnectionFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let preferencesName = UUID().uuidString
    let preferences: UserDefaults
    let store = ConnectionCredentialStore()
    let credentials: Credentials
    let requests = ConnectionRequests()
    let jobStore: ProbeJobStore
    let connection: ChatGPTConnection

    init(permission: Bool = true, response: (@Sendable (URLRequest) throws -> SessionReply)? = nil,
         revocation: (@Sendable (URLRequest) throws -> SessionReply)? = nil) throws {
        preferences = UserDefaults(suiteName: preferencesName)!
        let saved = savedCredentials(now: .now, expired: false)
        credentials = Credentials(registration: saved.registration, accessToken: saved.accessToken,
            refreshToken: saved.refreshToken, idToken: saved.idToken,
            scopes: permission ? saved.scopes : ["openid"], expiresAt: saved.expiresAt)
        try store.replace(credentials)
        preferences.set(credentials.registrationID, forKey: "selectedRegistrationID")
        preferences.set(true, forKey: "openAISharingConsent")
        jobStore = ProbeJobStore(directory: directory)
        let requests = requests, jobStore = jobStore
        let session = syntheticSession { request in
            requests.append(request)
            switch request.url?.path {
            case "/v1/models": return connectionCatalog()
            case "/v1/responses":
                let saved = try #require(try jobStore.load())
                #expect(saved.state != .completed)
                #expect(saved.image == SyntheticConnectionProbe.image)
                return try response?(request) ?? connectionCompletion()
            case "/api/accounts/oauth/revoke": return try revocation?(request) ?? SessionReply(status: 503, data: Data())
            default: throw URLError(.badURL)
            }
        }
        connection = ChatGPTConnection(auth: AuthSession(session: session, store: store),
            client: ResponsesClient(session: session), jobStore: jobStore, preferences: preferences)
    }
    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
        preferences.removePersistentDomain(forName: preferencesName)
    }
}

private func connectionCatalog() -> SessionReply {
    SessionReply(status: 200, data: Data(#"{"models":[{"slug":"fixture-model","display_name":"Synthetic model","visibility":"list"},{"slug":"second-model","display_name":"Second synthetic model","visibility":"list"}]}"#.utf8))
}
private func connectionCompletion() -> SessionReply {
    SessionReply(status: 200, data: Data("event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"model\":\"fixture-model\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Synthetic completion\"}]}]}}\n\n".utf8))
}
private func waitForConnectionRequest(_ requests: ConnectionRequests, path: String) async throws {
    for _ in 0..<2_000 {
        if requests.values.contains(where: { $0.url?.path == path }) { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw URLError(.timedOut)
}

extension ConnectionTests {
    @Test func providerIneligibilityStaysPausedAcrossForegroundAndExplicitRestore() async throws {
        let fixture = try ConnectionFixture(response: { _ in SessionReply(status: 403, data: Data()) })
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        #expect(fixture.connection.captureSample())
        await fixture.connection.waitForProbe()
        let count = fixture.requests.values.count
        #expect(!fixture.connection.planAuthorized)
        await fixture.connection.enterForeground()
        fixture.connection.retry()
        await fixture.connection.waitForProbe()
        #expect(!fixture.connection.planAuthorized)
        #expect(fixture.requests.values.count == count)
        await fixture.connection.restore()
        #expect(!fixture.connection.planAuthorized)
        #expect(fixture.requests.values.count == count)
    }

    @Test func consumedCallbackExchangesOnceAndEnablesValidatedRegistration() async throws {
        let signing = try ConnectionSigningFixture()
        let requests = ConnectionRequests()
        let store = ConnectionCredentialStore()
        let session = syntheticSession { request in
            requests.append(request)
            switch request.url?.path {
            case "/api/accounts/oauth/token": return try tokenReply(idToken: signing.token())
            case "/.well-known/jwks.json": return SessionReply(status: 200, data: signing.keys)
            case "/v1/models": return connectionCatalog()
            default: throw URLError(.badURL)
            }
        }
        let preferences = UserDefaults(suiteName: UUID().uuidString)!
        preferences.set(true, forKey: "openAISharingConsent")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = ChatGPTConnection(auth: AuthSession(session: session, store: store),
            client: ResponsesClient(session: session), jobStore: ProbeJobStore(directory: directory), preferences: preferences)
        await connection.connect { url in
            let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            signing.setNonce(try #require(query.first { $0.name == "nonce" }?.value))
            #expect(query.first { $0.name == "client_id" }?.value == "dynamic_agent_client")
            let redirect = try #require(query.first { $0.name == "redirect_uri" }?.value)
            var callback = try #require(URLComponents(string: redirect))
            callback.queryItems = [URLQueryItem(name: "state", value: try #require(query.first { $0.name == "state" }?.value)),
                URLQueryItem(name: "code", value: "synthetic-code"), URLQueryItem(name: "client_id", value: "oaiapp_synthetic")]
            _ = try await URLSession.shared.data(from: #require(callback.url))
            throw CancellationError()
        }
        #expect(connection.accountState == .connected)
        let owner = try #require(connection.activeRegistrationID)
        #expect(preferences.string(forKey: "selectedRegistrationID") == owner)
        #expect(try store.load(registrationID: owner)?.planPermissionGranted == true)
        #expect(requests.values.filter { $0.url?.path == "/api/accounts/oauth/token" }.count == 1)
        #expect(connection.models.map(\.slug) == ["fixture-model", "second-model"])
    }
}

private final class ConnectionSigningFixture: @unchecked Sendable {
    private let signing: SyntheticIdentityToken
    private let lock = NSLock()
    private var nonce = ""
    var keys: Data { signing.jwks }
    init() throws { signing = try SyntheticIdentityToken() }
    func setNonce(_ value: String) { lock.withLock { nonce = value } }
    func token() throws -> String {
        let nonce = lock.withLock { self.nonce }
        let now = Int(Date.now.timeIntervalSince1970)
        return try signing.token(changes: ["nonce": nonce, "iat": now - 1, "exp": now + 300])
    }
}

extension ConnectionTests {
    @Test func cancellingDuringExchangePreservesOldRegistration() async throws {
        let signing = try ConnectionSigningFixture()
        let requests = ConnectionRequests()
        let block = DispatchSemaphore(value: 0)
        let store = ConnectionCredentialStore()
        let old = savedCredentials(now: .now, expired: false)
        try store.replace(old)
        let session = syntheticSession { request in
            requests.append(request)
            switch request.url?.path {
            case "/api/accounts/oauth/token":
                _ = block.wait(timeout: .now() + 5)
                return try tokenReply(idToken: signing.token())
            case "/.well-known/jwks.json": return SessionReply(status: 200, data: signing.keys)
            case "/v1/models": return connectionCatalog()
            default: throw URLError(.badURL)
            }
        }
        let preferences = UserDefaults(suiteName: UUID().uuidString)!
        preferences.set(old.registrationID, forKey: "selectedRegistrationID")
        preferences.set(true, forKey: "openAISharingConsent")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { block.signal(); try? FileManager.default.removeItem(at: directory) }
        let connection = ChatGPTConnection(auth: AuthSession(session: session, store: store),
            client: ResponsesClient(session: session), jobStore: ProbeJobStore(directory: directory), preferences: preferences)
        await connection.restore()
        let attempt = Task {
            await connection.connect { url in
                let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
                signing.setNonce(try #require(query.first { $0.name == "nonce" }?.value))
                #expect(query.first { $0.name == "client_id" }?.value == old.registration.issuedClientID)
                let redirect = try #require(query.first { $0.name == "redirect_uri" }?.value)
                var callback = try #require(URLComponents(string: redirect))
                callback.queryItems = [URLQueryItem(name: "state", value: try #require(query.first { $0.name == "state" }?.value)),
                    URLQueryItem(name: "code", value: "synthetic-code")]
                _ = try await URLSession.shared.data(from: #require(callback.url))
                throw CancellationError()
            }
        }
        try await waitForConnectionRequest(requests, path: "/api/accounts/oauth/token")
        connection.cancelConnection()
        block.signal()
        await attempt.value
        #expect(connection.activeRegistrationID == old.registrationID)
        #expect(connection.accountState == .connected)
        #expect(preferences.string(forKey: "selectedRegistrationID") == old.registrationID)
        #expect(try store.load(registrationID: old.registrationID) == old)
        #expect(requests.values.filter { $0.url?.path == "/api/accounts/oauth/token" }.count == 1)
    }
}

extension ConnectionTests {
    @Test func backgroundWhileDisconnectingDoesNotLeaveBusyState() async throws {
        let block = DispatchSemaphore(value: 0)
        let fixture = try ConnectionFixture(revocation: { _ in
            _ = block.wait(timeout: .now() + 5)
            return SessionReply(status: 503, data: Data())
        })
        defer { block.signal(); fixture.cleanup() }
        await fixture.connection.restore()
        let operation = Task { await fixture.connection.disconnect() }
        try await waitForConnectionRequest(fixture.requests, path: "/api/accounts/oauth/revoke")
        fixture.connection.enterBackground()
        block.signal()
        await operation.value
        await fixture.connection.enterForeground()
        #expect(!fixture.connection.isDisconnecting)
        #expect(!fixture.connection.isAnalyzing)
        #expect(fixture.connection.accountState == .disconnected)
        #expect(fixture.preferences.string(forKey: "selectedRegistrationID") == nil)
    }
}

extension ConnectionTests {
    @Test func failedLocalCredentialDeletionPreservesSelectionAndAllowsRetry() async throws {
        let fixture = try ConnectionFixture()
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        fixture.store.failDeletes = true
        await fixture.connection.disconnect()
        #expect(fixture.connection.notice == .storageFailed)
        #expect(fixture.connection.activeRegistrationID == fixture.credentials.registrationID)
        #expect(fixture.connection.accountState == .connected)
        #expect(fixture.preferences.string(forKey: "selectedRegistrationID") == fixture.credentials.registrationID)
        #expect(!fixture.connection.isDisconnecting)
        #expect(!fixture.requests.values.contains { $0.url?.path == "/api/accounts/oauth/revoke" })
        fixture.store.failDeletes = false
        await fixture.connection.disconnect()
        #expect(fixture.connection.accountState == .disconnected)
        #expect(fixture.connection.activeRegistrationID == nil)
        #expect(fixture.preferences.string(forKey: "selectedRegistrationID") == nil)
        #expect(try fixture.store.load(registrationID: fixture.credentials.registrationID) == nil)
        #expect(fixture.connection.notice == .unconfirmed)
    }
}

extension ConnectionTests {
    @Test func unreadableSavedSamplePreservesAcknowledgmentAndPreventsOverwrite() async throws {
        let directory = ConnectionFixtureDirectory()
        let fixture = try ConnectionFixture(response: { _ in
            try directory.corruptSavedJob()
            return SessionReply(status: 500, data: Data())
        })
        defer { fixture.cleanup() }
        directory.set(fixture.directory)
        await fixture.connection.restore()
        #expect(fixture.connection.captureSample())
        let id = try #require(fixture.connection.job?.id)
        await fixture.connection.waitForProbe()
        #expect(fixture.connection.job?.id == id)
        #expect(fixture.connection.lastCompletedProbe == nil)
        #expect(fixture.connection.notice == .storageFailed)
        #expect(!fixture.connection.canCapture)
        #expect(!fixture.connection.canRetry)
        #expect(!fixture.connection.captureSample())
        let onDisk = try Data(contentsOf: fixture.directory.appendingPathComponent("probe-job.json"))
        #expect(onDisk == Data("synthetic unreadable job".utf8))
        #expect(fixture.connection.inferenceState == .needsRetry)
    }

    @Test func failedDeleteRetainsSampleAndStopsAnalyzingStatus() async throws {
        let block = DispatchSemaphore(value: 0)
        let fixture = try ConnectionFixture(response: { _ in
            _ = block.wait(timeout: .now() + 5)
            return connectionCompletion()
        })
        defer { block.signal(); fixture.cleanup() }
        await fixture.connection.restore()
        #expect(fixture.connection.captureSample())
        let id = try #require(fixture.connection.job?.id)
        try await waitForConnectionRequest(fixture.requests, path: "/v1/responses")
        try Data("synthetic unreadable job".utf8).write(to: fixture.directory.appendingPathComponent("probe-job.json"))
        let operation = Task { await fixture.connection.deleteSample() }
        await Task.yield()
        block.signal()
        await operation.value
        #expect(fixture.connection.job?.id == id)
        #expect(fixture.connection.notice == .storageFailed)
        #expect(!fixture.connection.isAnalyzing)
        #expect(fixture.connection.inferenceState == .needsRetry)
        #expect(!fixture.connection.canCapture)
        #expect(!fixture.connection.canRetry)
    }
}

private final class ConnectionFixtureDirectory: @unchecked Sendable {
    private let lock = NSLock()
    private var directory: URL?
    func set(_ value: URL) { lock.withLock { directory = value } }
    func corruptSavedJob() throws {
        let directory = try #require(lock.withLock { self.directory })
        try Data("synthetic unreadable job".utf8).write(to: directory.appendingPathComponent("probe-job.json"))
    }
}

extension ConnectionTests {
    @Test func unreadableCompletedSlotHidesResultUntilTrustworthyReload() async throws {
        let fixture = try ConnectionFixture()
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        #expect(fixture.connection.captureSample())
        await fixture.connection.waitForProbe()
        let id = try #require(fixture.connection.job?.id)
        let file = fixture.directory.appendingPathComponent("probe-job.json")
        let validBytes = try Data(contentsOf: file)
        let count = fixture.requests.values.count
        try Data("synthetic unreadable job".utf8).write(to: file)
        await fixture.connection.enterForeground()
        #expect(fixture.connection.job?.id == id)
        #expect(fixture.connection.isStorageUnavailable)
        #expect(fixture.connection.lastCompletedProbe == nil)
        #expect(!fixture.connection.canCapture && !fixture.connection.canRetry)
        await fixture.connection.restore()
        await fixture.connection.loadModels()
        #expect(fixture.connection.isStorageUnavailable)
        #expect(!fixture.connection.canCapture && !fixture.connection.canRetry)
        #expect(fixture.requests.values.filter { $0.url?.path == "/v1/responses" }.count == 1)
        try validBytes.write(to: file)
        await fixture.connection.enterForeground()
        #expect(!fixture.connection.isStorageUnavailable)
        #expect(fixture.connection.lastCompletedProbe?.outputText == "Synthetic completion")
        #expect(fixture.connection.job?.id == id)
        #expect(fixture.requests.values.count == count + 1)
    }

    @Test func unreadableLaunchSlotBlocksCaptureWithoutActivatingCredentials() async throws {
        let fixture = try ConnectionFixture()
        defer { fixture.cleanup() }
        let directory = ConnectionFixtureDirectory()
        directory.set(fixture.directory)
        try fixture.jobStore.save(ProbeJob(text: "Synthetic", image: nil, model: "fixture-model",
            registrationID: fixture.credentials.registrationID))
        try directory.corruptSavedJob()
        await fixture.connection.restore()
        await fixture.connection.loadModels()
        #expect(fixture.connection.job == nil)
        #expect(fixture.connection.isStorageUnavailable)
        #expect(fixture.connection.activeRegistrationID == nil)
        #expect(!fixture.connection.captureSample())
        #expect(fixture.store.loads == 0)
        #expect(fixture.requests.values.isEmpty)
    }

    @Test func successfullyReloadedAbsentSlotAllowsNewCapture() async throws {
        let fixture = try ConnectionFixture()
        defer { fixture.cleanup() }
        await fixture.connection.restore()
        #expect(fixture.connection.captureSample())
        await fixture.connection.waitForProbe()
        let id = try #require(fixture.connection.job?.id)
        try fixture.jobStore.remove(id: id)
        await fixture.connection.enterForeground()
        #expect(fixture.connection.job == nil)
        #expect(!fixture.connection.isStorageUnavailable)
        #expect(fixture.connection.lastCompletedProbe == nil)
        #expect(fixture.connection.canCapture)
    }
}
