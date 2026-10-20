import Foundation
import Testing
@testable import Mivu

@Suite struct CoachReplyTests {
    private static let mealReply = CoachReply(target: .meal(UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!),
                                              excerpt: "Toast · Breakfast, Tue 14 Oct")

    @Test func replyPersistsWithTurnAndPage() async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        let head = try await store.selectPagedProfile(f.profileID)
        let owner = try await store.selectionOwnership(expectedProfileID: f.profileID)
        let payload = try f.payload(head: head, reply: Self.mealReply)
        let accepted = try await store.captureCoachSubmission(payload, expectedSelection: owner, expectedProfileID: f.profileID)
        #expect(accepted.reply == Self.mealReply)
        let relaunched = DiaryStore(directory: f.root)
        _ = try await relaunched.selectPagedProfile(f.profileID)
        let page = try await relaunched.coachPage(.latest, expectedProfileID: f.profileID)
        #expect(page.exchanges.last?.reply == Self.mealReply)
        #expect(page.exchanges.dropLast().allSatisfy { $0.reply == nil })
    }

    @Test func replyIsPartOfImmutableCapture() async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        let head = try await store.selectPagedProfile(f.profileID)
        let owner = try await store.selectionOwnership(expectedProfileID: f.profileID)
        let id = UUID()
        _ = try await store.captureCoachSubmission(try f.payload(head: head, id: id, reply: Self.mealReply),
                                                   expectedSelection: owner, expectedProfileID: f.profileID)
        let other = try f.payload(head: head, id: id, reply: CoachReply(target: .day(UUID()), excerpt: "Tue 14 Oct"))
        #expect(try await store.reconcileCoachCapture(submissionID: id, expectedManifest: other.manifest,
            expectedSelection: owner, expectedProfileID: f.profileID) == .conflictingPayload)
        let plain = try f.payload(head: head, id: id)
        #expect(try await store.reconcileCoachCapture(submissionID: id, expectedManifest: plain.manifest,
            expectedSelection: owner, expectedProfileID: f.profileID) == .conflictingPayload)
    }

    @Test(arguments: [String(repeating: "a", count: 281), "  \n "])
    func replyExcerptIsBounded(_ excerpt: String) async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let head = try await DiaryStore(directory: f.root).selectPagedProfile(f.profileID)
        #expect(throws: DiaryError.invalidData) {
            try f.payload(head: head, reply: CoachReply(target: .day(UUID()), excerpt: excerpt))
        }
        #expect(try f.payload(head: head, reply: CoachReply(target: .day(UUID()), excerpt: String(repeating: "a", count: 280))).manifest.reply != nil)
    }

    @Test func archiveRoundTripsReply() async throws {
        let f = try CaptureFixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root)
        let head = try await store.selectPagedProfile(f.profileID)
        let owner = try await store.selectionOwnership(expectedProfileID: f.profileID)
        _ = try await store.captureCoachSubmission(try f.payload(head: head, reply: Self.mealReply),
                                                   expectedSelection: owner, expectedProfileID: f.profileID)
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let ticket = try await coordinator.makeClone(try await store.exportRequest(expectedProfileID: f.profileID))
        let snapshot = try await coordinator.completeSnapshot(ticket)
        let decoded = try DiaryArchive.decode(DiaryArchive.encode(snapshot), expectedProfileID: f.profileID)
        #expect(decoded.coachTurns.last?.submissionManifest?.reply == Self.mealReply)
        var invalid = snapshot
        invalid.coachTurns[invalid.coachTurns.count - 1].submissionManifest?.reply?.excerpt = String(repeating: "a", count: 281)
        #expect(throws: DiaryError.invalidData) { try DiaryArchive.decode(DiaryArchive.encode(invalid)) }
    }
}
