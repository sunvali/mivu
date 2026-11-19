import Foundation
import Testing
@testable import Mivu

/// Answers every request from one canned reply and records what was sent. Synthetic only.
private final class FeedbackStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 204
    nonisolated(unsafe) static var failure: URLError?
    nonisolated(unsafe) static var request: URLRequest?
    nonisolated(unsafe) static var body = Data()

    static func session(status: Int = 204, failure: URLError? = nil) -> URLSession {
        self.status = status; self.failure = failure; request = nil; body = Data()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedbackStub.self]
        return URLSession(configuration: config)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.request = request
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                Self.body.append(contentsOf: bytes.prefix(count))
            }
        } else if let data = request.httpBody { Self.body = data }
        if let failure = Self.failure { client?.urlProtocol(self, didFailWithError: failure); return }
        let reply = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: reply, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("<html>login</html>".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct FeedbackTests {
    let d = FeedbackDiagnostics(appVersion: "1.7.0", build: "42", os: "26.1", device: "iPhone17,1", language: "es")
    let endpoint = URL(string: "https://feedback.invalid/report")!
    var full: FeedbackReport { FeedbackReport(kind: .bug, message: "It broke", email: "a@b.co", diagnostics: d, context: .coachNetwork)! }

    @Test func trimsAndBuilds() {
        let r = FeedbackReport(kind: .bug, message: "  It broke \n", email: " a@b.co ", diagnostics: d, context: .coachNetwork)
        #expect(r?.message == "It broke"); #expect(r?.email == "a@b.co"); #expect(r?.language == "es")
    }
    @Test func emptyEmailIsNil() {
        #expect(FeedbackReport(kind: .idea, message: "x", email: "  ", diagnostics: d, context: nil)?.email == nil)
    }
    @Test(arguments: ["", "   ", String(repeating: "a", count: 4001)])
    func rejectsMessage(_ m: String) {
        #expect(FeedbackReport(kind: .bug, message: m, email: "", diagnostics: d, context: nil) == nil)
    }
    @Test func acceptsLimit() {
        #expect(FeedbackReport(kind: .bug, message: String(repeating: "a", count: 4000), email: "", diagnostics: d, context: nil) != nil)
    }
    @Test(arguments: ["nope", "a@b", "a b@c.co", "a@b.co\nBcc: x@y.z", String(repeating: "a", count: 250) + "@b.co"])
    func rejectsEmail(_ e: String) {
        #expect(FeedbackReport(kind: .bug, message: "x", email: e, diagnostics: d, context: nil) == nil)
    }
    @Test func jsonHasExactlyTheAgreedFields() throws {
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(full)) as? [String: String])
        #expect(Set(object.keys) == ["kind", "message", "email", "appVersion", "build", "os", "device", "language", "context"])
        #expect(object["kind"] == "bug"); #expect(object["context"] == "coach_network")
    }
    @Test func jsonOmitsNilEmailAndContext() throws {
        let report = try #require(FeedbackReport(kind: .idea, message: "x", email: "", diagnostics: d, context: nil))
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: String])
        #expect(Set(object.keys) == ["kind", "message", "appVersion", "build", "os", "device", "language"])
    }
    @Test func includedLinesListEverythingSent() throws {
        let lines = full.includedLines.joined(separator: "\n")
        for value in ["1.7.0", "42", "26.1", "iPhone17,1", "es", "coach_network"] { #expect(lines.contains(value)) }
        let plain = try #require(FeedbackReport(kind: .bug, message: "x", email: "", diagnostics: d, context: nil))
        #expect(!plain.includedLines.joined().contains("coach_"))
    }
    @Test func mailtoCarriesTheSameReport() throws {
        let parts = try #require(URLComponents(url: Feedback.mailto(full), resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "mailto"); #expect(parts.path == "support@mivuapp.com")
        let subject = try #require(parts.queryItems?.first { $0.name == "subject" }?.value)
        let body = try #require(parts.queryItems?.first { $0.name == "body" }?.value)
        #expect(subject.hasPrefix("[Bug] Mivu 1.7.0 (42)"))
        #expect(body.contains("It broke"))
        for line in full.includedLines { #expect(body.contains(line)) }
        #expect(!body.contains("a@b.co"))
    }
    @Test func contextFromTurnState() {
        #expect(FeedbackContext(.waitingForNetwork) == .coachNetwork)
        #expect(FeedbackContext(.waitingForConnection) == .coachSession)
        #expect(FeedbackContext(.needsRetry) == .coachOther)
    }
    @Test func sendPostsJSONAndAccepts204() async throws {
        try await Feedback.send(full, to: endpoint, session: FeedbackStub.session())
        #expect(FeedbackStub.request?.httpMethod == "POST")
        #expect(FeedbackStub.request?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let sent = try #require(JSONSerialization.jsonObject(with: FeedbackStub.body) as? [String: String])
        #expect(sent["message"] == "It broke"); #expect(sent["email"] == "a@b.co"); #expect(sent["device"] == "iPhone17,1")
    }
    @Test(arguments: [200, 400, 413, 500])
    func sendThrowsOnAnythingBut204(_ status: Int) async {
        await #expect(throws: FeedbackError.rejected) {
            try await Feedback.send(full, to: endpoint, session: FeedbackStub.session(status: status))
        }
    }
    @Test func sendThrowsWhenOffline() async {
        await #expect(throws: URLError.self) {
            try await Feedback.send(full, to: endpoint, session: FeedbackStub.session(failure: URLError(.notConnectedToInternet)))
        }
    }
}
