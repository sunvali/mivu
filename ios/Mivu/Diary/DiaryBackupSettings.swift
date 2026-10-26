import SwiftUI
import UniformTypeIdentifiers

struct DiaryBackupSettings: View {
    @Bindable var model: DiaryViewModel
    @State private var importPicker = false
    @State private var exporting = false
    @State private var imported: DiarySnapshot?
    @State private var confirmRestore = false
    @State private var importing = false
    @State private var exported = false
    var body: some View {
        Group {
            if model.readModel != nil {
            if model.backupStatus.configured {
                if let date = model.backupStatus.savedAt {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Saved on this iPhone", systemImage: "checkmark.circle").font(.headline)
                        Text(date, format: .dateTime.day().month().hour().minute()).font(.subheadline).foregroundStyle(Color.diarySecondary)
                    }.padding(.vertical, 8)
                } else { Label("Backup pending", systemImage: "clock") }
                if let error = model.backupStatus.pendingError {
                    Text(error == DiaryError.staleArchive.localizedDescription
                         ? "Local backup copies conflict. Your diary and existing backup are preserved. Export a copy and contact support before replacing a backup."
                         : "Local backup pending. Check available storage, then retry. Your diary is saved.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
                Button("Retry backup") { model.retryBackup() }.frame(minHeight: 44)
            } else { Text("Local backup unavailable").foregroundStyle(Color.diarySecondary) }
            Text("Automatic backups stay on this iPhone. They do not protect against losing the phone. Portable copies stay in Mivu. In Shortcuts, add Mivu’s Export Diary action, choose a format, then transfer its output to another device for recovery.").font(.subheadline).foregroundStyle(Color.diarySecondary)
            if model.backupStatus.externalFoldersStopped {
                Text("Automatic writes to previously selected external folders have stopped. Existing external archives are preserved and remain yours to manage.")
                    .font(.subheadline).foregroundStyle(Color.diarySecondary)
            }
            Button("Export diary and photos") {
                guard let token = model.selection else { return }
                exporting = true; exported = false
                Task {
                    defer { exporting = false }
                    do {
                        let request = try await model.store.exportRequest(expectedProfileID: token.identity.profileID)
                        let ticket = try await model.exportCoordinator.makeClone(request)
                        do {
                            let data = try await model.exportCoordinator.archiveData(ticket)
                            try await model.exportCoordinator.release(ticket)
                            guard model.selection == token, !model.isChangingProfile else { return }
                            let files = LocalDiaryFiles.local
                            let url = try await Task.detached { try files.writeArchive(data, profileID: token.identity.profileID) }.value
                            guard model.selection == token, !model.isChangingProfile else { try? FileManager.default.removeItem(at: url); return }
                            exported = true
                        } catch { try? await model.exportCoordinator.release(ticket); throw error }
                    } catch { model.errorMessage = "Could not prepare an export. Your local diary is preserved." }
                }
            }.frame(minHeight: 44).disabled(exporting).accessibilityIdentifier("exportDiary")
            if exporting { ProgressView("Saving local export") }
            if exported { Label("Saved locally in Mivu", systemImage: "checkmark.circle").font(.subheadline).accessibilityIdentifier("localExportSaved") }
            }
            Link("Open Shortcuts to transfer a copy", destination: URL(string: "shortcuts://")!).frame(minHeight: 44)
            Button("Restore from diary archive") { importPicker = true }.frame(minHeight: 44).disabled(importing)
            if importing { ProgressView("Reading archive") }
        }
        .fileImporter(isPresented: $importPicker, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importing = true
                Task {
                    defer { importing = false }
                    do {
                        let archive = try await Task.detached { try DiaryArchive.read(url) }.value
                        guard !model.profiles.contains(where: { $0.id == archive.profile.id }) || model.readModel?.profile.id == archive.profile.id else {
                            model.errorMessage = "This archive belongs to another local profile. Select that profile before restoring."; return
                        }
                        imported = archive; confirmRestore = true
                    } catch { model.errorMessage = "Could not read this diary archive. Your local diary is preserved." }
                }
            case .failure: model.errorMessage = "Could not read this diary archive. Your local diary is preserved."
            }
        }
        .onChange(of: model.selection) { exported = false; imported = nil; confirmRestore = false }
        .confirmationDialog("Restore \(imported?.profile.name ?? "this private diary")?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore diary", role: .destructive) { if let archive = imported { Task { if await model.importArchive(archive) { imported = nil } } } }
            Button("Cancel", role: .cancel) { imported = nil }
        } message: {
            if imported?.profile.id == model.readModel?.profile.id { Text("Replace \(model.readModel?.profile.name ?? "the selected profile") with \(imported?.profile.name ?? "the validated archive") (\(imported?.meals.count ?? 0) meals). Older or deleted records cannot overwrite newer changes.") }
            else { Text("Import \(imported?.profile.name ?? "the archived profile") (\(imported?.meals.count ?? 0) meals) as a separate private local diary. The selected profile is preserved.") }
        }
    }
}
