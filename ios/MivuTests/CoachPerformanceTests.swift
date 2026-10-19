import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import Mivu

@Suite struct CoachPerformanceTests {
    @Test func historyLengthDoesNotIncreaseDecodedStartupOrWorkingSet() async throws {
        var samples: [DiaryQueryDiagnostics.Counters] = []
        var nonChat: DiarySnapshot?
        for count in [100, 10_000] {
            let source = try performanceSnapshot(exchanges: count)
            var constant = source; constant.coachTurns = []
            if let nonChat { #expect(constant == nonChat) } else { nonChat = constant }
            let fixture = try CaptureFixture(snapshot: source); defer { fixture.remove() }
            let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: fixture.root, diagnostics: metrics)
            #expect(try await store.profiles() == [source.profile])
            _ = try await store.selectProfile(fixture.profileID)
            let page = try await store.coachPage(.latest, expectedProfileID: fixture.profileID)
            let startup = metrics.counters
            #expect(page.exchanges.map(\.id) == source.coachTurns.suffix(20).map(\.id))
            #expect(startup.decodedTurnPayloads == 20)
            #expect(ordinaryReadBudget(startup))
            var window = CoachPagedHistoryWindow()
            let reset = window.reset(page)
            #expect(reset)
            #expect(window.residentCount + window.reservedCapacity <= 100)
            samples.append(startup)
        }
        #expect(samples.map(\.decodedTurnPayloads) == [20, 20])
        #expect(samples.map(\.originalPhotoBytes) == [0, 0])
    }

    @Test(arguments: [100, 10_000])
    func seekAndPagingStayWithinDeclaredBounds(count: Int) async throws {
        let source = try performanceSnapshot(exchanges: count)
        let fixture = try CaptureFixture(snapshot: source); defer { fixture.remove() }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: fixture.root, diagnostics: metrics)
        _ = try await store.selectProfile(fixture.profileID)
        let ownership = try await store.selectionOwnership(expectedProfileID: fixture.profileID)
        let requests: [CoachPageRequest] = [.aroundTurn(source.coachTurns[0].id), .atDay(source.days[1].id), .latest]
        for request in requests {
            metrics.reset()
            let page = try await store.coachPage(request, expectedProfileID: fixture.profileID)
            #expect(page.exchanges.count == 20)
            #expect(metrics.counters.decodedTurnPayloads == page.exchanges.count)
            #expect(ordinaryReadBudget(metrics.counters))
            #expect(metrics.counters.queryPlans.contains { $0.contains("SEARCH") && $0.contains("sequence") })
        }
        let oldest = try await store.coachPage(.aroundTurn(source.coachTurns[0].id), expectedProfileID: fixture.profileID)
        metrics.reset()
        let forward = try await store.coachPage(.after(try #require(oldest.after)), expectedProfileID: fixture.profileID)
        #expect(forward.exchanges.map(\.id) == source.coachTurns.dropFirst(20).prefix(20).map(\.id))
        #expect(metrics.counters.decodedTurnPayloads == 20 && ordinaryReadBudget(metrics.counters))
        metrics.reset()
        let days = try await store.coachDays(expectedSelection: ownership, expectedProfileID: fixture.profileID)
        #expect(days.segments.count == 30 && days.hasMore)
        let moreDays = try await store.coachDays(before: days.cursor, expectedSelection: ownership, expectedProfileID: fixture.profileID)
        #expect(moreDays.segments.count <= 30)
        #expect(Set(days.segments.map(\.segmentID)).isDisjoint(with: moreDays.segments.map(\.segmentID)))
        #expect(metrics.counters.decodedTurnPayloads == 0 && ordinaryReadBudget(metrics.counters))
        var window = CoachPagedHistoryWindow()
        let reset = window.reset(try await store.coachPage(.latest, expectedProfileID: fixture.profileID))
        #expect(reset)
        var seen = Set(window.exchanges.map(\.id))
        for _ in 0..<8 {
            let anchor = CoachViewportAnchor(rowID: try #require(window.exchanges.first).id, offset: 12, focusedExchangeID: nil)
            window.setViewport(.history(anchor), visibleIDs: [anchor.rowID])
            guard let reservation = window.reserve(.earlier, anchor: anchor) else { break }
            #expect(window.residentCount + window.reservedCapacity <= 100 && window.occupiedPageSlots <= 5)
            metrics.reset()
            let page = try await store.coachPage(reservation.request, expectedProfileID: fixture.profileID)
            #expect(metrics.counters.decodedTurnPayloads <= 20 && ordinaryReadBudget(metrics.counters))
            #expect(seen.isDisjoint(with: page.exchanges.map(\.id)))
            seen.formUnion(page.exchanges.map(\.id))
            let completed = window.complete(page, reservation: reservation)
            #expect(completed)
            #expect(window.residentCount + window.reservedCapacity <= 100 && window.occupiedPageSlots <= 5)
        }
        #expect(seen.count == min(count, 180))
        if count == 10_000 { #expect(window.residentCount == 100) }
    }

    @Test func indexedPhotosRespectDecodedCacheAndWorkBudgets() async throws {
        let source = try performanceSnapshot(exchanges: 100)
        let fixture = try CaptureFixture(snapshot: source); defer { fixture.remove() }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: fixture.root, diagnostics: metrics)
        _ = try await store.selectProfile(fixture.profileID)
        let page = try await store.coachPage(.aroundTurn(source.coachTurns[0].id), expectedProfileID: fixture.profileID)
        let references = page.exchanges.flatMap(\.photos)
        #expect(references.count == 5)
        let owner = try await store.selectionOwnership(expectedProfileID: fixture.profileID)
        let scope = DiaryPhotoScope(identity: owner.identity, selectionEpoch: owner.selectionEpoch)
        let limiter = PhotoWorkLimiter()
        let loader = DiaryPhotoLoader(scope: scope, limiter: limiter, reader: { reference, _ in
            try await store.photoContent(reference, expectedProfileID: reference.profileID)
        })
        metrics.reset()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for reference in references {
                group.addTask { _ = try await loader.thumbnail(for: reference, pixelSize: 1024) }
            }
            try await group.waitForAll()
        }
        let decoded = await loader.statistics(), work = await limiter.statistics()
        #expect(decoded.residentCost > 0 && decoded.residentCost + decoded.reservedCost <= 16 * 1024 * 1024)
        #expect(decoded.peakAccountedCost <= 16 * 1024 * 1024 && decoded.reservedCost == 0)
        #expect(decoded.cachedCount <= 4)
        #expect(work.peakActive > 0 && work.peakActive <= 2 && work.active == 0 && work.queued == 0)
        #expect(metrics.counters.originalPhotoBytes == references.count * source.coachTurns[0].photos[0].data.count)
        #expect(metrics.counters.completeReads == 0 && metrics.counters.completeReconciles == 0)
    }

    @Test @MainActor func tenThousandthCaptureCommitsAndNextCaptureRollsBack() async throws {
        let fixture = try CaptureFixture(snapshot: performanceSnapshot(exchanges: 9_999)); defer { fixture.remove() }
        let metrics = DiaryQueryDiagnostics(), store = DiaryStore(directory: fixture.root, diagnostics: metrics)
        _ = try await store.selectProfile(fixture.profileID)
        let preparation = try await store.coachCapturePreparation(at: fixture.before.days[0].startAt, expectedProfileID: fixture.profileID)
        let last = try CoachSubmissionPayload(submissionID: UUID(), text: "Synthetic exchange 10,000", attachments: [], context: preparation.context)
        metrics.reset()
        let accepted = try await store.captureCoachSubmission(last, expectedSelection: preparation.ownership, expectedProfileID: fixture.profileID)
        #expect(accepted.id == last.submissionID)
        #expect(try fixture.rows("SELECT COUNT(*) FROM coach_turn") == [["10000"]])
        let before = try fixture.durableState()
        let head = try await store.diaryHead(expectedProfileID: fixture.profileID)
        let photo = MealPhoto(data: fixture.before.meals[0].photos[0].data, createdAt: fixture.before.days[0].startAt)
        let draft = CoachAttachmentDraft(ownership: preparation.ownership, limiter: PhotoWorkLimiter(),
            dependencies: .init(store: store), text: "Synthetic retained draft 10,001 🍎", attachments: [photo])
        let rejectedID = draft.submissionID, rejectedText = draft.text, rejectedPhotos = draft.attachments
        await #expect(throws: DiaryError.invalidData) {
            _ = try await draft.send()
        }
        #expect(draft.submissionID == rejectedID && draft.text == rejectedText && draft.attachments == rejectedPhotos)
        #expect(draft.captureReceipt == nil && !draft.isSending)
        #expect(try fixture.durableState() == before)
        #expect(try await store.diaryHead(expectedProfileID: fixture.profileID) == head)
        #expect(ordinaryReadBudget(metrics.counters))
        let reference = try ChatHistoryFixture.completeReference(databaseURL: fixture.url)
        #expect(try fixture.rows("SELECT portableBytes FROM storage_quota") == [[String(try JSONEncoder().encode(reference).count)]])
    }

    @Test func realCompleteReadNegativeControlTripsHotPathOracle() throws {
        let source = try performanceSnapshot(exchanges: 100)
        let url = try ChatHistoryFixture.makeDatabase(source)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let metrics = DiaryQueryDiagnostics(), database = try DiaryDatabase(url: url, diagnostics: metrics)
        #expect(ordinaryReadBudget(metrics.counters))
        // Exercise the real prohibited reader, including its payload/BLOB instrumentation.
        #expect(try database.read(maximumBytes: ChatHistoryFixture.maximumBytes) == source)
        #expect(!ordinaryReadBudget(metrics.counters))
        #expect(metrics.counters.completeReads == 1 && metrics.counters.decodedTurnPayloads == 100)
        #expect(metrics.counters.originalPhotoBytes > 0)
    }

    private func ordinaryReadBudget(_ counters: DiaryQueryDiagnostics.Counters) -> Bool {
        counters.completeReads == 0 && counters.completeReconciles == 0 && counters.originalPhotoBytes == 0
    }

    private func performanceSnapshot(exchanges: Int) throws -> DiarySnapshot {
        var source = ChatHistoryFixture.pagingSnapshot(exchanges: exchanges)
        let bytes = try syntheticPNG()
        for index in source.meals.indices {
            for photo in source.meals[index].photos.indices { source.meals[index].photos[photo].data = bytes }
        }
        for index in source.coachTurns.indices {
            source.coachTurns[index].state = .completed
            for photo in source.coachTurns[index].photos.indices { source.coachTurns[index].photos[photo].data = bytes }
        }
        try source.validate()
        return source
    }

    private func syntheticPNG() throws -> Data {
        let context = try #require(CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
            bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        let image = try #require(context.makeImage()), bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
}
