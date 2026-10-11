import Foundation
import Network

@MainActor final class LoopbackCallback {
    private let timeout: Duration
    private(set) var listener: NWListener?
    private var callbackURL: URL?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var ready: CheckedContinuation<URL, any Error>?
    private var callback: CheckedContinuation<URL, any Error>?
    private var validate: ((URL) throws -> Void)?
    private var deadline: Task<Void, Never>?
    private var browser: Task<Void, Never>?
    private var accepted = false
    private var started = false
    private var stopped = false

    init(timeout: Duration = .seconds(300)) { self.timeout = timeout }

    func start() async throws -> URL {
        guard !started, !stopped else { throw OAuthError.alreadyConsumed }
        started = true
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                switch state {
                case .ready:
                    guard let port = self.listener?.port,
                          let url = URL(string: "http://127.0.0.1:\(port.rawValue)/auth/callback") else {
                        self.finish(.failure(OAuthError.invalidRedirect))
                        return
                    }
                    self.callbackURL = url
                    self.ready?.resume(returning: url)
                    self.ready = nil
                case .failed(let error): self.finish(.failure(error))
                default: break
                }
            }
        }
        deadline = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) }
            catch { return }
            self?.finish(.failure(CallbackError.timedOut))
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                listener.start(queue: .main)
            }
        } onCancel: { Task { @MainActor [weak self] in self?.stop() } }
    }

    func receive(validating validate: @escaping (URL) throws -> Void,
                 openBrowser: (@MainActor (URL) async throws -> Void)? = nil,
                 browserURL: URL? = nil) async throws -> URL {
        guard !stopped, callbackURL != nil else { throw CancellationError() }
        guard callback == nil else { throw CallbackError.alreadyWaiting }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            self.validate = validate
            return try await withCheckedThrowingContinuation { continuation in
                callback = continuation
                // Register the receiver before opening a browser that can immediately navigate back.
                if let openBrowser, let browserURL {
                    browser = Task { [weak self] in
                        do { try await openBrowser(browserURL) }
                        catch {
                            guard let self, !self.accepted else { return }
                            self.finish(.failure(error))
                        }
                    }
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.stop() } }
    }

    func stop() { finish(.failure(CancellationError())) }

    private func finish(_ result: Result<URL, any Error>) {
        guard !stopped else { return }
        stopped = true
        ready?.resume(with: result)
        ready = nil
        callback?.resume(with: result)
        callback = nil
        validate = nil
        deadline?.cancel()
        deadline = nil
        browser?.cancel()
        browser = nil
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped, connections.count < 4 else { connection.cancel(); return }
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: .main)
        read(connection, accumulated: Data())
    }

    private func read(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16385) { [weak self] data, _, ended, error in
            Task { @MainActor in
                guard let self, !self.stopped else { connection.cancel(); return }
                var bytes = accumulated
                if let data { bytes.append(data) }
                guard bytes.count <= 16384 else { self.respond(connection, status: 400); return }
                if bytes.range(of: Data("\r\n\r\n".utf8)) != nil {
                    self.handle(bytes, connection: connection)
                } else if ended || error != nil {
                    self.close(connection)
                } else {
                    self.read(connection, accumulated: bytes)
                }
            }
        }
    }

    private func handle(_ bytes: Data, connection: NWConnection) {
        guard let request = String(data: bytes, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first,
              let base = callbackURL, let port = base.port else {
            respond(connection, status: 400); return
        }
        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "GET", parts[2] == "HTTP/1.1",
              let url = URL(string: "http://127.0.0.1:\(port)\(parts[1])"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.percentEncodedPath == "/auth/callback", components.fragment == nil,
              let validate, callback != nil else { respond(connection, status: 400); return }
        do {
            try validate(url)
            accepted = true
            respond(connection, status: 200) { [weak self] in self?.finish(.success(url)) }
        } catch OAuthError.denied {
            accepted = true
            respond(connection, status: 200) { [weak self] in self?.finish(.failure(OAuthError.denied)) }
        } catch OAuthError.providerError {
            accepted = true
            respond(connection, status: 200) { [weak self] in self?.finish(.failure(OAuthError.providerError)) }
        } catch { respond(connection, status: 400) }
    }

    private func respond(_ connection: NWConnection, status: Int, then action: (@MainActor @Sendable () -> Void)? = nil) {
        let body = status == 200 ? "You can return to Mivu." : "Invalid request."
        let response = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Bad Request")\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in
                self?.close(connection)
                action?()
            }
        })
    }

    private func close(_ connection: NWConnection) {
        connection.cancel()
        connections.removeValue(forKey: ObjectIdentifier(connection))
    }
}

private enum CallbackError: Error { case timedOut, alreadyWaiting }
