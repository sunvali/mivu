import Foundation
import Observation
import UIKit

struct ProbeResult: Equatable, Sendable {
    let model: String
    let outputText: String
}

enum ProofState: Equatable {
    case disconnected, connecting, connected, planPermissionMissing
    case quotaReached, unavailable, queued, analyzing, completed, needsRetry
}

enum ConnectionNotice: String {
    case cancelled = "Connection cancelled"
    case denied = "Connection permission declined"
    case unavailable = "Connection unavailable. Try again."
    case saveFailed = "Sample could not be saved. No request sent."
    case storageFailed = "Local sample storage unavailable"
    case retry = "Analysis paused. Retry when ready."
    case quota = "ChatGPT usage limit reached. Check ChatGPT usage settings, then retry when usage is available."
    case permission = "Enable ChatGPT plan usage before sending a request."
    case revoked = "Reconnect to authorize plan usage."
    case disconnected = "Local credentials removed"
    case unconfirmed = "Local credentials removed. Remote revocation unconfirmed."
}

@Observable @MainActor
final class ChatGPTConnection {
    private(set) var accountState: ProofState = .disconnected
    private(set) var inferenceState: ProofState?
    private(set) var lastCompletedProbe: ProbeResult?
    private(set) var models: [AvailableModel] = []
    var selectedModel = ""
    private(set) var job: ProbeJob?
    private(set) var notice: ConnectionNotice?
    private(set) var isConnecting = false
    private(set) var isLoadingModels = false
    private(set) var isAnalyzing = false
    private(set) var isDisconnecting = false
    private(set) var isStorageUnavailable = false
    private(set) var activeRegistrationID: String?
    var state: ProofState { inferenceState ?? accountState }
    var planAuthorized: Bool { accountState == .connected }
    var canCapture: Bool { isForeground && planAuthorized && !isStorageUnavailable && models.contains(where: { $0.slug == selectedModel }) && job == nil && !isConnecting && !isLoadingModels && !isDisconnecting }
    var canRetry: Bool {
        isForeground && planAuthorized && !isStorageUnavailable && job?.registrationID == activeRegistrationID && job?.state != .completed
            && models.contains(where: { $0.slug == job?.model }) && !isAnalyzing && !isConnecting && !isLoadingModels && !isDisconnecting
    }

    @ObservationIgnored private let auth: AuthSession
    @ObservationIgnored private let client: ResponsesClient
    @ObservationIgnored private let jobStore: ProbeJobStore
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let runner: ProbeRunner
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    @ObservationIgnored private var listener: LoopbackCallback?
    private var generation = 0
    @ObservationIgnored private var isForeground = true

    init(auth: AuthSession = AuthSession(), client: ResponsesClient = ResponsesClient(),
         jobStore: ProbeJobStore? = nil, preferences: UserDefaults = .standard) {
        self.auth = auth
        self.client = client
        self.preferences = preferences
        let store = jobStore ?? ProbeJobStore(directory: URL.applicationSupportDirectory.appendingPathComponent("Mivu/ConnectionProof", isDirectory: true))
        self.jobStore = store
        runner = ProbeRunner(store: store, client: client,
            accessToken: { try await auth.accessToken(expectedRegistrationID: $0) },
            activeRegistrationID: { await auth.snapshot()?.registrationID })
    }

    // Launch restoration is explicit; constructing the screen never activates saved credentials.
    func restore() async {
        guard !isConnecting, !isDisconnecting else { return }
        let revision = generation
        guard reloadSavedJob() else { return }
        do {
            guard let selection = preferences.string(forKey: "selectedRegistrationID") else {
                return
            }
            let snapshot = try await auth.restore(registrationID: selection)
            guard revision == generation else { return }
            apply(snapshot)
            updateSavedState()
            if planAuthorized { await loadModels() }
            guard revision == generation else { return }
            resumePending()
        } catch {
            guard revision == generation else { return }
            notice = .unavailable
        }
    }

    func connect(window: UIWindow) async {
        let browser = NativeAuthorizationBrowser(window: window)
        await connect { try await browser.open($0) }
    }

    func connect(openBrowser: @escaping @MainActor (URL) async throws -> Void) async {
        guard !isConnecting, !isDisconnecting, !isAnalyzing else { return }
        generation += 1
        let revision = generation
        isConnecting = true
        isLoadingModels = false
        notice = nil
        let task = Task { await self.authorize(revision: revision, openBrowser: openBrowser) }
        connectionTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if revision == generation { connectionTask = nil; isConnecting = false }
    }

    private func authorize(revision: Int, openBrowser: @escaping @MainActor (URL) async throws -> Void) async {
        let callback = LoopbackCallback()
        listener = callback
        defer { callback.stop(); if revision == generation { listener = nil } }
        do {
            let hostID = try await auth.hostID()
            guard revision == generation else { return }
            let registrations = try await auth.registrations()
            guard revision == generation else { return }
            let selection = activeRegistrationID ?? preferences.string(forKey: "selectedRegistrationID")
            let returning = registrations.first { $0.id == selection }
            let redirect = try await callback.start()
            guard revision == generation else { return }
            var attempt = try OAuthAttempt.make(hostID: hostID, issuedClientID: returning?.issuedClientID,
                callbackURL: redirect, requestPlanConsent: returning != nil && accountState == .planPermissionMissing)
            var code: AuthorizationCode?
            _ = try await callback.receive(validating: { code = try attempt.consumeCallback($0) },
                openBrowser: openBrowser, browserURL: attempt.authorizationURL)
            guard revision == generation else { return }
            try Task.checkCancellation()
            guard let code else { throw OAuthError.invalidCallback }
            let snapshot = try await auth.establish(code: code, verifier: attempt.verifier, nonce: attempt.nonce,
                returningRegistrationID: returning?.id)
            guard revision == generation else { return }
            preferences.set(snapshot.registrationID, forKey: "selectedRegistrationID")
            if preferences.string(forKey: "pausedRegistrationID") == snapshot.registrationID {
                preferences.removeObject(forKey: "pausedRegistrationID")
            }
            apply(snapshot)
            models = []; selectedModel = ""
            let storageAvailable = reloadSavedJob()
            if planAuthorized { await loadModels() }
            guard revision == generation else { return }
            if storageAvailable { resumePending() }
        } catch {
            guard revision == generation else { return }
            if error is CancellationError { notice = .cancelled }
            else if error as? OAuthError == .denied { notice = .denied }
            else { notice = .unavailable }
        }
    }

    func cancelConnection() {
        let wasConnecting = isConnecting
        generation += 1
        connectionTask?.cancel()
        listener?.stop()
        connectionTask = nil; listener = nil; isConnecting = false; isLoadingModels = false
        if wasConnecting { notice = .cancelled }
    }

    func loadModels() async {
        guard planAuthorized, let owner = activeRegistrationID, !isLoadingModels, !isDisconnecting else { return }
        let revision = generation
        isLoadingModels = true
        defer { if revision == generation { isLoadingModels = false } }
        do {
            let token = try await auth.accessToken(expectedRegistrationID: owner)
            guard revision == generation else { return }
            let catalog = try await client.models(accessToken: token)
            guard revision == generation else { return }
            models = catalog
            if !catalog.contains(where: { $0.slug == selectedModel }) { selectedModel = catalog.first?.slug ?? "" }
        } catch {
            guard revision == generation else { return }
            await reflectFailure(error, revision: revision)
        }
    }

    @discardableResult
    func captureSample() -> Bool {
        guard canCapture, let owner = activeRegistrationID,
              models.contains(where: { $0.slug == selectedModel }) else { return false }
        let capture = ProbeJob(text: SyntheticConnectionProbe.prompt, image: SyntheticConnectionProbe.image,
            model: selectedModel, registrationID: owner)
        do { try jobStore.save(capture) }
        catch { notice = .saveFailed; return false }
        job = capture
        lastCompletedProbe = nil
        preferences.removeObject(forKey: "quotaJobID")
        notice = nil
        inferenceState = .queued
        resumePending()
        return true
    }

    func retry() {
        guard canRetry, var pending = job, pending.registrationID == activeRegistrationID,
              models.contains(where: { $0.slug == pending.model }) else { return }
        pending.state = .pending
        do { try jobStore.save(pending) }
        catch { markStorageUnavailable(); return }
        job = pending; notice = nil
        preferences.removeObject(forKey: "quotaJobID")
        resumePending()
    }

    private func resumePending() {
        guard isForeground, planAuthorized, !isStorageUnavailable, !isAnalyzing, !isDisconnecting, let pending = job, pending.state == .pending,
              pending.registrationID == activeRegistrationID,
              models.contains(where: { $0.slug == pending.model }) else { return }
        let revision = generation
        isAnalyzing = true
        inferenceState = .analyzing
        probeTask = Task {
            do {
                _ = try await runner.run(pending)
                guard revision == generation, job?.id == pending.id else { return }
                _ = reloadSavedJob()
            } catch {
                guard revision == generation, job?.id == pending.id else { return }
                lastCompletedProbe = nil
                if reloadSavedJob(), !(error is CancellationError) { await reflectFailure(error, revision: revision) }
            }
            if revision == generation { isAnalyzing = false; probeTask = nil }
        }
    }

    var sessionRevision: Int { generation }

    func coachInference() throws -> @Sendable ([CoachInferenceInput], Data) async throws -> CoachInferenceResult {
        guard planAuthorized, let owner = activeRegistrationID,
              !isConnecting, !isDisconnecting,
              models.contains(where: { $0.slug == selectedModel }) else {
            throw SessionError.noActiveSession
        }
        let revision = generation, model = selectedModel
        return { [self] input, namespace in
            try await self.respondForCoach(input: input, namespace: namespace,
                                           owner: owner, revision: revision, model: model)
        }
    }

    private func respondForCoach(input: [CoachInferenceInput], namespace: Data,
                                 owner: String, revision: Int, model: String) async throws -> CoachInferenceResult {
        func validate() throws {
            try Task.checkCancellation()
            guard generation == revision, activeRegistrationID == owner,
                  selectedModel == model, planAuthorized,
                  !isConnecting, !isDisconnecting,
                  models.contains(where: { $0.slug == model }) else { throw SessionError.sessionChanged }
        }
        try validate()
        do {
            let token = try await auth.accessToken(expectedRegistrationID: owner)
            try validate()
            let result = try await client.respond(model: model, input: input,
                                                  toolNamespace: namespace, accessToken: token)
            try validate()
            return result
        } catch {
            try validate()
            if !(error is CancellationError) { await reflectFailure(error, revision: revision) }
            throw error
        }
    }

    func waitForProbe() async { await probeTask?.value }

    func deleteSample() async {
        let task = probeTask
        task?.cancel()
        cancelConnection()
        let deletionRevision = generation
        let id = job?.id
        // Remove first, before awaiting a cancelled transport, so late output cannot resurrect capture.
        do { if let id { try jobStore.remove(id: id) } }
        catch {
            await task?.value
            guard deletionRevision == generation else { return }
            isAnalyzing = false; probeTask = nil
            markStorageUnavailable()
            return
        }
        job = nil; lastCompletedProbe = nil; inferenceState = nil
        isStorageUnavailable = false
        preferences.removeObject(forKey: "quotaJobID")
        await task?.value
        guard deletionRevision == generation else { return }
        isAnalyzing = false; probeTask = nil; isLoadingModels = false; notice = nil
    }

    func disconnect() async {
        guard !isDisconnecting else { return }
        let previousOwner = activeRegistrationID
        let previousModels = models
        let previousModel = selectedModel
        cancelConnection()
        let revision = generation
        isDisconnecting = true
        defer { isDisconnecting = false }
        let task = probeTask
        task?.cancel()
        accountState = .disconnected; activeRegistrationID = nil
        models = []; selectedModel = ""; lastCompletedProbe = nil; inferenceState = nil
        var outcome: RevocationOutcome?
        var retained: SessionSnapshot?
        do { outcome = try await auth.disconnect() }
        catch { retained = await auth.snapshot() }
        if outcome != nil, preferences.string(forKey: "selectedRegistrationID") == previousOwner {
            preferences.removeObject(forKey: "selectedRegistrationID")
        }
        await task?.value
        // No new probe can start while disconnecting; always settle its running flag.
        probeTask = nil; isAnalyzing = false
        guard revision == generation else { return }
        _ = reloadSavedJob()
        if let outcome {
            notice = outcome == .confirmed ? .disconnected : .unconfirmed
        } else {
            apply(retained)
            if let retained, retained.registrationID == previousOwner {
                preferences.set(retained.registrationID, forKey: "selectedRegistrationID")
                models = previousModels; selectedModel = previousModel
            }
            notice = .storageFailed
        }
    }

    func enterBackground() {
        isForeground = false
        cancelConnection()
        probeTask?.cancel()
        isLoadingModels = false
        lastCompletedProbe = nil
    }

    func enterForeground() async {
        isForeground = true
        let revision = generation
        await probeTask?.value
        guard revision == generation, !isConnecting, !isDisconnecting else { return }
        isAnalyzing = false; probeTask = nil
        let snapshot = await auth.snapshot()
        guard revision == generation else { return }
        apply(snapshot)
        let storageAvailable = reloadSavedJob()
        if planAuthorized, models.isEmpty { await loadModels() }
        guard revision == generation else { return }
        if storageAvailable { resumePending() }
    }

    private func apply(_ snapshot: SessionSnapshot?) {
        activeRegistrationID = snapshot?.registrationID
        accountState = snapshot.map {
            $0.planPermissionGranted && preferences.string(forKey: "pausedRegistrationID") != $0.registrationID
                ? .connected : .planPermissionMissing
        } ?? .disconnected
        if !planAuthorized { models = []; selectedModel = ""; lastCompletedProbe = nil; inferenceState = nil }
    }

    private func updateSavedState() {
        lastCompletedProbe = nil
        guard let job, job.registrationID == activeRegistrationID, planAuthorized else { inferenceState = nil; return }
        switch job.state {
        case .pending: inferenceState = .queued
        case .analyzing: inferenceState = .analyzing
        case .needsRetry:
            inferenceState = preferences.string(forKey: "quotaJobID") == job.id.uuidString ? .quotaReached : .needsRetry
        case .completed: inferenceState = .completed; lastCompletedProbe = job.result
        }
    }

    @discardableResult
    private func reloadSavedJob() -> Bool {
        do {
            job = try jobStore.load()
            isStorageUnavailable = false
            if notice == .storageFailed { notice = nil }
            updateSavedState()
            return true
        } catch {
            markStorageUnavailable()
            return false
        }
    }

    private func markStorageUnavailable() {
        isStorageUnavailable = true
        lastCompletedProbe = nil
        inferenceState = job == nil ? nil : .needsRetry
        notice = .storageFailed
    }

    private func reflectFailure(_ error: any Error, revision: Int) async {
        let snapshot = await auth.snapshot()
        guard revision == generation else { return }
        apply(snapshot)
        if error as? ResponsesClient.Failure == .quotaReached {
            if let job { preferences.set(job.id.uuidString, forKey: "quotaJobID") }
            inferenceState = .quotaReached; notice = .quota
        }
        else if error as? ResponsesClient.Failure == .forbidden {
            pausePermission(snapshot)
            notice = .permission
        } else if error as? ResponsesClient.Failure == .unauthorized {
            pausePermission(snapshot)
            notice = .revoked
        } else if error as? SessionError == .invalidRefresh || snapshot == nil {
            accountState = .disconnected; models = []; selectedModel = ""; notice = .revoked
        } else if error as? SessionError == .planPermissionMissing { accountState = .planPermissionMissing; notice = .permission }
        else { notice = job == nil ? .unavailable : .retry }
    }

    private func pausePermission(_ snapshot: SessionSnapshot?) {
        if let snapshot { preferences.set(snapshot.registrationID, forKey: "pausedRegistrationID") }
        accountState = snapshot == nil ? .disconnected : .planPermissionMissing
        models = []; selectedModel = ""; lastCompletedProbe = nil; inferenceState = nil
    }
}
