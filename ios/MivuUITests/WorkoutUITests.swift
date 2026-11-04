import XCTest

@MainActor final class WorkoutUITests: XCTestCase {
    func testLogRunFromToday() {
        let app = launch()
        let start = app.buttons["startWorkout"]
        reveal(start, in: app)
        start.tap()
        let run = app.buttons["Run"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        run.tap()

        let time = app.descendants(matching: .any)["timeRuler"]
        XCTAssertTrue(time.waitForExistence(timeout: 5))
        let before = time.value as? String
        // The element's frame runs past the screen edge with the off-screen ticks, so aim at the screen's middle.
        let grip = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX + 40, dy: time.frame.maxY - 25))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: -60, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertNotEqual(time.value as? String, before)
        capture("Cardio", in: app)
        app.buttons["saveCardio"].tap()

        let row = app.buttons["workoutRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.hasPrefix("Run") && row.label.contains("km"), row.label)
        XCTAssertTrue(app.staticTexts["Workouts"].exists)
        capture("Today", in: app)
    }

    func testTypedMinutesSaveWithoutDone() {
        let app = launch()
        let time = openRun(app)
        // The number sits at the top of the time card; tapping it types.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: time.frame.minY + 30)).tap()
        app.typeText("45")
        app.buttons["saveCardio"].tap()
        let row = app.buttons["workoutRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("45 min"), row.label)
    }

    func testCancelAsksBeforeDiscardingChanges() {
        let app = launch()
        _ = openRun(app)
        app.buttons["cancelCardio"].tap()
        XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 5), "an untouched log closes without asking")

        _ = openRun(app)
        app.buttons["Hard"].tap()
        app.buttons["cancelCardio"].tap()
        XCTAssertTrue(app.alerts["Discard changes to this workout?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Keep editing"].tap()
        XCTAssertTrue(app.buttons["saveCardio"].exists)
        app.buttons["cancelCardio"].tap()
        app.alerts.buttons["Discard changes"].tap()
        XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["workoutRow"].exists)
    }

    func testAddWeightBringsTheEstimate() {
        let app = launch()
        _ = openRun(app)
        let addWeight = app.buttons["cardioAddWeight"]
        XCTAssertTrue(addWeight.waitForExistence(timeout: 5))
        addWeight.tap()
        let field = app.textFields["weightInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("70")
        app.buttons["saveWeight"].tap()
        let kcal = app.buttons["cardioKcal"]
        XCTAssertTrue(kcal.waitForExistence(timeout: 10))
        XCTAssertTrue(kcal.label.hasPrefix("About ") && kcal.label.hasSuffix("kcal"), kcal.label)
        XCTAssertFalse(addWeight.exists)
    }

    func testLargestTextKeepsCardioUsable() {
        let app = launch(["--proof-largest-text"])
        let start = app.buttons["startWorkout"]
        reveal(start, in: app)
        start.tap()
        let run = app.buttons["Run"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        run.tap()
        let save = app.buttons["saveCardio"]
        XCTAssertTrue(save.waitForExistence(timeout: 5) && save.isHittable)
        capture("Cardio largest text", in: app)
        save.tap()
        let row = app.buttons["workoutRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        reveal(row, in: app)
        capture("Today largest text", in: app)
    }

    /// Today → Start workout → Run; returns the time ruler.
    private func openRun(_ app: XCUIApplication) -> XCUIElement {
        let start = app.buttons["startWorkout"]
        reveal(start, in: app)
        start.tap()
        let run = app.buttons["Run"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        run.tap()
        let time = app.descendants(matching: .any)["timeRuler"]
        XCTAssertTrue(time.waitForExistence(timeout: 5))
        return time
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        // A metric English region, so distances read in km whatever the simulator's region.
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english", "-AppleLocale", "en_AU"] + arguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        return app
    }

    /// Scrolls until the element sits fully above the floating capture bar.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let list = app.collectionViews.firstMatch, bar = app.buttons["logMeal"]
        func clear() -> Bool { element.isHittable && element.frame.maxY < bar.frame.minY - 12 }
        for _ in 0..<8 where !clear() { list.swipeUp(velocity: .slow) }
        XCTAssertTrue(clear())
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
