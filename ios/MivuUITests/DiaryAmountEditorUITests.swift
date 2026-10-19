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
        let row = app.buttons["mealRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
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
        XCTAssertTrue(app.buttons["mealRow"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["mealRow"].firstMatch.tap(); openEditor(app)
        XCTAssertEqual(app.textFields["itemQuantity"].value as? String, "4.0")
        XCTAssertEqual(app.textFields["itemCalories"].value as? String, "160.0")
        XCTAssertEqual(app.textFields["Protein (g)"].value as? String, "40.0")
        XCTAssertEqual(app.textFields["Carbs (g)"].value as? String, "Unknown")
    }

    private func openEditor(_ app: XCUIApplication) {
        let edit = app.buttons["editItem"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        for _ in 0..<6 where !edit.isHittable { app.swipeUp() }
        edit.tap()
        XCTAssertTrue(app.textFields["itemQuantity"].waitForExistence(timeout: 5))
    }

    private func replace(_ field: XCUIElement, with value: String) {
        field.tap(); field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        if let text = field.value as? String, text != "Unknown", !text.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
        }
        if !value.isEmpty { field.typeText(value) }
    }
}
