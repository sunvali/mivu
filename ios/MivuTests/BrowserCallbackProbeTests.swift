import AuthenticationServices
import Foundation
import Testing
import UIKit
@testable import Mivu

@Suite @MainActor struct BrowserCallbackProbeTests {
    @Test(.timeLimit(.minutes(1))) func successfulCallbackWinsOverBrowserCancellation() async {
        let probe = BrowserCallbackProbe()
        await probe.run { url in
            _ = try await URLSession.shared.data(from: url)
            try await Task.sleep(for: .seconds(30))
        }
        #expect(probe.state == .passed)
    }

    @Test(.timeLimit(.minutes(1))) func browserFailureCannotClaimSuccess() async {
        let probe = BrowserCallbackProbe()
        await probe.run { _ in throw URLError(.cannotConnectToHost) }
        #expect(probe.state == .failed)
    }

    @Test(.timeLimit(.minutes(1))) func browserCancellationIsCancelled() async {
        let probe = BrowserCallbackProbe()
        await probe.run { _ in throw CancellationError() }
        #expect(probe.state == .cancelled)
    }

    @Test(.timeLimit(.minutes(1))) func nativeSheetCancellationIsNormalized() async {
        let cancellation = ASWebAuthenticationSessionError(.canceledLogin)
        let normalized = NativeAuthorizationBrowser.completionError(cancellation)
        #expect(normalized is CancellationError)
        let failure = URLError(.cannotConnectToHost)
        #expect(NativeAuthorizationBrowser.completionError(failure) as? URLError == failure)
        #expect(!(NativeAuthorizationBrowser.completionError(nil) is CancellationError))
        let probe = BrowserCallbackProbe()
        await probe.run { _ in throw normalized }
        #expect(probe.state == .cancelled)
    }

    @Test(.timeLimit(.minutes(1))) func wrongStateDoesNotConsumePendingBrowserAttempt() async {
        let probe = BrowserCallbackProbe()
        await probe.run { url in
            var wrong = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            wrong.queryItems?[0].value = "another-attempt"
            let (_, rejected) = try await URLSession.shared.data(from: #require(wrong.url))
            #expect((rejected as? HTTPURLResponse)?.statusCode == 400)
            let (_, valid) = try await URLSession.shared.data(from: url)
            #expect((valid as? HTTPURLResponse)?.statusCode == 200)
            throw CancellationError()
        }
        #expect(probe.state == .passed)
    }

    @Test(.timeLimit(.minutes(1))) func parentCancellationStopsBrowserAndListener() async throws {
        let probe = BrowserCallbackProbe()
        var callbackURL: URL?
        var browserCancelled = false
        let task = Task {
            await probe.run { url in
                callbackURL = url
                do { try await Task.sleep(for: .seconds(30)) }
                catch { browserCancelled = true; throw error }
            }
        }
        while callbackURL == nil { await Task.yield() }
        task.cancel()
        await task.value
        for _ in 0..<100 where !browserCancelled { await Task.yield() }
        #expect(probe.state == .cancelled)
        #expect(browserCancelled)
        await #expect(throws: (any Error).self) {
            _ = try await URLSession.shared.data(from: #require(callbackURL))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MIVU_NATIVE_BROWSER_PROBE"] == "1"),
          .timeLimit(.minutes(1)))
    func nativeAuthenticationBrowserReachesLoopback() async throws {
        let window = try #require(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow })
        let browser = NativeAuthorizationBrowser(window: window)
        let probe = BrowserCallbackProbe(timeout: .seconds(15))
        await probe.run { try await browser.open($0) }
        #expect(probe.state == .passed)
    }
}
