import Testing
@testable import Mivu

struct PipLineTests {
    private func line(hour: Int = 12, mealsLogged: Bool = false, typing: Bool = false, connected: Bool = true,
                      processing: Bool = false, withPhotos: Bool = false, recovery: Bool = false,
                      error: String? = nil, turnState: CoachTurnState? = nil) -> PipLine? {
        PipLine.current(hour: hour, mealsLogged: mealsLogged, typing: typing, connected: connected, processing: processing,
                        withPhotos: withPhotos, recovery: recovery, error: error, turnState: turnState)
    }

    @Test func idleFollowsTheTimeOfDayUntilSomethingIsLogged() {
        #expect(line(hour: 8) == .say("Morning! What’s for breakfast?"))
        #expect(line(hour: 12) == .say("Ready for lunch?"))
        #expect(line(hour: 19) == .say("What’s for dinner?"))
        #expect(line(hour: 2) == .say("Anything to log?"))
        #expect(line(hour: 8, mealsLogged: true) == .say("Anything else to log?"))
    }

    @Test func typingHidesOnlyTheIdleLine() {
        #expect(line(typing: true) == nil)
        #expect(line(typing: true, processing: true) == .working("Counting that up…"))
        #expect(line(typing: true, connected: false) == .connect)
    }

    @Test func workingNamesTheInput() {
        #expect(line(processing: true, withPhotos: true) == .working("Looking at your photo…"))
        #expect(line(processing: true) == .working("Counting that up…"))
    }

    @Test func recoveryKeepsTheDetailAndOffersRetryOnlyWhenItApplies() {
        let detail = "Analysis could not finish. Your input is saved."
        #expect(line(recovery: true, error: detail, turnState: .needsRetry)
            == .problem("That one didn’t go through.", detail: detail, canRetry: true))
        #expect(line(recovery: true, turnState: .waitingForNetwork)
            == .problem("I’m offline. I’ll pick this up when you’re back.", detail: nil, canRetry: false))
        #expect(line(recovery: true, turnState: .needsClarification)
            == .problem("I need a bit more detail. My question is above.", detail: nil, canRetry: false))
        #expect(line(recovery: true, error: detail) == .problem("Something went wrong.", detail: detail, canRetry: false))
        #expect(line(recovery: true, turnState: .waitingForConnection) == .connect)
    }

    @Test func chipNamesTheLoggingDayAndIntake() {
        let today = coachDayChip(localDate: "2026-10-24", today: "2026-10-24", kcal: 1240, kcalPartial: false, mealsLogged: true, goal: 2000)
        #expect(today.text == "Today · 1,240 / 2,000 kcal")
        #expect(today.spoken == "Logging to today, 1,240 of 2,000 kcal")
        #expect(coachDayChip(localDate: "2026-10-23", today: "2026-10-24", kcal: 1240, kcalPartial: false, mealsLogged: true, goal: nil).text
            == "Yesterday · 1,240 kcal")
        #expect(coachDayChip(localDate: "2027-01-21", today: "2026-10-24", kcal: nil, kcalPartial: false, mealsLogged: false, goal: 2000).text
            == CoachReplyLines.dayLabel("2027-01-21", today: "2026-10-24") + " · 0 / 2,000 kcal", "Other days use the device's date style")
        #expect(coachDayChip(localDate: "2026-10-24", today: "2026-10-24", kcal: nil, kcalPartial: true, mealsLogged: true, goal: 2000).text
            == "Today · — / 2,000 kcal", "Unknown intake stays visible instead of reading as zero")
    }

    @Test func foodWithoutCaloriesMakesTheChipALowerBound() {
        let chip = coachDayChip(localDate: "2026-10-24", today: "2026-10-24", kcal: 400, kcalPartial: true, mealsLogged: true, goal: 2000)
        #expect(chip.text == "Today · 400+ / 2,000 kcal")
        #expect(chip.spoken == "Logging to today, at least 400 of 2,000 kcal")
    }
}
