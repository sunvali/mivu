import Foundation
import ActivityKit
import Testing
@testable import Mivu

@Suite struct DayProgressActivityTests {
    typealias State = DayProgressAttributes.ContentState

    /// A synthetic active day with one meal and an optional goal, reported the way Today reports it.
    private func state(eaten: NutritionValues?, also: [NutritionValues] = [], target: NutritionValues?, hide: Bool = true) throws -> State {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-21T05:00:00Z"))
        let day = TrackingDay(localDate: "2026-10-21", timeZoneID: "Asia/Jerusalem", startAt: start)
        let meals = eaten.map { [MealReadModel(id: UUID(), dayID: day.id, capturedAt: start, eatenAt: start, revision: 1, timePrecision: nil,
                                               items: ([$0] + also).map { FoodItem(name: "Synthetic bowl", nutrition: $0) },
                                               submissions: [], photos: [], sourceTurnID: nil)] } ?? []
        let goal = target.map { GoalRecord(effectiveLocalDate: "2026-10-01", timeZoneID: "Asia/Jerusalem", targets: $0,
                                           goalWeightKg: nil, exerciseCreditEnabled: false) }
        let head = DiaryHead(profile: DiaryProfile(name: "Synthetic island", timeZoneID: "Asia/Jerusalem"), revision: 1,
                             lineage: nil, activeDayID: day.id, previousDayConfirmedAt: nil, timelineGeneration: UUID())
        let model = DiaryReadModel(head: head, activeDay: day, meals: meals, weight: nil, workouts: [], activeGoal: goal,
                                   pendingAnalysisCount: 0)
        return State(readModel: model, hideWhenLocked: hide)
    }

    private let full = NutritionValues(kcal: 1360, carbs: 150, protein: 80, fat: 40)
    private let targets = NutritionValues(kcal: 2000, carbs: 200, protein: 120, fat: 60)

    @Test func underTarget() throws {
        let s = try state(eaten: full, target: targets)
        #expect(s.figure == "640" && s.word == "left" && s.compact == "640" && !s.isOver)
    }

    @Test func exactlyAtTarget() throws {
        let s = try state(eaten: NutritionValues(kcal: 2000, carbs: 0, protein: 0, fat: 0), target: targets)
        #expect(s.figure == "0" && s.word == "left" && !s.isOver)
    }

    @Test func overTarget() throws {
        let s = try state(eaten: NutritionValues(kcal: 2300, carbs: 0, protein: 0, fat: 0), target: targets)
        #expect(s.figure == "300" && s.word == "over" && s.compact == "300 over" && s.isOver)
    }

    @Test func noKcalTarget() throws {
        let s = try state(eaten: full, target: nil)
        #expect(s.figure == "1,360" && s.word == "eaten" && s.compact == "1,360" && s.kcalTarget == nil)
    }

    @Test func macroLabelsAndFractions() {
        #expect(State.macroLabel("P", 80, 120) == "P 80/120g")
        #expect(State.macroLabel("P", 80, nil) == "P 80g")
        #expect(abs((State.fraction(80, 120) ?? 0) - 0.667) < 0.001)
        #expect(State.fraction(150, 120) == 1)
        #expect(State.fraction(80, nil) == nil)
    }

    @Test func noSavedMealShowsDash() throws {
        let s = try state(eaten: nil, target: targets)
        #expect(s.kcalEaten == nil && s.figure == "–" && s.compact == "–" && !s.isOver)
    }

    @Test func spokenLabel() throws {
        let s = try state(eaten: full, target: targets)
        #expect(s.spoken == "640 calories left. Protein 80 of 120 grams. Carbs 150 of 200 grams. Fat 40 of 60 grams.")
    }

    @Test func hideFlagPassesThrough() throws {
        #expect(try state(eaten: full, target: targets, hide: false).hideWhenLocked == false)
        #expect(try state(eaten: full, target: targets).hideWhenLocked)
    }

    @Test func disabledEndsAll() { #expect(DayProgressSync.decide(enabled: false, authorized: true, hasDiary: true, running: 1) == .endAll) }
    @Test func unauthorizedEndsAll() { #expect(DayProgressSync.decide(enabled: true, authorized: false, hasDiary: true, running: 1) == .endAll) }
    @Test func noDiaryEndsAll() { #expect(DayProgressSync.decide(enabled: true, authorized: true, hasDiary: false, running: 1) == .endAll) }
    @Test func noneRunningStarts() { #expect(DayProgressSync.decide(enabled: true, authorized: true, hasDiary: true, running: 0) == .start) }
    @Test func oneRunningUpdates() { #expect(DayProgressSync.decide(enabled: true, authorized: true, hasDiary: true, running: 1) == .update(endingExtra: 0)) }
    @Test func extrasEnd() { #expect(DayProgressSync.decide(enabled: true, authorized: true, hasDiary: true, running: 3) == .update(endingExtra: 2)) }

    @Test func unknownMacroIsNeverZero() {
        #expect(State.macroLabel("P", nil, 120) == "P –/120g")
        #expect(State.macroLabel("P", nil, nil) == "P –")
        #expect(State.fraction(nil, 120) == nil)
    }

    @Test func unknownCaloriesNeverShowAFullTarget() throws {
        // One saved item without calories makes the day's total unknown; "2,000 left" would overstate it.
        let s = try state(eaten: NutritionValues(carbs: 10, protein: 5, fat: 2), target: targets)
        #expect(s.kcalEaten == nil && s.figure == "–" && s.spoken.hasPrefix("Calories not known yet."))
    }

    @Test func calorieOnlyFoodKeepsKnownMacrosMarkedPartial() throws {
        // A "200 kcal extra" entry has no macros; the rest of the day's protein must still show, as a lower bound.
        let s = try state(eaten: full, also: [NutritionValues(kcal: 200)], target: targets)
        #expect(s.kcalEaten == 1560 && s.protein == 80 && s.carbs == 150 && s.fat == 40 && s.macrosPartial == true)
        #expect(State.macroAmount(s.protein, s.proteinTarget, partial: true) == "80+/120g")
        #expect(s.spoken == "440 calories left. Protein at least 80 of 120 grams. Carbs at least 150 of 200 grams. Fat at least 40 of 60 grams.")
        #expect(try state(eaten: full, target: targets).macrosPartial != true)
    }

    @Test func onlyActiveOrStaleActivitiesCountAsRunning() {
        #expect(DayProgressSync.isLive(.active) && DayProgressSync.isLive(.stale))
        #expect(!DayProgressSync.isLive(.ended) && !DayProgressSync.isLive(.dismissed))
    }
}
