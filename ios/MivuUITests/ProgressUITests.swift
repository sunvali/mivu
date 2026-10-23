import XCTest

@MainActor final class ProgressUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    func testSavedGoalsWeightWorkoutAndReportsSurviveRelaunch() {
        let app = launchDiary()
        openSettings(in: app)
        reveal(app.buttons["editGoals"], in: app)
        app.buttons["editGoals"].tap()
        replace(app.textFields["goalKcal"], with: "2000")
        replace(app.textFields["goalProtein"], with: "100")
        app.buttons["saveGoals"].tap()
        app.buttons["doneSettings"].tap()

        app.tabBars.buttons["Progress"].tap()
        let target = text(containing: "target 2,000 kcal", in: app)
        reveal(target, in: app)
        XCTAssertTrue(target.exists)
        app.tabBars.buttons["Today"].tap()
        logWeight("70", in: app)
        app.buttons["logMeal"].tap()
        replace(app.textFields["mealText"], with: "Synthetic apple")
        app.buttons["sendMeal"].tap()

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["missingDayCopy"], in: app)
        XCTAssertTrue(app.staticTexts["missingDayCopy"].exists)
        open("openWeight", in: app)
        let correction = app.buttons["editWeight"].firstMatch
        reveal(correction, in: app)
        correction.tap()
        replace(app.textFields["weightCorrectionInput"], with: "71")
        app.buttons["saveWeightCorrection"].tap()
        app.navigationBars.buttons["Progress"].tap()
        open("openWorkouts", in: app)
        logWorkout(in: app)
        app.buttons["workoutStrength"].tap()
        replace(app.textFields["workoutDuration"], with: "30")
        replace(app.textFields["workoutExercise"], with: "Squat")
        replace(app.textFields["workoutRepetitions"], with: "8")
        app.buttons["saveWorkout"].tap()
        let session = app.buttons["workoutRow"].firstMatch
        reveal(session, in: app)
        session.tap()
        XCTAssertTrue(app.staticTexts["Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["30 minutes"].exists)
        app.buttons["editWorkout"].tap()
        replace(app.textFields["workoutDuration"], with: "35")
        app.buttons["saveWorkout"].tap()
        XCTAssertTrue(app.staticTexts["35 minutes"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Progress"].tap()
        open("openWeight", in: app)
        let savedWeight = app.staticTexts["71 kg"].firstMatch
        reveal(savedWeight, in: app)
        XCTAssertTrue(savedWeight.exists)
        let weightSummary = app.staticTexts["weightChartSummary"]
        reveal(weightSummary, in: app)
        XCTAssertTrue(weightSummary.label.contains("71.0 kg"))
        app.navigationBars.buttons["Progress"].tap()
        open("openWorkouts", in: app)
        let savedWorkout = app.buttons["workoutRow"].firstMatch
        reveal(savedWorkout, in: app)
        XCTAssertTrue(savedWorkout.exists)
        XCTAssertTrue(savedWorkout.label.contains("35 minutes"))
        app.navigationBars.buttons["Progress"].tap()

        for range in ["Week", "Month"] {
            selectRange(range, in: app)
            reveal(app.staticTexts["missingDayCopy"], in: app)
            XCTAssertTrue(app.staticTexts["missingDayCopy"].exists)
            XCTAssertTrue(calorieSummary(in: app).contains("95 kcal"))
            if range == "Month" { attachScreenshot("Synthetic saved 30-day progress", from: app) }
            scrollToTop(in: app)
        }
    }

    func testFilledGoalLabelsAndClearingLastTargetSurviveRelaunch() {
        let app = launchDiary()
        openSettings(in: app)
        open("editGoals", in: app)
        let fields = [("goalKcal", "Energy (kcal)", "2000"), ("goalCarbs", "Carbs (g)", "200"),
                      ("goalProtein", "Protein (g)", "100"), ("goalFat", "Fat (g)", "60"), ("goalWeight", "Weight (kg)", "70")]
        for (id, title, value) in fields {
            replace(app.textFields[id], with: value)
            XCTAssertTrue(app.staticTexts[title].exists, "Filled input keeps its visible name and unit: " + title)
        }
        app.buttons["saveGoals"].tap()
        open("editGoals", in: app)
        for (id, _, _) in fields.dropFirst() { replace(app.textFields[id], with: "") }
        app.buttons["saveGoals"].tap()
        open("editGoals", in: app)
        replace(app.textFields["goalKcal"], with: "")
        guard app.buttons["saveGoals"].isEnabled else { XCTFail("An all-unset dated goal must be saveable"); return }
        app.buttons["saveGoals"].tap()
        app.buttons["doneSettings"].tap()
        app.tabBars.buttons["Progress"].tap()
        let summary = text(containing: "No energy target set", in: app)
        reveal(summary, in: app)
        XCTAssertTrue(summary.exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Progress"].tap()
        reveal(summary, in: app)
        XCTAssertTrue(summary.exists)
        openSettings(in: app)
        open("editGoals", in: app)
        XCTAssertEqual(app.textFields["goalKcal"].value as? String, "Energy (kcal)")
        attachScreenshot("Synthetic cleared dated goals retain visible units", from: app)
    }

    func testLargestTextDarkProgressKeepsReportsAccessible() {
        let app = launchDiary(extra: ["--proof-dark", "--proof-largest-text"])
        app.tabBars.buttons["Progress"].tap()
        selectRange("Month", in: app)
        let missing = app.staticTexts["missingDayCopy"]
        reveal(missing, in: app)
        XCTAssertTrue(missing.exists)
        let empty = text(containing: "Log a meal to see your calories", in: app)
        reveal(empty, in: app)
        XCTAssertTrue(empty.exists)
        attachScreenshot("English dark accessibility5 Progress", from: app)
        open("openWeight", in: app)
        reveal(app.staticTexts["weightChartSummary"], in: app)
        XCTAssertTrue(app.staticTexts["weightChartSummary"].label.contains("insufficient data"))
    }

    func testSavedWorkoutSetsAndNoGoalReport() {
        let app = launchDiary()
        app.buttons["logMeal"].tap()
        replace(app.textFields["mealText"], with: "Synthetic apple")
        app.buttons["sendMeal"].tap()
        logWeight("70", in: app)
        app.tabBars.buttons["Progress"].tap()
        open("openWorkouts", in: app)
        logWorkout(in: app)
        replace(app.textFields["workoutDuration"], with: "30")
        XCTAssertTrue(app.staticTexts["Duration in minutes"].exists, "Filled workout input keeps its visible name and unit")
        replace(app.textFields["workoutExercise"], with: "Squat")
        replace(app.textFields["workoutRepetitions"], with: "8")
        XCTAssertTrue(app.staticTexts["Repetitions"].exists, "Filled workout input keeps its visible name and unit")
        replace(app.textFields["workoutLoad"], with: "40")
        XCTAssertTrue(app.staticTexts["Load (kg, blank for bodyweight)"].exists, "Filled workout input keeps its visible name and unit")
        replace(app.textFields["workoutBurn"], with: "120")
        XCTAssertTrue(app.staticTexts["Estimated burn (kcal)"].exists, "Filled workout input keeps its visible name and unit")
        attachScreenshot("Synthetic filled workout fields retain visible units", from: app)
        app.buttons["saveWorkout"].tap()
        app.navigationBars.buttons["Progress"].tap()
        XCTAssertTrue(calorieSummary(in: app).contains("95 kcal"))
        scrollToTop(in: app)
        open("openWorkouts", in: app)
        let row = app.buttons["workoutRow"].firstMatch
        reveal(row, in: app)
        row.tap()
        XCTAssertTrue(app.staticTexts["Set 1: 8 repetitions · 40 kg"].waitForExistence(timeout: 5))
        app.buttons["editWorkout"].tap()
        app.buttons["addWorkoutSet"].tap()
        reveal(app.textFields["workoutRepetitions1"], in: app)
        replace(app.textFields["workoutRepetitions1"], with: "10")
        reveal(app.textFields["workoutLoad1"], in: app)
        replace(app.textFields["workoutLoad1"], with: "45")
        app.buttons["saveWorkout"].tap()
        XCTAssertTrue(app.staticTexts["Set 2: 10 repetitions · 45 kg"].waitForExistence(timeout: 5))
        app.buttons["editWorkout"].tap()
        reveal(app.buttons["removeWorkoutExercise0"], in: app)
        app.buttons["removeWorkoutExercise0"].tap()
        app.buttons["saveWorkout"].tap()
        XCTAssertTrue(app.staticTexts["No exercise details recorded."].waitForExistence(timeout: 5))
        let delete = app.buttons["deleteWorkout"]
        reveal(delete, in: app)
        delete.tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.label.contains("strength workout"))
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["No exercise details recorded."].exists, "Cancel preserves the selected workout")
        delete.tap()
        app.alerts.buttons["Delete workout"].tap()
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["workoutRow"].exists)
        app.navigationBars.buttons["Progress"].tap()
        XCTAssertTrue(calorieSummary(in: app).contains("95 kcal"), "Deleting a workout preserves recorded food")
        scrollToTop(in: app)
        open("openWeight", in: app)
        reveal(app.staticTexts["70 kg"].firstMatch, in: app)
        XCTAssertTrue(app.staticTexts["70 kg"].firstMatch.exists, "Deleting a workout preserves the recorded weight")
    }

    func testWeightChartSelectsSavedMeasurement() {
        let app = launchDiary()
        logWeight("70", in: app)
        app.tabBars.buttons["Progress"].tap()
        open("openWeight", in: app)
        let chart = app.otherElements["weightChart"]
        reveal(chart, in: app)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let selected = app.staticTexts["selectedWeight"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue(selected.label.contains("70.0 kg"))
        attachScreenshot("Selected saved weight on Progress chart", from: app)
        let correction = app.buttons["editWeight"].firstMatch
        reveal(correction, in: app)
        correction.tap()
        XCTAssertTrue(app.textFields["weightCorrectionInput"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Weight in kg"].exists, "Saved weight keeps its visible unit label")
        app.navigationBars.buttons["Cancel"].tap()
        app.navigationBars.buttons["Progress"].tap()
        openSettings(in: app)
        open("localProfiles", in: app)
        let create = app.buttons["Create local profile"]
        reveal(create, in: app)
        create.tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Synthetic chart profile")
        app.alerts.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic chart profile"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["Settings"].tap()
        app.buttons["doneSettings"].tap()
        app.tabBars.buttons["Today"].tap()
        logWeight("80", in: app)
        app.tabBars.buttons["Progress"].tap()
        open("openWeight", in: app)
        reveal(chart, in: app)
        XCTAssertFalse(selected.exists, "A new profile has no chart selection until a fresh tap")
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue(selected.label.contains("80.0 kg"))
    }

    func testWeightAskPipQuotesRecord() {
        let app = launchDiary(extra: ["--coach-inference-fixture"])
        logWeight("70", in: app)
        app.tabBars.buttons["Progress"].tap()
        open("openWeight", in: app)
        askPip("editWeight", expecting: "Weight · 70", in: app)
    }

    func testWorkoutAskPipQuotesRecord() {
        let app = launchDiary(extra: ["--coach-inference-fixture"])
        app.tabBars.buttons["Progress"].tap()
        open("openWorkouts", in: app)
        logWorkout(in: app)
        replace(app.textFields["workoutDuration"], with: "30")
        app.buttons["saveWorkout"].tap()
        askPip("workoutRow", expecting: "30 min", in: app)
    }

    private func askPip(_ row: String, expecting text: String, in app: XCUIApplication) {
        let target = app.buttons[row].firstMatch
        reveal(target, in: app)
        target.press(forDuration: 1)
        let ask = app.buttons["Ask Pip"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5)); ask.tap()
        let bar = app.otherElements["coachReplyBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        XCTAssertTrue(bar.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists)
    }

    func testChartCardsRenderForEveryRange() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english", "--diary-progress-fixture"]
        app.launch()
        let tab = app.tabBars.buttons["Progress"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15)); tab.tap()
        XCTAssertTrue(app.staticTexts["missingDayCopy"].waitForExistence(timeout: 10))
        let picker = app.segmentedControls["progressRange"]
        for range in ["Week", "Month", "3M", "Year"] {
            picker.buttons[range].tap()
            XCTAssertTrue(picker.buttons[range].isSelected)
            for part in ["top", "middle", "lower", "bottom"] {
                attachScreenshot("Progress \(range) \(part)", from: app)
                app.swipeUp()
            }
            for _ in 0..<6 { app.swipeDown() }
        }
    }

    func testEachCardOpensItsDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english", "--diary-progress-fixture"]
        app.launch()
        let tab = app.tabBars.buttons["Progress"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15)); tab.tap()
        app.segmentedControls["progressRange"].buttons["Month"].tap()
        for (id, title) in [("progressMacros", "Macros"), ("progressCalendar", "Calendar"), ("progressCalories", "Calories"),
                            ("progressBurn", "Estimated burn"), ("progressTopFoods", "Top foods")] {
            let card = app.buttons[id]
            reveal(card, in: app)
            card.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(id) should open \(title)")
            attachScreenshot("Detail \(title)", from: app)
            app.navigationBars[title].buttons.firstMatch.tap()
            XCTAssertTrue(app.segmentedControls["progressRange"].waitForExistence(timeout: 5) || app.buttons[id].waitForExistence(timeout: 5))
        }
    }

    private func launchDiary(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Day start at midnight keeps meals, weights and the Day report on one date between 00:00 and 04:00.
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english", "-dayStartHour", "<integer>0</integer>"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        return app
    }

    private func openSettings(in app: XCUIApplication) {
        app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    private func open(_ id: String, in app: XCUIApplication) {
        let action = app.buttons[id]
        reveal(action, in: app)
        action.tap()
    }

    private func selectRange(_ title: String, in app: XCUIApplication) {
        let segment = app.segmentedControls["progressRange"].buttons[title]
        // The picker is the list's first row; a scrolled list drops it from the hierarchy.
        for _ in 0..<8 where !segment.waitForExistence(timeout: 1) { app.swipeDown() }
        XCTAssertTrue(segment.waitForExistence(timeout: 10))
        segment.tap()
        XCTAssertTrue(segment.isSelected)
    }

    private func text(containing value: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    /// The calories chart's spoken summary, e.g. "Oct 23: 95 kcal".
    private func calorieSummary(in app: XCUIApplication) -> String {
        let chart = app.descendants(matching: .any)["nutritionChartSummary"]
        reveal(chart, in: app)
        return chart.value as? String ?? ""
    }

    private func scrollToTop(in app: XCUIApplication) {
        for _ in 0..<6 { app.collectionViews["progressList"].swipeDown() }
    }

    private func logWeight(_ value: String, in app: XCUIApplication) {
        open("logWeight", in: app)
        replace(app.textFields["weightInput"], with: value)
        app.buttons["saveWeight"].tap()
    }

    private func logWorkout(in app: XCUIApplication) { open("logWorkout", in: app) }

    private func attachScreenshot(_ name: String, from app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let workoutForm = app.collectionViews["workoutForm"]
        let progress = app.collectionViews["progressList"]
        let scroller = workoutForm.exists && workoutForm.isHittable ? workoutForm
            : (progress.exists && progress.isHittable ? progress
               : app.collectionViews.allElementsBoundByIndex.first(where: \.isHittable) ?? app.collectionViews.firstMatch)
        for _ in 0..<8 {
            if readyToUse(element, in: app, scroller: scroller) { break }
            scroller.swipeUp()
        }
        for _ in 0..<8 {
            if readyToUse(element, in: app, scroller: scroller) { break }
            scroller.swipeDown()
        }
        if !readyToUse(element, in: app, scroller: scroller) {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Progress lookup accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            attachScreenshot("Progress lookup failure", from: app)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(readyToUse(element, in: app, scroller: scroller), "Interactive rows must be fully clear of fixed bars before use")
    }

    private func readyToUse(_ element: XCUIElement, in app: XCUIApplication, scroller: XCUIElement) -> Bool {
        guard element.exists && element.isHittable else { return false }
        guard element.identifier == "logWeight" else { return true }
        var top = scroller.frame.minY
        var bottom = scroller.frame.maxY
        if let navigation = app.navigationBars.allElementsBoundByIndex.first(where: \.isHittable) {
            top = max(top, navigation.frame.maxY)
        }
        if let tabs = app.tabBars.allElementsBoundByIndex.first(where: \.isHittable) {
            bottom = min(bottom, tabs.frame.minY)
        }
        let capture = app.buttons["logMeal"]
        if element.identifier != "logMeal", capture.exists && capture.isHittable {
            bottom = min(bottom, capture.frame.minY - 12)
        }
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists { bottom = min(bottom, keyboard.frame.minY) }
        return element.frame.minY >= top && element.frame.maxY <= bottom
    }

    private func replace(_ field: XCUIElement, with value: String) {
        let app = XCUIApplication()
        dismissKeyboard(in: app)
        reveal(field, in: app)
        field.tap()
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        if !focused.evaluate(with: field) { field.tap() }
        let focus = XCTNSPredicateExpectation(predicate: focused, object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [focus], timeout: 5), .completed, "The selected input must own keyboard focus before typing")
        if let existing = field.value as? String, !existing.isEmpty, existing != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value.isEmpty ? field.placeholderValue : value)
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let done = app.buttons.matching(identifier: "progressKeyboardDone").allElementsBoundByIndex.first(where: \.isHittable)
        if let done {
            done.tap()
            let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
            let result = XCTWaiter.wait(for: [hidden], timeout: 5)
            if result != .completed {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "Progress keyboard after its Done action"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
                attachScreenshot("Progress keyboard after its Done action", from: app)
            }
            XCTAssertEqual(result, .completed)
        } else {
            XCTFail("The visible numeric keyboard must expose its Done action")
        }
    }
}
