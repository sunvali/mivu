import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct LoopbackCallbackTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["stop", "success", "timeout"])
    func releasesNetworkListenerAfterFinishing(reason: String) async throws {
        let callback = LoopbackCallback(timeout: .seconds(5))
        let url = try await callback.start()
        weak let networkListener = callback.listener
        #expect(networkListener != nil)
        switch reason {
        case "success":
            let receive = Task { try await callback.receive { _ in } }
            _ = try await URLSession.shared.data(from: url)
            _ = try await receive.value
        case "timeout":
            await #expect(throws: (any Error).self) { try await callback.receive { _ in } }
        default:
            callback.stop()
        }
        for _ in 0..<100 where networkListener != nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(callback.listener == nil)
        #expect(networkListener == nil)
    }

    @Test(.timeLimit(.minutes(1))) func acceptsOneValidatedLoopbackRequest() async throws {
        let listener = LoopbackCallback()
        defer { listener.stop() }
        let url = try await listener.start()
        #expect(url.scheme == "http")
        #expect(url.host == "127.0.0.1")
        #expect(url.path == "/auth/callback")
        #expect(url.port != nil)
        var attempt = try OAuthAttempt.make(hostID: "fixture-host", issuedClientID: nil, callbackURL: url)
        var parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        parts.queryItems = [URLQueryItem(name: "state", value: attempt.state),
                           URLQueryItem(name: "code", value: "synthetic-code"),
                           URLQueryItem(name: "client_id", value: "oaiapp_fixture")]
        let valid = try #require(parts.url)
        let received = Task { try await listener.receive { _ = try attempt.consumeCallback($0) } }
        let (_, rejected) = try await URLSession.shared.data(from: url)
        #expect((rejected as? HTTPURLResponse)?.statusCode == 400)
        let (_, response) = try await URLSession.shared.data(from: valid)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(try await received.value == valid)
    }

    @Test(.timeLimit(.minutes(1))) func cancellationEndsPendingReceive() async throws {
        let listener = LoopbackCallback()
        _ = try await listener.start()
        let received = Task { try await listener.receive { _ in } }
        listener.stop()
        await #expect(throws: (any Error).self) { try await received.value }
    }

    @Test(.timeLimit(.minutes(1))) func timeoutEndsPendingReceive() async throws {
        let listener = LoopbackCallback(timeout: .milliseconds(100))
        _ = try await listener.start()
        await #expect(throws: (any Error).self) { try await listener.receive { _ in } }
    }

    @Test(.timeLimit(.minutes(1))) func refusesPostAndOversizedHeaders() async throws {
        let listener = LoopbackCallback()
        defer { listener.stop() }
        let url = try await listener.start()
        let received = Task { try await listener.receive { _ in } }
        defer { received.cancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, post) = try await URLSession.shared.data(for: request)
        #expect((post as? HTTPURLResponse)?.statusCode == 400)
        request.httpMethod = "GET"
        request.setValue(String(repeating: "x", count: 17000), forHTTPHeaderField: "X-Synthetic")
        let (_, large) = try await URLSession.shared.data(for: request)
        #expect((large as? HTTPURLResponse)?.statusCode == 400)
    }
}
