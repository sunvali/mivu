import Foundation

struct ManualNutritionSaveResult: Sendable {
    let acceptance: ManualNutritionAcceptance
    let submissionID: UUID
    let meal: MealReadModel
    let replayed: Bool
}

extension DiaryDatabase {
    func saveManualNutrition(_ payload: ManualNutritionPayload, expected: DiaryHead,
                             maximumBytes: Int) throws -> DiaryCommit<ManualNutritionSaveResult> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { transaction in
            if let accepted = try transaction.manualNutritionResult(for: payload) { return accepted }
            let meal: DiaryMeal
            switch payload.operation {
            case .create:
                let day = try transaction.resolveManualNutritionDay(payload.target, capturedAt: payload.capturedAt)
                meal = DiaryMeal(id: payload.mealID, dayID: day.id, capturedAt: payload.capturedAt,
                    eatenAt: payload.eatenAt, timePrecision: payload.timePrecision)
                try transaction.insertMeal(meal)
            case .append:
                let current = try transaction.mealProjection(id: payload.mealID)
                guard current.revision == payload.expectedMealRevision else { throw DiaryError.staleRevision }
                guard !current.hasUnresolvedInput, case .recorded = payload.target,
                      current.dayID == payload.target.day.id, current.eatenAt == payload.eatenAt,
                      (current.timePrecision ?? .exact) == payload.timePrecision else { throw DiaryError.invalidData }
                _ = try transaction.manualRecordedDay(payload.target)
                meal = try transaction.mealRecord(id: payload.mealID)
            }
            let items = try payload.operation == .append ? transaction.mealItems(id: meal.id) + payload.items : payload.items
            let saved = try transaction.commitSavedItems(mealID: meal.id, items: items, expectedRevision: meal.revision)
            let acceptance = try ManualNutritionAcceptance(payload: payload)
            let proposal = AnalysisOutput(profileID: payload.profileID, mealID: meal.id, submissionID: payload.submissionID,
                baseRevision: meal.revision, items: payload.items)
            try transaction.saveSubmission(MealSubmission(id: payload.submissionID, baseRevision: meal.revision,
                text: "Entered manually", photoIDs: [], reviewFirst: false, state: .saved,
                proposal: proposal, manualAcceptance: acceptance), meal: saved)
            return ManualNutritionSaveResult(acceptance: acceptance, submissionID: payload.submissionID,
                meal: try transaction.mealProjection(id: meal.id), replayed: false)
        }
    }
    func prepareManualNutritionTarget(choice: ManualNutritionDayChoice, at: Date,
                                      expectedProfileID: UUID) throws -> ManualNutritionTarget {
        try domainRead(expectedProfileID: expectedProfileID) { head in
            guard at.timeIntervalSinceReferenceDate.isFinite else { throw DiaryError.invalidData }
            let transaction = DiaryTransaction(database: self, head: head)
            if case let .recorded(id) = choice {
                let day = try trackingDay(id: id)
                return .recorded(dayID: id, localDate: day.localDate, timeZoneID: day.timeZoneID)
            }
            let assignment = try transaction.dayAssignment(at: at)
            switch (choice, assignment) {
            case let (.current, .existing(id)), let (.previous, .ask(id)):
                let day = try trackingDay(id: id)
                return .active(dayID: id, localDate: day.localDate, timeZoneID: day.timeZoneID, confirmPrevious: choice == .previous)
            case (.newCurrent, .newDay), (.newCurrent, .ask):
                let date = diaryDateLabel(at, zone: head.profile.timeZoneID)
                let day = try transaction.manualDay(localDate: date, timeZoneID: head.profile.timeZoneID)
                return .newCurrent(dayID: day?.id ?? UUID(), localDate: date, timeZoneID: head.profile.timeZoneID, previousActiveDayID: head.activeDayID)
            default: throw DiaryError.ambiguousDay
            }
        }
    }
    func manualNutritionResult(for payload: ManualNutritionPayload,
                               expectedProfileID: UUID) throws -> ManualNutritionSaveResult? {
        try domainRead(expectedProfileID: expectedProfileID) { head in
            try DiaryTransaction(database: self, head: head).manualNutritionResult(for: payload)
        }
    }
}

extension DiaryTransaction {
    func manualNutritionResult(for payload: ManualNutritionPayload) throws -> ManualNutritionSaveResult? {
        guard payload.profileID == head.profile.id else { throw DiaryError.wrongOwner }
        try validateManualNutritionPayload(payload)
        guard try database.mutationInteger("SELECT COUNT(*) FROM tombstone WHERE id = ?", [.text(payload.mealID.uuidString)]) == 0 else { throw DiaryError.notFound }
        if let parent = try submissionParent(id: payload.submissionID) {
            guard parent == payload.mealID else { throw DiaryError.invalidData }
            let submission = try submission(id: payload.submissionID, mealID: parent)
            guard let acceptance = submission.manualAcceptance,
                  acceptance.matches(payload, proposal: submission.proposal) else { throw DiaryError.invalidData }
            _ = try manualRecordedDay(acceptance.target)
            return ManualNutritionSaveResult(acceptance: acceptance, submissionID: submission.id,
                meal: try mealProjection(id: parent), replayed: true)
        }
        guard try database.mutationInteger("SELECT COUNT(*) FROM coach_turn WHERE id = ?", [.text(payload.submissionID.uuidString)]) == 0 else { throw DiaryError.invalidData }
        switch payload.operation {
        case .create:
            guard try database.mutationInteger("SELECT COUNT(*) FROM meal WHERE id = ?", [.text(payload.mealID.uuidString)]) == 0 else { throw DiaryError.invalidData }
        case .append: _ = try mealRecord(id: payload.mealID)
        }
        return nil
    }
    func manualDay(localDate: String, timeZoneID: String) throws -> TrackingDay? {
        let rows = try records("day", clause: "json_extract(CAST(payload AS TEXT), '$.localDate') = ? AND json_extract(CAST(payload AS TEXT), '$.timeZoneID') = ?",
            values: [.text(localDate), .text(timeZoneID)], limit: 2)
        guard rows.count <= 1 else { throw DiaryError.invalidData }
        guard let row = rows.first else { return nil }
        let day = try database.decode(TrackingDay.self, row); try validateTrackingDayFields(day); return day
    }
    func manualRecordedDay(_ target: ManualNutritionTarget) throws -> TrackingDay {
        let day = try database.trackingDay(id: target.day.id)
        guard day.localDate == target.day.localDate, day.timeZoneID == target.day.timeZoneID else { throw DiaryError.invalidData }
        return day
    }
    func dayAssignment(at: Date) throws -> DayAssignment {
        guard at.timeIntervalSinceReferenceDate.isFinite else { throw DiaryError.invalidData }
        guard let id = head.activeDayID else { return .newDay }
        let day = try database.trackingDay(id: id), date = diaryDateLabel(at, zone: head.profile.timeZoneID)
        if let confirmed = head.previousDayConfirmedAt, at >= confirmed, at.timeIntervalSince(confirmed) < 4 * 3600,
           diaryDateLabel(confirmed, zone: head.profile.timeZoneID) == date { return .existing(id) }
        return day.timeZoneID == head.profile.timeZoneID && day.localDate == date ? .existing(id) : .ask(id)
    }
    func resolveManualNutritionDay(_ target: ManualNutritionTarget, capturedAt: Date) throws -> TrackingDay {
        switch target {
        case .recorded: return try manualRecordedDay(target)
        case let .active(id, _, _, confirmPrevious):
            let day = try manualRecordedDay(target)
            guard head.activeDayID == id,
                  try dayAssignment(at: capturedAt) == (confirmPrevious ? .ask(id) : .existing(id)) else { throw DiaryError.ambiguousDay }
            if confirmPrevious {
                head.previousDayConfirmedAt = capturedAt
                try resolveDayChoices(at: capturedAt, dayID: day.id)
            }
            return day
        case let .newCurrent(id, date, zone, previous):
            guard head.activeDayID == previous, zone == head.profile.timeZoneID,
                  date == diaryDateLabel(capturedAt, zone: zone),
                  try head.activeDayID.map({ try database.trackingDay(id: $0).startAt <= capturedAt }) ?? true else { throw DiaryError.ambiguousDay }
            if case .existing = try dayAssignment(at: capturedAt) { throw DiaryError.ambiguousDay }
            let day = try resolveDay(localDate: date, timeZoneID: zone, at: capturedAt, newDayID: id)
            try activateDay(day); try resolveDayChoices(at: capturedAt, dayID: day.id); return day
        }
    }
    func commitSavedItems(mealID: UUID, items: [FoodItem], expectedRevision: Int) throws -> DiaryMeal {
        var meal = try mealRecord(id: mealID)
        guard meal.revision == expectedRevision else { throw DiaryError.staleRevision }
        try replaceItems(items, mealID: mealID)
        meal.revision += 1; try saveMeal(meal); return meal
    }
}
