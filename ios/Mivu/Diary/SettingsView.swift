import SwiftUI

struct SettingsView: View {
    @Bindable var model: DiaryViewModel
    @State private var profileName = ""
    @State private var creatingProfile = false
    @State private var showDelete = false
    @State private var showDiagnostic = false
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
                    Text("The diary works in apple sample mode without connecting ChatGPT.").font(.caption).foregroundStyle(Color.diarySecondary)
                    Button("ChatGPT connection diagnostic") { showDiagnostic = true }.frame(minHeight: 44)
                }
                Section("Delete local diary") {
                    Text("Deletion removes this profile's meals, photos, weights and preferences from this iPhone. Other profiles are preserved.").font(.caption).foregroundStyle(Color.diarySecondary)
                    Button("Delete this local profile", role: .destructive) { showDelete = true }.frame(minHeight: 44)
                }
            }
            Section { SampleBanner() }
        }
        .disabled(model.isChangingProfile)
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("Settings")
        .sheet(isPresented: $showDiagnostic) {
            VStack(spacing: 0) {
                HStack { Spacer(); Button("Done") { showDiagnostic = false }.frame(minHeight: 44) }.padding(.horizontal)
                ConnectionProofView()
            }
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.layoutDirection, .leftToRight)
        }
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
