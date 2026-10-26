import Foundation

enum ProbeJobState: String, Codable, Sendable {
    case pending, analyzing, needsRetry, completed
}

struct ProbeJob: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let image: Data?
    let model: String
    let registrationID: String
    var state: ProbeJobState
    private(set) var completedModel: String?
    private(set) var outputText: String?

    init(id: UUID = UUID(), text: String, image: Data?, model: String,
         registrationID: String, state: ProbeJobState = .pending) {
        self.id = id
        self.text = text
        self.image = image
        self.model = model
        self.registrationID = registrationID
        self.state = state
    }

    var result: ProbeResult? {
        guard state == .completed, let completedModel, let outputText else { return nil }
        return ProbeResult(model: completedModel, outputText: outputText)
    }

    fileprivate func hasSameInput(as other: ProbeJob) -> Bool {
        id == other.id && text == other.text && image == other.image
            && model == other.model && registrationID == other.registrationID
    }

    fileprivate mutating func transition(to state: ProbeJobState, result: ProbeResult? = nil) {
        self.state = state
        completedModel = result?.model
        outputText = result?.outputText
    }
}

// The lock makes identity checking and replacement indivisible with deletion.
final class ProbeJobStore: @unchecked Sendable {
    let directory: URL
    private let lock = NSLock()
    private var file: URL { directory.appendingPathComponent("probe-job.json") }

    init(directory: URL) { self.directory = directory }

    func save(_ job: ProbeJob) throws {
        try lock.withLock { try write(job) }
    }

    func load() throws -> ProbeJob? {
        try lock.withLock {
            guard var job = try read() else { return nil }
            if job.state == .analyzing { job.transition(to: .pending) }
            return job
        }
    }

    func remove(id: UUID) throws {
        try lock.withLock {
            guard try read()?.id == id else { return }
            try FileManager.default.removeItem(at: file)
        }
    }

    fileprivate func matches(_ job: ProbeJob) throws -> Bool {
        try lock.withLock { try read()?.hasSameInput(as: job) == true }
    }

    @discardableResult
    fileprivate func transition(_ job: ProbeJob, to state: ProbeJobState, result: ProbeResult? = nil) throws -> Bool {
        try lock.withLock {
            guard var current = try read(), current.hasSameInput(as: job) else { return false }
            current.transition(to: state, result: result)
            try write(current)
            return true
        }
    }

    private func read() throws -> ProbeJob? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        return try JSONDecoder().decode(ProbeJob.self, from: data)
    }

    private func write(_ job: ProbeJob) throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        try FileManager.default.setAttributes(attributes, ofItemAtPath: directory.path)
        try LocalDiaryFiles.excludeFromBackup(directory)
        try JSONEncoder().encode(job).write(to: file, options: options)
        try LocalDiaryFiles.excludeFromBackup(file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

actor ProbeRunner {
    enum Failure: Error, Equatable {
        case alreadyRunning, staleJob, registrationChanged, alreadyCompleted
    }

    private let store: ProbeJobStore
    private let client: ResponsesClient
    private let accessToken: @Sendable (String) async throws -> String
    private let activeRegistrationID: @Sendable () async -> String?
    private let sleep: @Sendable (Duration) async throws -> Void
    private var running = false

    init(store: ProbeJobStore, client: ResponsesClient = ResponsesClient(),
         accessToken: @escaping @Sendable (String) async throws -> String,
         activeRegistrationID: @escaping @Sendable () async -> String?,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.store = store
        self.client = client
        self.accessToken = accessToken
        self.activeRegistrationID = activeRegistrationID
        self.sleep = sleep
    }

    func run(_ job: ProbeJob, diagnostic: (@Sendable (ResponseFailureDiagnostic) async -> Void)? = nil) async throws -> ProbeResult {
        guard !running else { throw Failure.alreadyRunning }
        guard try store.matches(job) else { throw Failure.staleJob }
        guard try store.load()?.state != .completed else { throw Failure.alreadyCompleted }
        running = true
        defer { running = false }
        do {
            try await checkOwnerAndJob(job)
            guard try store.transition(job, to: .analyzing) else { throw Failure.staleJob }
            let delays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]
            for attempt in 0...delays.count {
                do {
                    try await checkOwnerAndJob(job)
                    let token = try await accessToken(job.registrationID)
                    try await checkOwnerAndJob(job)
                    let result = try await client.run(model: job.model, text: job.text, image: job.image, accessToken: token, diagnostic: diagnostic)
                    try await checkOwnerAndJob(job)
                    guard try store.transition(job, to: .completed, result: result) else { throw Failure.staleJob }
                    return result
                } catch {
                    try await checkOwnerAndJob(job)
                    guard attempt < delays.count, Self.isTransient(error) else { throw error }
                    try await sleep(delays[attempt])
                    try await checkOwnerAndJob(job)
                }
            }
            throw Failure.staleJob
        } catch {
            let interrupted = error is CancellationError || (error as? URLError)?.code == .cancelled
            guard try store.transition(job, to: interrupted ? .pending : .needsRetry) else { throw Failure.staleJob }
            throw error
        }
    }

    private func checkOwnerAndJob(_ job: ProbeJob) async throws {
        try Task.checkCancellation()
        let registration = await activeRegistrationID()
        try Task.checkCancellation()
        guard registration == job.registrationID else { throw Failure.registrationChanged }
        guard try store.matches(job) else { throw Failure.staleJob }
    }

    static func isTransient(_ error: any Error) -> Bool {
        if let error = error as? URLError {
            return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                    .dnsLookupFailed, .notConnectedToInternet].contains(error.code)
        }
        if let error = error as? ResponsesClient.Failure {
            switch error {
            case .incompleteResponse, .usageUnavailable: return true
            case .http(let status): return (500...599).contains(status) || status == 408
            default: return false
            }
        }
        return false
    }
}
