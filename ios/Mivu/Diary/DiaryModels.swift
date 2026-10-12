import Foundation

struct DiaryProfile: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    var language = "en"
    var timeZoneID = "Asia/Jerusalem"
    var preferences = ""
}

enum DayCompleteness: String, Codable, CaseIterable, Sendable { case unknown, complete, partial, untracked }
enum PhotoRole: String, Codable, CaseIterable, Sendable { case unspecified, before, after }
enum NutritionProvenance: String, Codable, Sendable { case sample, user, confirmedLabel, identifiedSource, estimate }
enum SubmissionState: String, Codable, Sendable { case captured, waitingForConnection, analyzing, awaitingReview, saved, needsRetry, cancelled }
enum DayAssignment: Equatable, Sendable { case existing(UUID), newDay, ask(UUID) }

enum DiaryError: Error, Equatable, LocalizedError {
    case noProfile, wrongOwner, invalidData, persistenceFailed, staleRevision, notFound, emptyCapture, ambiguousDay, staleArchive
    var errorDescription: String? {
        switch self {
        case .noProfile: "Choose a local profile first."
        case .wrongOwner: "The profile changed. Please try again."
        case .invalidData: "This diary contains invalid or unsupported data."
        case .persistenceFailed: "The diary could not be saved. Your input is still available."
        case .staleRevision: "This meal changed. Please retry the correction."
        case .notFound: "This diary entry no longer exists."
        case .emptyCapture: "Add a photo or a meal description."
        case .ambiguousDay: "Choose the previous waking day or start a new day."
        case .staleArchive: "This backup is older than the diary or contains deleted meals."
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
}

struct MealSubmission: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var baseRevision: Int
    var text: String
    var photoIDs: [UUID]
    var reviewFirst: Bool
    var state: SubmissionState = .captured
    var proposal: AnalysisOutput? = nil
}

struct DiaryMeal: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var dayID: UUID
    var capturedAt: Date
    var eatenAt: Date
    var revision = 0
    var items: [FoodItem] = []
    var photos: [MealPhoto] = []
    var submissions: [MealSubmission] = []
    var totals: NutritionTotals { nutritionTotals(items) }
    var isSaved: Bool { revision > 0 }
    var state: SubmissionState { submissions.last?.state ?? .saved }
}

struct WeightEntry: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var dayID: UUID?
    var measuredAt: Date
    var value: Double
    var unit = "kg"
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
    var activeDayID: UUID? = nil
    var previousDayConfirmedAt: Date? = nil
    var deletedMealIDs: [UUID] = []
    var pendingCount: Int {
        meals.reduce(0) { count, meal in count + meal.submissions.filter { [.captured, .waitingForConnection, .analyzing, .needsRetry].contains($0.state) }.count }
    }
    func totals(dayID: UUID) -> NutritionTotals {
        let items = meals.filter { $0.dayID == dayID && $0.isSaved }.flatMap(\.items)
        if items.isEmpty, days.contains(where: { $0.id == dayID && $0.completeness == .complete }),
           !meals.contains(where: { $0.dayID == dayID && !$0.isSaved }) {
            return NutritionTotals(kcal: 0, carbs: 0, protein: 0, fat: 0, unknownItemCount: 0)
        }
        return nutritionTotals(items)
    }
    func validate() throws {
        guard schemaVersion == 1, revision >= 0, revision < 10_000_000, !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              profile.name.count <= 200, ["en", "he"].contains(profile.language),
              TimeZone(identifier: profile.timeZoneID) != nil, profile.preferences.count <= 10_000,
              days.count <= 10_000, meals.count <= 50_000, weights.count <= 10_000, deletedMealIDs.count <= 50_000,
              unique(days.map(\.id)), unique(meals.map(\.id)), unique(weights.map(\.id)), unique(deletedMealIDs),
              activeDayID == nil || days.contains(where: { $0.id == activeDayID }),
              previousDayConfirmedAt == nil || previousDayConfirmedAt!.timeIntervalSince1970.isFinite,
              Set(meals.map(\.id)).isDisjoint(with: deletedMealIDs) else { throw DiaryError.invalidData }
        var photoBytes = 0
        var submissionIDs = Set<UUID>()
        for day in days {
            guard validLocalDate(day.localDate), TimeZone(identifier: day.timeZoneID) != nil,
                  day.startAt.timeIntervalSince1970.isFinite else { throw DiaryError.invalidData }
        }
        for meal in meals {
            guard days.contains(where: { $0.id == meal.dayID }), meal.revision >= 0, meal.revision < 1_000_000,
                  meal.revision == 0 || !meal.items.isEmpty,
                  meal.capturedAt.timeIntervalSince1970.isFinite, meal.eatenAt.timeIntervalSince1970.isFinite,
                  meal.items.count <= 200, meal.photos.count <= 30, meal.submissions.count <= 1000,
                  unique(meal.photos.map(\.id)) else { throw DiaryError.invalidData }
            try validateItems(meal.items)
            for photo in meal.photos {
                guard !photo.data.isEmpty, photo.data.count <= 10_000_000,
                      photo.createdAt.timeIntervalSince1970.isFinite else { throw DiaryError.invalidData }
                photoBytes += photo.data.count
            }
            for submission in meal.submissions {
                guard submissionIDs.insert(submission.id).inserted, submission.baseRevision >= 0,
                      submission.baseRevision <= meal.revision, submission.text.count <= 20_000,
                      unique(submission.photoIDs), submission.photoIDs.allSatisfy({ id in meal.photos.contains { $0.id == id } })
                else { throw DiaryError.invalidData }
                if let proposal = submission.proposal {
                    guard proposal.schemaVersion == 1, proposal.profileID == profile.id, proposal.mealID == meal.id,
                          proposal.submissionID == submission.id, proposal.baseRevision == submission.baseRevision
                    else { throw DiaryError.invalidData }
                    try validateItems(proposal.items)
                }
                guard submission.state != .awaitingReview || submission.proposal != nil else { throw DiaryError.invalidData }
            }
        }
        guard photoBytes <= 250_000_000 else { throw DiaryError.invalidData }
        for weight in weights {
            guard weight.value.isFinite, weight.value > 0, weight.value <= 1500,
                  ["kg", "lb"].contains(weight.unit), weight.measuredAt.timeIntervalSince1970.isFinite,
                  weight.dayID == nil || days.contains(where: { $0.id == weight.dayID }) else { throw DiaryError.invalidData }
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

private func validLocalDate(_ value: String) -> Bool {
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
