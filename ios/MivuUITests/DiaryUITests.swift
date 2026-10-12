import XCTest

@MainActor final class DiaryUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 15))
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for index in 0..<9 where !element.isHittable {
            if element.exists, element.frame.maxY < 120 { app.collectionViews.firstMatch.swipeDown() }
            else if index < 3 { app.collectionViews.firstMatch.swipeUp() }
            else { app.collectionViews.firstMatch.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }
    private func replace(_ field: XCUIElement, with value: String) {
        field.tap()
        if let text = field.value as? String, !text.isEmpty { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count)) }
        field.typeText(value)
    }

    func testCapturePhotoReviewCorrectionEditingAndHistory() {
        let app = launch(["--proof-hebrew", "-AppleLanguages", "(he)", "-AppleLocale", "he_IL"])
        app.buttons["logMeal"].tap()
        let field = app.textFields["mealText"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.navigationBars.buttons["Cancel"].frame.midX, app.buttons["sendMeal"].frame.midX)
        field.tap(); field.typeText("Synthetic lunch")
        if app.buttons["doneMealText"].exists { app.buttons["doneMealText"].tap() }
        app.buttons["syntheticPhoto"].tap()
        let review = app.switches["reviewFirst"]
        let toggle = review.switches.firstMatch
        reveal(toggle, in: app); toggle.tap()
        guard review.value as? String == "1" else {
            let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Review switch input failure"; attachment.lifetime = .keepAlways; add(attachment)
            print("REVIEW_SWITCH_INPUT_STATE\n" + review.debugDescription)
            XCTFail("Review switch must be on before sending"); return
        }
        app.buttons["sendMeal"].tap()
        let row = app.buttons["mealRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); reveal(row, in: app); row.tap()
        let accept = app.buttons["acceptReview"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10)); reveal(accept, in: app); accept.tap()
        let half = app.buttons["halfPortion"]
        reveal(half, in: app); XCTAssertTrue(half.isEnabled); half.tap()
        let edit = app.buttons["editItem"].firstMatch
        reveal(edit, in: app); edit.tap()
        let quantity = app.textFields["itemQuantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.navigationBars.buttons["Cancel"].frame.midX, app.buttons["saveItem"].frame.midX)
        let itemScreen = XCTAttachment(screenshot: app.screenshot()); itemScreen.name = "English item editor"; itemScreen.lifetime = .keepAlways; add(itemScreen)
        replace(quantity, with: "2")
        app.buttons["saveItem"].tap()
        XCTAssertTrue(app.staticTexts["190"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        let weight = app.buttons["logWeight"]
        reveal(weight, in: app); weight.tap()
        let input = app.textFields["weightInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.navigationBars.buttons["Cancel"].frame.midX, app.buttons["saveWeight"].frame.midX)
        let weightScreen = XCTAttachment(screenshot: app.screenshot()); weightScreen.name = "English weight sheet"; weightScreen.lifetime = .keepAlways; add(weightScreen)
        input.tap(); input.typeText("70")
        app.buttons["saveWeight"].tap()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["70 kg"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Synthetic diary history"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testCancelDoesNotCreateMealAndProfilesRemainSeparate() {
        let app = launch()
        app.buttons["logMeal"].tap()
        let text = app.textFields["mealText"]; XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap(); text.typeText("Unsaved synthetic input")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["mealRow"].firstMatch.exists)
        let settings = app.tabBars.buttons["Settings"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: settings)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else { XCTFail("Settings must be reachable after composer dismissal"); return }
        settings.tap()
        let create = app.buttons["Create local profile"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        let name = app.alerts.textFields.firstMatch; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.typeText("Synthetic second profile")
        app.alerts.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic second profile"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["mealRow"].firstMatch.exists)
    }

    private func capturePhotoOnlyReview(in app: XCUIApplication) -> XCUIElement {
        app.buttons["logMeal"].tap()
        XCTAssertTrue(app.buttons["syntheticPhoto"].waitForExistence(timeout: 5))
        app.buttons["syntheticPhoto"].tap()
        let review = app.switches["reviewFirst"]
        let toggle = review.switches.firstMatch; reveal(toggle, in: app); toggle.tap()
        XCTAssertEqual(review.value as? String, "1")
        app.buttons["sendMeal"].tap()
        let row = app.buttons["mealRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        return row
    }

    func testPhotoOnlyReviewHasReadableMealTitle() {
        let app = launch()
        let row = capturePhotoOnlyReview(in: app)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Photo-only review meal title"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(row.label.contains("Meal"), "Photo-only pending/review meals need a readable fallback title; actual label: " + row.label)
    }

    func testEnglishDarkLargeTextRendering() {
        let app = launch(["--proof-hebrew", "--proof-dark", "--proof-largest-text", "-AppleLanguages", "(he)", "-AppleLocale", "he_IL"])
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Apple sample mode"].exists)
        XCTAssertTrue(app.buttons["logMeal"].isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "English dark largest accessibility5 Today"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testLegacyHebrewLaunchUsesEnglishLeftToRight() {
        let app = launch(["--proof-hebrew", "-AppleLanguages", "(he)", "-AppleLocale", "he_IL"])
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "English legacy Hebrew launch"; attachment.lifetime = .keepAlways; add(attachment)
        guard app.navigationBars["Today"].waitForExistence(timeout: 5) else { XCTFail("Legacy Hebrew settings must still open English Today"); return }
        XCTAssertTrue(app.staticTexts["Apple sample mode"].exists)
        let today = app.tabBars.buttons["Today"], history = app.tabBars.buttons["History"], settings = app.tabBars.buttons["Settings"]
        XCTAssertLessThan(today.frame.midX, history.frame.midX)
        XCTAssertLessThan(history.frame.midX, settings.frame.midX)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.segmentedControls.count, 0)
        XCTAssertTrue(app.staticTexts["My diary"].exists)
        let diagnostic = app.buttons["ChatGPT connection diagnostic"]
        reveal(diagnostic, in: app); diagnostic.tap()
        XCTAssertTrue(app.staticTexts["Connection test"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.segmentedControls.count, 0)
        XCTAssertGreaterThan(app.buttons["Done"].frame.midX, app.frame.midX)
        XCTAssertLessThan(app.staticTexts["Connection test"].frame.minX, app.frame.midX)
        let diagnosticScreen = XCTAttachment(screenshot: app.screenshot()); diagnosticScreen.name = "English connection diagnostic"; diagnosticScreen.lifetime = .keepAlways; add(diagnosticScreen)
    }
}
