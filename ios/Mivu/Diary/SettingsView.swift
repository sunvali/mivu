import SwiftUI

struct SettingsView: View {
    @Bindable var model: DiaryViewModel
    @Bindable var connection: ChatGPTConnection
    @State private var window: UIWindow?
    let nutritionKeys: NutritionAPIKeyStore
    @State private var nutritionDraft = NutritionKeyDraft()
    @State private var nutritionConfigured = false
    @State private var profileName = ""
    @State private var creatingProfile = false
    @State private var showDelete = false
    @State private var showDiagnostic = false
    @State private var showGoals = false
    @State private var fields = DiaryPreferencesDraft()
    var body: some View {
        Form {
            Section("Private local profile") {
                if let profile = model.snapshot?.profile { Text(profile.name).font(.headline) }
                Text("Profiles are separate private diaries on this iPhone. Keep a backup folder or export before changing phones.").font(.caption).foregroundStyle(Color.diarySecondary)
                ForEach(model.profiles) { profile in
                    Button { Task { await model.switchProfile(profile.id) } } label: {
                        HStack { Text(profile.name); Spacer(); if model.snapshot?.profile.id == profile.id { Image(systemName: "checkmark").accessibilityLabel("Selected profile") } }
                    }.frame(minHeight: 44)
                }
                Button("Create local profile") { creatingProfile = true }.frame(minHeight: 44)
                if model.snapshot != nil { Button("Sign out of local profile") { Task { await model.signOut() } }.frame(minHeight: 44) }
            }
            if let profile = model.snapshot?.profile {
                Section("Goals") {
                    Button("Set dated goals") { showGoals = true }
                        .frame(minHeight: 44).accessibilityIdentifier("editGoals")
                    Text("Your targets are optional settings and are never inferred from meals or workouts.")
                        .font(.caption).foregroundStyle(Color.diarySecondary)
                }
                Section("Diary preferences") {
                    TextField("Timezone", text: $fields.timezone).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Dietary preferences and restrictions", text: $fields.preferences, axis: .vertical).lineLimit(3...6)
                    Text("A photo cannot prove that food meets a dietary restriction.").font(.caption).foregroundStyle(Color.diarySecondary)
                    Button("Save preferences") {
                        let updated = fields.applying(to: profile)
                        Task { await model.change { try await model.store.updateProfile(updated, expectedProfileID: profile.id) } }
                    }.frame(minHeight: 44).disabled(TimeZone(identifier: fields.timezone) == nil || fields.preferences.count > 10_000)
                    Text("Timezone changes preserve earlier meals and day labels. You may be asked which waking day to use.").font(.caption).foregroundStyle(Color.diarySecondary)
                }
                Section("Backup and portability") {
                    DiaryBackupSettings(model: model)
                }
                Section("Connection") {
                    Label(connection.planAuthorized ? "ChatGPT connected" : "Connect for meal analysis", systemImage: "person.crop.circle")
                    Text("Captures save locally without a connection. Analysis uses your selected ChatGPT account.").font(.caption).foregroundStyle(Color.diarySecondary)
                    if connection.isConnecting {
                        ProgressView("Connecting")
                        Button("Cancel connection") { connection.cancelConnection() }.frame(minHeight: 44)
                    } else {
                        Button(connection.activeRegistrationID == nil ? "Connect ChatGPT" : "Reauthorize ChatGPT") {
                            guard let window else { return }
                            Task { await connection.connect(window: window) }
                        }.frame(minHeight: 44).disabled(window == nil || connection.isDisconnecting)
                    }
                    if !connection.models.isEmpty {
                        Picker("Account model", selection: $connection.selectedModel) {
                            ForEach(connection.models, id: \.slug) { Text($0.displayName).tag($0.slug) }
                        }
                    }
                    if connection.activeRegistrationID != nil {
                        Button("Disconnect ChatGPT", role: .destructive) { Task { await connection.disconnect() } }.frame(minHeight: 44)
                    }
                    if let notice = connection.notice { Text(notice.rawValue).font(.caption).foregroundStyle(Color.diarySecondary) }
                    Button("ChatGPT connection diagnostic") { showDiagnostic = true }.frame(minHeight: 44)
                }
                Section("Optional nutrition source") {
                    Label(nutritionConfigured ? "USDA lookup configured" : "USDA lookup not configured", systemImage: "leaf")
                    Text("Food estimates and capture work without a lookup key. Add your own USDA key for retrieved nutrition evidence.").font(.caption).foregroundStyle(Color.diarySecondary)
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
                    if let message = nutritionDraft.message { Text(message).font(.caption).foregroundStyle(Color.diarySecondary) }
                    Text("This key stays in this iPhone's Keychain and is excluded from diary exports and backups.").font(.caption).foregroundStyle(Color.diarySecondary)
                }
                Section("Delete local diary") {
                    Text("Deletion removes this profile's meals, photos, weights and preferences from this iPhone. Other profiles are preserved.").font(.caption).foregroundStyle(Color.diarySecondary)
                    Button("Delete this local profile", role: .destructive) { showDelete = true }.frame(minHeight: 44)
                }
            }
            if model.sampleMode { Section { SampleBanner() } }
        }
        .disabled(model.isChangingProfile)
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("Settings")
        .background(PresentationWindowReader { window = $0 })
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
        .onChange(of: model.snapshot?.profile.id, initial: true) { _, _ in fields.synchronize(model.snapshot?.profile, restoreGeneration: model.restoreGeneration) }
        .onChange(of: model.restoreGeneration) { _, _ in fields.synchronize(model.snapshot?.profile, restoreGeneration: model.restoreGeneration) }
        .alert("Create local profile", isPresented: $creatingProfile) {
            TextField("Profile name", text: $profileName)
            Button("Create") { let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines); if !name.isEmpty { Task { await model.createProfile(name: name); profileName = "" } } }.disabled(model.isChangingProfile)
            Button("Cancel", role: .cancel) {}
        } message: { Text("This profile is stored privately on this iPhone.") }
        .confirmationDialog("Delete this private local profile?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete profile", role: .destructive) {
                Task {
                    await model.deleteCurrentProfile()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Export or save a backup first if you want to keep your records.") }
    }
}
