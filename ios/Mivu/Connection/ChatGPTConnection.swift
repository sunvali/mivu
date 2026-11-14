import Foundation
import FoundationModels
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

enum KeyConnectionError: Error, Equatable { case consentRequired, invalidKey, rejected, unavailable, storage }

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
    case keyRejected = "This key was rejected. Replace it in Settings → Coach AI."
    case keyQuota = "Your AI service is out of credit or over its limit. Check its usage page, then try again."
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

    @ObservationIgnored private let appleModelAvailable: @Sendable () -> Bool
    @ObservationIgnored private let keyStore: AIKeyStore
    @ObservationIgnored private let keyClient: KeyServiceClient
    /// Services with a saved key. Each keeps its own key, model list and chosen model, so switching loses nothing.
    private(set) var connectedServices: Set<KeyService> = []
    private(set) var serviceModels: [KeyService: [AvailableModel]] = [:]
    private var chosenModels: [KeyService: String] = [:]
    private(set) var isCheckingKey = false

    /// `apple` is the on-device model, a no-account fallback for logging; ChatGPT is the main Coach.
    /// The other four run on the person's own key.
    enum Provider: String, CaseIterable {
        case apple, chatGPT, claude, openAI, gemini, openRouter
        var keyService: KeyService? { KeyService(rawValue: rawValue) }
    }

    nonisolated static let appleIntelligenceAvailable: @Sendable () -> Bool = {
        if #available(iOS 27.0, *) { SystemLanguageModel.default.isAvailable } else { false }
    }

    /// The person's choice while it can answer; otherwise Apple when this iPhone can run it, then ChatGPT.
    var provider: Provider {
        get {
            access(keyPath: \.provider)
            let stored = preferences.string(forKey: "aiProvider").flatMap(Provider.init)
            if let stored, stored == .chatGPT || available(stored) { return stored }
            // Someone with a saved ChatGPT connection keeps it until they pick Apple, also while it restores at launch.
            // Also where a key service lands once its key is removed.
            if planAuthorized || preferences.string(forKey: "selectedRegistrationID") != nil { return .chatGPT }
            return appleModelAvailable() ? .apple : .chatGPT
        }
        set { withMutation(keyPath: \.provider) { preferences.set(newValue.rawValue, forKey: "aiProvider") } }
    }

    func available(_ provider: Provider) -> Bool {
        if let service = provider.keyService { return connectedServices.contains(service) && consented(to: service) }
        return provider == .apple ? appleModelAvailable() : planAuthorized
    }
    var activeName: String { provider.keyService?.name ?? (provider == .apple ? "Apple Intelligence" : "ChatGPT") }
    var activeUsagePage: URL? { provider.keyService?.usagePage ?? (provider == .chatGPT ? MivuLinks.chatGPTUsage : nil) }
    var appleAvailable: Bool { appleModelAvailable() }
    var canInfer: Bool { available(provider) }
    /// Cloud models tune onboarding targets; the formula estimate beats the on-device model there.
    var tunesTargets: Bool { provider != .apple && available(provider) }

    init(auth: AuthSession = AuthSession(), client: ResponsesClient = ResponsesClient(),
         jobStore: ProbeJobStore? = nil, preferences: UserDefaults = .standard,
         appleModelAvailable: @escaping @Sendable () -> Bool = ChatGPTConnection.appleIntelligenceAvailable,
         keyStore: AIKeyStore? = nil, keyClient: KeyServiceClient = KeyServiceClient()) {
        self.appleModelAvailable = appleModelAvailable
        let keys = keyStore ?? .local
        self.keyStore = keys
        self.keyClient = keyClient
        self.auth = auth
        self.client = client
        self.preferences = preferences
        planWelcomeSeen = preferences.bool(forKey: "chatGPTPlanWelcomeSeen")
        let store = jobStore ?? ProbeJobStore(directory: URL.applicationSupportDirectory.appendingPathComponent("Mivu/ConnectionProof", isDirectory: true))
        self.jobStore = store
        runner = ProbeRunner(store: store, client: client,
            accessToken: { try await auth.accessToken(expectedRegistrationID: $0) },
            activeRegistrationID: { await auth.snapshot()?.registrationID })
        // Read here, not in restore(), so the active AI is right from the first frame.
        for service in KeyService.allCases where (try? keys.load(service)) != nil {
            connectedServices.insert(service)
            chosenModels[service] = preferences.string(forKey: "aiModel." + service.rawValue)
        }
    }

    // Launch restoration is explicit; constructing the screen never activates saved credentials.
    func restore() async {
        await refreshServiceModels()
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

    // MARK: Key services

    func consented(to service: KeyService) -> Bool { preferences.bool(forKey: service.consentKey) }
    func recordConsent(to service: KeyService) { preferences.set(true, forKey: service.consentKey) }

    func selectedModel(for service: KeyService) -> String { chosenModels[service] ?? "" }
    func selectModel(_ slug: String, for service: KeyService) {
        guard serviceModels[service]?.contains(where: { $0.slug == slug }) == true else { return }
        chosenModels[service] = slug
        preferences.set(slug, forKey: "aiModel." + service.rawValue)
    }

    /// Checks the key with the service before keeping it, then makes that service the Coach AI.
    func saveKey(_ raw: String, for service: KeyService) async throws {
        guard consented(to: service) else { throw KeyConnectionError.consentRequired }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: { $0.isWhitespace }) else { throw KeyConnectionError.invalidKey }
        guard !isCheckingKey else { throw KeyConnectionError.unavailable }
        isCheckingKey = true
        defer { isCheckingKey = false }
        let listed: [AvailableModel]
        do { listed = try await keyClient.models(service, key: key) }
        catch let failure as ResponsesClient.Failure where failure == .unauthorized || failure == .forbidden { throw KeyConnectionError.rejected }
        catch { throw KeyConnectionError.unavailable }
        guard !listed.isEmpty else { throw KeyConnectionError.unavailable }
        do { try keyStore.save(key, for: service) }
        catch AIKeyStore.Failure.invalidKey { throw KeyConnectionError.invalidKey }
        catch { throw KeyConnectionError.storage }
        generation += 1   // a reply still in flight on the old key must not complete
        connectedServices.insert(service)
        adopt(listed, for: service)
        notice = nil
        provider = Provider(rawValue: service.rawValue)!
    }

    /// Signs in to OpenRouter over whichever window is in front.
    func signInOpenRouter() async {
        let scene = UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let window = scene?.keyWindow else { notice = .unavailable; return }
        let browser = NativeAuthorizationBrowser(window: window)
        await signInOpenRouter { try await browser.open($0) }
    }

    // shortcut: OpenRouter's acceptance of a 127.0.0.1 callback is unverified, fall back to a pasted key if sign-in cannot return
    func signInOpenRouter(openBrowser: @escaping @MainActor (URL) async throws -> Void) async {
        guard !isConnecting, !isDisconnecting, consented(to: .openRouter) else { return }
        generation += 1
        let revision = generation
        isConnecting = true
        notice = nil
        let task = Task { await self.authorizeOpenRouter(revision: revision, openBrowser: openBrowser) }
        connectionTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if revision == generation { connectionTask = nil; isConnecting = false }
    }

    private func authorizeOpenRouter(revision: Int, openBrowser: @escaping @MainActor (URL) async throws -> Void) async {
        let callback = LoopbackCallback()
        listener = callback
        defer { callback.stop(); if listener === callback { listener = nil } }
        do {
            let attempt = try OpenRouterSignIn.make(callbackURL: try await callback.start())
            guard revision == generation else { return }
            var code: String?
            _ = try await callback.receive(validating: { code = try attempt.code(from: $0) },
                                           openBrowser: openBrowser, browserURL: attempt.authorizationURL)
            try Task.checkCancellation()
            guard revision == generation, let code else { return }
            let key = try await keyClient.openRouterKey(attempt.exchange(code: code))
            guard revision == generation else { return }
            try await saveKey(key, for: .openRouter)
            // saveKey moved the generation on, so the caller no longer clears these.
            connectionTask = nil; isConnecting = false
        } catch {
            guard revision == generation else { return }
            notice = error is CancellationError ? .cancelled : .unavailable
        }
    }

    func removeKey(for service: KeyService) {
        do { try keyStore.remove(service) } catch { notice = .storageFailed; return }
        generation += 1
        connectedServices.remove(service)
        serviceModels[service] = nil
    }

    /// Keeps the chosen model while the service still lists it; otherwise the service default, then the first listed.
    private func adopt(_ listed: [AvailableModel], for service: KeyService) {
        serviceModels[service] = listed
        guard !listed.contains(where: { $0.slug == chosenModels[service] }) else { return }
        let model = listed.contains { $0.slug == service.defaultModel } ? service.defaultModel : listed[0].slug
        chosenModels[service] = model
        preferences.set(model, forKey: "aiModel." + service.rawValue)
    }

    /// The list only feeds the picker; when it cannot load, the saved model keeps working.
    private func refreshServiceModels() async {
        guard let service = provider.keyService, let key = try? keyStore.load(service) else { return }
        let revision = generation
        guard let listed = try? await keyClient.models(service, key: key), !listed.isEmpty, revision == generation else { return }
        adopt(listed, for: service)
    }

    private func respondWithKey(_ service: KeyService, key: String, model: String, revision: Int,
                                input: [CoachInferenceInput], namespace: Data?) async throws -> CoachInferenceResult {
        func validate() throws {
            try Task.checkCancellation()
            guard generation == revision, provider.keyService == service, selectedModel(for: service) == model else { throw SessionError.sessionChanged }
        }
        try validate()
        do {
            let result = try await keyClient.respond(service, model: model, input: input, toolNamespace: namespace, key: key)
            try validate()
            return result
        } catch {
            try validate()
            let failure = error as? ResponsesClient.Failure
            if failure == .unauthorized || failure == .forbidden { notice = .keyRejected }
            else if failure == .quotaReached { notice = .keyQuota }
            throw error
        }
    }

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
        if let service = provider.keyService {
            let model = selectedModel(for: service)
            guard !model.isEmpty, let key = try? keyStore.load(service) else { throw SessionError.noActiveSession }
            let revision = generation
            return { [self] input, namespace in
                try await self.respondWithKey(service, key: key, model: model, revision: revision, input: input, namespace: namespace)
            }
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
