import Foundation
import Testing
@testable import Mivu

@Suite(.serialized)
struct ProbeJobTests {
    @Test func interruptedJobRestoresAsPending() throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob(state: .analyzing)
        try store.save(job)
        let restored = try #require(try store.load())
        #expect(restored.id == job.id)
        #expect(restored.state == .pending)
        #expect(restored.image == job.image && restored.text == job.text)
        #expect(restored.result == nil)
    }

    @Test func failedSaveNeverAcknowledgesCapture() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("Synthetic obstruction".utf8).write(to: directory)
        let store = ProbeJobStore(directory: directory)
        var acknowledged = false
        #expect(throws: (any Error).self) {
            try store.save(makeJob())
            acknowledged = true
        }
        #expect(!acknowledged)
    }

    @Test func completedOutputAndInputSurviveFreshStore() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        let fixture = JobFixture([.success])
        let runner = runner(store, fixture)
        let result = try await runner.run(job)
        let saved = try #require(try ProbeJobStore(directory: store.directory).load())
        #expect(saved.id == job.id && saved.state == .completed)
        #expect(saved.result == result)
        #expect(saved.text == job.text && saved.image == job.image)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.directory.appendingPathComponent("probe-job.json").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func boundedNetworkRetriesKeepOriginalUUID() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        let fixture = JobFixture(Array(repeating: .network, count: 4))
        let delays = Delays()
        let runner = runner(store, fixture, sleep: { await delays.append($0) })
        await #expect(throws: (any Error).self) { try await runner.run(job) }
        let saved = try #require(try store.load())
        #expect(saved.id == job.id && saved.state == .needsRetry && saved.result == nil)
        #expect(await delays.values == [.seconds(1), .seconds(2), .seconds(4)])
        #expect(fixture.requestCount == 4)
    }

    @Test func retrySuccessRetainsUUID() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob(state: .needsRetry)
        try store.save(job)
        let fixture = JobFixture([.network, .success])
        _ = try await runner(store, fixture).run(job)
        #expect(try store.load()?.id == job.id)
        #expect(try store.load()?.state == .completed)
        #expect(fixture.requestCount == 2)
    }

    @Test(arguments: [StreamFailure.partial, .afterCompleted])
    func streamTransportFailureCannotPersistOutput(failure: StreamFailure) async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        let fixture = JobFixture(Array(repeating: failure == .partial ? .partial : .afterCompleted, count: 4))
        await #expect(throws: (any Error).self) { try await runner(store, fixture).run(job) }
        let saved = try #require(try store.load())
        #expect(saved.id == job.id && saved.state == .needsRetry)
        #expect(saved.result == nil && saved.text == job.text && saved.image == job.image)
    }

    @Test func incompleteStreamRetriesWithoutPartialOutput() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        let fixture = JobFixture(Array(repeating: .incomplete, count: 4))
        await #expect(throws: ResponsesClient.Failure.incompleteResponse) { try await runner(store, fixture).run(job) }
        #expect(try store.load()?.result == nil)
        #expect(try store.load()?.state == .needsRetry)
    }

    @Test(arguments: [401, 403, 429])
    func ownerActionDoesNotAutomaticallyRetry(status: Int) async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        let fixture = JobFixture([.http(status)])
        let delays = Delays()
        await #expect(throws: (any Error).self) { try await runner(store, fixture, sleep: { await delays.append($0) }).run(job) }
        #expect(fixture.requestCount == 1)
        #expect(await delays.values.isEmpty)
        #expect(try store.load()?.state == .needsRetry)
    }

    @Test func cancellationPreservesPendingInput() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        let fixture = JobFixture([.success])
        let runner = ProbeRunner(store: store, client: fixture.client, accessToken: { _ in throw CancellationError() }, activeRegistrationID: { "fixture-registration" })
        await #expect(throws: CancellationError.self) { try await runner.run(job) }
        #expect(try store.load()?.state == .pending)
        #expect(try store.load()?.image == job.image)
        #expect(fixture.requestCount == 0)
    }

    @Test func staleResultAfterDeletionCannotRestoreJob() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        let fixture = JobFixture([.success], hook: { try! store.remove(id: job.id) })
        await #expect(throws: ProbeRunner.Failure.staleJob) { try await runner(store, fixture).run(job) }
        #expect(try store.load() == nil)
    }

    @Test func staleResultCannotOverwriteReplacementUUID() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        let replacement = makeJob()
        try store.save(job)
        let fixture = JobFixture([.success], hook: { try! store.save(replacement) })
        await #expect(throws: ProbeRunner.Failure.staleJob) { try await runner(store, fixture).run(job) }
        #expect(try store.load()?.id == replacement.id)
        #expect(try store.load()?.state == .pending)
    }

    @Test func wrongRegistrationIsRejectedBeforeTokenOrRequest() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        let fixture = JobFixture([.success])
        let runner = ProbeRunner(store: store, client: fixture.client, accessToken: { _ in Issue.record("Token must not be requested"); return "fixture-token" }, activeRegistrationID: { "another-registration" })
        await #expect(throws: ProbeRunner.Failure.registrationChanged) { try await runner.run(job) }
        #expect(fixture.requestCount == 0)
        #expect(try store.load()?.state == .needsRetry)
    }

    @Test func accountChangeDuringTokenAwaitNeverDispatches() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        let registration = Registration()
        let fixture = JobFixture([.success])
        let runner = ProbeRunner(store: store, client: fixture.client, accessToken: { requested in
            #expect(requested == job.registrationID)
            registration.change()
            return "fixture-owner-token"
        }, activeRegistrationID: { registration.value })
        await #expect(throws: ProbeRunner.Failure.registrationChanged) { try await runner.run(job) }
        #expect(fixture.requestCount == 0)
        #expect(try store.load()?.result == nil)
    }

    @Test func accountChangeDuringInferenceCannotComplete() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        let registration = Registration()
        let fixture = JobFixture([.success], hook: { registration.change() })
        let runner = ProbeRunner(store: store, client: fixture.client, accessToken: { requested in
            #expect(requested == job.registrationID)
            return "fixture-owner-token"
        }, activeRegistrationID: { registration.value })
        await #expect(throws: ProbeRunner.Failure.registrationChanged) { try await runner.run(job) }
        #expect(try store.load()?.result == nil)
        #expect(try store.load()?.state == .needsRetry)
    }

    @Test func runnerAllowsOnlyOneInFlightJob() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        let gate = TokenGate()
        let fixture = JobFixture([.success])
        let runner = ProbeRunner(store: store, client: fixture.client, accessToken: { _ in await gate.token() }, activeRegistrationID: { "fixture-registration" })
        let first = Task { try await runner.run(job) }
        await gate.waitUntilRequested()
        await #expect(throws: ProbeRunner.Failure.alreadyRunning) { try await runner.run(job) }
        await gate.release()
        _ = try await first.value
        #expect(fixture.requestCount == 1)
    }

    @Test func accountChangeDuringRetryDelayStopsBeforeAnotherToken() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        let registration = Registration()
        let fixture = JobFixture([.network, .success])
        let runner = ProbeRunner(store: store, client: fixture.client, accessToken: { requested in
            #expect(requested == job.registrationID)
            return "fixture-token"
        }, activeRegistrationID: { registration.value }, sleep: { _ in registration.change() })
        await #expect(throws: ProbeRunner.Failure.registrationChanged) { try await runner.run(job) }
        #expect(fixture.requestCount == 1)
        #expect(try store.load()?.state == .needsRetry)
        #expect(try store.load()?.result == nil)
    }

    @Test func cancelDuringRetryDelayLeavesPendingWithoutAnotherAttempt() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        let fixture = JobFixture([.network, .success])
        await #expect(throws: CancellationError.self) {
            try await runner(store, fixture, sleep: { _ in throw CancellationError() }).run(job)
        }
        #expect(fixture.requestCount == 1)
        #expect(try store.load()?.state == .pending)
        #expect(try store.load()?.result == nil)
    }

    @Test func deletedJobBeforeStartNeverRequestsCredentials() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        try store.remove(id: job.id)
        let fixture = JobFixture([.success])
        let runner = ProbeRunner(store: store, client: fixture.client, accessToken: { _ in
            Issue.record("Deleted input must not request credentials")
            return "fixture-token"
        }, activeRegistrationID: { "fixture-registration" })
        await #expect(throws: ProbeRunner.Failure.staleJob) { try await runner.run(job) }
        #expect(fixture.requestCount == 0)
    }

    @Test func completedJobCannotBeDispatchedAgain() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        let fixture = JobFixture([.success])
        let runner = runner(store, fixture)
        _ = try await runner.run(job)
        await #expect(throws: ProbeRunner.Failure.alreadyCompleted) { try await runner.run(job) }
        #expect(fixture.requestCount == 1)
        #expect(try store.load()?.result != nil)
    }

    @Test func postInferenceReadFailureNeverReturnsAResult() async throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        let fixture = JobFixture([.success], hook: {
            // A real filesystem obstruction makes atomic replacement fail.
            try! FileManager.default.removeItem(at: store.directory.appendingPathComponent("probe-job.json"))
            try! FileManager.default.createDirectory(at: store.directory.appendingPathComponent("probe-job.json"), withIntermediateDirectories: false)
        })
        var acknowledged = false
        await #expect(throws: (any Error).self) {
            _ = try await runner(store, fixture).run(job)
            acknowledged = true
        }
        #expect(!acknowledged)
    }

    @Test func removeWrongUUIDPreservesSavedJob() throws {
        let store = try makeStore()
        defer { cleanup(store) }
        let job = makeJob()
        try store.save(job)
        try store.remove(id: UUID())
        #expect(try store.load()?.id == job.id)
    }
}

enum StreamFailure: Sendable { case partial, afterCompleted }
private func makeJob(state: ProbeJobState = .pending) -> ProbeJob {
    ProbeJob(id: UUID(), text: "Synthetic test", image: SyntheticConnectionProbe.image, model: "fixture-model", registrationID: "fixture-registration", state: state)
}
private func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
private func makeStore() throws -> ProbeJobStore { ProbeJobStore(directory: temporaryDirectory()) }
private func cleanup(_ store: ProbeJobStore) { try? FileManager.default.removeItem(at: store.directory) }
private func runner(_ store: ProbeJobStore, _ fixture: JobFixture, sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }) -> ProbeRunner {
    ProbeRunner(store: store, client: fixture.client, accessToken: { _ in "fixture-token" }, activeRegistrationID: { "fixture-registration" }, sleep: sleep)
}
private actor Delays {
    var values: [Duration] = []
    func append(_ duration: Duration) { values.append(duration) }
}
private final class Registration: @unchecked Sendable {
    private let lock = NSLock()
    private var current = "fixture-registration"
    var value: String { lock.withLock { current } }
    func change() { lock.withLock { current = "another-registration" } }
}
private actor TokenGate {
    private var continuation: CheckedContinuation<String, Never>?
    private var requested = false
    func token() async -> String { requested = true; return await withCheckedContinuation { continuation = $0 } }
    func waitUntilRequested() async { while !requested { await Task.yield() } }
    func release() { continuation?.resume(returning: "fixture-token"); continuation = nil }
}
private final class JobFixture: @unchecked Sendable {
    enum Outcome: Sendable { case success, network, partial, afterCompleted, incomplete, http(Int) }
    private let lock = NSLock()
    private var outcomes: [Outcome]
    private var count = 0
    let hook: @Sendable () -> Void
    init(_ outcomes: [Outcome], hook: @escaping @Sendable () -> Void = {}) { self.outcomes = outcomes; self.hook = hook }
    var requestCount: Int { lock.withLock { count } }
    func next() -> Outcome { lock.withLock { count += 1; return outcomes.isEmpty ? .network : outcomes.removeFirst() } }
    var client: ResponsesClient {
        let id = UUID().uuidString
        JobFixtureProtocol.registry.add(self, id: id)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [JobFixtureProtocol.self]
        config.httpAdditionalHeaders = ["Fixture-ID": id]
        return ResponsesClient(session: URLSession(configuration: config))
    }
}
private final class JobFixtureProtocol: URLProtocol, @unchecked Sendable {
    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var fixtures: [String: JobFixture] = [:]
        func add(_ fixture: JobFixture, id: String) { lock.withLock { fixtures[id] = fixture } }
        func get(_ id: String) -> JobFixture? { lock.withLock { fixtures[id] } }
    }
    static let registry = Registry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "Fixture-ID"), let fixture = Self.registry.get(id), let url = request.url else { fatalError("Missing synthetic fixture") }
        let outcome = fixture.next()
        fixture.hook()
        if case .network = outcome { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
        let status: Int = if case .http(let value) = outcome { value } else { 200 }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        let partial = Data("data: {\"type\":\"response.output_text.delta\",\"delta\":\"Synthetic partial\"}\n\n".utf8)
        let completed = Data("data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"model\":\"fixture-model\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Synthetic complete\"}]}]}}\n\n".utf8)
        switch outcome {
        case .success: client?.urlProtocol(self, didLoad: completed)
        case .afterCompleted: client?.urlProtocol(self, didLoad: completed)
        case .partial, .incomplete: client?.urlProtocol(self, didLoad: partial)
        default: break
        }
        if case .partial = outcome { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)) }
        else if case .afterCompleted = outcome { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)) }
        else { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {}
}
