import SwiftUI
import UniformTypeIdentifiers

private struct DiaryExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw DiaryError.invalidData }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct DiaryBackupSettings: View {
    @Bindable var model: DiaryViewModel
    @State private var folderPicker = false
    @State private var importPicker = false
    @State private var exportPicker = false
    @State private var exportDocument: DiaryExportDocument?
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
                        Label("Saved to backup folder", systemImage: "checkmark.circle").font(.headline)
                        Text(date, format: .dateTime.day().month().hour().minute()).font(.subheadline).foregroundStyle(Color.diarySecondary)
                    }.padding(.vertical, 8)
                } else { Label("Backup pending", systemImage: "clock") }
                if let error = model.backupStatus.pendingError {
                    Text(error == DiaryError.staleArchive.localizedDescription
                         ? "Backup copies conflict. Your local diary and existing backup are preserved. Export a copy and resolve the folder copy in Files before retrying."
                         : "Backup pending. Check that the folder is available, then retry. Your local diary is saved.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
                Button("Retry backup") { model.retryBackup() }.frame(minHeight: 44)
            } else { Text("No backup folder selected").foregroundStyle(Color.diarySecondary) }
            Button("Choose private backup folder") { folderPicker = true }.frame(minHeight: 44)
            Text("Choose a private Files folder, including iCloud Drive when available. Folder acknowledgement does not confirm remote upload.").font(.subheadline).foregroundStyle(Color.diarySecondary)
            Button("Export diary and photos") {
                guard let token = model.selection else { return }
                Task {
                    do {
                        let request = try await model.store.exportRequest(expectedProfileID: token.identity.profileID)
                        let ticket = try await model.exportCoordinator.makeClone(request)
                        do {
                            let data = try await model.exportCoordinator.archiveData(ticket)
                            try await model.exportCoordinator.release(ticket)
                            guard model.selection == token else { return }
                            exportDocument = DiaryExportDocument(data: data); exportPicker = true
                        } catch { try? await model.exportCoordinator.release(ticket); throw error }
                    } catch { model.errorMessage = "Could not prepare an export. Your local diary is preserved." }
                }
            }.frame(minHeight: 44)
            if exported { Label("Export saved", systemImage: "checkmark.circle").font(.subheadline) }
            }
            Button("Restore from diary archive") { importPicker = true }.frame(minHeight: 44).disabled(importing)
            if importing { ProgressView("Reading archive") }
        }
        .fileImporter(isPresented: $folderPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await model.selectBackupFolder(url) }
            case .failure: model.errorMessage = "Could not choose this backup folder. Your local diary is preserved."
            }
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
        .fileExporter(isPresented: $exportPicker, document: exportDocument, contentType: .json, defaultFilename: "Mivu-private-diary") { result in
            switch result {
            case .success: exported = true
            case .failure: model.errorMessage = "Export was not saved. Your local diary is preserved."
            }
        }
        .confirmationDialog("Restore \(imported?.profile.name ?? "this private diary")?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore diary", role: .destructive) { if let archive = imported { Task { if await model.importArchive(archive) { imported = nil } } } }
            Button("Cancel", role: .cancel) { imported = nil }
        } message: {
            if imported?.profile.id == model.readModel?.profile.id { Text("Replace \(model.readModel?.profile.name ?? "the selected profile") with \(imported?.profile.name ?? "the validated archive") (\(imported?.meals.count ?? 0) meals). Older or deleted records cannot overwrite newer changes.") }
            else { Text("Import \(imported?.profile.name ?? "the archived profile") (\(imported?.meals.count ?? 0) meals) as a separate private local diary. The selected profile is preserved.") }
        }
    }
}
