import SwiftUI
import Observation

@MainActor @Observable final class DiarySettingsRouteOwner {
    struct Route: Identifiable { let id = UUID(); let destination: CoachDestination? }
    var route: Route?
    func openConnection() { route = Route(destination: .connection) }
}

extension EnvironmentValues {
    @Entry var diarySettingsRoutes: DiarySettingsRouteOwner? = nil
    @Entry var diaryPhotoLimiter: PhotoWorkLimiter? = nil
}

private struct DiarySetupView: View {
    @Bindable var model: DiaryViewModel
    let onSelected: () -> Void
    @State private var name = ""
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundStyle(Color.diaryAccent).accessibilityHidden(true)
                    Text("A clearer record of your day.").font(.largeTitle.bold())
                    Text("Log meals, review estimates, and follow your progress. Your diary stays on this iPhone. Keep a backup before changing phones.")
                        .foregroundStyle(Color.diarySecondary)
                }.padding(.vertical, 12)
            }
            Section("Create your diary") {
                TextField("Profile name", text: $name).textContentType(.nickname)
                    .accessibilityIdentifier("newDiaryName")
                Button("Create diary") {
                    Task {
                        await model.createProfile(name: trimmedName)
                        if model.readModel != nil { onSelected() }
                    }
                }.disabled(trimmedName.isEmpty || model.isChangingProfile)
                    .frame(minHeight: 44).accessibilityIdentifier("createDiary")
            }
            if !model.profiles.isEmpty {
                Section("Your local diaries") {
                    ForEach(model.profiles) { profile in
                        Button(profile.name) {
                            Task { await model.switchProfile(profile.id); if model.readModel?.profile.id == profile.id { onSelected() } }
                        }.disabled(model.isChangingProfile).frame(minHeight: 44)
                    }
                }
            }
            Section("Have a backup?") {
                DiaryBackupSettings(model: model)
            }
        }
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("Mivu")
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
    @State private var companion = CompanionPresentation()
    @State private var companionRuntime: CompanionRuntime
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
        let diary = DiaryViewModel.local(), session = ChatGPTConnection()
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
        self.observeCompanionOutput = observeCompanionOutput
        self.observeCompanionApplication = observeCompanionApplication
    }
    #endif
    @Environment(\.scenePhase) private var phase
    @State private var backgroundLease: UIBackgroundTaskIdentifier = .invalid
    @State private var backgroundGeneration: UUID?
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
            resetCompanionProfile()
            if !DiaryLaunch.isUITest { await connection.restore() }
            coach.startMonitoring(); coach.resume()
        }
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
                if value == .background { companion.enterBackground() }
                refreshCompanion()
            }
            if value == .background { continueInBackground() }
            if value == .active {
                companion.attach(profileID: model.isChangingProfile ? nil : model.readModel?.profile.id,
                                 existingEvents: companionEvents, existingSubmissions: companionSubmissions, now: Date())
                refreshCompanion()
            }
            if value == .active { endBackgroundLease(); Task { await connection.enterForeground(); await coach.waitForWorker(); coach.enterForeground() }; model.resumeWorker(); model.queueBackup() }
        }
    }
    private var companionView: some View {
        routedContent
        .onChange(of: selectedTab) { _, value in
            if !DiaryLaunch.isUITest { restoredTab = value }
            refreshCompanion()
        }
        .onChange(of: [routes.route != nil, coachHistory != nil, model.errorMessage != nil, model.isChangingProfile, hasLoaded, reduceMotion, lowPower]) { _, _ in refreshCompanion() }
        .onChange(of: model.selection, initial: true) { _, selection in
            coachRoutes.synchronize(selection: selection, isChangingProfile: model.isChangingProfile)
            coachHistory = nil
        }
        .onChange(of: model.restoreGeneration) { _, _ in coachRoutes.invalidate(); coachHistory = nil }
        .onChange(of: thermalState) { _, _ in refreshCompanion() }
        .onChange(of: companionSelection.selectedCharacterID) { _, _ in
            companionRuntime.stop()
            companion.characterChanged(now: Date())
            refreshCompanion()
        }
        .onChange(of: model.companionCaptureEvent) { _, event in receiveCompanionEvent(event) }
        .onChange(of: model.companionReviewEvent) { _, event in receiveCompanionEvent(event) }
        .onChange(of: coach.companionSubmission) { _, _ in receiveCompanionSubmission() }
        .onChange(of: coach.companionCaptureEvent) { _, event in receiveCompanionEvent(event) }
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
            await companionRuntime.attach(eligible: companionOutput.playback == .animated)
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
        .foregroundStyle(Color.diaryText)
        .environment(\.diarySettingsRoutes, routes)
        .environment(\.diaryPhotoLimiter, model.photoWorkLimiter)
        .environment(\.openDiaryCoach, openCoachAction)
        .sensoryFeedback(.success, trigger: model.captureReceipt)
        .sheet(item: $routes.route) { route in
            NavigationStack {
                SettingsView(model: model, connection: connection, nutritionKeys: nutritionKeys, destination: route.destination, companionSelection: $companionSelection)
            }
            .tint(.diaryAccent)
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
                NavigationStack { DiarySetupView(model: model) { selectedTab = "today" } }
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
                              onCompanionContextChanged: updateCompanionContext).toolbar { profileControl }
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
                              navigationRequest: coachRoutes.request,
                              onNavigationConsumed: { coachRoutes.consume($0) },
                              openHistory: openCoachHistory) { destination in
                        routes.route = SettingsRoute(destination: destination)
                    }.toolbar { profileControl }
                }
            }
        }
    }
    private var openCoachAction: OpenDiaryCoachAction {
        coachAction(from: coachRoutes.origin(selection: model.selection, isChangingProfile: model.isChangingProfile))
    }
    private func coachAction(from origin: CoachNavigationOrigin?) -> OpenDiaryCoachAction {
        OpenDiaryCoachAction(origin: origin) { target, captured in
            guard coachRoutes.queue(target, from: captured, selection: model.selection,
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
        [model.companionCaptureEvent, model.companionReviewEvent, coach.companionCaptureEvent].compactMap { $0 }
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
        companion.attach(profileID: model.isChangingProfile ? nil : model.readModel?.profile.id,
                         existingEvents: companionEvents, existingSubmissions: companionSubmissions, now: Date())
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
            visible: context.playback != .hidden, covered: routes.route != nil || coachHistory != nil || model.errorMessage != nil)
        let output = companion.resolve(context: context, now: Date())
        if companionOutput.playback == .animated && output.playback != .animated { companionRuntime.stop() }
        companionOutput = output
        #if DEBUG
        observeCompanionOutput?(output)
        #endif
    }
    private struct RuntimeUpdate: Hashable {
        let surface: CompanionSurface?
        let characterID: String
        let pose: Int
        let animated: Bool
        let reactionID: UUID?
        let darkMode: Bool
        let loaded: Bool
        // Loading can outlive its requesting task; readiness reconciles the latest output.
        let ready: Bool
    }
    private var runtimeUpdate: RuntimeUpdate {
        RuntimeUpdate(surface: selectedCompanionSurface, characterID: companionSelection.selectedCharacterID, pose: companionOutput.pose.rawValue,
                      animated: companionOutput.playback == .animated, reactionID: companionOutput.reactionID,
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
        coach.pauseActivity()
        guard (model.readModel?.pendingCount ?? 0) > 0 || coach.hasPendingWork else { coach.enterBackground(); connection.enterBackground(); return }
        endBackgroundLease()
        let generation = UUID()
        backgroundGeneration = generation
        backgroundLease = UIApplication.shared.beginBackgroundTask(withName: "Finish saved meal") {
            Task { @MainActor in guard backgroundGeneration == generation else { return }; model.enterBackground(); coach.enterBackground(); connection.enterBackground(); endBackgroundLease() }
        }
        model.resumeWorker()
        Task { await model.waitForWorker(); await coach.waitForWorker(); if backgroundGeneration == generation { coach.enterBackground(); connection.enterBackground(); endBackgroundLease() } }
    }
    private func endBackgroundLease() {
        guard backgroundLease != .invalid else { return }
        let lease = backgroundLease; backgroundLease = .invalid; backgroundGeneration = nil
        UIApplication.shared.endBackgroundTask(lease)
    }
}

struct TodayView: View {
    @Bindable var model: DiaryViewModel
    let companionOutput: CompanionOutput
    let companionRuntime: CompanionRuntime
    let onCompanionContextChanged: (CompanionContext) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var companionVisible = false
    @State private var surfaceVisible = false
    @State private var showingDetail = false
    @State private var showComposer = false
    @State private var showWeight = false
    @State private var showGoals = false
    @State private var confirmDay = false
    @State private var savedMealID: UUID?
    var body: some View {
        List {
            if model.sampleMode { Section { SampleBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) } }
            if let snapshot = model.readModel {
                if let savedMealID, model.meal(savedMealID) != nil {
                    Section {
                        NavigationLink(value: savedMealID) {
                            Label("Saved on this iPhone", systemImage: "checkmark.circle")
                                .font(.subheadline).foregroundStyle(Color.diarySuccess).frame(minHeight: 44)
                        }.accessibilityIdentifier("savedMealReceipt")
                    }
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
        .onChange(of: model.readModel?.profile.id) { _, _ in savedMealID = nil }
        .confirmationDialog("Start a waking day?", isPresented: $confirmDay, titleVisibility: .visible) {
            Button("Start new day") { guard let owner = model.readModel?.profile.id else { return }; Task { await model.change { _ = try await model.store.startDay(expectedProfileID: owner) } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Meals already recorded keep their original day. Repeated starts today reuse this day.") }
        .sheet(isPresented: $showWeight) { MorningWeightEditorView(model: model) }
        .sheet(isPresented: $showGoals) { GoalEditorView(model: model) }
        .onAppear { surfaceVisible = true; reportCompanionContext() }
        .onDisappear { surfaceVisible = false; reportCompanionContext() }
        .onChange(of: [companionVisible, showComposer, showWeight, showGoals, confirmDay, showingDetail]) { _, _ in reportCompanionContext() }
    }

    private var covered: Bool { showComposer || showWeight || showGoals || confirmDay || showingDetail }
    private func reportCompanionContext() {
        // Foreground capture is covered by its sheet. Background persistence is not a character action.
        onCompanionContextChanged(CompanionContext(surface: .today, isTyping: false,
            isProcessing: false, needsRecovery: false,
            playback: surfaceVisible && companionVisible && !covered ? .animated : .hidden))
    }
    private var summaryDate: some View {
        Menu {
            Button("Start new day", systemImage: "sunrise") { confirmDay = true }.accessibilityIdentifier("startNewDay")
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
        CompanionView(presentation: companionOutput, darkMode: colorScheme == .dark,
                      size: typeSize.isAccessibilitySize ? 144 : 200, runtime: companionRuntime)
            .frame(width: 144, height: typeSize.isAccessibilitySize ? 144 : 186, alignment: .top)
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
