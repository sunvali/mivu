import CryptoKit
import Foundation
import Testing
@testable import Mivu

@Suite struct OAuthAttemptTests {
    private let redirect = URL(string: "http://127.0.0.1:1455/auth/callback")!

    private func callback(_ attempt: OAuthAttempt, extra: [URLQueryItem] = [],
                          clientID: String? = "oaiapp_fixture") throws -> URL {
        var components = try #require(URLComponents(url: redirect, resolvingAgainstBaseURL: false))
        components.queryItems = [URLQueryItem(name: "state", value: attempt.state),
                                 URLQueryItem(name: "code", value: "synthetic-code")]
        if let clientID { components.queryItems?.append(URLQueryItem(name: "client_id", value: clientID)) }
        components.queryItems?.append(contentsOf: extra)
        return try #require(components.url)
    }

    @Test func newRegistrationUsesActualAppNameAndPlanScopes() throws {
        let attempt = try OAuthAttempt.make(hostID: "fixture-host", issuedClientID: nil, callbackURL: redirect)
        let components = try #require(URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(components.host == "auth.openai.com")
        #expect(components.path == "/api/accounts/authorize")
        #expect(query["client_id"] == "dynamic_agent_client")
        #expect(query["agent_name_hint"] == "Mivu")
        #expect(query["redirect_uri"] == "http://127.0.0.1:1455/auth/callback")
        #expect(query["resource"] == "https://api.openai.com/v1")
        #expect(query["scope"] == "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct")
        #expect(query["code_challenge_method"] == "S256")
        let digest = Data(SHA256.hash(data: Data(attempt.verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(query["code_challenge"] == digest)
        #expect(attempt.state != attempt.nonce)
        #expect(attempt.verifier.count >= 43)
    }

    @Test func pkceMatchesPublishedVector() {
        #expect(OAuthAttempt.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
                == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func returningRegistrationRetainsIssuedIDWithoutNameHint() throws {
        var attempt = try OAuthAttempt.make(hostID: "fixture-host", issuedClientID: "oaiapp_returning", callbackURL: redirect)
        let query = try #require(URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)).queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "client_id", value: "oaiapp_returning")))
        #expect(!query.contains { $0.name == "agent_name_hint" })
        let code = try attempt.consumeCallback(callback(attempt, clientID: nil))
        #expect(code.issuedClientID == "oaiapp_returning")
        #expect(code.redirectURL == redirect)
    }

    @Test func rejectsWrongStateWithoutLosingValidAttempt() throws {
        var attempt = try OAuthAttempt.make(hostID: "fixture-host", issuedClientID: nil, callbackURL: redirect)
        var parts = try #require(URLComponents(url: callback(attempt), resolvingAgainstBaseURL: false))
        parts.queryItems?[0].value = "wrong"
        #expect(throws: (any Error).self) { try attempt.consumeCallback(#require(parts.url)) }
        #expect(try attempt.consumeCallback(callback(attempt)).code == "synthetic-code")
    }

    @Test(arguments: ["state", "code", "client_id"])
    func rejectsDuplicateFields(field: String) throws {
        var attempt = try OAuthAttempt.make(hostID: "fixture-host", issuedClientID: nil, callbackURL: redirect)
        let url = try callback(attempt, extra: [URLQueryItem(name: field, value: "duplicate")])
        #expect(throws: (any Error).self) { try attempt.consumeCallback(url) }
    }

    @Test func rejectsMissingIssuedIDAndDynamicID() throws {
        var attempt = try OAuthAttempt.make(hostID: "fixture-host", issuedClientID: nil, callbackURL: redirect)
        #expect(throws: (any Error).self) { try attempt.consumeCallback(callback(attempt, clientID: nil)) }
        #expect(throws: (any Error).self) { try attempt.consumeCallback(callback(attempt, clientID: "dynamic_agent_client")) }
    }

    @Test func rejectsChangedReturningID() throws {
        var attempt = try OAuthAttempt.make(hostID: "fixture-host", issuedClientID: "oaiapp_returning", callbackURL: redirect)
        #expect(throws: (any Error).self) { try attempt.consumeCallback(callback(attempt)) }
    }

    @Test func successfulCallbackIsSingleUse() throws {
        var attempt = try OAuthAttempt.make(hostID: "fixture-host", issuedClientID: nil, callbackURL: redirect)
        let url = try callback(attempt)
        #expect(try attempt.consumeCallback(url).code == "synthetic-code")
        #expect(throws: (any Error).self) { try attempt.consumeCallback(url) }
    }

    @Test func denialIsConsumedWithoutReturningCode() throws {
        var attempt = try OAuthAttempt.make(hostID: "fixture-host", issuedClientID: nil, callbackURL: redirect)
        let url = try callback(attempt, extra: [URLQueryItem(name: "error", value: "access_denied")])
        #expect(throws: OAuthError.denied) { try attempt.consumeCallback(url) }
        #expect(throws: OAuthError.alreadyConsumed) { try attempt.consumeCallback(callback(attempt)) }
    }

    @Test(arguments: ["https://127.0.0.1:1455/auth/callback", "http://localhost:1455/auth/callback",
                      "http://127.0.0.1:1456/auth/callback", "http://127.0.0.1:1455/callback"])
    func rejectsChangedRedirect(base: String) throws {
        var attempt = try OAuthAttempt.make(hostID: "fixture-host", issuedClientID: nil, callbackURL: redirect)
        var parts = try #require(URLComponents(string: base))
        parts.queryItems = try #require(URLComponents(url: callback(attempt), resolvingAgainstBaseURL: false)).queryItems
        #expect(throws: (any Error).self) { try attempt.consumeCallback(#require(parts.url)) }
    }
}
