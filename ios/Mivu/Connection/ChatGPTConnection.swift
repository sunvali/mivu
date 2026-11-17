import Foundation
import FoundationModels
import Observation
import UIKit

struct ProbeResult: Equatable, Sendable {
    let model: String
    let outputText: String
}

enum ProofState: Equatable {
    case disconnected, connecting, connected, planPermissionMissing, planNotEligible
    case quotaReached, unavailable, queued, analyzing, completed, needsRetry
}

enum ConnectionNotice: String {
    case cancelled = "Connection cancelled"
    case denied = "Connection permission declined"
    case unavailable = "Connection unavailable. Try again."
    case saveFailed = "Sample could not be saved. No request sent."
    case storageFailed = "Local sample storage unavailable"
    case retry = "Analysis paused. Retry when ready."
    case quota = "ChatGPT usage limit reached. Open Manage usage in Settings, then retry when usage is available."
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
    private(set) var failureDiagnostic: ResponseFailureDiagnostic?
    private(set) var isConnecting = false
    private(set) var isLoadingModels = false
    private(set) var isAnalyzing = false
    private(set) var isDisconnecting = false
    private(set) var isStorageUnavailable = false
    private(set) var activeRegistrationID: String?
    var state: ProofState { inferenceState ?? accountState }
    var planAuthorized: Bool { accountState == .connected }
    /// Signed in, but OpenAI says this account's plan can't be used in other apps.
    var planNotEligible: Bool { accountState == .planNotEligible }
    private(set) var planScopeGranted = false
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
    @ObservationIgnored private var lastEligibilityCheck: Date?

    @ObservationIgnored private let appleModelAvailable: @Sendable () -> Bool
    @ObservationIgnored private let appleModelSupported: @Sendable () -> Bool

    /// `apple` is the on-device model, a no-account fallback for logging; ChatGPT is the main Coach.
    enum Provider: String { case apple, chatGPT }

    nonisolated static let appleIntelligenceAvailable: @Sendable () -> Bool = {
        if #available(iOS 27.0, *) { SystemLanguageModel.default.isAvailable } else { false }
    }

    /// False only on hardware that can never run Apple's model; switched off or still downloading still counts.
    nonisolated static let appleIntelligenceSupported: @Sendable () -> Bool = {
        if #available(iOS 27.0, *) { appleSupported(SystemLanguageModel.default.availability) } else { false }
    }

    @available(iOS 27.0, *)
    nonisolated static func appleSupported(_ availability: SystemLanguageModel.Availability) -> Bool {
        if case .unavailable(.deviceNotEligible) = availability { false } else { true }
    }

    /// The person's choice while it can answer; otherwise Apple when this iPhone can run it, then ChatGPT.
    var provider: Provider {
        get {
            access(keyPath: \.provider)
            let stored = preferences.string(forKey: "aiProvider").flatMap(Provider.init)
            if let stored, available(stored) || (stored == .chatGPT && !planNotEligible) { return stored }
            // Someone with a saved ChatGPT connection keeps it until they pick Apple, also while it restores at launch.
            if stored == nil, !planNotEligible, planAuthorized || preferences.string(forKey: "selectedRegistrationID") != nil { return .chatGPT }
            return appleModelAvailable() ? .apple : .chatGPT
        }
        set { withMutation(keyPath: \.provider) { preferences.set(newValue.rawValue, forKey: "aiProvider") } }
    }

    func available(_ provider: Provider) -> Bool { provider == .apple ? appleModelAvailable() : planAuthorized }
    var appleAvailable: Bool { appleModelAvailable() }
    var appleSupported: Bool { appleModelSupported() }
    var canInfer: Bool { available(provider) }
    /// Only ChatGPT tunes onboarding targets; the formula estimate beats the on-device model there.
    var tunesTargets: Bool { provider == .chatGPT && planAuthorized }

    init(auth: AuthSession = AuthSession(), client: ResponsesClient = ResponsesClient(),
         jobStore: ProbeJobStore? = nil, preferences: UserDefaults = .standard,
         appleModelAvailable: @escaping @Sendable () -> Bool = ChatGPTConnection.appleIntelligenceAvailable,
         appleModelSupported: @escaping @Sendable () -> Bool = ChatGPTConnection.appleIntelligenceSupported) {
        self.appleModelAvailable = appleModelAvailable
        self.appleModelSupported = appleModelSupported
        self.auth = auth
        self.client = client
        self.preferences = preferences
        planWelcomeSeen = preferences.bool(forKey: "chatGPTPlanWelcomeSeen")
        let store = jobStore ?? ProbeJobStore(directory: URL.applicationSupportDirectory.appendingPathComponent("Mivu/ConnectionProof", isDirectory: true))
        self.jobStore = store
        runner = ProbeRunner(store: store, client: client,
            accessToken: { try await auth.accessToken(expectedRegistrationID: $0) },
            activeRegistrationID: { await auth.snapshot()?.registrationID })
    }

    // Launch restoration is explicit; constructing the screen never activates saved credentials.
    func restore() async {
        // A connection saved before the sharing consent existed stays unused until the person agrees and reconnects.
        guard !isConnecting, !isDisconnecting, sharingConsented else { return }
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
            if planNotEligible { await checkEligibility() }
            guard revision == generation else { return }
            resumePending()
        } catch {
            guard revision == generation else { return }
            notice = .unavailable
        }
    }

    /// Whether the person agreed to send meal and profile data to OpenAI; asked before connecting.
    var sharingConsented: Bool { preferences.bool(forKey: "openAISharingConsent") }
    func recordSharingConsent() { preferences.set(true, forKey: "openAISharingConsent") }

    /// OpenAI's Sign in with ChatGPT guidelines: confirm plan use once, the first time it is enabled.
    private(set) var planWelcomeSeen: Bool
    var showsPlanWelcome: Bool { provider == .chatGPT && planAuthorized && !planWelcomeSeen }
    func acknowledgePlanWelcome() { planWelcomeSeen = true; preferences.set(true, forKey: "chatGPTPlanWelcomeSeen") }

    /// Explained once per account, and only when no on-device model takes over.
    var showsNotEligibleNotice: Bool {
        access(keyPath: \.showsNotEligibleNotice)
        return planNotEligible && !appleModelAvailable()
            && preferences.string(forKey: "notEligibleNoticeSeenRegistrationID") != activeRegistrationID
    }
    func acknowledgeNotEligibleNotice() {
        withMutation(keyPath: \.showsNotEligibleNotice) { preferences.set(activeRegistrationID, forKey: "notEligibleNoticeSeenRegistrationID") }
    }

    /// Signs in over whichever window is in front, so any screen can start it.
    func connect() async {
        let scene = UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let window = scene?.keyWindow else { notice = .unavailable; return }
        await connect(window: window)
    }

    func connect(window: UIWindow) async {
        let browser = NativeAuthorizationBrowser(window: window)
        await connect { try await browser.open($0) }
    }

    func connect(openBrowser: @escaping @MainActor (URL) async throws -> Void) async {
        // Consent is enforced here, not only by the buttons that call this.
        guard !isConnecting, !isDisconnecting, !isAnalyzing, sharingConsented else { return }
        generation += 1
        failureDiagnostic = nil
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
            let askedConsent = returning != nil && (accountState == .planPermissionMissing || planNotEligible)
            var attempt = try OAuthAttempt.make(hostID: hostID, issuedClientID: returning?.issuedClientID,
                callbackURL: redirect, requestPlanConsent: askedConsent)
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
            // Asked for plan permission twice and still refused: OpenAI won't share this plan, so stop offering Enable.
            if snapshot.planPermissionGranted { preferences.removeObject(forKey: "notEligibleRegistrationID") }
            else if askedConsent { preferences.set(snapshot.registrationID, forKey: "notEligibleRegistrationID") }
            apply(snapshot)
            models = []; selectedModel = ""
            let storageAvailable = reloadSavedJob()
            if planAuthorized { await loadModels() }
            guard revision == generation else { return }
            if planAuthorized { await checkEligibility(force: true) }
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
        failureDiagnostic = nil
        connectionTask?.cancel()
        listener?.stop()
        connectionTask = nil; listener = nil; isConnecting = false; isLoadingModels = false
        if wasConnecting { notice = .cancelled }
    }

    func loadModels() async {
        guard planAuthorized, let owner = activeRegistrationID, !isLoadingModels, !isDisconnecting else { return }
        let revision = generation
        failureDiagnostic = nil
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

    /// One tiny request that tells whether OpenAI lets this account's plan be used here; temporary failures change nothing.
    func checkEligibility(force: Bool = false) async {
        guard planNotEligible || accountState == .connected, planScopeGranted, let owner = activeRegistrationID, !isDisconnecting else { return }
        if !force, let last = lastEligibilityCheck, Date.now.timeIntervalSince(last) < 900 { return }
        lastEligibilityCheck = .now
        let revision = generation
        do {
            let token = try await auth.accessToken(expectedRegistrationID: owner)
            let catalog = models.isEmpty ? try await client.models(accessToken: token) : models
            guard let model = catalog.first(where: { $0.slug == selectedModel })?.slug ?? catalog.first?.slug else { return }
            _ = try await client.respond(model: model, input: [.message(role: .user, text: EligibilityCheck.prompt, images: [])],
                                         toolNamespace: nil, accessToken: token)
            guard revision == generation, planNotEligible else { return }
            preferences.removeObject(forKey: "notEligibleRegistrationID")
            apply(await auth.snapshot())
            guard revision == generation, planAuthorized else { return }
            models = catalog
            if !catalog.contains(where: { $0.slug == selectedModel }) { selectedModel = catalog.first?.slug ?? "" }
            resumePending()
        } catch ResponsesClient.Failure.notEligible {
            guard revision == generation else { return }
            markNotEligible(await auth.snapshot())
        } catch {}
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
        failureDiagnostic = nil
        probeTask = Task { [self] in
            do {
                _ = try await runner.run(pending, diagnostic: { [weak self] failure in
                    await self?.recordDiagnostic(failure, revision: revision, model: pending.model)
                })
                guard revision == generation, job?.id == pending.id else { return }
                failureDiagnostic = nil
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
        let respond = try inference()
        return { input, namespace in try await respond(input, namespace) }
    }

    /// A request on the connected plan, bound to this session; `nil` tools for a plain answer such as onboarding targets.
    func inference() throws -> @Sendable ([CoachInferenceInput], Data?) async throws -> CoachInferenceResult {
        if provider == .apple {
            guard #available(iOS 27.0, *), appleModelAvailable() else { throw SessionError.noActiveSession }
            return { input, namespace in try await AppleInference.respondLocally(input, namespace: namespace) }
        }
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

    private func respondForCoach(input: [CoachInferenceInput], namespace: Data?,
                                 owner: String, revision: Int, model: String) async throws -> CoachInferenceResult {
        func validate() throws {
            try Task.checkCancellation()
            guard generation == revision, activeRegistrationID == owner,
                  selectedModel == model, planAuthorized,
                  !isConnecting, !isDisconnecting,
                  models.contains(where: { $0.slug == model }) else { throw SessionError.sessionChanged }
        }
        try validate()
        failureDiagnostic = nil
        do {
            let token = try await auth.accessToken(expectedRegistrationID: owner)
            try validate()
            let result = try await client.respond(model: model, input: input,
                                                  toolNamespace: namespace, accessToken: token, diagnostic: { [weak self] failure in
                await self?.recordDiagnostic(failure, revision: revision, model: model)
            })
            try validate()
            failureDiagnostic = nil
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
        if outcome != nil {
            preferences.removeObject(forKey: "notEligibleRegistrationID")
            preferences.removeObject(forKey: "notEligibleNoticeSeenRegistrationID")
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
        if planNotEligible { await checkEligibility() }
        guard revision == generation else { return }
        if storageAvailable { resumePending() }
    }

    private func apply(_ snapshot: SessionSnapshot?) {
        activeRegistrationID = snapshot?.registrationID
        planScopeGranted = snapshot?.planPermissionGranted ?? false
        accountState = snapshot.map {
            preferences.string(forKey: "notEligibleRegistrationID") == $0.registrationID ? .planNotEligible
                : $0.planPermissionGranted && preferences.string(forKey: "pausedRegistrationID") != $0.registrationID
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

    private func recordDiagnostic(_ failure: ResponseFailureDiagnostic, revision: Int, model: String) {
        guard revision == generation, selectedModel == model else { return }
        failureDiagnostic = failure
    }

    private func reflectFailure(_ error: any Error, revision: Int) async {
        let snapshot = await auth.snapshot()
        guard revision == generation else { return }
        if failureDiagnostic == nil { failureDiagnostic = ResponseFailureDiagnostic(error: error) }
        apply(snapshot)
        if error as? ResponsesClient.Failure == .quotaReached {
            if let job { preferences.set(job.id.uuidString, forKey: "quotaJobID") }
            inferenceState = .quotaReached; notice = .quota
        }
        else if error as? ResponsesClient.Failure == .notEligible {
            markNotEligible(snapshot)
            notice = nil
        } else if error as? ResponsesClient.Failure == .forbidden {
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

    private func markNotEligible(_ snapshot: SessionSnapshot?) {
        guard let snapshot else { return pausePermission(nil) }
        preferences.set(snapshot.registrationID, forKey: "notEligibleRegistrationID")
        if preferences.string(forKey: "pausedRegistrationID") == snapshot.registrationID { preferences.removeObject(forKey: "pausedRegistrationID") }
        accountState = .planNotEligible
        models = []; selectedModel = ""; lastCompletedProbe = nil; inferenceState = nil
    }

    private func pausePermission(_ snapshot: SessionSnapshot?) {
        if let snapshot { preferences.set(snapshot.registrationID, forKey: "pausedRegistrationID") }
        accountState = snapshot == nil ? .disconnected : .planPermissionMissing
        models = []; selectedModel = ""; lastCompletedProbe = nil; inferenceState = nil
    }
}
