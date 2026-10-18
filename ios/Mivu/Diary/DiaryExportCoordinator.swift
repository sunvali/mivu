import Foundation
import SQLite3

struct DiaryExportRequest: Sendable {
    let operationID: UUID
    let profileID: UUID
    let head: DiaryHead
    let selectionEpoch: UInt64
    let sourceURL: URL
    let sourceFileIdentity: UInt64
    let backupGeneration: UUID?
    let storageVersion: Int
    let maximumBytes: Int
}

struct DiaryExportTicket: Sendable {
    let request: DiaryExportRequest
    let protectedCloneURL: URL
    let head: DiaryHead
}

struct DiaryPreparedReplacement: Sendable {
    let request: DiaryExportRequest
    let originalHead: DiaryHead
    let protectedDatabaseURL: URL
    let head: DiaryHead
    let legacySnapshot: DiarySnapshot?
}

enum DiaryExportStage: Equatable, Sendable {
    case cloneCreated, cloneStep, cloneReady, serialization, serialized
    case providerWrite, providerWritten, acknowledgement, acknowledged, replacementBuild, replacementValidated
}

/// Owns explicit interchange work away from the live diary writer.
struct DiaryExportCoordinator: Sendable {
    let store: DiaryStore
    let temporaryDirectory: URL
    let pagesPerStep: Int32
    let checkpoint: @Sendable (DiaryExportStage, URL) async throws -> Void

    init(store: DiaryStore, temporaryDirectory: URL = .temporaryDirectory, pagesPerStep: Int32 = 64,
         checkpoint: @escaping @Sendable (DiaryExportStage, URL) async throws -> Void = { _, _ in }) {
        self.store = store; self.temporaryDirectory = temporaryDirectory
        self.pagesPerStep = pagesPerStep; self.checkpoint = checkpoint
    }

    func makeClone(_ request: DiaryExportRequest) async throws -> DiaryExportTicket {
        try Task.checkCancellation()
        try await store.validateExportRequest(request)
        let root = temporaryDirectory.appending(path: "diary-export-" + request.operationID.uuidString)
        let destination = root.appending(path: "diary.sqlite")
        var source: OpaquePointer?, target: OpaquePointer?, backup: OpaquePointer?
        var ownsRoot = false, handedOff = false
        defer {
            if let backup { sqlite3_backup_finish(backup) }
            sqlite3_close(target); sqlite3_close(source)
            if ownsRoot && !handedOff { try? FileManager.default.removeItem(at: root) }
        }
        try Self.checkCapacity(at: temporaryDirectory, source: request.sourceURL)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        ownsRoot = true
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: root.path)
        #endif
        guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw DiaryError.persistenceFailed
        }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: destination.path)
        #endif
        try await checkpoint(.cloneCreated, destination)
        try Task.checkCancellation()
        try await store.validateExportRequest(request)
        guard try Self.fileIdentity(request.sourceURL) == request.sourceFileIdentity,
              sqlite3_open_v2(request.sourceURL.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              try Self.fileIdentity(request.sourceURL) == request.sourceFileIdentity,
              sqlite3_open_v2(destination.path, &target, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let handle = sqlite3_backup_init(target, "main", source, "main") else { throw DiaryError.persistenceFailed }
        backup = handle
        var busyAttempts = 0
        while true {
            try Task.checkCancellation()
            try await store.validateExportRequest(request)
            let result = sqlite3_backup_step(handle, max(1, pagesPerStep))
            guard [SQLITE_OK, SQLITE_DONE, SQLITE_BUSY, SQLITE_LOCKED].contains(result) else { throw DiaryError.persistenceFailed }
            try await checkpoint(.cloneStep, destination)
            try Task.checkCancellation()
            try await store.validateExportRequest(request)
            if result == SQLITE_DONE { break }
            if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                busyAttempts += 1
                guard busyAttempts <= 100 else { throw DiaryError.persistenceFailed }
                try await Task.sleep(for: .milliseconds(10))
            } else { busyAttempts = 0; await Task.yield() }
        }
        let finished = sqlite3_backup_finish(handle); backup = nil
        guard finished == SQLITE_OK, sqlite3_close(target) == SQLITE_OK else { throw DiaryError.persistenceFailed }
        target = nil
        guard sqlite3_close(source) == SQLITE_OK else { throw DiaryError.persistenceFailed }
        source = nil
        let head = try DiaryArchive.cloneHead(at: destination, request: request)
        try await checkpoint(.cloneReady, destination)
        try Task.checkCancellation()
        try await store.validateExportRequest(request, cloneHead: head)
        handedOff = true
        return DiaryExportTicket(request: request, protectedCloneURL: destination, head: head)
    }

    func completeSnapshot(_ ticket: DiaryExportTicket) async throws -> DiarySnapshot {
        try Task.checkCancellation()
        return try DiaryArchive.completeSnapshot(at: ticket.protectedCloneURL, request: ticket.request)
    }

    func archiveData(_ ticket: DiaryExportTicket) async throws -> Data {
        try await archiveContent(ticket).data
    }

    func portableData(_ ticket: DiaryExportTicket) async throws -> Data {
        try await checkpoint(.serialization, ticket.protectedCloneURL)
        let data = try JSONEncoder().encode(try await completeSnapshot(ticket))
        try await checkpoint(.serialized, ticket.protectedCloneURL)
        try Task.checkCancellation()
        return data
    }

    func archiveContent(_ ticket: DiaryExportTicket) async throws -> (snapshot: DiarySnapshot, data: Data) {
        try await checkpoint(.serialization, ticket.protectedCloneURL)
        try Task.checkCancellation()
        let snapshot = try await completeSnapshot(ticket)
        let data = try DiaryArchive.encode(snapshot)
        try await checkpoint(.serialized, ticket.protectedCloneURL)
        try Task.checkCancellation()
        return (snapshot, data)
    }

    func release(_ ticket: DiaryExportTicket) async throws {
        let root = ticket.protectedCloneURL.deletingLastPathComponent()
        guard root.lastPathComponent == "diary-export-" + ticket.request.operationID.uuidString,
              root.deletingLastPathComponent().standardizedFileURL == temporaryDirectory.standardizedFileURL,
              ticket.protectedCloneURL.lastPathComponent == "diary.sqlite" else { throw DiaryError.wrongOwner }
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    func prepareReplacement(_ incoming: DiarySnapshot, replacing ticket: DiaryExportTicket) async throws -> DiaryPreparedReplacement {
        try Task.checkCancellation()
        try await store.validateExportRequest(ticket.request, cloneHead: ticket.head)
        let original = try await completeSnapshot(ticket)
        let replacement = try DiaryArchive.replacement(incoming, original: original)
        guard try JSONEncoder().encode(replacement).count <= ticket.request.maximumBytes else { throw DiaryError.invalidData }
        // Validated recovery must survive deletion of the original profile's directory.
        let root = ticket.request.sourceURL.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "diary-replacement-" + UUID().uuidString)
        let destination = root.appending(path: "diary.sqlite")
        var validated = false, ownsRoot = false
        defer { if ownsRoot && !validated { try? FileManager.default.removeItem(at: root) } }
        try Self.checkCapacity(at: root.deletingLastPathComponent(), source: ticket.request.sourceURL)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        ownsRoot = true
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: root.path)
        #endif
        try await checkpoint(.replacementBuild, destination)
        try Task.checkCancellation()
        do {
            let database = try DiaryDatabase(url: destination, create: true)
            try database.write(replacement, expected: nil, maximumBytes: ticket.request.maximumBytes)
            if ticket.request.storageVersion == 1 { try database.migrateForPagedStorage(maximumBytes: ticket.request.maximumBytes) }
        }
        guard try DiaryArchive.completeSnapshot(at: destination, request: ticket.request) == replacement else { throw DiaryError.invalidData }
        let head = try DiaryArchive.cloneHead(at: destination, request: ticket.request)
        validated = true
        try await checkpoint(.replacementValidated, destination)
        try Task.checkCancellation()
        return DiaryPreparedReplacement(request: ticket.request, originalHead: ticket.head,
            protectedDatabaseURL: destination, head: head, legacySnapshot: ticket.request.storageVersion == 0 ? replacement : nil)
    }

    private static func fileIdentity(_ url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let identity = attributes[.systemFileNumber] as? NSNumber else { throw DiaryError.persistenceFailed }
        return identity.uint64Value
    }

    private static func checkCapacity(at directory: URL, source: URL) throws {
        let bytes = (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? 0
        let walBytes = ((try? FileManager.default.attributesOfItem(atPath: source.path + "-wal"))?[.size] as? NSNumber)?.int64Value ?? 0
        let (physical, physicalOverflow) = bytes.addingReportingOverflow(walBytes)
        // Clone + inline portable output + fresh replacement + SQLite/atomic-write journals.
        let (copies, copiesOverflow) = physical.multipliedReportingOverflow(by: 5)
        let (required, requiredOverflow) = copies.addingReportingOverflow(65_536)
        guard bytes >= 0, walBytes >= 0, !physicalOverflow, !copiesOverflow, !requiredOverflow else { throw DiaryError.persistenceFailed }
        if let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let available = values.volumeAvailableCapacityForImportantUsage, available < required {
            throw DiaryError.persistenceFailed
        }
    }
}
