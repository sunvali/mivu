import XCTest

final class FeedbackUITests: XCTestCase {
    func testSettingsOpensFeedbackForm() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english"]
        app.launch()
        XCTAssertTrue(app.buttons["profileSettings"].waitForExistence(timeout: 15)); app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let row = app.buttons["sendFeedback"], list = app.collectionViews.firstMatch
        for _ in 0..<8 where !row.isHittable { list.swipeUp() }
        row.tap()
        XCTAssertTrue(app.navigationBars["Send feedback"].waitForExistence(timeout: 5))
        for id in ["feedbackKind", "feedbackMessage", "feedbackEmail"] { XCTAssertTrue(app.descendants(matching: .any)[id].firstMatch.exists, id) }
        XCTAssertTrue(app.staticTexts["Your diary is never included."].exists || { app.swipeUp(); return app.staticTexts["Your diary is never included."].exists }())
        let send = app.buttons["feedbackSend"]
        XCTAssertTrue(send.exists); XCTAssertFalse(send.isEnabled)
        let message = app.descendants(matching: .any)["feedbackMessage"].firstMatch // a vertical TextField reports as either field or view
        message.tap(); message.typeText("Synthetic test message")
        XCTAssertTrue(send.isEnabled)
    }
}
