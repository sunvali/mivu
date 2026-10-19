import Foundation
import SQLite3

extension DiaryDatabase {
    func applyCoachWrites(_ writes: [CoachWrite], turnID: UUID, mode: CoachWriteMode = .uninterrupted,
                          at: Date, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<[CoachReceipt]> {
        guard at.timeIntervalSince1970.isFinite else { throw DiaryError.invalidData }
        return try transaction(expected: expected, maximumBytes: maximumBytes) { transaction in
            guard let turn = try transaction.turn(id: turnID) else { throw DiaryError.notFound }
            let normalized = try transaction.validateCoachWrites(writes, turn: turn, mode: mode, at: at)
            var results: [CoachReceipt] = [], newReceipts: [CoachReceipt] = []
            for write in normalized {
                let key = "\(turnID)/\(write.target)"
                if let prior = turn.receipts.first(where: { $0.operationKey == key }) { results.append(prior); continue }
                var receipt = try transaction.applyCoachWrite(write, turn: turn, at: at)
                receipt.operationKey = key; receipt.commandFingerprint = try write.commandFingerprint()
                newReceipts.append(receipt); results.append(receipt)
            }
            if !newReceipts.isEmpty {
                // Photo/day helpers can update visible links before the final proposed-revision receipts exist.
                guard var final = try transaction.turn(id: turnID) else { throw DiaryError.notFound }
                final.receipts.append(contentsOf: newReceipts)
                if let id = final.pendingMealID, let row = try transaction.records("meal", clause: "id = ?", values: [.text(id.uuidString)], limit: 1).first {
                    final.pendingMealRevision = try decode(DiaryMeal.self, row).revision
                }
                try transaction.saveTurn(final)
            }
            return results
        }
    }
    func validateCoachWrites(_ writes: [CoachWrite], turnID: UUID, mode: CoachWriteMode, at: Date, expectedProfileID: UUID) throws {
        try domainRead(expectedProfileID: expectedProfileID) { head in
            let transaction = DiaryTransaction(database: self, head: head)
            guard let turn = try transaction.turn(id: turnID) else { throw DiaryError.notFound }
            _ = try transaction.validateCoachWrites(writes, turn: turn, mode: mode, at: at)
        }
    }
}

extension DiaryTransaction {
    func validateCoachWrites(_ writes: [CoachWrite], turn: CoachTurn, mode: CoachWriteMode, at: Date) throws -> [CoachWrite] {
        guard Set(writes.map(\.target)).count == writes.count else { throw CoachError.invalidArguments }
        let normalized = try writes.map { try resolvedWeightWrite($0, turn: turn) }
        guard Set(normalized.map(\.target)).count == normalized.count else { throw CoachError.invalidArguments }
        let targets = normalized.compactMap { write -> String? in
            switch write {
            case .correctWeight(let id, _, _, _), .deleteWeight(let id, _): "weight/\(id)"
            case .editWorkout(let id, _, _), .deleteWorkout(let id, _): "workout/\(id)"
            case .weight(let date, _, _, _): "weight-date/\(date)"
            case .workout(let date, _): "workout-date/\(date)"
            default: nil
            }
        }
        guard Set(targets).count == targets.count else { throw CoachError.invalidArguments }
        if turn.pendingMealID != nil {
            guard normalized.filter({ if case .food = $0 { return true }; return false }).count <= 1 else { throw CoachError.invalidArguments }
        }
        var newCount = 0
        for write in normalized {
            let key = "\(turn.id)/\(write.target)"
            if let receipt = turn.receipts.first(where: { $0.operationKey == key }) {
                if let fingerprint = receipt.commandFingerprint { guard try fingerprint == write.commandFingerprint() else { throw CoachError.invalidArguments } }
                try validateReplay(write, receipt: receipt)
            } else {
                guard mode != .replayOnly else { throw CoachError.invalidArguments }
                newCount += 1; try validateCoachWrite(write, turn: turn, at: at)
            }
        }
        guard turn.receipts.count + newCount <= 16 else { throw CoachError.limitExceeded }
        return normalized
    }
    private func resolvedWeightWrite(_ write: CoachWrite, turn: CoachTurn) throws -> CoachWrite {
        guard case .weight(let date, let value, let unit, let revision) = write else { return write }
        if turn.receipts.contains(where: { $0.operationKey == "\(turn.id)/weight/\(date)" }) { return write }
        let days = try records("day", clause: "json_extract(CAST(payload AS TEXT), '$.localDate') = ? AND json_extract(CAST(payload AS TEXT), '$.timeZoneID') = ?", values: [.text(date), .text(turn.captureTimeZoneID)])
        let dayIDs = Set(days.map(\.id))
        if let receipt = turn.receipts.first(where: { $0.weightID != nil && $0.operationKey == "\(turn.id)/correct_weight/\($0.weightID!)" && $0.dayID.map { dayIDs.contains($0.uuidString) } == true }) {
            guard let revision else { throw DiaryError.staleRevision }; return .correctWeight(id: receipt.weightID!, value: value, unit: unit, revision: revision)
        }
        for row in days {
            guard let id = UUID(uuidString: row.id) else { throw DiaryError.invalidData }
            if let existing = try weight(on: id) { guard let revision else { throw DiaryError.staleRevision }; return .correctWeight(id: existing.id, value: value, unit: unit, revision: revision) }
        }
        return write
    }
    private func validateReplay(_ write: CoachWrite, receipt: CoachReceipt) throws {
        switch write {
        case .deleteWeight(let id, _): guard try exists("weight_tombstone", id) else { throw DiaryError.notFound }; return
        case .deleteWorkout(let id, _): guard try exists("workout_tombstone", id) else { throw DiaryError.notFound }; return
        case .manual(.deleteMeal(let id, _), _): guard try exists("tombstone", id) else { throw DiaryError.notFound }; return
        case .manual(.deletePhoto(let meal, let photo, _), _):
            _ = try mealRecord(id: meal); guard try photoMetadata(photoID: photo, owner: .meal(meal)) == nil else { throw DiaryError.notFound }; return
        case .manual(.attach(let meal, let ids, _, _), _):
            _ = try mealRecord(id: meal)
            for id in ids { guard try photoMetadata(photoID: id, owner: .meal(meal)) != nil else { throw DiaryError.notFound } }; return
        default: break
        }
        if let id = receipt.mealID {
            _ = try mealRecord(id: id)
            if let item = receipt.itemID { guard try mealItems(id: id).contains(where: { $0.id == item }) else { throw DiaryError.notFound } }
        }
        if let id = receipt.weightID { _ = try weight(id: id) }
        if let id = receipt.workoutID { _ = try workout(id: id) }
        if let id = receipt.goalID { guard try exists("goal", id) else { throw DiaryError.notFound } }
        if let id = receipt.dayID { _ = try database.trackingDay(id: id) }
    }
    private func exists(_ table: String, _ id: UUID) throws -> Bool { try database.mutationInteger("SELECT COUNT(*) FROM \(table) WHERE id = ?", [.text(id.uuidString)]) == 1 }
    private func validateCoachWrite(_ write: CoachWrite, turn: CoachTurn, at: Date) throws {
        func meal(_ id: UUID, revision: Int) throws -> DiaryMeal {
            guard turn.pendingMealID == nil || turn.pendingMealID == id else { throw DiaryError.invalidData }
            let meal = try mealRecord(id: id)
            guard meal.revision == revision, turn.pendingMealID != id || turn.pendingMealRevision == revision else { throw DiaryError.staleRevision }; return meal
        }
        switch write {
        case .food(let date, let items, let time, _):
            guard !items.isEmpty else { throw DiaryError.invalidData }; try validateItems(items); _ = try diaryDateOnlyInstant(date, zone: turn.captureTimeZoneID)
            if let time { guard time.timeIntervalSince1970.isFinite, diaryDateLabel(time, zone: turn.captureTimeZoneID) == date else { throw DiaryError.invalidData } }
            if let id = turn.pendingMealID {
                let current = try mealRecord(id: id), submission = try submission(id: turn.id, mealID: id)
                guard submission.state != .cancelled else { throw DiaryError.notFound }
                guard current.revision == turn.pendingMealRevision else { throw DiaryError.staleRevision }
                _ = try addedCoachItems(items, meal: current, turnID: turn.id)
                if current.revision > 0 { let day = try database.trackingDay(id: current.dayID); guard day.localDate == date else { throw DiaryError.ambiguousDay } }
            }
        case .correction(let id, let item, let revision):
            _ = try meal(id, revision: revision)
            guard let previous = try mealItems(id: id).first(where: { $0.id == item.id }) else { throw DiaryError.notFound }
            try validateItems([diaryCorrectedItem(item, previous: previous)])
        case .close(let date, _), .workout(let date, _): _ = try diaryDateOnlyInstant(date, zone: turn.captureTimeZoneID)
        case .weight(let date, let value, let unit, let revision):
            _ = try diaryDateOnlyInstant(date, zone: turn.captureTimeZoneID)
            guard revision == nil else { throw DiaryError.staleRevision }
            try validateWeightFields(WeightEntry(dayID: nil, measuredAt: turn.capturedAt, value: value, unit: unit))
        case .correctWeight(let id, let value, let unit, let revision):
            var record = try weight(id: id); guard record.revision == revision else { throw DiaryError.staleRevision }; record.value = value; record.unit = unit; record.revision += 1; try validateWeightFields(record)
        case .editWorkout(let id, let draft, let revision):
            var record = try workout(id: id); guard record.revision == revision else { throw DiaryError.staleRevision }
            record.kind = draft.kind; record.durationMinutes = draft.durationMinutes; record.exercises = draft.exercises; record.estimatedBurnKcal = draft.estimatedBurnKcal; record.burnSource = draft.burnSource; record.revision += 1; try validateWorkoutFields(record)
        case .deleteWeight(let id, let revision): guard try weight(id: id).revision == revision else { throw DiaryError.staleRevision }
        case .deleteWorkout(let id, let revision): guard try workout(id: id).revision == revision else { throw DiaryError.staleRevision }
        case .manual(let edit, _):
            switch edit {
            case .item(let id, let item, let revision, let submissionID, let original):
                _ = try meal(id, revision: revision)
                let items = try submissionID.map { try submission(id: $0, mealID: id).proposal?.items ?? [] } ?? mealItems(id: id)
                guard items.first(where: { $0.id == item.id }) == original else { throw DiaryError.staleRevision }; try validateItems([diaryCorrectedItem(item, previous: original)])
            case .append(let id, let items, let revision): _ = try meal(id, revision: revision); try validateItems(items); guard try mealProjection(id: id).state == .saved else { throw DiaryError.invalidData }
            case .accept(let id, let submissionID, let revision): _ = try meal(id, revision: revision); _ = try submission(id: submissionID, mealID: id)
            case .move(let id, let date, let revision, let day): guard try meal(id, revision: revision).dayID == day else { throw DiaryError.staleRevision }; _ = try diaryDateOnlyInstant(date, zone: turn.captureTimeZoneID)
            case .deleteMeal(let id, let revision), .retry(let id, let revision): _ = try meal(id, revision: revision)
            case .attach(let id, let photos, _, let revision):
                _ = try meal(id, revision: revision)
                guard !photos.isEmpty, Set(photos).count == photos.count else { throw DiaryError.invalidData }
                for photo in photos { guard turn.photoIDs.contains(photo), try photoMetadata(photoID: photo, owner: .meal(id)) == nil else { throw DiaryError.notFound } }
            case .deletePhoto(let id, let photo, let revision): _ = try meal(id, revision: revision); guard try photoMetadata(photoID: photo, owner: .meal(id)) != nil else { throw DiaryError.notFound }
            case .goals(let date, let targets, _, _, _, let revision):
                guard try exactGoal(on: date)?.revision == revision else { throw DiaryError.staleRevision }
                guard Set(targets.map(\.nutrient)).count == targets.count, targets.allSatisfy({ ["kcal", "carbs", "protein", "fat"].contains($0.nutrient) }) else { throw DiaryError.invalidData }
            case .preferences(_, _, let revision): guard head.revision == revision else { throw DiaryError.staleRevision }
            case .startDay(let revision):
                guard head.revision == revision else { throw DiaryError.staleRevision }
                guard turn.captureTimeZoneID == head.profile.timeZoneID, diaryDateLabel(turn.capturedAt, zone: turn.captureTimeZoneID) == diaryDateLabel(at, zone: head.profile.timeZoneID), try head.activeDayID.map({ try database.trackingDay(id: $0).startAt <= turn.capturedAt }) ?? true else { throw DiaryError.ambiguousDay }
            case .coverage(let date, _): _ = try diaryDateOnlyInstant(date, zone: turn.captureTimeZoneID)
            case .open: break
            }
        }
    }
    private func coachDay(_ date: String, turn: CoachTurn, activateIfEmpty: Bool = true, exact: Bool = false) throws -> TrackingDay {
        let noon = try diaryDateOnlyInstant(date, zone: turn.captureTimeZoneID), current = diaryDateLabel(turn.capturedAt, zone: turn.captureTimeZoneID) == date
        if !exact && current {
            if let id = turn.resolvedDayID { return try database.trackingDay(id: id) }
            if let id = turn.activeDayID, try database.trackingDay(id: id).localDate != date { throw DiaryError.ambiguousDay }
        }
        let day = try resolveDay(localDate: date, timeZoneID: turn.captureTimeZoneID, at: current ? turn.capturedAt : noon)
        if activateIfEmpty && current && head.activeDayID == nil { try activateDay(day) }
        return day
    }
    private func addSource(kind: String, recordID: UUID, turnID: UUID, origin: Bool) throws {
        guard try exists(kind, recordID) else { return }
        try database.execute("INSERT OR IGNORE INTO record_source(kind, recordID, turnID, relation) VALUES (?, ?, ?, ?)", [.text(kind), .text(recordID.uuidString), .text(turnID.uuidString), .text(origin ? "origin" : "reference")])
    }
    private func addedCoachItems(_ items: [FoodItem], meal: DiaryMeal, turnID: UUID) throws -> [FoodItem] {
        guard meal.revision > 0 else { return items }
        let pending = try mealSubmissions(id: meal.id).first { $0.id == turnID && $0.state == .awaitingReview }?.proposal?.items
        let previous = try pending ?? mealItems(id: meal.id), ids = Set(previous.map(\.id)), names = Set(previous.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        guard items.allSatisfy({ !ids.contains($0.id) && !names.contains($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }) else { throw DiaryError.invalidData }
        let result = previous + items; try validateItems(result); return result
    }
    private func mealResult(_ id: UUID) throws -> CoachContext.Meal {
        let meal = try mealProjection(id: id)
        return CoachContext.Meal(id: meal.id, dayID: meal.dayID, revision: meal.revision, eatenAt: meal.eatenAt, timePrecision: meal.timePrecision, items: meal.items, state: meal.state)
    }
    fileprivate func applyCoachWrite(_ write: CoachWrite, turn: CoachTurn, at: Date) throws -> CoachReceipt {
        var receipt = CoachReceipt(operationKey: "\(turn.id)/\(write.target)", turnID: turn.id, dayID: nil, committedRevision: head.revision + 1, resultJSON: "{}")
        switch write {
        case .food(let date, let items, _, let review):
            let day = try coachDay(date, turn: turn), isNew = turn.pendingMealID == nil
            var meal = try turn.pendingMealID.map { try mealRecord(id: $0) } ?? DiaryMeal(dayID: day.id, capturedAt: turn.capturedAt, eatenAt: day.startAt, revision: 0, timePrecision: .dateOnly)
            if isNew { try insertMeal(meal) }
            let proposalItems = try addedCoachItems(items, meal: meal, turnID: turn.id)
            if let pending = turn.pendingMealID {
                var submission = try submission(id: turn.id, mealID: pending)
                submission.proposal = AnalysisOutput(profileID: head.profile.id, mealID: meal.id, submissionID: turn.id, baseRevision: meal.revision, items: proposalItems)
                meal.dayID = day.id
                if submission.reviewFirst || review { submission.state = .awaitingReview }
                else { try replaceItems(proposalItems, mealID: meal.id); meal.revision += 1; submission.state = .saved }
                if turn.pendingMealRevision == 0 && day.id != turn.activeDayID { meal.eatenAt = day.startAt; meal.timePrecision = .dateOnly }
                try saveMeal(meal); try saveSubmission(submission, meal: meal)
            } else if review {
                let proposal = AnalysisOutput(profileID: head.profile.id, mealID: meal.id, submissionID: turn.id, baseRevision: 0, items: items)
                try saveSubmission(MealSubmission(id: turn.id, baseRevision: 0, text: turn.text, photoIDs: turn.photoIDs, reviewFirst: true, state: .awaitingReview, proposal: proposal), meal: meal)
            } else { try replaceItems(items, mealID: meal.id); meal.revision = 1; try saveMeal(meal) }
            try addSource(kind: "meal", recordID: meal.id, turnID: turn.id, origin: isNew)
            for photo in try photoReferences(owner: .coachTurn(turn.id)) {
                guard try photoConsumers(photoID: photo.photoID, owner: photo.owner) == [turn.id] else { throw DiaryError.invalidData }
                // The final receipt establishes this consumer's meal link atomically; never reread a future receipt.
                try transferPhoto(photoID: photo.photoID, from: photo.owner, to: .meal(meal.id), consumers: [], removeSource: false)
                try database.execute("INSERT INTO photo_consumer(ownerKind, parentID, photoID, turnID) VALUES ('meal', ?, ?, ?)", [.text(meal.id.uuidString), .text(photo.photoID.uuidString), .text(turn.id.uuidString)])
                try removePhoto(photoID: photo.photoID, owner: photo.owner)
            }
            receipt.dayID = day.id; receipt.mealID = meal.id; receipt.resultJSON = try coachJSON(mealResult(meal.id))
        case .correction(let id, let item, _):
            var meal = try mealRecord(id: id), items = try mealItems(id: id)
            let pending = turn.pendingMealID == id ? try submission(id: turn.id, mealID: id) : nil
            if let proposal = pending?.proposal, pending?.state == .awaitingReview { items = proposal.items }
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { throw DiaryError.notFound }
            let edited = try diaryCorrectedItem(item, previous: items[index]); items[index] = edited; try validateItems(items)
            if var submission = pending {
                submission.proposal = AnalysisOutput(profileID: head.profile.id, mealID: id, submissionID: turn.id, baseRevision: submission.baseRevision, items: items)
                if submission.reviewFirst { submission.state = .awaitingReview }
                else { try updateCoachItem(edited, mealID: id); meal.revision += 1; submission.state = .saved }
                try saveMeal(meal); try saveSubmission(submission, meal: meal)
            } else { try updateCoachItem(edited, mealID: id); meal.revision += 1; try saveMeal(meal) }
            struct Result: Encodable { var mealID: UUID; var targetLocalDate: String; var revision: Int; var state: SubmissionState; var item: FoodItem }
            receipt.dayID = meal.dayID; receipt.mealID = id; receipt.itemID = item.id
            receipt.resultJSON = try coachJSON(Result(mealID: id, targetLocalDate: database.trackingDay(id: meal.dayID).localDate, revision: meal.revision, state: mealProjection(id: id).state, item: edited))
            try addSource(kind: "meal", recordID: id, turnID: turn.id, origin: false)
        case .close(let date, let completeness):
            var day = try coachDay(date, turn: turn); day.completeness = completeness; day.closedAt = turn.capturedAt; try saveDay(day)
            receipt.dayID = day.id; receipt.resultJSON = try coachJSON(day)
        case .weight(let date, let value, let unit, let revision):
            let current = date == diaryDateLabel(turn.capturedAt, zone: turn.captureTimeZoneID)
            var clock = turn; if current { clock.activeDayID = nil; clock.resolvedDayID = nil }
            let day = try coachDay(date, turn: clock, activateIfEmpty: false)
            let conflicting = try records("day", clause: "json_extract(CAST(payload AS TEXT), '$.localDate') = ? AND id != ?", values: [.text(date), .text(day.id.uuidString)])
            for row in conflicting { guard let id = UUID(uuidString: row.id) else { throw DiaryError.invalidData }; guard try weight(on: id) == nil else { throw DiaryError.staleRevision } }
            let active = try head.activeDayID.map { try database.trackingDay(id: $0) }
            if current && date == diaryDateLabel(at, zone: head.profile.timeZoneID) && (active == nil || (active!.localDate <= date && active!.startAt <= turn.capturedAt)) { try activateDay(day) }
            let saved = try setWeight(dayID: day.id, value: value, unit: unit, expectedRevision: revision)
            receipt.dayID = day.id; receipt.weightID = saved.id; receipt.resultJSON = try coachJSON(saved)
            try addSource(kind: "weight", recordID: saved.id, turnID: turn.id, origin: true)
        case .correctWeight(let id, let value, let unit, _):
            var record = try weight(id: id); record.value = value; record.unit = unit; record.revision += 1; try saveWeight(record)
            receipt.dayID = try weightReceiptDay(record).id; receipt.weightID = id; receipt.resultJSON = try coachJSON(record)
            try addSource(kind: "weight", recordID: id, turnID: turn.id, origin: false)
        case .workout(let date, let draft):
            let day = try coachDay(date, turn: turn), saved = try createWorkout(dayID: day.id, draft: draft)
            receipt.dayID = day.id; receipt.workoutID = saved.id; receipt.resultJSON = try coachJSON(saved)
            try addSource(kind: "workout", recordID: saved.id, turnID: turn.id, origin: true)
        case .editWorkout(let id, let draft, _):
            var record = try workout(id: id); record.kind = draft.kind; record.durationMinutes = draft.durationMinutes; record.exercises = draft.exercises; record.estimatedBurnKcal = draft.estimatedBurnKcal; record.burnSource = draft.burnSource; record.revision += 1; try saveWorkout(record)
            receipt.dayID = record.dayID; receipt.workoutID = id; receipt.resultJSON = try coachJSON(record)
            try addSource(kind: "workout", recordID: id, turnID: turn.id, origin: false)
        case .deleteWeight(let id, let revision):
            receipt.dayID = try weightReceiptDay(weight(id: id)).id; receipt.weightID = id
            try deleteWeight(id: id, revision: revision); receipt.resultJSON = try coachJSON(Deleted(id: id))
        case .deleteWorkout(let id, let revision):
            receipt.dayID = try workout(id: id).dayID; receipt.workoutID = id
            try deleteWorkout(id: id, revision: revision); receipt.resultJSON = try coachJSON(Deleted(id: id))
        case .manual(let edit, _): try applyManual(edit, turn: turn, at: at, receipt: &receipt)
        }
        return receipt
    }
    private struct Deleted: Encodable { var id: UUID; var deleted = true }
    private func updateCoachItem(_ item: FoodItem, mealID: UUID) throws {
        let id = "\(mealID)/\(item.id)", bytes = try JSONEncoder().encode(item)
        try database.execute("UPDATE item SET payload = ? WHERE id = ? AND parent = ?", [.blob(bytes), .text(id), .text(mealID.uuidString)])
        guard sqlite3_changes(database.connection) == 1 else { throw DiaryError.notFound }
        try contribution(table: "item", rowID: id, parentID: mealID.uuidString, encodedBytes: bytes.count)
    }
    private func weightReceiptDay(_ weight: WeightEntry) throws -> TrackingDay {
        if let id = weight.dayID { return try database.trackingDay(id: id) }
        let date = diaryDateLabel(weight.measuredAt, zone: head.profile.timeZoneID)
        return try resolveDay(localDate: date, timeZoneID: head.profile.timeZoneID, at: diaryDateOnlyInstant(date, zone: head.profile.timeZoneID))
    }
    private func applyManual(_ edit: CoachManualEdit, turn: CoachTurn, at: Date, receipt: inout CoachReceipt) throws {
        switch edit {
        case .item(let id, let item, _, let submissionID, _):
            try editItem(mealID: id, item: item, reviewSubmissionID: submissionID, expectedRevision: nil)
            receipt.mealID = id; receipt.itemID = item.id; receipt.dayID = try mealRecord(id: id).dayID; receipt.resultJSON = try coachJSON(mealResult(id))
        case .append(let id, let items, _):
            let meal = try mealRecord(id: id), submissionID = UUID(), previous = try mealItems(id: id)
            try saveSubmission(MealSubmission(id: submissionID, baseRevision: meal.revision, text: turn.text, photoIDs: [], reviewFirst: false), meal: meal)
            try applyAnalysis(AnalysisOutput(profileID: head.profile.id, mealID: id, submissionID: submissionID, baseRevision: meal.revision, items: previous + items))
            receipt.dayID = meal.dayID; receipt.mealID = id; receipt.resultJSON = try coachJSON(mealResult(id))
        case .accept(let id, let submissionID, _):
            try acceptReview(mealID: id, submissionID: submissionID)
            receipt.mealID = id; receipt.dayID = try mealRecord(id: id).dayID; receipt.resultJSON = try coachJSON(mealResult(id))
        case .move(let id, let date, _, _):
            let day = try coachDay(date, turn: turn, activateIfEmpty: false, exact: true)
            try moveMeal(id, to: day.id, eatenAt: nil, expectedRevision: nil, expectedDayID: nil)
            receipt.dayID = day.id; receipt.mealID = id; receipt.resultJSON = try coachJSON(mealResult(id))
        case .deleteMeal(let id, _):
            receipt.dayID = try mealRecord(id: id).dayID; receipt.mealID = id; try deleteMeal(id); receipt.resultJSON = try coachJSON(Deleted(id: id))
        case .attach(let id, let photos, let role, _):
            for photoID in photos {
                let statement = try database.domainStatement("SELECT ownerKind, parentID FROM photo_consumer WHERE turnID = ? AND photoID = ?", [.text(turn.id.uuidString), .text(photoID.uuidString)])
                defer { sqlite3_finalize(statement) }; guard try database.mutationStep(statement), let parent = try database.mutationOptionalUUID(statement, 1) else { throw DiaryError.notFound }
                let owner: DiaryPhotoOwner = try database.mutationText(statement, 0) == "meal" ? .meal(parent) : .coachTurn(parent)
                guard try !database.mutationStep(statement) else { throw DiaryError.invalidData }
                try transferPhoto(photoID: photoID, from: owner, to: .meal(id), consumers: [], removeSource: false)
                try updatePhotoRole(mealID: id, photoID: photoID, role: role)
                try database.execute("INSERT INTO photo_consumer(ownerKind, parentID, photoID, turnID) VALUES ('meal', ?, ?, ?)", [.text(id.uuidString), .text(photoID.uuidString), .text(turn.id.uuidString)])
                if owner == .coachTurn(turn.id) { try removePhoto(photoID: photoID, owner: owner) }
            }
            receipt.dayID = try mealRecord(id: id).dayID; receipt.mealID = id; receipt.resultJSON = try coachJSON(mealResult(id))
        case .deletePhoto(let id, let photoID, _):
            receipt.dayID = try mealRecord(id: id).dayID; receipt.mealID = id
            try deleteMealPhoto(mealID: id, photoID: photoID); receipt.resultJSON = try coachJSON(Deleted(id: photoID))
        case .retry(let id, _):
            let selected = try ids("SELECT i.turnID FROM coach_index i WHERE i.turnID != ? AND i.state IN ('needsRetry','needsClarification','waitingForConnection','waitingForNetwork','captured') AND (i.pendingMealID = ? OR EXISTS (SELECT 1 FROM record_source r WHERE r.turnID = i.turnID AND r.kind = 'meal' AND r.recordID = ?)) ORDER BY i.sequence DESC LIMIT 1", [.text(turn.id.uuidString), .text(id.uuidString), .text(id.uuidString)])
            guard let selectedID = selected.first, var paused = try self.turn(id: selectedID) else { throw DiaryError.notFound }
            if paused.receipts.isEmpty, paused.pendingMealID != nil {
                let meal = try mealRecord(id: id); var submission = try submission(id: paused.id, mealID: id)
                submission.baseRevision = meal.revision; submission.proposal = nil; try saveSubmission(submission, meal: meal); paused.pendingMealRevision = meal.revision
            }
            paused.state = .captured; paused.assistantText = nil; try saveTurn(paused)
            struct Queued: Encodable { var queued = true; var turnID: UUID }
            receipt.dayID = try mealRecord(id: id).dayID; receipt.mealID = id; receipt.resultJSON = try coachJSON(Queued(turnID: selectedID))
        case .goals(let date, let targets, let weight, let clear, let credit, _):
            let exact = try exactGoal(on: date)
            var value = try exact ?? goal(on: date) ?? GoalRecord(effectiveLocalDate: date, timeZoneID: turn.captureTimeZoneID, targets: NutritionValues(), goalWeightKg: nil, exerciseCreditEnabled: false)
            if exact == nil { value.id = UUID(); value.effectiveLocalDate = date; value.timeZoneID = turn.captureTimeZoneID }
            for target in targets { value.targets.set(target) }
            if clear { value.goalWeightKg = nil } else if let weight { value.goalWeightKg = weight }
            if let credit { value.exerciseCreditEnabled = credit }
            let saved = try setGoal(value, revision: exact?.revision); receipt.goalID = saved.id; receipt.resultJSON = try coachJSON(saved)
        case .preferences(let zone, let text, _):
            var profile = head.profile; if let zone { profile.timeZoneID = zone }; if let text { profile.preferences = text }
            try updateProfile(profile, expectedProfile: nil)
            struct Result: Encodable { var profile: DiaryProfile; var diaryRevision: Int }
            receipt.resultJSON = try coachJSON(Result(profile: profile, diaryRevision: head.revision + 1))
        case .startDay:
            let day = try startDay(at: turn.capturedAt); receipt.dayID = day.id; receipt.resultJSON = try coachJSON(day)
        case .coverage(let date, let completeness):
            var day = try coachDay(date, turn: turn, activateIfEmpty: false, exact: true); day.completeness = completeness; try saveDay(day)
            receipt.dayID = day.id; receipt.resultJSON = try coachJSON(day)
        case .open(let destination):
            receipt.destination = destination
            struct Handoff: Encodable { var destination: CoachDestination; var completed = false }
            receipt.resultJSON = try coachJSON(Handoff(destination: destination))
        }
        if let id = receipt.mealID { try addSource(kind: "meal", recordID: id, turnID: turn.id, origin: false) }
    }
}
