import Foundation
import Security
import Testing
@testable import Mivu

final class MemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: Credentials] = [:]
    private var mappings: [String: AccountRegistration] = [:]
    private var writeCount = 0
    private var shouldFailWrites = false
    private var shouldFailDeletes = false
    var failDeletes: Bool {
        get { lock.withLock { shouldFailDeletes } }
        set { lock.withLock { shouldFailDeletes = newValue } }
    }
    var failWrites: Bool {
        get { lock.withLock { shouldFailWrites } }
        set { lock.withLock { shouldFailWrites = newValue } }
    }
    func hostID() throws -> String { "urn:uuid:00000000-0000-4000-8000-000000000001" }
    func registrations() throws -> [AccountRegistration] { lock.withLock { Array(mappings.values) } }
    func load(registrationID: String) throws -> Credentials? { lock.withLock { records[registrationID] } }
    func replace(_ credentials: Credentials) throws {
        try lock.withLock {
            if shouldFailWrites { throw CredentialStoreError.invalidRecord }
            records[credentials.registrationID] = credentials
            mappings[credentials.registrationID] = credentials.registration
            writeCount += 1
        }
    }
    func delete(registrationID: String) throws {
        try lock.withLock {
            if shouldFailDeletes { throw CredentialStoreError.invalidRecord }
            records[registrationID] = nil
        }
    }
    var writes: Int { lock.withLock { writeCount } }
}

struct SessionReply: Sendable { let status: Int; let data: Data }
final class SessionFixtureRouter: @unchecked Sendable {
    static let shared = SessionFixtureRouter()
    private let lock = NSLock()
    private var handlers: [String: @Sendable (URLRequest) throws -> SessionReply] = [:]
    func insert(_ handler: @escaping @Sendable (URLRequest) throws -> SessionReply) -> String {
        lock.withLock { let id = UUID().uuidString; handlers[id] = handler; return id }
    }
    func handler(for request: URLRequest) -> (@Sendable (URLRequest) throws -> SessionReply)? {
        lock.withLock { handlers[request.value(forHTTPHeaderField: "X-Synthetic-Fixture") ?? ""] }
    }
}
final class SessionFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var capturedRequest = request
        if capturedRequest.httpBody == nil, let stream = capturedRequest.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var bytes = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
            }
            capturedRequest.httpBody = data
        }
        let fixtureRequest = capturedRequest
        DispatchQueue.global().async { [self] in
            do {
                let handler = try #require(SessionFixtureRouter.shared.handler(for: fixtureRequest))
                let reply = try handler(fixtureRequest)
                let url = try #require(fixtureRequest.url)
                let response = try #require(HTTPURLResponse(url: url, statusCode: reply.status,
                    httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]))
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: reply.data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() {}
}
func syntheticSession(_ handler: @escaping @Sendable (URLRequest) throws -> SessionReply) -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SessionFixtureProtocol.self]
    config.httpAdditionalHeaders = ["X-Synthetic-Fixture": SessionFixtureRouter.shared.insert(handler)]
    return URLSession(configuration: config)
}
func syntheticCode() -> AuthorizationCode {
    AuthorizationCode(code: "synthetic-code", issuedClientID: "oaiapp_synthetic",
                      redirectURL: URL(string: "http://127.0.0.1:54321/auth/callback")!)
}
func tokenReply(idToken: String? = nil, access: String = "synthetic-access", refresh: String? = "synthetic-refresh",
                scope: String? = "openid offline_access resource.invoke chatgpt.tokens.use.direct") throws -> SessionReply {
    var fields: [String: Any] = ["access_token": access, "token_type": "Bearer", "expires_in": 3600]
    fields["refresh_token"] = refresh
    fields["id_token"] = idToken
    fields["scope"] = scope
    return SessionReply(status: 200, data: try JSONSerialization.data(withJSONObject: fields))
}

struct SessionTests {
    @Test func successfulExchangePersistsCompleteRegistration() async throws {
        let fixture = try SyntheticIdentityToken()
        let token = try fixture.token()
        let keys = fixture.jwks
        let reply = try tokenReply(idToken: token)
        let store = MemoryCredentialStore()
        let session = AuthSession(session: syntheticSession { request in
            if request.url?.path == "/.well-known/jwks.json" { return SessionReply(status: 200, data: keys) }
            return reply
        }, store: store)
        let snapshot = try await session.establish(code: syntheticCode(), verifier: "synthetic-verifier",
                                                   nonce: fixture.nonce, now: fixture.now)
        #expect(snapshot.planPermissionGranted)
        #expect(try store.load(registrationID: snapshot.registrationID) != nil)
        #expect(store.writes == 1)
    }
}

final class SessionRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    func add(_ request: URLRequest) { lock.withLock { recorded.append(request) } }
    var requests: [URLRequest] { lock.withLock { recorded } }
    func waitForRequest() async throws {
        for _ in 0..<2_000 {
            if !requests.isEmpty { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw SessionError.networkUnavailable
    }
}
func savedCredentials(now: Date, subject: String = "synthetic-account", clientID: String = "oaiapp_synthetic",
                      expired: Bool = true) -> Credentials {
    Credentials(registration: AccountRegistration(identity: VerifiedIdentity(issuer: "https://auth.openai.com", subject: subject),
        issuedClientID: clientID), accessToken: "synthetic-old-access", refreshToken: "synthetic-old-refresh",
        idToken: "synthetic-retained-hint", scopes: ["openid", "offline_access", "resource.invoke", "chatgpt.tokens.use.direct"],
        expiresAt: now.addingTimeInterval(expired ? -1 : 3_600))
}
func formFields(_ request: URLRequest) -> [String: String] {
    let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    return Dictionary(uniqueKeysWithValues: body.split(separator: "&").compactMap { field in
        let pieces = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.count == 2, let name = String(pieces[0]).removingPercentEncoding,
              let value = String(pieces[1]).removingPercentEncoding else { return nil }
        return (name, value)
    })
}

extension SessionTests {
    @Test func constructionDoesNotLoadOrRequestCredentials() async {
        let log = SessionRequestLog()
        let session = AuthSession(session: syntheticSession { request in
            log.add(request)
            throw URLError(.notConnectedToInternet)
        }, store: MemoryCredentialStore())
        #expect(await session.snapshot() == nil)
        #expect(log.requests.isEmpty)
    }

    @Test func exchangeUsesExactCallbackVerifierResourceAndIssuedID() async throws {
        let fixture = try SyntheticIdentityToken()
        let reply = try tokenReply(idToken: fixture.token())
        let keys = fixture.jwks
        let log = SessionRequestLog()
        let session = AuthSession(session: syntheticSession { request in
            log.add(request)
            return request.url?.path == "/.well-known/jwks.json" ? SessionReply(status: 200, data: keys) : reply
        }, store: MemoryCredentialStore())
        let code = syntheticCode()
        _ = try await session.establish(code: code, verifier: "synthetic+verifier&=?", nonce: fixture.nonce, now: fixture.now)
        let request = try #require(log.requests.first { $0.httpMethod == "POST" })
        let fields = formFields(request)
        #expect(request.url?.absoluteString == "https://auth.openai.com/api/accounts/oauth/token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(fields["client_id"] == code.issuedClientID)
        #expect(fields["redirect_uri"] == code.redirectURL.absoluteString)
        #expect(fields["code_verifier"] == "synthetic+verifier&=?")
        #expect(fields["resource"] == "https://api.openai.com/v1")
        #expect(fields["grant_type"] == "authorization_code")
        #expect(fields["client_secret"] == nil)
    }

    @Test(arguments: ["openid", "openid resource.invoke", "openid chatgpt.tokens.use.direct", ""])
    func validIdentityWithoutRequiredScopesNeverGrantsInference(_ scopes: String) async throws {
        let fixture = try SyntheticIdentityToken()
        let keys = fixture.jwks
        let reply = try tokenReply(idToken: fixture.token(), scope: scopes)
        let log = SessionRequestLog()
        let session = AuthSession(session: syntheticSession { request in
            log.add(request)
            return request.url?.path == "/.well-known/jwks.json" ? SessionReply(status: 200, data: keys) : reply
        }, store: MemoryCredentialStore())
        let snapshot = try await session.establish(code: syntheticCode(), verifier: "synthetic-verifier",
            nonce: fixture.nonce, now: fixture.now)
        #expect(!snapshot.planPermissionGranted)
        await #expect(throws: SessionError.planPermissionMissing) { try await session.accessToken(now: fixture.now) }
        #expect(log.requests.count == 2)
    }

    @Test(arguments: [true, false])
    func unknownKeyFetchesTrustedJWKSOnceMore(_ recovered: Bool) async throws {
        let fixture = try SyntheticIdentityToken()
        let keys = fixture.jwks
        let reply = try tokenReply(idToken: fixture.token())
        let log = SessionRequestLog()
        let session = AuthSession(session: syntheticSession { request in
            log.add(request)
            if request.url?.path == "/.well-known/jwks.json" {
                let count = log.requests.filter { $0.url?.path == "/.well-known/jwks.json" }.count
                return SessionReply(status: 200, data: recovered && count == 2 ? keys : Data("{\"keys\":[]}".utf8))
            }
            return reply
        }, store: MemoryCredentialStore())
        if recovered {
            _ = try await session.establish(code: syntheticCode(), verifier: "synthetic-verifier", nonce: fixture.nonce, now: fixture.now)
        } else {
            await #expect(throws: IDTokenError.unknownKey) {
                try await session.establish(code: syntheticCode(), verifier: "synthetic-verifier", nonce: fixture.nonce, now: fixture.now)
            }
        }
        let fetched = log.requests.filter { $0.url?.path == "/.well-known/jwks.json" }
        #expect(fetched.count == 2)
        #expect(fetched.allSatisfy { $0.url?.absoluteString == "https://auth.openai.com/.well-known/jwks.json" })
    }

    @Test func returningAccountSubjectMismatchPreservesOldRegistration() async throws {
        let fixture = try SyntheticIdentityToken()
        let keys = fixture.jwks
        let reply = try tokenReply(idToken: fixture.token(changes: ["sub": "another-synthetic-account"]))
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: fixture.now)
        try store.replace(old)
        let session = AuthSession(session: syntheticSession { request in
            request.url?.path == "/.well-known/jwks.json" ? SessionReply(status: 200, data: keys) : reply
        }, store: store)
        _ = try await session.restore(registrationID: old.registrationID)
        await #expect(throws: SessionError.identityMismatch) {
            try await session.establish(code: syntheticCode(), verifier: "synthetic-verifier", nonce: fixture.nonce,
                                         returningRegistrationID: old.registrationID, now: fixture.now)
        }
        #expect(await session.snapshot()?.registrationID == old.registrationID)
        #expect(try store.load(registrationID: old.registrationID) == old)
        #expect(store.writes == 1)
    }

    @Test func failedOrCanceledConnectPreservesOldCredentials() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: now)
        try store.replace(old)
        for cancel in [false, true] {
            let log = SessionRequestLog()
            let gate = DispatchSemaphore(value: 0)
            let session = AuthSession(session: syntheticSession { request in
                log.add(request)
                if cancel { _ = gate.wait(timeout: .now() + 5) }
                return SessionReply(status: 503, data: Data())
            }, store: store)
            _ = try await session.restore(registrationID: old.registrationID)
            let task = Task { try await session.establish(code: syntheticCode(), verifier: "synthetic-verifier",
                                                          nonce: "synthetic-nonce", now: now) }
            try await log.waitForRequest()
            if cancel { task.cancel(); gate.signal() }
            do { _ = try await task.value; Issue.record("Connect unexpectedly succeeded") } catch {}
            #expect(await session.snapshot()?.registrationID == old.registrationID)
            #expect(try store.load(registrationID: old.registrationID) == old)
        }
        #expect(store.writes == 1)
    }

    @Test func failedAtomicSaveDoesNotActivateNewTokenSet() async throws {
        let fixture = try SyntheticIdentityToken()
        let keys = fixture.jwks
        let reply = try tokenReply(idToken: fixture.token())
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: fixture.now)
        try store.replace(old)
        store.failWrites = true
        let session = AuthSession(session: syntheticSession { request in
            request.url?.path == "/.well-known/jwks.json" ? SessionReply(status: 200, data: keys) : reply
        }, store: store)
        _ = try await session.restore(registrationID: old.registrationID)
        await #expect(throws: CredentialStoreError.invalidRecord) {
            try await session.establish(code: syntheticCode(), verifier: "synthetic-verifier", nonce: fixture.nonce, now: fixture.now)
        }
        #expect(try store.load(registrationID: old.registrationID) == old)
        #expect(await session.snapshot()?.registrationID == old.registrationID)
    }

    @Test func concurrentRefreshRotatesOneCompleteRecordAndRestoresIt() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: now)
        try store.replace(old)
        let log = SessionRequestLog()
        let gate = DispatchSemaphore(value: 0)
        let reply = try tokenReply(access: "synthetic-renewed-access", refresh: "synthetic-replacement-refresh", scope: nil)
        let transport = syntheticSession { request in
            log.add(request)
            _ = gate.wait(timeout: .now() + 5)
            return reply
        }
        let session = AuthSession(session: transport, store: store)
        _ = try await session.restore(registrationID: old.registrationID)
        let first = Task { try await session.accessToken(now: now) }
        try await log.waitForRequest()
        let second = Task { try await session.accessToken(now: now) }
        try await Task.sleep(for: .milliseconds(20))
        gate.signal()
        let firstToken = try await first.value
        let secondToken = try await second.value
        #expect(firstToken == secondToken)
        #expect(log.requests.count == 1)
        let fields = formFields(try #require(log.requests.first))
        #expect(fields["grant_type"] == "refresh_token")
        #expect(fields["client_id"] == old.registration.issuedClientID)
        #expect(fields["resource"] == "https://api.openai.com/v1")
        #expect(fields["scope"] == nil)
        let replacement = try #require(try store.load(registrationID: old.registrationID))
        #expect(replacement.refreshToken != old.refreshToken)
        #expect(replacement.accessToken != old.accessToken)
        #expect(replacement.scopes == old.scopes)
        #expect(replacement.idToken == old.idToken)
        #expect(store.writes == 2)
        let restarted = AuthSession(session: transport, store: store)
        _ = try await restarted.restore(registrationID: old.registrationID)
        #expect(try await restarted.accessToken(now: now) == firstToken)
        #expect(log.requests.count == 1)
    }

    @Test(arguments: ["", "openid resource.invoke"])
    func refreshWithReducedScopesDisablesPlanUsage(_ scope: String) async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: now)
        try store.replace(old)
        let reply = try tokenReply(scope: scope)
        let session = AuthSession(session: syntheticSession { _ in reply }, store: store)
        _ = try await session.restore(registrationID: old.registrationID)
        await #expect(throws: SessionError.planPermissionMissing) { try await session.accessToken(now: now) }
        #expect(await session.snapshot()?.planPermissionGranted == false)
        #expect(try store.load(registrationID: old.registrationID)?.scopes == Set(scope.split(separator: " ").map(String.init)))
    }

    @Test(arguments: [true, false])
    func transientRefreshFailuresPreserveCredentials(_ networkFailure: Bool) async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: now)
        try store.replace(old)
        let session = AuthSession(session: syntheticSession { _ in
            if networkFailure { throw URLError(.notConnectedToInternet) }
            return SessionReply(status: 503, data: Data())
        }, store: store)
        _ = try await session.restore(registrationID: old.registrationID)
        await #expect(throws: (any Error).self) { try await session.accessToken(now: now) }
        #expect(try store.load(registrationID: old.registrationID) == old)
        #expect(await session.snapshot()?.registrationID == old.registrationID)
    }

    @Test(arguments: ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"])
    func terminalRefreshFailureClearsOnlyItsCredentialRecord(_ error: String) async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: now)
        let other = savedCredentials(now: now, subject: "another-synthetic-account", clientID: "oaiapp_other")
        try store.replace(old)
        try store.replace(other)
        let body = try JSONEncoder().encode(["error": error])
        let session = AuthSession(session: syntheticSession { _ in SessionReply(status: 400, data: body) }, store: store)
        _ = try await session.restore(registrationID: old.registrationID)
        await #expect(throws: SessionError.invalidRefresh) { try await session.accessToken(now: now) }
        #expect(await session.snapshot() == nil)
        #expect(try store.load(registrationID: old.registrationID) == nil)
        #expect(try store.load(registrationID: other.registrationID) == other)
        #expect(try store.registrations().count == 2)
    }

    @Test(arguments: [true, false])
    func logoutDeletesLocallyWhenRemoteRevocationFails(_ networkFailure: Bool) async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: now)
        try store.replace(old)
        let log = SessionRequestLog()
        let session = AuthSession(session: syntheticSession { request in
            log.add(request)
            if networkFailure { throw URLError(.notConnectedToInternet) }
            return SessionReply(status: 503, data: Data())
        }, store: store)
        _ = try await session.restore(registrationID: old.registrationID)
        let result = try await session.disconnect()
        #expect(result == .unconfirmed)
        #expect(await session.snapshot() == nil)
        #expect(try store.load(registrationID: old.registrationID) == nil)
        #expect(try store.registrations().count == 1)
        #expect(log.requests.first?.url?.absoluteString == "https://auth.openai.com/api/accounts/oauth/revoke")
        #expect(formFields(try #require(log.requests.first))["token_type_hint"] == "refresh_token")
    }

    @Test func logoutConfirmsAnEmptyHTTP200() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: now)
        try store.replace(old)
        let session = AuthSession(session: syntheticSession { _ in SessionReply(status: 200, data: Data()) }, store: store)
        _ = try await session.restore(registrationID: old.registrationID)
        #expect(try await session.disconnect() == .confirmed)
        #expect(try store.load(registrationID: old.registrationID) == nil)
    }

    @Test(arguments: [true, false])
    func lateConnectCannotReplaceLogoutOrAccountSwitch(_ logout: Bool) async throws {
        let fixture = try SyntheticIdentityToken()
        let keys = fixture.jwks
        let reply = try tokenReply(idToken: fixture.token())
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: fixture.now)
        let other = savedCredentials(now: fixture.now, subject: "another-synthetic-account", clientID: "oaiapp_other")
        try store.replace(old)
        try store.replace(other)
        let log = SessionRequestLog()
        let gate = DispatchSemaphore(value: 0)
        let session = AuthSession(session: syntheticSession { request in
            if request.url?.path == "/api/accounts/oauth/revoke" { return SessionReply(status: 200, data: Data()) }
            if request.url?.path == "/.well-known/jwks.json" { return SessionReply(status: 200, data: keys) }
            log.add(request)
            _ = gate.wait(timeout: .now() + 5)
            return reply
        }, store: store)
        _ = try await session.restore(registrationID: old.registrationID)
        let pending = Task { try await session.establish(code: syntheticCode(), verifier: "synthetic-verifier",
                                                        nonce: fixture.nonce, now: fixture.now) }
        try await log.waitForRequest()
        if logout { _ = try await session.disconnect() }
        else { _ = try await session.restore(registrationID: other.registrationID) }
        gate.signal()
        await #expect(throws: SessionError.sessionChanged) { try await pending.value }
        #expect(await session.snapshot()?.registrationID == (logout ? nil : other.registrationID))
        #expect(store.writes == 2)
    }

    @Test(arguments: [true, false])
    func lateRefreshCannotReplaceLogoutOrAccountSwitch(_ logout: Bool) async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: now)
        let other = savedCredentials(now: now, subject: "another-synthetic-account", clientID: "oaiapp_other", expired: false)
        try store.replace(old)
        try store.replace(other)
        let log = SessionRequestLog()
        let gate = DispatchSemaphore(value: 0)
        let reply = try tokenReply()
        let session = AuthSession(session: syntheticSession { request in
            if request.url?.path == "/api/accounts/oauth/revoke" { return SessionReply(status: 200, data: Data()) }
            log.add(request)
            _ = gate.wait(timeout: .now() + 5)
            return reply
        }, store: store)
        _ = try await session.restore(registrationID: old.registrationID)
        let pending = Task { try await session.accessToken(now: now, expectedRegistrationID: old.registrationID) }
        try await log.waitForRequest()
        if logout {
            _ = try await session.disconnect()
            gate.signal()
            await #expect(throws: SessionError.sessionChanged) { try await pending.value }
        } else {
            let selection = Task { try await session.restore(registrationID: other.registrationID) }
            try await Task.sleep(for: .milliseconds(20))
            gate.signal()
            _ = try await selection.value
            if let token = try? await pending.value { #expect(token != other.accessToken) }
            #expect(try store.load(registrationID: old.registrationID)?.refreshToken != old.refreshToken)
        }
        #expect(await session.snapshot()?.registrationID == (logout ? nil : other.registrationID))
        #expect(try store.load(registrationID: other.registrationID) == other)
        #expect(store.writes == (logout ? 2 : 3))
    }

    @Test func registrationScopedTokenLookupRejectsOtherOwnersWithoutNetwork() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MemoryCredentialStore()
        let current = savedCredentials(now: now, expired: false)
        try store.replace(current)
        let log = SessionRequestLog()
        let session = AuthSession(session: syntheticSession { request in
            log.add(request)
            throw URLError(.notConnectedToInternet)
        }, store: store)
        _ = try await session.restore(registrationID: current.registrationID)
        await #expect(throws: SessionError.sessionChanged) {
            try await session.accessToken(now: now, expectedRegistrationID: "different-synthetic-registration")
        }
        #expect(log.requests.isEmpty)
    }
}

extension SessionTests {
    @Test func failedReauthorizationDoesNotCancelRotatingRefresh() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: now)
        try store.replace(old)
        let refreshLog = SessionRequestLog()
        let gate = DispatchSemaphore(value: 0)
        let reply = try tokenReply()
        let session = AuthSession(session: syntheticSession { request in
            if formFields(request)["grant_type"] == "authorization_code" {
                return SessionReply(status: 503, data: Data())
            }
            refreshLog.add(request)
            _ = gate.wait(timeout: .now() + 5)
            return reply
        }, store: store)
        _ = try await session.restore(registrationID: old.registrationID)
        let refresh = Task { try await session.accessToken(now: now) }
        try await refreshLog.waitForRequest()
        await #expect(throws: SessionError.providerFailure(503)) {
            try await session.establish(code: syntheticCode(), verifier: "synthetic-verifier", nonce: "synthetic-nonce", now: now)
        }
        gate.signal()
        _ = try await refresh.value
        let replacement = try #require(try store.load(registrationID: old.registrationID))
        #expect(replacement.refreshToken != old.refreshToken)
        #expect(await session.snapshot()?.registrationID == old.registrationID)
        #expect(store.writes == 2)
    }

    @Test func successfulNewAccountConnectPersistsPreviousRotatingRefreshBeforeSwitch() async throws {
        let fixture = try SyntheticIdentityToken()
        let now = fixture.now
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: now, subject: "previous-synthetic-account", clientID: "oaiapp_previous")
        try store.replace(old)
        let keys = fixture.jwks
        let authorizeReply = try tokenReply(idToken: fixture.token())
        let refreshReply = try tokenReply()
        let refreshLog = SessionRequestLog()
        let authorizeLog = SessionRequestLog()
        let gate = DispatchSemaphore(value: 0)
        let session = AuthSession(session: syntheticSession { request in
            if request.url?.path == "/.well-known/jwks.json" { return SessionReply(status: 200, data: keys) }
            if formFields(request)["grant_type"] == "authorization_code" {
                authorizeLog.add(request)
                return authorizeReply
            }
            refreshLog.add(request)
            _ = gate.wait(timeout: .now() + 5)
            return refreshReply
        }, store: store)
        _ = try await session.restore(registrationID: old.registrationID)
        let refresh = Task { try await session.accessToken(now: now) }
        try await refreshLog.waitForRequest()
        let connect = Task { try await session.establish(code: syntheticCode(), verifier: "synthetic-verifier",
                                                         nonce: fixture.nonce, now: now) }
        try await authorizeLog.waitForRequest()
        try await Task.sleep(for: .milliseconds(20))
        #expect(await session.snapshot()?.registrationID == old.registrationID)
        gate.signal()
        _ = try? await refresh.value
        let selected = try await connect.value
        #expect(selected.registrationID != old.registrationID)
        #expect(try store.load(registrationID: old.registrationID)?.refreshToken != old.refreshToken)
        #expect(store.writes == 3)
    }

    @Test func validationAndExpiryUseReceiptClockAfterNetworkDelay() async throws {
        let fixture = try SyntheticIdentityToken()
        let start = Date.now
        let seconds = Int(start.timeIntervalSince1970)
        let token = try fixture.token(changes: ["iat": seconds + 6, "exp": seconds + 300])
        let reply = try tokenReply(idToken: token)
        let keys = fixture.jwks
        let store = MemoryCredentialStore()
        let session = AuthSession(session: syntheticSession { request in
            if request.url?.path == "/.well-known/jwks.json" { return SessionReply(status: 200, data: keys) }
            Thread.sleep(forTimeInterval: 2.1)
            return reply
        }, store: store)
        let snapshot = try await session.establish(code: syntheticCode(), verifier: "synthetic-verifier", nonce: fixture.nonce)
        let saved = try #require(try store.load(registrationID: snapshot.registrationID))
        #expect(saved.expiresAt > start.addingTimeInterval(3_601))
    }
}

extension SessionTests {
    @Test func redirectPolicyPreventsCredentialBodyReplay() throws {
        let session = URLSession(configuration: .ephemeral)
        let original = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!)
        let task = session.dataTask(with: original)
        let response = try #require(HTTPURLResponse(url: original.url!, statusCode: 307, httpVersion: "HTTP/1.1", headerFields: nil))
        let redirected = URLRequest(url: URL(string: "https://untrusted.example/token")!)
        let log = SessionRequestLog()
        RejectAuthRedirects().urlSession(session, task: task, willPerformHTTPRedirection: response,
            newRequest: redirected) { request in
                if let request { log.add(request) }
            }
        #expect(log.requests.isEmpty)
        session.invalidateAndCancel()
    }
}

#if os(iOS)
extension SessionTests {
    @Test func keychainKeepsStableHostAndIsolatedRegistrationsWithDeviceOnlyProtection() throws {
        let service = "com.yakov103.mivu.synthetic-tests.\(UUID().uuidString)"
        let store = CredentialStore(service: service)
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                               kSecAttrService as String: service] as CFDictionary) }
        let host = try store.hostID()
        #expect(try store.hostID() == host)
        #expect(host.hasPrefix("urn:uuid:"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = savedCredentials(now: now)
        let second = savedCredentials(now: now, subject: "another-synthetic-account")
        let third = savedCredentials(now: now, clientID: "oaiapp_other")
        try store.replace(first)
        try store.replace(second)
        try store.replace(third)
        #expect(try store.registrations().count == 3)
        #expect(try store.load(registrationID: first.registrationID) == first)
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "credentials:\(first.registrationID)",
            kSecReturnAttributes as String: true] as CFDictionary, &result)
        #expect(status == errSecSuccess)
        let attributes = try #require(result as? [String: Any])
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        try store.delete(registrationID: first.registrationID)
        #expect(try store.load(registrationID: first.registrationID) == nil)
        #expect(try store.load(registrationID: second.registrationID) == second)
        #expect(try store.load(registrationID: third.registrationID) == third)
        #expect(try store.registrations().count == 3)
        #expect(try store.hostID() == host)
    }
}
#endif

extension SessionTests {
    @Test func concurrentRefreshStorageFailureNeverReturnsOldExpiredToken() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: now)
        try store.replace(old)
        store.failWrites = true
        let log = SessionRequestLog()
        let gate = DispatchSemaphore(value: 0)
        let reply = try tokenReply()
        let session = AuthSession(session: syntheticSession { request in
            log.add(request)
            _ = gate.wait(timeout: .now() + 5)
            return reply
        }, store: store)
        _ = try await session.restore(registrationID: old.registrationID)
        let first = Task { try await session.accessToken(now: now) }
        try await log.waitForRequest()
        let second = Task { try await session.accessToken(now: now) }
        try await Task.sleep(for: .milliseconds(20))
        gate.signal()
        await #expect(throws: (any Error).self) { try await first.value }
        await #expect(throws: (any Error).self) { try await second.value }
        #expect(try store.load(registrationID: old.registrationID) == old)
        #expect(store.writes == 1)
    }

    @Test func lateRevocationCannotDeleteNewCredentialsForSameRegistration() async throws {
        let fixture = try SyntheticIdentityToken()
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: fixture.now)
        try store.replace(old)
        let log = SessionRequestLog()
        let gate = DispatchSemaphore(value: 0)
        let reply = try tokenReply(idToken: fixture.token())
        let keys = fixture.jwks
        let session = AuthSession(session: syntheticSession { request in
            if request.url?.path == "/api/accounts/oauth/revoke" {
                log.add(request)
                _ = gate.wait(timeout: .now() + 5)
                return SessionReply(status: 503, data: Data())
            }
            return request.url?.path == "/.well-known/jwks.json" ? SessionReply(status: 200, data: keys) : reply
        }, store: store)
        _ = try await session.restore(registrationID: old.registrationID)
        let logout = Task { try await session.disconnect() }
        try await log.waitForRequest()
        #expect(try store.load(registrationID: old.registrationID) == nil)
        let renewed = try await session.establish(code: syntheticCode(), verifier: "synthetic-verifier",
            nonce: fixture.nonce, returningRegistrationID: old.registrationID, now: fixture.now)
        gate.signal()
        #expect(try await logout.value == .unconfirmed)
        #expect(await session.snapshot()?.registrationID == renewed.registrationID)
        #expect(try store.load(registrationID: renewed.registrationID) != nil)
        #expect(store.writes == 2)
    }
}

extension SessionTests {
    @Test func logoutDeletionFailureCanBeRetriedBeforeRestoration() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MemoryCredentialStore()
        let old = savedCredentials(now: now, expired: false)
        try store.replace(old)
        let log = SessionRequestLog()
        let transport = syntheticSession { request in
            log.add(request)
            return SessionReply(status: 200, data: Data())
        }
        let session = AuthSession(session: transport, store: store)
        _ = try await session.restore(registrationID: old.registrationID)
        store.failDeletes = true
        await #expect(throws: CredentialStoreError.invalidRecord) { try await session.disconnect() }
        #expect(try store.load(registrationID: old.registrationID) != nil)
        #expect(log.requests.isEmpty)
        store.failDeletes = false
        #expect(try await session.disconnect() == .confirmed)
        #expect(try store.load(registrationID: old.registrationID) == nil)
        #expect(await session.snapshot() == nil)
        #expect(log.requests.count == 1)
        let restarted = AuthSession(session: transport, store: store)
        #expect(try await restarted.restore(registrationID: old.registrationID) == nil)
        #expect(try store.registrations().count == 1)
    }
}
