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
        try XCTSkipIf(app.windows.firstMatch.frame.height < 760, "Too short to show Weight without scrolling: not a sideways window")
        let summary = app.descendants(matching: .any)["todaySummaryColumn"]
        let meals = app.descendants(matching: .any)["todayMealsColumn"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(meals.exists)
        XCTAssertLessThanOrEqual(summary.frame.maxX, meals.frame.minX + 1)
        XCTAssertTrue(app.buttons["logWeight"].exists, "Weight stays in the summary column")
        XCTAssertLessThanOrEqual(app.buttons["logMeal"].frame.width, 300, "Capture buttons keep a normal size sideways")
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
        XCTAssertFalse(app.descendants(matching: .any)["coachLiveDay"].waitForExistence(timeout: 3),
                       "The keyboard shortens the view, but the window is still upright")
    }

    func testSidewaysCoachShowsLiveDayAndHighlightsChange() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture",
                               "--proof-english", "--wide-layout-ui-test"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        let liveDay = app.descendants(matching: .any)["coachLiveDay"]
        XCTAssertTrue(liveDay.waitForExistence(timeout: 5))
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Two eggs, three bread slices and salad")
        app.buttons["coachSend"].tap()
        let changed = app.descendants(matching: .any)["justChangedMeal"]
        XCTAssertTrue(changed.waitForExistence(timeout: 20), "The meal Coach logged lights up in the live day")
        XCTAssertGreaterThan(changed.frame.minX, input.frame.maxX - 1, "The live day sits beside the chat")
        XCTAssertLessThan(changed.frame.minY, liveDay.frame.midY, "The changed meal shows near the top, above the keyboard")
        XCTAssertFalse(app.buttons["coachFollowUp-today"].exists, "See today is redundant beside the live day")
    }

    func testSidewaysDiaryKeepsReadableWidth() throws {
        let app = launch(wide: true)
        try XCTSkipIf(app.windows.firstMatch.frame.width < 760, "Needs the sideways inner display, wider than the readable width")
        app.buttons["Diary"].firstMatch.tap()
        let intake = app.staticTexts["Recorded intake"]
        XCTAssertTrue(intake.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(intake.frame.minX, 70, "Diary is capped and centered, not stretched")
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
