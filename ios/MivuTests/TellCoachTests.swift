import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct TellCoachTests {
    private struct Fixture {
        let services: MivuServices
        let inbox: CoachInbox
        let defaults: UserDefaults
        let profileID: UUID
        let paths: [URL]
        func clean() { paths.forEach { try? FileManager.default.removeItem(at: $0) } }
    }
    private func fixture(dependencies: ((DiaryStore) -> CoachAttachmentDraft.Dependencies)? = nil,
                         restore: (@MainActor (DiaryStore) async -> Void)? = nil) async throws -> Fixture {
        let path = URL.temporaryDirectory.appending(path: "TellCoach-" + UUID().uuidString)
        let inbox = CoachInbox(directory: URL.temporaryDirectory.appending(path: "TellCoachInbox-" + UUID().uuidString))
        let suite = "TellCoachTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = DiaryStore(directory: path)
        let profile = try await store.createProfile(DiaryProfile(name: "Synthetic Siri"))
        let diary = DiaryViewModel(store: store), connection = ChatGPTConnection(appleModelAvailable: { false })
        let inference: () throws -> CoachViewModel.Inference = { { _, _ in CoachInferenceResult(model: "fixture", text: "Synthetic guidance", calls: [], outputItems: []) } }
        let attachmentDependencies: CoachAttachmentDraft.Dependencies? = dependencies?(store)
        let coach = CoachViewModel(diary: diary, connection: connection, inference: inference, attachmentDependencies: attachmentDependencies)
        var restoreConnection: (@MainActor () async -> Void)? = nil
        if let restore { restoreConnection = { await restore(store) } }
        let services = MivuServices(diary: diary, connection: connection, coach: coach, nutritionKeys: .local, inbox: inbox,
                                    restore: restoreConnection)
        return Fixture(services: services, inbox: inbox, defaults: defaults, profileID: profile.head.profile.id, paths: [path, inbox.directory])
    }
    private func turns(_ f: Fixture) async throws -> [CoachTurn] { try await f.services.diary.store.snapshotForExport().coachTurns }
    private func run(_ text: String, _ f: Fixture, locked: Bool = false, appActive: Bool = false, now: Date = Date(),
                     onBackgroundCapture: @escaping @MainActor (UUID) -> Void = { _ in }) async -> TellCoachOutcome {
        await TellCoach.run(text, services: f.services, defaults: f.defaults, protectedDataAvailable: !locked,
                            appActive: appActive, now: now, onBackgroundCapture: onBackgroundCapture)
    }

    @Test func lockedWritesInboxEntry() async throws {
        let f = try await fixture(); defer { f.clean() }
        f.defaults.set(f.profileID.uuidString, forKey: "diarySelectedProfile")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(await run("Synthetic eggs", f, locked: true, now: now) == .savedLocked)
        let entry = try #require(f.inbox.entries().first)
        #expect(f.inbox.entries().count == 1)
        #expect(entry.profileID == f.profileID && entry.text == "Synthetic eggs" && entry.capturedAt == now)
        #expect(f.services.diary.readModel == nil, "A locked run never opens the diary")
    }
    @Test func lockedWithoutProfileNeedsSetup() async throws {
        let f = try await fixture(); defer { f.clean() }
        #expect(await run("Synthetic eggs", f, locked: true) == .needsSetup)
        f.defaults.set(f.profileID.uuidString, forKey: "diarySelectedProfile"); f.defaults.set(true, forKey: "diarySignedOut")
        #expect(await run("Synthetic eggs", f, locked: true) == .needsSetup)
        #expect(f.inbox.entries().isEmpty)
    }
    @Test func unlockedCapturesTurn() async throws {
        let f = try await fixture(); defer { f.clean() }
        #expect(await run("Synthetic eggs", f) == .savedNeedsConnection)
        await f.services.coach.waitForWorker()
        #expect(try await turns(f).map(\.text) == ["Synthetic eggs"])
    }
    @Test func unlockedLeavesLockedQueueForApproval() async throws {
        let f = try await fixture(); defer { f.clean() }
        try f.inbox.add(CoachInbox.Entry(id: UUID(), profileID: f.profileID, text: "Synthetic toast", capturedAt: Date(timeIntervalSinceNow: -60)))
        _ = await run("Synthetic eggs", f)
        await f.services.coach.waitForWorker()
        #expect(f.inbox.entries().map(\.text) == ["Synthetic toast"])
        #expect(try await turns(f).map(\.text) == ["Synthetic eggs"])
    }
    @Test func foregroundRunOnlyResumes() async throws {
        let f = try await fixture(); defer { f.clean() }
        var handedOff: [UUID] = []
        _ = await run("Synthetic eggs", f, appActive: true) { handedOff.append($0) }
        #expect(handedOff.isEmpty)
    }
    @Test func backgroundRunHandsOffTurn() async throws {
        let f = try await fixture(); defer { f.clean() }
        var handedOff: [UUID] = []
        _ = await run("Synthetic eggs", f, appActive: false) { handedOff.append($0) }
        await f.services.coach.waitForWorker()
        #expect(handedOff == (try await turns(f).map(\.id)))
        #expect(handedOff.count == 1)
    }
    @Test func blankTextFails() async throws {
        let f = try await fixture(); defer { f.clean() }
        f.defaults.set(f.profileID.uuidString, forKey: "diarySelectedProfile")
        #expect(await run("  ", f, locked: true) == .failed)
        #expect(await run("  ", f) == .failed)
        #expect(f.inbox.entries().isEmpty)
        #expect(try await turns(f).isEmpty)
    }
    @Test func dialogCopyIsExact() {
        #expect(TellCoachOutcome.sent.dialog == "Sent to the Coach.")
        #expect(TellCoachOutcome.savedLocked.dialog == "Saved. Open Mivu after you unlock to see the Coach's reply.")
        #expect(TellCoachOutcome.savedNeedsConnection.dialog == "Saved. Open Mivu to connect the Coach.")
        #expect(TellCoachOutcome.needsSetup.dialog == "Open Mivu to finish setup first.")
        #expect(TellCoachOutcome.failed.dialog == "I couldn't save that. Please try again.")
    }
    @Test func overlongTextFails() async throws {
        let f = try await fixture(); defer { f.clean() }
        f.defaults.set(f.profileID.uuidString, forKey: "diarySelectedProfile")
        let long = String(repeating: "a", count: 20_001)
        #expect(await run(long, f, locked: true) == .failed)
        #expect(await run(long, f) == .failed)
        #expect(f.inbox.entries().isEmpty)
        #expect(try await turns(f).isEmpty)
    }
    @Test func savesBeforeRestoringConnection() async throws {
        var turnsAtRestore: Int?
        let f = try await fixture(restore: { store in turnsAtRestore = (try? await store.snapshotForExport().coachTurns.count) ?? -1 })
        defer { f.clean() }
        _ = await run("Synthetic eggs", f)
        #expect(turnsAtRestore == 1, "The message is stored before the network-bound connection restore")
    }
    @Test func uncertainSaveIsReconciledNotFailed() async throws {
        let calls = Counter()
        let f = try await fixture(dependencies: { store in
            var dependencies = CoachAttachmentDraft.Dependencies(store: store)
            let validate = dependencies.validate
            // The third check runs right after the capture commits; failing it once leaves the save uncertain.
            dependencies.validate = { owner in
                if await calls.next() == 3 { throw CancellationError() }
                try await validate(owner)
            }
            return dependencies
        })
        defer { f.clean() }
        #expect(await run("Synthetic eggs", f) == .savedNeedsConnection)
        await f.services.coach.waitForWorker()
        #expect(try await turns(f).map(\.text) == ["Synthetic eggs"])
    }
}

private actor Counter {
    private var value = 0
    func next() -> Int { value += 1; return value }
}
