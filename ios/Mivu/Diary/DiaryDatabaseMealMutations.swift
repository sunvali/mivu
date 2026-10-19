import Foundation
import SQLite3

extension DiaryDatabase {
    func diaryReadModel(expectedProfileID: UUID) throws -> DiaryReadModel {
        try domainRead(expectedProfileID: expectedProfileID) { head in
            let transaction = DiaryTransaction(database: self, head: head)
            let day = try head.activeDayID.map { try trackingDay(id: $0) }
            let projection = try day.map { try transaction.dayProjection($0) }
            let pending = try mutationInteger("SELECT COUNT(*) FROM submission WHERE json_extract(CAST(payload AS TEXT), '$.state') IN ('captured','waitingForConnection','analyzing','needsRetry')")
                + mutationInteger("SELECT COUNT(*) FROM coach_index WHERE pendingMealID IS NULL AND state IN ('captured','analyzing','waitingForConnection','waitingForNetwork','needsRetry','needsClarification')")
            let activePending = try day.map { day in
                try mutationInteger("SELECT EXISTS(SELECT 1 FROM coach_turn WHERE COALESCE(json_extract(CAST(payload AS TEXT), '$.resolvedDayID'), json_extract(CAST(payload AS TEXT), '$.activeDayID')) = ? AND json_extract(CAST(payload AS TEXT), '$.state') != 'completed') OR EXISTS(SELECT 1 FROM coach_index i JOIN coach_turn t ON t.id = i.turnID WHERE i.displayLocalDate = ? AND i.state != 'completed' AND COALESCE(json_extract(CAST(t.payload AS TEXT), '$.resolvedDayID'), json_extract(CAST(t.payload AS TEXT), '$.activeDayID')) IS NULL)", [.text(day.id.uuidString), .text(day.localDate)]) > 0
            } ?? false
            return DiaryReadModel(head: head, activeDay: day, meals: projection?.meals ?? [], weight: projection?.weight,
                workouts: projection?.workouts ?? [], activeGoal: try transaction.goal(on: day?.localDate ?? diaryDateLabel(Date(), zone: head.profile.timeZoneID)), pendingAnalysisCount: pending,
                hasPendingOnActiveDay: activePending || projection?.meals.contains(where: \.hasUnresolvedInput) == true)
        }
    }
    func diaryDay(id: UUID, expectedProfileID: UUID) throws -> DiaryDayReadModel {
        try domainRead(expectedProfileID: expectedProfileID) { head in
            try DiaryTransaction(database: self, head: head).dayProjection(trackingDay(id: id))
        }
    }
    func meal(id: UUID, expectedProfileID: UUID) throws -> MealReadModel {
        try domainRead(expectedProfileID: expectedProfileID) { try DiaryTransaction(database: self, head: $0).mealProjection(id: id) }
    }
    func photoContent(_ reference: DiaryPhotoReference, expectedProfileID: UUID) throws -> Data {
        guard reference.profileID == expectedProfileID else { throw DiaryError.wrongOwner }
        return try domainRead(expectedProfileID: expectedProfileID) { _ in
            let scope = diaryPhotoScope(reference.owner)
            let statement = try domainStatement("SELECT p.bytes FROM photo_content c JOIN \(scope.table) p ON p.id = c.physicalID WHERE c.ownerKind = ? AND c.parentID = ? AND c.photoID = ? AND c.contentToken = ?",
                [.text(scope.kind), .text(scope.parent.uuidString), .text(reference.photoID.uuidString), .text(reference.contentToken.uuidString)])
            defer { sqlite3_finalize(statement) }
            guard try mutationStep(statement) else { throw DiaryError.notFound }
            let bytes = try mutationBlob(statement, 0)
            guard bytes.count > 0, bytes.count <= 10_000_000 else { throw DiaryError.invalidData }
            diagnostics?.recordPhotoRead(bytes: bytes.count)
            return bytes
        }
    }
    func diaryHistory(before: DiaryHistoryCursor? = nil, limit: Int = 30, recordedOnly: Bool = false, localDate: String? = nil, expectedProfileID: UUID) throws -> DiaryHistoryPage {
        try domainRead(expectedProfileID: expectedProfileID) { head in
            guard limit > 0, limit <= 30 else { throw DiaryError.invalidData }
            let identity = CoachTimelineIdentity(profileID: head.profile.id, timelineGeneration: head.timelineGeneration)
            var clauses: [String] = [], values: [Value] = []
            if let before {
                guard before.identity == identity else { throw CoachQueryError.wrongTimeline }
                guard before.recordedOnly == recordedOnly, before.localDate == localDate else { throw CoachQueryError.invalidCursor }
                guard try mutationInteger("SELECT COUNT(*) FROM day WHERE id = ? AND ordinal = ?", [.text(before.dayID.uuidString), .integer(before.ordinal)]) == 1 else { throw CoachQueryError.invalidCursor }
                clauses.append("(d.ordinal, d.id) < (?, ?)"); values += [.integer(before.ordinal), .text(before.dayID.uuidString)]
            }
            if let localDate { guard validLocalDate(localDate) else { throw DiaryError.invalidData }; clauses.append("json_extract(CAST(d.payload AS TEXT), '$.localDate') = ?"); values.append(.text(localDate)) }
            if recordedOnly { clauses.append("(json_extract(CAST(d.payload AS TEXT), '$.completeness') = 'complete' OR EXISTS (SELECT 1 FROM meal m WHERE m.parent = d.id AND json_extract(CAST(m.payload AS TEXT), '$.revision') > 0))") }
            let statement = try domainStatement("SELECT d.id, d.ordinal, d.payload FROM day d \(clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")) ORDER BY d.ordinal DESC, d.id DESC LIMIT ?", values + [.integer(limit + 1)])
            defer { sqlite3_finalize(statement) }
            let transaction = DiaryTransaction(database: self, head: head)
            var rows: [(day: TrackingDay, ordinal: Int)] = []
            while try mutationStep(statement) {
                guard let id = UUID(uuidString: try mutationText(statement, 0)) else { throw DiaryError.invalidData }
                let day = try decode(TrackingDay.self, Record(id: id.uuidString, ordinal: 0, payload: mutationBlob(statement, 2)))
                try validateTrackingDayFields(day)
                rows.append((day, Int(sqlite3_column_int64(statement, 1))))
            }
            let hasMore = rows.count > limit
            if hasMore { rows.removeLast() }
            let days = try rows.map { try transaction.daySummary($0.day) }
            return DiaryHistoryPage(days: days, cursor: rows.last.map { DiaryHistoryCursor(identity: identity, ordinal: $0.ordinal, dayID: $0.day.id, recordedOnly: recordedOnly, localDate: localDate) }, hasMore: hasMore)
        }
    }
    func startDay(at: Date, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<TrackingDay> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.startDay(at: at) }
    }
    func confirmPreviousDay(at: Date, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { transaction in
            guard let dayID = transaction.head.activeDayID else { throw DiaryError.notFound }
            transaction.head.previousDayConfirmedAt = at
            try transaction.resolveDayChoices(at: at, dayID: dayID)
        }
    }
    func captureProjection(text: String, photos: [MealPhoto], reviewFirst: Bool, dayID: UUID, at: Date, dateOnly: Bool = false, submissionID: UUID = UUID(), forCoach: Bool = false, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<MealReadModel> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { transaction in
            if let prior = try transaction.submissionParent(id: submissionID) {
                try transaction.validateManualRetry(submissionID: submissionID, text: text, photos: photos)
                return try transaction.mealProjection(id: prior)
            }
            let day = try trackingDay(id: dayID)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty else { throw DiaryError.emptyCapture }
            guard photos.count <= 8, Set(photos.map(\.id)).count == photos.count else { throw DiaryError.invalidData }
            let meal = DiaryMeal(dayID: dayID, capturedAt: at, eatenAt: dateOnly ? day.startAt : at, timePrecision: dateOnly ? .dateOnly : nil)
            try transaction.insertMeal(meal)
            try transaction.saveSubmission(MealSubmission(id: submissionID, baseRevision: 0, text: text, photoIDs: photos.map(\.id), reviewFirst: reviewFirst), meal: meal)
            if forCoach { try transaction.appendManualCapture(meal: meal, submissionID: submissionID, text: text, photos: photos, at: at) }
            else { for photo in photos { try transaction.insertPhoto(photo, owner: .meal(meal.id)) } }
            return try transaction.mealProjection(id: meal.id)
        }
    }
    func correctMealProjection(mealID: UUID, text: String, photos: [MealPhoto] = [], reviewFirst: Bool = false, submissionID: UUID = UUID(), forCoach: Bool = false, at: Date, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<MealReadModel> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { transaction in
            if let prior = try transaction.submissionParent(id: submissionID) {
                guard prior == mealID else { throw DiaryError.invalidData }
                try transaction.validateManualRetry(submissionID: submissionID, text: text, photos: photos)
                return try transaction.mealProjection(id: prior)
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty else { throw DiaryError.emptyCapture }
            guard photos.count <= 8, Set(photos.map(\.id)).count == photos.count else { throw DiaryError.invalidData }
            let meal = try transaction.mealRecord(id: mealID)
            try transaction.saveSubmission(MealSubmission(id: submissionID, baseRevision: meal.revision, text: text, photoIDs: photos.map(\.id), reviewFirst: reviewFirst), meal: meal)
            if forCoach { try transaction.appendManualCapture(meal: meal, submissionID: submissionID, text: text, photos: photos, at: at) }
            else { for photo in photos { try transaction.insertPhoto(photo, owner: .meal(mealID)) } }
            return try transaction.mealProjection(id: mealID)
        }
    }
    func applyAnalysis(_ output: AnalysisOutput, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.applyAnalysis(output) }
    }
    func acceptReview(mealID: UUID, submissionID: UUID, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.acceptReview(mealID: mealID, submissionID: submissionID) }
    }
    func editItem(mealID: UUID, item: FoodItem, explicitNutrients: Set<String>, reviewSubmissionID: UUID? = nil, expectedRevision: Int? = nil, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.editItem(mealID: mealID, item: item, explicitNutrients: explicitNutrients, reviewSubmissionID: reviewSubmissionID, expectedRevision: expectedRevision) }
    }
    func addPhotos(mealID: UUID, photos: [MealPhoto], expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { transaction in
            _ = try transaction.mealRecord(id: mealID)
            for photo in photos { try transaction.insertPhoto(photo, owner: .meal(mealID)) }
        }
    }
    func deletePhoto(mealID: UUID, photoID: UUID, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.deleteMealPhoto(mealID: mealID, photoID: photoID) }
    }
    func deleteMeal(_ mealID: UUID, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.deleteMeal(mealID) }
    }
    func moveMeal(_ mealID: UUID, to dayID: UUID, eatenAt: Date? = nil, expectedRevision: Int? = nil, expectedDayID: UUID? = nil, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.moveMeal(mealID, to: dayID, eatenAt: eatenAt, expectedRevision: expectedRevision, expectedDayID: expectedDayID) }
    }
    func setCompleteness(dayID: UUID, _ completeness: DayCompleteness, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { transaction in
            var day = try trackingDay(id: dayID); day.completeness = completeness
            try transaction.saveDay(day)
        }
    }
    func prepareAnalysis(mealID: UUID, submissionID: UUID, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { transaction in
            let meal = try transaction.mealRecord(id: mealID)
            var submission = try transaction.submission(id: submissionID, mealID: mealID)
            guard [.captured, .waitingForConnection, .analyzing, .needsRetry].contains(submission.state) else { throw DiaryError.invalidData }
            if submission.baseRevision != meal.revision { submission.baseRevision = meal.revision; submission.proposal = nil; try transaction.saveSubmission(submission, meal: meal) }
        }
    }
    func nextPendingMealSubmission(expectedProfileID: UUID) throws -> (mealID: UUID, submissionID: UUID)? {
        try domainRead(expectedProfileID: expectedProfileID) { _ in
            let statement = try domainStatement("SELECT parent, id FROM submission WHERE json_extract(CAST(payload AS TEXT), '$.state') IN ('captured','waitingForConnection','analyzing','needsRetry') ORDER BY ordinal, id LIMIT 1")
            defer { sqlite3_finalize(statement) }
            guard try mutationStep(statement) else { return nil }
            guard let mealID = try mutationOptionalUUID(statement, 0), let submissionID = try mutationOptionalUUID(statement, 1) else { throw DiaryError.invalidData }
            return (mealID, submissionID)
        }
    }
    func analysisInput(mealID: UUID, submissionID: UUID, expectedProfileID: UUID) throws -> AnalysisInput {
        try domainRead(expectedProfileID: expectedProfileID) { head in
            let transaction = DiaryTransaction(database: self, head: head)
            let meal = try transaction.mealProjection(id: mealID), submission = try transaction.submission(id: submissionID, mealID: mealID)
            guard submission.state != .cancelled else { throw DiaryError.notFound }
            guard submission.baseRevision == meal.revision else { throw DiaryError.staleRevision }
            let photos = try meal.photos.filter { submission.photoIDs.contains($0.photoID) }.map { reference -> MealPhoto in
                let statement = try domainStatement("SELECT bytes FROM photo WHERE id = ?", [.text(mealID.uuidString + "/" + reference.photoID.uuidString)])
                defer { sqlite3_finalize(statement) }; guard try mutationStep(statement) else { throw DiaryError.notFound }
                let bytes = try mutationBlob(statement, 0); diagnostics?.recordPhotoRead(bytes: bytes.count)
                return MealPhoto(id: reference.photoID, data: bytes, createdAt: reference.createdAt, role: reference.role)
            }
            return AnalysisInput(profileID: head.profile.id, mealID: mealID, submissionID: submissionID, baseRevision: submission.baseRevision,
                text: submission.text, photos: photos, currentItems: meal.items, language: head.profile.language, preferences: head.profile.preferences)
        }
    }
    func chooseCoachDay(turnID: UUID, usePrevious: Bool, at: Date, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { transaction in
            guard var turn = try transaction.turn(id: turnID) else { throw DiaryError.notFound }
            guard turn.needsDayChoice == true else { throw DiaryError.invalidData }
            let day: TrackingDay
            if usePrevious {
                guard let id = turn.activeDayID else { throw DiaryError.notFound }; day = try trackingDay(id: id)
            } else {
                let date = diaryDateLabel(turn.capturedAt, zone: turn.captureTimeZoneID)
                day = try transaction.resolveDay(localDate: date, timeZoneID: turn.captureTimeZoneID, at: turn.capturedAt)
                if diaryDateLabel(at, zone: turn.captureTimeZoneID) == date { try transaction.activateDay(day) }
            }
            turn.resolvedDayID = day.id; turn.needsDayChoice = nil; try transaction.saveTurn(turn)
        }
    }

    func domainRead<Value>(expectedProfileID: UUID, _ body: (DiaryHead) throws -> Value) throws -> Value {
        try validateFileIdentity(); try execute("BEGIN")
        do {
            let head = try readHead(expectedProfileID: expectedProfileID), value = try body(head)
            try validateFileIdentity(); try execute("COMMIT"); return value
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func domainStatement(_ sql: String, _ values: [Value] = []) throws -> OpaquePointer {
        if let diagnostics {
            let plan = try mutationStatement("EXPLAIN QUERY PLAN " + sql, values); defer { sqlite3_finalize(plan) }
            while try mutationStep(plan) { diagnostics.recordQueryPlan(try mutationText(plan, 3)) }
        }
        return try mutationStatement(sql, values)
    }
}

extension DiaryTransaction {
    func mealRecord(id: UUID) throws -> DiaryMeal {
        let rows = try records("meal", clause: "id = ?", values: [.text(id.uuidString)])
        guard let row = rows.first else { throw DiaryError.notFound }
        let meal = try database.decode(DiaryMeal.self, row)
        guard row.parent == meal.dayID.uuidString, meal.items.isEmpty, meal.photos.isEmpty, meal.submissions.isEmpty else { throw DiaryError.invalidData }
        let itemCount = try database.mutationInteger("SELECT COUNT(*) FROM item WHERE parent = ?", [.text(id.uuidString)])
        try validateMealFields(meal, itemCount: itemCount)
        return meal
    }
    func mealProjection(id: UUID) throws -> MealReadModel {
        let meal = try mealRecord(id: id), items = try mealItems(id: id), submissions = try mealSubmissions(id: id), photos = try photoReferences(owner: .meal(id))
        guard submissions.allSatisfy({ $0.photoIDs.allSatisfy(Set(photos.map(\.photoID)).contains) }) else { throw DiaryError.invalidData }
        let statement = try database.domainStatement("SELECT r.turnID FROM record_source r JOIN coach_index c ON c.turnID = r.turnID WHERE r.kind = 'meal' AND r.recordID = ? AND r.relation = 'origin' ORDER BY c.sequence LIMIT 1", [.text(id.uuidString)])
        defer { sqlite3_finalize(statement) }
        let source = try database.mutationStep(statement) ? database.mutationOptionalUUID(statement, 0) : nil
        return MealReadModel(id: id, dayID: meal.dayID, capturedAt: meal.capturedAt, eatenAt: meal.eatenAt, revision: meal.revision,
            timePrecision: meal.timePrecision, items: items, submissions: submissions, photos: photos, sourceTurnID: source)
    }
    func dayProjection(_ day: TrackingDay) throws -> DiaryDayReadModel {
        let meals = try records("meal", clause: "parent = ?", values: [.text(day.id.uuidString)]).map { row -> MealReadModel in
            guard let id = UUID(uuidString: row.id) else { throw DiaryError.invalidData }; return try mealProjection(id: id)
        }
        let weights = try records("weight", clause: "parent = ?", values: [.text(day.id.uuidString)]).map { try database.decode(WeightEntry.self, $0) }
        let workouts = try records("workout", clause: "parent = ?", values: [.text(day.id.uuidString)]).map { try database.decode(WorkoutSession.self, $0) }
        for weight in weights { try validateWeightFields(weight) }; for workout in workouts { try validateWorkoutFields(workout) }
        return DiaryDayReadModel(head: head, day: day, meals: meals, weight: weights.first, workouts: workouts, goal: try goal(on: day.localDate))
    }
    func goal(on date: String) throws -> GoalRecord? {
        let statement = try database.domainStatement("SELECT id, payload FROM goal WHERE effectiveLocalDate <= ? ORDER BY effectiveLocalDate DESC LIMIT 1", [.text(date)])
        defer { sqlite3_finalize(statement) }; guard try database.mutationStep(statement) else { return nil }
        let value = try database.decode(GoalRecord.self, DiaryDatabase.Record(id: database.mutationText(statement, 0), ordinal: 0, payload: database.mutationBlob(statement, 1)))
        try validateGoalFields(value); return value
    }
    func daySummary(_ day: TrackingDay) throws -> DiaryDaySummary {
        let statement = try database.domainStatement("SELECT COUNT(*), SUM(CASE WHEN json_extract(CAST(m.payload AS TEXT), '$.revision') > 0 THEN 1 ELSE 0 END), SUM(CASE WHEN (json_extract(CAST(m.payload AS TEXT), '$.revision') = 0 AND NOT EXISTS (SELECT 1 FROM submission s WHERE s.parent = m.id)) OR EXISTS (SELECT 1 FROM submission s WHERE s.parent = m.id AND json_extract(CAST(s.payload AS TEXT), '$.state') NOT IN ('saved','cancelled')) THEN 1 ELSE 0 END) FROM meal m WHERE m.parent = ?", [.text(day.id.uuidString)])
        defer { sqlite3_finalize(statement) }; guard try database.mutationStep(statement) else { throw DiaryError.invalidData }
        let saved = Int(sqlite3_column_int64(statement, 1)), pending = Int(sqlite3_column_int64(statement, 2))
        let fields = ["kcal", "carbs", "protein", "fat"]
        let expressions = fields.map { "CASE WHEN COUNT(*) = COUNT(json_extract(CAST(i.payload AS TEXT), '$.nutrition.\($0)')) THEN SUM(json_extract(CAST(i.payload AS TEXT), '$.nutrition.\($0)')) ELSE NULL END" }
        let totals = try database.domainStatement("SELECT COUNT(*), " + expressions.joined(separator: ", ") + ", COALESCE(SUM(CASE WHEN " + fields.map { "json_extract(CAST(i.payload AS TEXT), '$.nutrition.\($0)') IS NULL" }.joined(separator: " OR ") + " THEN 1 ELSE 0 END), 0) FROM meal m JOIN item i ON i.parent = m.id WHERE m.parent = ? AND json_extract(CAST(m.payload AS TEXT), '$.revision') > 0", [.text(day.id.uuidString)])
        defer { sqlite3_finalize(totals) }; guard try database.mutationStep(totals) else { throw DiaryError.invalidData }
        let emptyComplete = sqlite3_column_int64(totals, 0) == 0 && day.completeness == .complete && pending == 0
        func value(_ column: Int32) -> Double? { emptyComplete ? 0 : (sqlite3_column_type(totals, column) == SQLITE_NULL ? nil : sqlite3_column_double(totals, column)) }
        return DiaryDaySummary(mealCount: Int(sqlite3_column_int64(statement, 0)), day: day, totals: NutritionTotals(kcal: value(1), carbs: value(2), protein: value(3), fat: value(4), unknownItemCount: Int(sqlite3_column_int64(totals, 5))), savedMealCount: saved, pendingMealCount: pending)
    }
    func records(_ table: String, clause: String, values: [DiaryDatabase.Value], limit: Int? = nil) throws -> [DiaryDatabase.Record] {
        let hasParent = ["meal", "submission", "item", "photo", "weight", "workout", "coach_photo"].contains(table)
        let statement = try database.domainStatement("SELECT id, ordinal, payload, \(hasParent ? "parent" : "NULL") FROM \(table) WHERE \(clause) ORDER BY ordinal, id \(limit.map { "LIMIT \($0)" } ?? "")", values)
        defer { sqlite3_finalize(statement) }; var result: [DiaryDatabase.Record] = []
        while try database.mutationStep(statement) { result.append(DiaryDatabase.Record(id: try database.mutationText(statement, 0), ordinal: Int(sqlite3_column_int64(statement, 1)), payload: try database.mutationBlob(statement, 2), parent: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : try database.mutationText(statement, 3))) }
        return result
    }
    func nextOrdinal(_ table: String, parent: UUID? = nil) throws -> Int {
        try database.mutationInteger("SELECT COALESCE(MAX(ordinal) + 1, 0) FROM \(table) \(parent == nil ? "" : "WHERE parent = ?")", parent.map { [.text($0.uuidString)] } ?? [])
    }
    func resolveDay(localDate: String, timeZoneID: String, at: Date) throws -> TrackingDay {
        let row = try records("day", clause: "json_extract(CAST(payload AS TEXT), '$.localDate') = ? AND json_extract(CAST(payload AS TEXT), '$.timeZoneID') = ?", values: [.text(localDate), .text(timeZoneID)], limit: 1).first
        if let row { let day = try database.decode(TrackingDay.self, row); try validateTrackingDayFields(day); return day }
        let day = TrackingDay(localDate: localDate, timeZoneID: timeZoneID, startAt: at)
        try validateTrackingDayFields(day)
        let payload = try JSONEncoder().encode(day)
        try database.execute("INSERT INTO day(id, ordinal, payload) VALUES (?, ?, ?)", [.text(day.id.uuidString), .integer(nextOrdinal("day")), .blob(payload)])
        try contribution(table: "day", rowID: day.id.uuidString, encodedBytes: payload.count)
        changes.dayIDs.insert(day.id); return day
    }
    func activateDay(_ day: TrackingDay) throws {
        try validateTrackingDayFields(day)
        guard try database.trackingDay(id: day.id) == day else { throw DiaryError.invalidData }
        if head.activeDayID != day.id {
            var boundary = UUID()
            while try boundary == head.effectiveConversationSegmentID || database.captureSegment(id: boundary) != nil { boundary = UUID() }
            head.activeDayID = day.id; head.activeConversationSegmentID = boundary
            head.effectiveConversationSegmentID = boundary; changes.coachLatestChanged = true
        }
        head.previousDayConfirmedAt = nil
    }
    func startDay(at: Date) throws -> TrackingDay {
        guard at.timeIntervalSince1970.isFinite else { throw DiaryError.invalidData }
        let day = try resolveDay(localDate: diaryDateLabel(at, zone: head.profile.timeZoneID), timeZoneID: head.profile.timeZoneID, at: at)
        try activateDay(day); try resolveDayChoices(at: at, dayID: day.id); return day
    }
    func saveDay(_ day: TrackingDay) throws {
        try validateTrackingDayFields(day); _ = try database.trackingDay(id: day.id)
        let payload = try JSONEncoder().encode(day)
        try database.execute("UPDATE day SET payload = ? WHERE id = ?", [.blob(payload), .text(day.id.uuidString)])
        try contribution(table: "day", rowID: day.id.uuidString, encodedBytes: payload.count); changes.dayIDs.insert(day.id)
    }
    func resolveDayChoices(at: Date, dayID: UUID) throws {
        guard at.timeIntervalSince1970.isFinite else { throw DiaryError.invalidData }
        let rows = try records("coach_turn", clause: "json_extract(CAST(payload AS TEXT), '$.needsDayChoice') = 1 AND json_extract(CAST(payload AS TEXT), '$.state') = 'needsClarification'", values: [])
        for row in rows {
            guard let id = UUID(uuidString: row.id), var turn = try turn(id: id) else { throw DiaryError.invalidData }
            if diaryDateLabel(turn.capturedAt, zone: turn.captureTimeZoneID) == diaryDateLabel(at, zone: turn.captureTimeZoneID) {
                turn.resolvedDayID = dayID; turn.needsDayChoice = nil; try saveTurn(turn)
            }
        }
    }
    func mealItems(id: UUID) throws -> [FoodItem] {
        let result = try records("item", clause: "parent = ?", values: [.text(id.uuidString)], limit: 201).map { try database.decode(FoodItem.self, $0, composite: true) }
        try validateItems(result); return result
    }
    func mealSubmissions(id: UUID) throws -> [MealSubmission] {
        let meal = try mealRecord(id: id)
        let result = try records("submission", clause: "parent = ?", values: [.text(id.uuidString)], limit: 1001).map { try database.decode(MealSubmission.self, $0) }
        guard result.count <= 1000 else { throw DiaryError.invalidData }
        for submission in result { try validateMealSubmissionFields(submission, mealID: id, mealRevision: meal.revision, profileID: head.profile.id) }; return result
    }
    func submissionParent(id: UUID) throws -> UUID? {
        let statement = try database.domainStatement("SELECT parent FROM submission WHERE id = ?", [.text(id.uuidString)])
        defer { sqlite3_finalize(statement) }; return try database.mutationStep(statement) ? database.mutationOptionalUUID(statement, 0) : nil
    }
    func submission(id: UUID, mealID: UUID) throws -> MealSubmission {
        guard let row = try records("submission", clause: "id = ? AND parent = ?", values: [.text(id.uuidString), .text(mealID.uuidString)], limit: 1).first else { throw DiaryError.notFound }
        let submission = try database.decode(MealSubmission.self, row), meal = try mealRecord(id: mealID)
        try validateMealSubmissionFields(submission, mealID: mealID, mealRevision: meal.revision, profileID: head.profile.id); return submission
    }
    func insertMeal(_ meal: DiaryMeal) throws {
        guard meal.items.isEmpty, meal.submissions.isEmpty, meal.photos.isEmpty, try database.mutationInteger("SELECT COUNT(*) FROM tombstone WHERE id = ?", [.text(meal.id.uuidString)]) == 0 else { throw DiaryError.invalidData }
        _ = try database.trackingDay(id: meal.dayID); try validateMealFields(meal, itemCount: 0)
        let payload = try JSONEncoder().encode(meal)
        try database.execute("INSERT INTO meal(id, parent, ordinal, payload) VALUES (?, ?, ?, ?)", [.text(meal.id.uuidString), .text(meal.dayID.uuidString), .integer(nextOrdinal("meal")), .blob(payload)])
        try contribution(table: "meal", rowID: meal.id.uuidString, encodedBytes: payload.count)
        changes.mealIDs.insert(meal.id); changes.dayIDs.insert(meal.dayID)
    }
    func saveMeal(_ meal: DiaryMeal) throws {
        guard meal.items.isEmpty, meal.submissions.isEmpty, meal.photos.isEmpty else { throw DiaryError.invalidData }
        _ = try database.trackingDay(id: meal.dayID)
        try validateMealFields(meal, itemCount: database.mutationInteger("SELECT COUNT(*) FROM item WHERE parent = ?", [.text(meal.id.uuidString)]))
        let payload = try JSONEncoder().encode(meal)
        try database.execute("UPDATE meal SET parent = ?, payload = ? WHERE id = ?", [.text(meal.dayID.uuidString), .blob(payload), .text(meal.id.uuidString)])
        guard sqlite3_changes(database.connection) == 1 else { throw DiaryError.notFound }
        try contribution(table: "meal", rowID: meal.id.uuidString, encodedBytes: payload.count)
        changes.mealIDs.insert(meal.id); changes.dayIDs.insert(meal.dayID)
    }
    func saveSubmission(_ submission: MealSubmission, meal: DiaryMeal) throws {
        try validateMealSubmissionFields(submission, mealID: meal.id, mealRevision: meal.revision, profileID: head.profile.id)
        if let parent = try submissionParent(id: submission.id) { guard parent == meal.id else { throw DiaryError.invalidData } }
        let payload = try JSONEncoder().encode(submission)
        try database.execute("INSERT INTO submission(id, parent, ordinal, payload) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload",
            [.text(submission.id.uuidString), .text(meal.id.uuidString), .integer(nextOrdinal("submission", parent: meal.id)), .blob(payload)])
        try contribution(table: "submission", rowID: submission.id.uuidString, parentID: meal.id.uuidString, encodedBytes: payload.count)
        changes.mealIDs.insert(meal.id); changes.dayIDs.insert(meal.dayID)
    }
    func replaceItems(_ items: [FoodItem], mealID: UUID) throws {
        try validateItems(items)
        for row in try records("item", clause: "parent = ?", values: [.text(mealID.uuidString)]) {
            try removeContribution(table: "item", rowID: row.id)
            try database.execute("DELETE FROM item WHERE id = ?", [.text(row.id)])
        }
        for (ordinal, item) in items.enumerated() {
            let id = mealID.uuidString + "/" + item.id.uuidString, payload = try JSONEncoder().encode(item)
            try database.execute("INSERT INTO item(id, parent, ordinal, payload) VALUES (?, ?, ?, ?)", [.text(id), .text(mealID.uuidString), .integer(ordinal), .blob(payload)])
            try contribution(table: "item", rowID: id, parentID: mealID.uuidString, encodedBytes: payload.count)
        }
    }
    func setSubmissionState(mealID: UUID, submissionID: UUID, state: SubmissionState) throws {
        let meal = try mealRecord(id: mealID)
        var submission = try submission(id: submissionID, mealID: mealID)
        guard submission.state != .cancelled else { throw DiaryError.notFound }
        submission.state = state; try saveSubmission(submission, meal: meal)
    }
    func applyAnalysis(_ output: AnalysisOutput) throws {
        guard output.profileID == head.profile.id else { throw DiaryError.wrongOwner }
        guard output.schemaVersion == 1, !output.items.isEmpty else { throw DiaryError.invalidData }; try validateItems(output.items)
        var meal = try mealRecord(id: output.mealID), submission = try submission(id: output.submissionID, mealID: output.mealID)
        if submission.state == .saved || submission.state == .awaitingReview { return }
        guard submission.state != .cancelled else { throw DiaryError.notFound }
        guard output.baseRevision == meal.revision, output.baseRevision == submission.baseRevision else { throw DiaryError.staleRevision }
        submission.proposal = output
        if submission.reviewFirst { submission.state = .awaitingReview }
        else { try replaceItems(output.items, mealID: meal.id); meal.revision += 1; try saveMeal(meal); submission.state = .saved }
        try saveSubmission(submission, meal: meal)
    }
    func acceptReview(mealID: UUID, submissionID: UUID) throws {
        var meal = try mealRecord(id: mealID), submission = try submission(id: submissionID, mealID: mealID)
        if submission.state == .saved { return }
        guard submission.state == .awaitingReview, let proposal = submission.proposal else { throw DiaryError.invalidData }
        guard meal.revision == proposal.baseRevision else { throw DiaryError.staleRevision }
        try replaceItems(proposal.items, mealID: mealID); meal.revision += 1; try saveMeal(meal)
        submission.state = .saved; try saveSubmission(submission, meal: meal)
    }
    func editItem(mealID: UUID, item: FoodItem, explicitNutrients: Set<String>, reviewSubmissionID: UUID?, expectedRevision: Int?) throws {
        var meal = try mealRecord(id: mealID)
        guard expectedRevision == nil || expectedRevision == meal.revision else { throw DiaryError.staleRevision }
        if let reviewSubmissionID {
            var submission = try submission(id: reviewSubmissionID, mealID: mealID)
            guard submission.state == .awaitingReview, var proposal = submission.proposal, let index = proposal.items.firstIndex(where: { $0.id == item.id }) else { throw DiaryError.notFound }
            guard submission.baseRevision == meal.revision else { throw DiaryError.staleRevision }
            proposal.items[index] = try diaryCorrectedItem(item, previous: proposal.items[index], explicitNutrients: explicitNutrients); try validateItems(proposal.items)
            submission.proposal = proposal; try saveSubmission(submission, meal: meal); return
        }
        var items = try mealItems(id: mealID)
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { throw DiaryError.notFound }
        items[index] = try diaryCorrectedItem(item, previous: items[index], explicitNutrients: explicitNutrients); try validateItems(items)
        let physicalID = mealID.uuidString + "/" + item.id.uuidString, payload = try JSONEncoder().encode(items[index])
        try database.execute("UPDATE item SET payload = ? WHERE id = ?", [.blob(payload), .text(physicalID)])
        try contribution(table: "item", rowID: physicalID, parentID: mealID.uuidString, encodedBytes: payload.count)
        let id = UUID(), output = AnalysisOutput(profileID: head.profile.id, mealID: mealID, submissionID: id, baseRevision: meal.revision, items: items)
        let saved = MealSubmission(id: id, baseRevision: meal.revision, text: "Direct item edit", photoIDs: [], reviewFirst: false, state: .saved, proposal: output)
        meal.revision += 1; try saveMeal(meal); try saveSubmission(saved, meal: meal)
    }
    func moveMeal(_ mealID: UUID, to dayID: UUID, eatenAt: Date?, expectedRevision: Int?, expectedDayID: UUID?) throws {
        var meal = try mealRecord(id: mealID); let day = try database.trackingDay(id: dayID)
        guard expectedRevision == nil || expectedRevision == meal.revision, expectedDayID == nil || expectedDayID == meal.dayID else { throw DiaryError.staleRevision }
        changes.dayIDs.insert(meal.dayID); meal.dayID = dayID
        if let eatenAt {
            guard eatenAt.timeIntervalSince1970.isFinite, diaryDateLabel(eatenAt, zone: day.timeZoneID) == day.localDate else { throw DiaryError.invalidData }
            meal.eatenAt = eatenAt; meal.timePrecision = .exact
        }
        try saveMeal(meal)
    }
    func validateManualRetry(submissionID: UUID, text: String, photos: [MealPhoto]) throws {
        // Accepted context wins over a later retry clock/day. Legacy evidence is never fingerprinted retroactively.
        guard let accepted = try turn(id: submissionID), let manifest = accepted.submissionManifest else { return }
        let attempted = try CoachSubmissionPayload(submissionID: submissionID, text: text, attachments: photos, context: manifest.context,
            pendingMealID: manifest.pendingMealID, pendingMealRevision: manifest.pendingMealRevision)
        guard attempted.manifest == manifest else { throw DiaryError.staleRevision }
    }
    func appendManualCapture(meal: DiaryMeal, submissionID: UUID, text: String, photos: [MealPhoto], at: Date) throws {
        let context = CoachCaptureContext(capturedAt: at, timeZoneID: head.profile.timeZoneID, activeDayID: head.activeDayID,
            previousDayConfirmedAt: head.previousDayConfirmedAt, activeConversationSegmentID: head.effectiveConversationSegmentID)
        let payload = try CoachSubmissionPayload(submissionID: submissionID, text: text, attachments: photos, context: context, pendingMealID: meal.id, pendingMealRevision: meal.revision)
        try appendCapture(payload)
        guard var turn = try turn(id: submissionID) else { throw DiaryError.invalidData }
        turn.pendingMealID = meal.id; turn.pendingMealRevision = meal.revision; turn.resolvedDayID = meal.dayID; try saveTurn(turn)
        try database.execute("INSERT INTO record_source(kind, recordID, turnID, relation) VALUES ('meal', ?, ?, ?)", [.text(meal.id.uuidString), .text(turn.id.uuidString), .text(meal.revision == 0 ? "origin" : "reference")])
        for photo in photos { try transferPhoto(photoID: photo.id, from: .coachTurn(turn.id), to: .meal(meal.id), consumers: [turn.id], removeSource: true) }
    }
}

extension DiaryTransaction {
    struct PhotoMetadata {
        var photo: MealPhoto
        var encodedBytes: Int
        var originalBytes: Int
        var token: UUID
        var ordinal: Int
    }
    func photoMetadata(photoID: UUID, owner: DiaryPhotoOwner) throws -> PhotoMetadata? {
        let scope = diaryPhotoScope(owner), physicalID = scope.parent.uuidString + "/" + photoID.uuidString
        let statement = try database.domainStatement("SELECT p.payload, length(p.bytes), c.contentToken, k.encodedBytes, k.originalPhotoBytes, p.ordinal FROM \(scope.table) p JOIN photo_content c ON c.physicalID = p.id AND c.ownerKind = ? JOIN storage_contribution k ON k.tableName = ? AND k.rowID = p.id WHERE p.id = ? AND p.parent = ? AND c.parentID = ? AND c.photoID = ?",
            [.text(scope.kind), .text(scope.table), .text(physicalID), .text(scope.parent.uuidString), .text(scope.parent.uuidString), .text(photoID.uuidString)])
        defer { sqlite3_finalize(statement) }; guard try database.mutationStep(statement) else { return nil }
        let photo = try JSONDecoder().decode(MealPhoto.self, from: database.mutationBlob(statement, 0))
        let size = Int(sqlite3_column_int64(statement, 1))
        guard photo.id == photoID, photo.data.isEmpty, size == Int(sqlite3_column_int64(statement, 4)), let token = try database.mutationOptionalUUID(statement, 2) else { throw DiaryError.invalidData }
        try validatePhotoFields(photo, byteCount: size)
        return PhotoMetadata(photo: photo, encodedBytes: Int(sqlite3_column_int64(statement, 3)), originalBytes: size, token: token, ordinal: Int(sqlite3_column_int64(statement, 5)))
    }
    func photoReferences(owner: DiaryPhotoOwner) throws -> [DiaryPhotoReference] {
        let scope = diaryPhotoScope(owner)
        let rows = try records(scope.table, clause: "parent = ?", values: [.text(scope.parent.uuidString)], limit: 31)
        guard rows.count <= 30 else { throw DiaryError.invalidData }
        return try rows.map { row in
            let metadata = try database.decode(MealPhoto.self, row, composite: true)
            guard let stored = try photoMetadata(photoID: metadata.id, owner: owner) else { throw DiaryError.invalidData }
            return DiaryPhotoReference(profileID: head.profile.id, owner: owner, photoID: metadata.id, createdAt: stored.photo.createdAt, role: stored.photo.role, contentToken: stored.token)
        }
    }
    func insertPhoto(_ photo: MealPhoto, owner: DiaryPhotoOwner) throws {
        try validatePhotoFields(photo, byteCount: photo.data.count)
        let scope = diaryPhotoScope(owner), id = scope.parent.uuidString + "/" + photo.id.uuidString
        switch owner {
        case .meal(let parent): _ = try mealRecord(id: parent); changes.mealIDs.insert(parent)
        case .coachTurn(let parent): guard let turn = try turn(id: parent), turn.photoIDs.contains(photo.id) else { throw DiaryError.invalidData }; changes.turnIDs.insert(parent)
        }
        guard try database.mutationInteger("SELECT COUNT(*) FROM \(scope.table) WHERE id = ?", [.text(id)]) == 0 else { throw DiaryError.invalidData }
        var metadata = photo; metadata.data = Data()
        try database.execute("INSERT INTO \(scope.table)(id, parent, ordinal, payload, bytes) VALUES (?, ?, ?, ?, ?)", [.text(id), .text(scope.parent.uuidString), .integer(nextOrdinal(scope.table, parent: scope.parent)), .blob(try JSONEncoder().encode(metadata)), .blob(photo.data)])
        try contribution(table: scope.table, rowID: id, parentID: scope.parent.uuidString, encodedBytes: JSONEncoder().encode(photo).count, originalPhotoBytes: photo.data.count)
        try database.execute("INSERT INTO photo_content(ownerKind, parentID, photoID, physicalID, contentToken, mealPhysicalID, coachPhysicalID) VALUES (?, ?, ?, ?, ?, ?, ?)", [.text(scope.kind), .text(scope.parent.uuidString), .text(photo.id.uuidString), .text(id), .text(UUID().uuidString), scope.kind == "meal" ? .text(id) : .null, scope.kind == "coachTurn" ? .text(id) : .null])
    }
    func replacePhoto(_ photo: MealPhoto, mealID: UUID) throws {
        _ = try mealRecord(id: mealID); try validatePhotoFields(photo, byteCount: photo.data.count)
        guard try photoMetadata(photoID: photo.id, owner: .meal(mealID)) != nil else { throw DiaryError.notFound }
        let id = mealID.uuidString + "/" + photo.id.uuidString
        var metadata = photo; metadata.data = Data()
        try database.execute("UPDATE photo SET payload = ?, bytes = ? WHERE id = ?", [.blob(try JSONEncoder().encode(metadata)), .blob(photo.data), .text(id)])
        try database.execute("UPDATE photo_content SET contentToken = ? WHERE ownerKind = 'meal' AND parentID = ? AND photoID = ?", [.text(UUID().uuidString), .text(mealID.uuidString), .text(photo.id.uuidString)])
        try contribution(table: "photo", rowID: id, parentID: mealID.uuidString, encodedBytes: JSONEncoder().encode(photo).count, originalPhotoBytes: photo.data.count)
        changes.mealIDs.insert(mealID)
        for turnID in try photoConsumers(photoID: photo.id, owner: .meal(mealID)) { changes.turnIDs.insert(turnID) }
    }
    func updatePhotoRole(mealID: UUID, photoID: UUID, role: PhotoRole) throws {
        _ = try mealRecord(id: mealID)
        guard let stored = try photoMetadata(photoID: photoID, owner: .meal(mealID)) else { throw DiaryError.notFound }
        var metadata = stored.photo; metadata.role = role
        let payload = try JSONEncoder().encode(metadata), oldBytes = try JSONEncoder().encode(stored.photo).count
        let id = mealID.uuidString + "/" + photoID.uuidString
        try database.execute("UPDATE photo SET payload = ? WHERE id = ?", [.blob(payload), .text(id)])
        try contribution(table: "photo", rowID: id, parentID: mealID.uuidString, encodedBytes: stored.encodedBytes + payload.count - oldBytes, originalPhotoBytes: stored.originalBytes)
        changes.mealIDs.insert(mealID)
        for turnID in try photoConsumers(photoID: photoID, owner: .meal(mealID)) { changes.turnIDs.insert(turnID) }
    }
    /// Bounded SQL copy retains exact original bytes without loading them into Swift.
    func transferPhoto(photoID: UUID, from source: DiaryPhotoOwner, to destination: DiaryPhotoOwner, consumers: [UUID], removeSource: Bool) throws {
        guard source != destination, Set(consumers).count == consumers.count, let stored = try photoMetadata(photoID: photoID, owner: source) else { throw DiaryError.invalidData }
        let old = diaryPhotoScope(source), new = diaryPhotoScope(destination)
        let oldID = old.parent.uuidString + "/" + photoID.uuidString, newID = new.parent.uuidString + "/" + photoID.uuidString
        guard try database.mutationInteger("SELECT COUNT(*) FROM \(new.table) WHERE id = ?", [.text(newID)]) == 0 else { throw DiaryError.invalidData }
        switch destination {
        case .meal(let id): _ = try mealRecord(id: id); changes.mealIDs.insert(id)
        case .coachTurn(let id): guard let turn = try turn(id: id), turn.photoIDs.contains(photoID) else { throw DiaryError.invalidData }; changes.turnIDs.insert(id)
        }
        if removeSource { guard Set(try photoConsumers(photoID: photoID, owner: source)) == Set(consumers) else { throw DiaryError.invalidData } }
        for id in consumers {
            guard let turn = try turn(id: id), turn.photoIDs.contains(photoID) else { throw DiaryError.invalidData }
            switch destination {
            case .coachTurn(let parent): guard parent == id else { throw DiaryError.invalidData }
            case .meal(let parent): guard turn.pendingMealID == parent || turn.receipts.contains(where: { $0.mealID == parent }) else { throw DiaryError.invalidData }
            }
        }
        try database.execute("INSERT INTO \(new.table)(id, parent, ordinal, payload, bytes) SELECT ?, ?, ?, payload, bytes FROM \(old.table) WHERE id = ?", [.text(newID), .text(new.parent.uuidString), .integer(nextOrdinal(new.table, parent: new.parent)), .text(oldID)])
        guard sqlite3_changes(database.connection) == 1 else { throw DiaryError.invalidData }
        try contribution(table: new.table, rowID: newID, parentID: new.parent.uuidString, encodedBytes: stored.encodedBytes, originalPhotoBytes: stored.originalBytes)
        try database.execute("INSERT INTO photo_content(ownerKind, parentID, photoID, physicalID, contentToken, mealPhysicalID, coachPhysicalID) VALUES (?, ?, ?, ?, ?, ?, ?)", [.text(new.kind), .text(new.parent.uuidString), .text(photoID.uuidString), .text(newID), .text(UUID().uuidString), new.kind == "meal" ? .text(newID) : .null, new.kind == "coachTurn" ? .text(newID) : .null])
        for id in consumers {
            try database.execute("INSERT INTO photo_consumer(ownerKind, parentID, photoID, turnID) VALUES (?, ?, ?, ?)", [.text(new.kind), .text(new.parent.uuidString), .text(photoID.uuidString), .text(id.uuidString)])
            changes.turnIDs.insert(id)
        }
        if removeSource { try removePhoto(photoID: photoID, owner: source) }
    }
    func photoConsumers(photoID: UUID, owner: DiaryPhotoOwner) throws -> [UUID] {
        let scope = diaryPhotoScope(owner)
        return try ids("SELECT turnID FROM photo_consumer WHERE ownerKind = ? AND parentID = ? AND photoID = ? ORDER BY turnID", [.text(scope.kind), .text(scope.parent.uuidString), .text(photoID.uuidString)])
    }
    func ids(_ sql: String, _ values: [DiaryDatabase.Value]) throws -> [UUID] {
        let statement = try database.domainStatement(sql, values); defer { sqlite3_finalize(statement) }
        var result: [UUID] = []
        while try database.mutationStep(statement) { guard let id = try database.mutationOptionalUUID(statement, 0) else { throw DiaryError.invalidData }; result.append(id) }; return result
    }
    func removePhoto(photoID: UUID, owner: DiaryPhotoOwner) throws {
        let scope = diaryPhotoScope(owner), id = scope.parent.uuidString + "/" + photoID.uuidString
        guard try photoMetadata(photoID: photoID, owner: owner) != nil else { throw DiaryError.notFound }
        try removeContribution(table: scope.table, rowID: id)
        try database.execute("DELETE FROM \(scope.table) WHERE id = ?", [.text(id)])
    }
    func stripUnusedPhotoID(_ photoID: UUID, turnID: UUID) throws {
        guard var turn = try turn(id: turnID) else { throw DiaryError.invalidData }
        if try database.mutationInteger("SELECT COUNT(*) FROM photo_consumer WHERE turnID = ? AND photoID = ?", [.text(turnID.uuidString), .text(photoID.uuidString)]) == 0 {
            turn.photoIDs.removeAll { $0 == photoID }; try saveTurn(turn)
        }
        changes.turnIDs.insert(turnID)
    }
    func deleteMealPhoto(mealID: UUID, photoID: UUID) throws {
        let meal = try mealRecord(id: mealID)
        guard try photoMetadata(photoID: photoID, owner: .meal(mealID)) != nil else { return }
        let consumers = try photoConsumers(photoID: photoID, owner: .meal(mealID))
        try removePhoto(photoID: photoID, owner: .meal(mealID))
        for turnID in consumers { try stripUnusedPhotoID(photoID, turnID: turnID) }
        for var submission in try mealSubmissions(id: mealID) where submission.photoIDs.contains(photoID) {
            if submission.state != .saved { submission.state = .cancelled; submission.proposal = nil }
            submission.photoIDs.removeAll { $0 == photoID }; try saveSubmission(submission, meal: meal)
        }
        changes.mealIDs.insert(mealID); changes.dayIDs.insert(meal.dayID)
    }
    func hasSurvivingProgress(_ turn: CoachTurn) throws -> Bool {
        if try database.mutationInteger("SELECT EXISTS(SELECT 1 FROM record_source r WHERE r.turnID = ? AND ((r.kind = 'weight' AND EXISTS(SELECT 1 FROM weight w WHERE w.id = r.recordID)) OR (r.kind = 'workout' AND EXISTS(SELECT 1 FROM workout w WHERE w.id = r.recordID))))", [.text(turn.id.uuidString)]) == 1 { return true }
        for receipt in turn.receipts {
            if let id = receipt.weightID, try database.mutationInteger("SELECT COUNT(*) FROM weight WHERE id = ?", [.text(id.uuidString)]) == 1 { return true }
            if let id = receipt.workoutID, try database.mutationInteger("SELECT COUNT(*) FROM workout WHERE id = ?", [.text(id.uuidString)]) == 1 { return true }
        }
        return false
    }
    func deleteMeal(_ mealID: UUID) throws {
        let meal = try mealRecord(id: mealID)
        for photo in try photoReferences(owner: .meal(mealID)) {
            let consumers = try photoConsumers(photoID: photo.photoID, owner: .meal(mealID))
            for turnID in consumers {
                guard let turn = try turn(id: turnID) else { throw DiaryError.invalidData }
                if try hasSurvivingProgress(turn) { try transferPhoto(photoID: photo.photoID, from: .meal(mealID), to: .coachTurn(turnID), consumers: [turnID], removeSource: false) }
            }
            try removePhoto(photoID: photo.photoID, owner: .meal(mealID))
            for turnID in consumers { try stripUnusedPhotoID(photo.photoID, turnID: turnID) }
        }
        let linked = try ids("SELECT turnID FROM record_source WHERE kind = 'meal' AND recordID = ? UNION SELECT turnID FROM coach_index WHERE pendingMealID = ?", [.text(mealID.uuidString), .text(mealID.uuidString)])
        for turnID in linked {
            guard var turn = try turn(id: turnID) else { throw DiaryError.invalidData }
            if turn.pendingMealID == mealID { turn.state = .needsClarification; try saveTurn(turn) }
            changes.turnIDs.insert(turnID)
        }
        for table in ["submission", "item"] {
            for row in try records(table, clause: "parent = ?", values: [.text(mealID.uuidString)]) { try removeContribution(table: table, rowID: row.id) }
        }
        try removeContribution(table: "meal", rowID: mealID.uuidString)
        try database.execute("DELETE FROM record_source WHERE kind = 'meal' AND recordID = ?", [.text(mealID.uuidString)])
        try database.execute("DELETE FROM meal WHERE id = ?", [.text(mealID.uuidString)])
        let payload = try JSONEncoder().encode(mealID)
        try database.execute("INSERT INTO tombstone(id, ordinal, payload) VALUES (?, ?, ?)", [.text(mealID.uuidString), .integer(nextOrdinal("tombstone")), .blob(payload)])
        try contribution(table: "tombstone", rowID: mealID.uuidString, encodedBytes: payload.count)
        changes.mealIDs.insert(mealID); changes.dayIDs.insert(meal.dayID)
    }
}

func diaryDateLabel(_ at: Date, zone: String) -> String {
    let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(identifier: zone)
    return formatter.string(from: at)
}

private func diaryPhotoScope(_ owner: DiaryPhotoOwner) -> (table: String, kind: String, parent: UUID) {
    switch owner { case .meal(let id): ("photo", "meal", id); case .coachTurn(let id): ("coach_photo", "coachTurn", id) }
}

func diaryCorrectedItem(_ item: FoodItem, previous: FoodItem, explicitNutrients: Set<String>) throws -> FoodItem {
    try validateItems([item])
    let nutrients: [(String, WritableKeyPath<NutritionValues, Double?>)] = [("kcal", \.kcal), ("carbs", \.carbs), ("protein", \.protein), ("fat", \.fat)]
    guard explicitNutrients.isSubset(of: Set(nutrients.map(\.0))) else { throw DiaryError.invalidData }
    let conversion = diaryUnitConversion(from: previous.unit, to: item.unit)
    var edited = item
    edited.nutrientSources = previous.nutrientSources
    var basis = NutritionValues()
    for (name, field) in nutrients {
        let explicit = explicitNutrients.contains(name)
        guard explicit || item.nutrition[keyPath: field] == previous.nutrition[keyPath: field] else { throw DiaryError.invalidData }
        let oldValue = previous.nutrition[keyPath: field]
        let oldBasis = previous.quantity > 0 ? oldValue.map { $0 / previous.quantity } : previous.nutritionBasis?[keyPath: field]
        if explicit {
            edited.nutrientSources[name] = .user
        } else {
            guard let conversion else {
                guard oldValue == nil else { throw DiaryError.invalidAmountUnitChange }
                edited.nutrition[keyPath: field] = nil
                continue
            }
            let convertedBasis = oldBasis.map { $0 * conversion }
            if item.quantity > 0 {
                guard oldValue == nil || convertedBasis != nil else { throw DiaryError.invalidAmountUnitChange }
                edited.nutrition[keyPath: field] = oldValue == nil ? nil : convertedBasis.map { $0 * item.quantity }
            } else {
                edited.nutrition[keyPath: field] = oldValue.map { _ in 0 }
                basis[keyPath: field] = convertedBasis
            }
            if oldValue != nil && !explicitNutrients.isEmpty { edited.nutrientSources[name] = previous.nutrientSources[name] ?? previous.provenance }
        }
        if item.quantity > 0 { basis[keyPath: field] = edited.nutrition[keyPath: field].map { $0 / item.quantity } }
    }
    edited.nutritionBasis = basis
    edited.provenance = explicitNutrients.isEmpty ? previous.provenance : .user
    edited.reference = previous.reference
    edited.uncertain = previous.uncertain || edited.nutrientSources.values.contains { [.sample, .estimate].contains($0) }
    return edited
}

private func diaryUnitConversion(from previous: String, to edited: String) -> Double? {
    if previous == edited { return 1 }
    func unit(_ label: String) -> (family: String, factor: Double)? {
        switch label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mg", "milligram", "milligrams": ("mass", 0.001)
        case "g", "gram", "grams": ("mass", 1)
        case "kg", "kilogram", "kilograms": ("mass", 1000)
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres": ("volume", 1)
        case "l", "liter", "liters", "litre", "litres": ("volume", 1000)
        default: nil
        }
    }
    guard let from = unit(previous), let to = unit(edited), from.family == to.family else { return nil }
    return to.factor / from.factor
}
