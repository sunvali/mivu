import Foundation
import Observation

struct MealDraft {
    let submissionID = UUID()
    var text = ""
    var photos: [Data] = []
    var reviewFirst = false
    var isValid: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty }
}

@MainActor @Observable
final class DiaryViewModel {
    let store: DiaryStore
    private let preferences: UserDefaults?
    let backup: FolderBackup?
    var backupStatus = FolderBackupStatus()
    private var backupTask: Task<Void, Never>?
    private var backupGeneration: UUID?
    var snapshot: DiarySnapshot?
    var profiles: [DiaryProfile] = []
    var errorMessage: String?
    var isSaving = false
    private(set) var captureReceipt: UUID?
    var restoreGeneration = 0
    private var worker: Task<Void, Never>?
    private var workerID: UUID?

    init(store: DiaryStore, preferences: UserDefaults? = nil, backup: FolderBackup? = nil) { self.store = store; self.preferences = preferences; self.backup = backup }

    static func local() -> DiaryViewModel {
        let directory = DiaryLaunch.directory
        return DiaryViewModel(store: DiaryStore(directory: directory), preferences: DiaryLaunch.defaults, backup: FolderBackup(directory: directory.deletingLastPathComponent().appending(path: DiaryLaunch.isUITest ? "BackupSettings-" + (DiaryLaunch.testID?.uuidString ?? "test") : "BackupSettings", directoryHint: .isDirectory)))
    }

    var activeDay: TrackingDay? { snapshot?.days.first { $0.id == snapshot?.activeDayID } }
    var todaysMeals: [DiaryMeal] { snapshot?.meals.filter { $0.dayID == activeDay?.id }.sorted { $0.capturedAt > $1.capturedAt } ?? [] }
    func meal(_ id: UUID) -> DiaryMeal? { snapshot?.meals.first { $0.id == id } }

    func load() async {
        do {
            profiles = try await store.profiles()
            if preferences?.bool(forKey: "diarySignedOut") == true { return }
            if snapshot == nil, !profiles.isEmpty {
                let selectedID = preferences?.string(forKey: "diarySelectedProfile").flatMap(UUID.init(uuidString:))
                let profile = profiles.first { $0.id == selectedID } ?? profiles[0]
                snapshot = try await store.selectProfile(profile.id)
            } else if profiles.isEmpty {
                snapshot = try await store.createProfile(DiaryProfile(name: String(localized: "My diary"), language: DiaryLaunch.language))
                profiles = try await store.profiles()
            }
            rememberSelection()
            await selectBackupProfile()
            queueBackup()
            resumeWorker()
        } catch { present(error) }
    }

    func refresh(profileID: UUID) async throws {
        let updated = try await store.snapshot(expectedProfileID: profileID)
        guard snapshot?.profile.id == profileID else { return }
        snapshot = updated
        if let index = profiles.firstIndex(where: { $0.id == profileID }) { profiles[index] = updated.profile }
        else { profiles.append(updated.profile) }
        queueBackup()
    }

    @discardableResult
    func change(_ operation: () async throws -> Void) async -> Bool {
        guard let owner = snapshot?.profile.id else { return false }
        do {
            try await operation()
            try await refresh(profileID: owner)
            return true
        } catch { if snapshot?.profile.id == owner { present(error) }; return false }
    }

    func capture(_ draft: MealDraft, dayID: UUID, at: Date = Date(), photoPreparation: PhotoPreparation? = nil) async -> Bool {
        guard draft.isValid, photoPreparation?.canCapture != false, !isSaving, let owner = snapshot?.profile.id else { return false }
        let isNewSubmission = snapshot?.meals.contains { $0.submissions.contains { $0.id == draft.submissionID } } != true
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await store.capture(text: draft.text, photos: draft.photos.map { MealPhoto(data: $0) }, reviewFirst: draft.reviewFirst, dayID: dayID, at: at, submissionID: draft.submissionID, expectedProfileID: owner)
            try await refresh(profileID: owner)
            guard snapshot?.profile.id == owner else { return false }
            if isNewSubmission { captureReceipt = draft.submissionID }
            resumeWorker()
            return true
        } catch { if snapshot?.profile.id == owner { present(error) }; return false }
    }

    func switchProfile(_ id: UUID) async {
        enterBackground()
        snapshot = nil
        do { snapshot = try await store.selectProfile(id); rememberSelection(); await selectBackupProfile(); queueBackup(); resumeWorker() } catch { present(error) }
    }

    func createProfile(name: String) async {
        enterBackground()
        do {
            snapshot = try await store.createProfile(DiaryProfile(name: name))
            profiles = try await store.profiles()
            rememberSelection()
            await selectBackupProfile()
            queueBackup()
        } catch { present(error) }
    }

    func signOut() async {
        enterBackground(); snapshot = nil; preferences?.set(true, forKey: "diarySignedOut")
        preferences?.removeObject(forKey: "diarySelectedProfile")
        backupTask?.cancel()
        backupGeneration = nil
        await backup?.selectProfile(nil)
        backupStatus = FolderBackupStatus()
        await store.signOut()
    }
    func deleteCurrentProfile() async {
        guard let owner = snapshot?.profile.id else { return }
        enterBackground()
        do {
            try await backup?.removeProfile(owner)
            try await store.deleteProfile(owner)
            await signOut()
            profiles = try await store.profiles()
        } catch { present(error) }
    }
    private func rememberSelection() {
        guard let id = snapshot?.profile.id else { return }
        preferences?.set(id.uuidString, forKey: "diarySelectedProfile")
        preferences?.set(false, forKey: "diarySignedOut")
    }
    func loadProfiles() async { do { profiles = try await store.profiles() } catch { present(error) } }
    func waitForWorker() async { await worker?.value }
    func waitForBackup() async { await backupTask?.value }
    private func selectBackupProfile() async {
        backupTask?.cancel()
        backupGeneration = nil
        await backup?.selectProfile(snapshot?.profile.id)
        if let owner = snapshot?.profile.id, let backup {
            do { backupGeneration = try await backup.generation(profileID: owner) }
            catch { backupStatus = await backup.status(profileID: owner); backupStatus.pendingError = "Backup pending"; return }
            backupStatus = await backup.status(profileID: owner)
        } else { backupStatus = FolderBackupStatus() }
    }
    func queueBackup() {
        guard let backup, let captured = snapshot, let generation = backupGeneration else { return }
        backupTask?.cancel()
        backupTask = Task {
            let status = await backup.status(profileID: captured.profile.id)
            guard !Task.isCancelled, snapshot?.profile.id == captured.profile.id else { return }
            if status.configured {
                do { try await backup.save(captured, generation: generation) }
                catch {
                    guard !Task.isCancelled, snapshot?.profile.id == captured.profile.id else { return }
                    backupStatus = await backup.status(profileID: captured.profile.id)
                    if backupStatus.pendingError == nil { backupStatus.pendingError = "Backup pending" }
                    return
                }
            }
            guard !Task.isCancelled, snapshot?.profile.id == captured.profile.id else { return }
            backupStatus = await backup.status(profileID: captured.profile.id)
        }
    }
    func selectBackupFolder(_ url: URL) async {
        guard let backup, let owner = snapshot?.profile.id else { return }
        do {
            try await backup.selectFolder(url, profileID: owner)
            guard snapshot?.profile.id == owner else { return }
            backupGeneration = try await backup.generation(profileID: owner)
            backupStatus = await backup.status(profileID: owner)
            queueBackup()
        } catch { errorMessage = "Could not choose this backup folder. Your local diary is preserved." }
    }
    func importArchive(_ archive: DiarySnapshot) async -> Bool {
        enterBackground()
        do {
            if profiles.contains(where: { $0.id == archive.profile.id }) {
                guard snapshot?.profile.id == archive.profile.id else { throw DiaryError.wrongOwner }
                try await store.restore(archive, expectedProfileID: archive.profile.id)
                try await refresh(profileID: archive.profile.id)
            } else {
                snapshot = try await store.importProfile(archive)
                profiles = try await store.profiles()
                rememberSelection()
                await backup?.selectProfile(archive.profile.id)
                if let backup {
                    do {
                        backupGeneration = try await backup.authorizeRestoredProfile(archive.profile.id)
                        backupStatus = await backup.status(profileID: archive.profile.id)
                    } catch { backupGeneration = nil; backupStatus = FolderBackupStatus(pendingError: "Backup pending") }
                }
                queueBackup()
            }
            restoreGeneration += 1
            resumeWorker()
            return true
        } catch { present(error); return false }
    }
    func enterBackground() { worker?.cancel(); worker = nil; workerID = nil }
    func resumeWorker() {
        guard worker == nil, let owner = snapshot?.profile.id else { return }
        let id = UUID()
        workerID = id
        worker = Task {
            defer { if workerID == id { worker = nil; workerID = nil } }
            do {
                try Task.checkCancellation()
                try await store.processPending(expectedProfileID: owner)
                try Task.checkCancellation()
                try await refresh(profileID: owner)
            } catch is CancellationError {} catch { if snapshot?.profile.id == owner { present(error) } }
        }
    }

    private func present(_ error: Error) {
        switch error as? DiaryError {
        case .persistenceFailed: errorMessage = "Could not save on this iPhone. Your input is still here."
        case .staleRevision: errorMessage = "This meal changed. Open it again before editing."
        case .ambiguousDay: errorMessage = "Choose the tracking day before saving."
        case .staleArchive: errorMessage = "This backup is older or contains deleted meals. It cannot replace this diary."
        case .wrongOwner: errorMessage = "The active profile changed. Try again in this profile."
        default: errorMessage = "Could not complete this action. Your saved diary is unchanged."
        }
    }
}

@MainActor enum DiaryLaunch {
    static var testID: UUID? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--diary-ui-test"), args.indices.contains(index + 1) else { return nil }
        return UUID(uuidString: args[index + 1])
    }
    static var isUITest: Bool { testID != nil }
    static var defaults: UserDefaults {
        if let id = testID, let defaults = UserDefaults(suiteName: "MivuUITest-" + id.uuidString) { return defaults }
        return .standard
    }
    static var language: String {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--proof-hebrew") { return "he" }
        if args.contains("--proof-english") { return "en" }
        return defaults.string(forKey: "appLanguage") ?? "en"
    }
    static var directory: URL {
        if let id = testID { return URL.temporaryDirectory.appending(path: "MivuUITest-" + id.uuidString, directoryHint: .isDirectory) }
        return URL.documentsDirectory.appending(path: "Diary", directoryHint: .isDirectory)
    }
}

@MainActor @Observable final class PhotoPreparation {
    private(set) var isPreparing = false
    private var generation: UUID?
    private var active = true
    var canCapture: Bool { active && !isPreparing }
    func begin() -> UUID {
        let id = UUID()
        guard active else { return id }
        generation = id; isPreparing = true
        return id
    }
    func isCurrent(_ id: UUID) -> Bool { generation == id && isPreparing }
    func load(_ id: UUID, using operation: () async throws -> Data) async throws -> Data? {
        guard isCurrent(id), !Task.isCancelled else { return nil }
        let data = try await operation()
        return isCurrent(id) && !Task.isCancelled ? data : nil
    }
    func finish(_ id: UUID) { if generation == id { generation = nil; isPreparing = false } }
    func cancel() { active = false; generation = nil; isPreparing = false }
}

struct DiaryPreferencesDraft {
    var timezone = "Asia/Jerusalem"
    var preferences = ""
    private var profileID: UUID?
    private var synchronizedRestoreGeneration: Int?
    mutating func synchronize(_ profile: DiaryProfile?, restoreGeneration: Int) {
        guard profileID != profile?.id || synchronizedRestoreGeneration != restoreGeneration else { return }
        profileID = profile?.id; synchronizedRestoreGeneration = restoreGeneration
        timezone = profile?.timeZoneID ?? "Asia/Jerusalem"
        preferences = profile?.preferences ?? ""
    }
    func applying(to profile: DiaryProfile) -> DiaryProfile {
        var updated = profile; updated.timeZoneID = timezone; updated.preferences = preferences
        return updated
    }
}
