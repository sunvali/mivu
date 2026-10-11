import Foundation

enum SessionError: Error, Equatable {
    case noActiveSession, planPermissionMissing, invalidRegistration, identityMismatch
    case invalidResponse, networkUnavailable, providerFailure(Int), invalidRefresh, sessionChanged
}

enum RevocationOutcome: Equatable, Sendable { case confirmed, unconfirmed }

actor AuthSession {
    private let session: URLSession
    private let store: any CredentialStoring
    private var active: Credentials?
    private var generation = 0
    private var connectionAttempt = 0
    private var trustedKeys: Data?
    private var refreshing: (id: UUID, task: Task<Credentials, any Error>)?

    init(session: URLSession = .shared, store: any CredentialStoring = CredentialStore()) {
        self.session = session
        self.store = store
    }

    func hostID() throws -> String { try store.hostID() }
    func registrations() throws -> [AccountRegistration] { try store.registrations() }
    func snapshot() -> SessionSnapshot? { active.map(SessionSnapshot.init) }

    func restore(registrationID: String) async throws -> SessionSnapshot? {
        connectionAttempt += 1
        let attempt = connectionAttempt
        let revision = generation
        await settleCurrentRefresh()
        try Task.checkCancellation()
        guard revision == generation, attempt == connectionAttempt else { throw SessionError.sessionChanged }
        let credentials = try store.load(registrationID: registrationID)
        invalidatePendingWork()
        active = credentials
        return snapshot()
    }

    func establish(code: AuthorizationCode, verifier: String, nonce: String,
                   returningRegistrationID: String? = nil, now: Date? = nil) async throws -> SessionSnapshot {
        guard !code.issuedClientID.isEmpty, code.issuedClientID != "dynamic_agent_client",
              !code.code.isEmpty, !verifier.isEmpty, !nonce.isEmpty else { throw SessionError.invalidRegistration }
        let expected: AccountRegistration?
        if let returningRegistrationID {
            expected = try store.registrations().first { $0.id == returningRegistrationID }
            guard let expected, expected.issuedClientID == code.issuedClientID else {
                throw SessionError.invalidRegistration
            }
        } else {
            expected = active?.registration.issuedClientID == code.issuedClientID ? active?.registration : nil
        }
        connectionAttempt += 1
        let attempt = connectionAttempt
        let revision = generation
        let fields = ["grant_type": "authorization_code", "client_id": code.issuedClientID,
                      "code": code.code, "code_verifier": verifier,
                      "redirect_uri": code.redirectURL.absoluteString, "resource": Self.resource]
        let reply = try await Self.exchange(fields, session: session, isRefresh: false)
        let receivedAt = now ?? .now
        try Task.checkCancellation()
        guard revision == generation, attempt == connectionAttempt else { throw SessionError.sessionChanged }
        guard let idToken = reply.id_token, !idToken.isEmpty else { throw SessionError.invalidResponse }
        if trustedKeys == nil { trustedKeys = try await Self.fetchKeys(session: session) }
        guard let keys = trustedKeys else { throw SessionError.invalidResponse }
        let identity: VerifiedIdentity
        do {
            identity = try IDTokenValidator().validate(idToken, jwks: keys, clientID: code.issuedClientID,
                                                       nonce: nonce, now: now ?? .now)
        } catch IDTokenError.unknownKey {
            let refreshed = try await Self.fetchKeys(session: session)
            trustedKeys = refreshed
            identity = try IDTokenValidator().validate(idToken, jwks: refreshed, clientID: code.issuedClientID,
                                                       nonce: nonce, now: now ?? .now)
        }
        try Task.checkCancellation()
        guard revision == generation, attempt == connectionAttempt else { throw SessionError.sessionChanged }
        guard expected == nil || expected?.identity == identity else { throw SessionError.identityMismatch }
        let scopes = Set((reply.scope ?? "").split(separator: " ").map(String.init))
        if scopes.contains("offline_access") && (reply.refresh_token?.isEmpty != false) {
            throw SessionError.invalidResponse
        }
        let credentials = Credentials(registration: AccountRegistration(identity: identity,
            issuedClientID: code.issuedClientID), accessToken: reply.access_token,
            refreshToken: reply.refresh_token, idToken: idToken, scopes: scopes,
            expiresAt: receivedAt.addingTimeInterval(TimeInterval(reply.expires_in)))
        await settleCurrentRefresh()
        try Task.checkCancellation()
        guard revision == generation, attempt == connectionAttempt else { throw SessionError.sessionChanged }
        try store.replace(credentials)
        invalidatePendingWork()
        active = credentials
        return SessionSnapshot(credentials)
    }

    func accessToken(now: Date? = nil, expectedRegistrationID: String? = nil) async throws -> String {
        guard let credentials = active else { throw SessionError.noActiveSession }
        guard expectedRegistrationID == nil || expectedRegistrationID == credentials.registrationID else {
            throw SessionError.sessionChanged
        }
        guard credentials.planPermissionGranted else { throw SessionError.planPermissionMissing }
        if credentials.expiresAt > (now ?? .now).addingTimeInterval(30) { return credentials.accessToken }
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            try store.delete(registrationID: credentials.registrationID)
            active = nil
            throw SessionError.invalidRefresh
        }
        let revision = generation
        let pending: (id: UUID, task: Task<Credentials, any Error>)
        if let refreshing { pending = refreshing }
        else {
            let session = session
            let task = Task {
                let reply = try await Self.exchange(["grant_type": "refresh_token",
                    "client_id": credentials.registration.issuedClientID, "refresh_token": refreshToken,
                    "resource": Self.resource], session: session, isRefresh: true)
                let receivedAt = now ?? .now
                guard let replacement = reply.refresh_token, !replacement.isEmpty else {
                    throw SessionError.invalidResponse
                }
                let scopes = reply.scope.map { Set($0.split(separator: " ").map(String.init)) } ?? credentials.scopes
                return Credentials(registration: credentials.registration, accessToken: reply.access_token,
                    refreshToken: replacement, idToken: credentials.idToken, scopes: scopes,
                    expiresAt: receivedAt.addingTimeInterval(TimeInterval(reply.expires_in)))
            }
            pending = (UUID(), task)
            refreshing = pending
        }
        do {
            let replacement = try await pending.task.value
            guard revision == generation, active?.registrationID == credentials.registrationID else {
                throw SessionError.sessionChanged
            }
            if refreshing?.id == pending.id {
                try store.replace(replacement)
                active = replacement
                refreshing = nil
            } else if active != replacement {
                throw SessionError.sessionChanged
            }
            try Task.checkCancellation()
            guard let current = active, current.planPermissionGranted else { throw SessionError.planPermissionMissing }
            return current.accessToken
        } catch {
            guard revision == generation else { throw SessionError.sessionChanged }
            if refreshing?.id == pending.id {
                refreshing = nil
                if error as? SessionError == .invalidRefresh {
                    try store.delete(registrationID: credentials.registrationID)
                    active = nil
                }
            }
            throw error
        }
    }

    func disconnect() async throws -> RevocationOutcome {
        let credentials = active
        invalidatePendingWork()
        guard let credentials else { return .confirmed }
        // Delete before suspension so a later sign-in cannot be erased by this logout.
        try store.delete(registrationID: credentials.registrationID)
        active = nil
        guard let token = credentials.refreshToken, !token.isEmpty else { return .unconfirmed }
        do {
            let request = Self.formRequest(url: Self.revocationURL, fields: ["token": token,
                "token_type_hint": "refresh_token", "client_id": credentials.registration.issuedClientID])
            let (_, response) = try await Self.send(request, session: session)
            return response.statusCode == 200 ? .confirmed : .unconfirmed
        } catch { return .unconfirmed }
    }

    private func settleCurrentRefresh() async {
        guard refreshing != nil, let current = active else { return }
        _ = try? await accessToken(now: current.expiresAt, expectedRegistrationID: current.registrationID)
    }

    private func invalidatePendingWork() {
        generation += 1
        connectionAttempt += 1
        refreshing?.task.cancel()
        refreshing = nil
    }

    private static let resource = "https://api.openai.com/v1"
    private static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    private static let revocationURL = URL(string: "https://auth.openai.com/api/accounts/oauth/revoke")!
    private static let jwksURL = URL(string: "https://auth.openai.com/.well-known/jwks.json")!

    private struct TokenReply: Decodable, Sendable {
        let access_token: String
        let refresh_token: String?
        let id_token: String?
        let token_type: String
        let expires_in: Int
        let scope: String?
        let client_id: String?
    }

    private static func exchange(_ fields: [String: String], session: URLSession, isRefresh: Bool) async throws -> TokenReply {
        let (data, response) = try await send(formRequest(url: tokenURL, fields: fields), session: session)
        guard response.statusCode == 200 else {
            struct ProviderError: Decodable { let error: String }
            let errorCode = (try? JSONDecoder().decode(ProviderError.self, from: data))?.error
            let terminal = ["invalid_grant", "invalid_refresh_token", "token_expired",
                "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"]
            if isRefresh, (400...401).contains(response.statusCode), let errorCode, terminal.contains(errorCode) {
                throw SessionError.invalidRefresh
            }
            throw SessionError.providerFailure(response.statusCode)
        }
        let reply: TokenReply
        do { reply = try JSONDecoder().decode(TokenReply.self, from: data) }
        catch { throw SessionError.invalidResponse }
        guard !reply.access_token.isEmpty, reply.token_type.lowercased() == "bearer",
              reply.expires_in > 0, reply.expires_in <= 86_400,
              reply.client_id == nil || reply.client_id == fields["client_id"] else { throw SessionError.invalidResponse }
        return reply
    }

    private static func fetchKeys(session: URLSession) async throws -> Data {
        let (data, response) = try await send(URLRequest(url: jwksURL), session: session)
        guard response.statusCode == 200 else { throw SessionError.providerFailure(response.statusCode) }
        return data
    }

    private static func send(_ request: URLRequest, session: URLSession) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request, delegate: RejectAuthRedirects()) }
        catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw SessionError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse, data.count <= 1_048_576 else { throw SessionError.invalidResponse }
        return (data, http)
    }

    private static func formRequest(url: URL, fields: [String: String]) -> URLRequest {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        return request
    }
}

final class RejectAuthRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
