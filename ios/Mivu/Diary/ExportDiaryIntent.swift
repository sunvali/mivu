import AppIntents
import UIKit
import UniformTypeIdentifiers

/// Shortcuts receives portable files only; whole-Documents sharing stays disabled on upgrades.
enum DiaryTransferFormat: String, AppEnum {
    case archive, pdf, csv
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Diary export format"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .archive: "Diary and photos", .pdf: "PDF report", .csv: "CSV reports"
    ]
}

enum DiaryTransfer {
    static func files(store: DiaryStore, owner: DiarySelectionOwnership, format: DiaryTransferFormat,
                      layout: LocalDiaryFiles, checkpoint: @Sendable ([URL]) async throws -> Void = { _ in }) async throws -> [URL] {
        try await store.validateSelectionOwnership(owner)
        let snapshot = try await store.snapshotForExport(expectedProfileID: owner.identity.profileID)
        try await store.validateSelectionOwnership(owner)
        let output: [URL]
        switch format {
        case .archive:
            let data = try DiaryArchive.encode(snapshot)
            output = [try layout.writeArchive(data, profileID: owner.identity.profileID)]
        case .pdf, .csv:
            let folder = layout.exports.appending(path: owner.identity.profileID.uuidString).appending(path: UUID().uuidString)
            output = try DiaryReport(snapshot, from: nil, through: nil).write(format == .pdf ? .pdf : .csv,
                to: folder, allowedRoot: layout.exports)
        }
        do {
            try await checkpoint(output)
            // The selected profile can change while output files are being prepared.
            try await store.validateSelectionOwnership(owner)
        }
        catch { for file in output { try? FileManager.default.removeItem(at: file) }; throw error }
        return output
    }
}

struct ExportDiaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Diary"
    static let description = IntentDescription("Creates portable copies of the selected diary. Transfer the returned files yourself using Shortcuts.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Format", default: .archive) var format: DiaryTransferFormat

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> & ProvidesDialog {
        guard UIApplication.shared.isProtectedDataAvailable else { throw DiaryError.persistenceFailed }
        let services = MivuServices.shared
        await services.loadDiary(createDefaultProfile: false)
        guard !services.diary.isChangingProfile, let owner = services.diary.selection else { throw DiaryError.noProfile }
        let urls = try await DiaryTransfer.files(store: services.diary.store, owner: owner, format: format, layout: .local)
        guard services.diary.selection == owner, !services.diary.isChangingProfile else {
            for url in urls { try? FileManager.default.removeItem(at: url) }
            throw DiaryError.wrongOwner
        }
        let files = urls.map { IntentFile(fileURL: $0, filename: $0.lastPathComponent, type: UTType(filenameExtension: $0.pathExtension)) }
        return .result(value: files, dialog: "Portable copies are ready. Transfer them from Shortcuts to another device for recovery.")
    }
}
