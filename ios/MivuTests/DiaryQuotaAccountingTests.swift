import Foundation
import Testing
@testable import Mivu

@Suite struct DiaryQuotaAccountingTests {
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
