import Foundation
import Testing
@testable import Mivu

/// English output that sentence-building code must keep after it moved to whole translatable strings.
struct LanguageTextTests {
    @Test func removeWholeMealQuestionIsOneSentence() {
        #expect(CoachEngine.removeMealQuestion(names: "Rice, Beans") == "Remove the whole Rice, Beans meal?")
        #expect(CoachEngine.removeMealQuestion(names: "") == "Remove the whole meal?")
    }

    @Test func dayChipKeepsItsEnglishShape() {
        let partial = coachDayChip(localDate: "2026-10-19", today: "2026-10-19", kcal: 1240, kcalPartial: true, mealsLogged: true, goal: 2000)
        #expect(partial.text == "Today · 1,240+ / 2,000 kcal")
        #expect(partial.spoken == "Logging to today, at least 1,240 of 2,000 kcal")
        let open = coachDayChip(localDate: "2026-10-18", today: "2026-10-19", kcal: nil, kcalPartial: false, mealsLogged: true, goal: nil)
        #expect(open.text == "Yesterday · — kcal")
        #expect(open.spoken == "Logging to yesterday, unknown kcal")
    }
}
