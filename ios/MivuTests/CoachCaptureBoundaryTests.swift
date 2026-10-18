import Foundation
import Testing
@testable import Mivu

@Suite struct CoachCaptureBoundaryTests {
    @Test func inferredEmptyBoundarySkipsOccupiedUUIDWithoutPersistingIt() throws {
        var snapshot = ChatHistoryFixture.snapshot(exchanges: 1)
        snapshot.coachTurns[0].activeDayID = snapshot.days[1].id
        let calibration = try CaptureFixture(snapshot: snapshot); defer { calibration.remove() }
        let candidateHead = try DiaryDatabase(url: calibration.url).readHead(expectedProfileID: calibration.profileID)
        let candidate = try #require(candidateHead.effectiveConversationSegmentID)
        snapshot.coachTurns[0].captureSegmentID = candidate
        let fixture = try CaptureFixture(snapshot: snapshot); defer { fixture.remove() }
        try fixture.execute("UPDATE storage_head SET timelineGeneration = '\(candidateHead.timelineGeneration.uuidString)'")
        let before = try fixture.durableState()
        let database = try DiaryDatabase(url: fixture.url)
        let resolved = try database.readHead(expectedProfileID: fixture.profileID)
        #expect(resolved.activeConversationSegmentID == nil)
        #expect(resolved.effectiveConversationSegmentID != nil && resolved.effectiveConversationSegmentID != candidate)
        #expect(try database.readHead(expectedProfileID: fixture.profileID).effectiveConversationSegmentID == resolved.effectiveConversationSegmentID)
        #expect(try fixture.durableState() == before)
        #expect(try fixture.rows("SELECT segmentID FROM coach_segment") == [[candidate.uuidString]])
    }

    @Test func legacyEffectiveTokenSurvivesStatusAndTwoFrozenSubmissions() throws {
        let fixture = try CaptureFixture(); defer { fixture.remove() }
        let database = try DiaryDatabase(url: fixture.url)
        let legacy = try database.readHead(expectedProfileID: fixture.profileID)
        #expect(legacy.activeConversationSegmentID == nil)
        let token = try #require(legacy.effectiveConversationSegmentID)
        let first = try fixture.payload(head: legacy), second = try fixture.payload(head: legacy)
        let status = try database.updateCoachTurn(turnID: fixture.before.coachTurns[0].id, state: .waitingForNetwork,
            assistantText: nil, needsDayChoice: false, expected: legacy, maximumBytes: ChatHistoryFixture.maximumBytes)
        #expect(status.head.activeConversationSegmentID == nil && status.head.effectiveConversationSegmentID == token)
        #expect(try fixture.rows("SELECT activeConversationSegmentID IS NULL FROM storage_head") == [["1"]])
        let accepted = try database.captureCoachSubmission(first, expected: status.head, maximumBytes: ChatHistoryFixture.maximumBytes)
        #expect(accepted.head.activeConversationSegmentID == token && accepted.value.segmentID == token)
        let other = try database.captureCoachSubmission(second, expected: accepted.head, maximumBytes: ChatHistoryFixture.maximumBytes)
        #expect(other.value.segmentID == token && other.value.sequence == accepted.value.sequence + 1)
        let complete = try ChatHistoryFixture.completeReference(databaseURL: fixture.url)
        #expect(try fixture.rows("SELECT portableBytes FROM storage_quota") == [[String(try JSONEncoder().encode(complete).count)]])
    }

    @Test func emptyActiveBoundaryAppearsOnlyAtLatestAndDoesNotCreateHistory() throws {
        var snapshot = ChatHistoryFixture.snapshot(exchanges: 40)
        let emptyDay = TrackingDay(localDate: "2026-10-19", timeZoneID: snapshot.profile.timeZoneID,
            startAt: Date(timeIntervalSinceReferenceDate: 800_100_000))
        snapshot.days.append(emptyDay); snapshot.activeDayID = emptyDay.id
        let boundary = UUID(); snapshot.activeConversationSegmentID = boundary
        let fixture = try CaptureFixture(snapshot: snapshot); defer { fixture.remove() }
        let database = try DiaryDatabase(url: fixture.url)
        let latest = try database.coachPage(.latest, expectedProfileID: fixture.profileID)
        #expect(latest.latestEmptySegment == CoachEmptySegment(segmentID: boundary, trackingDayID: emptyDay.id,
            displayLocalDate: emptyDay.localDate, displayTimeZoneID: emptyDay.timeZoneID))
        let first = try database.coachPage(.aroundTurn(snapshot.coachTurns[0].id), expectedProfileID: fixture.profileID)
        #expect(first.hasLater && first.latestEmptySegment == nil)
        #expect(throws: CoachQueryError.noChatForDay(emptyDay.id)) { try database.coachPage(.atDay(emptyDay.id), expectedProfileID: fixture.profileID) }
        #expect(try database.coachDays(before: nil, expectedProfileID: fixture.profileID).segments.allSatisfy { $0.trackingDayID != emptyDay.id })
        #expect(try fixture.rows("SELECT COUNT(*) FROM coach_turn") == [["40"]])
    }

    @Test func firstCaptureRetainsPendingBoundaryAcrossRollbackAndRestart() async throws {
        var snapshot = ChatHistoryFixture.snapshot(exchanges: 0)
        let boundary = UUID(); snapshot.activeConversationSegmentID = boundary
        let fixture = try CaptureFixture(snapshot: snapshot); defer { fixture.remove() }
        let database = try DiaryDatabase(url: fixture.url)
        let head = try database.readHead(expectedProfileID: fixture.profileID)
        #expect(head.activeConversationSegmentID == boundary)
        let payload = try fixture.payload(head: head)
        let before = try fixture.durableState()
        let maximum = try #require(Int(fixture.rows("SELECT portableBytes FROM storage_quota")[0][0]))
        #expect(throws: DiaryError.invalidData) { try database.captureCoachSubmission(payload, expected: head, maximumBytes: maximum) }
        #expect(try fixture.durableState() == before)
        let store = DiaryStore(directory: fixture.root)
        _ = try await store.selectPagedProfile(fixture.profileID)
        let accepted = try await capturedSubmission(store, payload, expectedProfileID: fixture.profileID)
        #expect(accepted.segmentID == boundary)
        let reopened = try DiaryDatabase(url: fixture.url)
        let page = try reopened.coachPage(.latest, expectedProfileID: fixture.profileID)
        #expect(page.latestEmptySegment == nil && page.exchanges.map(\.segmentID) == [boundary])
        #expect(try reopened.readHead(expectedProfileID: fixture.profileID).activeConversationSegmentID == boundary)
        let complete = try ChatHistoryFixture.completeReference(databaseURL: fixture.url)
        #expect(complete.activeConversationSegmentID == boundary && complete.coachTurns[0].captureSegmentID == boundary)
        #expect(try fixture.rows("SELECT portableBytes FROM storage_quota") == [[String(try JSONEncoder().encode(complete).count)]])
    }

    @Test func returnedActiveDayRejectsFrozenPriorBoundaryAndPreservesOldSegment() async throws {
        var snapshot = ChatHistoryFixture.snapshot(exchanges: 1)
        let firstBoundary = UUID(), returnedBoundary = UUID()
        snapshot.coachTurns[0].captureSegmentID = firstBoundary
        // A1 populated -> B empty -> A2 empty: only current A2 and real A1 persist.
        snapshot.days.append(TrackingDay(localDate: "2026-10-19", timeZoneID: snapshot.profile.timeZoneID,
            startAt: Date(timeIntervalSinceReferenceDate: 800_100_000)))
        snapshot.activeConversationSegmentID = returnedBoundary
        let fixture = try CaptureFixture(snapshot: snapshot); defer { fixture.remove() }
        let store = DiaryStore(directory: fixture.root)
        let head = try await store.selectPagedProfile(fixture.profileID)
        var context = try fixture.payload(head: head).context; context.activeConversationSegmentID = firstBoundary
        let stale = try fixture.payload(head: head, context: context)
        await #expect(throws: DiaryError.staleRevision) { try await capturedSubmission(store, stale, expectedProfileID: fixture.profileID) }
        let captured = try await capturedSubmission(store, try fixture.payload(head: head), expectedProfileID: fixture.profileID)
        #expect(captured.segmentID == returnedBoundary)
        let page = try DiaryDatabase(url: fixture.url).coachPage(.latest, expectedProfileID: fixture.profileID)
        #expect(page.exchanges.map(\.segmentID) == [firstBoundary, returnedBoundary])
        #expect(try fixture.rows("SELECT COUNT(*) FROM coach_segment") == [["2"]])
    }

    @Test func acceptedRetryKeepsOriginalBoundaryAfterCurrentActivationChanges() async throws {
        var snapshot = ChatHistoryFixture.snapshot(exchanges: 0)
        let boundary = UUID(); snapshot.activeConversationSegmentID = boundary
        let fixture = try CaptureFixture(snapshot: snapshot); defer { fixture.remove() }
        let store = DiaryStore(directory: fixture.root)
        let head = try await store.selectPagedProfile(fixture.profileID)
        let payload = try fixture.payload(head: head, photos: [fixture.photo()])
        let accepted = try await capturedSubmission(store, payload, expectedProfileID: fixture.profileID)
        let next = UUID()
        try fixture.execute("UPDATE storage_head SET activeConversationSegmentID = '\(next.uuidString)'")
        let reopened = DiaryStore(directory: fixture.root)
        _ = try await reopened.selectPagedProfile(fixture.profileID)
        let retried = try await capturedSubmission(reopened, payload, expectedProfileID: fixture.profileID)
        #expect(retried == accepted && retried.segmentID == boundary)
        #expect(try await reconciledSubmission(reopened, submissionID: payload.submissionID,
            expectedManifest: payload.manifest, expectedProfileID: fixture.profileID) == .accepted(accepted))
        #expect(try fixture.rows("SELECT COUNT(*) FROM coach_turn") == [["1"]])
    }

    @Test func portableRebuildPreservesExplicitNonadjacentActivationBoundaries() throws {
        var snapshot = ChatHistoryFixture.snapshot(exchanges: 2)
        let first = UUID(), second = UUID()
        snapshot.coachTurns[0].captureSegmentID = first; snapshot.coachTurns[1].captureSegmentID = second
        snapshot.activeConversationSegmentID = second
        let roundTripped = try JSONDecoder().decode(DiarySnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(roundTripped == snapshot)
        let fixture = try CaptureFixture(snapshot: roundTripped); defer { fixture.remove() }
        let database = try DiaryDatabase(url: fixture.url)
        let page = try database.coachPage(.latest, expectedProfileID: fixture.profileID)
        #expect(page.exchanges.map(\.segmentID) == [first, second])
        #expect(try database.readHead(expectedProfileID: fixture.profileID).activeConversationSegmentID == second)
        #expect(try fixture.rows("SELECT COUNT(*) FROM coach_segment") == [["2"]])
    }
}
