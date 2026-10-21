import SwiftUI
import Observation

@MainActor @Observable final class DiarySettingsRouteOwner {
    struct Route: Identifiable { let id = UUID(); let destination: CoachDestination? }
    var route: Route?
}

extension EnvironmentValues {
    @Entry var diarySettingsRoutes: DiarySettingsRouteOwner? = nil
    @Entry var diaryPhotoLimiter: PhotoWorkLimiter? = nil
}

/// First launch never asks for a diary name: with no diaries one is created and Pip's setup opens;
/// with diaries (or after signing out) you pick one or start another.
private struct DiarySetupView: View {
    @Bindable var model: DiaryViewModel
    let onSelected: () -> Void
    var onCreated: () -> Void = {}
    @State private var failed = false
    var body: some View {
        if model.profiles.isEmpty {
            Group {
                if failed {
                    ContentUnavailableView {
                        Label("Couldn't create your diary", systemImage: "exclamationmark.triangle")
                    } actions: {
                        Button("Try again") { Task { await startNew() } }.buttonStyle(.glassProminent).tint(.diaryAccent)
                    }
                } else {
                    ProgressView("Setting up your diary").task { await startNew() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.diaryCanvas)
        } else {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundStyle(Color.diaryAccent).accessibilityHidden(true)
                        Text("Welcome back").font(.largeTitle.bold())
                        Text("Choose a diary on this iPhone, or start a new one.").foregroundStyle(Color.diarySecondary)
                    }.padding(.vertical, 12)
                }
                Section("Your diaries") {
                    ForEach(model.profiles) { profile in
                        Button(profile.name) {
                            Task { await model.switchProfile(profile.id); if model.readModel?.profile.id == profile.id { onSelected() } }
                        }.disabled(model.isChangingProfile).frame(minHeight: 44)
                    }
                    Button("Start a new diary", systemImage: "plus") { Task { await startNew() } }
                        .disabled(model.isChangingProfile).frame(minHeight: 44).accessibilityIdentifier("startNewDiary")
                }
                Section("Have a backup?") {
                    DiaryBackupSettings(model: model)
                }
            }
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .navigationTitle("Mivu")
        }
    }
    private func startNew() async {
        failed = false
        await model.createProfile(name: model.profiles.isEmpty ? "My diary" : "Diary \(model.profiles.count + 1)")
        if model.readModel != nil { onSelected(); onCreated() } else { failed = true }
    }
}

struct DiaryRootView: View {
    @State private var model: DiaryViewModel
    @State private var connection: ChatGPTConnection
    @State private var coach: CoachViewModel
    @State private var selectedTab: String
    private typealias SettingsRoute = DiarySettingsRouteOwner.Route
    @State private var routes = DiarySettingsRouteOwner()
    @State private var coachRoutes = CoachNavigationOwner()
    @State private var coachHistory: CoachHistoryPresentation?
    @State private var hasLoaded = false
    @State private var showOnboarding = false
    @State private var quickLog = QuickLogRequest.shared
    @State private var quickLogOwner: DiarySelectionOwnership?
    @State private var loggedMealID: UUID?
    @State private var noteMealID: UUID?
    @State private var mealNotifications = MealNotification.shared
    @State private var notifiedMealID: UUID?
    @State private var companion = CompanionPresentation()
    @State private var companionRuntime: CompanionRuntime
    #if DEBUG
    @State private var poseTrail = ""
    #endif
    @State private var lastActive = CompanionLastActive(defaults: DiaryLaunch.defaults)
    @State private var companionSelection: CompanionSelection
    @State private var companionContext = CompanionContext(surface: nil, isTyping: false, isProcessing: false, needsRecovery: false, playback: .hidden)
    @State private var companionOutput = CompanionOutput(pose: .resting, playback: .hidden, reactionID: nil, nextDeadline: nil)
    #if DEBUG
    private var observeCompanionOutput: ((CompanionOutput) -> Void)?
    private var observeCompanionApplication: ((CompanionOutput) -> Void)?
    #endif
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermalState = ProcessInfo.processInfo.thermalState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("diarySelectedTab") private var restoredTab = "today"
    private let nutritionKeys: NutritionAPIKeyStore
    init() {
        let diary = DiaryViewModel.local(), session = ChatGPTConnection(preferences: DiaryLaunch.defaults)
        let keys = NutritionAPIKeyStore.local
        nutritionKeys = keys
        let foodSource = FoodEvidenceClient()
        let fixture: (() throws -> CoachViewModel.Inference)? = DiaryLaunch.isCoachInferenceFixture
            ? { { input, tools in try await CoachUITestInference.respond(input, tools) } } : nil
        var catalog = CharacterCatalog.bundled
        #if DEBUG
        if DiaryLaunch.isUITest && ProcessInfo.processInfo.arguments.contains("--companion-two-fixtures") {
            // Test-only alias validates switching with the production rig; never a shipping character.
            let pip = catalog.resolve("pip")
            catalog = CharacterCatalog(characters: [pip, CharacterDescriptor(
                id: "pip-test-alias", displayName: "Pip test fixture", schemaVersion: pip.schemaVersion,
                animationResourcePath: pip.animationResourcePath, fallbackAssetPrefix: pip.fallbackAssetPrefix,
                previewAssetName: pip.previewAssetName)])
        }
        if DiaryLaunch.isUITest && ProcessInfo.processInfo.arguments.contains("--companion-unknown-selection") {
            DiaryLaunch.defaults.set("unavailable-test-character", forKey: "selectedCharacterID")
        }
        if DiaryLaunch.isUITest && ProcessInfo.processInfo.arguments.contains("--companion-load-failure") {
            _companionRuntime = State(initialValue: CompanionRuntime(load: { _ in throw CocoaError(.fileReadCorruptFile) }))
        } else {
            _companionRuntime = State(initialValue: CompanionRuntime())
        }
        #else
        _companionRuntime = State(initialValue: CompanionRuntime())
        #endif
        _companionSelection = State(initialValue: CompanionSelection(catalog: catalog, defaults: DiaryLaunch.defaults))
        _model = State(initialValue: diary)
        _connection = State(initialValue: session)
        _coach = State(initialValue: CoachViewModel(diary: diary, connection: session, inference: fixture, lookup: { query in
            try await foodSource.search(query: query, apiKey: keys.load())
        }))
        let startToday = DiaryLaunch.isUITest && ProcessInfo.processInfo.arguments.contains("--coach-navigation-start-today")
        _selectedTab = State(initialValue: DiaryLaunch.isUITest && !DiaryLaunch.isSampleMode && !startToday ? "coach" : "today")
    }
    #if DEBUG
    // Hosted integration tests exercise the actual root task with an intentionally delayed asset.
    init(testDiary: DiaryViewModel, testCoach: CoachViewModel, testRuntime: CompanionRuntime, testTab: String, testDefaults: UserDefaults,
         observeCompanionApplication: ((CompanionOutput) -> Void)? = nil,
         observeCompanionOutput: @escaping (CompanionOutput) -> Void) {
        self.init()
        _model = State(initialValue: testDiary)
        _coach = State(initialValue: testCoach)
        _connection = State(initialValue: testCoach.connection)
        _companionRuntime = State(initialValue: testRuntime)
        _selectedTab = State(initialValue: testTab)
        _restoredTab = AppStorage(wrappedValue: testTab, "diarySelectedTab", store: testDefaults)
        _companionSelection = State(initialValue: CompanionSelection(catalog: .bundled, defaults: testDefaults))
        _lastActive = State(initialValue: CompanionLastActive(defaults: testDefaults))
        self.observeCompanionOutput = observeCompanionOutput
        self.observeCompanionApplication = observeCompanionApplication
    }
    #endif
    @Environment(\.scenePhase) private var phase
    @State private var backgroundLease: UIBackgroundTaskIdentifier = .invalid
    var body: some View {
        lifecycleView
        .alert("Could not complete action", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(LocalizedStringKey(model.errorMessage ?? "")) }
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--proof-dark") ? .dark : ProcessInfo.processInfo.arguments.contains("--proof-light") ? .light : nil)
        .transformEnvironment(\.dynamicTypeSize) {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--proof-largest-text") { $0 = .accessibility5 }
            else if arguments.contains("--proof-large-text") { $0 = .accessibility3 }
        }
    }
    private var lifecycleView: some View {
        companionView
        .task {
            if !DiaryLaunch.isUITest, ["today", "diary", "progress", "coach"].contains(restoredTab) { selectedTab = restoredTab }
            model.resumeCoach = { coach.resume() }
            model.retryCoachMeal = { id in
                Task { await coach.retryMeal(id) }
            }
            await model.load(createDefaultProfile: (DiaryLaunch.isUITest || DiaryLaunch.isSampleMode) && !ProcessInfo.processInfo.arguments.contains("--onboarding-ui-test"))
            hasLoaded = true
            if DiaryLaunch.rollsOverDays { await model.rollOverDay() }
            resetCompanionProfile()
            if !DiaryLaunch.isUITest { await connection.restore() }
            coach.startMonitoring(); coach.resume()
        }
        .task(id: "\(model.activeDay?.id.uuidString ?? "")\(model.changeGeneration)") { await model.loadMorningRecap() }
        .onChange(of: model.readModel, initial: true) { _, readModel in publishWidgetSnapshot(readModel) }
        .onChange(of: quickLog.pending, initial: true) { _, _ in openQuickLog() }
        .onChange(of: quickLog.openCoach, initial: true) { _, _ in openCoachRequest() }
        .onOpenURL { if $0.host == "today" { selectedTab = "today" } }
        .onChange(of: hasLoaded) { _, _ in openQuickLog(); openCoachRequest(); openNotifiedMeal() }
        .onChange(of: mealNotifications.openedMealID, initial: true) { _, _ in openNotifiedMeal() }
        .onChange(of: model.isChangingProfile) { _, changing in
            coachRoutes.synchronize(selection: model.selection, isChangingProfile: changing)
            if changing { coachHistory = nil }
            if changing { coach.cancel(); companionRuntime.stop(); companion.enterBackground(); refreshCompanion() }
            else { resetCompanionProfile(); Task { await coach.waitForWorker(); coach.resume() } }
        }
        .onChange(of: model.readModel?.profile.id) { _, _ in
            coach.draft = MealDraft(); coach.errorMessage = nil
            resetCompanionProfile()
        }
        .onChange(of: connection.sessionRevision) { _, _ in coach.cancel() }
        .onChange(of: connection.planAuthorized) { _, authorized in if authorized { coach.resume() } }
        .onChange(of: connection.selectedModel) { _, _ in coach.cancel(); Task { await coach.waitForWorker(); coach.resume() } }
        .onChange(of: phase) { _, value in
            if value != .active {
                companionRuntime.stop()
                if value == .background {
                    if let id = model.readModel?.profile.id { lastActive.record(Date(), for: id) }
                    companion.enterBackground()
                }
                refreshCompanion()
            }
            if value == .inactive { coach.pauseForInactiveScene() }
            if value == .background { continueInBackground() }
            if value == .active {
                attachCompanion()
                refreshCompanion()
            }
            if value == .active, hasLoaded, DiaryLaunch.rollsOverDays { Task { await model.rollOverDay() } }
            if value == .active { endBackgroundLease(); Task { await connection.enterForeground(); await coach.waitForWorker(); coach.enterForeground() }; model.resumeWorker(allowProcessing: true); model.queueBackup() }
        }
    }
    private var companionView: some View {
        routedContent
        .onChange(of: selectedTab) { _, value in
            if !DiaryLaunch.isUITest { restoredTab = value }
            refreshCompanion()
        }
        .onChange(of: [routes.route != nil, coachHistory != nil, showOnboarding, model.errorMessage != nil, model.isChangingProfile, hasLoaded, reduceMotion, lowPower]) { _, _ in refreshCompanion() }
        .onChange(of: model.selection, initial: true) { _, selection in
            coachRoutes.synchronize(selection: selection, isChangingProfile: model.isChangingProfile)
            coachHistory = nil
            if selection != quickLogOwner { quickLogOwner = nil }
        }
        .onChange(of: model.restoreGeneration) { _, _ in coachRoutes.invalidate(); coachHistory = nil }
        .onChange(of: thermalState) { _, _ in refreshCompanion() }
        .onChange(of: companionSelection.selectedCharacterID) { _, _ in
            companionRuntime.stop()
            companion.characterChanged(now: Date())
            refreshCompanion()
        }
        .onChange(of: model.companionCaptureEvent) { _, event in receiveCompanionEvent(event) }
        .onChange(of: model.companionHabitEvent) { _, event in receiveCompanionEvent(event) }
        .onChange(of: model.companionReviewEvent) { _, event in receiveCompanionEvent(event) }
        .onChange(of: coach.companionSubmission) { _, _ in receiveCompanionSubmission() }
        .onChange(of: coach.companionCaptureEvent) { _, event in receiveCompanionEvent(event) }
        .onChange(of: coach.companionPhotoEvent) { _, event in receiveCompanionEvent(event) }
        .onChange(of: [coach.isSending, coach.companionNeedsRecovery, coach.companionIsProcessing]) { _, _ in refreshCompanion() }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            thermalState = ProcessInfo.processInfo.thermalState
        }
        .task(id: runtimeUpdate) {
            guard hasLoaded else { return }
            let update = runtimeUpdate
            if companionRuntime.character.id != companionSelection.selectedCharacterID {
                await companionRuntime.attach(eligible: false)
            }
            await companionRuntime.select(companionSelection.selectedCharacter)
            guard !Task.isCancelled, update == runtimeUpdate else { return }
            await companionRuntime.attach(eligible: companionOutput.playback != .hidden)
            guard !Task.isCancelled, update == runtimeUpdate else { return }
            await companionRuntime.apply(companionOutput, darkMode: colorScheme == .dark, surface: selectedCompanionSurface ?? .today)
            #if DEBUG
            observeCompanionApplication?(companionOutput)
            #endif
        }
        .task(id: companionOutput.nextDeadline) {
            guard let deadline = companionOutput.nextDeadline else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                try Task.checkCancellation()
                guard companionOutput.nextDeadline == deadline else { return }
                refreshCompanion()
            } catch {}
        }
    }
    private var routedContent: some View {
        rootContent
        .tint(.diaryAccent)
        #if DEBUG
        .overlay(alignment: .topLeading) {
            // UI tests cannot see Pip (accessibility-hidden), so the applied pose is mirrored here.
            if DiaryLaunch.isUITest {
                Text("pose:\(String(describing: companionOutput.pose))").font(.system(size: 1)).opacity(0.01)
                    .allowsHitTesting(false).accessibilityIdentifier("companionDebugPose")
                    .accessibilityValue(poseTrail)
            }
        }
        #endif
        .foregroundStyle(Color.diaryText)
        .environment(\.diarySettingsRoutes, routes)
        .environment(\.diaryPhotoLimiter, model.photoWorkLimiter)
        .environment(\.openDiaryCoach, openCoachAction)
        .environment(connection)
        .sensoryFeedback(.success, trigger: model.captureReceipt)
        .sheet(item: $routes.route) { route in
            NavigationStack {
                SettingsView(model: model, connection: connection, nutritionKeys: nutritionKeys, destination: route.destination, companionSelection: $companionSelection)
            }
            .tint(.diaryAccent)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(model: model, connection: connection) { showOnboarding = false }
        }
        .fullScreenCover(isPresented: Binding(get: { quickLogOwner != nil }, set: { if !$0 { quickLogOwner = nil } })) {
            if let owner = quickLogOwner {
                QuickLogCameraView(model: model, ownership: owner) { id in
                    quickLogOwner = nil; selectedTab = "today"
                    withAnimation { loggedMealID = id }
                    AccessibilityNotification.Announcement("Meal logged").post()
                    Task { await MealNotification.requestPermissionIfNeeded() }
                }
            }
        }
        .sheet(isPresented: Binding(get: { noteMealID != nil }, set: { if !$0 { noteMealID = nil } })) {
            if let id = noteMealID { MealComposerView(model: model, correctingMealID: id) }
        }
        .sheet(isPresented: Binding(get: { notifiedMealID != nil }, set: { if !$0 { notifiedMealID = nil } })) {
            if let id = notifiedMealID {
                NavigationStack {
                    MealDetailView(model: model, mealID: id).toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { notifiedMealID = nil } }
                    }
                }
            }
        }
        .sheet(item: $coachHistory) { presentation in
            CoachHistoryView(model: model, routes: coachRoutes, presentation: presentation,
                             open: coachAction(from: presentation.origin))
        }
    }
    private var rootContent: some View {
        Group {
            if !hasLoaded {
                ProgressView("Opening diary").frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.diaryCanvas)
            } else if model.readModel == nil {
                NavigationStack { DiarySetupView(model: model, onSelected: { selectedTab = "today" }, onCreated: { showOnboarding = true }) }
            } else {
                rootTabs
            }
        }
    }
    private var rootTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "fork.knife", value: "today") {
                NavigationStack {
                    TodayView(model: model, companionOutput: output(for: .today), companionRuntime: companionRuntime,
                              onCompanionContextChanged: updateCompanionContext,
                              onCompanionTouch: touchCompanion).toolbar { profileControl }
                }
                .overlay(alignment: .bottom) { if let id = loggedMealID { quickLogToast(id) } }
                .task(id: loggedMealID) {
                    guard loggedMealID != nil else { return }
                    try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 10 : 5))
                    if !Task.isCancelled { withAnimation { loggedMealID = nil } }
                }
            }
            Tab("Diary", systemImage: "text.document", value: "diary") {
                NavigationStack { HistoryView(model: model).toolbar { profileControl } }
            }
            Tab("Progress", systemImage: "chart.bar.fill", value: "progress") {
                NavigationStack { DiaryProgressView(model: model, openDiary: { selectedTab = "diary" }).toolbar { profileControl } }
            }
            Tab("Coach", systemImage: "bubble.left.fill", value: "coach") {
                NavigationStack {
                    CoachView(coach: coach, companionOutput: output(for: .coach), companionRuntime: companionRuntime,
                              onCompanionContextChanged: updateCompanionContext,
                              onCompanionTouch: touchCompanion,
                              navigationRequest: coachRoutes.request,
                              onNavigationConsumed: { coachRoutes.consume($0) },
                              openHistory: openCoachHistory) { destination in
                        routes.route = SettingsRoute(destination: destination)
                    }.toolbar { profileControl }
                }
            }
        }
    }
    private func openQuickLog() {
        guard quickLog.pending, hasLoaded else { return }
        quickLog.pending = false
        // Without a diary there is nowhere to save; the app shows setup instead.
        guard let owner = model.selection, model.readModel != nil, !showOnboarding, !model.isChangingProfile else { return }
        // shortcut: sheets presented inside a tab (composer, Coach camera) stay up and block this cover; dismiss them if that shows up in use.
        routes.route = nil; coachHistory = nil; noteMealID = nil
        selectedTab = "today"; quickLogOwner = owner
    }
    private func openCoachRequest() {
        guard quickLog.openCoach, hasLoaded else { return }
        quickLog.openCoach = false
        guard model.selection != nil, model.readModel != nil, !showOnboarding, !model.isChangingProfile else { return }
        routes.route = nil; coachHistory = nil; noteMealID = nil
        selectedTab = "coach"
    }
    private func openNotifiedMeal() {
        guard let id = mealNotifications.openedMealID, hasLoaded else { return }
        mealNotifications.openedMealID = nil
        guard model.readModel != nil, !showOnboarding, !model.isChangingProfile, quickLogOwner == nil else { return }
        routes.route = nil; coachHistory = nil; noteMealID = nil
        selectedTab = "today"; notifiedMealID = id
    }
    private func quickLogToast(_ id: UUID) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.diaryAccent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Meal logged").font(.subheadline.weight(.semibold)).foregroundStyle(Color.diaryText)
                Text(connection.planAuthorized ? "Analyzing your photo" : "Analyzes when ChatGPT is connected")
                    .font(.caption).foregroundStyle(Color.diarySecondary)
            }
            Spacer(minLength: 8)
            Button { loggedMealID = nil; noteMealID = id } label: {
                Text("Add Note").font(.subheadline.weight(.semibold)).foregroundStyle(Color.diaryAccent)
                    .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
            }.accessibilityIdentifier("quickLogAddNote")
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 6)
        // Solid, not glass: the toast sits over busy meal rows and must stay readable.
        .background(Color.diarySurface, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.diaryRule))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 16).padding(.bottom, 8)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quickLogToast")
    }
    private var openCoachAction: OpenDiaryCoachAction {
        coachAction(from: coachRoutes.origin(selection: model.selection, isChangingProfile: model.isChangingProfile))
    }
    private func coachAction(from origin: CoachNavigationOrigin?) -> OpenDiaryCoachAction {
        OpenDiaryCoachAction(origin: origin) { target, draft, captured in
            guard coachRoutes.queue(target, draft: draft, from: captured, selection: model.selection,
                                    isChangingProfile: model.isChangingProfile) else { return false }
            selectedTab = "coach"
            return true
        }
    }
    private func openCoachHistory() {
        guard let origin = coachRoutes.origin(selection: model.selection, isChangingProfile: model.isChangingProfile) else { return }
        coachHistory = CoachHistoryPresentation(origin: origin, timeZoneID: model.readModel?.profile.timeZoneID ?? TimeZone.current.identifier)
    }
    private var companionEvents: [CompanionEvent] {
        [model.companionCaptureEvent, model.companionHabitEvent, model.companionReviewEvent, coach.companionCaptureEvent, coach.companionPhotoEvent].compactMap { $0 }
    }
    private var companionSubmissions: [CompanionSubmission] { [coach.companionSubmission].compactMap { $0 } }
    private var selectedCompanionSurface: CompanionSurface? {
        selectedTab == "today" ? .today : selectedTab == "coach" ? .coach : nil
    }
    private func output(for surface: CompanionSurface) -> CompanionOutput {
        guard selectedCompanionSurface == surface, companionContext.surface == surface else {
            return CompanionOutput(pose: .resting, playback: .hidden, reactionID: nil, nextDeadline: nil)
        }
        return companionOutput
    }
    private func updateCompanionContext(_ context: CompanionContext) {
        guard let surface = context.surface, surface == selectedCompanionSurface else { return }
        companionContext = context
        refreshCompanion()
    }
    private func resetCompanionProfile() {
        companionRuntime.stop()
        companion.enterBackground()
        attachCompanion()
        refreshCompanion()
    }
    private func attachCompanion() {
        let profileID = model.isChangingProfile ? nil : model.readModel?.profile.id
        lastActive.attach(companion, profileID: profileID, existingEvents: companionEvents,
                          existingSubmissions: companionSubmissions, now: Date())
    }
    private func touchCompanion(_ touch: CompanionTouch) {
        if !companion.touch(touch, now: Date()) { companionRuntime.earTwitch() }
        refreshCompanion()
    }
    private func receiveCompanionEvent(_ event: CompanionEvent?) {
        guard phase == .active, !model.isChangingProfile, let event, event.profileID == model.readModel?.profile.id else { return }
        // Observation may coalesce a fast write; acceptance must reach the presenter first.
        receiveCompanionSubmission()
        companion.receive(event, now: Date())
        refreshCompanion()
    }
    private func receiveCompanionSubmission() {
        guard phase == .active, !model.isChangingProfile, let submission = coach.companionSubmission,
              submission.profileID == model.readModel?.profile.id else { return }
        guard companion.receive(submission, now: Date()) else { return }
        if companionContext.surface == .coach, coach.isSending || !coach.draft.isValid {
            companionContext.isTyping = false
        }
        refreshCompanion()
    }
    private func refreshCompanion() {
        var context = companionContext
        if context.surface == .coach {
            context.needsRecovery = coach.companionNeedsRecovery
            context.isProcessing = coach.companionIsProcessing
            if coach.isSending { context.isTyping = false }
        }
        context.playback = MotionPolicy.playback(
            reduceMotion: reduceMotion, lowPower: lowPower, thermalState: thermalState,
            sceneActive: phase == .active && hasLoaded && model.readModel != nil && !model.isChangingProfile,
            selected: context.surface != nil && context.surface == selectedCompanionSurface,
            visible: context.playback != .hidden, covered: routes.route != nil || coachHistory != nil || showOnboarding || model.errorMessage != nil)
        let output = companion.resolve(context: context, now: Date())
        if companionOutput.playback == .animated && output.playback != .animated { companionRuntime.stop() }
        #if DEBUG
        if DiaryLaunch.isUITest, output.pose != companionOutput.pose || poseTrail.isEmpty { poseTrail += "[\(String(describing: output.pose))]" }
        #endif
        companionOutput = output
        #if DEBUG
        observeCompanionOutput?(output)
        #endif
    }
    /// What `.task(id:)` watches: any change here re-applies the output to the runtime.
    struct RuntimeUpdate: Hashable {
        let surface: CompanionSurface?
        let characterID: String
        let pose: Int
        let animated: Bool
        let reactionID: UUID?
        /// The draft grows while the pose stays attentive; the eyes follow it.
        let typing: Double
        let darkMode: Bool
        let loaded: Bool
        // Loading can outlive its requesting task; readiness reconciles the latest output.
        let ready: Bool

        init(output: CompanionOutput, surface: CompanionSurface?, characterID: String, darkMode: Bool, loaded: Bool, ready: Bool) {
            self.surface = surface; self.characterID = characterID; pose = output.pose.rawValue
            animated = output.playback == .animated; reactionID = output.reactionID; typing = output.typingProgress
            self.darkMode = darkMode; self.loaded = loaded; self.ready = ready
        }
    }
    private var runtimeUpdate: RuntimeUpdate {
        RuntimeUpdate(output: companionOutput, surface: selectedCompanionSurface, characterID: companionSelection.selectedCharacterID,
                      darkMode: colorScheme == .dark, loaded: hasLoaded, ready: companionRuntime.isReady)
    }
    private var profileControl: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { routes.route = SettingsRoute(destination: nil) } label: {
                Image(systemName: "person.crop.circle").font(.title3).frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Profile and settings")
            .accessibilityIdentifier("profileSettings")
        }
    }
    private func continueInBackground() {
        coach.continueInBackground(begin: { expire in
            backgroundLease = UIApplication.shared.beginBackgroundTask(withName: "Finish saved meal") {
                expire() // handler runs on the main actor and must end the task before returning
            }
            return backgroundLease != .invalid
        }, end: {
            guard backgroundLease != .invalid else { return }
            let lease = backgroundLease; backgroundLease = .invalid
            UIApplication.shared.endBackgroundTask(lease)
        })
    }
    private func endBackgroundLease() { coach.endBackgroundLease() }

}

struct TodayView: View {
    @Bindable var model: DiaryViewModel
    let companionOutput: CompanionOutput
    let companionRuntime: CompanionRuntime
    let onCompanionContextChanged: (CompanionContext) -> Void
    var onCompanionTouch: (CompanionTouch) -> Void = { _ in }
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var companionVisible = false
    @State private var surfaceVisible = false
    @State private var showingDetail = false
    @State private var showComposer = false
    @State private var showWeight = false
    @State private var showGoals = false
    @State private var savedMealID: UUID?
    @AppStorage("morningCardDismissedDay") private var dismissedMorningDay = ""
    var body: some View {
        List {
            if model.sampleMode { Section { SampleBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) } }
            if let snapshot = model.readModel {
                if let savedMealID, let meal = model.meal(savedMealID) {
                    Section {
                        let lateDay = lateMealDay(meal)
                        NavigationLink(value: savedMealID) {
                            Label(lateDay.map { "Added to \(wakingDayTitle($0.localDate))" } ?? "Saved on this iPhone", systemImage: "checkmark.circle")
                                .font(.subheadline).foregroundStyle(Color.diarySuccess).frame(minHeight: 44)
                        }.accessibilityIdentifier("savedMealReceipt")
                        // Moving opens today's calendar date, so offer it only while that is still the meal's date.
                        if lateDay != nil, diaryDateLabel(meal.capturedAt, zone: snapshot.profile.timeZoneID) == diaryDateLabel(Date(), zone: snapshot.profile.timeZoneID) {
                            Button("Move to \(wakingDayTitle(diaryDateLabel(meal.capturedAt, zone: snapshot.profile.timeZoneID)))", systemImage: "arrow.uturn.forward") {
                                Task { await moveToCalendarDay(meal) }
                            }.font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("moveLateMeal")
                        }
                    }
                }
                if let day = model.activeDay, let recap = model.morningRecap, model.todaysMeals.isEmpty, dismissedMorningDay != day.id.uuidString {
                    Section {
                        MorningCheckInCard(model: model, day: day, previous: recap.previous, previousTarget: recap.target, todayWeight: snapshot.weight) {
                            withAnimation(.snappy) { dismissedMorningDay = day.id.uuidString }
                        }
                    }.transition(.opacity)
                }
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        summaryDate
                        if let day = model.activeDay {
                            intakeHero(totals: snapshot.totals, day: day)
                            if snapshot.activeGoal != nil {
                                todayGoal(snapshot: snapshot, day: day, showCompleteness: typeSize.isAccessibilitySize)
                            }
                        } else {
                            intakeHero(totals: nutritionTotals([]), day: nil)
                        }
                        if snapshot.pendingCount > 0 {
                            Label("\(snapshot.pendingCount) pending", systemImage: "clock")
                                .font(.subheadline).foregroundStyle(Color.diaryWarning)
                                .accessibilityIdentifier("pendingCount")
                        }
                    }.diarySummaryCard()
                }
                Section {
                    if model.todaysMeals.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Your first meal starts here", systemImage: "fork.knife").font(.headline)
                            Text("Add photos or a note.").foregroundStyle(Color.diarySecondary)
                        }.diarySummaryCard()
                    }
                    ForEach(model.todaysMeals, id: \.id) { meal in
                        NavigationLink(value: meal.id) { MealRow(meal: meal, prominent: true, model: model) }
                            .diarySummaryCard()
                            .accessibilityIdentifier("mealRow")
                    }
                } header: { Text("Meals").font(.title3.weight(.bold)).foregroundStyle(Color.diaryText).textCase(nil) }
                if let day = model.activeDay, snapshot.activeGoal == nil {
                    Section { todayGoal(snapshot: snapshot, day: day, showCompleteness: false).diarySummaryCard() }
                }
                Section {
                    Button { showWeight = true } label: {
                        HStack {
                            Label { Text("Morning weight") } icon: { Image(systemName: "scalemass").foregroundStyle(Color.diaryWeight) }
                            Spacer()
                            if let entry = snapshot.weight {
                                Text("\(entry.value.formatted(.number.precision(.fractionLength(1)))) \(entry.unit)").monospacedDigit()
                            } else { Text("Log weight").foregroundStyle(Color.diarySecondary) }
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("logWeight").diarySummaryCard()
                }
                if let day = model.activeDay {
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Day coverage").font(.title3.weight(.bold))
                            Picker("Completeness", selection: Binding(get: { day.completeness }, set: { value in
                                Task { await model.change { try await model.store.setCompleteness(dayID: day.id, value, expectedProfileID: snapshot.profile.id) } }
                            })) { ForEach(DayCompleteness.allCases, id: \.self) { Text($0.title).tag($0) } }
                            Text("Complete means all intake was recorded. Partial totals describe only recorded meals.").font(.caption).foregroundStyle(Color.diarySecondary)
                        }.diarySummaryCard()
                    }
                }
            } else {
                Section { Text("Choose a private local profile in Settings to open your diary.").foregroundStyle(Color.diarySecondary) }
            }
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .listSectionSpacing(12)
        .contentMargins(.top, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 56)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .safeAreaInset(edge: .bottom) {
            if model.readModel != nil {
                DiaryCaptureAction { showComposer = true }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.diaryCanvas)
            }
        }
        .navigationDestination(for: UUID.self) {
            MealDetailView(model: model, mealID: $0)
                .onAppear { showingDetail = true; reportCompanionContext() }
                .onDisappear { showingDetail = false; reportCompanionContext() }
        }
        .navigationTitle("Today")
        .toolbarTitleDisplayMode(.inlineLarge)
        .sheet(isPresented: $showComposer) { MealComposerView(model: model, onSaved: { savedMealID = $0 }) }
        .task(id: "\(model.activeDay?.id.uuidString ?? "")\(model.changeGeneration)") {
            // Coach may move the saved meal to the night before; keep its receipt readable once it leaves today.
            if let savedMealID, model.readModel?.meals.contains(where: { $0.id == savedMealID }) == false { await model.loadMeal(savedMealID) }
        }
        .onChange(of: model.readModel?.profile.id) { _, _ in savedMealID = nil }
        .sheet(isPresented: $showWeight) { MorningWeightEditorView(model: model) }
        .sheet(isPresented: $showGoals) { GoalEditorView(model: model) }
        .onAppear { surfaceVisible = true; reportCompanionContext() }
        .onDisappear { surfaceVisible = false; reportCompanionContext() }
        .onChange(of: [companionVisible, showComposer, showWeight, showGoals, showingDetail]) { _, _ in reportCompanionContext() }
    }

    /// A meal logged after midnight that counts for the waking day before: before the cutoff, or because Coach judged it late-night food.
    private func lateMealDay(_ meal: MealReadModel) -> TrackingDay? {
        guard let day = model.day(meal.dayID), day.localDate < diaryDateLabel(meal.capturedAt, zone: day.timeZoneID) else { return nil }
        return day
    }
    private func moveToCalendarDay(_ meal: MealReadModel) async {
        guard let owner = model.readModel?.profile.id else { return }
        await model.change {
            // Starting before the cutoff opens the calendar date, because the waking day is already active.
            let day = try await model.store.startDay(at: Date(), expectedProfileID: owner)
            try await model.store.moveMeal(meal.id, to: day.id, expectedRevision: meal.revision, expectedDayID: meal.dayID, expectedProfileID: owner)
        }
    }
    private var covered: Bool { showComposer || showWeight || showGoals || showingDetail }
    private func reportCompanionContext() {
        // Foreground capture is covered by its sheet. Background persistence is not a character action.
        onCompanionContextChanged(CompanionContext(surface: .today, isTyping: false,
            isProcessing: false, needsRecovery: false,
            playback: surfaceVisible && companionVisible && !covered ? .animated : .hidden))
    }
    private var summaryDate: some View {
        Menu {
            // No confirmation: a repeated start reuses the open day, and meals can be moved back.
            Button("Start new day", systemImage: "sunrise") {
                guard let owner = model.readModel?.profile.id else { return }
                Task { await model.change { _ = try await model.store.startDay(expectedProfileID: owner) } }
            }.accessibilityIdentifier("startNewDay")
        } label: {
            HStack(spacing: 6) {
                Text(displayDate).font(.subheadline)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }.foregroundStyle(Color.diarySecondary).frame(minHeight: 44)
        }.accessibilityLabel("Day actions, " + displayDate).accessibilityIdentifier("todayDayActions")
    }
    private var displayDate: String {
        guard let value = model.activeDay?.localDate else { return "Your waking day" }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return value }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
    private var companionArt: some View {
        // 186 keeps the hero's old height; taller pushes the first meal row under the floating Log meal bar.
        CompanionView(presentation: companionOutput, darkMode: colorScheme == .dark,
                      size: typeSize.isAccessibilitySize ? 144 : 186, runtime: companionRuntime, onTouch: onCompanionTouch)
            .onScrollVisibilityChange(threshold: 0.5) { visible in
                companionVisible = visible; reportCompanionContext()
            }
    }
    @ViewBuilder private func intakeHero(totals: NutritionTotals, day: TrackingDay?) -> some View {
        if typeSize.isAccessibilitySize {
            companionArt
            NutritionSummary(totals: totals)
        } else {
            HStack(alignment: .center, spacing: 8) {
                companionArt
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(totals.kcal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                            .font(.system(size: 52, weight: .bold)).tracking(-2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                            .foregroundStyle(Color.diaryText)
                            .contentTransition(.numericText())
                            .animation(companionOutput.playback == .animated ? .snappy(duration: MivuMotion.numeric) : nil, value: totals.kcal)
                        Text("kcal recorded").font(.subheadline).foregroundStyle(Color.diaryText)
                    }
                    Group {
                        if let day { Text("\(Text(day.completeness.title)) day") }
                        else { Text("No meals recorded") }
                    }.font(.caption).foregroundStyle(Color.diarySecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                heroMetric("Protein", value: totals.protein, color: .diaryProtein)
                Divider().frame(height: 32)
                heroMetric("Carbs", value: totals.carbs, color: .diaryCarbs)
                Divider().frame(height: 32)
                heroMetric("Fat", value: totals.fat, color: .diaryFat)
            }
            if totals.unknownItemCount > 0 {
                Text("Some nutrients are unknown. Recorded totals may be incomplete.")
                    .font(.caption).foregroundStyle(Color.diarySecondary)
            }
        }
    }
    private func heroMetric(_ title: LocalizedStringKey, value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(title).font(.caption).fixedSize(horizontal: true, vertical: false)
            }
            Text(value.map { $0.formatted(.number.precision(.fractionLength(0))) + " g" } ?? "—")
                .font(.system(size: 17, weight: .medium)).monospacedDigit()
        }.foregroundStyle(Color.diaryText).frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func todayGoal(snapshot: DiaryReadModel, day: TrackingDay, showCompleteness: Bool = true) -> some View {
        let report = ProgressAnalytics.daily(readModel: snapshot)
        if let target = report.goal?.targets.kcal {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("\(target.formatted(.number.precision(.fractionLength(0)))) kcal goal")
                        Spacer(minLength: 12)
                        remaining(report.remainingFromRecorded.kcal)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(target.formatted(.number.precision(.fractionLength(0)))) kcal goal")
                        remaining(report.remainingFromRecorded.kcal)
                    }
                }.font(.subheadline).monospacedDigit()
                if let recorded = report.foodTotals?.kcal, target > 0 {
                    ProgressView(value: min(recorded / target, 1))
                        .accessibilityLabel("Recorded intake toward your goal")
                        .accessibilityValue("\(recorded.formatted(.number.precision(.fractionLength(0)))) of \(target.formatted(.number.precision(.fractionLength(0)))) kilocalories")
                }
                if report.goal?.exerciseCreditEnabled == true, let adjusted = report.exerciseAdjustedKcalRemaining {
                    Text("Exercise-adjusted remaining: \(adjusted.formatted(.number.precision(.fractionLength(0)))) kcal")
                        .font(.caption).foregroundStyle(Color.diarySecondary)
                }
            }.accessibilityIdentifier("todayGoalSummary")
        } else {
            Button { showGoals = true } label: {
                Label(report.goal == nil ? "Set a goal" : "Edit goals", systemImage: "target").font(.subheadline).frame(minHeight: 44)
            }.accessibilityIdentifier("todayGoalSummary")
        }
        if showCompleteness { HStack {
            Image(systemName: day.completeness == .complete ? "checkmark.circle" : "circle.lefthalf.filled")
            Text(day.completeness.title)
            Text("day")
        }.font(.caption).foregroundStyle(Color.diarySecondary) }
    }

    @ViewBuilder private func remaining(_ value: Double?) -> some View {
        if let value {
            Text("\(abs(value).formatted(.number.precision(.fractionLength(0)))) \(value < 0 ? "above goal" : "to goal")")
        } else { Text("Not estimated yet").foregroundStyle(Color.diarySecondary) }
    }
}
