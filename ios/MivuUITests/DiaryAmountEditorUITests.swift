import XCTest

@MainActor final class DiaryAmountEditorUITests: XCTestCase {
    func testExplicitTotalsAndUntouchedProteinSurviveSaveAndRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english"]
        app.launch()
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 15))
        app.buttons["logMeal"].tap()
        let note = app.textFields["mealText"]
        XCTAssertTrue(note.waitForExistence(timeout: 5)); note.tap(); note.typeText("Synthetic bread")
        if app.buttons["doneMealText"].exists { app.buttons["doneMealText"].tap() }
        app.buttons["sendMeal"].tap()
        openMeal(app)
        openEditor(app)
        replace(app.textFields["itemQuantity"], with: "2")
        replace(app.textFields["itemCalories"], with: "160")
        replace(app.textFields["Protein (g)"], with: "20")
        replace(app.textFields["Carbs (g)"], with: "30")
        app.buttons["Done"].firstMatch.tap()
        app.buttons["saveItem"].tap()
        openEditor(app)
        replace(app.textFields["itemQuantity"], with: "4")
        replace(app.textFields["itemCalories"], with: "160")
        replace(app.textFields["Carbs (g)"], with: "")
        app.buttons["Done"].firstMatch.tap()
        app.buttons["saveItem"].tap()
        XCTAssertTrue(app.buttons["editItem"].firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        openMeal(app); openEditor(app)
        XCTAssertEqual(app.textFields["itemQuantity"].value as? String, "4.0")
        XCTAssertEqual(app.textFields["itemCalories"].value as? String, "160.0")
        reveal(app.textFields["Carbs (g)"], in: app)
        XCTAssertEqual(app.textFields["Protein (g)"].value as? String, "40.0")
        XCTAssertEqual(app.textFields["Carbs (g)"].value as? String, "Unknown")
    }

    private func launchWithMeal(_ text: String = "Synthetic bread") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english"]
        app.launch()
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 15))
        app.buttons["logMeal"].tap()
        let note = app.textFields["mealText"]
        XCTAssertTrue(note.waitForExistence(timeout: 5)); note.tap(); note.typeText(text)
        if app.buttons["doneMealText"].exists { app.buttons["doneMealText"].tap() }
        app.buttons["sendMeal"].tap()
        openMeal(app)
        return app
    }
    private func kcal(_ element: XCUIElement) -> Double? {
        Double(element.label.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).joined())
    }

    func testEditSheetPreviewScalesWithAmount() {
        let app = launchWithMeal(); openEditor(app, details: false)
        let preview = app.descendants(matching: .any)["foodPreviewCalories"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let before = kcal(preview)
        app.buttons["foodScale2"].tap()
        let doubled = NSPredicate { _, _ in self.kcal(preview).map { value in before.map { abs(value - $0 * 2) < 1 } ?? false } ?? false }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: doubled, object: nil)], timeout: 5), .completed, "Preview \(preview.label) from \(before ?? -1)")
    }

    func testAdjustMealTotal() {
        let app = launchWithMeal()
        // The sample meal is far below 650 kcal / 3, so add a 500 kcal food first.
        let add = app.buttons["addFoodManually"]
        reveal(add, in: app, above: app.buttons["mealAskPip"]); add.tap()
        let name = app.textFields["manualFoodName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Synthetic stew")
        let calories = app.textFields["manualCalories"]
        for _ in 0..<4 where !calories.isHittable { app.swipeUp() }
        calories.tap(); calories.typeText("500")
        if app.buttons["doneManualNutrition"].exists { app.buttons["doneManualNutrition"].tap() }
        app.buttons["saveManualNutrition"].tap()
        XCTAssertFalse(app.staticTexts["Not estimated yet"].exists)
        let adjust = app.buttons["adjustMealTotal"]
        for _ in 0..<6 where app.buttons.matching(identifier: "editItem").count < 2 { _ = adjust.waitForExistence(timeout: 2) }
        reveal(adjust, in: app); XCTAssertGreaterThanOrEqual(adjust.frame.height, 44); adjust.tap()
        let field = app.textFields["mealTargetKcal"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replace(field, with: "650")
        let preview = app.descendants(matching: .any)["mealPreviewKcal"].firstMatch
        XCTAssertEqual(kcal(preview), 650, "field=\(field.value ?? "nil") preview=\(preview.exists) \(preview.label)")
        if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
        app.buttons["saveMealTotal"].tap()
        let summary = app.staticTexts["nutritionEnergy"].firstMatch
        let near = NSPredicate { _, _ in summary.exists && abs((Double(summary.label) ?? 0) - 650) <= 10 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: near, object: nil)], timeout: 10), .completed, "Summary showed \(summary.label)")
    }

    func testDeleteFoodRemovesRowAfterConfirm() {
        let app = launchWithMeal()
        let add = app.buttons["addFoodManually"]
        reveal(add, in: app, above: app.buttons["mealAskPip"])
        add.tap()
        let name = app.textFields["manualFoodName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Synthetic milk")
        let calories = app.textFields["manualCalories"]
        for _ in 0..<4 where !calories.isHittable { app.swipeUp() }
        calories.tap(); calories.typeText("80")
        if app.buttons["doneManualNutrition"].exists { app.buttons["doneManualNutrition"].tap() }
        app.buttons["saveManualNutrition"].tap()
        let foods = app.buttons.matching(identifier: "editItem")
        let two = NSPredicate { _, _ in foods.count == 2 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: two, object: nil)], timeout: 10), .completed)
        let milk = foods.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic milk")).firstMatch
        reveal(milk, in: app, above: app.buttons["mealAskPip"])
        milk.tap()
        XCTAssertTrue(app.textFields["itemQuantity"].waitForExistence(timeout: 5))
        let delete = app.buttons["deleteFood"]
        reveal(delete, in: app); delete.tap()
        let confirm = app.buttons["confirmDeleteFood"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let one = NSPredicate { _, _ in foods.count == 1 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: one, object: nil)], timeout: 10), .completed)
        XCTAssertFalse(milk.exists)
    }

    func testOnlyFoodOffersDeleteMealInstead() {
        let app = launchWithMeal(); openEditor(app, details: false)
        reveal(app.buttons["deleteMealFromFood"], in: app)
        XCTAssertFalse(app.buttons["deleteFood"].exists)
        XCTAssertTrue(app.buttons["deleteMealFromFood"].exists)
    }

    func testFoodRowAskPipButtonPrefillsCoach() {
        let app = launchWithMeal()
        let ask = app.buttons["askPipFood"].firstMatch
        XCTAssertTrue(ask.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(ask.frame.height, 44)
        ask.tap()
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        let prefilled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@", "About the "), object: input)
        XCTAssertEqual(XCTWaiter.wait(for: [prefilled], timeout: 10), .completed, "Coach draft was \(input.value ?? "nil")")
        XCTAssertTrue(app.descendants(matching: .any)["coachReplyBar"].waitForExistence(timeout: 5), "The handoff quotes the food")
    }

    func testAskPipAboutFoodPrefillsCoach() {
        let app = launchWithMeal(); openEditor(app, details: false)
        reveal(app.buttons["askPipAboutFood"], in: app)
        app.buttons["askPipAboutFood"].tap()
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        let prefilled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@", "About the "), object: input)
        XCTAssertEqual(XCTWaiter.wait(for: [prefilled], timeout: 10), .completed, "Coach draft was \(input.value ?? "nil")")
    }

    /// After midnight Today shows late-meal receipts that push the row under the Log meal bar.
    private func openMeal(_ app: XCUIApplication) {
        let row = app.buttons["mealRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let bar = app.buttons["logMeal"]
        for _ in 0..<4 where bar.exists && row.frame.maxY > bar.frame.minY { app.collectionViews.firstMatch.swipeUp() }
        row.tap()
    }
    /// Scrolls until `element` sits above any pinned bottom control.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, above bar: XCUIElement? = nil) {
        for _ in 0..<8 {
            let clear = bar.map { !$0.exists || element.frame.maxY <= $0.frame.minY } ?? true
            if element.exists && element.isHittable && clear { return }
            app.swipeUp()
        }
    }
    private func openEditor(_ app: XCUIApplication, details: Bool = true) {
        let edit = app.buttons["editItem"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        for _ in 0..<6 where !edit.isHittable { app.swipeUp() }
        edit.tap()
        XCTAssertTrue(app.textFields["itemQuantity"].waitForExistence(timeout: 5))
        let toggle = app.buttons["foodMoreDetails"]
        if details, toggle.exists, !app.textFields["itemCalories"].exists { toggle.tap() }
    }

    private func replace(_ field: XCUIElement, with value: String) {
        let app = XCUIApplication()
        // isHittable fails outright for an offscreen field, so check the frame first.
        for _ in 0..<6 where !(field.exists && app.windows.firstMatch.frame.intersects(field.frame) && field.isHittable) { app.swipeUp() }
        field.tap(); field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        if let text = field.value as? String, text != "Unknown", !text.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
        }
        if !value.isEmpty { field.typeText(value) }
    }
}
