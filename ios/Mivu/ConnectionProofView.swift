import SwiftUI

struct ConnectionProofView: View {
    @State private var connection = ChatGPTConnection()
    @State private var callbackProbe = BrowserCallbackProbe()
    @State private var window: UIWindow?
    @State private var callbackTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLanguage") private var language = "en"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Connection test", systemImage: "checkmark.shield").font(.headline)
                    Text("Connect your own ChatGPT plan before testing a sample image.").foregroundStyle(.secondary)
                    Text("This diagnostic uses only a synthetic image and prompt.").foregroundStyle(.secondary)
                }
                Section("Account") {
                    Label(accountStatus, systemImage: "person.crop.circle")
                    if connection.isConnecting {
                        ProgressView("Connecting")
                        Button("Cancel connection", role: .cancel) { connection.cancelConnection() }.frame(minHeight: 44)
                    } else {
                        Button(connection.activeRegistrationID == nil ? "Connect ChatGPT" : "Reauthorize ChatGPT") {
                            guard let window else { return }
                            Task { await connection.connect(window: window) }
                        }
                        .frame(minHeight: 44)
                        .disabled(window == nil || connection.isAnalyzing || connection.isDisconnecting || callbackProbe.state == .running)
                    }
                    if connection.activeRegistrationID != nil {
                        Button("Disconnect", role: .destructive) { Task { await connection.disconnect() } }
                            .frame(minHeight: 44).disabled(connection.isDisconnecting)
                    }
                    if let notice = connection.notice {
                        Text(LocalizedStringKey(notice.rawValue)).foregroundStyle(.secondary)
                            .accessibilityIdentifier("connectionNotice")
                    }
                }
                Section("Sample request") {
                    if connection.isLoadingModels {
                        ProgressView("Loading account models")
                    } else if !connection.models.isEmpty {
                        Picker("Account model", selection: $connection.selectedModel) {
                            ForEach(connection.models, id: \.slug) { Text($0.displayName).tag($0.slug) }
                        }
                        .frame(minHeight: 44)
                        .disabled(connection.isAnalyzing || connection.isConnecting || connection.isDisconnecting)
                        Text("The catalog does not guarantee image support. This sample checks compatibility.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No account models loaded").foregroundStyle(.secondary)
                    }
                    Button("Reload account models") { Task { await connection.loadModels() } }
                        .frame(minHeight: 44)
                        .disabled(!connection.planAuthorized || connection.isLoadingModels || connection.isAnalyzing || connection.isConnecting || connection.isDisconnecting)
                    Label(localSampleStatus, systemImage: "internaldrive")
                        .accessibilityIdentifier("localSampleStatus")
                    Label(inferenceStatus, systemImage: connection.lastCompletedProbe == nil ? "hourglass" : "checkmark.circle")
                        .accessibilityIdentifier("inferenceStatus")
                    Text("Only completed analysis will appear as a result.").foregroundStyle(.secondary)
                    if let result = connection.lastCompletedProbe {
                        Text(result.model).font(.caption).foregroundStyle(.secondary)
                        Text(result.outputText).textSelection(.enabled).accessibilityIdentifier("completedProbe")
                    }
                    Button("Save and test synthetic sample") { connection.captureSample() }
                        .frame(minHeight: 44).disabled(!connection.canCapture)
                        .accessibilityIdentifier("captureSyntheticSample")
                    if connection.job != nil {
                        Button("Retry analysis") { connection.retry() }
                            .frame(minHeight: 44).disabled(!connection.canRetry)
                        Button("Delete synthetic sample", role: .destructive) { Task { await connection.deleteSample() } }
                            .frame(minHeight: 44).disabled(connection.isDisconnecting)
                    }
                    Text("Pending work resumes when this app is active and authorized. Locked or suspended execution is not guaranteed.")
                        .foregroundStyle(.secondary)
                }
                Section("Native browser test") {
                    Label(callbackStatus, systemImage: callbackProbe.state == .passed ? "checkmark.circle" : "safari")
                        .accessibilityIdentifier("browserProbeStatus")
                    Text("Uses a synthetic local callback. No account sign-in or analysis request.").foregroundStyle(.secondary)
                    Button("Test native browser", action: testBrowser)
                        .frame(minHeight: 44)
                        .disabled(window == nil || callbackProbe.state == .running || connection.isConnecting || connection.isAnalyzing)
                        .accessibilityIdentifier("testNativeBrowser")
                    if callbackProbe.state == .running {
                        Button("Cancel browser test", role: .cancel) { callbackTask?.cancel() }.frame(minHeight: 44)
                    }
                }
                Section("Language") {
                    Picker("App language", selection: $language) {
                        Text("English").tag("en")
                        Text("עברית").tag("he")
                    }
                    .pickerStyle(.segmented).frame(minHeight: 44)
                }
            }
            .navigationTitle("Mivu")
        }
        .background(PresentationWindowReader { window = $0 })
        .task { await connection.restore() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { callbackTask?.cancel(); connection.enterBackground() }
            else if phase == .active { Task { await connection.enterForeground() } }
        }
        .onDisappear { callbackTask?.cancel(); connection.enterBackground() }
        .environment(\.locale, Locale(identifier: language))
        .environment(\.layoutDirection, language == "he" ? .rightToLeft : .leftToRight)
        .preferredColorScheme(proofColorScheme)
        .transformEnvironment(\.dynamicTypeSize) {
            if ProcessInfo.processInfo.arguments.contains("--proof-large-text") { $0 = .accessibility3 }
        }
    }

    private func testBrowser() {
        guard let window else { return }
        let browser = NativeAuthorizationBrowser(window: window)
        callbackTask = Task { await callbackProbe.run { try await browser.open($0) } }
    }

    private var proofColorScheme: ColorScheme? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--proof-dark") { return .dark }
        return arguments.contains("--proof-light") ? .light : nil
    }

    private var accountStatus: LocalizedStringKey {
        switch connection.accountState {
        case .connected: "Connected with plan permission"
        case .planPermissionMissing: "Signed in without plan permission"
        default: "Not connected"
        }
    }

    private var localSampleStatus: LocalizedStringKey {
        if connection.isStorageUnavailable { return "Local sample storage unavailable" }
        return connection.job == nil ? "No local sample saved" : "Synthetic sample saved on this iPhone"
    }

    private var inferenceStatus: LocalizedStringKey {
        switch connection.inferenceState {
        case .queued: "Queued"
        case .analyzing: "Analyzing"
        case .completed: "Completed"
        case .quotaReached: "Usage limit reached"
        case .needsRetry: "Analysis paused"
        default: connection.job == nil ? "No request sent" : "Waiting for authorized connection"
        }
    }

    private var callbackStatus: LocalizedStringKey {
        switch callbackProbe.state {
        case .idle: "Browser test not started"
        case .running: "Testing native browser"
        case .passed: "Native callback received"
        case .failed: "Browser test did not complete"
        case .cancelled: "Browser test cancelled"
        }
    }
}

private struct PresentationWindowReader: UIViewRepresentable {
    let foundWindow: @MainActor (UIWindow?) -> Void
    func makeUIView(context: Context) -> WindowView { WindowView(foundWindow: foundWindow) }
    func updateUIView(_ view: WindowView, context: Context) {}

    final class WindowView: UIView {
        private let foundWindow: @MainActor (UIWindow?) -> Void
        init(foundWindow: @escaping @MainActor (UIWindow?) -> Void) {
            self.foundWindow = foundWindow
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            Task { @MainActor [weak self] in
                guard let self else { return }
                foundWindow(window)
            }
        }
    }
}
