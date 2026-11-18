import Foundation

/// A saved meal from an earlier day, with the day it was logged to.
struct RecentMeal: Equatable, Sendable {
    var localDate: String
    var meal: MealReadModel
}

enum MealSlot: String, Sendable {
    case breakfast, lunch, dinner

    static func at(hour: Int) -> MealSlot { hour < 11 ? .breakfast : hour < 16 ? .lunch : .dinner }

    // Whole phrases per slot rather than a slot word inside a sentence, so translations keep their grammar.
    var logTitle: String {
        switch self { case .breakfast: String(localized: "Log breakfast…"); case .lunch: String(localized: "Log lunch…"); case .dinner: String(localized: "Log dinner…") }
    }
    var fill: String {
        switch self { case .breakfast: String(localized: "For breakfast I had "); case .lunch: String(localized: "For lunch I had "); case .dinner: String(localized: "For dinner I had ") }
    }
    func fill(_ foods: String) -> String {
        switch self {
        case .breakfast: String(localized: "For breakfast I had \(foods)")
        case .lunch: String(localized: "For lunch I had \(foods)")
        case .dinner: String(localized: "For dinner I had \(foods)")
        }
    }
    var sameTitle: String {
        switch self { case .breakfast: String(localized: "Same breakfast"); case .lunch: String(localized: "Same lunch"); case .dinner: String(localized: "Same dinner") }
    }
    var usualTitle: String {
        switch self { case .breakfast: String(localized: "Usual breakfast"); case .lunch: String(localized: "Usual lunch"); case .dinner: String(localized: "Usual dinner") }
    }
    var smallerPortion: String {
        switch self {
        case .breakfast: String(localized: "Make breakfast a smaller portion: ")
        case .lunch: String(localized: "Make lunch a smaller portion: ")
        case .dinner: String(localized: "Make dinner a smaller portion: ")
        }
    }
    var addDrink: String {
        switch self {
        case .breakfast: String(localized: "Add a drink to breakfast: ")
        case .lunch: String(localized: "Add a drink to lunch: ")
        case .dinner: String(localized: "Add a drink to dinner: ")
        }
    }
}

/// One chip in the Coach composer's quick-prompt row.
struct QuickPrompt: Equatable, Identifiable, Sendable {
    enum Action: Equatable, Sendable {
        /// A read-only question, sent as is.
        case send(String)
        /// Text for the person to finish and send.
        case fill(String)
        /// Fills the box with a saved meal and quotes it, so Coach can copy it exactly.
        case relog(mealID: UUID, text: String, excerpt: String)
    }
    var id: String
    var title: String
    var symbol: String?
    var kcal: Int? = nil
    var photo: DiaryPhotoReference? = nil
    var action: Action
    var sends: Bool { if case .send = action { true } else { false } }
}

/// What Coach replied last, when it is recent enough to suggest a next step.
enum QuickPromptLatest: Equatable, Sendable {
    /// The meal as the receipt committed it; edited since, its follow-ups no longer apply.
    case meal(id: UUID, items: [CoachCommittedItem], localDate: String)
    case weight(localDate: String)
    case workout(localDate: String)
}

struct QuickPromptInput: Sendable {
    var hour: Int
    var today: String
    var yesterday: String
    var calendar: Calendar
    var todaysMeals: [MealReadModel]
    /// Saved meals from yesterday back 14 days, newest first.
    var recent: [RecentMeal]
    var kcalEaten: Double?
    var kcalTarget: Double?
    var proteinEaten: Double?
    var proteinTarget: Double?
    var weighedToday: Bool
    var morningCardShowing: Bool
    var latest: QuickPromptLatest?
    var limit: Int
    var wide: Bool
    var hidden: Set<String>
}

/// Rule-based chips for the moment. Pure, so every rule is pinned by tests rather than by the view.
enum QuickPrompts {
    static func choose(_ input: QuickPromptInput) -> [QuickPrompt] {
        var chips: [QuickPrompt] = []
        switch input.latest {
        case .meal(let id, let committed, let date) where date == input.today:
            if let meal = input.todaysMeals.first(where: { $0.id == id }),
               meal.items.map({ [$0.id.uuidString, "\($0.quantity)", $0.unit] }) == committed.map({ [$0.itemID.uuidString, "\($0.quantity)", $0.unit] }) {
                let slot = MealSlot.at(hour: input.calendar.component(.hour, from: meal.eatenAt))
                chips = [calories(input),
                         QuickPrompt(id: "fix.portion", title: String(localized: "Smaller portion…"), symbol: "minus.circle",
                                     action: .fill(slot.smallerPortion)),
                         QuickPrompt(id: "add.drink", title: String(localized: "Add a drink…"), symbol: "cup.and.saucer",
                                     action: .fill(slot.addDrink))]
            } else { chips = slotChips(input) }
        case .weight(let date) where date == input.today:
            chips = [QuickPrompt(id: "ask.trend", title: String(localized: "Weekly trend?"), symbol: "chart.line.uptrend.xyaxis",
                                 action: .send(String(localized: "Weekly trend?")))] + slotChips(input)
        case .workout(let date) where date == input.today:
            chips = [calories(input)] + slotChips(input)
        default:
            chips = slotChips(input)
        }
        var seen = Set<String>()
        chips = chips.filter { !input.hidden.contains($0.id) && seen.insert($0.id).inserted }
        if !chips.prefix(2).contains(where: \.sends), let index = chips.firstIndex(where: \.sends) {
            chips.insert(chips.remove(at: index), at: 1)
        }
        return Array(chips.prefix(input.limit))
    }

    private static func slotChips(_ input: QuickPromptInput) -> [QuickPrompt] {
        let slot = MealSlot.at(hour: input.hour)
        let logged = input.todaysMeals.contains { MealSlot.at(hour: input.calendar.component(.hour, from: $0.eatenAt)) == slot }
        var chips: [QuickPrompt] = []
        if !logged, let relog = relog(input, slot: slot) { chips.append(relog) }
        if let question = question(input) { chips.append(question) }
        chips.append(logged
            ? QuickPrompt(id: "log.snack", title: String(localized: "Log a snack…"), symbol: "fork.knife", action: .fill(String(localized: "For a snack I had ")))
            : QuickPrompt(id: "log.slot", title: slot.logTitle, symbol: "fork.knife", action: .fill(slot.fill)))
        if !input.weighedToday && !input.morningCardShowing {
            chips.append(QuickPrompt(id: "log.weight", title: String(localized: "Log weight…"), symbol: "scalemass",
                                     action: .fill(String(localized: "My weight this morning is "))))
        }
        return chips
    }

    private static func question(_ input: QuickPromptInput) -> QuickPrompt? {
        if input.hour < 11 {
            return QuickPrompt(id: "ask.yesterday", title: String(localized: "How was yesterday?"), symbol: "chart.bar.fill",
                               action: .send(String(localized: "How was yesterday?")))
        }
        if input.hour >= 16, let target = input.proteinTarget, target > 0, (input.proteinEaten ?? 0) < target * 0.7 {
            return QuickPrompt(id: "ask.protein", title: String(localized: "Protein ideas?"), symbol: "leaf.fill",
                               action: .send(String(localized: "Protein ideas?")))
        }
        return input.kcalTarget == nil ? nil : calories(input)
    }

    private static func calories(_ input: QuickPromptInput) -> QuickPrompt {
        // Beside the live day the number is already on screen, so ask something it doesn't show.
        input.wide
            ? QuickPrompt(id: "ask.balanced", title: String(localized: "Was it balanced?"), symbol: "leaf.fill", action: .send(String(localized: "Was it balanced?")))
            : QuickPrompt(id: "ask.calories", title: String(localized: "Calories left?"), symbol: "chart.bar.fill", action: .send(String(localized: "Calories left?")))
    }

    private static func relog(_ input: QuickPromptInput, slot: MealSlot) -> QuickPrompt? {
        let candidates = input.recent.filter {
            // A date-only meal sits at the day's start, so its hour says nothing about the slot.
            $0.meal.isSaved && !$0.meal.items.isEmpty && $0.meal.timePrecision != .dateOnly && MealSlot.at(hour: input.calendar.component(.hour, from: $0.meal.eatenAt)) == slot
        }
        let title: String, source: MealReadModel
        if let yesterday = candidates.first(where: { $0.localDate == input.yesterday }) {
            title = slot.sameTitle; source = yesterday.meal
        } else {
            // Candidates are newest first, so on a tie the group seen first is the most recent; its first meal is its newest.
            var groups: [String: [MealReadModel]] = [:], order: [String] = []
            for meal in candidates.map(\.meal) {
                let key = foodsKey(meal)
                if groups[key] == nil { order.append(key) }
                groups[key, default: []].append(meal)
            }
            var best: [MealReadModel] = []
            for key in order where groups[key]!.count > best.count { best = groups[key]! }
            guard best.count >= 2 else { return nil }
            title = slot.usualTitle; source = best[0]
        }
        // The chip shows the meal's kcal, so every food must know its calories.
        guard source.items.allSatisfy({ $0.nutrition.kcal != nil }), let kcal = source.totals.kcal else { return nil }
        let foods = source.items.map { item in
            "\(item.name.trimmingCharacters(in: .whitespacesAndNewlines)) \(item.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(item.shownUnit)"
        }.joined(separator: ", ")
        let kcalValue = Int(kcal.rounded())
        return QuickPrompt(id: "relog", title: title, symbol: nil, kcal: kcalValue, photo: source.photos.first,
                           action: .relog(mealID: source.id, text: slot.fill(foods),
                                          excerpt: String(localized: "\(title) · \(kcalValue) kcal")))
    }

    private static func foodsKey(_ meal: MealReadModel) -> String {
        meal.items.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.sorted().joined(separator: "|")
    }
}
