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

@Suite @MainActor struct CoachReplyComposerTests {
    private static let dayReply = CoachReply(target: .day(UUID()), excerpt: "Tue 14 Oct")

    @Test func sendAttachesReplyAndClears() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let draft = CoachAttachmentDraft(ownership: try #require(f.diary.selection), limiter: f.diary.photoWorkLimiter,
            dependencies: Task10Fixture.dependencies(f.diary), text: "Was this right?")
        draft.reply = Self.dayReply
        let accepted = try #require(try await draft.send())
        #expect(accepted.reply == Self.dayReply && draft.reply == nil && draft.text.isEmpty)
    }

    @Test func uncertainRetryKeepsFrozenReply() async throws {
        let once = Task10Once(), f = try await Task10Fixture.make(); defer { f.remove() }
        var dependencies = Task10Fixture.dependencies(f.diary)
        let capture = dependencies.capture
        dependencies.capture = { payload, owner in
            if await once.claim() { throw DiaryError.persistenceFailed }
            return try await capture(payload, owner)
        }
        let draft = CoachAttachmentDraft(ownership: try #require(f.diary.selection), limiter: f.diary.photoWorkLimiter,
            dependencies: dependencies, text: "About this day")
        draft.reply = Self.dayReply
        let id = draft.submissionID
        await #expect(throws: DiaryError.persistenceFailed) { _ = try await draft.send() }
        #expect(draft.reply == Self.dayReply)
        let accepted = try #require(try await draft.send())
        #expect(accepted.id == id && accepted.reply == Self.dayReply)
    }

    @Test func profileChangeClearsReply() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let draft = CoachAttachmentDraft(ownership: try #require(f.diary.selection), limiter: f.diary.photoWorkLimiter,
            dependencies: Task10Fixture.dependencies(f.diary))
        draft.reply = Self.dayReply
        draft.synchronizeOwnership(Task10Fixture.ownership())
        #expect(draft.reply == nil)
    }

    @Test func queuedReplyReachesRequest() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let owner = try #require(f.diary.selection), routes = CoachNavigationOwner()
        routes.synchronize(selection: owner, isChangingProfile: false)
        let origin = try #require(routes.origin(selection: owner, isChangingProfile: false))
        #expect(routes.queue(nil, reply: Self.dayReply, from: origin, selection: owner, isChangingProfile: false))
        #expect(routes.request?.reply == Self.dayReply && routes.request?.draft == nil)
    }

    @Test func navigationReplyNeverReplacesInProgressDraft() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection()); defer { coach.cancel() }
        #expect(coach.startReply(Self.dayReply) && coach.attachmentDraft.reply == Self.dayReply)
        let other = CoachReply(target: .meal(UUID()), excerpt: "Toast · Breakfast")
        #expect(!coach.startReply(other) && coach.attachmentDraft.reply == Self.dayReply)
        coach.attachmentDraft.reply = nil; coach.draft.text = "two eggs"
        #expect(!coach.startReply(other) && coach.attachmentDraft.reply == nil)
    }

    @Test func messageExcerptUsesTextOrPhoto() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection()); defer { coach.cancel() }
        let turn = CoachTimelineTestData.row(1)
        var long = turn; long.assistantText = String(repeating: "b", count: 400)
        coach.reply(to: long, fromPip: true)
        #expect(coach.attachmentDraft.reply == CoachReply(target: .message(turnID: turn.id, fromPip: true), excerpt: String(repeating: "b", count: 280)))
        var photoOnly = turn; photoOnly.text = ""
        coach.reply(to: photoOnly, fromPip: false)
        #expect(coach.attachmentDraft.reply?.excerpt == "Photo")
    }
}
