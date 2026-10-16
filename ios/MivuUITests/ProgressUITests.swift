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
        selectReport("reportDaily", in: app)
        let goalSummary = app.staticTexts["progressGoalSummary"]
        XCTAssertTrue(goalSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(goalSummary.label.contains("2,000"))
        let proteinGoal = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Protein goal 100.0 g")).firstMatch
        reveal(proteinGoal, in: app)
        XCTAssertTrue(proteinGoal.exists)
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

        for report in ["reportDaily", "reportWeekly", "reportMonthly"] {
            selectReport(report, in: app)
            if report != "reportDaily" {
                expand("progressCoverage", toShow: app.staticTexts["missingDayCopy"], in: app)
            }
            if report == "reportMonthly" {
                let samples = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Known samples of 30 dates")).firstMatch
                reveal(samples, in: app)
                XCTAssertTrue(samples.label.contains("protein 0"))
            }
            reveal(app.staticTexts["missingDayCopy"], in: app)
            XCTAssertTrue(app.staticTexts["missingDayCopy"].exists)
            let nutrition = app.staticTexts["nutritionChartSummary"]
            expand("nutritionData", toShow: nutrition, in: app)
            reveal(nutrition, in: app)
            XCTAssertTrue(nutrition.label.contains("95 kcal"))
            if report == "reportMonthly" { attachScreenshot("Synthetic saved 30-day progress", from: app) }
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
        selectReport("reportDaily", in: app)
        let summary = app.staticTexts["progressGoalSummary"]
        reveal(summary, in: app)
        XCTAssertEqual(summary.label, "No energy target set")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Progress"].tap()
        selectReport("reportDaily", in: app)
        reveal(summary, in: app)
        XCTAssertEqual(summary.label, "No energy target set")
        openSettings(in: app)
        open("editGoals", in: app)
        XCTAssertEqual(app.textFields["goalKcal"].value as? String, "Energy (kcal)")
        attachScreenshot("Synthetic cleared dated goals retain visible units", from: app)
    }

    func testLargestTextDarkProgressKeepsReportsAccessible() {
        let app = launchDiary(extra: ["--proof-dark", "--proof-largest-text"])
        app.tabBars.buttons["Progress"].tap()
        let monthly = app.buttons["reportMonthly"]
        reveal(monthly, in: app)
        XCTAssertGreaterThanOrEqual(monthly.frame.height, 44)
        monthly.tap()
        let missing = app.staticTexts["missingDayCopy"]
        expand("progressCoverage", toShow: missing, in: app)
        reveal(missing, in: app)
        XCTAssertTrue(missing.exists)
        let nutrition = app.staticTexts["nutritionChartSummary"]
        expand("nutritionData", toShow: nutrition, in: app)
        reveal(nutrition, in: app)
        XCTAssertTrue(nutrition.label.contains("insufficient data"))
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
        selectReport("reportDaily", in: app)
        let recordedFood = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Recorded food: 95 kcal")).firstMatch
        reveal(recordedFood, in: app)
        XCTAssertTrue(recordedFood.exists)
        let recordedBurn = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Estimated workout burn: 120 kcal")).firstMatch
        reveal(recordedBurn, in: app)
        XCTAssertTrue(recordedBurn.exists)
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
        selectReport("reportDaily", in: app)
        reveal(recordedFood, in: app)
        XCTAssertTrue(recordedFood.exists, "Deleting a workout preserves recorded food")
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

    private func launchDiary(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english"] + extra
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

    private func selectReport(_ id: String, in app: XCUIApplication) {
        open(id, in: app)
        XCTAssertTrue(app.buttons[id].isSelected)
    }

    private func logWeight(_ value: String, in app: XCUIApplication) {
        open("logWeight", in: app)
        replace(app.textFields["weightInput"], with: value)
        app.buttons["saveWeight"].tap()
    }

    private func logWorkout(in app: XCUIApplication) { open("logWorkout", in: app) }

    private func expand(_ id: String, toShow element: XCUIElement, in app: XCUIApplication) {
        if !element.exists {
            let title = id == "progressCoverage" ? "Coverage & averages" : "Recorded intake data"
            let disclosure = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
            reveal(disclosure, in: app)
            disclosure.tap()
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Progress immediately after expanding " + id
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            attachScreenshot("Progress immediately after expanding " + id, from: app)
        }
    }

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
            if element.exists && element.isHittable { break }
            scroller.swipeUp()
        }
        if !element.exists {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Progress after upward scrolling before fallback"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            attachScreenshot("Progress after upward scrolling before fallback", from: app)
        }
        for _ in 0..<8 {
            if element.exists && element.isHittable { break }
            scroller.swipeDown()
        }
        if !element.exists || !element.isHittable {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Progress lookup accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            attachScreenshot("Progress lookup failure", from: app)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
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
