import Foundation
import Testing
@testable import Mivu

@Suite struct DiaryQuotaAccountingTests {
    @Test(arguments: [UInt64(42), 20261018, 0xC0FFEE])
    func seededMutationSequencesMatchPortableAccountingAfterEveryCommit(seed: UInt64) throws {
        let fixture = try CaptureFixture(); defer { fixture.remove() }
        let metrics = DiaryQueryDiagnostics(), database = try DiaryDatabase(url: fixture.url, diagnostics: metrics)
        var generator = ChatHistoryFixture.Generator(seed: seed)
        var turnID = fixture.before.coachTurns[0].id
        var manualMealID = fixture.before.meals[0].id
        var addedPhotoID = fixture.before.meals[0].photos[0].id
        var replay: [CoachWrite] = []
        let originalMeal = fixture.before.meals[0].id
        let dates: [TimeInterval] = [-0.125, 0, 0.1, 0.3333333333333333, 800_000_000.125]
        var successes = 0
        for index in 0..<132 {
            let command = index % 12, cycle = index / 12
            let head = try database.readHead(expectedProfileID: fixture.profileID)
            let text = generator.encodingEdge() + " \(index)"
            let date = String(format: "2027-02-%02d", cycle + 1)
            let instant = Date(timeIntervalSinceReferenceDate: dates[index % dates.count])
            let photo = MealPhoto(id: generator.uuid(), data: Data(repeating: UInt8(index % 256), count: index % 17 + 1),
                                  createdAt: instant, role: index.isMultiple(of: 2) ? .before : .after)
            do {
                switch command {
                case 0:
                    let payload = try fixture.payload(head: head, id: generator.uuid(), text: text, photos: index.isMultiple(of: 24) ? [photo] : [])
                    turnID = try database.captureCoachSubmission(payload, expected: head, maximumBytes: ChatHistoryFixture.maximumBytes).value.id
                case 1:
                    _ = try database.updateCoachTurn(turnID: turnID, state: cycle.isMultiple(of: 2) ? .completed : .needsClarification,
                        assistantText: cycle.isMultiple(of: 2) ? text : nil, needsDayChoice: !cycle.isMultiple(of: 2), expected: head, maximumBytes: ChatHistoryFixture.maximumBytes)
                case 2:
                    manualMealID = try database.captureProjection(text: text, photos: [photo], reviewFirst: cycle.isMultiple(of: 2),
                        dayID: fixture.before.days[1].id, at: instant, dateOnly: cycle.isMultiple(of: 2), submissionID: generator.uuid(),
                        expected: head, maximumBytes: ChatHistoryFixture.maximumBytes).value.id
                case 3:
                    var item = try database.meal(id: originalMeal, expectedProfileID: fixture.profileID).items[0]
                    item.name = text; item.reference = generator.encodingEdge()
                    item.quantity = [0, 0.001, 100_000][cycle % 3]
                    item.nutrition = NutritionValues(kcal: [0, 0.125, 10_000_000][cycle % 3], carbs: cycle.isMultiple(of: 2) ? nil : 0.3333333333333333)
                    _ = try database.editItem(mealID: originalMeal, item: item, explicitNutrients: ["kcal", "carbs", "protein", "fat"], expected: head, maximumBytes: ChatHistoryFixture.maximumBytes)
                case 4:
                    addedPhotoID = photo.id
                    _ = try database.addPhotos(mealID: manualMealID, photos: [photo], expected: head, maximumBytes: ChatHistoryFixture.maximumBytes)
                case 5:
                    _ = try database.deletePhoto(mealID: manualMealID, photoID: addedPhotoID, expected: head, maximumBytes: ChatHistoryFixture.maximumBytes)
                case 6:
                    let targetDay = fixture.before.days[cycle % 2]
                    _ = try database.moveMeal(originalMeal, to: targetDay.id,
                        eatenAt: cycle.isMultiple(of: 2) ? nil : diaryDateOnlyInstant(targetDay.localDate, zone: targetDay.timeZoneID),
                        expected: head, maximumBytes: ChatHistoryFixture.maximumBytes)
                case 7:
                    let food = FoodItem(id: generator.uuid(), name: text, quantity: cycle.isMultiple(of: 2) ? 0.001 : 1,
                        unit: "piece", nutrition: NutritionValues(kcal: cycle.isMultiple(of: 2) ? 0 : 0.125, protein: nil), reference: generator.encodingEdge())
                    let draft = WorkoutDraft(kind: .other, durationMinutes: 1, exercises: [],
                        estimatedBurnKcal: cycle.isMultiple(of: 2) ? nil : 0.125, burnSource: cycle.isMultiple(of: 2) ? nil : .userEstimate)
                    replay = [.food(date: date, items: [food], eatenAt: nil), .weight(date: date, value: [0.001, 70.125, 1500][cycle % 3], unit: "kg", revision: nil),
                        .workout(date: date, draft: draft), .close(date: date, completeness: .complete),
                        .manual(.goals(date: date, targets: [CoachNutrientEdit(nutrient: "kcal", value: cycle.isMultiple(of: 2) ? nil : 1800.125)],
                            weight: cycle.isMultiple(of: 2) ? nil : 70.125, clearWeight: cycle.isMultiple(of: 2), exerciseCredit: cycle.isMultiple(of: 2) ? nil : true, revision: nil)),
                        .manual(.preferences(timezone: nil, text: text, revision: head.revision))]
                    let committed = try database.applyCoachWrites(replay, turnID: turnID, at: fixture.before.days[0].startAt, expected: head, maximumBytes: ChatHistoryFixture.maximumBytes)
                    #expect(committed.value.count == 6, "seed=\(seed) index=\(index) command=batch receipt growth")
                case 8:
                    _ = try database.applyCoachWrites(replay, turnID: turnID, mode: .replayOnly,
                        at: fixture.before.days[0].startAt, expected: head, maximumBytes: ChatHistoryFixture.maximumBytes)
                case 9:
                    _ = try database.correctMealProjection(mealID: manualMealID, text: text, photos: [], reviewFirst: false,
                        submissionID: generator.uuid(), at: instant, expected: head, maximumBytes: ChatHistoryFixture.maximumBytes)
                case 10:
                    _ = try database.deleteMeal(manualMealID, expected: head, maximumBytes: ChatHistoryFixture.maximumBytes)
                default:
                    _ = try database.setCompleteness(dayID: fixture.before.days[0].id, cycle.isMultiple(of: 2) ? .partial : .complete,
                        expected: head, maximumBytes: ChatHistoryFixture.maximumBytes)
                }
            } catch {
                Issue.record("seed=\(seed) index=\(index) command=\(command) unexpected error: \(error)")
                throw error
            }
            successes += 1
            #expect(try portableAccountingMatches(fixture), "seed=\(seed) index=\(index) command=\(command)")
            #expect(metrics.counters.completeReads == 0 && metrics.counters.completeReconciles == 0 && metrics.counters.originalPhotoBytes == 0,
                "seed=\(seed) index=\(index) command=\(command) hot-path work")
            if index.isMultiple(of: 13) {
                let before = try accountingDurableState(fixture)
                let current = try database.readHead(expectedProfileID: fixture.profileID)
                let maximum = try #require(Int(fixture.rows("SELECT portableBytes FROM storage_quota")[0][0]))
                let rejected = try fixture.payload(head: current, id: generator.uuid(), text: "Synthetic rejected " + text)
                #expect(throws: DiaryError.invalidData) { try database.captureCoachSubmission(rejected, expected: current, maximumBytes: maximum) }
                #expect(try accountingDurableState(fixture) == before, "seed=\(seed) index=\(index) command=reject quota rollback")
                #expect(try database.readHead(expectedProfileID: fixture.profileID) == current)
                var invalid = try database.meal(id: originalMeal, expectedProfileID: fixture.profileID).items[0]
                invalid.quantity = .infinity
                #expect(throws: DiaryError.invalidData) { try database.editItem(mealID: originalMeal, item: invalid, explicitNutrients: [], expected: current, maximumBytes: ChatHistoryFixture.maximumBytes) }
                #expect(try accountingDurableState(fixture) == before, "seed=\(seed) index=\(index) command=reject nonfinite rollback")
            }
        }
        #expect(successes >= 100)
    }

    @Test func actualCounterDriftIsDetectedByPortableOracle() throws {
        let fixture = try CaptureFixture(); defer { fixture.remove() }
        #expect(try portableAccountingMatches(fixture))
        let before = try ChatHistoryFixture.completeReference(databaseURL: fixture.url)
        try fixture.execute("UPDATE storage_quota SET portableBytes = portableBytes + 1")
        #expect(try ChatHistoryFixture.completeReference(databaseURL: fixture.url) == before)
        #expect(try !portableAccountingMatches(fixture))
        try fixture.execute("UPDATE storage_quota SET portableBytes = portableBytes - 1")
        #expect(try portableAccountingMatches(fixture))
        try fixture.execute("UPDATE storage_quota SET originalPhotoBytes = originalPhotoBytes + 1")
        #expect(try !portableAccountingMatches(fixture))
        try fixture.execute("UPDATE storage_quota SET originalPhotoBytes = originalPhotoBytes - 1")
        try fixture.execute("UPDATE storage_row_count SET rowCount = rowCount + 1 WHERE tableName = 'coach_turn'")
        #expect(try !portableAccountingMatches(fixture))
    }

    @Test func targetedMutationJustUnderAtAndOverLimitPreservesRollbackCounters() throws {
        let calibration = try CaptureFixture(); defer { calibration.remove() }
        let database = try DiaryDatabase(url: calibration.url)
        var item = calibration.before.meals[0].items[0]
        item.name = String(repeating: "Synthetic escaped \" 🍎\\\n", count: 20)
        _ = try database.editItem(mealID: calibration.before.meals[0].id, item: item, explicitNutrients: [],
            expected: database.readHead(expectedProfileID: calibration.profileID), maximumBytes: ChatHistoryFixture.maximumBytes)
        let exact = try JSONEncoder().encode(ChatHistoryFixture.completeReference(databaseURL: calibration.url)).count
        for limit in [exact - 1, exact, exact + 1] {
            let fixture = try CaptureFixture(); defer { fixture.remove() }
            let database = try DiaryDatabase(url: fixture.url), head = try database.readHead(expectedProfileID: fixture.profileID)
            let before = try accountingDurableState(fixture)
            if limit < exact {
                #expect(throws: DiaryError.invalidData) { try database.editItem(mealID: fixture.before.meals[0].id, item: item, explicitNutrients: [], expected: head, maximumBytes: limit) }
                #expect(try accountingDurableState(fixture) == before)
                #expect(try database.readHead(expectedProfileID: fixture.profileID) == head)
            } else {
                _ = try database.editItem(mealID: fixture.before.meals[0].id, item: item, explicitNutrients: [], expected: head, maximumBytes: limit)
                #expect(try fixture.rows("SELECT portableBytes FROM storage_quota") == [[String(exact)]])
                #expect(try portableAccountingMatches(fixture))
            }
        }
    }

    private func accountingDurableState(_ fixture: CaptureFixture) throws -> [[[String]]] {
        try fixture.durableState() + ["day", "meal", "submission", "item", "weight", "workout", "goal", "weight_tombstone", "workout_tombstone", "tombstone", "record_source"].map {
            try fixture.rows("SELECT * FROM \($0) ORDER BY rowid")
        }
    }

    private func portableAccountingMatches(_ fixture: CaptureFixture) throws -> Bool {
        let full = try ChatHistoryFixture.completeReference(databaseURL: fixture.url)
        try full.validate()
        let originals = full.meals.flatMap(\.photos).reduce(0) { $0 + $1.data.count } + full.coachTurns.flatMap(\.photos).reduce(0) { $0 + $1.data.count }
        let encodedBytes = try JSONEncoder().encode(full).count
        guard try fixture.rows("SELECT portableBytes, originalPhotoBytes FROM storage_quota") == [[String(encodedBytes), String(originals)]] else { return false }
        for table in ["day", "meal", "submission", "item", "photo", "weight", "workout", "coach_turn", "coach_photo", "goal", "tombstone", "weight_tombstone", "workout_tombstone"] {
            guard try fixture.rows("SELECT rowCount FROM storage_row_count WHERE tableName = '\(table)'") == fixture.rows("SELECT COUNT(*) FROM \(table)") else { return false }
        }
        return try fixture.rows("SELECT COUNT(*) FROM pragma_foreign_key_check") == [["0"]]
    }

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

    @Test func manualAcceptanceBytesAreIncludedInPortableQuota() throws {
        let snapshot = try ManualNutritionPayloadTests.snapshot()
        var legacy = snapshot; legacy.meals[0].submissions[0].manualAcceptance = nil
        #expect(try JSONEncoder().encode(snapshot).count > JSONEncoder().encode(legacy).count)
        let url = try ChatHistoryFixture.makeDatabase(snapshot)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try DiaryDatabase(url: url).migrateForPagedStorage(maximumBytes: ChatHistoryFixture.maximumBytes)
        #expect(try ChatHistoryFixture.strings(url, "SELECT portableBytes FROM storage_quota") == [[String(try JSONEncoder().encode(snapshot).count)]])
        #expect(try ChatHistoryFixture.strings(url, "PRAGMA user_version") == [["1"]])
        #expect(try ChatHistoryFixture.completeReference(databaseURL: url) == snapshot)
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
