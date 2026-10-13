import CryptoKit
import Foundation
import Security

enum OAuthError: Error, Equatable {
    case invalidRedirect, invalidRegistration, randomGenerationFailed
    case invalidCallback, denied, providerError, alreadyConsumed
}

struct AuthorizationCode: Sendable {
    let code: String
    let issuedClientID: String
    let redirectURL: URL
}

struct OAuthAttempt {
    let state: String
    let nonce: String
    let verifier: String
    let callbackURL: URL
    let authorizationURL: URL
    private let issuedClientID: String?
    private var consumed = false

    static func make(hostID: String, issuedClientID: String?, callbackURL: URL,
                     requestPlanConsent: Bool = false) throws -> Self {
        guard !hostID.isEmpty, issuedClientID != "", issuedClientID != "dynamic_agent_client" else {
            throw OAuthError.invalidRegistration
        }
        guard let redirect = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              redirect.scheme == "http", redirect.host == "127.0.0.1",
              let port = redirect.port, (1...65535).contains(port),
              redirect.path == "/auth/callback", redirect.user == nil, redirect.password == nil,
              redirect.query == nil, redirect.fragment == nil else { throw OAuthError.invalidRedirect }
        let state = try randomValue()
        let nonce = try randomValue()
        let verifier = try randomValue()
        var authorization = URLComponents()
        authorization.scheme = "https"
        authorization.host = "auth.openai.com"
        authorization.path = "/api/accounts/authorize"
        authorization.queryItems = [
            URLQueryItem(name: "client_id", value: issuedClientID ?? "dynamic_agent_client"),
            URLQueryItem(name: "ext_agent_host_id", value: hostID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: callbackURL.absoluteString),
            URLQueryItem(name: "scope", value: "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"),
            URLQueryItem(name: "resource", value: "https://api.openai.com/v1"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier))
        ]
        if issuedClientID == nil {
            authorization.queryItems?.append(URLQueryItem(name: "agent_name_hint", value: "Mivu"))
        }
        if requestPlanConsent {
            authorization.queryItems?.append(URLQueryItem(name: "prompt", value: "consent"))
        }
        guard let url = authorization.url else { throw OAuthError.invalidRedirect }
        return Self(state: state, nonce: nonce, verifier: verifier, callbackURL: callbackURL,
                    authorizationURL: url, issuedClientID: issuedClientID)
    }

    mutating func consumeCallback(_ url: URL) throws -> AuthorizationCode {
        guard !consumed else { throw OAuthError.alreadyConsumed }
        guard let received = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let expected = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              received.scheme == expected.scheme, received.host == expected.host,
              received.port == expected.port, received.path == expected.path,
              received.user == nil, received.password == nil, received.fragment == nil else {
            throw OAuthError.invalidCallback
        }
        var parameters: [String: String] = [:]
        for item in received.queryItems ?? [] {
            guard parameters[item.name] == nil, let value = item.value else {
                throw OAuthError.invalidCallback
            }
            parameters[item.name] = value
        }
        guard parameters["state"] == state else { throw OAuthError.invalidCallback }
        if let error = parameters["error"] {
            consumed = true
            throw error == "access_denied" ? OAuthError.denied : OAuthError.providerError
        }
        guard let code = parameters["code"], !code.isEmpty,
              let clientID = parameters["client_id"] ?? issuedClientID,
              !clientID.isEmpty, clientID != "dynamic_agent_client",
              issuedClientID == nil || issuedClientID == clientID else { throw OAuthError.invalidCallback }
        consumed = true
        return AuthorizationCode(code: code, issuedClientID: clientID, redirectURL: callbackURL)
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func randomValue() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw OAuthError.randomGenerationFailed
        }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
