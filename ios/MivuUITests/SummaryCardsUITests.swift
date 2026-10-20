import XCTest

@MainActor final class SummaryCardsUITests: XCTestCase {
    func testSummaryCardsInBothAppearances() throws {
        for appearance in ["--proof-light", "--proof-dark"] { try exercise(appearance: appearance, largestText: false) }
    }

    func testLargestTextSummaryCardsInBothAppearances() throws {
        for appearance in ["--proof-light", "--proof-dark"] { try exercise(appearance: appearance, largestText: true) }
    }

    private func exercise(appearance: String, largestText: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english", appearance]
        if largestText { app.launchArguments.append("--proof-largest-text") }
        app.launch()
        defer { app.terminate() }
        let variant = appearance + (largestText ? " largest" : " normal")
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        let logMeal = app.buttons["logMeal"]
        XCTAssertTrue(logMeal.isHittable)
        XCTAssertGreaterThanOrEqual(logMeal.frame.height, 44)
        logMeal.tap()
        let note = app.textFields["mealText"]
        XCTAssertTrue(note.waitForExistence(timeout: 5)); note.tap(); note.typeText("Synthetic summary card lunch")
        if app.buttons["doneMealText"].exists { app.buttons["doneMealText"].tap() }
        app.buttons["sendMeal"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        let meal = app.buttons["mealRow"].firstMatch
        reveal(meal, in: app)
        let savedMeal = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Apple"), object: meal)
        XCTAssertEqual(XCTWaiter.wait(for: [savedMeal], timeout: 10), .completed, "The synthetic meal must be an actual saved record")
        try capture("Today meal card " + variant, in: app)
        let dayActions = app.buttons["todayDayActions"]
        for _ in 0..<10 where !dayActions.isHittable { list(in: app).swipeDown() }
        XCTAssertTrue(dayActions.isHittable)
        XCTAssertTrue(logMeal.isHittable)
        if !largestText {
            let protein = app.staticTexts["Protein"].firstMatch
            let carbs = app.staticTexts["Carbs"].firstMatch
            let fat = app.staticTexts["Fat"].firstMatch
            for label in [protein, carbs, fat] { XCTAssertTrue(label.isHittable) }
            XCTAssertEqual(protein.frame.height, carbs.frame.height, accuracy: 1,
                "Protein must remain on the same single line as the other nutrient labels")
            XCTAssertLessThanOrEqual(protein.frame.height, app.staticTexts["kcal recorded"].frame.height,
                "The smaller nutrient caption must not wrap into two lines")
            XCTAssertLessThan(protein.frame.maxX, carbs.frame.minX)
            XCTAssertLessThan(carbs.frame.maxX, fat.frame.minX)
            XCTAssertLessThanOrEqual(fat.frame.maxY, logMeal.frame.minY)
        }
        try capture("Today intake card " + variant, in: app)

        app.tabBars.buttons["Diary"].tap()
        XCTAssertTrue(app.navigationBars["Diary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.diaryPills.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.diaryPills.matching(NSPredicate(format: "selected == true")).firstMatch.label.contains("1 meal"))
        reveal(app.buttons["historyMeal"].firstMatch, in: app)
        try capture("Diary day card " + variant, in: app)

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reportWeekly"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["reportWeekly"].isSelected)
        try capture("Progress intake card " + variant, in: app)
        let data = app.staticTexts["nutritionData"]
        reveal(data, in: app)
        XCTAssertEqual(data.label, "Recorded intake data")
        try capture("Progress trend card " + variant, in: app)
    }

    private func list(in app: XCUIApplication) -> XCUIElement {
        app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<14 where !element.isHittable {
            let native = list(in: app)
            if element.exists, element.frame.minY < native.frame.minY { native.swipeDown() }
            else { native.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ name: String, in app: XCUIApplication) throws {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("summary-card-" + UUID().uuidString + ".png")
        try screenshot.pngRepresentation.write(to: path)
        print("SUMMARY_VISUAL_PATH " + path.path)
    }
}
