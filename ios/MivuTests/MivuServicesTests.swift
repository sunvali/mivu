import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct MivuServicesTests {
    @Test func startRunsOnceAndListsInboxForApproval() async throws {
        let path = URL.temporaryDirectory.appending(path: "MivuServices-" + UUID().uuidString)
        let inbox = CoachInbox(directory: URL.temporaryDirectory.appending(path: "MivuServicesInbox-" + UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: path); try? FileManager.default.removeItem(at: inbox.directory) }
        let store = DiaryStore(directory: path)
        let profile = try await store.createProfile(DiaryProfile(name: "Synthetic services"))
        try inbox.add(CoachInbox.Entry(id: UUID(), profileID: profile.head.profile.id, text: "Synthetic toast", capturedAt: Date(timeIntervalSinceNow: -60)))
        let diary = DiaryViewModel(store: store), connection = ChatGPTConnection(appleModelAvailable: { false })
        let coach = CoachViewModel(diary: diary, connection: connection,
                                   inference: { { _, _ in CoachInferenceResult(model: "fixture", text: "Synthetic guidance", calls: [], outputItems: []) } })
        let services = MivuServices(diary: diary, connection: connection, coach: coach, nutritionKeys: .local, inbox: inbox)

        async let first: Void = services.start(createDefaultProfile: false)
        async let second: Void = services.start(createDefaultProfile: false)
        _ = await (first, second)
        await coach.waitForWorker()

        #expect(diary.selection?.identity.profileID == profile.head.profile.id)
        #expect(coach.queuedSiri.map(\.text) == ["Synthetic toast"])
        #expect(try await store.snapshotForExport().coachTurns.isEmpty, "Nothing reaches the Coach before Send")
    }
}
