import Foundation
import Testing
@testable import Mivu

struct QuickPromptsTests {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    private func meal(day: Int = 17, hour: Int, minute: Int = 0, items: [(String, Double, String)] = [("oats", 1, "bowl")],
                      kcal: Double? = 320, revision: Int = 1, id: UUID = UUID()) -> MealReadModel {
        let foods = items.enumerated().map { index, item in
            FoodItem(name: item.0, quantity: item.1, unit: item.2, nutrition: NutritionValues(kcal: index == 0 ? kcal : 0))
        }
        return MealReadModel(id: id, dayID: UUID(), capturedAt: at(day, hour, minute), eatenAt: at(day, hour, minute), revision: revision,
                             timePrecision: nil, items: foods, submissions: [], photos: [], sourceTurnID: nil)
    }
    private func committed(_ meal: MealReadModel) -> [CoachCommittedItem] {
        meal.items.map { CoachCommittedItem(itemID: $0.id, name: $0.name, quantity: $0.quantity, unit: $0.unit) }
    }
    private func recent(_ day: Int, _ meal: MealReadModel) -> RecentMeal { RecentMeal(localDate: "2026-11-\(day)", meal: meal) }
    private func input(hour: Int = 12, todaysMeals: [MealReadModel] = [], recent: [RecentMeal] = [], kcalTarget: Double? = 1600,
                       proteinEaten: Double? = nil, proteinTarget: Double? = nil, weighedToday: Bool = false,
                       morningCardShowing: Bool = false, latest: QuickPromptLatest? = nil, limit: Int = 4, wide: Bool = false,
                       hidden: Set<String> = []) -> QuickPromptInput {
        QuickPromptInput(hour: hour, today: "2026-11-17", yesterday: "2026-11-16", calendar: calendar, todaysMeals: todaysMeals,
                         recent: recent, kcalEaten: nil, kcalTarget: kcalTarget, proteinEaten: proteinEaten, proteinTarget: proteinTarget,
                         weighedToday: weighedToday, morningCardShowing: morningCardShowing, latest: latest, limit: limit, wide: wide, hidden: hidden)
    }

    @Test func morningWithYesterdaysBreakfastLeadsWithSameBreakfast() {
        let source = meal(day: 16, hour: 8, minute: 20)
        let chips = QuickPrompts.choose(input(hour: 8, recent: [recent(16, source)]))
        #expect(chips.map(\.id) == ["relog", "ask.yesterday", "log.slot", "log.weight"])
        #expect(chips.first?.title == "Same breakfast")
        #expect(chips.first?.kcal == 320)
        #expect(chips.first?.action == .relog(mealID: source.id, text: "For breakfast I had oats 1 bowl", excerpt: "Same breakfast · 320 kcal"))
    }

    @Test func frequentMealIsUsedWhenYesterdayHasNone() {
        let older = meal(day: 10, hour: 19, items: [("Rice", 1, "cup"), ("chicken", 150, "g")], kcal: 540)
        let newer = meal(day: 12, hour: 19, items: [("chicken ", 150, "g"), ("rice", 1, "cup")], kcal: 540)
        let other = meal(day: 14, hour: 19, items: [("pasta", 1, "bowl")], kcal: 600)
        let chips = QuickPrompts.choose(input(hour: 20, recent: [recent(14, other), recent(12, newer), recent(10, older)]))
        #expect(chips.first?.title == "Usual dinner")
        #expect(chips.first?.action == .relog(mealID: newer.id, text: "For dinner I had chicken 150 g, rice 1 cup", excerpt: "Usual dinner · 540 kcal"))
    }

    @Test func afterAMealLogTheFollowUpsLeadWithTheQuestion() {
        let lunch = meal(hour: 13, minute: 10)
        let chips = QuickPrompts.choose(input(hour: 13, todaysMeals: [lunch], latest: .meal(id: lunch.id, items: committed(lunch), localDate: "2026-11-17")))
        #expect(chips.map(\.id) == ["ask.calories", "fix.portion", "add.drink"])
        #expect(chips[1].action == .fill("Make lunch a smaller portion: "))
        #expect(chips[2].action == .fill("Add a drink to lunch: "))
    }

    @Test func followUpsNeedTodaysExchange() {
        let lunch = meal(hour: 13)
        let chips = QuickPrompts.choose(input(hour: 13, todaysMeals: [lunch], latest: .meal(id: lunch.id, items: committed(lunch), localDate: "2026-11-16")))
        #expect(!chips.map(\.id).contains("fix.portion"))
        #expect(chips.map(\.id).contains("log.snack"))
    }

    @Test func changedMealDropsItsFollowUps() {
        var lunch = meal(hour: 13)
        let receipt = committed(lunch)
        lunch.items[0].quantity = 2
        let chips = QuickPrompts.choose(input(hour: 13, todaysMeals: [lunch], latest: .meal(id: lunch.id, items: receipt, localDate: "2026-11-17")))
        #expect(!chips.map(\.id).contains("fix.portion"))
    }

    @Test func eveningShortOnProteinAsksForIdeas() {
        let ids = QuickPrompts.choose(input(hour: 20, proteinEaten: 40, proteinTarget: 100)).map(\.id)
        #expect(ids.contains("ask.protein"))
        #expect(!ids.contains("ask.calories"))
    }

    @Test func wideSwapsCaloriesForBalancedAndLimitKeepsASend() {
        let ids = QuickPrompts.choose(input(hour: 13, wide: true)).map(\.id)
        #expect(ids.contains("ask.balanced"))
        #expect(!ids.contains("ask.calories"))
        let source = meal(day: 16, hour: 8)
        let two = QuickPrompts.choose(input(hour: 8, recent: [recent(16, source)], limit: 2))
        #expect(two.count == 2)
        #expect(two.contains { $0.sends })
    }

    @Test func hiddenChipsAreSkippedBeforeTheLimit() {
        let source = meal(day: 16, hour: 8)
        let ids = QuickPrompts.choose(input(hour: 8, recent: [recent(16, source)], hidden: ["relog"])).map(\.id)
        #expect(ids == ["ask.yesterday", "log.slot", "log.weight"])
    }

    @Test func sendChipStaysInTheFirstTwo() {
        let source = meal(day: 16, hour: 13)
        let ids = QuickPrompts.choose(input(hour: 13, recent: [recent(16, source)], hidden: ["ask.calories"])).map(\.id)
        #expect(ids == ["relog", "log.slot", "log.weight"])
        let shown = QuickPrompts.choose(input(hour: 13, recent: [recent(16, source)])).map(\.id)
        #expect(shown == ["relog", "ask.calories", "log.slot", "log.weight"])
    }

    @Test func newUserWithoutTargetGetsLoggingChipsOnly() {
        let chips = QuickPrompts.choose(input(hour: 13, kcalTarget: nil))
        #expect(chips.map(\.id) == ["log.slot", "log.weight"])
        #expect(!chips.contains { $0.sends })
    }

    @Test func loggedSlotOffersASnack() {
        let ids = QuickPrompts.choose(input(hour: 13, todaysMeals: [meal(hour: 12)])).map(\.id)
        #expect(ids == ["ask.calories", "log.snack", "log.weight"])
    }

    @Test func weighInAndMorningCardHideTheWeightChip() {
        #expect(!QuickPrompts.choose(input(hour: 8, weighedToday: true)).map(\.id).contains("log.weight"))
        #expect(!QuickPrompts.choose(input(hour: 8, morningCardShowing: true)).map(\.id).contains("log.weight"))
    }

    @Test func weighInAndWorkoutFollowUps() {
        #expect(QuickPrompts.choose(input(hour: 8, weighedToday: true, latest: .weight(localDate: "2026-11-17"))).map(\.id).first == "ask.trend")
        #expect(QuickPrompts.choose(input(hour: 13, latest: .workout(localDate: "2026-11-17"))).map(\.id).first == "ask.calories")
    }

    @Test func dateOnlyMealsAreNotReloggedForASlot() {
        var source = meal(day: 16, hour: 0)
        source.timePrecision = .dateOnly
        #expect(!QuickPrompts.choose(input(hour: 8, recent: [recent(16, source)])).map(\.id).contains("relog"))
    }

    @Test func mealWithoutKnownCaloriesIsNotOffered() {
        let source = meal(day: 16, hour: 8, kcal: nil)
        #expect(!QuickPrompts.choose(input(hour: 8, recent: [recent(16, source)])).map(\.id).contains("relog"))
    }

    @Test func everyTitleFitsEighteenCharacters() {
        let lunch = meal(hour: 13)
        let cases = [
            input(hour: 8, recent: [recent(16, meal(day: 16, hour: 8))]), input(hour: 13), input(hour: 20, proteinEaten: 1, proteinTarget: 100),
            input(hour: 13, todaysMeals: [lunch], latest: .meal(id: lunch.id, items: committed(lunch), localDate: "2026-11-17")),
            input(hour: 13, wide: true), input(hour: 8, latest: .weight(localDate: "2026-11-17")), input(hour: 13, todaysMeals: [lunch]),
            input(hour: 20, recent: [recent(10, meal(day: 10, hour: 19)), recent(12, meal(day: 12, hour: 19))])
        ]
        for chip in cases.flatMap({ QuickPrompts.choose($0) }) { #expect(chip.title.count <= 18, "\(chip.title)") }
    }

    @Test func sendChipsAreTheApprovedQuestions() {
        let approved = ["How was yesterday?", "Calories left?", "Was it balanced?", "Protein ideas?", "Weekly trend?"]
        let lunch = meal(hour: 13)
        let cases = [input(hour: 8), input(hour: 13), input(hour: 20, proteinEaten: 1, proteinTarget: 100), input(hour: 13, wide: true),
                     input(hour: 8, latest: .weight(localDate: "2026-11-17")),
                     input(hour: 13, todaysMeals: [lunch], latest: .meal(id: lunch.id, items: committed(lunch), localDate: "2026-11-17"))]
        for chip in cases.flatMap({ QuickPrompts.choose($0) }) {
            if case .send(let text) = chip.action { #expect(approved.contains(text)) }
        }
    }
}
