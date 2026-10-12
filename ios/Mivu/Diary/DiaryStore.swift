import Foundation

/// One serialized writer; a mutation becomes visible only after atomic disk replacement.
actor DiaryStore {
    private let directory: URL
    private var current: DiarySnapshot?
    init(directory: URL, maximumFileBytes: Int = 350_000_000) {
        self.directory = directory
        self.maximumFileBytes = min(maximumFileBytes, 350_000_000)
    }
    private let maximumFileBytes: Int

    func profiles() throws -> [DiaryProfile] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        do {
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
                .map { url in
                    let profile = try read(url).profile
                    guard url.deletingPathExtension().lastPathComponent == profile.id.uuidString else { throw DiaryError.wrongOwner }
                    return profile
                }.sorted { $0.name < $1.name }
        } catch let error as DiaryError { throw error }
        catch { throw DiaryError.persistenceFailed }
    }

    func createProfile(_ profile: DiaryProfile) throws -> DiarySnapshot {
        guard !FileManager.default.fileExists(atPath: file(profile.id).path) else { throw DiaryError.invalidData }
        var snapshot = DiarySnapshot(profile: profile)
        snapshot.lineage = [UUID()]
        try write(snapshot)
        current = snapshot
        return snapshot
    }

    func importProfile(_ incoming: DiarySnapshot) throws -> DiarySnapshot {
        try incoming.validate()
        guard !FileManager.default.fileExists(atPath: file(incoming.profile.id).path) else { throw DiaryError.invalidData }
        try write(incoming)
        current = incoming
        return incoming
    }

    func selectProfile(_ id: UUID) throws -> DiarySnapshot {
        let loaded = try read(file(id))
        guard loaded.profile.id == id else { throw DiaryError.wrongOwner }
        current = loaded
        return loaded
    }

    func signOut() { current = nil }

    func snapshot(expectedProfileID: UUID? = nil) throws -> DiarySnapshot {
        guard let current else { throw DiaryError.noProfile }
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
        }
    }

    func capture(text: String, photos: [MealPhoto], reviewFirst: Bool, dayID: UUID, at: Date = Date(), submissionID: UUID = UUID(), expectedProfileID: UUID? = nil) throws -> DiaryMeal {
        let original = try snapshot(expectedProfileID: expectedProfileID)
        if let existing = original.meals.first(where: { $0.submissions.contains { $0.id == submissionID } }) { return existing }
        var meal = DiaryMeal(dayID: dayID, capturedAt: at, eatenAt: at, photos: photos,
            submissions: [MealSubmission(id: submissionID, baseRevision: 0, text: text, photoIDs: photos.map(\.id), reviewFirst: reviewFirst)])
        try transaction(expectedProfileID) { snapshot in
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty else { throw DiaryError.emptyCapture }
            guard snapshot.days.contains(where: { $0.id == dayID }) else { throw DiaryError.notFound }
            meal.items = []
            snapshot.meals.append(meal)
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
            edited.uncertain = edited.nutrientSources.values.contains { [.sample, .estimate].contains($0) }
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

    func correctMeal(mealID: UUID, text: String, photos: [MealPhoto] = [], reviewFirst: Bool = false, submissionID: UUID = UUID(), expectedProfileID: UUID? = nil) throws -> DiaryMeal {
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
            snapshot.meals.removeAll { $0.id == mealID }
            snapshot.deletedMealIDs.append(mealID)
        }
    }

    func moveMeal(_ mealID: UUID, to dayID: UUID, expectedProfileID: UUID? = nil) throws {
        try transaction(expectedProfileID) { snapshot in
            guard snapshot.days.contains(where: { $0.id == dayID }), let m = snapshot.meals.firstIndex(where: { $0.id == mealID })
            else { throw DiaryError.notFound }
            snapshot.meals[m].dayID = dayID
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
                weight = snapshot.weights[w]
            } else {
                weight = WeightEntry(dayID: dayID, measuredAt: at, value: value, unit: unit)
                snapshot.weights.append(weight)
            }
        }
        return weight
    }

    func updateProfile(_ profile: DiaryProfile, expectedProfileID: UUID? = nil) throws {
        try transaction(expectedProfileID) { snapshot in
            guard snapshot.profile.id == profile.id else { throw DiaryError.wrongOwner }
            if snapshot.profile.timeZoneID != profile.timeZoneID { snapshot.previousDayConfirmedAt = nil }
            snapshot.profile = profile
        }
    }

    func deleteProfile(_ id: UUID) throws {
        do { try FileManager.default.removeItem(at: file(id)) }
        catch { throw DiaryError.persistenceFailed }
        if current?.profile.id == id { current = nil }
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
              Set(incoming.meals.map(\.id)).isDisjoint(with: original.deletedMealIDs) else { throw DiaryError.staleArchive }
        var replacement = incoming
        replacement.deletedMealIDs = Array(Set(incoming.deletedMealIDs + original.deletedMealIDs)).sorted { $0.uuidString < $1.uuidString }
        replacement.revision = max(incoming.revision, original.revision) + 1
        // shortcut: ancestors older than 255 writes cannot prove descent; require explicit recovery then.
        replacement.lineage = Array((incoming.lineage ?? []).suffix(255)) + [UUID()]
        try write(replacement)
        current = replacement
    }

    private func transaction(_ owner: UUID?, _ change: (inout DiarySnapshot) throws -> Void) throws {
        var next = try snapshot(expectedProfileID: owner)
        try change(&next)
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

    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }

    private func read(_ url: URL) throws -> DiarySnapshot {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= maximumFileBytes else { throw DiaryError.invalidData }
            let snapshot = try JSONDecoder().decode(DiarySnapshot.self, from: Data(contentsOf: url))
            try snapshot.validate()
            return snapshot
        } catch let error as DiaryError { throw error }
        catch { throw DiaryError.invalidData }
    }

    private func write(_ snapshot: DiarySnapshot) throws {
        try snapshot.validate()
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= maximumFileBytes else { throw DiaryError.invalidData }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            #if os(iOS)
            try data.write(to: file(snapshot.profile.id), options: [.atomic, .completeFileProtectionUnlessOpen])
            #else
            try data.write(to: file(snapshot.profile.id), options: .atomic)
            #endif
        } catch { throw DiaryError.persistenceFailed }
    }
}
