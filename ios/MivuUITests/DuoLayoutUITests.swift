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

    func testUprightTodayStaysOneColumn() {
        let app = launch(wide: false)
        XCTAssertFalse(app.descendants(matching: .any)["todayMealsColumn"].exists)
        XCTAssertTrue(app.buttons["logWeight"].exists)
    }
}
