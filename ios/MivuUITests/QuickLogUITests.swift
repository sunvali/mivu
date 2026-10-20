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
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        XCTAssertTrue(app.buttons["mealRow"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(addNote.frame.height, 44)
        addNote.tap()
        XCTAssertTrue(app.textFields["mealText"].waitForExistence(timeout: 5))
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
