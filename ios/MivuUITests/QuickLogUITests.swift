import XCTest

@MainActor final class QuickLogUITests: XCTestCase {
    func testLogFoodOpensCameraLogsPhotoOnTodayAndOffersNote() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english", "--quick-log"]
        app.launch()
        // The simulator has no camera, so the synthetic photo stands in for the shutter.
        let photo = app.buttons["quickLogSyntheticPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["quickLogClose"].exists)
        photo.tap()
        let addNote = app.buttons["quickLogAddNote"]
        XCTAssertTrue(addNote.waitForExistence(timeout: 10))
        // The toast hides itself after 5 seconds, so use it before any slower wait.
        XCTAssertGreaterThanOrEqual(addNote.frame.height, 44)
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        addNote.tap()
        XCTAssertTrue(app.textFields["mealText"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        let discard = app.buttons["Discard changes"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }
        XCTAssertTrue(app.buttons["mealRow"].firstMatch.waitForExistence(timeout: 10))
    }

    func testSnapItOnTodayIsVisibleAtLaunchAndOpensCamera() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english"]
        app.launch()
        let snapIt = app.buttons["snapIt"]
        XCTAssertTrue(snapIt.waitForExistence(timeout: 15))
        XCTAssertTrue(snapIt.isHittable, "Snap It is on screen as soon as Today opens")
        XCTAssertGreaterThanOrEqual(snapIt.frame.height, 44)
        XCTAssertTrue(snapIt.label.contains("Instant photo log"), "The caption separates Snap It from chatting with Pip")
        XCTAssertLessThan(snapIt.frame.maxY, app.buttons["logMeal"].frame.minY, "Snap It leads the capture bar")
        snapIt.tap()
        let photo = app.buttons["quickLogSyntheticPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.tap()
        XCTAssertTrue(app.buttons["quickLogAddNote"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["mealRow"].firstMatch.waitForExistence(timeout: 10))
    }

    func testLargestTextPairsPipAndManualAsIconsUnderSnapIt() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-navigation-start-today",
                               "--proof-english", "--proof-largest-text"]
        app.launch()
        let snapIt = app.buttons["snapIt"], pip = app.buttons["logMeal"], manual = app.buttons["addManually"]
        XCTAssertTrue(snapIt.waitForExistence(timeout: 15))
        XCTAssertTrue(snapIt.isHittable)
        XCTAssertEqual(pip.frame.midY, manual.frame.midY, accuracy: 2, "Icons share one row so the bar leaves room for the day")
        XCTAssertLessThan(snapIt.frame.maxY, pip.frame.minY)
        XCTAssertEqual(pip.label, "Chat with Pip")
        XCTAssertEqual(manual.label, "Add manually")
        XCTAssertGreaterThanOrEqual(manual.frame.height, 44)
    }

    func testCameraRequestWaitsForTheDiaryChooser() {
        let id = UUID().uuidString, app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", id, "--proof-english"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 15))
        app.terminate()
        app.launchArguments += ["-diarySignedOut", "YES", "--quick-log"]
        app.launch()
        let diary = app.buttons["My diary"]
        XCTAssertTrue(diary.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["quickLogSyntheticPhoto"].exists)
        diary.tap()
        XCTAssertTrue(app.buttons["quickLogSyntheticPhoto"].waitForExistence(timeout: 10))
    }

    func testOpenCoachRequestLandsOnCoach() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english", "--open-coach"]
        app.launch()
        let coach = app.tabBars.buttons["Coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: 15))
        let selected = NSPredicate(format: "isSelected == true")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: selected, object: coach)], timeout: 10), .completed)
    }
}
