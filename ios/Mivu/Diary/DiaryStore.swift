import Foundation

/// One serialized writer; a mutation becomes visible only after atomic disk replacement.
actor DiaryStore {
    private let directory: URL
    private var current: DiarySnapshot?
    private var stagedCoachSnapshot: DiarySnapshot?
    private var profileSelectionEpoch: UInt64 = 0
    private var fileIdentities: [UUID: UInt64] = [:]
    init(directory: URL, maximumFileBytes: Int = 350_000_000) {
        self.directory = directory
        self.maximumFileBytes = min(maximumFileBytes, 350_000_000)
    }
    private let maximumFileBytes: Int

    func profiles() throws -> [DiaryProfile] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        do {
            let ids = Set(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { ["json", "sqlite"].contains($0.pathExtension) }
                .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) })
            return try ids.map { id in
                let profile = try read(file(id), rememberIdentity: false).profile
                guard profile.id == id else { throw DiaryError.wrongOwner }
                return profile
            }.sorted { $0.name < $1.name }
        } catch let error as DiaryError { throw error }
        catch { throw DiaryError.persistenceFailed }
    }

    func createProfile(_ profile: DiaryProfile) throws -> DiarySnapshot {
        guard !exists(profile.id) else { throw DiaryError.invalidData }
        var snapshot = DiarySnapshot(profile: profile)
        snapshot.lineage = [UUID()]
        try write(snapshot)
        current = snapshot
        profileSelectionEpoch &+= 1
        return snapshot
    }

    func importProfile(_ incoming: DiarySnapshot) throws -> DiarySnapshot {
        try incoming.validate()
        guard !exists(incoming.profile.id) else { throw DiaryError.invalidData }
        try write(incoming)
        current = incoming
        profileSelectionEpoch &+= 1
        return incoming
    }

    func selectProfile(_ id: UUID) throws -> DiarySnapshot {
        let loaded = try read(file(id))
        guard loaded.profile.id == id else { throw DiaryError.wrongOwner }
        current = loaded
        profileSelectionEpoch &+= 1
        return loaded
    }

    func signOut() { current = nil; profileSelectionEpoch &+= 1 }

    func snapshot(expectedProfileID: UUID? = nil) throws -> DiarySnapshot {
        guard let current = stagedCoachSnapshot ?? self.current else { throw DiaryError.noProfile }
        guard expectedProfileID == nil || expectedProfileID == current.profile.id else { throw DiaryError.wrongOwner }
        return current
    }

    func startDay(at: Date = Date(), expectedProfileID: UUID? = nil) throws -> TrackingDay {
        var day: TrackingDay!
        try transaction(expectedProfileID) { snapshot in day = startDay(in: &snapshot, at: at) }
        return day
    }

    func dayAssignment(at: Date = Date(), expectedProfileID: UUID? = nil) throws -> DayAssignment {
        let snapshot = try snapshot(expectedProfileID: expectedProfileID)
        guard let day = snapshot.days.first(where: { $0.id == snapshot.activeDayID }) else { return .newDay }
        let localDate = dateLabel(at, zone: snapshot.profile.timeZoneID)
        if let confirmed = snapshot.previousDayConfirmedAt, at >= confirmed,
           at.timeIntervalSince(confirmed) < 4 * 3600,
           dateLabel(confirmed, zone: snapshot.profile.timeZoneID) == localDate { return .existing(day.id) }
        if day.timeZoneID == snapshot.profile.timeZoneID && day.localDate == localDate { return .existing(day.id) }
        return .ask(day.id)
    }

    func confirmPreviousDay(at: Date = Date(), expectedProfileID: UUID? = nil) throws {
        try transaction(expectedProfileID) { snapshot in
            guard snapshot.activeDayID != nil else { throw DiaryError.notFound }
            snapshot.previousDayConfirmedAt = at
            resolveCoachDayChoices(in: &snapshot, at: at, dayID: snapshot.activeDayID!)
        }
    }

    func capture(text: String, photos: [MealPhoto], reviewFirst: Bool, dayID: UUID, at: Date = Date(), submissionID: UUID = UUID(), forCoach: Bool = false, expectedProfileID: UUID? = nil) throws -> DiaryMeal {
        let original = try snapshot(expectedProfileID: expectedProfileID)
        if let existing = original.meals.first(where: { $0.submissions.contains { $0.id == submissionID } }) { return existing }
        var meal = DiaryMeal(dayID: dayID, capturedAt: at, eatenAt: at, photos: photos,
            submissions: [MealSubmission(id: submissionID, baseRevision: 0, text: text, photoIDs: photos.map(\.id), reviewFirst: reviewFirst)])
        try transaction(expectedProfileID) { snapshot in
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty else { throw DiaryError.emptyCapture }
            guard snapshot.days.contains(where: { $0.id == dayID }) else { throw DiaryError.notFound }
            meal.items = []
            snapshot.meals.append(meal)
            if forCoach { appendManualCoachTurn(meal: meal, submissionID: submissionID, at: at, snapshot: &snapshot) }
        }
        return meal
    }

    func processPending(expectedProfileID: UUID? = nil) throws {
        let snapshot = try snapshot(expectedProfileID: expectedProfileID)
        let owner = snapshot.profile.id
        let jobs = snapshot.meals.flatMap { meal in
            meal.submissions.filter { [.captured, .waitingForConnection, .analyzing, .needsRetry].contains($0.state) }.map { (meal.id, $0.id) }
        }
        for (mealID, submissionID) in jobs {
            if Task.isCancelled { return }
            let latest = try self.snapshot(expectedProfileID: owner)
            guard let meal = latest.meals.first(where: { $0.id == mealID }),
                  let submission = meal.submissions.first(where: { $0.id == submissionID }) else { continue }
            if submission.baseRevision != meal.revision {
                try transaction(owner) { snapshot in
                    let m = snapshot.meals.firstIndex { $0.id == mealID }!
                    let s = snapshot.meals[m].submissions.firstIndex { $0.id == submissionID }!
                    snapshot.meals[m].submissions[s].baseRevision = meal.revision
                    snapshot.meals[m].submissions[s].proposal = nil
                }
            }
            let input = try analysisInput(mealID: mealID, submissionID: submissionID, expectedProfileID: owner)
            do { try applyAnalysis(SampleAnalyzer().analyze(input), expectedProfileID: owner) }
            catch {
                try transaction(owner) { snapshot in
                    guard let m = snapshot.meals.firstIndex(where: { $0.id == mealID }),
                          let s = snapshot.meals[m].submissions.firstIndex(where: { $0.id == submissionID }) else { throw DiaryError.notFound }
                    snapshot.meals[m].submissions[s].state = .needsRetry
                }
                throw error
            }
        }
    }

    func analysisInput(mealID: UUID, submissionID: UUID, expectedProfileID: UUID? = nil) throws -> AnalysisInput {
        let snapshot = try snapshot(expectedProfileID: expectedProfileID)
        guard let meal = snapshot.meals.first(where: { $0.id == mealID }),
              let submission = meal.submissions.first(where: { $0.id == submissionID }), submission.state != .cancelled
        else { throw DiaryError.notFound }
        guard submission.baseRevision == meal.revision else { throw DiaryError.staleRevision }
        return AnalysisInput(profileID: snapshot.profile.id, mealID: mealID, submissionID: submissionID,
            baseRevision: submission.baseRevision, text: submission.text,
            photos: meal.photos.filter { submission.photoIDs.contains($0.id) }, currentItems: meal.items,
            language: snapshot.profile.language, preferences: snapshot.profile.preferences)
    }

    func applyAnalysis(_ output: AnalysisOutput, expectedProfileID: UUID? = nil) throws {
        let original = try snapshot(expectedProfileID: expectedProfileID)
        guard output.profileID == original.profile.id else { throw DiaryError.wrongOwner }
        guard output.schemaVersion == 1, !output.items.isEmpty else { throw DiaryError.invalidData }
        try validateItems(output.items)
        guard let meal = original.meals.first(where: { $0.id == output.mealID }),
              let submission = meal.submissions.first(where: { $0.id == output.submissionID }), submission.state != .cancelled
        else { throw DiaryError.notFound }
        if submission.state == .saved || submission.state == .awaitingReview { return }
        guard output.baseRevision == meal.revision && output.baseRevision == submission.baseRevision else { throw DiaryError.staleRevision }
        try transaction(expectedProfileID) { snapshot in
            let m = snapshot.meals.firstIndex { $0.id == output.mealID }!
            let s = snapshot.meals[m].submissions.firstIndex { $0.id == output.submissionID }!
            snapshot.meals[m].submissions[s].proposal = output
            if submission.reviewFirst {
                snapshot.meals[m].submissions[s].state = .awaitingReview
            } else {
                snapshot.meals[m].items = output.items
                snapshot.meals[m].revision += 1
                snapshot.meals[m].submissions[s].state = .saved
            }
        }
    }

    func acceptReview(mealID: UUID, submissionID: UUID, expectedProfileID: UUID? = nil) throws {
        let original = try snapshot(expectedProfileID: expectedProfileID)
        guard let meal = original.meals.first(where: { $0.id == mealID }),
              let submission = meal.submissions.first(where: { $0.id == submissionID }) else { throw DiaryError.notFound }
        if submission.state == .saved { return }
        guard submission.state == .awaitingReview, let proposal = submission.proposal else { throw DiaryError.invalidData }
        guard meal.revision == proposal.baseRevision else { throw DiaryError.staleRevision }
        try transaction(expectedProfileID) { snapshot in
            let m = snapshot.meals.firstIndex { $0.id == mealID }!
            let s = snapshot.meals[m].submissions.firstIndex { $0.id == submissionID }!
            snapshot.meals[m].items = proposal.items
            snapshot.meals[m].revision += 1
            snapshot.meals[m].submissions[s].state = .saved
        }
    }

    func editItem(mealID: UUID, item: FoodItem, reviewSubmissionID: UUID? = nil, expectedRevision: Int? = nil, expectedProfileID: UUID? = nil) throws {
        try transaction(expectedProfileID) { snapshot in
            guard let m = snapshot.meals.firstIndex(where: { $0.id == mealID }) else { throw DiaryError.notFound }
            guard expectedRevision == nil || expectedRevision == snapshot.meals[m].revision else { throw DiaryError.staleRevision }
            let reviewIndex = reviewSubmissionID.flatMap { submissionID in
                snapshot.meals[m].submissions.firstIndex { $0.id == submissionID && $0.state == .awaitingReview }
            }
            guard reviewSubmissionID == nil || reviewIndex != nil else { throw DiaryError.notFound }
            let previous = reviewIndex.map { snapshot.meals[m].submissions[$0].proposal?.items.first { $0.id == item.id } }
                ?? snapshot.meals[m].items.first { $0.id == item.id }
            guard let previous else { throw DiaryError.notFound }
            let edited = try correctedItem(item, previous: previous)
            if let s = reviewIndex {
                guard snapshot.meals[m].submissions[s].baseRevision == snapshot.meals[m].revision else { throw DiaryError.staleRevision }
                let i = snapshot.meals[m].submissions[s].proposal!.items.firstIndex { $0.id == item.id }!
                snapshot.meals[m].submissions[s].proposal!.items[i] = edited
                return
            }
            guard let i = snapshot.meals[m].items.firstIndex(where: { $0.id == item.id }) else { throw DiaryError.notFound }
            snapshot.meals[m].items[i] = edited
            let base = snapshot.meals[m].revision
            let submissionID = UUID()
            let output = AnalysisOutput(profileID: snapshot.profile.id, mealID: mealID, submissionID: submissionID,
                baseRevision: base, items: snapshot.meals[m].items)
            snapshot.meals[m].submissions.append(MealSubmission(id: submissionID, baseRevision: base,
                text: "Direct item edit", photoIDs: [], reviewFirst: false, state: .saved, proposal: output))
            snapshot.meals[m].revision += 1
        }
    }

    func correctMeal(mealID: UUID, text: String, photos: [MealPhoto] = [], reviewFirst: Bool = false, submissionID: UUID = UUID(), forCoach: Bool = false, expectedProfileID: UUID? = nil) throws -> DiaryMeal {
        let original = try snapshot(expectedProfileID: expectedProfileID)
        if let existing = original.meals.first(where: { $0.submissions.contains { $0.id == submissionID } }) {
            guard existing.id == mealID else { throw DiaryError.invalidData }
            return existing
        }
        try transaction(expectedProfileID) { snapshot in
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty else { throw DiaryError.emptyCapture }
            guard let m = snapshot.meals.firstIndex(where: { $0.id == mealID }) else { throw DiaryError.notFound }
            snapshot.meals[m].photos.append(contentsOf: photos)
            snapshot.meals[m].submissions.append(MealSubmission(id: submissionID, baseRevision: snapshot.meals[m].revision,
                text: text, photoIDs: photos.map(\.id), reviewFirst: reviewFirst))
            if forCoach { appendManualCoachTurn(meal: snapshot.meals[m], submissionID: submissionID, at: Date(), snapshot: &snapshot) }
        }
        return try snapshot(expectedProfileID: expectedProfileID).meals.first { $0.id == mealID }!
    }

    func addPhotos(mealID: UUID, photos: [MealPhoto], expectedProfileID: UUID? = nil) throws {
        try transaction(expectedProfileID) { snapshot in
            guard let m = snapshot.meals.firstIndex(where: { $0.id == mealID }) else { throw DiaryError.notFound }
            snapshot.meals[m].photos.append(contentsOf: photos)
        }
    }

    func deletePhoto(mealID: UUID, photoID: UUID, expectedProfileID: UUID? = nil) throws {
        try transaction(expectedProfileID) { snapshot in
            guard let m = snapshot.meals.firstIndex(where: { $0.id == mealID }) else { throw DiaryError.notFound }
            snapshot.meals[m].photos.removeAll { $0.id == photoID }
            for t in snapshot.coachTurns.indices where snapshot.coachTurns[t].pendingMealID == mealID || snapshot.coachTurns[t].receipts.contains(where: { $0.mealID == mealID }) {
                snapshot.coachTurns[t].photoIDs.removeAll { $0 == photoID }
                snapshot.coachTurns[t].photos.removeAll { $0.id == photoID }
            }
            for index in snapshot.meals[m].submissions.indices {
                if snapshot.meals[m].submissions[index].photoIDs.contains(photoID),
                   snapshot.meals[m].submissions[index].state != .saved {
                    snapshot.meals[m].submissions[index].state = .cancelled
                    snapshot.meals[m].submissions[index].proposal = nil
                }
                snapshot.meals[m].submissions[index].photoIDs.removeAll { $0 == photoID }
            }
        }
    }

    func deleteMeal(_ mealID: UUID, expectedProfileID: UUID? = nil) throws {
        try transaction(expectedProfileID) { snapshot in
            guard snapshot.meals.contains(where: { $0.id == mealID }) else { throw DiaryError.notFound }
            let photoIDs = Set(snapshot.meals.first { $0.id == mealID }!.photos.map(\.id))
            for t in snapshot.coachTurns.indices where snapshot.coachTurns[t].pendingMealID == mealID || snapshot.coachTurns[t].receipts.contains(where: { $0.mealID == mealID }) {
                snapshot.coachTurns[t].photoIDs.removeAll { photoIDs.contains($0) }
                if snapshot.coachTurns[t].pendingMealID == mealID { snapshot.coachTurns[t].state = .needsClarification }
            }
            snapshot.meals.removeAll { $0.id == mealID }
            snapshot.deletedMealIDs.append(mealID)
        }
    }

    func moveMeal(_ mealID: UUID, to dayID: UUID, eatenAt: Date? = nil, expectedProfileID: UUID? = nil) throws {
        try transaction(expectedProfileID) { snapshot in
            guard snapshot.days.contains(where: { $0.id == dayID }), let m = snapshot.meals.firstIndex(where: { $0.id == mealID })
            else { throw DiaryError.notFound }
            snapshot.meals[m].dayID = dayID
            if let eatenAt {
                let day = snapshot.days.first { $0.id == dayID }!
                guard eatenAt.timeIntervalSince1970.isFinite, dateLabel(eatenAt, zone: day.timeZoneID) == day.localDate else { throw DiaryError.invalidData }
                snapshot.meals[m].eatenAt = eatenAt; snapshot.meals[m].timePrecision = .exact
            }
        }
    }

    func setCompleteness(dayID: UUID, _ completeness: DayCompleteness, expectedProfileID: UUID? = nil) throws {
        try transaction(expectedProfileID) { snapshot in
            guard let d = snapshot.days.firstIndex(where: { $0.id == dayID }) else { throw DiaryError.notFound }
            snapshot.days[d].completeness = completeness
        }
    }

    func recordWeight(value: Double, unit: String = "kg", at: Date = Date(), startNewDay: Bool = true, expectedProfileID: UUID? = nil) throws -> WeightEntry {
        var weight: WeightEntry!
        try transaction(expectedProfileID) { snapshot in
            let dayID = startNewDay ? startDay(in: &snapshot, at: at).id : snapshot.activeDayID
            if let w = snapshot.weights.firstIndex(where: { $0.dayID == dayID && dayID != nil }) {
                snapshot.weights[w].value = value
                snapshot.weights[w].unit = unit
                snapshot.weights[w].measuredAt = at
                snapshot.weights[w].timePrecision = .exact
                snapshot.weights[w].revision += 1
                weight = snapshot.weights[w]
            } else {
                weight = WeightEntry(dayID: dayID, measuredAt: at, value: value, unit: unit)
                snapshot.weights.append(weight)
            }
        }
        return weight
    }

    func setGoals(_ goal: GoalRecord, expectedRevision: Int?, expectedProfileID: UUID) throws -> GoalRecord {
        var saved: GoalRecord!
        try transaction(expectedProfileID) { snapshot in
            guard validLocalDate(goal.effectiveLocalDate) else { throw DiaryError.invalidData }
            if let index = snapshot.goals.firstIndex(where: { $0.effectiveLocalDate == goal.effectiveLocalDate }) {
                let previous = snapshot.goals[index]
                guard goal.id == previous.id else { throw DiaryError.staleRevision }
                guard expectedRevision == previous.revision else { throw DiaryError.staleRevision }
                saved = goal; saved.revision = previous.revision + 1
                snapshot.goals[index] = saved
            } else {
                guard expectedRevision == nil else { throw DiaryError.staleRevision }
                guard !snapshot.goals.contains(where: { $0.id == goal.id }) else { throw DiaryError.invalidData }
                saved = goal; saved.revision = 1
                snapshot.goals.append(saved)
            }
        }
        return saved
    }

    func setWeight(dayLocalDate: String, value: Double, unit: String, measuredAt: Date?, expectedRevision: Int?, expectedProfileID: UUID) throws -> WeightEntry {
        var saved: WeightEntry!
        try transaction(expectedProfileID) { snapshot in
            let day = try progressDay(dayLocalDate, in: &snapshot)
            if let measuredAt {
                guard measuredAt.timeIntervalSince1970.isFinite,
                      dateLabel(measuredAt, zone: day.timeZoneID) == day.localDate else { throw DiaryError.invalidData }
            }
            let time = try measuredAt ?? dateOnlyInstant(day.localDate, zone: day.timeZoneID)
            saved = try saveWeight(on: day, value: value, unit: unit, at: time,
                                   precision: measuredAt == nil ? .dateOnly : .exact,
                                   expectedRevision: expectedRevision, snapshot: &snapshot)
        }
        return saved
    }

    private func saveWeight(on day: TrackingDay, value: Double, unit: String, at time: Date, precision: MealTimePrecision, expectedRevision: Int?, snapshot: inout DiarySnapshot) throws -> WeightEntry {
        var saved: WeightEntry!
        if let index = snapshot.weights.firstIndex(where: { $0.dayID == day.id }) {
            guard expectedRevision == snapshot.weights[index].revision else { throw DiaryError.staleRevision }
            snapshot.weights[index].value = value
            snapshot.weights[index].unit = unit
            snapshot.weights[index].measuredAt = time
            snapshot.weights[index].timePrecision = precision
            snapshot.weights[index].revision += 1
            saved = snapshot.weights[index]
        } else {
            guard expectedRevision == nil else { throw DiaryError.staleRevision }
            saved = WeightEntry(dayID: day.id, measuredAt: time, value: value, unit: unit,
                        timePrecision: precision)
            snapshot.weights.append(saved)
        }
        return saved
    }

    func deleteWeight(id: UUID, expectedRevision: Int, expectedProfileID: UUID) throws {
        try transaction(expectedProfileID) { snapshot in
            guard let index = snapshot.weights.firstIndex(where: { $0.id == id }) else { throw DiaryError.notFound }
            guard snapshot.weights[index].revision == expectedRevision else { throw DiaryError.staleRevision }
            snapshot.weights.remove(at: index)
            snapshot.deletedWeightIDs.append(id)
        }
    }

    func createWorkout(localDate: String, draft: WorkoutDraft, performedAt: Date?, expectedProfileID: UUID) throws -> WorkoutSession {
        var saved: WorkoutSession!
        try transaction(expectedProfileID) { snapshot in
            let day = try progressDay(localDate, in: &snapshot)
            if let performedAt {
                guard performedAt.timeIntervalSince1970.isFinite,
                      dateLabel(performedAt, zone: day.timeZoneID) == day.localDate else { throw DiaryError.invalidData }
            }
            saved = try appendWorkout(on: day, draft: draft, performedAt: performedAt, snapshot: &snapshot)
        }
        return saved
    }

    private func appendWorkout(on day: TrackingDay, draft: WorkoutDraft, performedAt: Date?, snapshot: inout DiarySnapshot) throws -> WorkoutSession {
        let saved = WorkoutSession(dayID: day.id, performedAt: try performedAt ?? dateOnlyInstant(day.localDate, zone: day.timeZoneID),
                                   timePrecision: performedAt == nil ? .dateOnly : .exact, revision: 1,
                                   kind: draft.kind, durationMinutes: draft.durationMinutes, exercises: draft.exercises,
                                   estimatedBurnKcal: draft.estimatedBurnKcal, burnSource: draft.burnSource)
        snapshot.workouts.append(saved)
        return saved
    }

    func updateWorkout(_ session: WorkoutSession, expectedRevision: Int, expectedProfileID: UUID) throws -> WorkoutSession {
        var saved: WorkoutSession!
        try transaction(expectedProfileID) { snapshot in
            guard let index = snapshot.workouts.firstIndex(where: { $0.id == session.id }) else { throw DiaryError.notFound }
            let previous = snapshot.workouts[index]
            guard previous.revision == expectedRevision else { throw DiaryError.staleRevision }
            guard session.dayID == previous.dayID,
                  let day = snapshot.days.first(where: { $0.id == session.dayID }),
                  session.performedAt.timeIntervalSince1970.isFinite,
                  dateLabel(session.performedAt, zone: day.timeZoneID) == day.localDate else { throw DiaryError.invalidData }
            saved = session; saved.revision = previous.revision + 1
            snapshot.workouts[index] = saved
        }
        return saved
    }

    func deleteWorkout(id: UUID, expectedRevision: Int, expectedProfileID: UUID) throws {
        try transaction(expectedProfileID) { snapshot in
            try removeWorkout(id: id, expectedRevision: expectedRevision, snapshot: &snapshot)
        }
    }

    func updateProfile(_ profile: DiaryProfile, expectedProfileID: UUID? = nil) throws {
        try transaction(expectedProfileID) { snapshot in
            guard snapshot.profile.id == profile.id else { throw DiaryError.wrongOwner }
            if snapshot.profile.timeZoneID != profile.timeZoneID { snapshot.previousDayConfirmedAt = nil }
            snapshot.profile = profile
        }
    }

    func deleteProfile(_ id: UUID) throws {
        do {
            guard exists(id) else { throw DiaryError.persistenceFailed }
            // Remove recovery material first so deletion cannot expose an old diary.
            for url in [legacyFile(id), selectedFile(id)] where FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch { throw DiaryError.persistenceFailed }
        if current?.profile.id == id { current = nil; profileSelectionEpoch &+= 1 }
    }

    func exportData(expectedProfileID: UUID? = nil) throws -> Data {
        try JSONEncoder().encode(snapshot(expectedProfileID: expectedProfileID))
    }

    func restore(_ incoming: DiarySnapshot, expectedProfileID: UUID? = nil) throws {
        let original = try snapshot(expectedProfileID: expectedProfileID)
        try incoming.validate()
        guard incoming.profile.id == original.profile.id else { throw DiaryError.wrongOwner }
        guard incoming.revision >= original.revision,
              (incoming == original || incoming.isVerifiedSuccessor(of: original)),
              Set(incoming.meals.map(\.id)).isDisjoint(with: original.deletedMealIDs),
              Set(incoming.weights.map(\.id)).isDisjoint(with: original.deletedWeightIDs),
              Set(incoming.workouts.map(\.id)).isDisjoint(with: original.deletedWorkoutIDs) else { throw DiaryError.staleArchive }
        var replacement = incoming
        replacement.deletedMealIDs = Array(Set(incoming.deletedMealIDs + original.deletedMealIDs)).sorted { $0.uuidString < $1.uuidString }
        replacement.deletedWeightIDs = Array(Set(incoming.deletedWeightIDs + original.deletedWeightIDs)).sorted { $0.uuidString < $1.uuidString }
        replacement.deletedWorkoutIDs = Array(Set(incoming.deletedWorkoutIDs + original.deletedWorkoutIDs)).sorted { $0.uuidString < $1.uuidString }
        replacement.revision = max(incoming.revision, original.revision) + 1
        // shortcut: ancestors older than 255 writes cannot prove descent; require explicit recovery then.
        replacement.lineage = Array((incoming.lineage ?? []).suffix(255)) + [UUID()]
        try write(replacement)
        current = replacement
    }

    private func transaction(_ owner: UUID?, _ change: (inout DiarySnapshot) throws -> Void) throws {
        var next = try snapshot(expectedProfileID: owner)
        try change(&next)
        if stagedCoachSnapshot != nil { stagedCoachSnapshot = next; return }
        next.revision += 1
        // shortcut: bounded ancestry fails closed for snapshots more than 255 writes apart.
        next.lineage = Array((next.lineage ?? []).suffix(255)) + [UUID()]
        try write(next)
        current = next
    }

    private func startDay(in snapshot: inout DiarySnapshot, at: Date) -> TrackingDay {
        let localDate = dateLabel(at, zone: snapshot.profile.timeZoneID)
        let day = snapshot.days.first { $0.localDate == localDate && $0.timeZoneID == snapshot.profile.timeZoneID }
            ?? TrackingDay(localDate: localDate, timeZoneID: snapshot.profile.timeZoneID, startAt: at)
        if !snapshot.days.contains(where: { $0.id == day.id }) { snapshot.days.append(day) }
        snapshot.activeDayID = day.id
        snapshot.previousDayConfirmedAt = nil
        resolveCoachDayChoices(in: &snapshot, at: at, dayID: day.id)
        return day
    }

    private func dateLabel(_ date: Date, zone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func progressDay(_ localDate: String, in snapshot: inout DiarySnapshot) throws -> TrackingDay {
        guard validLocalDate(localDate) else { throw DiaryError.invalidData }
        if let existing = snapshot.days.first(where: {
            $0.localDate == localDate && $0.timeZoneID == snapshot.profile.timeZoneID
        }) { return existing }
        let day = TrackingDay(localDate: localDate, timeZoneID: snapshot.profile.timeZoneID,
                              startAt: try dateOnlyInstant(localDate, zone: snapshot.profile.timeZoneID))
        snapshot.days.append(day)
        return day
    }

    private func dateOnlyInstant(_ localDate: String, zone: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.isLenient = false
        guard let noon = formatter.date(from: localDate + " 12:00") else { throw DiaryError.invalidData }
        return noon
    }

    private func file(_ id: UUID) -> URL { selectedFile(id).appendingPathComponent("diary.sqlite") }
    private func legacyFile(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    private func selectedFile(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".sqlite") }
    private func exists(_ id: UUID) -> Bool {
        [file(id), legacyFile(id), selectedFile(id)].contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func read(_ url: URL, rememberIdentity: Bool = true) throws -> DiarySnapshot {
        guard let id = UUID(uuidString: url.deletingLastPathComponent().deletingPathExtension().lastPathComponent) else { throw DiaryError.invalidData }
        if FileManager.default.fileExists(atPath: url.path) || FileManager.default.fileExists(atPath: selectedFile(id).path) {
            let loaded = try DiaryDatabase(url: url).read(maximumBytes: maximumFileBytes)
            let identity = try fileIdentity(url)
            if rememberIdentity { fileIdentities[id] = identity }
            return loaded
        }
        let snapshot = try readLegacy(legacyFile(id))
        guard snapshot.profile.id == id else { throw DiaryError.wrongOwner }
        try createDatabase(snapshot)
        return snapshot
    }

    private func readLegacy(_ url: URL) throws -> DiarySnapshot {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= maximumFileBytes else { throw DiaryError.invalidData }
            let snapshot = try JSONDecoder().decode(DiarySnapshot.self, from: Data(contentsOf: url))
            try snapshot.validate()
            return snapshot
        } catch let error as DiaryError { throw error }
        catch { throw DiaryError.invalidData }
    }

    private func createDatabase(_ snapshot: DiarySnapshot) throws {
        let temporary = directory.appendingPathComponent("migration-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            #if os(iOS)
            for url in [directory, temporary] {
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
            }
            #endif
            do {
                let database = try DiaryDatabase(url: temporary.appendingPathComponent("diary.sqlite"), create: true)
                try database.write(snapshot, expected: nil, maximumBytes: maximumFileBytes)
                guard try database.read(maximumBytes: maximumFileBytes) == snapshot else { throw DiaryError.invalidData }
            }
            // The atomic directory switch is also the durable selection fence if its database is removed.
            try FileManager.default.moveItem(at: temporary, to: selectedFile(snapshot.profile.id))
            fileIdentities[snapshot.profile.id] = try fileIdentity(file(snapshot.profile.id))
        } catch let error as DiaryError { throw error }
        catch { throw DiaryError.persistenceFailed }
    }

    private func fileIdentity(_ url: URL) throws -> UInt64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let inode = attributes[.systemFileNumber] as? NSNumber else { throw DiaryError.persistenceFailed }
            return inode.uint64Value
        } catch { throw DiaryError.persistenceFailed }
    }

    private func write(_ snapshot: DiarySnapshot) throws {
        try snapshot.validate()
        guard try JSONEncoder().encode(snapshot).count <= maximumFileBytes else { throw DiaryError.invalidData }
        if let current, current.profile.id == snapshot.profile.id {
            guard try fileIdentity(file(snapshot.profile.id)) == fileIdentities[snapshot.profile.id] else { throw DiaryError.persistenceFailed }
            try DiaryDatabase(url: file(snapshot.profile.id)).write(snapshot, expected: current, maximumBytes: maximumFileBytes)
        } else {
            try createDatabase(snapshot)
        }
    }
    func selectionEpoch(expectedProfileID: UUID) throws -> UInt64 {
        _ = try snapshot(expectedProfileID: expectedProfileID)
        return profileSelectionEpoch
    }
    func validateSelection(epoch: UInt64, expectedProfileID: UUID) throws {
        _ = try snapshot(expectedProfileID: expectedProfileID)
        guard epoch == profileSelectionEpoch else { throw DiaryError.wrongOwner }
    }
    func captureCoachTurn(text: String, photos: [MealPhoto], at: Date = Date(), turnID: UUID = UUID(), pendingMealID: UUID? = nil, expectedProfileID: UUID) throws -> CoachTurn {
        let original = try snapshot(expectedProfileID: expectedProfileID)
        if let existing = original.coachTurns.first(where: { $0.id == turnID }) { return existing }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty else { throw DiaryError.emptyCapture }
        var turn = CoachTurn(id: turnID, capturedAt: at, text: text, photos: photos,
            captureTimeZoneID: original.profile.timeZoneID, activeDayID: original.activeDayID, photoIDs: photos.map(\.id))
        if let pendingMealID {
            guard let meal = original.meals.first(where: { $0.id == pendingMealID }),
                  let submission = meal.submissions.first(where: { $0.id == turnID }),
                  [.captured, .waitingForConnection, .analyzing, .needsRetry].contains(submission.state),
                  submission.baseRevision == meal.revision else { throw DiaryError.notFound }
            turn.pendingMealID = meal.id; turn.pendingMealRevision = meal.revision; turn.resolvedDayID = meal.dayID
            turn.captureTimeZoneID = original.days.first { $0.id == meal.dayID }!.timeZoneID
            turn.photos = []; turn.photoIDs = submission.photoIDs
        }
        try transaction(expectedProfileID) { $0.coachTurns.append(turn) }
        return turn
    }
    /// Called by the serialized worker only before starting a fresh analysis attempt.
    func preparePendingCoachTurn(turnID: UUID, expectedProfileID: UUID) throws -> CoachTurn {
        let original = try snapshot(expectedProfileID: expectedProfileID)
        let existing = original.coachTurns.first { $0.id == turnID }
        if let existing, existing.pendingMealID == nil { return existing }
        guard existing == nil || (existing!.state != .analyzing && existing!.state != .completed && existing!.receipts.isEmpty),
              let meal = original.meals.first(where: { $0.submissions.contains { $0.id == turnID } }),
              existing == nil || existing!.pendingMealID == meal.id,
              let submission = meal.submissions.first(where: { $0.id == turnID }),
              [.captured, .waitingForConnection, .analyzing, .needsRetry].contains(submission.state)
        else { throw DiaryError.staleRevision }
        if let existing, submission.baseRevision == meal.revision && existing.pendingMealRevision == meal.revision { return existing }
        var prepared: CoachTurn!
        try transaction(expectedProfileID) { snapshot in
            let m = snapshot.meals.firstIndex { $0.id == meal.id }!, s = snapshot.meals[m].submissions.firstIndex { $0.id == turnID }!
            snapshot.meals[m].submissions[s].baseRevision = meal.revision
            snapshot.meals[m].submissions[s].proposal = nil
            snapshot.meals[m].submissions[s].state = .captured
            if let t = snapshot.coachTurns.firstIndex(where: { $0.id == turnID }) {
                snapshot.coachTurns[t].pendingMealRevision = meal.revision
                prepared = snapshot.coachTurns[t]
            } else {
                prepared = CoachTurn(id: turnID, capturedAt: meal.capturedAt, text: submission.text, photos: [],
                    captureTimeZoneID: snapshot.days.first { $0.id == meal.dayID }!.timeZoneID,
                    activeDayID: meal.dayID, photoIDs: submission.photoIDs, resolvedDayID: meal.dayID,
                    pendingMealID: meal.id, pendingMealRevision: meal.revision)
                snapshot.coachTurns.append(prepared)
            }
        }
        return prepared
    }
    func coachTurn(turnID: UUID, expectedProfileID: UUID) throws -> CoachTurn {
        guard let turn = try snapshot(expectedProfileID: expectedProfileID).coachTurns.first(where: { $0.id == turnID }) else { throw DiaryError.notFound }
        return turn
    }
    func coachPhotos(turnID: UUID, expectedProfileID: UUID) throws -> [MealPhoto] {
        let snapshot = try snapshot(expectedProfileID: expectedProfileID)
        let turn = try coachTurn(turnID: turnID, expectedProfileID: expectedProfileID)
        let linkedMeals = Set(turn.receipts.compactMap(\.mealID) + (turn.pendingMealID.map { [$0] } ?? []))
        return turn.photoIDs.compactMap { id in turn.photos.first { $0.id == id } ?? snapshot.meals.filter { linkedMeals.contains($0.id) }.lazy.flatMap(\.photos).first { $0.id == id } }
    }
    func coachContext(turnID: UUID, expectedProfileID: UUID) throws -> CoachContext {
        let snapshot = try snapshot(expectedProfileID: expectedProfileID)
        let turn = try coachTurn(turnID: turnID, expectedProfileID: expectedProfileID)
        let days = Array(snapshot.days.suffix(14)), ids = Set(snapshot.days.suffix(14).map(\.id))
        let eligibleMeals = snapshot.meals.filter { ids.contains($0.dayID) }
        var profile = snapshot.profile
        profile.preferences = coachProse(profile.preferences, maximumBytes: 8192)
        profile.name = coachProse(profile.name, maximumBytes: 512)
        var recent = snapshot.coachTurns.filter { $0.id != turnID }.suffix(12).map {
            CoachContext.Turn(id: $0.id, capturedAt: $0.capturedAt, text: coachProse($0.text, maximumBytes: 1024),
                assistantText: $0.assistantText.map { coachProse($0, maximumBytes: 1024) })
        }
        while try JSONEncoder().encode(recent).count > 8192 { recent.removeFirst() }
        var context = CoachContext(profile: profile, capturedAt: turn.capturedAt, captureTimeZoneID: turn.captureTimeZoneID,
            activeDayID: turn.resolvedDayID ?? turn.activeDayID, days: days, meals: [], weights: Array(snapshot.weights.suffix(14)), recentTurns: recent)
        context.goal = snapshot.goal(on: dateLabel(turn.capturedAt, zone: turn.captureTimeZoneID))
        context.workouts = Array(snapshot.workouts.suffix(20)).compactMap { workout in
            snapshot.days.first { $0.id == workout.dayID }.map { WorkoutReference(id: workout.id, dayID: workout.dayID, localDate: $0.localDate, revision: workout.revision, kind: workout.kind, durationMinutes: workout.durationMinutes) }
        }
        context.omittedWorkoutCount = max(0, snapshot.workouts.count - (context.workouts?.count ?? 0))
        context.omittedWeightCount = max(0, snapshot.weights.count - context.weights.count)
        context.pendingMealID = turn.pendingMealID; context.pendingMealRevision = turn.pendingMealRevision
        context.truncated = profile != snapshot.profile || recent.count != snapshot.coachTurns.filter { $0.id != turnID }.count ||
            recent.contains { projected in snapshot.coachTurns.contains { $0.id == projected.id && ($0.text != projected.text || $0.assistantText != projected.assistantText) } }
        context.additionalMealCount = max(0, eligibleMeals.count - 40)
        for meal in eligibleMeals.suffix(40) {
            let projection = CoachContext.Meal(id: meal.id, dayID: meal.dayID, revision: meal.revision,
                eatenAt: meal.eatenAt, timePrecision: meal.timePrecision, items: meal.items, state: meal.state)
            let candidate = context.meals + [projection]
            if try JSONEncoder().encode(candidate).count <= 24_000 { context.meals.append(projection) }
            else { context.omittedMeals.append(CoachContext.MealReference(id: meal.id, dayID: meal.dayID, revision: meal.revision, itemCount: meal.items.count)) }
        }
        while try JSONEncoder().encode(context).count > 60_000, let meal = context.meals.first {
            context.meals.removeFirst()
            context.omittedMeals.append(CoachContext.MealReference(id: meal.id, dayID: meal.dayID, revision: meal.revision, itemCount: meal.items.count))
        }
        context.truncated = context.truncated || !context.omittedMeals.isEmpty || context.additionalMealCount > 0 || (context.omittedWorkoutCount ?? 0) > 0 || (context.omittedWeightCount ?? 0) > 0
        guard try JSONEncoder().encode(context).count <= 60_000 else { throw DiaryError.invalidData }
        return context
    }
    private func coachProse(_ value: String, maximumBytes: Int) -> String {
        guard value.utf8.count > maximumBytes else { return value }
        return String(decoding: value.utf8.prefix(maximumBytes), as: UTF8.self) + "…"
    }
    func setCoachTurnState(turnID: UUID, state: CoachTurnState, needsDayChoice: Bool = false, expectedProfileID: UUID) throws {
        try transaction(expectedProfileID) { snapshot in
            guard let i = snapshot.coachTurns.firstIndex(where: { $0.id == turnID }) else { throw DiaryError.notFound }
            snapshot.coachTurns[i].state = state
            snapshot.coachTurns[i].needsDayChoice = state == .needsClarification && needsDayChoice ? true : nil
            if state != .completed { snapshot.coachTurns[i].assistantText = nil }
        }
    }
    func completeCoachTurn(turnID: UUID, assistantText: String, expectedProfileID: UUID) throws {
        try transaction(expectedProfileID) { snapshot in
            guard let i = snapshot.coachTurns.firstIndex(where: { $0.id == turnID }) else { throw DiaryError.notFound }
            snapshot.coachTurns[i].assistantText = assistantText; snapshot.coachTurns[i].state = .completed
            snapshot.coachTurns[i].needsDayChoice = nil
        }
    }
    func applyCoachFood(turnID: UUID, targetLocalDate: String, items: [FoodItem], eatenAt: Date? = nil, expectedProfileID: UUID) throws -> CoachReceipt {
        let turn = try coachTurn(turnID: turnID, expectedProfileID: expectedProfileID)
        let key = "\(turnID.uuidString)/food/\(targetLocalDate)"
        if let receipt = turn.receipts.first(where: { $0.operationKey == key }) {
            guard try snapshot(expectedProfileID: expectedProfileID).meals.contains(where: { $0.id == receipt.mealID }) else { throw DiaryError.notFound }
            return receipt
        }
        guard !items.isEmpty else { throw DiaryError.invalidData }; try validateItems(items)
        var receipt: CoachReceipt!
        try transaction(expectedProfileID) { snapshot in
            let t = snapshot.coachTurns.firstIndex { $0.id == turnID }!
            let day = try coachDay(localDate: targetLocalDate, turn: turn, snapshot: &snapshot)
            var meal: DiaryMeal
            if let pendingID = turn.pendingMealID {
                guard let m = snapshot.meals.firstIndex(where: { $0.id == pendingID }),
                      let s = snapshot.meals[m].submissions.firstIndex(where: { $0.id == turn.id }),
                      snapshot.meals[m].submissions[s].state != .cancelled else { throw DiaryError.notFound }
                guard snapshot.meals[m].revision == turn.pendingMealRevision else { throw DiaryError.staleRevision }
                meal = snapshot.meals[m]
                if meal.revision > 0 { guard meal.dayID == day.id else { throw DiaryError.ambiguousDay } }
                meal.dayID = day.id
                let proposedItems = try coachFoodItems(items, in: meal, turnID: turn.id)
                let proposal = AnalysisOutput(profileID: expectedProfileID, mealID: meal.id, submissionID: turn.id, baseRevision: meal.revision, items: proposedItems)
                meal.submissions[s].proposal = proposal
                if meal.submissions[s].reviewFirst { meal.submissions[s].state = .awaitingReview }
                else { meal.items = proposedItems; meal.revision += 1; meal.submissions[s].state = .saved }
                // Coach timestamps are unconfirmed; retain the linked manual capture's precision.
                if turn.pendingMealRevision == 0 && day.id != turn.activeDayID { meal.eatenAt = day.startAt; meal.timePrecision = .dateOnly }
                snapshot.meals[m] = meal
            } else {
                meal = DiaryMeal(dayID: day.id, capturedAt: turn.capturedAt, eatenAt: day.startAt,
                    revision: 1, timePrecision: .dateOnly, items: items, photos: turn.photos)
                snapshot.meals.append(meal)
            }
            snapshot.coachTurns[t].photos = []
            if turn.pendingMealID != nil { snapshot.coachTurns[t].pendingMealRevision = meal.revision }
            receipt = CoachReceipt(operationKey: key, turnID: turnID, dayID: day.id, mealID: meal.id,
                committedRevision: snapshot.revision + 1, resultJSON: try coachJSON(CoachContext.Meal(id: meal.id, dayID: meal.dayID,
                    revision: meal.revision, eatenAt: meal.eatenAt, timePrecision: meal.timePrecision, items: meal.items, state: meal.state)))
            snapshot.coachTurns[t].receipts.append(receipt)
        }
        return receipt
    }
    func applyCoachItemCorrection(turnID: UUID, mealID: UUID, item: FoodItem, expectedRevision: Int, expectedProfileID: UUID) throws -> CoachReceipt {
        let turn = try coachTurn(turnID: turnID, expectedProfileID: expectedProfileID)
        guard turn.pendingMealID == nil || turn.pendingMealID == mealID else { throw DiaryError.invalidData }
        let key = "\(turnID.uuidString)/correct/\(mealID.uuidString)/\(item.id.uuidString)"
        let original = try snapshot(expectedProfileID: expectedProfileID)
        guard let meal = original.meals.first(where: { $0.id == mealID }), let previous = meal.items.first(where: { $0.id == item.id }) else { throw DiaryError.notFound }
        if let receipt = turn.receipts.first(where: { $0.operationKey == key }) { return receipt }
        guard meal.revision == expectedRevision,
              turn.pendingMealID != mealID || meal.revision == turn.pendingMealRevision else { throw DiaryError.staleRevision }
        let edited = try correctedItem(item, previous: previous); try validateItems([edited])
        var receipt: CoachReceipt!
        try transaction(expectedProfileID) { snapshot in
            let m = snapshot.meals.firstIndex { $0.id == mealID }!, t = snapshot.coachTurns.firstIndex { $0.id == turnID }!
            var proposedItems = snapshot.meals[m].submissions.first { $0.id == turnID && $0.state == .awaitingReview }?.proposal?.items ?? snapshot.meals[m].items
            guard let proposedIndex = proposedItems.firstIndex(where: { $0.id == item.id }) else { throw DiaryError.notFound }
            proposedItems[proposedIndex] = edited
            if turn.pendingMealID == mealID {
                guard let s = snapshot.meals[m].submissions.firstIndex(where: { $0.id == turnID }),
                      snapshot.meals[m].submissions[s].state != .cancelled else { throw DiaryError.notFound }
                snapshot.meals[m].submissions[s].proposal = AnalysisOutput(profileID: expectedProfileID, mealID: mealID,
                    submissionID: turnID, baseRevision: snapshot.meals[m].submissions[s].baseRevision, items: proposedItems)
                if snapshot.meals[m].submissions[s].reviewFirst { snapshot.meals[m].submissions[s].state = .awaitingReview }
                else { snapshot.meals[m].items = proposedItems; snapshot.meals[m].revision += 1; snapshot.meals[m].submissions[s].state = .saved }
            } else { snapshot.meals[m].items = proposedItems; snapshot.meals[m].revision += 1 }
            if turn.pendingMealID != nil { snapshot.coachTurns[t].pendingMealRevision = snapshot.meals[m].revision }
            receipt = CoachReceipt(operationKey: key, turnID: turnID, dayID: meal.dayID, mealID: mealID, itemID: item.id,
                committedRevision: snapshot.revision + 1, resultJSON: try coachJSON(CoachItemResult(mealID: mealID, revision: snapshot.meals[m].revision,
                    state: snapshot.meals[m].state, item: edited)))
            snapshot.coachTurns[t].receipts.append(receipt)
        }
        return receipt
    }
    func closeCoachDay(turnID: UUID, localDate: String, completeness: DayCompleteness, expectedProfileID: UUID) throws -> CoachReceipt {
        let turn = try coachTurn(turnID: turnID, expectedProfileID: expectedProfileID)
        let key = "\(turnID.uuidString)/close/\(localDate)"
        if let receipt = turn.receipts.first(where: { $0.operationKey == key }) { return receipt }
        var receipt: CoachReceipt!
        try transaction(expectedProfileID) { snapshot in
            let day = try coachDay(localDate: localDate, turn: turn, snapshot: &snapshot)
            let d = snapshot.days.firstIndex { $0.id == day.id }!, t = snapshot.coachTurns.firstIndex { $0.id == turnID }!
            snapshot.days[d].completeness = completeness; snapshot.days[d].closedAt = turn.capturedAt
            receipt = CoachReceipt(operationKey: key, turnID: turnID, dayID: day.id, committedRevision: snapshot.revision + 1,
                resultJSON: try coachJSON(snapshot.days[d]))
            snapshot.coachTurns[t].receipts.append(receipt)
        }
        return receipt
    }
    private func coachDay(localDate: String, turn: CoachTurn, snapshot: inout DiarySnapshot) throws -> TrackingDay {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(identifier: turn.captureTimeZoneID)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard localDate.count == 10, let date = formatter.date(from: localDate), formatter.string(from: date) == localDate else { throw DiaryError.invalidData }
        if localDate == dateLabel(turn.capturedAt, zone: turn.captureTimeZoneID), let chosen = turn.resolvedDayID {
            guard let day = snapshot.days.first(where: { $0.id == chosen }) else { throw DiaryError.notFound }
            return day
        }
        if localDate == dateLabel(turn.capturedAt, zone: turn.captureTimeZoneID),
           let active = snapshot.days.first(where: { $0.id == turn.activeDayID }), active.localDate != localDate { throw DiaryError.ambiguousDay }
        let currentDate = localDate == dateLabel(turn.capturedAt, zone: turn.captureTimeZoneID)
        let day = snapshot.days.first(where: { $0.localDate == localDate && $0.timeZoneID == turn.captureTimeZoneID })
            ?? TrackingDay(localDate: localDate, timeZoneID: turn.captureTimeZoneID, startAt: currentDate ? turn.capturedAt : date)
        if !snapshot.days.contains(where: { $0.id == day.id }) { snapshot.days.append(day) }
        if snapshot.activeDayID == nil && currentDate { snapshot.activeDayID = day.id; snapshot.previousDayConfirmedAt = nil }
        return day
    }

    private func correctedItem(_ item: FoodItem, previous: FoodItem) throws -> FoodItem {
        var edited = item
        edited.nutrientSources = previous.nutrientSources
        let nutrients: [(String, KeyPath<NutritionValues, Double?>)] = [("kcal", \.kcal), ("carbs", \.carbs), ("protein", \.protein), ("fat", \.fat)]
        for (name, field) in nutrients {
            edited.nutrientSources[name] = item.nutrition[keyPath: field] == previous.nutrition[keyPath: field]
                ? previous.nutrientSources[name] ?? previous.provenance : .user
        }
        if edited.quantity != previous.quantity && edited.nutrition == previous.nutrition {
            let basis = previous.nutritionBasis ?? (previous.quantity > 0 ? previous.nutrition.scaled(by: 1 / previous.quantity) : nil)
            guard let basis else { throw DiaryError.invalidData }
            edited.nutrition = basis.scaled(by: edited.quantity)
            edited.nutritionBasis = basis
        } else if edited.quantity > 0 {
            edited.nutritionBasis = edited.nutrition.scaled(by: 1 / edited.quantity)
        }
        edited.provenance = .user
        edited.reference = previous.reference
        edited.uncertain = previous.uncertain || edited.nutrientSources.values.contains { [.sample, .estimate].contains($0) }
        return edited
    }

    func coachMeal(id: UUID, expectedProfileID: UUID) throws -> CoachContext.Meal {
        guard let meal = try snapshot(expectedProfileID: expectedProfileID).meals.first(where: { $0.id == id }) else { throw DiaryError.notFound }
        var projection = CoachContext.Meal(id: meal.id, dayID: meal.dayID, revision: meal.revision,
            eatenAt: meal.eatenAt, timePrecision: meal.timePrecision, items: [], state: meal.state, omittedItemCount: meal.items.count)
        for item in meal.items {
            projection.items.append(item); projection.omittedItemCount -= 1
            if try JSONEncoder().encode(projection).count > 48_000 {
                projection.items.removeLast(); projection.omittedItemCount += 1; break
            }
        }
        return projection
    }
    func validateCoachWrites(_ writes: [CoachWrite], turnID: UUID, epoch: UInt64, expectedProfileID: UUID) throws {
        try validateSelection(epoch: epoch, expectedProfileID: expectedProfileID)
        guard Set(writes.map(\.target)).count == writes.count else { throw CoachError.invalidArguments }
        let turn = try coachTurn(turnID: turnID, expectedProfileID: expectedProfileID)
        var snapshot = try snapshot(expectedProfileID: expectedProfileID)
        let writes = try writes.map { try resolvedCoachWrite($0, turn: turn, snapshot: snapshot) }
        guard Set(writes.map(\.target)).count == writes.count else { throw CoachError.invalidArguments }
        let progressTargets = writes.compactMap { write -> String? in
            switch write {
            case .weight(let date, _, _, _):
                let dayIDs = Set(snapshot.days.filter { $0.localDate == date && $0.timeZoneID == turn.captureTimeZoneID }.map(\.id))
                if let weight = snapshot.weights.first(where: { $0.dayID.map { dayIDs.contains($0) } == true }) { return "weight/\(weight.id)" }
                return "weight-date/\(date)"
            case .correctWeight(let id, _, _, _), .deleteWeight(let id, _): return "weight/\(id)"
            case .editWorkout(let id, _, _), .deleteWorkout(let id, _): return "workout/\(id)"
            case .workout(let date, _): return "workout-date/\(date)"
            default: return nil
            }
        }
        guard Set(progressTargets).count == progressTargets.count else { throw CoachError.invalidArguments }
        if turn.pendingMealID != nil {
            guard writes.filter({ if case .food = $0 { return true }; return false }).count <= 1 else { throw CoachError.invalidArguments }
        }
        for write in writes {
            let key = "\(turnID.uuidString)/\(write.target)"
            let previousReceipt = turn.receipts.first { $0.operationKey == key }
            switch write {
            case .food(let date, let items, let eatenAt):
                let day = try coachDay(localDate: date, turn: turn, snapshot: &snapshot)
                guard !items.isEmpty else { throw DiaryError.invalidData }; try validateItems(items)
                if let eatenAt { guard dateLabel(eatenAt, zone: turn.captureTimeZoneID) == date else { throw DiaryError.invalidData } }
                if let previousReceipt {
                    guard snapshot.meals.contains(where: { $0.id == previousReceipt.mealID }) else { throw DiaryError.notFound }
                } else if let pendingID = turn.pendingMealID {
                    guard let meal = snapshot.meals.first(where: { $0.id == pendingID }),
                          let submission = meal.submissions.first(where: { $0.id == turnID }), submission.state != .cancelled else { throw DiaryError.notFound }
                    guard meal.revision == turn.pendingMealRevision else { throw DiaryError.staleRevision }
                    if meal.revision > 0 { guard meal.dayID == day.id else { throw DiaryError.ambiguousDay } }
                    _ = try coachFoodItems(items, in: meal, turnID: turnID)
                }
            case .correction(let mealID, let item, let revision):
                guard turn.pendingMealID == nil || turn.pendingMealID == mealID else { throw DiaryError.invalidData }
                guard let meal = snapshot.meals.first(where: { $0.id == mealID }),
                      let previous = meal.items.first(where: { $0.id == item.id }) else { throw DiaryError.notFound }
                if previousReceipt == nil {
                    guard meal.revision == revision,
                          turn.pendingMealID != mealID || meal.revision == turn.pendingMealRevision else { throw DiaryError.staleRevision }
                    try validateItems([correctedItem(item, previous: previous)])
                }
            case .close(let date, _): _ = try coachDay(localDate: date, turn: turn, snapshot: &snapshot)
            default:
                _ = try mutateCoachProgress(write, turn: turn, snapshot: &snapshot)
                var checked = snapshot; checked.revision += 1; try checked.validate()
            }
        }
        guard turn.receipts.count + writes.filter({ write in !turn.receipts.contains { $0.operationKey == "\(turnID.uuidString)/\(write.target)" } }).count <= 16 else { throw CoachError.limitExceeded }
    }
    func applyCoachWrites(_ writes: [CoachWrite], turnID: UUID, epoch: UInt64, expectedProfileID: UUID) throws -> [CoachReceipt] {
        try validateCoachWrites(writes, turnID: turnID, epoch: epoch, expectedProfileID: expectedProfileID)
        guard !writes.isEmpty else { return [] }
        let original = try snapshot(expectedProfileID: expectedProfileID)
        let priorKeys = Set(original.coachTurns.first { $0.id == turnID }!.receipts.map(\.operationKey))
        guard stagedCoachSnapshot == nil else { throw DiaryError.invalidData }
        stagedCoachSnapshot = original
        defer { stagedCoachSnapshot = nil }
        // No await: stage all record/receipt operations, then acknowledge one durable write.
        let receipts = try writes.map { write in
            switch write {
            case .food(let date, let items, let eatenAt):
                return try applyCoachFood(turnID: turnID, targetLocalDate: date, items: items, eatenAt: eatenAt, expectedProfileID: expectedProfileID)
            case .correction(let meal, let item, _):
                let revision = try snapshot(expectedProfileID: expectedProfileID).meals.first { $0.id == meal }!.revision
                return try applyCoachItemCorrection(turnID: turnID, mealID: meal, item: item, expectedRevision: revision, expectedProfileID: expectedProfileID)
            case .close(let date, let completeness):
                return try closeCoachDay(turnID: turnID, localDate: date, completeness: completeness, expectedProfileID: expectedProfileID)
            default:
                var receipt: CoachReceipt!
                try transaction(expectedProfileID) { snapshot in
                    let turn = snapshot.coachTurns.first { $0.id == turnID }!
                    receipt = try mutateCoachProgress(write, turn: turn, snapshot: &snapshot)
                }
                return receipt
            }
        }
        var next = stagedCoachSnapshot!
        if next != original {
            next.revision = original.revision + 1
            next.lineage = Array((original.lineage ?? []).suffix(255)) + [UUID()]
        }
        let t = next.coachTurns.firstIndex { $0.id == turnID }!
        for i in next.coachTurns[t].receipts.indices where !priorKeys.contains(next.coachTurns[t].receipts[i].operationKey) {
            next.coachTurns[t].receipts[i].committedRevision = next.revision
        }
        if next != original { try write(next); current = next }
        return receipts.map { receipt in next.coachTurns[t].receipts.first { $0.operationKey == receipt.operationKey }! }
    }
    func finishCoachTurn(turnID: UUID, assistantText: String, epoch: UInt64, expectedProfileID: UUID) throws {
        try validateSelection(epoch: epoch, expectedProfileID: expectedProfileID)
        try completeCoachTurn(turnID: turnID, assistantText: assistantText, expectedProfileID: expectedProfileID)
    }
    func failCoachTurn(turnID: UUID, state: CoachTurnState, needsDayChoice: Bool = false, epoch: UInt64, expectedProfileID: UUID) throws {
        try validateSelection(epoch: epoch, expectedProfileID: expectedProfileID)
        try setCoachTurnState(turnID: turnID, state: state, needsDayChoice: needsDayChoice, expectedProfileID: expectedProfileID)
    }
    func coachCommittedSummary(turnID: UUID, expectedProfileID: UUID) throws -> String {
        let snapshot = try snapshot(expectedProfileID: expectedProfileID)
        let turn = try coachTurn(turnID: turnID, expectedProfileID: expectedProfileID)
        var facts: [String] = []
        for receipt in turn.receipts {
            if let id = receipt.weightID {
                if let weight = snapshot.weights.first(where: { $0.id == id }) {
                    facts.append("Recorded weight: \(coachNumber(weight.value)) \(weight.unit).")
                } else { facts.append("This weight was deleted.") }
            } else if let id = receipt.workoutID {
                if let workout = snapshot.workouts.first(where: { $0.id == id }) {
                    facts.append("Recorded \(workout.kind.rawValue): \(workout.durationMinutes) minutes.")
                } else { facts.append("This workout was deleted.") }
            } else if let id = receipt.mealID {
                guard let meal = snapshot.meals.first(where: { $0.id == id }) else { facts.append("This meal was deleted."); continue }
                if meal.state == .awaitingReview { facts.append("Estimate ready for review."); continue }
                let names = meal.items.map(\.name).joined(separator: ", ")
                let calories = meal.totals.kcal.map { " \(Int($0.rounded())) kcal." } ?? " Calories are incomplete."
                facts.append("\(receipt.itemID == nil ? "Logged" : "Updated") \(names)." + calories + " Nutrition may be uncertain.")
            } else if let day = snapshot.days.first(where: { $0.id == receipt.dayID }) {
                facts.append("Closed \(day.localDate) as \(day.completeness.rawValue).")
            }
        }
        return facts.joined(separator: "\n")
    }

    private func resolvedCoachWrite(_ write: CoachWrite, turn: CoachTurn, snapshot: DiarySnapshot) throws -> CoachWrite {
        guard case .weight(let date, let value, let unit, let revision) = write else { return write }
        let createKey = "\(turn.id.uuidString)/weight/\(date)"
        // A completed create stays a create replay even after the weight is edited or deleted.
        if turn.receipts.contains(where: { $0.operationKey == createKey }) { return write }
        let dayIDs = Set(snapshot.days.filter { $0.localDate == date && $0.timeZoneID == turn.captureTimeZoneID }.map(\.id))
        let existingID = snapshot.weights.first { $0.dayID.map { dayIDs.contains($0) } == true }?.id
        let correctedID = turn.receipts.first { receipt in
            guard let id = receipt.weightID else { return false }
            return receipt.operationKey == "\(turn.id.uuidString)/correct_weight/\(id.uuidString)" && dayIDs.contains(receipt.dayID)
        }?.weightID
        if let id = correctedID ?? existingID {
            guard let revision else { throw DiaryError.staleRevision }
            return .correctWeight(id: id, value: value, unit: unit, revision: revision)
        }
        return write
    }

    private func mutateCoachProgress(_ write: CoachWrite, turn: CoachTurn, snapshot: inout DiarySnapshot) throws -> CoachReceipt {
        let write = try resolvedCoachWrite(write, turn: turn, snapshot: snapshot)
        let key = "\(turn.id.uuidString)/\(write.target)"
        if let receipt = turn.receipts.first(where: { $0.operationKey == key }) {
            switch write {
            case .deleteWeight:
                guard let id = receipt.weightID, snapshot.deletedWeightIDs.contains(id) else { throw DiaryError.notFound }
            case .deleteWorkout:
                guard let id = receipt.workoutID, snapshot.deletedWorkoutIDs.contains(id) else { throw DiaryError.notFound }
            default:
                guard receipt.weightID.map({ id in snapshot.weights.contains { $0.id == id } }) == true ||
                      receipt.workoutID.map({ id in snapshot.workouts.contains { $0.id == id } }) == true else { throw DiaryError.notFound }
            }
            return receipt
        }
        var dayID: UUID, weightID: UUID?, workoutID: UUID?, json: String
        switch write {
        case .weight(let date, let value, let unit, let revision):
            // A delayed morning capture cannot undo a newer explicit waking-day choice.
            let active = snapshot.days.first { $0.id == snapshot.activeDayID }
            var clockTurn = turn
            if date == dateLabel(turn.capturedAt, zone: turn.captureTimeZoneID) { clockTurn.activeDayID = nil; clockTurn.resolvedDayID = nil }
            let day = try coachDay(localDate: date, turn: clockTurn, snapshot: &snapshot)
            if date == dateLabel(turn.capturedAt, zone: turn.captureTimeZoneID),
               active == nil || (active!.localDate <= date && active!.startAt <= turn.capturedAt) {
                snapshot.activeDayID = day.id; snapshot.previousDayConfirmedAt = nil
            }
            guard !snapshot.weights.contains(where: { weight in
                weight.dayID != day.id && snapshot.days.contains { $0.id == weight.dayID && $0.localDate == date }
            }) else { throw DiaryError.staleRevision }
            let previous = snapshot.weights.first { $0.dayID == day.id }
            let saved = try saveWeight(on: day, value: value, unit: unit, at: previous?.measuredAt ?? dateOnlyInstant(date, zone: day.timeZoneID), precision: previous?.timePrecision ?? .dateOnly, expectedRevision: revision, snapshot: &snapshot)
            dayID = day.id; weightID = saved.id; json = try coachJSON(saved)
        case .correctWeight(let id, let value, let unit, let revision):
            guard let index = snapshot.weights.firstIndex(where: { $0.id == id }) else { throw DiaryError.notFound }
            guard snapshot.weights[index].revision == revision else { throw DiaryError.staleRevision }
            let linkedDay = try coachWeightReceiptDay(snapshot.weights[index], snapshot: &snapshot).id
            snapshot.weights[index].value = value; snapshot.weights[index].unit = unit; snapshot.weights[index].revision += 1
            dayID = linkedDay; weightID = id; json = try coachJSON(snapshot.weights[index])
        case .workout(let date, let draft):
            let day = try coachDay(localDate: date, turn: turn, snapshot: &snapshot)
            let saved = try appendWorkout(on: day, draft: draft, performedAt: nil, snapshot: &snapshot)
            dayID = day.id; workoutID = saved.id; json = try coachJSON(saved)
        case .editWorkout(let id, let draft, let revision):
            guard let index = snapshot.workouts.firstIndex(where: { $0.id == id }) else { throw DiaryError.notFound }
            guard snapshot.workouts[index].revision == revision else { throw DiaryError.staleRevision }
            snapshot.workouts[index].kind = draft.kind; snapshot.workouts[index].durationMinutes = draft.durationMinutes
            snapshot.workouts[index].exercises = draft.exercises; snapshot.workouts[index].estimatedBurnKcal = draft.estimatedBurnKcal
            snapshot.workouts[index].burnSource = draft.burnSource; snapshot.workouts[index].revision += 1
            dayID = snapshot.workouts[index].dayID; workoutID = id; json = try coachJSON(snapshot.workouts[index])
        case .deleteWeight(let id, let revision):
            guard let index = snapshot.weights.firstIndex(where: { $0.id == id }) else { throw DiaryError.notFound }
            guard snapshot.weights[index].revision == revision else { throw DiaryError.staleRevision }
            let linkedDay = try coachWeightReceiptDay(snapshot.weights[index], snapshot: &snapshot).id
            snapshot.weights.remove(at: index); snapshot.deletedWeightIDs.append(id)
            dayID = linkedDay; weightID = id; json = try coachJSON(CoachDeletedRecord(id: id, deleted: true))
        case .deleteWorkout(let id, let revision):
            guard let index = snapshot.workouts.firstIndex(where: { $0.id == id }) else { throw DiaryError.notFound }
            guard snapshot.workouts[index].revision == revision else { throw DiaryError.staleRevision }
            dayID = snapshot.workouts[index].dayID; workoutID = id
            try removeWorkout(id: id, expectedRevision: revision, snapshot: &snapshot)
            json = try coachJSON(CoachDeletedRecord(id: id, deleted: true))
        default: throw CoachError.invalidArguments
        }
        let receipt = CoachReceipt(operationKey: key, turnID: turn.id, dayID: dayID, weightID: weightID, workoutID: workoutID, committedRevision: snapshot.revision + 1, resultJSON: json)
        let index = snapshot.coachTurns.firstIndex { $0.id == turn.id }!
        snapshot.coachTurns[index].receipts.append(receipt)
        return receipt
    }

    private func coachWeightReceiptDay(_ weight: WeightEntry, snapshot: inout DiarySnapshot) throws -> TrackingDay {
        if let id = weight.dayID, let day = snapshot.days.first(where: { $0.id == id }) { return day }
        let zone = snapshot.profile.timeZoneID, date = dateLabel(weight.measuredAt, zone: zone)
        if let day = snapshot.days.first(where: { $0.localDate == date && $0.timeZoneID == zone }) { return day }
        let day = TrackingDay(localDate: date, timeZoneID: zone, startAt: try dateOnlyInstant(date, zone: zone))
        snapshot.days.append(day)
        return day
    }

    private func removeWorkout(id: UUID, expectedRevision: Int, snapshot: inout DiarySnapshot) throws {
        guard let index = snapshot.workouts.firstIndex(where: { $0.id == id }) else { throw DiaryError.notFound }
        guard snapshot.workouts[index].revision == expectedRevision else { throw DiaryError.staleRevision }
        snapshot.workouts.remove(at: index); snapshot.deletedWorkoutIDs.append(id)
        for index in snapshot.coachTurns.indices where snapshot.coachTurns[index].receipts.contains(where: { $0.workoutID == id }) {
            let attached = snapshot.coachTurns[index]
            let survivingLink = attached.receipts.contains { $0.weightID.map({ weightID in snapshot.weights.contains { $0.id == weightID } }) == true || $0.mealID.map({ mealID in snapshot.meals.contains { $0.id == mealID } }) == true || $0.workoutID.map({ workoutID in snapshot.workouts.contains { $0.id == workoutID } }) == true }
            if !survivingLink && attached.pendingMealID == nil {
                snapshot.coachTurns[index].photos.removeAll(); snapshot.coachTurns[index].photoIDs.removeAll()
            }
        }
    }

    private struct CoachDeletedRecord: Codable { var id: UUID; var deleted: Bool }

    func coachWorkout(id: UUID, expectedProfileID: UUID) throws -> WorkoutSession {
        guard let workout = try snapshot(expectedProfileID: expectedProfileID).workouts.first(where: { $0.id == id }) else { throw DiaryError.notFound }
        // Full replacement must never be based on unseen sets.
        guard try JSONEncoder().encode(workout).count <= 48_000 else { throw CoachError.limitExceeded }
        return workout
    }

    func coachProgress(endingOn: String, days: Int, finalizingTurnID: UUID? = nil, expectedProfileID: UUID) throws -> CoachProgress {
        guard validLocalDate(endingOn), [1, 7, 30].contains(days) else { throw CoachError.invalidArguments }
        var snapshot = try snapshot(expectedProfileID: expectedProfileID)
        if let finalizingTurnID {
            guard let index = snapshot.coachTurns.firstIndex(where: { $0.id == finalizingTurnID }) else { throw DiaryError.notFound }
            // The successful final reply resolves this question; other captures stay pending.
            snapshot.coachTurns[index].state = .completed
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: snapshot.profile.timeZoneID)!
        let start = calendar.date(byAdding: .day, value: 1 - days, to: try dateOnlyInstant(endingOn, zone: snapshot.profile.timeZoneID))!
        let startLabel = dateLabel(start, zone: snapshot.profile.timeZoneID)
        let labels = Dictionary(uniqueKeysWithValues: snapshot.days.map { ($0.id, $0.localDate) })
        let weights = snapshot.weights.compactMap { record -> CoachWeightReference? in
            let label = record.dayID.flatMap { labels[$0] } ?? dateLabel(record.measuredAt, zone: snapshot.profile.timeZoneID)
            guard label >= startLabel && label <= endingOn else { return nil }
            return CoachWeightReference(localDate: label, record: record)
        }
        let workouts = snapshot.workouts.compactMap { record -> WorkoutReference? in
            guard let label = labels[record.dayID], label >= startLabel && label <= endingOn else { return nil }
            return WorkoutReference(id: record.id, dayID: record.dayID, localDate: label, revision: record.revision, kind: record.kind, durationMinutes: record.durationMinutes)
        }
        return CoachProgress(startLocalDate: startLabel, endLocalDate: endingOn,
            daily: ProgressAnalytics.daily(snapshot: snapshot, localDate: endingOn),
            period: days == 1 ? nil : ProgressAnalytics.period(snapshot: snapshot, endingOn: endingOn, days: days),
            weight: ProgressAnalytics.weight(snapshot: snapshot, endingOn: endingOn),
            weights: Array(weights.suffix(40)), workouts: Array(workouts.suffix(100)),
            omittedWeightCount: max(0, weights.count - 40), omittedWorkoutCount: max(0, workouts.count - 100),
            truncated: weights.count > 40 || workouts.count > 100)
    }

    func coachWorkoutSummary(id: UUID, expectedProfileID: UUID) throws -> String {
        let snapshot = try snapshot(expectedProfileID: expectedProfileID)
        if snapshot.deletedWorkoutIDs.contains(id) { return "This workout was deleted." }
        let workout = try coachWorkout(id: id, expectedProfileID: expectedProfileID)
        let day = snapshot.days.first { $0.id == workout.dayID }!
        var facts = ["\(day.localDate): recorded \(workout.kind.rawValue), \(workout.durationMinutes) minutes; revision \(workout.revision)."]
        for exercise in workout.exercises {
            facts.append(exercise.name + ": " + exercise.sets.map { "\($0.repetitions) reps" + ($0.loadKg.map { " at \(coachNumber($0)) kg" } ?? " (load unset)") }.joined(separator: ", "))
        }
        facts.append("Estimated burn: " + (workout.estimatedBurnKcal.map { "\(coachNumber($0)) kcal (\(workout.burnSource?.rawValue ?? "source unset"))." } ?? "unknown."))
        return facts.joined(separator: "\n")
    }

    private func coachNumber(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US")))
    }

    func coachProgressSummary(endingOn: String, days: Int, finalizingTurnID: UUID? = nil, expectedProfileID: UUID) throws -> String {
        let report = try coachProgress(endingOn: endingOn, days: days, finalizingTurnID: finalizingTurnID, expectedProfileID: expectedProfileID)
        var facts = ["\(report.startLocalDate) through \(report.endLocalDate)."]
        let daily = report.daily
        facts.append("Recorded food: " + (daily.foodTotals?.kcal.map { "\(coachNumber($0)) kcal." } ?? "calories unknown."))
        facts.append("Remaining from recorded food: " + (daily.remainingFromRecorded.kcal.map { "\(coachNumber($0)) kcal." } ?? "unknown (target or intake missing)."))
        if let goal = daily.goal {
            facts.append("Configured target: " + (goal.targets.kcal.map { "\(coachNumber($0)) kcal." } ?? "calories unset."))
        }
        for (name, field) in [("carbs", \NutritionValues.carbs), ("protein", \NutritionValues.protein), ("fat", \NutritionValues.fat)] {
            facts.append("Remaining \(name) from recorded food: " + (daily.remainingFromRecorded[keyPath: field].map { "\(coachNumber($0)) g." } ?? "unknown."))
        }
        facts.append("Recorded workouts: \(daily.workoutCount).")
        facts.append("Estimated exercise burn: " + (daily.estimatedBurnKcal.map { "\(coachNumber($0)) kcal." } ?? "unknown."))
        if let adjusted = daily.exerciseAdjustedKcalRemaining { facts.append("Explicit exercise-adjusted remaining: \(coachNumber(adjusted)) kcal.") }
        if let period = report.period {
            facts.append("Coverage: \(period.completeDayCount) complete, \(period.partialDayCount) partial, \(period.untrackedDayCount) untracked, \(period.unknownDayCount) unknown, \(period.missingDayCount) missing, \(period.pendingDayCount) pending days.")
            facts.append("Average recorded intake: " + (period.averageIntake.kcal.map { "\(coachNumber($0)) kcal from \(period.knownIntakeSamples.kcal) complete known days." } ?? "unknown."))
            for (name, field, count) in [("carbs", \NutritionValues.carbs, period.knownIntakeSamples.carbs), ("protein", \NutritionValues.protein, period.knownIntakeSamples.protein), ("fat", \NutritionValues.fat, period.knownIntakeSamples.fat)] {
                facts.append("Average \(name): " + (period.averageIntake[keyPath: field].map { "\(coachNumber($0)) g from \(count) complete known days." } ?? "unknown."))
            }
            facts.append("Period recorded workouts: \(period.workoutCount).")
            facts.append("Within 10% of target: \(period.adherenceNumerator)/\(period.adherenceDenominator) eligible days.")
        } else { facts.append("Day coverage: \(daily.completeness?.rawValue ?? "missing"); pending: \(daily.hasPending).") }
        facts.append("Weight average: " + (report.weight.currentSevenDayAverageKg.map { "\(coachNumber($0)) kg" } ?? "unknown") + " from \(report.weight.currentSevenDayObservedCount) measured dates.")
        facts.append("Weight change versus prior 7-day window: " + (report.weight.changeFromSevenDaysAgoKg.map { "\(coachNumber($0)) kg." } ?? "insufficient data."))
        facts.append("Weight change versus 30 days ago: " + (report.weight.changeFromThirtyDaysAgoKg.map { "\(coachNumber($0)) kg." } ?? "insufficient data."))
        facts.append("Observed plateau readiness: \(report.weight.plateau.rawValue).")
        facts.append("Record references omitted: \(report.omittedWeightCount) weights, \(report.omittedWorkoutCount) workouts.")
        return facts.joined(separator: "\n")
    }

    private func appendManualCoachTurn(meal: DiaryMeal, submissionID: UUID, at: Date, snapshot: inout DiarySnapshot) {
        let submission = meal.submissions.first { $0.id == submissionID }!
        snapshot.coachTurns.append(CoachTurn(id: submissionID, capturedAt: at, text: submission.text,
            captureTimeZoneID: snapshot.days.first { $0.id == meal.dayID }!.timeZoneID, activeDayID: snapshot.activeDayID,
            photoIDs: submission.photoIDs, resolvedDayID: meal.dayID, pendingMealID: meal.id, pendingMealRevision: meal.revision))
    }

    private struct CoachItemResult: Encodable {
        var mealID: UUID
        var revision: Int
        var state: SubmissionState
        var item: FoodItem
    }
    private func coachFoodItems(_ additions: [FoodItem], in meal: DiaryMeal, turnID: UUID) throws -> [FoodItem] {
        guard meal.revision > 0 else { return additions }
        let priorItems = meal.submissions.first { $0.id == turnID && $0.state == .awaitingReview }?.proposal?.items ?? meal.items
        let existingIDs = Set(priorItems.map(\.id))
        let existingNames = Set(priorItems.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        guard additions.allSatisfy({ !existingIDs.contains($0.id) && !existingNames.contains($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }) else { throw DiaryError.invalidData }
        let items = priorItems + additions
        try validateItems(items)
        return items
    }

    private func resolveCoachDayChoices(in snapshot: inout DiarySnapshot, at: Date, dayID: UUID) {
        for i in snapshot.coachTurns.indices where snapshot.coachTurns[i].state == .needsClarification && snapshot.coachTurns[i].needsDayChoice == true {
            let turn = snapshot.coachTurns[i]
            if dateLabel(turn.capturedAt, zone: turn.captureTimeZoneID) == dateLabel(at, zone: turn.captureTimeZoneID) {
                snapshot.coachTurns[i].resolvedDayID = dayID
                snapshot.coachTurns[i].needsDayChoice = nil
            }
        }
    }
    func coachRecordedSummary(expectedProfileID: UUID) throws -> String {
        let snapshot = try snapshot(expectedProfileID: expectedProfileID)
        let days = snapshot.days.filter { day in day.completeness == .complete || snapshot.meals.contains { $0.dayID == day.id && $0.isSaved } }.suffix(14)
        let facts = days.map { day in
            let totals = snapshot.totals(dayID: day.id)
            return "\(day.localDate): " + (totals.kcal.map { "\(Int($0.rounded())) kcal" } ?? "calories incomplete") + "."
        }
        return "No new food was saved in this turn.\n" + (facts.isEmpty ? "There are no recorded food totals yet." : facts.joined(separator: "\n"))
    }

    func chooseCoachDay(turnID: UUID, usePrevious: Bool, at: Date = Date(), expectedProfileID: UUID) throws {
        let turn = try coachTurn(turnID: turnID, expectedProfileID: expectedProfileID)
        guard turn.needsDayChoice == true else { throw DiaryError.invalidData }
        try transaction(expectedProfileID) { snapshot in
            let day: TrackingDay
            if usePrevious {
                guard let previous = snapshot.days.first(where: { $0.id == turn.activeDayID }) else { throw DiaryError.notFound }
                day = previous
            } else {
                let date = dateLabel(turn.capturedAt, zone: turn.captureTimeZoneID)
                day = snapshot.days.first { $0.localDate == date && $0.timeZoneID == turn.captureTimeZoneID }
                    ?? TrackingDay(localDate: date, timeZoneID: turn.captureTimeZoneID, startAt: turn.capturedAt)
                if !snapshot.days.contains(where: { $0.id == day.id }) { snapshot.days.append(day) }
                if dateLabel(at, zone: turn.captureTimeZoneID) == date { snapshot.activeDayID = day.id; snapshot.previousDayConfirmedAt = nil }
            }
            let i = snapshot.coachTurns.firstIndex { $0.id == turnID }!
            snapshot.coachTurns[i].resolvedDayID = day.id; snapshot.coachTurns[i].needsDayChoice = nil
        }
    }

}
