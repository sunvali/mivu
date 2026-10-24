import Foundation

struct DiaryProfile: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    var language = "en"
    var timeZoneID = TimeZone.current.identifier
    var preferences = ""
    /// Body, goal and diet answers from onboarding; nil for diaries that never ran it.
    var about: ProfileAbout? = nil
}

struct ProfileAbout: Codable, Equatable, Sendable {
    enum Sex: String, Codable, CaseIterable, Sendable { case female, male, unspecified }
    enum Pace: String, Codable, CaseIterable, Sendable {
        case gentle, steady, faster
        var kgPerWeek: Double { switch self { case .gentle: 0.25; case .steady: 0.5; case .faster: 0.75 } }
    }
    var heightCm: Double
    var birthYear: Int
    var sex = Sex.unspecified
    var pace = Pace.steady
    var dietTags: [String] = []
    var healthNotes = ""
}

enum DayCompleteness: String, Codable, CaseIterable, Sendable { case unknown, complete, partial, untracked }
enum PhotoRole: String, Codable, CaseIterable, Sendable { case unspecified, before, after }
enum NutritionProvenance: String, Codable, Sendable { case sample, user, confirmedLabel, identifiedSource, estimate }
enum SubmissionState: String, Codable, Sendable { case captured, waitingForConnection, analyzing, awaitingReview, saved, needsRetry, cancelled }
enum DayAssignment: Equatable, Sendable { case existing(UUID), newDay }

enum DiaryError: Error, Equatable, LocalizedError {
    case noProfile, wrongOwner, invalidData, invalidAmountUnitChange, persistenceFailed, staleRevision, notFound, emptyCapture, ambiguousDay, staleArchive
    var errorDescription: String? {
        switch self {
        case .noProfile: "Choose a local profile first."
        case .wrongOwner: "The profile changed. Please try again."
        case .invalidData: "This diary contains invalid or unsupported data."
        case .invalidAmountUnitChange: "Enter or clear each known nutrient when changing to an unrelated unit."
        case .persistenceFailed: "The diary could not be saved. Your input is still available."
        case .staleRevision: "This meal changed. Please retry the correction."
        case .notFound: "This diary entry no longer exists."
        case .emptyCapture: "Add a photo or a meal description."
        case .ambiguousDay: "Your day just changed. Save again to add this to the new day."
        case .staleArchive: "This backup conflicts with the diary or contains deleted meals. Keep both copies and choose how to recover."
        }
    }
}

struct NutritionValues: Codable, Equatable, Sendable {
    var kcal: Double? = nil
    var carbs: Double? = nil
    var protein: Double? = nil
    var fat: Double? = nil
    func scaled(by factor: Double) -> NutritionValues {
        NutritionValues(kcal: kcal.map { $0 * factor }, carbs: carbs.map { $0 * factor },
                        protein: protein.map { $0 * factor }, fat: fat.map { $0 * factor })
    }
}

struct NutritionTotals: Equatable, Sendable {
    var kcal: Double?
    var carbs: Double?
    var protein: Double?
    var fat: Double?
    var unknownItemCount: Int
}

struct FoodItem: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    var quantity: Double = 1
    var unit = "medium"
    var nutrition: NutritionValues
    var provenance: NutritionProvenance = .sample
    var reference = "Synthetic medium apple"
    var uncertain = true
    var nutrientSources: [String: NutritionProvenance] = [:]
    var nutritionBasis: NutritionValues? = nil
}

struct MealPhoto: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var data: Data
    var createdAt = Date()
    var role: PhotoRole = .unspecified
}

struct TrackingDay: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var localDate: String
    var timeZoneID: String
    var startAt: Date
    var completeness: DayCompleteness = .unknown
    var closedAt: Date? = nil
}

struct MealSubmission: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var baseRevision: Int
    var text: String
    var photoIDs: [UUID]
    var reviewFirst: Bool
    var state: SubmissionState = .captured
    var proposal: AnalysisOutput? = nil
    var manualAcceptance: ManualNutritionAcceptance? = nil
}

struct DiaryMeal: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var dayID: UUID
    var capturedAt: Date
    var eatenAt: Date
    var revision = 0
    /// Diary head revision that last wrote this meal; nil on payloads saved before Coach focus.
    var changedRevision: Int? = nil
    var timePrecision: MealTimePrecision? = nil
    var items: [FoodItem] = []
    var photos: [MealPhoto] = []
    var submissions: [MealSubmission] = []
    var totals: NutritionTotals { nutritionTotals(items) }
    var isSaved: Bool { revision > 0 }
    var state: SubmissionState { submissions.last?.state ?? .saved }
    var hasUnresolvedInput: Bool {
        (!isSaved && submissions.isEmpty)
            || submissions.contains { $0.state != .saved && $0.state != .cancelled }
    }
}

struct WeightEntry: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var dayID: UUID?
    var measuredAt: Date
    var value: Double
    var unit = "kg"
    var revision = 1
    var timePrecision: MealTimePrecision = .exact
}

extension WeightEntry {
    enum CodingKeys: String, CodingKey { case id, dayID, measuredAt, value, unit, revision, timePrecision }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        dayID = try c.decodeIfPresent(UUID.self, forKey: .dayID)
        measuredAt = try c.decode(Date.self, forKey: .measuredAt)
        value = try c.decode(Double.self, forKey: .value)
        unit = try c.decode(String.self, forKey: .unit)
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        timePrecision = try c.decodeIfPresent(MealTimePrecision.self, forKey: .timePrecision) ?? .exact
    }
}

struct GoalRecord: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var effectiveLocalDate: String
    var timeZoneID: String
    var revision = 1
    var targets: NutritionValues
    var goalWeightKg: Double?
    var exerciseCreditEnabled: Bool
}

enum WorkoutKind: String, Codable, Sendable { case strength, cardio, other }
enum WorkoutBurnSource: String, Codable, Sendable { case userEstimate, modelEstimate }

struct WorkoutSet: Codable, Equatable, Sendable {
    var repetitions: Int
    var loadKg: Double?
}

struct WorkoutExercise: Codable, Equatable, Sendable {
    var name: String
    var sets: [WorkoutSet]
}

struct WorkoutDraft: Equatable, Sendable {
    var kind: WorkoutKind
    var durationMinutes: Int
    var exercises: [WorkoutExercise]
    var estimatedBurnKcal: Double?
    var burnSource: WorkoutBurnSource?
}

struct WorkoutSession: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var dayID: UUID
    var performedAt: Date
    var timePrecision: MealTimePrecision
    var revision: Int
    var kind: WorkoutKind
    var durationMinutes: Int
    var exercises: [WorkoutExercise]
    var estimatedBurnKcal: Double?
    var burnSource: WorkoutBurnSource?
}

struct AnalysisInput: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var profileID: UUID
    var mealID: UUID
    var submissionID: UUID
    var baseRevision: Int
    var text: String
    var photos: [MealPhoto]
    var currentItems: [FoodItem]
    var language = "en"
    var preferences = ""
}

struct AnalysisOutput: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var profileID: UUID
    var mealID: UUID
    var submissionID: UUID
    var baseRevision: Int
    var items: [FoodItem]
}

struct DiarySnapshot: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var revision = 0
    var profile: DiaryProfile
    var days: [TrackingDay] = []
    var meals: [DiaryMeal] = []
    var weights: [WeightEntry] = []
    var goals: [GoalRecord] = []
    var workouts: [WorkoutSession] = []
    var coachTurns: [CoachTurn] = []
    var activeDayID: UUID? = nil
    var previousDayConfirmedAt: Date? = nil
    var deletedMealIDs: [UUID] = []
    var deletedWeightIDs: [UUID] = []
    var deletedWorkoutIDs: [UUID] = []
    var lineage: [UUID]? = nil
    var activeConversationSegmentID: UUID? = nil
    enum CodingKeys: String, CodingKey { case schemaVersion, revision, profile, days, meals, weights, goals, workouts, coachTurns, activeDayID, previousDayConfirmedAt, deletedMealIDs, deletedWeightIDs, deletedWorkoutIDs, lineage, activeConversationSegmentID }
    init(schemaVersion: Int = 1, revision: Int = 0, profile: DiaryProfile, days: [TrackingDay] = [], meals: [DiaryMeal] = [], weights: [WeightEntry] = [], goals: [GoalRecord] = [], workouts: [WorkoutSession] = [], coachTurns: [CoachTurn] = [], activeDayID: UUID? = nil, previousDayConfirmedAt: Date? = nil, deletedMealIDs: [UUID] = [], deletedWeightIDs: [UUID] = [], deletedWorkoutIDs: [UUID] = [], lineage: [UUID]? = nil, activeConversationSegmentID: UUID? = nil) {
        self.schemaVersion = schemaVersion; self.revision = revision; self.profile = profile
        self.days = days; self.meals = meals; self.weights = weights; self.goals = goals; self.workouts = workouts; self.coachTurns = coachTurns
        self.activeDayID = activeDayID; self.previousDayConfirmedAt = previousDayConfirmedAt
        self.deletedMealIDs = deletedMealIDs; self.deletedWeightIDs = deletedWeightIDs
        self.deletedWorkoutIDs = deletedWorkoutIDs; self.lineage = lineage
        self.activeConversationSegmentID = activeConversationSegmentID
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        revision = try c.decode(Int.self, forKey: .revision)
        profile = try c.decode(DiaryProfile.self, forKey: .profile)
        days = try c.decode([TrackingDay].self, forKey: .days)
        meals = try c.decode([DiaryMeal].self, forKey: .meals)
        weights = try c.decode([WeightEntry].self, forKey: .weights)
        goals = try c.decodeIfPresent([GoalRecord].self, forKey: .goals) ?? []
        workouts = try c.decodeIfPresent([WorkoutSession].self, forKey: .workouts) ?? []
        coachTurns = try c.decodeIfPresent([CoachTurn].self, forKey: .coachTurns) ?? []
        activeDayID = try c.decodeIfPresent(UUID.self, forKey: .activeDayID)
        previousDayConfirmedAt = try c.decodeIfPresent(Date.self, forKey: .previousDayConfirmedAt)
        deletedMealIDs = try c.decode([UUID].self, forKey: .deletedMealIDs)
        deletedWeightIDs = try c.decodeIfPresent([UUID].self, forKey: .deletedWeightIDs) ?? []
        deletedWorkoutIDs = try c.decodeIfPresent([UUID].self, forKey: .deletedWorkoutIDs) ?? []
        lineage = try c.decodeIfPresent([UUID].self, forKey: .lineage)
        activeConversationSegmentID = try c.decodeIfPresent(UUID.self, forKey: .activeConversationSegmentID)
    }
    func goal(on localDate: String) -> GoalRecord? {
        goals.filter { $0.effectiveLocalDate <= localDate }.max { $0.effectiveLocalDate < $1.effectiveLocalDate }
    }
    func isVerifiedSuccessor(of prior: DiarySnapshot) -> Bool {
        guard let head = prior.lineage?.last, let lineage, lineage.last != head else { return false }
        return lineage.dropLast().contains(head)
    }
    var pendingCount: Int {
        meals.reduce(0) { count, meal in count + meal.submissions.filter { [.captured, .waitingForConnection, .analyzing, .needsRetry].contains($0.state) }.count }
        + coachTurns.filter { $0.pendingMealID == nil && [.captured, .analyzing, .waitingForConnection, .waitingForNetwork, .needsRetry, .needsClarification].contains($0.state) }.count
    }
    func totals(dayID: UUID) -> NutritionTotals {
        let items = meals.filter { $0.dayID == dayID && $0.isSaved }.flatMap(\.items)
        if items.isEmpty, days.contains(where: { $0.id == dayID && $0.completeness == .complete }),
           !meals.contains(where: { $0.dayID == dayID && $0.hasUnresolvedInput }) {
            return NutritionTotals(kcal: 0, carbs: 0, protein: 0, fat: 0, unknownItemCount: 0)
        }
        return nutritionTotals(items)
    }
    func validate() throws {
        try validateDiaryMetadataFields(schemaVersion: schemaVersion, revision: revision, profile: profile,
            lineage: lineage, previousDayConfirmedAt: previousDayConfirmedAt)
        try validateDiaryMetadataCollections(goals: goals, deletedWeightIDs: deletedWeightIDs, deletedWorkoutIDs: deletedWorkoutIDs)
        let linkedWeightDayIDs = weights.compactMap(\.dayID)
        guard days.count <= 10_000, meals.count <= 50_000, weights.count <= 10_000, workouts.count <= 50_000,
              deletedMealIDs.count <= 50_000,
              unique(days.map(\.id)), unique(meals.map(\.id)), unique(weights.map(\.id)), unique(linkedWeightDayIDs),
              unique(workouts.map(\.id)), unique(deletedMealIDs),
              activeDayID == nil || days.contains(where: { $0.id == activeDayID }),
              Set(meals.map(\.id)).isDisjoint(with: deletedMealIDs),
              Set(weights.map(\.id)).isDisjoint(with: deletedWeightIDs),
              Set(workouts.map(\.id)).isDisjoint(with: deletedWorkoutIDs) else { throw DiaryError.invalidData }
        var photoBytes = 0
        var submissionIDs = Set<UUID>()
        for day in days { try validateTrackingDayFields(day) }
        for meal in meals {
            guard days.contains(where: { $0.id == meal.dayID }), meal.photos.count <= 30, meal.submissions.count <= 1000,
                  unique(meal.photos.map(\.id)) else { throw DiaryError.invalidData }
            try validateMealFields(meal, itemCount: meal.items.count)
            try validateItems(meal.items)
            for photo in meal.photos {
                try validatePhotoFields(photo, byteCount: photo.data.count)
                photoBytes += photo.data.count
            }
            for submission in meal.submissions {
                guard submissionIDs.insert(submission.id).inserted,
                      submission.photoIDs.allSatisfy({ id in meal.photos.contains { $0.id == id } })
                else { throw DiaryError.invalidData }
                try validateMealSubmissionFields(submission, mealID: meal.id, mealRevision: meal.revision, profileID: profile.id)
                if let acceptance = submission.manualAcceptance {
                    let target = acceptance.target.day
                    guard days.contains(where: { $0.id == target.id && $0.localDate == target.localDate && $0.timeZoneID == target.timeZoneID }) else { throw DiaryError.invalidData }
                }
            }
        }
        guard coachTurns.count <= 10_000, unique(coachTurns.map(\.id)) else { throw DiaryError.invalidData }
        for turn in coachTurns {
            try validateCoachTurnFields(turn)
            guard turn.photos.count <= 30, unique(turn.photos.map(\.id)),
                  turn.activeDayID == nil || days.contains(where: { $0.id == turn.activeDayID }),
                  turn.resolvedDayID == nil || days.contains(where: { $0.id == turn.resolvedDayID }),
                  turn.photos.allSatisfy({ turn.photoIDs.contains($0.id) }) else { throw DiaryError.invalidData }
            for photo in turn.photos {
                try validatePhotoFields(photo, byteCount: photo.data.count)
                photoBytes += photo.data.count
            }
            for id in turn.photoIDs {
                guard turn.photos.contains(where: { $0.id == id }) || meals.contains(where: { meal in
                    (meal.id == turn.pendingMealID || turn.receipts.contains(where: { $0.mealID == meal.id })) && meal.photos.contains(where: { $0.id == id })
                }) else { throw DiaryError.invalidData }
            }
            for receipt in turn.receipts {
                try validateCoachReceiptFields(receipt, turnID: turn.id, revision: revision)
                guard receipt.dayID == nil || days.contains(where: { $0.id == receipt.dayID }) else { throw DiaryError.invalidData }
            }
        }
        guard photoBytes <= 250_000_000 else { throw DiaryError.invalidData }
        for weight in weights {
            try validateWeightFields(weight)
            guard weight.dayID == nil || days.contains(where: { $0.id == weight.dayID }) else { throw DiaryError.invalidData }
        }
        for workout in workouts {
            try validateWorkoutFields(workout)
            guard days.contains(where: { $0.id == workout.dayID }) else { throw DiaryError.invalidData }
        }
    }
}

func nutritionTotals(_ items: [FoodItem]) -> NutritionTotals {
    func sum(_ field: KeyPath<NutritionValues, Double?>) -> Double? {
        guard !items.isEmpty, items.allSatisfy({ $0.nutrition[keyPath: field] != nil }) else { return nil }
        return items.reduce(0) { $0 + $1.nutrition[keyPath: field]! }
    }
    return NutritionTotals(kcal: sum(\.kcal), carbs: sum(\.carbs), protein: sum(\.protein), fat: sum(\.fat),
        unknownItemCount: items.filter { [$0.nutrition.kcal, $0.nutrition.carbs, $0.nutrition.protein, $0.nutrition.fat].contains(nil) }.count)
}

private func unique(_ ids: [UUID]) -> Bool { Set(ids).count == ids.count }

func validLocalDate(_ value: String) -> Bool {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    return value.count == 10 && formatter.date(from: value).map { formatter.string(from: $0) == value } == true
}

func validateItems(_ items: [FoodItem]) throws {
    guard items.count <= 200, unique(items.map(\.id)) else { throw DiaryError.invalidData }
    for item in items {
        let values = [item.nutrition] + (item.nutritionBasis.map { [$0] } ?? [])
        guard Set(item.nutrientSources.keys).isSubset(of: ["kcal", "carbs", "protein", "fat"]),
              !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              item.name.count <= 500, item.quantity.isFinite, item.quantity >= 0, item.quantity <= 100_000,
              !item.unit.isEmpty, item.unit.count <= 100, item.reference.count <= 2000,
              values.allSatisfy({ value in
                  [value.kcal, value.carbs, value.protein, value.fat].allSatisfy {
                      $0 == nil || ($0!.isFinite && $0! >= 0 && $0! <= 10_000_000)
                  }
              }) else { throw DiaryError.invalidData }
    }
}

// Row rules are shared by complete interchange validation and bounded SQLite reads.
func validateDiaryMetadataFields(schemaVersion: Int, revision: Int, profile: DiaryProfile,
                                 lineage: [UUID]?, previousDayConfirmedAt: Date?) throws {
    guard schemaVersion == 1, revision >= 0, revision < 10_000_000,
          !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          profile.name.count <= 200, ["en", "he"].contains(profile.language),
          TimeZone(identifier: profile.timeZoneID) != nil, profile.preferences.count <= 10_000,
          profile.about.map(validAbout) ?? true,
          lineage == nil || (!lineage!.isEmpty && lineage!.count <= 256 && unique(lineage!)),
          previousDayConfirmedAt == nil || previousDayConfirmedAt!.timeIntervalSince1970.isFinite else { throw DiaryError.invalidData }
}

private func validAbout(_ about: ProfileAbout) -> Bool {
    (50...272).contains(about.heightCm) && (1900...2100).contains(about.birthYear)
        && about.dietTags.count <= 32 && about.dietTags.allSatisfy { !$0.isEmpty && $0.count <= 60 } && about.healthNotes.count <= 2_000
}

func validateDiaryMetadataCollections(goals: [GoalRecord], deletedWeightIDs: [UUID], deletedWorkoutIDs: [UUID]) throws {
    guard goals.count <= 10_000, unique(goals.map(\.id)),
          Set(goals.map(\.effectiveLocalDate)).count == goals.count,
          deletedWeightIDs.count <= 10_000, unique(deletedWeightIDs),
          deletedWorkoutIDs.count <= 50_000, unique(deletedWorkoutIDs) else { throw DiaryError.invalidData }
    for goal in goals { try validateGoalFields(goal) }
}

func validateTrackingDayFields(_ day: TrackingDay) throws {
    guard validLocalDate(day.localDate), TimeZone(identifier: day.timeZoneID) != nil,
          day.startAt.timeIntervalSince1970.isFinite,
          day.closedAt == nil || day.closedAt!.timeIntervalSince1970.isFinite else { throw DiaryError.invalidData }
}

func validateMealFields(_ meal: DiaryMeal, itemCount: Int) throws {
    guard meal.revision >= 0, meal.revision < 1_000_000, meal.revision == 0 || itemCount > 0,
          meal.capturedAt.timeIntervalSince1970.isFinite, meal.eatenAt.timeIntervalSince1970.isFinite else { throw DiaryError.invalidData }
}

func validateMealSubmissionFields(_ submission: MealSubmission, mealID: UUID, mealRevision: Int, profileID: UUID) throws {
    guard submission.baseRevision >= 0, submission.baseRevision <= mealRevision,
          submission.text.count <= 20_000, unique(submission.photoIDs),
          submission.state != .awaitingReview || submission.proposal != nil else { throw DiaryError.invalidData }
    if let proposal = submission.proposal {
        guard proposal.schemaVersion == 1, proposal.profileID == profileID, proposal.mealID == mealID,
              proposal.submissionID == submission.id, proposal.baseRevision == submission.baseRevision else { throw DiaryError.invalidData }
        try validateItems(proposal.items)
    }
    if let acceptance = submission.manualAcceptance {
        guard mealRevision > submission.baseRevision else { throw DiaryError.invalidData }
        try validateManualAcceptance(acceptance, submission: submission, mealID: mealID, profileID: profileID)
    }
}

func validatePhotoFields(_ photo: MealPhoto, byteCount: Int) throws {
    guard byteCount > 0, byteCount <= 10_000_000, photo.createdAt.timeIntervalSince1970.isFinite else { throw DiaryError.invalidData }
}

@discardableResult
func validateCoachTurnFields(_ turn: CoachTurn) throws -> TimeZone {
    guard turn.capturedAt.timeIntervalSince1970.isFinite, turn.text.count <= 20_000,
          let zone = TimeZone(identifier: turn.captureTimeZoneID),
          unique(turn.photoIDs), turn.photoIDs.count <= 30,
          turn.assistantText == nil || turn.assistantText!.utf8.count <= 65_536,
          turn.receipts.count <= 16, Set(turn.receipts.map(\.operationKey)).count == turn.receipts.count,
          turn.pendingMealRevision == nil || turn.pendingMealRevision! >= 0,
          turn.submissionManifest?.reply?.isValid != false,
          turn.failureReason == nil || turn.failureReason!.utf8.count <= 200 else { throw DiaryError.invalidData }
    return zone
}

func validateCoachReceiptFields(_ receipt: CoachReceipt, turnID: UUID, revision: Int) throws {
    if let fingerprint = receipt.commandFingerprint {
        guard fingerprint.utf8.count == 64, fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw DiaryError.invalidData }
    }
    guard receipt.turnID == turnID, receipt.operationKey.utf8.count <= 500, !receipt.operationKey.isEmpty,
          receipt.committedRevision > 0, receipt.committedRevision <= revision, receipt.resultJSON.utf8.count <= 65_536,
          receipt.dayID != nil || receipt.goalID != nil || receipt.destination != nil ||
            receipt.operationKey == "\(turnID.uuidString)/update_preferences" || receipt.operationKey.hasPrefix("\(turnID.uuidString)/update_preferences/"),
          let data = receipt.resultJSON.data(using: .utf8),
          (try? JSONSerialization.jsonObject(with: data)) != nil else { throw DiaryError.invalidData }
}

func validateWeightFields(_ weight: WeightEntry) throws {
    guard weight.value.isFinite, weight.value > 0, weight.value <= 1500, ["kg", "lb"].contains(weight.unit),
          weight.measuredAt.timeIntervalSince1970.isFinite, weight.revision > 0, weight.revision < 1_000_000 else { throw DiaryError.invalidData }
}

func validateGoalFields(_ goal: GoalRecord) throws {
    guard validLocalDate(goal.effectiveLocalDate), TimeZone(identifier: goal.timeZoneID) != nil,
          goal.revision > 0, goal.revision < 1_000_000,
          [goal.targets.kcal, goal.targets.carbs, goal.targets.protein, goal.targets.fat, goal.goalWeightKg]
            .allSatisfy({ $0 == nil || ($0!.isFinite && $0! > 0 && $0! <= 10_000_000) }) else { throw DiaryError.invalidData }
}

func validateWorkoutFields(_ workout: WorkoutSession) throws {
    guard workout.performedAt.timeIntervalSince1970.isFinite, workout.revision > 0, workout.revision < 1_000_000,
          (1...1440).contains(workout.durationMinutes), workout.exercises.count <= 100,
          workout.estimatedBurnKcal == nil || (workout.estimatedBurnKcal!.isFinite && workout.estimatedBurnKcal! >= 0 && workout.estimatedBurnKcal! <= 100_000),
          workout.burnSource == nil || workout.estimatedBurnKcal != nil else { throw DiaryError.invalidData }
    for exercise in workout.exercises {
        guard !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              exercise.name.count <= 200, exercise.sets.count <= 100 else { throw DiaryError.invalidData }
        for set in exercise.sets {
            guard (1...10_000).contains(set.repetitions),
                  set.loadKg == nil || (set.loadKg!.isFinite && set.loadKg! >= 0 && set.loadKg! <= 100_000) else { throw DiaryError.invalidData }
        }
    }
}
