import Foundation
import Testing
@testable import Mivu

@Suite struct DiaryQuotaAccountingTests {
    @Test(arguments: [UInt64(42), 20261018, 0xC0FFEE])
    func seededCaptureAndStatusQuotaMatchesCompleteReference(seed: UInt64) throws {
        let fixture = try CaptureFixture(); defer { fixture.remove() }
        let database = try DiaryDatabase(url: fixture.url)
        var generator = ChatHistoryFixture.Generator(seed: seed)
        var head = try database.readHead(expectedProfileID: fixture.profileID)
        var latestID = fixture.before.coachTurns[0].id
        for index in 0..<100 {
            let text = generator.encodingEdge() + String(index)
            if index.isMultiple(of: 3) {
                let photo = MealPhoto(id: generator.uuid(), data: Data(repeating: 255, count: index % 17 + 1), createdAt: Date(timeIntervalSinceReferenceDate: Double(index) + 0.125))
                let payload = try fixture.payload(head: head, id: generator.uuid(), text: text, photos: index.isMultiple(of: 2) ? [photo] : [])
                let commit = try database.captureCoachSubmission(payload, expected: head, maximumBytes: ChatHistoryFixture.maximumBytes)
                head = commit.head; latestID = commit.value.id
            } else {
                // Include a receipt-bearing legacy row as well as newly captured rows.
                let id = index.isMultiple(of: 2) ? fixture.before.coachTurns[0].id : latestID
                let commit = try database.updateCoachTurn(turnID: id,
                    state: index.isMultiple(of: 2) ? .completed : .needsClarification,
                    assistantText: index.isMultiple(of: 2) ? text : nil, needsDayChoice: !index.isMultiple(of: 2),
                    expected: head, maximumBytes: ChatHistoryFixture.maximumBytes)
                head = commit.head
            }
            let reference = try ChatHistoryFixture.completeReference(databaseURL: fixture.url)
            try reference.validate()
            let counted = try #require(Int(fixture.rows("SELECT portableBytes FROM storage_quota")[0][0]))
            #expect(counted == (try JSONEncoder().encode(reference)).count, "seed=\(seed) operation=\(index)")
            #expect(try fixture.rows("SELECT originalPhotoBytes FROM storage_quota") == [[String(reference.meals.flatMap(\.photos).reduce(0) { $0 + $1.data.count } + reference.coachTurns.flatMap(\.photos).reduce(0) { $0 + $1.data.count })]])
            if index.isMultiple(of: 10) {
                let before = try fixture.durableState()
                let failed = try fixture.payload(head: head, id: generator.uuid(), text: generator.encodingEdge())
                #expect(throws: DiaryError.invalidData) { try database.captureCoachSubmission(failed, expected: head, maximumBytes: counted) }
                #expect(try fixture.durableState() == before, "seed=\(seed) operation=\(index) rollback")
            }
        }
    }

    @Test func quotaJustUnderAtAndOverLimitPreservesRollbackCounters() throws {
        let calibration = try CaptureFixture(); defer { calibration.remove() }
        let database = try DiaryDatabase(url: calibration.url)
        let head = try database.readHead(expectedProfileID: calibration.profileID)
        let payload = try calibration.payload(head: head, text: "Synthetic quota boundary", photos: [calibration.photo()])
        _ = try database.captureCoachSubmission(payload, expected: head, maximumBytes: ChatHistoryFixture.maximumBytes)
        let reference = try ChatHistoryFixture.completeReference(databaseURL: calibration.url)
        let exact = try JSONEncoder().encode(reference).count
        #expect(try calibration.rows("SELECT portableBytes FROM storage_quota") == [[String(exact)]])
        for limit in [exact - 1, exact, exact + 1] {
            let fixture = try CaptureFixture(); defer { fixture.remove() }
            let database = try DiaryDatabase(url: fixture.url)
            let original = try database.readHead(expectedProfileID: fixture.profileID)
            let before = try fixture.durableState()
            if limit < exact {
                #expect(throws: DiaryError.invalidData) { try database.captureCoachSubmission(payload, expected: original, maximumBytes: limit) }
                #expect(try database.readHead(expectedProfileID: fixture.profileID) == original)
                #expect(try fixture.durableState() == before)
            } else {
                _ = try database.captureCoachSubmission(payload, expected: original, maximumBytes: limit)
                #expect(try fixture.rows("SELECT portableBytes FROM storage_quota") == [[String(exact)]])
            }
        }
    }

    @Test func storageBudgetMatchesPortableEncoding() throws {
        let before = ChatHistoryFixture.snapshot()
        let url = try ChatHistoryFixture.makeDatabase(before)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        let accountedBytes = try #require(Int(ChatHistoryFixture.strings(url, "SELECT portableBytes FROM storage_quota")[0][0]))
        #expect(accountedBytes == (try JSONEncoder().encode(before)).count)
        #expect(try ChatHistoryFixture.strings(url, "SELECT originalPhotoBytes FROM storage_quota") == [["19"]])
    }

    @Test(arguments: [UInt64(42), 20261018, 0xC0FFEE])
    func seededQuotaOracleCoversEncodingEdges(seed: UInt64) throws {
        var generator = ChatHistoryFixture.Generator(seed: seed)
        for operationIndex in 0..<100 {
            let count = Int(generator.next() % 6)
            var before = ChatHistoryFixture.snapshot(exchanges: count, seed: generator.next())
            before.profile.preferences = generator.encodingEdge()
            let dateEdges: [TimeInterval] = [-0.125, 0, 0.1, 0.3333333333333333, 800_000_000.125]
            before.previousDayConfirmedAt = Date(timeIntervalSinceReferenceDate: dateEdges[operationIndex % dateEdges.count])
            before.meals[0].items[0].quantity = [0, 0.001, 100_000][operationIndex % 3]
            before.meals[0].items[0].nutrition.kcal = [0, 0.125, 10_000_000][operationIndex % 3]
            before.weights[0].value = [0.001, 70.125, 1500][operationIndex % 3]
            before.goals[0].goalWeightKg = operationIndex.isMultiple(of: 2) ? nil : 0.001
            before.workouts[0].estimatedBurnKcal = operationIndex.isMultiple(of: 2) ? nil : 100_000
            if before.workouts[0].estimatedBurnKcal == nil { before.workouts[0].burnSource = nil }
            if operationIndex.isMultiple(of: 2) { before.lineage = nil; before.previousDayConfirmedAt = nil }
            if operationIndex.isMultiple(of: 3) { before.meals = []; before.weights = []; before.goals = []; before.workouts = []; before.deletedMealIDs = [] }
            if operationIndex.isMultiple(of: 5) {
                before.coachTurns = before.coachTurns.map { turn in var copy = turn; copy.receipts = []; return copy }
            }
            // Removing a referenced meal must also remove its historical receipt in this generated valid command.
            if before.meals.isEmpty { before.coachTurns = before.coachTurns.map { turn in var copy = turn; copy.receipts = []; return copy } }
            try before.validate()
            let url = try ChatHistoryFixture.makeDatabase(before)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
            let reference = try ChatHistoryFixture.completeReference(databaseURL: url)
            #expect(reference == before, "seed=\(seed) operationIndex=\(operationIndex) command=migrate preserves canonical metadata")
            let accountedBytes = try #require(Int(ChatHistoryFixture.strings(url, "SELECT portableBytes FROM storage_quota")[0][0]))
            #expect(accountedBytes == (try JSONEncoder().encode(reference)).count,
                "seed=\(seed) operationIndex=\(operationIndex) command=migrate encoding-edge fixture count=\(count)")
        }
    }
}
