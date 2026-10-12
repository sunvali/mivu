import SwiftUI

struct DiaryRootView: View {
    @State private var model = DiaryViewModel.local()
    @Environment(\.scenePhase) private var phase
    @State private var backgroundLease: UIBackgroundTaskIdentifier = .invalid
    @State private var backgroundGeneration: UUID?
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") { NavigationStack { TodayView(model: model) } }
            Tab("History", systemImage: "calendar") { NavigationStack { HistoryView(model: model) } }
            Tab("Settings", systemImage: "gearshape") { NavigationStack { SettingsView(model: model) } }
        }
        .tint(.diaryAccent)
        .foregroundStyle(Color.diaryText)
        .sensoryFeedback(.success, trigger: model.captureReceipt)
        .task { await model.load() }
        .onChange(of: phase) { _, value in
            if value == .background { continueInBackground() }
            if value == .active { endBackgroundLease(); model.resumeWorker(); model.queueBackup() }
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
    private func continueInBackground() {
        guard model.snapshot?.pendingCount ?? 0 > 0 else { return }
        endBackgroundLease()
        let generation = UUID()
        backgroundGeneration = generation
        backgroundLease = UIApplication.shared.beginBackgroundTask(withName: "Finish saved meal") {
            Task { @MainActor in guard backgroundGeneration == generation else { return }; model.enterBackground(); endBackgroundLease() }
        }
        model.resumeWorker()
        Task { await model.waitForWorker(); if backgroundGeneration == generation { endBackgroundLease() } }
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
    @State private var weight = ""
    @State private var confirmDay = false
    var body: some View {
        List {
            Section { SampleBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            if let snapshot = model.snapshot {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Waking day").font(.caption.weight(.medium)).foregroundStyle(Color.diarySecondary)
                        Text(model.activeDay?.localDate ?? "Your waking day").font(.title2.weight(.semibold))
                    }
                    if let day = model.activeDay { NutritionSummary(totals: snapshot.totals(dayID: day.id)) }
                    else { Text("No recorded meals yet").foregroundStyle(Color.diarySecondary) }
                    if snapshot.pendingCount > 0 {
                        Label("\(snapshot.pendingCount) pending", systemImage: "clock").foregroundStyle(Color.diarySecondary).accessibilityIdentifier("pendingCount")
                    }
                }
                Section {
                    Button("Start new day") { confirmDay = true }.frame(minHeight: 44).accessibilityIdentifier("startNewDay")
                    Button("Log morning weight") { showWeight = true }.frame(minHeight: 44).accessibilityIdentifier("logWeight")
                }
                Section("Meals") {
                    if model.todaysMeals.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Your first meal starts here", systemImage: "fork.knife").font(.headline)
                            Text("Add photos or a note.").foregroundStyle(Color.diarySecondary)
                        }.padding(.vertical, 16)
                    }
                    ForEach(model.todaysMeals, id: \.id) { meal in
                        NavigationLink(value: meal.id) { MealRow(meal: meal) }.accessibilityIdentifier("mealRow")
                    }
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
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .safeAreaInset(edge: .bottom) {
            if model.snapshot != nil {
                DiaryCaptureAction { showComposer = true }
                    .padding(.horizontal, 24).padding(.vertical, 12)
            }
        }
        .navigationDestination(for: UUID.self) { MealDetailView(model: model, mealID: $0) }
        .navigationTitle("Today")
        .sheet(isPresented: $showComposer) { MealComposerView(model: model) }
        .confirmationDialog("Start a waking day?", isPresented: $confirmDay, titleVisibility: .visible) {
            Button("Start new day") { guard let owner = model.snapshot?.profile.id else { return }; Task { await model.change { _ = try await model.store.startDay(expectedProfileID: owner) } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Meals already recorded keep their original day. Repeated starts today reuse this day.") }
        .sheet(isPresented: $showWeight) {
            NavigationStack {
                Form {
                    Section("Morning weight") { TextField("Weight in kg", text: $weight).keyboardType(.decimalPad).accessibilityIdentifier("weightInput"); Text("Optional. Saving starts or reuses today's waking day.").font(.caption).foregroundStyle(Color.diarySecondary) }
                }.navigationTitle("Morning weight")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showWeight = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        guard let value = Double(weight.replacingOccurrences(of: ",", with: ".")), value > 0, let owner = model.snapshot?.profile.id else { return }
                        Task { if await model.change({ _ = try await model.store.recordWeight(value: value, expectedProfileID: owner) }) { showWeight = false; weight = "" } }
                    }.disabled(Double(weight.replacingOccurrences(of: ",", with: ".")).map { $0 > 0 && $0 <= 1000 } != true).accessibilityIdentifier("saveWeight") }
                }
            }
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.layoutDirection, .leftToRight)
            .presentationDetents([.medium, .large])
        }
    }
}
