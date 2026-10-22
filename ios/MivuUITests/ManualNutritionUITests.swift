import XCTest

@MainActor final class ManualNutritionUITests: XCTestCase {
    func testOfflineTodayCreateAndAppendRemainSavedAfterRelaunch() {
        let app = launch()
        app.buttons["addManually"].tap()
        enter(app, name: "Synthetic oats", calories: "120")
        app.buttons["saveManualNutrition"].tap()
        XCTAssertTrue(app.buttons["mealRow"].firstMatch.waitForExistence(timeout: 10))
        reveal(app.buttons["mealRow"].firstMatch, in: app); app.buttons["mealRow"].firstMatch.tap()
        reveal(app.buttons["addFoodManually"], in: app)
        XCTAssertTrue(app.buttons["addFoodManually"].exists)
        app.buttons["addFoodManually"].tap(); enter(app, name: "Synthetic milk", calories: "80")
        app.buttons["saveManualNutrition"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic milk"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Synthetic oats"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["mealRow"].firstMatch.waitForExistence(timeout: 10))
        reveal(app.buttons["mealRow"].firstMatch, in: app); app.buttons["mealRow"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Synthetic milk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic oats"].exists)
    }
    func testManualCancelAndSavePreserveUnsentNoteDraft() {
        let app = launch(["--sample-mode"])
        app.buttons["logMeal"].tap()
        app.textFields["mealText"].tap(); app.textFields["mealText"].typeText("Synthetic unsent note")
        app.buttons["doneMealText"].tap()
        reveal(app.buttons["enterNutritionManually"], in: app); app.buttons["enterNutritionManually"].tap()
        XCTAssertFalse(app.buttons["saveManualNutrition"].isEnabled)
        enter(app, name: "Synthetic tea", calories: "-1")
        XCTAssertFalse(app.buttons["saveManualNutrition"].isEnabled)
        app.buttons["cancelManualNutrition"].tap(); app.buttons["Keep editing"].tap()
        XCTAssertEqual(app.textFields["manualFoodName"].value as? String, "Synthetic tea")
        app.buttons["cancelManualNutrition"].tap(); app.buttons["Discard changes"].tap()
        XCTAssertEqual(app.textFields["mealText"].value as? String, "Synthetic unsent note")
        app.buttons["enterNutritionManually"].tap(); enter(app, name: "Synthetic water", calories: "0")
        app.buttons["saveManualNutrition"].tap()
        let receipt = app.buttons["manualSavedFood"]
        reveal(receipt, in: app)
        XCTAssertTrue(receipt.exists)
        let explanation = app.staticTexts["Your note and photos are still here and have not been sent."]
        reveal(explanation, in: app)
        XCTAssertTrue(explanation.exists)
        let unsent = app.textFields["mealText"]
        let sourceForm = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        for _ in 0..<12 {
            if unsent.exists && unsent.isHittable { break }
            sourceForm.swipeDown()
        }
        XCTAssertTrue(unsent.exists && unsent.isHittable)
        XCTAssertEqual(unsent.value as? String, "Synthetic unsent note")
    }
    func testManualFormSupportsLightDarkAndLargestTextSave() throws {
        for appearance in ["--proof-light", "--proof-dark"] {
            let app = launch([appearance, "--proof-largest-text"])
            app.buttons["addManually"].tap()
            enter(app, name: "Synthetic accessible food", calories: "0")
            let save = app.buttons["saveManualNutrition"]
            XCTAssertTrue(save.isHittable && save.isEnabled)
            XCTAssertGreaterThanOrEqual(save.frame.width, 44)
            let calories = app.textFields["manualCalories"]
            XCTAssertEqual(calories.label, "Energy (kcal)")
            let energyLabel = app.staticTexts["Energy (kcal)"].firstMatch
            XCTAssertGreaterThanOrEqual(calories.frame.minY, energyLabel.frame.maxY,
                "Accessibility text must stack the numeric field below its label")
            let screenshot = app.screenshot()
            let shot = XCTAttachment(screenshot: screenshot); shot.name = "Manual nutrition " + appearance; shot.lifetime = .keepAlways; add(shot)
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("manual-nutrition-" + UUID().uuidString + ".png")
            try screenshot.pngRepresentation.write(to: path)
            print("MANUAL_NUTRITION_VISUAL_PATH " + appearance + " " + path.path)
            // Tap near the target's top or bottom edge; the iOS 26 toolbar clamps the capsule to 36 pt despite minHeight.
            let edgeOffset = (save.frame.height / 2 - 4) * (appearance == "--proof-light" ? -1 : 1)
            print("MANUAL_NUTRITION_SAVE_EDGE " + appearance + " frame=\(save.frame) offset=\(edgeOffset)")
            save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: edgeOffset)).tap()
            let meal = app.buttons["mealRow"].firstMatch
            reveal(meal, in: app)
            XCTAssertTrue(meal.waitForExistence(timeout: 10))
            app.terminate()
        }
    }
    func testHistoricalManualEntryLeavesTodayUnchanged() {
        let app = launch(["--diary-history-fixture"])
        let today = app.buttons.matching(identifier: "mealRow").count
        app.tabBars.buttons["Diary"].tap()
        XCTAssertTrue(app.selectDiaryDate("2026-10-18"))
        app.buttons["diaryAddMenu"].tap()
        app.buttons["enterNutritionForDay"].tap(); enter(app, name: "Synthetic historical food", calories: "30")
        app.buttons["saveManualNutrition"].tap()
        let saved = app.buttons["savedDayMealReceipt"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        saved.tap()
        XCTAssertTrue(app.staticTexts["Synthetic historical food"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Time unspecified"].exists)
        XCTAssertTrue(app.staticTexts["2026-10-18"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "mealRow").count, today)
    }
    private func enter(_ app: XCUIApplication, name: String, calories: String) {
        let field = app.textFields["manualFoodName"]; XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(name)
        // The form cannot scroll a field out from under the keyboard, so close it as a person would.
        if app.buttons["doneManualNutrition"].exists { app.buttons["doneManualNutrition"].tap() }
        let kcal = app.textFields["manualCalories"]; reveal(kcal, in: app); kcal.tap(); kcal.typeText(calories)
        if app.buttons["doneManualNutrition"].exists { app.buttons["doneManualNutrition"].tap() }
    }
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-navigation-start-today"] + extra
        if extra.contains("--proof-largest-text") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch(); XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 15)); return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        for _ in 0..<12 {
            // isHittable stays true under the keyboard and the pinned Log meal and Ask Pip bars.
            let covers = [app.keyboards.firstMatch, app.buttons["logMeal"], app.buttons["mealAskPip"]].filter { $0.exists && $0.isHittable }
            if element.exists && element.isHittable && covers.allSatisfy({ element.frame.maxY <= $0.frame.minY }) { return }
            // Drag in the upper list: at accessibility sizes the stacked bar covers the centre.
            let (from, to): (CGFloat, CGFloat) = element.exists && element.frame.minY < list.frame.minY ? (0.12, 0.4) : (0.4, 0.12)
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)))
        }
        XCTFail("Could not reveal \(element.identifier): \(app.debugDescription)")
    }
}
