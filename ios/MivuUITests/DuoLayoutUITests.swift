import XCTest

/// iPhone Duo sideways layouts. `--wide-layout-ui-test` makes the root report a wide window,
/// so these run on any simulator; real poses are checked on the Duo simulator.
@MainActor final class DuoLayoutUITests: XCTestCase {
    private func launch(wide: Bool, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-navigation-start-today",
                               "--diary-history-fixture", "--proof-english"] + (wide ? ["--wide-layout-ui-test"] : []) + extra
        app.launch()
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 15))
        return app
    }

    func testSidewaysTodaySplitsSummaryAndMeals() throws {
        let app = launch(wide: true)
        try XCTSkipIf(app.windows.firstMatch.frame.width < 760, "Needs the sideways inner display: the closed Duo is too short to show Weight")
        let summary = app.descendants(matching: .any)["todaySummaryColumn"]
        let meals = app.descendants(matching: .any)["todayMealsColumn"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(meals.exists)
        XCTAssertLessThanOrEqual(summary.frame.maxX, meals.frame.minX + 1)
        XCTAssertTrue(app.buttons["logWeight"].exists, "Weight stays in the summary column")
        for id in ["snapIt", "logMeal", "addManually"] {
            let action = app.buttons[id]
            XCTAssertTrue(action.isHittable, "\(id) is reachable without scrolling")
            XCTAssertGreaterThanOrEqual(action.frame.minX, meals.frame.minX - 1)
            XCTAssertLessThanOrEqual(action.frame.maxX, meals.frame.maxX + 1)
        }
        XCTAssertGreaterThan(summary.frame.maxY, app.buttons["logMeal"].frame.maxY,
                             "The summary scrolls alongside the capture actions")
        assertCaptureActionsShareARow(app)
    }

    /// Stacked, the three actions took about a quarter of an iPhone and most of the closed Duo.
    func testUprightCaptureActionsShareARow() {
        assertCaptureActionsShareARow(launch(wide: false))
    }

    private func assertCaptureActionsShareARow(_ app: XCUIApplication, line: UInt = #line) {
        let snap = app.buttons["snapIt"].frame, chat = app.buttons["logMeal"].frame
        XCTAssertEqual(snap.midY, chat.midY, accuracy: 1, "Snap It and Chat with Pip sit side by side", line: line)
        XCTAssertLessThanOrEqual(snap.maxX, chat.minX + 1, line: line)
        XCTAssertGreaterThanOrEqual(app.buttons["addManually"].frame.minY, chat.maxY - 1, "Add manually stays a link underneath", line: line)
    }

    func testUprightTodayStaysOneColumn() throws {
        let app = launch(wide: false)
        // XCUITest can't rotate the Duo's inner display; the open pose is wider than tall, so check upright windows only.
        let window = app.windows.firstMatch.frame
        try XCTSkipIf(window.width > window.height, "Needs an upright window: run Closed, or rotate the open Duo upright")
        XCTAssertFalse(app.descendants(matching: .any)["todayMealsColumn"].exists)
        // The list loads rows as they scroll in, and the outer display is short.
        for _ in 0..<4 where !app.buttons["logWeight"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["logWeight"].exists)
    }

    func testUprightKeyboardKeepsOneColumn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--proof-english"]
        app.launch()
        let window = app.windows.firstMatch.frame
        try XCTSkipIf(window.width > window.height, "Needs an upright window: rotate the open Duo upright")
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 15)); input.tap()
        try XCTSkipUnless(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Needs the software keyboard")
        XCTAssertFalse(app.descendants(matching: .any)["coachSidePane"].waitForExistence(timeout: 3),
                       "The keyboard shortens the view, but the window is still upright")
    }

    /// Closed and sideways with the keyboard up, the empty conversation is only a few lines tall.
    func testShortCoachEmptyStateStaysInItsSpace() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--proof-english"]
        app.launch()
        // Upright there is room, so hiding it must be about space, never a blanket hide.
        XCTAssertTrue(app.staticTexts["What would you like to record?"].waitForExistence(timeout: 15), "A tall window shows the empty state")
        XCUIDevice.shared.orientation = .landscapeLeft
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 15)); input.tap()
        try XCTSkipUnless(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Needs the software keyboard")
        let strip = app.descendants(matching: .any)["coachCompanionStrip"]
        XCTAssertTrue(strip.exists, "Pip's strip is on screen")
        let top = app.navigationBars["Coach"].frame.maxY, bottom = strip.frame.minY
        for text in ["What would you like to record?", "Describe a meal"] {
            let element = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
            guard element.exists else { continue }
            XCTAssertGreaterThanOrEqual(element.frame.minY, top, "\(text) runs under the bar")
            XCTAssertLessThanOrEqual(element.frame.maxY, bottom, "\(text) runs under Pip")
        }
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "short-coach-empty"; capture.lifetime = .keepAlways; add(capture)
        XCUIDevice.shared.orientation = .portrait
    }

    func testSidewaysCoachShowsLiveDayAndHighlightsChange() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture",
                               "--proof-english", "--wide-layout-ui-test"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        let liveDay = app.descendants(matching: .any)["coachSidePane"]
        XCTAssertTrue(liveDay.waitForExistence(timeout: 5))
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Two eggs, three bread slices and salad")
        app.buttons["coachSend"].tap()
        let changed = app.descendants(matching: .any)["justChangedMeal"]
        XCTAssertTrue(changed.waitForExistence(timeout: 20), "The meal Coach logged lights up in the live day")
        XCTAssertLessThan(changed.frame.maxX, input.frame.minX + 1, "The live day sits left of the chat")
        XCTAssertLessThan(changed.frame.minY, liveDay.frame.midY, "The changed meal shows near the top, above the keyboard")
    }

    func testQuickPromptsShowTwoChipsSidewaysAndSkipCaloriesBesideTheDay() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english",
                               "--wide-layout-ui-test", "--quick-prompts-fixture", "--quick-prompts-hour", "13"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["coachQuickPrompt-relog"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["coachQuickPrompt-ask.calories"].exists, "Beside the live day the number is already on screen")
        XCTAssertLessThanOrEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coachQuickPrompt-")).count, 2)
    }

    /// Coach with scripted replies. Sideways the pane sits left of the chat.
    private func launchCoach(wide: Bool = true) throws -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english"]
            + (wide ? ["--wide-layout-ui-test"] : [])
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        let window = app.windows.firstMatch.frame
        if wide { try XCTSkipIf(window.width < 760, "Needs the sideways inner display") }
        else { try XCTSkipIf(window.width > window.height, "Needs an upright window: run Closed, or rotate the open Duo upright") }
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        return (app, input)
    }
    private func send(_ text: String, _ app: XCUIApplication, _ input: XCUIElement) {
        input.tap(); input.typeText(text); app.buttons["coachSend"].tap()
    }
    private func pane(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["coachSidePane"] }

    func testSidewaysChatSitsRightOfThePane() throws {
        let (app, input) = try launchCoach()
        XCTAssertTrue(pane(app).waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(pane(app).frame.maxX, input.frame.minX + 1, "The pane is on the left, the chat on the right")
    }

    func testSidewaysTapOpensMealBesideChat() throws {
        let (app, input) = try launchCoach()
        send("Two eggs, three bread slices and salad", app, input)
        let link = app.buttons["coachMealLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 20)); link.tap()
        let meal = app.navigationBars["Meal"]
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(meal.frame.maxX, input.frame.minX + 1, "The meal opens in the pane, not over the chat")
        XCTAssertTrue(input.isHittable, "The composer stays usable beside the meal")
        meal.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5), "Back returns the pane to Today")
        XCTAssertFalse(meal.exists)
    }

    func testSidewaysProgressQuestionAddsNoFollowUp() throws {
        let (app, input) = try launchCoach()
        send("Show my weekly report", app, input)
        XCTAssertTrue(app.descendants(matching: .any)["coachReply"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["coachFollowUp-progress"].exists, "Quick prompts replace See progress")
    }

    func testSidewaysWeightChangeMovesPaneToProgress() throws {
        let (app, input) = try launchCoach()
        send("This morning I weighed 70 kg", app, input)
        let progress = app.navigationBars["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 20), "A weight Coach saved shows where it landed")
        XCTAssertLessThanOrEqual(progress.frame.maxX, input.frame.minX + 1)
    }

    func testSidewaysChangeOnAnotherDayShowsThatDay() throws {
        let (app, input) = try launchCoach()
        send("Yesterday I had dessert", app, input)
        let diary = app.navigationBars["Diary"]
        XCTAssertTrue(diary.waitForExistence(timeout: 20), "A meal Coach saved on another day shows that day")
        XCTAssertLessThanOrEqual(diary.frame.maxX, input.frame.minX + 1)
    }

    func testSidewaysTapOpensAnotherDaysMealBesideChat() throws {
        let (app, input) = try launchCoach()
        send("Yesterday I had dessert", app, input)
        XCTAssertTrue(app.navigationBars["Diary"].waitForExistence(timeout: 20))
        app.buttons["coachMealLink"].tap()
        let meal = app.navigationBars["Meal"]
        XCTAssertTrue(meal.waitForExistence(timeout: 5), "Yesterday's meal opens from its card while the pane shows that day")
        XCTAssertLessThanOrEqual(meal.frame.maxX, input.frame.minX + 1)
        XCTAssertTrue(app.buttons["deleteMeal"].exists || app.buttons["Meal actions"].exists, "The full meal loaded, not a placeholder")
    }

    func testExpandedChatOpensAnotherDaysMealOverTheChat() throws {
        let (app, input) = try launchCoach()
        send("Yesterday I had dessert", app, input)
        XCTAssertTrue(app.navigationBars["Diary"].waitForExistence(timeout: 20))
        app.buttons["coachExpand"].tap()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5), "Expanding shows the chat, not what the pane held")
        XCTAssertFalse(app.navigationBars["Diary"].exists)
        app.buttons["coachMealLink"].tap()
        XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5), "A card opens its meal over the expanded chat")
    }

    func testExpandedChatStaysUncoveredWhenCoachSaves() throws {
        let (app, input) = try launchCoach()
        app.buttons["coachExpand"].firstMatch.tap()
        send("Yesterday I had dessert", app, input)
        XCTAssertTrue(app.buttons["coachMealLink"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.navigationBars["Diary"].waitForExistence(timeout: 2), "The slid-away pane does not push the changed day over the chat")
        XCTAssertTrue(input.exists)
    }

    func testDeletingPaneMealReturnsToToday() throws {
        let (app, input) = try launchCoach()
        send("Two eggs, three bread slices and salad", app, input)
        let link = app.buttons["coachMealLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 20)); link.tap()
        XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5))
        app.buttons["Meal actions"].tap()
        app.buttons["deleteMeal"].tap()
        app.alerts.buttons["Delete meal"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10), "A deleted meal leaves the pane on Today")
        XCTAssertFalse(app.navigationBars["Meal"].exists)
    }

    func testUndoingPaneMealReturnsToToday() throws {
        let (app, input) = try launchCoach()
        send("Two eggs, three bread slices and salad", app, input)
        let link = app.buttons["coachMealLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 20)); link.tap()
        XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5))
        app.buttons["coachUndo"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10), "An undone meal leaves the pane on Today, not an empty detail")
        XCTAssertFalse(app.navigationBars["Meal"].exists)
    }

    func testSidewaysChatExpandsAndCollapses() throws {
        let (app, input) = try launchCoach()
        XCTAssertTrue(pane(app).waitForExistence(timeout: 5))
        input.tap(); input.typeText("draft text")
        let besideWidth = input.frame.width
        let expand = app.buttons["coachExpand"].firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 5)); expand.tap()
        // Expanded, the chat takes the screen and the side pane slides off it (kept mounted); Today keeps its own tab.
        let window = app.windows.firstMatch.frame
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.pane(app).frame.maxX <= window.minX + 1 }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "The side pane leaves")
        XCTAssertGreaterThan(input.frame.width, besideWidth + 100, "The chat is wider than its half")
        XCTAssertLessThan(input.frame.minX, app.windows.firstMatch.frame.midX, "The chat reaches into the left half")
        XCTAssertEqual(input.value as? String, "draft text", "The draft survives expanding")
        app.buttons["coachExpand"].firstMatch.tap()
        let back = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.pane(app).frame.minX >= window.minX - 1 }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [back], timeout: 5), .completed, "Collapsed, the side pane is back")
        XCTAssertLessThanOrEqual(pane(app).frame.maxX, input.frame.minX + 1)
        XCTAssertEqual(input.value as? String, "draft text", "The draft survives collapsing")
        // The pane coming back must not empty the system's toolbar strip.
        XCTAssertTrue(app.buttons["coachHistory"].firstMatch.waitForExistence(timeout: 5), "Chat history is still in reach")
        XCTAssertTrue(app.buttons["coachExpand"].firstMatch.exists, "The chat can expand again")
    }

    func testUprightTapStillPushesOverChat() throws {
        let (app, input) = try launchCoach(wide: false)
        send("Two eggs, three bread slices and salad", app, input)
        let link = app.buttons["coachMealLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 20)); link.tap()
        XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5))
        XCTAssertFalse(pane(app).exists, "Upright has no side pane")
        XCTAssertFalse(input.exists, "Upright the meal covers the chat, as before")
    }

    func testSidewaysDiarySplitsSummaryAndRecords() throws {
        let app = launch(wide: true)
        try XCTSkipIf(app.windows.firstMatch.frame.width < 760, "Needs the sideways inner display")
        app.buttons["Diary"].firstMatch.tap()
        let summary = app.descendants(matching: .any)["diarySummaryColumn"]
        let records = app.descendants(matching: .any)["diaryRecordsColumn"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(records.exists)
        XCTAssertLessThanOrEqual(summary.frame.maxX, records.frame.minX + 1)
        XCTAssertLessThan(app.descendants(matching: .any)["diaryWeekStrip"].frame.midX, records.frame.minX, "The week strip stays with the day's summary")
        let meal = app.descendants(matching: .any)["historyMeal"].firstMatch
        XCTAssertTrue(meal.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(meal.frame.minX, records.frame.minX - 1, "Meals sit in the second column")
    }

    func testUprightDiaryStaysOneColumn() throws {
        let app = launch(wide: false)
        let window = app.windows.firstMatch.frame
        try XCTSkipIf(window.width > window.height, "Needs an upright window: run Closed, or rotate the open Duo upright")
        app.buttons["Diary"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["diaryWeekStrip"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["diaryRecordsColumn"].exists)
    }

    func testSidewaysProgressUsesTwoColumns() {
        let app = launch(wide: true)
        app.buttons["Progress"].firstMatch.tap()
        let primary = app.descendants(matching: .any)["progressPrimaryColumn"]
        let secondary = app.descendants(matching: .any)["progressSecondaryColumn"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        XCTAssertTrue(secondary.exists)
        XCTAssertLessThanOrEqual(primary.frame.maxX, secondary.frame.minX + 1)
        XCTAssertLessThanOrEqual(app.buttons["openWeight"].frame.maxX, primary.frame.maxX + 1, "Weight balances the left column")
    }

    // Propped half-open on a table: content stays on the standing half, controls move to the flat half.
    private func launchTable(_ extra: [String]) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--proof-english",
                               "--duo-posture-ui-test", "table"] + extra
        app.launch()
        let window = app.windows.firstMatch.frame
        // Sideways, the crease always runs top to bottom, so table pose only exists upright.
        try XCTSkipIf(window.width > window.height, "Needs an upright window: rotate the open Duo upright")
        try XCTSkipIf(window.height < 760, "The closed Duo can't stand in table pose")
        return app
    }

    func testTableCoachMovesComposerToTheFlatHalf() throws {
        let app = try launchTable([])
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(input.frame.minY, app.windows.firstMatch.frame.midY, "The composer sits on the flat half")
        XCTAssertLessThanOrEqual(app.tables.firstMatch.frame.maxY, app.windows.firstMatch.frame.midY + 1, "The conversation stays on the standing half")
    }

    func testTableComposerRestsOnTheTabBar() throws {
        let app = try launchTable([])
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        XCTAssertLessThan(app.buttons["Coach"].firstMatch.frame.minY - input.frame.maxY, 72,
                          "The composer sits at the bottom of the flat half, so a tall one can't slide under the tab bar")
    }

    func testTableKeyboardKeepsTheFieldVisible() throws {
        let app = try launchTable(["--coach-inference-fixture"])
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 15)); input.tap()
        let keyboard = app.keyboards.firstMatch
        try XCTSkipUnless(keyboard.waitForExistence(timeout: 5), "Needs the software keyboard")
        input.typeText("Two eggs")
        XCTAssertLessThanOrEqual(input.frame.maxY, keyboard.frame.minY, "The field stays above the keyboard")
        XCTAssertEqual(input.value as? String, "Two eggs", "The field keeps focus while it moves")
    }

    func testTableProgressPutsTheChartAboveTheDetails() throws {
        let app = try launchTable(["--coach-navigation-start-today", "--diary-history-fixture"])
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 15))
        app.buttons["Progress"].firstMatch.tap()
        let primary = app.descendants(matching: .any)["progressPrimaryColumn"]
        let secondary = app.descendants(matching: .any)["progressSecondaryColumn"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(primary.frame.maxY, secondary.frame.minY + 1, "Chart on the standing half, details below")
    }

    func testTableCameraKeepsShootingUntilDone() throws {
        let app = try launchTable([])
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["coachPhotos"].waitForExistence(timeout: 5)); app.buttons["coachPhotos"].tap()
        let shutter = app.buttons["coachCameraShutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(shutter.frame.minY, app.windows.firstMatch.frame.midY, "Shutter on the flat half")
        XCTAssertTrue(app.buttons["coachCameraTimer"].exists, "A self-timer for hands-free shots")
        XCTAssertTrue(app.buttons["syntheticPhoto"].waitForExistence(timeout: 5)); app.buttons["syntheticPhoto"].tap()
        XCTAssertTrue(app.staticTexts["1 photo added"].waitForExistence(timeout: 5), "The camera stays open for the next plate")
        app.buttons["coachCameraDone"].tap()
        XCTAssertTrue(app.textFields["coachInput"].waitForExistence(timeout: 5))
        XCTAssertFalse(shutter.exists)
    }
}
