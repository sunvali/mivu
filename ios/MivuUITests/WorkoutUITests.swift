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

    func testGymTickThreeSets() {
        let app = launch()
        let start = app.buttons["startWorkout"]
        reveal(start, in: app)
        start.tap()
        let gym = app.buttons["startGym"]
        XCTAssertTrue(gym.waitForExistence(timeout: 5))
        gym.tap()

        let addExercise = app.buttons["addExercise"]
        XCTAssertTrue(addExercise.waitForExistence(timeout: 10))
        addExercise.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Bench press")
        let bench = app.buttons["Barbell Bench Press"].firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        bench.tap()

        // Tap a number: the wheels open; Done there also ticks the set.
        let weight = app.buttons["setWeight"].firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        weight.tap()
        let wheelDone = app.buttons["wheelDone"]
        XCTAssertTrue(wheelDone.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set 1"].exists)
        capture("Gym wheels", in: app)
        // Tapping the centred number types it.
        app.descendants(matching: .any)["wheelWeight"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let typed = app.alerts["Weight"]
        XCTAssertTrue(typed.waitForExistence(timeout: 5))
        typed.textFields.firstMatch.typeText("40")
        typed.buttons["OK"].tap()
        wheelDone.tap()
        XCTAssertTrue(wheelDone.waitForNonExistence(timeout: 5))
        XCTAssertEqual(weight.value as? String, "40 kg")

        let addSet = app.buttons["addSet"]
        for _ in 0..<2 { addSet.tap() }
        let ticks = app.buttons.matching(identifier: "tickSet")
        XCTAssertTrue(ticks.element(boundBy: 2).waitForExistence(timeout: 5))

        // Swiping a number up changes it without opening the wheels.
        let reps = app.buttons.matching(identifier: "setReps").element(boundBy: 2)
        let before = reps.value as? String
        let grip = reps.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 0, dy: -60)), withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertNotEqual(reps.value as? String, before)
        XCTAssertFalse(wheelDone.exists)

        ticks.element(boundBy: 1).tap()
        ticks.element(boundBy: 2).tap()
        let ticked = ticks.matching(NSPredicate(format: "selected == true"))
        XCTAssertTrue(ticked.element(boundBy: 2).waitForExistence(timeout: 5))
        XCTAssertEqual(ticked.count, 3)
        capture("Gym", in: app)

        // Next time the sets come back filled in, and a heavier one is a new best.
        app.buttons["finishWorkout"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        reveal(start, in: app)
        start.tap()
        XCTAssertTrue(gym.waitForExistence(timeout: 5))
        gym.tap()
        // Wait for the full-screen cover to settle; a tap while it slides in is lost.
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: addExercise)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed)
        addExercise.tap()
        XCTAssertTrue(app.staticTexts["Recent"].waitForExistence(timeout: 5))
        capture("Exercise picker", in: app)
        bench.tap()
        XCTAssertTrue(app.staticTexts["Last time 40 kg × 10"].waitForExistence(timeout: 5))
        XCTAssertEqual(ticks.count, 3)
        let firstWeight = app.buttons["setWeight"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        firstWeight.press(forDuration: 0.05, thenDragTo: firstWeight.withOffset(CGVector(dx: 0, dy: -60)), withVelocity: .slow, thenHoldForDuration: 0.2)
        ticks.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["New best"].waitForExistence(timeout: 5))
        capture("Gym last time", in: app)

        // A dumbbell lift starts with no weight; ✓ asks for one on the wheels, and their Done ticks it.
        // Below the fold at large text; scroll from the margin, since a swipe on a number changes it.
        let margin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8))
        for _ in 0..<6 where !addExercise.isHittable { margin.press(forDuration: 0.05, thenDragTo: margin.withOffset(CGVector(dx: 0, dy: -400))) }
        addExercise.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Dumbbell curl")
        let curl = app.buttons["Dumbbell Curl"].firstMatch
        XCTAssertTrue(curl.waitForExistence(timeout: 5))
        curl.tap()
        let curlWeight = app.buttons.matching(identifier: "setWeight").element(boundBy: 0)
        XCTAssertTrue(curlWeight.waitForExistence(timeout: 5))
        XCTAssertEqual(curlWeight.value as? String, "Not set")
        ticks.element(boundBy: 0).tap()
        XCTAssertTrue(wheelDone.waitForExistence(timeout: 5))
        wheelDone.tap()
        XCTAssertTrue(wheelDone.waitForNonExistence(timeout: 5))
        XCTAssertEqual(curlWeight.value as? String, "10 kg")
        XCTAssertTrue(ticks.element(boundBy: 0).isSelected)
    }

    func testPastGymHasNoClock() {
        let app = launch()
        let start = app.buttons["startWorkout"]
        reveal(start, in: app)
        start.tap()
        let when = app.buttons["workoutStart"]
        XCTAssertTrue(when.waitForExistence(timeout: 5))
        XCTAssertEqual(when.value as? String, "Today, now")
        when.tap()
        // The first wheel is the day; one notch back is yesterday.
        let day = app.pickerWheels.firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.adjust(toPickerWheelValue: day.value as? String == "Today" ? Self.yesterdayWheelValue() : "Today")
        XCTAssertNotEqual(when.value as? String, "Today, now")
        app.buttons["startGym"].tap()

        XCTAssertTrue(app.buttons["addExercise"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars.staticTexts["Yesterday"].exists)
        XCTAssertFalse(app.buttons["Minimize"].exists, "a past workout has no running clock to keep")
    }

    /// The date wheel's accessibility values name earlier days like "Nov 4".
    private static func yesterdayWheelValue() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "MMM d"
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
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
