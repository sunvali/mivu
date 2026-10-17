import SwiftUI

extension EnvironmentValues {
    @Entry var openDiaryConnection: () -> Void = {}
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
                        if model.snapshot != nil { onSelected() }
                    }
                }.disabled(trimmedName.isEmpty || model.isChangingProfile)
                    .frame(minHeight: 44).accessibilityIdentifier("createDiary")
            }
            if !model.profiles.isEmpty {
                Section("Your local diaries") {
                    ForEach(model.profiles) { profile in
                        Button(profile.name) {
                            Task { await model.switchProfile(profile.id); if model.snapshot?.profile.id == profile.id { onSelected() } }
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
    private struct SettingsRoute: Identifiable {
        let id = UUID()
        let destination: CoachDestination?
    }
    @State private var settingsRoute: SettingsRoute?
    @State private var hasLoaded = false
    @AppStorage("diarySelectedTab") private var restoredTab = "today"
    private let nutritionKeys: NutritionAPIKeyStore
    init() {
        let diary = DiaryViewModel.local(), session = ChatGPTConnection()
        let keys = NutritionAPIKeyStore.local
        nutritionKeys = keys
        let foodSource = FoodEvidenceClient()
        let fixture: (() throws -> CoachViewModel.Inference)? = DiaryLaunch.isCoachInferenceFixture
            ? { { input, tools in try await CoachUITestInference.respond(input, tools) } } : nil
        _model = State(initialValue: diary)
        _connection = State(initialValue: session)
        _coach = State(initialValue: CoachViewModel(diary: diary, connection: session, inference: fixture, lookup: { query in
            try await foodSource.search(query: query, apiKey: keys.load())
        }))
        _selectedTab = State(initialValue: DiaryLaunch.isUITest && !DiaryLaunch.isSampleMode ? "coach" : "today")
    }
    @Environment(\.scenePhase) private var phase
    @State private var backgroundLease: UIBackgroundTaskIdentifier = .invalid
    @State private var backgroundGeneration: UUID?
    var body: some View {
        Group {
            if !hasLoaded {
                ProgressView("Opening diary").frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.diaryCanvas)
            } else if model.snapshot == nil {
                NavigationStack { DiarySetupView(model: model) { selectedTab = "today" } }
            } else {
                TabView(selection: $selectedTab) {
                    Tab("Today", systemImage: "sun.max", value: "today") {
                        NavigationStack { TodayView(model: model).toolbar { profileControl } }
                    }
                    Tab("Diary", systemImage: "calendar", value: "diary") {
                        NavigationStack { HistoryView(model: model).toolbar { profileControl } }
                    }
                    Tab("Progress", systemImage: "chart.bar", value: "progress") {
                        NavigationStack { DiaryProgressView(model: model).toolbar { profileControl } }
                    }
                    Tab("Coach", systemImage: "bubble.left.and.bubble.right", value: "coach") {
                        NavigationStack {
                            CoachView(coach: coach) { destination in
                                settingsRoute = SettingsRoute(destination: destination)
                            }.toolbar { profileControl }
                        }
                    }
                }
            }
        }
        .tint(.diaryAccent)
        .foregroundStyle(Color.diaryText)
        .environment(\.openDiaryConnection) { settingsRoute = SettingsRoute(destination: .connection) }
        .sensoryFeedback(.success, trigger: model.captureReceipt)
        .sheet(item: $settingsRoute) { route in
            NavigationStack {
                SettingsView(model: model, connection: connection, nutritionKeys: nutritionKeys, destination: route.destination)
            }
            .tint(.diaryAccent)
        }
        .onChange(of: selectedTab) { _, value in if !DiaryLaunch.isUITest { restoredTab = value } }
        .task {
            if !DiaryLaunch.isUITest, ["today", "diary", "progress", "coach"].contains(restoredTab) { selectedTab = restoredTab }
            model.resumeCoach = { coach.resume() }
            model.retryCoachMeal = { id in
                Task { await coach.retryMeal(id) }
            }
            await model.load(createDefaultProfile: (DiaryLaunch.isUITest || DiaryLaunch.isSampleMode) && !ProcessInfo.processInfo.arguments.contains("--onboarding-ui-test"))
            hasLoaded = true
            if !DiaryLaunch.isUITest { await connection.restore() }
            coach.startMonitoring(); coach.resume()
        }
        .onChange(of: model.isChangingProfile) { _, changing in
            if changing { coach.cancel() }
            else { Task { await coach.waitForWorker(); coach.resume() } }
        }
        .onChange(of: model.snapshot?.profile.id) { _, _ in coach.draft = MealDraft(); coach.errorMessage = nil }
        .onChange(of: connection.sessionRevision) { _, _ in coach.cancel() }
        .onChange(of: connection.planAuthorized) { _, authorized in if authorized { coach.resume() } }
        .onChange(of: connection.selectedModel) { _, _ in coach.cancel(); Task { await coach.waitForWorker(); coach.resume() } }
        .onChange(of: phase) { _, value in
            if value == .background { continueInBackground() }
            if value == .active { endBackgroundLease(); Task { await connection.enterForeground(); await coach.waitForWorker(); coach.enterForeground() }; model.resumeWorker(); model.queueBackup() }
        }
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
    private var profileControl: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { settingsRoute = SettingsRoute(destination: nil) } label: {
                Image(systemName: "person.crop.circle").font(.title3).frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Profile and settings")
            .accessibilityIdentifier("profileSettings")
        }
    }
    private func continueInBackground() {
        coach.pauseActivity()
        guard (model.snapshot?.pendingCount ?? 0) > 0 || coach.hasPendingWork else { coach.enterBackground(); connection.enterBackground(); return }
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
    @State private var showComposer = false
    @State private var showWeight = false
    @State private var showGoals = false
    @State private var confirmDay = false
    @State private var savedMealID: UUID?
    var body: some View {
        List {
            if model.sampleMode { Section { SampleBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) } }
            if let snapshot = model.snapshot {
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
                        Text(model.activeDay?.localDate ?? "Your waking day")
                            .font(.subheadline).foregroundStyle(Color.diarySecondary)
                        if let day = model.activeDay {
                            NutritionSummary(totals: snapshot.totals(dayID: day.id))
                            todayGoal(snapshot: snapshot, day: day)
                        } else {
                            Text("No recorded meals yet").foregroundStyle(Color.diarySecondary)
                        }
                        if snapshot.pendingCount > 0 {
                            Label("\(snapshot.pendingCount) pending", systemImage: "clock")
                                .font(.subheadline).foregroundStyle(Color.diaryWarning)
                                .accessibilityIdentifier("pendingCount")
                        }
                    }.padding(.vertical, 8).listRowBackground(Color.diarySummarySurface)
                }
                Section {
                    if model.todaysMeals.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Your first meal starts here", systemImage: "fork.knife").font(.headline)
                            Text("Add photos or a note.").foregroundStyle(Color.diarySecondary)
                        }.padding(.vertical, 16)
                    }
                    ForEach(model.todaysMeals, id: \.id) { meal in
                        NavigationLink(value: meal.id) { MealRow(meal: meal) }.accessibilityIdentifier("mealRow")
                    }
                } header: { DiarySectionLabel(title: "Meals", symbol: "fork.knife", color: .diaryCarbs) }
                Section {
                    Button { showWeight = true } label: {
                        HStack {
                            Label { Text("Morning weight") } icon: { Image(systemName: "scalemass").foregroundStyle(Color.diaryWeight) }
                            Spacer()
                            if let entry = snapshot.weights.first(where: { $0.dayID == model.activeDay?.id }) {
                                Text("\(entry.value.formatted(.number.precision(.fractionLength(1)))) \(entry.unit)").monospacedDigit()
                            } else { Text("Log weight").foregroundStyle(Color.diarySecondary) }
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("logWeight")
                }
                if let day = model.activeDay {
                    Section("Day coverage") {
                        Picker("Completeness", selection: Binding(get: { day.completeness }, set: { value in
                            Task { await model.change { try await model.store.setCompleteness(dayID: day.id, value, expectedProfileID: snapshot.profile.id) } }
                        })) { ForEach(DayCompleteness.allCases, id: \.self) { Text($0.title).tag($0) } }
                        Text("Complete means all intake was recorded. Partial totals describe only recorded meals.").font(.caption).foregroundStyle(Color.diarySecondary)
                    }
                }
            } else {
                Section { Text("Choose a private local profile in Settings to open your diary.").foregroundStyle(Color.diarySecondary) }
            }
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .environment(\.defaultMinListRowHeight, 56)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .safeAreaInset(edge: .bottom) {
            if model.snapshot != nil {
                DiaryCaptureAction { showComposer = true }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.diaryCanvas)
            }
        }
        .navigationDestination(for: UUID.self) { MealDetailView(model: model, mealID: $0) }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Start new day", systemImage: "sunrise") { confirmDay = true }
                        .accessibilityIdentifier("startNewDay")
                } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Day actions")
            }
        }
        .sheet(isPresented: $showComposer) { MealComposerView(model: model, onSaved: { savedMealID = $0 }) }
        .onChange(of: model.snapshot?.profile.id) { _, _ in savedMealID = nil }
        .confirmationDialog("Start a waking day?", isPresented: $confirmDay, titleVisibility: .visible) {
            Button("Start new day") { guard let owner = model.snapshot?.profile.id else { return }; Task { await model.change { _ = try await model.store.startDay(expectedProfileID: owner) } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Meals already recorded keep their original day. Repeated starts today reuse this day.") }
        .sheet(isPresented: $showWeight) { MorningWeightEditorView(model: model) }
        .sheet(isPresented: $showGoals) { GoalEditorView(model: model) }
    }

    @ViewBuilder private func todayGoal(snapshot: DiarySnapshot, day: TrackingDay) -> some View {
        let report = ProgressAnalytics.daily(snapshot: snapshot, localDate: day.localDate)
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
        HStack {
            Image(systemName: day.completeness == .complete ? "checkmark.circle" : "circle.lefthalf.filled")
            Text(day.completeness.title)
            Text("day")
        }.font(.caption).foregroundStyle(Color.diarySecondary)
    }

    @ViewBuilder private func remaining(_ value: Double?) -> some View {
        if let value {
            Text("\(abs(value).formatted(.number.precision(.fractionLength(0)))) \(value < 0 ? "above goal" : "to goal")")
        } else { Text("Not estimated yet").foregroundStyle(Color.diarySecondary) }
    }
}
