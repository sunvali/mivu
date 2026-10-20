import XCTest

/// One critical journey; exhaustive appearance, paging and editor checks stay in Mivu.
@MainActor final class SmokeUITests: XCTestCase {
    func testOfflineCaptureSurvivesRelaunchAndNavigation() {
        continueAfterFailure = false
        executionTimeAllowance = 60
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5))
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText("Synthetic smoke lunch")
        app.buttons["coachPhotos"].tap()
        let photo = app.buttons["syntheticPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 3))
        photo.tap()
        let send = app.buttons["coachSend"]
        XCTAssertTrue(send.isHittable)
        send.tap()
        XCTAssertTrue(app.staticTexts["Synthetic smoke lunch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Waiting for an authorized connection"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic smoke lunch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Waiting for an authorized connection"].exists)
        for tab in ["Today", "Diary", "Progress", "Coach"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.isHittable)
            button.tap()
            XCTAssertTrue(button.isSelected)
        }
        app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons["doneSettings"].tap()
        XCTAssertTrue(app.tabBars.buttons["Coach"].isSelected)
    }
}
