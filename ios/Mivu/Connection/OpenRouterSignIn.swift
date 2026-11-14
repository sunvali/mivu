import Foundation

/// OpenRouter's sign-in: the person approves in the browser and OpenRouter hands back a key they own and pay for.
struct OpenRouterSignIn {
    let verifier: String, state: String, authorizationURL: URL

    static func make(callbackURL: URL) throws -> OpenRouterSignIn {
        let verifier = try OAuthAttempt.randomValue(), state = try OAuthAttempt.randomValue()
        var authorization = URLComponents(string: "https://openrouter.ai/auth")!
        authorization.queryItems = [
            URLQueryItem(name: "callback_url", value: callbackURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: OAuthAttempt.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        return OpenRouterSignIn(verifier: verifier, state: state, authorizationURL: authorization.url!)
    }

    func code(from callback: URL) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw OAuthError.invalidCallback }
        return code
    }

    func exchange(code: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/keys")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["code": code, "code_verifier": verifier, "code_challenge_method": "S256"])
        return request
    }

    static func key(from reply: Data) throws -> String {
        struct Reply: Decodable { let key: String }   // other fields come along, not all of them strings
        guard let key = (try? JSONDecoder().decode(Reply.self, from: reply))?.key, !key.isEmpty else { throw OAuthError.invalidCallback }
        return key
    }
}
