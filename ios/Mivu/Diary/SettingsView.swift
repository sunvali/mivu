import SwiftUI

struct SettingsView: View {
    @Bindable var model: DiaryViewModel
    @Bindable var connection: ChatGPTConnection
    let nutritionKeys: NutritionAPIKeyStore
    let destination: CoachDestination?
    @Binding var companionSelection: CompanionSelection
    @State private var nutritionDraft = NutritionKeyDraft()
    @State private var nutritionConfigured = false
    @State private var profileName = ""
    @State private var creatingProfile = false
    @State private var pendingDeletion: DiaryProfile?
    @State private var pendingRowDeletion: DiaryProfile?
    @State private var showDiagnostic = false
    @State private var showConnectionDiagnostic = false
    @State private var showGoals = false
    @State private var showOnboarding = false
    @State private var fields = DiaryPreferencesDraft()
    @State private var linkedSection: SettingsSection?
    @State private var openedInitialDestination = false
    @Environment(\.dismiss) private var dismiss
    @State private var showDiscard = false
    private var hasUnsavedChanges: Bool { fields.isDirty || !nutritionDraft.text.isEmpty }

    private enum SettingsSection: Hashable {
        case profiles, preferences, backup, connection, nutritionSource
    }
    var body: some View {
        List {
            Section {
                NavigationLink(value: SettingsSection.profiles) {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.largeTitle).foregroundStyle(Color.diaryProtein).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.readModel?.profile.name ?? "Local profiles").font(.title3.weight(.semibold))
                            Text("Private diary on this iPhone").font(.subheadline).foregroundStyle(Color.diarySecondary)
                        }
                    }.frame(minHeight: 72)
                }.accessibilityIdentifier("localProfiles")
            }
            companionSection
            if model.readModel != nil {
                DaySettingsSection(readModel: model.readModel)
                Section("Setup") {
                    Button { showGoals = true } label: { settingsRow("Goals", symbol: "scope", color: .diaryAccent) }
                        .accessibilityIdentifier("editGoals")
                    Button { showOnboarding = true } label: { settingsRow("Redo setup with Pip", symbol: "pawprint", color: .diaryProtein) }
                        .accessibilityIdentifier("redoOnboarding")
                    NavigationLink(value: SettingsSection.preferences) { settingsRow("Diary preferences", symbol: "list.bullet.rectangle", color: .diaryCarbs) }
                    NavigationLink(value: SettingsSection.backup) { settingsRow("Backup & export", symbol: "square.and.arrow.up", color: .diaryProtein) }
                    NavigationLink(value: SettingsSection.connection) {
                        settingsRow("Coach AI", symbol: "sparkles", color: .diaryFat,
                                    value: connection.provider == .apple ? "Apple · iPhone" : connection.provider == .appleCloud ? "Apple · Cloud"
                                        : connection.planAuthorized ? "ChatGPT" : "Connect ChatGPT")
                    }
                    NavigationLink(value: SettingsSection.nutritionSource) {
                        settingsRow("Nutrition source", symbol: "fork.knife", color: .diaryCarbs, value: nutritionConfigured ? "Configured" : "Optional")
                    }
                }
                Section {
                    #if DEBUG
                    Button { showDiagnostic = true } label: { settingsRow("Diagnostics", symbol: "stethoscope", color: .diarySuccess) }
                    #endif
                    Link(destination: MivuLinks.privacyPolicy) { settingsRow("Privacy Policy", symbol: "hand.raised", color: .diaryAccent) }
                        .accessibilityIdentifier("privacyPolicy")
                    Text("Calorie and nutrition figures are estimates, not medical advice. Check with a doctor or registered dietitian before big changes to how you eat.").font(.subheadline).foregroundStyle(Color.diarySecondary)
                    Text("Keep a backup or export before changing phones.").font(.subheadline).foregroundStyle(Color.diarySecondary)
                } header: { Text("Support") }
                Section {
                    Button(role: .destructive) { pendingDeletion = model.readModel?.profile } label: { Label("Delete profile", systemImage: "trash").frame(minHeight: 44) }
                }
            }
            if model.sampleMode { Section { SampleBanner() } }
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("Settings")
        .interactiveDismissDisabled(hasUnsavedChanges)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { if hasUnsavedChanges { showDiscard = true } else { dismiss() } }
                    .accessibilityIdentifier("doneSettings")
                    .alert("Discard unsaved settings?", isPresented: $showDiscard) {
                        Button("Discard changes", role: .destructive) { dismiss() }
                        Button("Keep editing", role: .cancel) {}
                    } message: { Text("Your saved settings stay unchanged. Unsaved preferences and lookup key will be discarded.") }
            }
        }
        .navigationDestination(for: SettingsSection.self) { section in
            settingsDetail(section)
        }
        .task { nutritionConfigured = (try? nutritionKeys.load()) != nil }
        .sheet(isPresented: $showDiagnostic) {
            VStack(spacing: 0) {
                HStack { Spacer(); Button("Done") { showDiagnostic = false }.frame(minHeight: 44) }.padding(.horizontal)
                ConnectionProofView(connection: connection)
            }
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.layoutDirection, .leftToRight)
        }
        .sheet(isPresented: $showGoals) { GoalEditorView(model: model) }
        .fullScreenCover(isPresented: $showOnboarding) { OnboardingView(model: model, connection: connection) { showOnboarding = false } }
        .onChange(of: model.readModel?.profile, initial: true) { _, profile in fields.synchronize(profile, restoreGeneration: model.restoreGeneration) }
        .onChange(of: model.restoreGeneration) { _, _ in fields.synchronize(model.readModel?.profile, restoreGeneration: model.restoreGeneration) }
        .modifier(DeleteProfileDialog(model: model, connection: connection, pending: $pendingDeletion))
        .onAppear {
            guard !openedInitialDestination else { return }
            openedInitialDestination = true
            open(destination)
        }
        .onChange(of: destination) { _, value in open(value) }
        .navigationDestination(isPresented: Binding(get: { linkedSection != nil }, set: { if !$0 { linkedSection = nil } })) {
            if let section = linkedSection { settingsDetail(section) }
        }
    }

    private var companionSection: some View {
        Section("Companion") {
            if companionSelection.catalog.showsChooser {
                ForEach(companionSelection.catalog.characters) { character in
                    Button { companionSelection.select(character.id) } label: {
                        HStack(spacing: 12) {
                            companionPreview(character)
                            Text(character.displayName).foregroundStyle(Color.diaryText)
                            Spacer()
                            if character.id == companionSelection.selectedCharacterID {
                                Image(systemName: "checkmark").accessibilityLabel("Selected companion")
                            }
                        }.frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("companionChoice-" + character.id)
                }
            } else {
                HStack(spacing: 12) {
                    companionPreview(companionSelection.selectedCharacter)
                    Text(companionSelection.selectedCharacter.displayName).accessibilityIdentifier("companionName")
                }.frame(minHeight: 44)
            }
        }
    }
    private func companionPreview(_ character: CharacterDescriptor) -> some View {
        Image(character.previewAssetName).resizable().scaledToFit().frame(width: 40, height: 40)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func settingsDetail(_ section: SettingsSection) -> some View {
        Form {
            switch section {
            case .profiles:
            Section("Private local profile") {
                if let profile = model.readModel?.profile { Text(profile.name).font(.headline) }
                Text("Profiles are separate private diaries on this iPhone. Keep a backup folder or export before changing phones.").font(.subheadline).foregroundStyle(Color.diarySecondary)
                ForEach(model.profiles) { profile in
                    Button { Task { await model.switchProfile(profile.id) } } label: {
                        HStack { Text(profile.name); Spacer(); if model.readModel?.profile.id == profile.id { Image(systemName: "checkmark").accessibilityLabel("Selected profile") } }
                    }.frame(minHeight: 44)
                    .swipeActions {
                        // No destructive role: it removes the row before the confirmation and the later delete then crashes the list.
                        Button("Delete", systemImage: "trash") { pendingRowDeletion = profile }.tint(Color.diaryError)
                    }
                }
                Button("Create local profile") { creatingProfile = true }.frame(minHeight: 44)
                if model.readModel != nil { Button("Sign out of local profile") { Task { await model.signOut() } }.frame(minHeight: 44) }
            }

            case .preferences:
                if let profile = model.readModel?.profile {
                Section("Diary preferences") {
                    TextField("Timezone", text: $fields.timezone).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Dietary preferences and restrictions", text: $fields.preferences, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("dietaryPreferences")
                    Text("A photo cannot prove that food meets a dietary restriction.").font(.subheadline).foregroundStyle(Color.diarySecondary)
                    Button("Save preferences") {
                        Task {
                            do {
                                let latest = try await model.store.diaryHead(expectedProfileID: profile.id).profile
                                guard !fields.conflicts(with: latest) else {
                                    fields.synchronize(latest, restoreGeneration: model.restoreGeneration)
                                    try await model.refresh(profileID: profile.id)
                                    return
                                }
                                let updated = fields.applying(to: latest)
                                await model.change { try await model.store.updateProfile(updated, expectedProfile: latest, expectedProfileID: profile.id) }
                            } catch { model.errorMessage = "Could not load the latest profile settings. Try again." }
                        }
                    }.frame(minHeight: 44).disabled(TimeZone(identifier: fields.timezone) == nil || fields.preferences.count > 10_000 || fields.hasConflict)
                    if fields.hasConflict {
                        Text("These settings changed while you were editing. Your draft is preserved.")
                            .font(.subheadline).foregroundStyle(Color.diarySecondary)
                        Button("Use latest saved settings") { fields.useSaved(model.readModel?.profile) }
                            .frame(minHeight: 44)
                    }
                    Text("Timezone changes preserve earlier meals and day labels. You may be asked which waking day to use.").font(.subheadline).foregroundStyle(Color.diarySecondary)
                }

                    Section("Language") {
                        LabeledContent("App language", value: "English")
                        Text("English is supported for this version. Your stored profile language is preserved.").font(.subheadline).foregroundStyle(Color.diarySecondary)
                    }
                }
            case .backup:
                Section("Backup and portability") { DiaryBackupSettings(model: model) }
                if model.readModel != nil { Section("Share a report") { DiaryReportSettings(model: model) } }
            case .connection:
                Section {
                    Picker("Coach AI", selection: $connection.provider) {
                        Text("Apple Intelligence · iPhone").tag(ChatGPTConnection.Provider.apple).selectionDisabled(!connection.available(.apple))
                        // Hidden until Apple grants the Private Cloud Compute entitlement.
                        if connection.available(.appleCloud) { Text("Apple Intelligence · Cloud").tag(ChatGPTConnection.Provider.appleCloud) }
                        Text("ChatGPT").tag(ChatGPTConnection.Provider.chatGPT)
                    }
                    .pickerStyle(.inline).labelsHidden()
                } header: { Text("Coach AI") } footer: {
                    switch connection.provider {
                    case .apple: Text("Runs on this iPhone with no account. It logs meals and changes amounts, with rougher estimates. Use ChatGPT for questions and other edits.")
                    case .appleCloud: Text("Uses Apple's Private Cloud Compute with no account. Apple doesn't keep your data.")
                    case .chatGPT: Text("Uses your ChatGPT plan. Coach messages and photos you send are shared with OpenAI.")
                    }
                }
                if connection.provider == .chatGPT || connection.activeRegistrationID != nil {
                Section("Connection") {
                    Label(connection.planAuthorized ? "ChatGPT connected" : "Connect for meal analysis", systemImage: "person.crop.circle")
                    Text("Coach analysis uses your selected ChatGPT account's plan allowance when eligible and is subject to its usage limits. Captures save locally without a connection.").font(.subheadline).foregroundStyle(Color.diarySecondary)
                    if connection.isConnecting {
                        ProgressView("Connecting")
                        Button("Cancel connection") { connection.cancelConnection() }.frame(minHeight: 44)
                    } else {
                        ChatGPTConnectButton(connection: connection).frame(minHeight: 44)
                    }
                    if !connection.models.isEmpty {
                        Picker("Account model", selection: $connection.selectedModel) {
                            ForEach(connection.models, id: \.slug) { Text($0.displayName).tag($0.slug) }
                        }
                    }
                    if connection.activeRegistrationID != nil {
                        Button("Disconnect ChatGPT", role: .destructive) { Task { await connection.disconnect() } }.frame(minHeight: 44)
                    }
                    if let notice = connection.notice { Text(notice.rawValue).font(.subheadline).foregroundStyle(Color.diarySecondary) }
                    Link("ChatGPT usage settings", destination: URL(string: "https://chatgpt.com/settings/usage")!).frame(minHeight: 44)
                    #if DEBUG
                    Button("ChatGPT connection diagnostic") { showConnectionDiagnostic = true }.frame(minHeight: 44)
                    #endif
                }
                }

            case .nutritionSource:
                Section("Optional nutrition source") {
                    Label(nutritionConfigured ? "USDA lookup configured" : "USDA lookup not configured", systemImage: "leaf")
                    Text("Food estimates and capture work without a lookup key. Add your own USDA key for retrieved nutrition evidence.").font(.subheadline).foregroundStyle(Color.diarySecondary)
                    SecureField("USDA API key", text: $nutritionDraft.text).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save lookup key") {
                        if nutritionDraft.save(using: nutritionKeys.save) { nutritionConfigured = true }
                    }.frame(minHeight: 44).disabled(nutritionDraft.text.isEmpty)
                    if nutritionConfigured {
                        Button("Remove lookup key", role: .destructive) {
                            do { try nutritionKeys.remove(); nutritionConfigured = false; nutritionDraft.message = "Nutrition lookup key removed." }
                            catch { nutritionDraft.message = "Could not remove the key securely. Try again." }
                        }.frame(minHeight: 44)
                    }
                    if let message = nutritionDraft.message { Text(message).font(.subheadline).foregroundStyle(Color.diarySecondary) }
                    Text("This key stays in this iPhone's Keychain and is excluded from diary exports and backups.").font(.subheadline).foregroundStyle(Color.diarySecondary)
                }

            }
        }
        .alert("Create local profile", isPresented: $creatingProfile) {
            TextField("Profile name", text: $profileName)
            Button("Create") {
                let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let previousProfileID = model.readModel?.profile.id
                Task {
                    await model.createProfile(name: name)
                    guard let profile = model.readModel?.profile,
                          profile.id != previousProfileID,
                          profile.name == name else { return }
                    profileName = ""
                }
            }.disabled(model.isChangingProfile || profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: { Text("This profile is stored privately on this iPhone.") }
        .modifier(DeleteProfileDialog(model: model, connection: connection, pending: $pendingRowDeletion))
        .alert("Settings error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(LocalizedStringKey(model.errorMessage ?? ""))
        }
        .sheet(isPresented: $showConnectionDiagnostic) {
            VStack(spacing: 0) {
                HStack { Spacer(); Button("Done") { showConnectionDiagnostic = false }.frame(minHeight: 44) }.padding(.horizontal)
                ConnectionProofView(connection: connection)
            }
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.layoutDirection, .leftToRight)
        }
        .disabled(model.isChangingProfile)
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle(title(section))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func settingsRow(_ title: String, symbol: String, color: Color, value: String? = nil) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 28).accessibilityHidden(true)
            Text(title).foregroundStyle(Color.diaryText)
            Spacer(minLength: 8)
            if let value { Text(value).font(.subheadline).foregroundStyle(Color.diarySecondary) }
        }.frame(minHeight: 48)
    }

    private func title(_ section: SettingsSection) -> String {
        switch section {
        case .profiles: "Local profiles"
        case .preferences: "Diary preferences"
        case .backup: "Backup & export"
        case .connection: "Coach AI"
        case .nutritionSource: "Nutrition source"
        }
    }

    private func open(_ destination: CoachDestination?) {
        switch destination {
        case .profiles: linkedSection = .profiles
        case .backup: linkedSection = .backup
        case .connection: linkedSection = .connection
        case .nutritionSource: linkedSection = .nutritionSource
        case .settings, nil: break
        }
    }
}

/// Settings and its pushed Local profiles page each present this, since a covered root cannot.
private struct DeleteProfileDialog: ViewModifier {
    let model: DiaryViewModel
    let connection: ChatGPTConnection
    @Binding var pending: DiaryProfile?

    func body(content: Content) -> some View {
        content.confirmationDialog("Delete \(pending?.name ?? "this private local profile")?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible, presenting: pending) { profile in
            Button("Delete profile", role: .destructive) {
                Task {
                    await model.deleteProfile(profile.id)
                    // The ChatGPT connection is shared by all profiles, so it goes with the last one.
                    if model.profiles.isEmpty, connection.activeRegistrationID != nil { await connection.disconnect() }
                }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { profile in Text("This removes \(profile.name)'s meals, photos, weights and preferences from this iPhone. Export or save a backup first if you want to keep your records. Other profiles are preserved. Deleting your last profile also disconnects ChatGPT.") }
    }
}
