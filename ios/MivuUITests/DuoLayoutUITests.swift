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

    func testSidewaysTodaySplitsSummaryAndMeals() {
        let app = launch(wide: true)
        let summary = app.descendants(matching: .any)["todaySummaryColumn"]
        let meals = app.descendants(matching: .any)["todayMealsColumn"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(meals.exists)
        XCTAssertLessThanOrEqual(summary.frame.maxX, meals.frame.minX + 1)
        XCTAssertTrue(app.buttons["logWeight"].exists, "Weight stays in the summary column")
    }

    func testUprightTodayStaysOneColumn() throws {
        let app = launch(wide: false)
        // XCUITest can't rotate the Duo's inner display; the open pose is wider than tall, so check upright windows only.
        let window = app.windows.firstMatch.frame
        try XCTSkipIf(window.width > window.height, "Needs an upright window: run Closed, or rotate the open Duo upright")
        XCTAssertFalse(app.descendants(matching: .any)["todayMealsColumn"].exists)
        XCTAssertTrue(app.buttons["logWeight"].exists)
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
    }

    func testSidewaysProgressUsesTwoColumns() {
        let app = launch(wide: true)
        app.buttons["Progress"].firstMatch.tap()
        let primary = app.descendants(matching: .any)["progressPrimaryColumn"]
        let secondary = app.descendants(matching: .any)["progressSecondaryColumn"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        XCTAssertTrue(secondary.exists)
        XCTAssertLessThanOrEqual(primary.frame.maxX, secondary.frame.minX + 1)
    }
}
