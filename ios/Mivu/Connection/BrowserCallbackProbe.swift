import Foundation
import Observation

@Observable @MainActor final class BrowserCallbackProbe {
    enum State { case idle, running, passed, failed, cancelled }
    private(set) var state: State = .idle
    private let timeout: Duration

    init(timeout: Duration = .seconds(300)) { self.timeout = timeout }

    func run(openBrowser: @escaping @MainActor (URL) async throws -> Void) async {
        guard state != .running else { return }
        state = .running
        let listener = LoopbackCallback(timeout: timeout)
        defer { listener.stop() }
        do {
            let redirect = try await listener.start()
            var attempt = try OAuthAttempt.make(hostID: "synthetic-browser-probe", issuedClientID: nil,
                                               callbackURL: redirect)
            guard var fixture = URLComponents(url: redirect, resolvingAgainstBaseURL: false) else {
                throw OAuthError.invalidRedirect
            }
            fixture.queryItems = [URLQueryItem(name: "state", value: attempt.state),
                                  URLQueryItem(name: "code", value: "synthetic-code"),
                                  URLQueryItem(name: "client_id", value: "oaiapp_synthetic")]
            guard let browserURL = fixture.url else { throw OAuthError.invalidRedirect }
            _ = try await listener.receive(validating: { _ = try attempt.consumeCallback($0) },
                                           openBrowser: openBrowser, browserURL: browserURL)
            state = .passed
        } catch {
            state = Task.isCancelled || error is CancellationError ? .cancelled : .failed
        }
    }
}
