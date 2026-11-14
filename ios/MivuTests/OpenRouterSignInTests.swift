import Foundation
import Testing
@testable import Mivu

@Suite struct OpenRouterSignInTests {
    let callback = URL(string: "http://127.0.0.1:49152/auth/callback")!

    @Test func authorizationURLCarriesCallbackChallengeAndState() throws {
        let attempt = try OpenRouterSignIn.make(callbackURL: callback)
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(attempt.authorizationURL.absoluteString.hasPrefix("https://openrouter.ai/auth?"))
        #expect(items["callback_url"] == callback.absoluteString)
        #expect(items["code_challenge"] == OAuthAttempt.challenge(for: attempt.verifier))
        #expect(items["code_challenge_method"] == "S256" && items["state"] == attempt.state)
        #expect(try OpenRouterSignIn.make(callbackURL: callback).state != attempt.state)
    }

    @Test func callbackNeedsTheSameStateAndACode() throws {
        let attempt = try OpenRouterSignIn.make(callbackURL: callback)
        #expect(try attempt.code(from: URL(string: "\(callback)?code=abc&state=\(attempt.state)")!) == "abc")
        #expect(throws: OAuthError.invalidCallback) { try attempt.code(from: URL(string: "\(callback)?code=abc&state=other")!) }
        #expect(throws: OAuthError.invalidCallback) { try attempt.code(from: URL(string: "\(callback)?state=\(attempt.state)")!) }
    }

    @Test func exchangeSendsTheCodeAndVerifierAndReadsTheKey() throws {
        let attempt = try OpenRouterSignIn.make(callbackURL: callback)
        let request = attempt.exchange(code: "abc")
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/auth/keys" && request.httpMethod == "POST")
        let body = try #require(request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] })
        #expect(body == ["code": "abc", "code_verifier": attempt.verifier, "code_challenge_method": "S256"])
        #expect(try OpenRouterSignIn.key(from: Data(#"{"key":"fixture-or-key"}"#.utf8)) == "fixture-or-key")
        // The reply carries other fields, and not all of them are strings.
        #expect(try OpenRouterSignIn.key(from: Data(#"{"key":"fixture-or-key","user_id":null,"limit":5}"#.utf8)) == "fixture-or-key")
        #expect(throws: OAuthError.invalidCallback) { try OpenRouterSignIn.key(from: Data("{}".utf8)) }
    }
}
