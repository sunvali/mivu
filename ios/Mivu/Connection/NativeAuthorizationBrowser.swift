import AuthenticationServices
import UIKit

@MainActor final class NativeAuthorizationBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: UIWindow
    private var session: ASWebAuthenticationSession?
    private var completion: CheckedContinuation<Void, any Error>?

    init(window: UIWindow) { self.window = window }

    func open(_ url: URL) async throws {
        guard session == nil, window.windowScene?.activationState == .foregroundActive,
              !window.isHidden, url.scheme == "http" || url.scheme == "https" else {
            throw BrowserError.unavailable
        }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                completion = continuation
                // The modern callback factories cannot receive the required HTTP loopback redirect.
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, error in
                    Task { @MainActor in self?.finish(Self.completionError(error)) }
                }
                self.session = session
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                if !session.start() { finish(BrowserError.unavailable) }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }

    func cancel() { finish(CancellationError()) }

    static func completionError(_ error: (any Error)?) -> any Error {
        if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
            return CancellationError()
        }
        return error ?? BrowserError.unexpectedCompletion
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }

    private func finish(_ error: any Error) {
        let completion = self.completion
        self.completion = nil
        let session = self.session
        self.session = nil
        session?.cancel()
        completion?.resume(throwing: error)
    }
}

private enum BrowserError: Error { case unavailable, unexpectedCompletion }
