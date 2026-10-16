import XCTest

@MainActor final class CoachActivityUITests: XCTestCase {
    func testReceiptOpensNativeBackupSettingsWithoutStartingFilesAction() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Open backup settings")
        app.buttons["coachSend"].tap()
        let handoff = app.buttons["coachSettingsLink"]
        XCTAssertTrue(handoff.waitForExistence(timeout: 15))
        XCTAssertTrue(handoff.label.contains("Open backup and Files"))
        XCTAssertFalse(app.descendants(matching: .any)["coachActivity"].exists)
        handoff.tap()
        XCTAssertTrue(app.navigationBars["Backup & export"].waitForExistence(timeout: 5))
        let folder = app.buttons["Choose private backup folder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        XCTAssertTrue(folder.isHittable)
        XCTAssertFalse(app.navigationBars["Browse"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["doneSettings"].tap()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Coach"].isSelected)
        XCTAssertTrue(app.textFields["coachInput"].isHittable)
    }
}
