import Foundation
import SQLite3

extension DiaryDatabase {
    func nextPendingCoachTurn(includeWaitingForConnection: Bool, capturedOnly: Bool = false, expectedProfileID: UUID) throws -> CoachWorkItem? {
        try domainRead(expectedProfileID: expectedProfileID) { head in
            let states: String
            if capturedOnly { states = "'captured','analyzing'" }
            else { states = includeWaitingForConnection ? "'captured','analyzing','waitingForNetwork','waitingForConnection'" : "'captured','analyzing','waitingForNetwork'" }
            let statement = try domainStatement("SELECT turnID FROM coach_index WHERE state IN (\(states)) ORDER BY sequence LIMIT 1")
            defer { sqlite3_finalize(statement) }
            guard try mutationStep(statement), let id = try mutationOptionalUUID(statement, 0) else { return nil }
            return try workerItem(id, head: head)
        }
    }
    func nextUnlinkedPendingSubmission(expectedProfileID: UUID) throws -> PendingSubmissionReference? {
        try domainRead(expectedProfileID: expectedProfileID) { head in
            let statement = try domainStatement("SELECT s.id, s.parent FROM submission s WHERE json_extract(CAST(s.payload AS TEXT), '$.state') IN ('captured','waitingForConnection','analyzing','needsRetry') AND NOT EXISTS (SELECT 1 FROM coach_turn t WHERE t.id = s.id) ORDER BY s.ordinal, s.id LIMIT 1")
            defer { sqlite3_finalize(statement) }
            guard try mutationStep(statement), let id = try mutationOptionalUUID(statement, 0), let parent = try mutationOptionalUUID(statement, 1) else { return nil }
            let transaction = DiaryTransaction(database: self, head: head)
            let meal = try transaction.mealRecord(id: parent), submission = try transaction.submission(id: id, mealID: parent)
            let day = try trackingDay(id: meal.dayID), ids = Set(submission.photoIDs)
            return PendingSubmissionReference(mealID: parent, submissionID: id, mealRevision: meal.revision,
                baseRevision: submission.baseRevision, capturedAt: meal.capturedAt, text: submission.text, state: submission.state,
                dayID: day.id, timeZoneID: day.timeZoneID, photos: try transaction.photoReferences(owner: .meal(parent)).filter { ids.contains($0.photoID) })
        }
    }
    func coachWorkItem(turnID: UUID, expectedProfileID: UUID) throws -> CoachWorkItem {
        try domainRead(expectedProfileID: expectedProfileID) { try workerItem(turnID, head: $0) }
    }
    private func workerItem(_ id: UUID, head: DiaryHead) throws -> CoachWorkItem {
        let transaction = DiaryTransaction(database: self, head: head)
        guard let turn = try transaction.turn(id: id) else { throw DiaryError.notFound }
        let statement = try domainStatement("SELECT sequence FROM coach_index WHERE turnID = ?", [.text(id.uuidString)])
        defer { sqlite3_finalize(statement) }; guard try mutationStep(statement) else { throw DiaryError.notFound }
        let references = try coachExchangeSummary(turnID: id, expectedProfileID: head.profile.id).photos
        return CoachWorkItem(id: id, sequence: sqlite3_column_int64(statement, 0), capturedAt: turn.capturedAt,
            text: turn.text, state: turn.state, assistantText: turn.assistantText, receipts: turn.receipts,
            captureTimeZoneID: turn.captureTimeZoneID, activeDayID: turn.activeDayID, resolvedDayID: turn.resolvedDayID,
            needsDayChoice: turn.needsDayChoice, pendingMealID: turn.pendingMealID, pendingMealRevision: turn.pendingMealRevision, photos: references)
    }
    func prepareCoachWork(turnID: UUID, at: Date, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { transaction in
            let existing = try transaction.turn(id: turnID)
            if let existing, existing.pendingMealID == nil { return }
            guard existing == nil || (existing!.state != .analyzing && existing!.state != .completed && existing!.receipts.isEmpty) else { throw DiaryError.staleRevision }
            guard let mealID = try transaction.submissionParent(id: turnID) else { throw DiaryError.notFound }
            let meal = try transaction.mealRecord(id: mealID)
            guard existing == nil || existing!.pendingMealID == mealID else { throw DiaryError.staleRevision }
            var submission = try transaction.submission(id: turnID, mealID: mealID)
            guard [.captured, .waitingForConnection, .analyzing, .needsRetry].contains(submission.state) else { throw DiaryError.staleRevision }
            submission.baseRevision = meal.revision; submission.proposal = nil; submission.state = .captured
            try transaction.saveSubmission(submission, meal: meal)
            if var existing { existing.pendingMealRevision = meal.revision; try transaction.saveTurn(existing) }
            else {
                let day = try trackingDay(id: meal.dayID)
                let context = CoachCaptureContext(capturedAt: meal.capturedAt, timeZoneID: day.timeZoneID,
                    activeDayID: nil, previousDayConfirmedAt: nil)
                try transaction.appendLegacyCapture(submissionID: turnID, text: submission.text, context: context,
                    meal: meal, photoIDs: submission.photoIDs)
                for photo in submission.photoIDs {
                    guard try transaction.photoMetadata(photoID: photo, owner: .meal(mealID)) != nil else { throw DiaryError.notFound }
                    try execute("INSERT OR IGNORE INTO photo_consumer(ownerKind,parentID,photoID,turnID) VALUES ('meal',?,?,?)", [.text(mealID.uuidString), .text(photo.uuidString), .text(turnID.uuidString)])
                }
                try execute("INSERT OR IGNORE INTO record_source(kind,recordID,turnID,relation) VALUES ('meal',?,?, 'reference')", [.text(mealID.uuidString), .text(turnID.uuidString)])
            }
        }
    }
    func coachMeals(on date: String, afterMealID: UUID? = nil, expectedProfileID: UUID) throws -> CoachMealCandidatePage {
        guard validLocalDate(date) else { throw DiaryError.invalidData }
        return try domainRead(expectedProfileID: expectedProfileID) { head in
            let transaction = DiaryTransaction(database: self, head: head)
            if let cursor = afterMealID {
                let meal = try transaction.mealRecord(id: cursor)
                guard try trackingDay(id: meal.dayID).localDate == date else { throw DiaryError.invalidData }
            }
            let statement = try domainStatement("SELECT m.id FROM day d JOIN meal m ON m.parent = d.id WHERE json_extract(CAST(d.payload AS TEXT), '$.localDate') = ? AND m.id > ? ORDER BY m.id LIMIT 21", [.text(date), .text(afterMealID?.uuidString ?? "")])
            defer { sqlite3_finalize(statement) }
            var ids: [UUID] = []; while try mutationStep(statement) { guard let id = try mutationOptionalUUID(statement, 0) else { throw DiaryError.invalidData }; ids.append(id) }
            let meals = try ids.prefix(20).map { try coachCandidate($0, transaction: transaction) }
            return CoachMealCandidatePage(localDate: date, meals: meals, hasMore: ids.count > 20, nextAfterMealID: ids.count > 20 ? meals.last?.id : nil)
        }
    }
    func coachFindMeals(query: String, from: String?, to: String?, expectedProfileID: UUID) throws -> [CoachMealCandidate] {
        guard !query.isEmpty, query.count <= 100, [from, to].allSatisfy({ $0.map(validLocalDate) ?? true }) else { throw DiaryError.invalidData }
        let pattern = "%" + query.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
        return try domainRead(expectedProfileID: expectedProfileID) { head in
            let transaction = DiaryTransaction(database: self, head: head)
            let statement = try domainStatement("""
                SELECT m.id FROM meal m JOIN day d ON m.parent = d.id
                WHERE EXISTS (SELECT 1 FROM item i WHERE i.parent = m.id AND json_extract(CAST(i.payload AS TEXT), '$.name') LIKE ? ESCAPE '\\')
                AND json_extract(CAST(d.payload AS TEXT), '$.localDate') >= ? AND json_extract(CAST(d.payload AS TEXT), '$.localDate') <= ?
                ORDER BY json_extract(CAST(m.payload AS TEXT), '$.eatenAt') DESC, m.ordinal DESC, m.id LIMIT 10
                """, [.text(pattern), .text(from ?? "0000-00-00"), .text(to ?? "9999-99-99")])
            defer { sqlite3_finalize(statement) }
            var ids: [UUID] = []; while try mutationStep(statement) { guard let id = try mutationOptionalUUID(statement, 0) else { throw DiaryError.invalidData }; ids.append(id) }
            return try ids.map { try coachCandidate($0, transaction: transaction) }
        }
    }
    private func coachCandidate(_ id: UUID, transaction: DiaryTransaction) throws -> CoachMealCandidate {
        let meal = try transaction.mealRecord(id: id), day = try trackingDay(id: meal.dayID)
        let itemCount = try mutationInteger("SELECT COUNT(*) FROM item WHERE parent = ?", [.text(id.uuidString)])
        let preview = try transaction.records("item", clause: "parent = ?", values: [.text(id.uuidString)], limit: 4).map { try decode(FoodItem.self, $0, composite: true) }
        try validateItems(preview)
        var items: [CoachMealCandidate.Item] = []
        for item in preview {
            let value = CoachMealCandidate.Item(id: item.id, name: coachBoundedText(item.name, bytes: 256), quantity: item.quantity, unit: item.unit)
            if try JSONEncoder().encode(items + [value]).count > 1200 { break }; items.append(value)
        }
        let submitted = try domainStatement("SELECT substr(json_extract(CAST(payload AS TEXT), '$.text'),1,513) FROM submission WHERE parent = ? ORDER BY ordinal, id LIMIT 1", [.text(id.uuidString)])
        defer { sqlite3_finalize(submitted) }
        var description = try mutationStep(submitted) ? mutationText(submitted, 0) : ""
        if description.isEmpty {
            let source = try domainStatement("SELECT substr(json_extract(CAST(t.payload AS TEXT), '$.text'),1,513) FROM record_source s JOIN coach_turn t ON t.id = s.turnID WHERE s.kind = 'meal' AND s.recordID = ? ORDER BY CASE s.relation WHEN 'origin' THEN 0 ELSE 1 END, t.ordinal LIMIT 1", [.text(id.uuidString)])
            defer { sqlite3_finalize(source) }; if try mutationStep(source) { description = try mutationText(source, 0) }
        }
        return CoachMealCandidate(id: id, dayID: day.id, localDate: day.localDate, timeZoneID: day.timeZoneID,
            revision: meal.revision, eatenAt: meal.eatenAt, timePrecision: meal.timePrecision, items: items,
            omittedItemCount: itemCount - items.count, capturedDescription: coachBoundedText(description, bytes: 512), descriptionTruncated: description.utf8.count > 512)
    }
    func coachMealDetail(id: UUID, expectedProfileID: UUID) throws -> CoachContext.Meal {
        try domainRead(expectedProfileID: expectedProfileID) { head in
            try coachMealDetail(id, transaction: DiaryTransaction(database: self, head: head))
        }
    }
    private func coachMealDetail(_ id: UUID, transaction: DiaryTransaction) throws -> CoachContext.Meal {
        let meal = try transaction.mealProjection(id: id)
        var value = CoachContext.Meal(id: id, dayID: meal.dayID, revision: meal.revision, eatenAt: meal.eatenAt,
            timePrecision: meal.timePrecision, items: [], state: meal.state, omittedItemCount: meal.items.count)
        for item in meal.items {
            value.items.append(item)
            if try JSONEncoder().encode(value).count > 48_000 { value.items.removeLast(); break }
            value.omittedItemCount -= 1
        }
        value.photos = meal.photos.map { .init(id: $0.photoID, role: $0.role) }; value.omittedPhotoCount = 0
        if let pending = meal.submissions.last(where: { $0.state == .awaitingReview }), let proposal = pending.proposal {
            value.review = .init(submissionID: pending.id, baseRevision: proposal.baseRevision, items: proposal.items)
        }
        guard try JSONEncoder().encode(value).count <= 60_000 else { throw CoachError.limitExceeded }; return value
    }
    /// Marks meals removed since, from any source, so Pip never treats an old receipt as a live record.
    private func receiptLine(_ receipts: [CoachReceipt]) throws -> String? {
        let parts = try receipts.compactMap { r -> String? in
            guard r.mealID != nil || r.itemID != nil else { return nil }
            let meal = try r.mealID.map { id in
                " meal=\(id.uuidString)" + (try mutationInteger("SELECT COUNT(*) FROM meal WHERE id = ?", [.text(id.uuidString)]) == 0 ? " deleted" : "")
            }
            return "saved key=\(r.operationKey)" + (meal ?? "") + (r.itemID.map { " item=\($0.uuidString)" } ?? "")
        }
        return parts.isEmpty ? nil : coachBoundedText("[" + parts.joined(separator: "; ") + "]", bytes: 1024)
    }
    func coachInferenceContext(turnID: UUID, expectedProfileID: UUID) throws -> CoachContext {
        try domainRead(expectedProfileID: expectedProfileID) { head in
            let transaction = DiaryTransaction(database: self, head: head), work = try workerItem(turnID, head: head)
            var profile = head.profile
            profile.name = coachBoundedText(profile.name, bytes: 512); profile.preferences = coachBoundedText(profile.preferences, bytes: 8192)
            let previous = try domainStatement("SELECT t.id, t.payload FROM coach_index i JOIN coach_turn t ON t.id = i.turnID WHERE i.sequence < ? ORDER BY i.sequence DESC LIMIT 12", [.integer(Int(work.sequence))])
            defer { sqlite3_finalize(previous) }
            var recent: [CoachContext.Turn] = []
            var pendingQuestion: CoachQuestion?
            while try mutationStep(previous) {
                diagnostics?.recordTurnDecode()
                let turn = try JSONDecoder().decode(CoachTurn.self, from: mutationBlob(previous, 1))
                if recent.isEmpty, turn.state == .completed { pendingQuestion = turn.question; pendingQuestion?.originalText = coachBoundedText(turn.text, bytes: 1024) } // only the immediately previous turn; bounded for the 60 KB cap
                recent.append(.init(id: turn.id, capturedAt: turn.capturedAt, text: coachBoundedText(turn.text, bytes: 1024), assistantText: turn.assistantText.map { coachBoundedText($0, bytes: 1024) }, receipts: try receiptLine(turn.receipts)))
            }
            recent.reverse(); while try JSONEncoder().encode(recent).count > 8192 { recent.removeFirst() }
            let daysQuery = try domainStatement("SELECT payload FROM day ORDER BY ordinal DESC, id DESC LIMIT 14")
            defer { sqlite3_finalize(daysQuery) }; var days: [TrackingDay] = []
            while try mutationStep(daysQuery) { days.append(try JSONDecoder().decode(TrackingDay.self, from: mutationBlob(daysQuery, 0))) }; days.reverse()
            var context = CoachContext(profile: profile, capturedAt: work.capturedAt, captureTimeZoneID: work.captureTimeZoneID,
                activeDayID: work.resolvedDayID ?? work.activeDayID, days: days, meals: [], weights: [], recentTurns: recent)
            context.diaryRevision = head.revision; context.goal = try transaction.goal(on: diaryDateLabel(work.capturedAt, zone: work.captureTimeZoneID))
            context.preferencesTruncated = profile.preferences != head.profile.preferences
            context.pendingMealID = work.pendingMealID; context.pendingMealRevision = work.pendingMealRevision
            context.attachedPhotoIDs = work.photos.map(\.photoID)
            let dayIDs = days.map { DiaryDatabase.Value.text($0.id.uuidString) }
            if !dayIDs.isEmpty {
                let placeholders = Array(repeating: "?", count: dayIDs.count).joined(separator: ",")
                context.additionalMealCount = max(0, try mutationInteger("SELECT COUNT(*) FROM meal WHERE parent IN (\(placeholders))", dayIDs) - 40)
                let meals = try domainStatement("SELECT id FROM meal WHERE parent IN (\(placeholders)) ORDER BY ordinal DESC, id DESC LIMIT 40", dayIDs)
                defer { sqlite3_finalize(meals) }
                while try mutationStep(meals) {
                    guard let id = try mutationOptionalUUID(meals, 0) else { throw DiaryError.invalidData }
                    let meal = try transaction.mealRecord(id: id)
                    let itemCount = try mutationInteger("SELECT COUNT(*) FROM item WHERE parent = ?", [.text(id.uuidString)])
                    let bytes = try mutationInteger("SELECT COALESCE(SUM(length(payload)),0) FROM item WHERE parent = ?", [.text(id.uuidString)])
                    let omission = CoachContext.MealReference(id: id, dayID: meal.dayID, revision: meal.revision, itemCount: itemCount)
                    if bytes > 24_000 { context.omittedMeals.append(omission); continue }
                    let state = try domainStatement("SELECT json_extract(CAST(payload AS TEXT), '$.state') FROM submission WHERE parent = ? ORDER BY ordinal DESC, id DESC LIMIT 1", [.text(id.uuidString)])
                    defer { sqlite3_finalize(state) }
                    let raw = try mutationStep(state) ? mutationText(state, 0) : SubmissionState.saved.rawValue
                    guard let status = SubmissionState(rawValue: raw) else { throw DiaryError.invalidData }
                    let projection = CoachContext.Meal(id: id, dayID: meal.dayID, revision: meal.revision, eatenAt: meal.eatenAt,
                        timePrecision: meal.timePrecision, items: try transaction.mealItems(id: id), state: status)
                    if try JSONEncoder().encode(context.meals + [projection]).count <= 24_000 { context.meals.append(projection) }
                    else { context.omittedMeals.append(omission) }
                }
                context.meals.reverse()
            }
            var lastChanged: CoachContext.Focus.LastChanged?
            if let day = context.activeDayID {
                let latest = try domainStatement("SELECT id FROM meal WHERE parent = ? AND json_extract(CAST(payload AS TEXT), '$.revision') > 0 AND json_extract(CAST(payload AS TEXT), '$.changedRevision') IS NOT NULL ORDER BY json_extract(CAST(payload AS TEXT), '$.changedRevision') DESC LIMIT 1", [.text(day.uuidString)])
                defer { sqlite3_finalize(latest) }
                if try mutationStep(latest), let id = try mutationOptionalUUID(latest, 0) {
                    lastChanged = .init(mealID: id, itemNames: try transaction.mealItems(id: id).prefix(8).map { coachBoundedText($0.name, bytes: 64) }, // bounded: a meal can hold hundreds of long names
                        localDate: try trackingDay(id: day).localDate, revision: try transaction.mealRecord(id: id).revision)
                }
            }
            if lastChanged != nil || pendingQuestion != nil { context.focus = .init(lastChanged: lastChanged, pendingQuestion: pendingQuestion) }
            let progress = try progressRangeInsideContext(transaction, date: diaryDateLabel(work.capturedAt, zone: work.captureTimeZoneID))
            context.weights = progress.weights; context.workouts = progress.workouts
            context.omittedWeightCount = progress.omittedWeights; context.omittedWorkoutCount = progress.omittedWorkouts
            let current = try coachExchangeSummary(turnID: turnID, expectedProfileID: expectedProfileID)
            try context.includeCommittedReceipts(current.receipts)
            context.replyTo = try current.reply.map { try coachReplyContext($0, transaction: transaction) }
            context.truncated = recent.count < min(12, Int(work.sequence - 1)) || !context.omittedMeals.isEmpty || context.additionalMealCount > 0 || context.preferencesTruncated == true
            while try JSONEncoder().encode(context).count > 60_000, let meal = context.meals.first {
                context.meals.removeFirst(); context.omittedMeals.append(.init(id: meal.id, dayID: meal.dayID, revision: meal.revision, itemCount: meal.items.count)); context.truncated = true
            }
            while try JSONEncoder().encode(context).count > 60_000, context.workouts?.isEmpty == false {
                context.workouts!.removeFirst(); context.omittedWorkoutCount = (context.omittedWorkoutCount ?? 0) + 1; context.truncated = true
            }
            guard try JSONEncoder().encode(context).count <= 60_000 else { throw CoachError.limitExceeded }; return context
        }
    }
    /// One bounded read of what the turn quotes; missing records are explicit, never guessed.
    private func coachReplyContext(_ reply: CoachReply, transaction: DiaryTransaction) throws -> CoachContext.Reply {
        var value = CoachContext.Reply(target: reply.target, excerpt: reply.excerpt)
        do {
            switch reply.target {
            case .message(let id, _):
                guard let turn = try transaction.turn(id: id) else { throw DiaryError.notFound }
                value.turn = .init(id: turn.id, capturedAt: turn.capturedAt, text: coachBoundedText(turn.text, bytes: 1024),
                                   assistantText: turn.assistantText.map { coachBoundedText($0, bytes: 1024) }, receipts: try receiptLine(turn.receipts))
            case .meal(let id), .item(let id, _):
                if case .item(_, let itemID) = reply.target,
                   !(try transaction.mealItems(id: id)).contains(where: { $0.id == itemID }) { throw DiaryError.notFound }
                do {
                    let meal = try coachMealDetail(id, transaction: transaction)
                    if try JSONEncoder().encode(meal).count <= 8192 { value.meal = meal }
                } catch CoachError.limitExceeded {} // ids only; the model uses get_meal
            case .day(let id): _ = try trackingDay(id: id)
            case .weight(let id): value.weight = try transaction.weight(id: id)
            case .workout(let id):
                let workout = try transaction.workout(id: id)
                if try JSONEncoder().encode(workout).count <= 8192 { value.workout = workout } // else ids only
            }
        } catch DiaryError.notFound { value.unavailable = true }
        return value
    }
    private func progressRangeInsideContext(_ transaction: DiaryTransaction, date: String) throws -> (weights: [WeightEntry], workouts: [WorkoutReference], omittedWeights: Int, omittedWorkouts: Int) {
        let weights = try domainStatement("SELECT payload FROM weight ORDER BY ordinal DESC, id DESC LIMIT 41")
        defer { sqlite3_finalize(weights) }; var values: [WeightEntry] = []
        while try mutationStep(weights) { values.append(try JSONDecoder().decode(WeightEntry.self, from: mutationBlob(weights, 0))) }
        let workouts = try domainStatement("SELECT w.id, w.parent, json_extract(CAST(w.payload AS TEXT), '$.revision'), json_extract(CAST(w.payload AS TEXT), '$.kind'), json_extract(CAST(w.payload AS TEXT), '$.durationMinutes') FROM workout w ORDER BY w.ordinal DESC, w.id DESC LIMIT 101")
        defer { sqlite3_finalize(workouts) }; var references: [WorkoutReference] = []
        while try mutationStep(workouts) {
            guard let id = try mutationOptionalUUID(workouts, 0), let dayID = try mutationOptionalUUID(workouts, 1), let kind = WorkoutKind(rawValue: try mutationText(workouts, 3)) else { throw DiaryError.invalidData }
            references.append(.init(id: id, dayID: dayID, localDate: try trackingDay(id: dayID).localDate, revision: Int(sqlite3_column_int64(workouts, 2)), kind: kind, durationMinutes: Int(sqlite3_column_int64(workouts, 4))))
        }
        return (Array(values.prefix(40).reversed()), Array(references.prefix(100).reversed()), max(0, try mutationInteger("SELECT COUNT(*) FROM weight") - 40), max(0, try mutationInteger("SELECT COUNT(*) FROM workout") - 100))
    }
}

func coachBoundedText(_ value: String, bytes: Int) -> String {
    guard value.utf8.count > bytes else { return value }
    var result = "", count = 3
    for scalar in value.unicodeScalars {
        let size = scalar.utf8.count; guard count + size <= bytes else { break }
        result.unicodeScalars.append(scalar); count += size
    }
    return result + "…"
}
