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
            if model.backupStatus.configured {
                if let date = model.backupStatus.savedAt {
                    Label("Saved to backup folder", systemImage: "checkmark.circle")
                    Text(date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(Color.diarySecondary)
                } else { Label("Backup pending", systemImage: "clock") }
                if model.backupStatus.pendingError != nil { Text("Backup pending. Check that the folder is available, then retry. Your local diary is saved.").font(.caption).foregroundStyle(Color.diarySecondary) }
                Button("Retry backup") { model.queueBackup() }.frame(minHeight: 44)
            } else { Text("No backup folder selected").foregroundStyle(Color.diarySecondary) }
            Button("Choose private backup folder") { folderPicker = true }.frame(minHeight: 44)
            Text("Choose a private Files folder, including iCloud Drive when available. Folder acknowledgement does not confirm remote upload.").font(.caption).foregroundStyle(Color.diarySecondary)
            Button("Export diary and photos") {
                guard let snapshot = model.snapshot else { return }
                do { exportDocument = DiaryExportDocument(data: try DiaryArchive.encode(snapshot)); exportPicker = true }
                catch { model.errorMessage = "Could not prepare an export. Your local diary is preserved." }
            }.frame(minHeight: 44)
            if exported { Label("Export saved", systemImage: "checkmark.circle").font(.caption) }
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
                        guard !model.profiles.contains(where: { $0.id == archive.profile.id }) || model.snapshot?.profile.id == archive.profile.id else {
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
        .confirmationDialog("Restore this private diary?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore diary", role: .destructive) { if let archive = imported { Task { if await model.importArchive(archive) { imported = nil } } } }
            Button("Cancel", role: .cancel) { imported = nil }
        } message: {
            if imported?.profile.id == model.snapshot?.profile.id { Text("This replaces the selected profile with the validated archive. Older or deleted records cannot overwrite newer changes.") }
            else { Text("This imports the archived profile as a separate private local diary. The selected profile is preserved.") }
        }
    }
}
