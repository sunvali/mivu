import XCTest

@MainActor final class ProgressUITests: XCTestCase {
    func testSavedGoalsWeightWorkoutAndReportsSurviveRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))

        app.tabBars.buttons["Settings"].tap()
        let goals = app.buttons["editGoals"]
        reveal(goals, in: app)
        goals.tap()
        replace(app.textFields["goalKcal"], with: "2000")
        replace(app.textFields["goalProtein"], with: "100")
        app.buttons["saveGoals"].tap()

        app.tabBars.buttons["Today"].tap()
        let goalSummary = app.staticTexts["todayGoalSummary"]
        XCTAssertTrue(goalSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(goalSummary.label.contains("2,000"))
        let proteinGoal = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Protein goal 100.0 g")).firstMatch
        reveal(proteinGoal, in: app)
        XCTAssertTrue(proteinGoal.exists)
        let weight = app.buttons["logWeight"]
        reveal(weight, in: app)
        weight.tap()
        replace(app.textFields["weightInput"], with: "70")
        app.buttons["saveWeight"].tap()
        app.buttons["logMeal"].tap()
        replace(app.textFields["mealText"], with: "Synthetic apple")
        app.buttons["sendMeal"].tap()

        app.tabBars.buttons["History"].tap()
        let progress = app.buttons["openProgress"]
        reveal(progress, in: app)
        progress.tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["missingDayCopy"], in: app)
        XCTAssertTrue(app.staticTexts["missingDayCopy"].exists)

        let correction = app.buttons["editWeight"]
        reveal(correction, in: app)
        correction.tap()
        replace(app.textFields["weightCorrectionInput"], with: "71")
        app.buttons["saveWeightCorrection"].tap()

        let workout = app.buttons["logWorkout"]
        reveal(workout, in: app)
        workout.tap()
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
        app.navigationBars.buttons.firstMatch.tap()

        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        app.tabBars.buttons["History"].tap()
        reveal(app.buttons["openProgress"], in: app)
        app.buttons["openProgress"].tap()
        let savedWeight = app.staticTexts["71 kg"]
        reveal(savedWeight, in: app)
        XCTAssertTrue(savedWeight.exists)
        let savedWorkout = app.buttons["workoutRow"].firstMatch
        reveal(savedWorkout, in: app)
        XCTAssertTrue(savedWorkout.exists)
        XCTAssertTrue(savedWorkout.label.contains("35 minutes"))

        for (button, title) in [("reportDaily", "Daily report"), ("reportWeekly", "7-day report"), ("reportMonthly", "30-day report")] {
            let report = app.buttons[button]
            reveal(report, in: app)
            report.tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
            if title == "30-day report" {
                let samples = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Known samples of 30 dates")).firstMatch
                reveal(samples, in: app)
                XCTAssertTrue(samples.label.contains("protein 0"))
            }
            reveal(app.staticTexts["missingDayCopy"], in: app)
            XCTAssertTrue(app.staticTexts["missingDayCopy"].exists)
            let nutrition = app.staticTexts["nutritionChartSummary"]
            reveal(nutrition, in: app)
            XCTAssertTrue(nutrition.label.contains("95 kcal"))
            if title == "30-day report" {
                let chart = XCTAttachment(screenshot: app.screenshot())
                chart.name = "Synthetic saved nutrition trend"
                chart.lifetime = .keepAlways
                add(chart)
            }
            let weight = app.staticTexts["weightChartSummary"]
            reveal(weight, in: app)
            XCTAssertTrue(weight.label.contains("71.0 kg"))
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Synthetic saved 30-day progress"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testFilledGoalLabelsAndClearingLastTargetSurviveRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()
        reveal(app.buttons["editGoals"], in: app); app.buttons["editGoals"].tap()
        let fields = [("goalKcal", "Energy (kcal)", "2000"), ("goalCarbs", "Carbs (g)", "200"),
                      ("goalProtein", "Protein (g)", "100"), ("goalFat", "Fat (g)", "60"), ("goalWeight", "Weight (kg)", "70")]
        for (id, title, value) in fields {
            replace(app.textFields[id], with: value)
            XCTAssertTrue(app.staticTexts[title].exists, "Filled input keeps its visible name and unit: " + title)
        }
        app.buttons["saveGoals"].tap()
        reveal(app.buttons["editGoals"], in: app); app.buttons["editGoals"].tap()
        for (id, _, _) in fields.dropFirst() { replace(app.textFields[id], with: "") }
        app.buttons["saveGoals"].tap()
        reveal(app.buttons["editGoals"], in: app); app.buttons["editGoals"].tap()
        replace(app.textFields["goalKcal"], with: "")
        guard app.buttons["saveGoals"].isEnabled else { XCTFail("An all-unset dated goal must be saveable"); return }
        app.buttons["saveGoals"].tap()
        app.tabBars.buttons["Today"].tap()
        let summary = app.staticTexts["todayGoalSummary"]
        reveal(summary, in: app); XCTAssertEqual(summary.label, "No energy target set")
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        reveal(summary, in: app); XCTAssertEqual(summary.label, "No energy target set")
        app.tabBars.buttons["Settings"].tap()
        reveal(app.buttons["editGoals"], in: app); app.buttons["editGoals"].tap()
        XCTAssertEqual(app.textFields["goalKcal"].value as? String, "Energy (kcal)")
        let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = "Synthetic cleared dated goals retain visible units"; screen.lifetime = .keepAlways; add(screen)
    }

    func testLargestTextDarkProgressKeepsReportsAccessible() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english", "--proof-dark", "--proof-largest-text"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        app.tabBars.buttons["History"].tap()
        reveal(app.buttons["openProgress"], in: app)
        app.buttons["openProgress"].tap()
        let monthly = app.buttons["reportMonthly"]
        reveal(monthly, in: app)
        XCTAssertGreaterThanOrEqual(monthly.frame.height, 44)
        monthly.tap()
        XCTAssertTrue(app.staticTexts["30-day report"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["missingDayCopy"], in: app)
        XCTAssertTrue(app.staticTexts["missingDayCopy"].exists)
        reveal(app.staticTexts["nutritionChartSummary"], in: app)
        XCTAssertTrue(app.staticTexts["nutritionChartSummary"].label.contains("insufficient data"))
        reveal(app.staticTexts["weightChartSummary"], in: app)
        XCTAssertTrue(app.staticTexts["weightChartSummary"].label.contains("insufficient data"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "English dark accessibility5 Progress"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSavedWorkoutSetsAndNoGoalReport() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        app.buttons["logMeal"].tap()
        replace(app.textFields["mealText"], with: "Synthetic apple")
        app.buttons["sendMeal"].tap()
        let weight = app.buttons["logWeight"]
        reveal(weight, in: app)
        weight.tap()
        replace(app.textFields["weightInput"], with: "70")
        app.buttons["saveWeight"].tap()

        app.tabBars.buttons["History"].tap()
        let progress = app.buttons["openProgress"]
        reveal(progress, in: app)
        progress.tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        let workout = app.buttons["logWorkout"]
        reveal(workout, in: app)
        workout.tap()
        replace(app.textFields["workoutDuration"], with: "30")
        XCTAssertTrue(app.staticTexts["Duration in minutes"].exists, "Filled workout input keeps its visible name and unit")
        replace(app.textFields["workoutExercise"], with: "Squat")
        replace(app.textFields["workoutRepetitions"], with: "8")
        XCTAssertTrue(app.staticTexts["Repetitions"].exists, "Filled workout input keeps its visible name and unit")
        replace(app.textFields["workoutLoad"], with: "40")
        XCTAssertTrue(app.staticTexts["Load (kg, blank for bodyweight)"].exists, "Filled workout input keeps its visible name and unit")
        replace(app.textFields["workoutBurn"], with: "120")
        XCTAssertTrue(app.staticTexts["Estimated burn (kcal)"].exists, "Filled workout input keeps its visible name and unit")
        let labeled = XCTAttachment(screenshot: app.screenshot()); labeled.name = "Synthetic filled workout fields retain visible units"; labeled.lifetime = .keepAlways; add(labeled)
        app.buttons["saveWorkout"].tap()

        let recordedFood = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Recorded food: 95 kcal")).firstMatch
        reveal(recordedFood, in: app)
        XCTAssertTrue(recordedFood.exists)
        let recordedBurn = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Estimated workout burn: 120 kcal")).firstMatch
        reveal(recordedBurn, in: app)
        XCTAssertTrue(recordedBurn.exists)

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
    }

    func testWeightChartSelectsSavedMeasurement() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        let weight = app.buttons["logWeight"]
        reveal(weight, in: app)
        weight.tap()
        replace(app.textFields["weightInput"], with: "70")
        app.buttons["saveWeight"].tap()
        app.tabBars.buttons["History"].tap()
        reveal(app.buttons["openProgress"], in: app)
        app.buttons["openProgress"].tap()
        let chart = app.otherElements["weightChart"]
        reveal(chart, in: app)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let selected = app.staticTexts["selectedWeight"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue(selected.label.contains("70.0 kg"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Selected saved weight on Progress chart"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        reveal(app.buttons["editWeight"], in: app); app.buttons["editWeight"].tap()
        XCTAssertTrue(app.textFields["weightCorrectionInput"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Weight in kg"].exists, "Saved weight keeps its visible unit label")
        app.navigationBars.buttons["Cancel"].tap()
        app.tabBars.buttons["Settings"].tap()
        let create = app.buttons["Create local profile"]
        reveal(create, in: app); create.tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.typeText("Synthetic chart profile")
        app.alerts.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic chart profile"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
        reveal(weight, in: app); weight.tap()
        replace(app.textFields["weightInput"], with: "80"); app.buttons["saveWeight"].tap()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        reveal(chart, in: app)
        XCTAssertFalse(selected.exists, "A new profile has no chart selection until a fresh tap")
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5)); XCTAssertTrue(selected.label.contains("80.0 kg"))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let workoutForm = app.collectionViews["workoutForm"]
        let progress = app.collectionViews["progressList"]
        let scroller = workoutForm.exists ? workoutForm : (progress.exists ? progress : app.collectionViews.firstMatch)
        for _ in 0..<8 {
            if element.isHittable { break }
            scroller.swipeUp()
        }
        if !workoutForm.exists {
            for _ in 0..<12 {
                if element.isHittable { break }
                scroller.swipeDown()
            }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }

    private func replace(_ field: XCUIElement, with value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if let existing = field.value as? String, !existing.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(value)
        if !value.isEmpty { XCTAssertEqual(field.value as? String, value) }
    }
}
