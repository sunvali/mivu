import XCTest

@MainActor final class AppStoreSafetyUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false; executionTimeAllowance = 60 }

    func testNewDiaryRequiresAdultConfirmationAndRemembersIt() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--onboarding-ui-test", "--proof-english"]
        app.launch()
        let confirm = app.buttons["confirmAdultEligibility"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["coachSend"].isHittable)
        confirm.tap()
        let confirmed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [confirmed], timeout: 5), .completed)
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 10))
        XCTAssertFalse(confirm.exists)
    }

    func testGeneratedReplyCanBeReviewedAndCopiedWithoutMail() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 10))
        let text = "Synthetic report source"
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText(text); app.buttons["coachSend"].tap()
        let sent = app.staticTexts.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", text, "coachText-")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 5))
        let id = String(sent.identifier.dropFirst("coachText-".count))
        let answer = app.descendants(matching: .any)["coachExchange-" + id].firstMatch
            .descendants(matching: .any).matching(identifier: "coachReply").firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        answer.press(forDuration: 1)
        let report = app.buttons["Report reply"]
        XCTAssertTrue(report.waitForExistence(timeout: 5)); report.tap()
        XCTAssertTrue(app.navigationBars["Report reply"].waitForExistence(timeout: 5))
        let payload = app.staticTexts["coachReportPayload"]
        XCTAssertTrue(payload.waitForExistence(timeout: 5))
        XCTAssertTrue(payload.label.contains("Selected reply:\nAll set."))
        XCTAssertFalse(payload.label.contains(text))
        let copy = app.buttons["coachReportCopy"]
        for _ in 0..<4 where !copy.isHittable { app.swipeUp() }
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "Copy fallback is available: " + app.debugDescription)
        XCTAssertTrue(copy.isEnabled && copy.isHittable); copy.tap()
        let status = app.staticTexts["coachReportStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Copying does not send a report."))
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Reply report copy fallback"; evidence.lifetime = .keepAlways; add(evidence)
    }

    func testBackupExportSavesLocallyWithoutDestinationPicker() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 10))
        app.buttons["profileSettings"].tap()
        let backup = app.buttons["Backup & export"]
        for _ in 0..<3 where !backup.isHittable { app.swipeUp() }
        XCTAssertTrue(backup.waitForExistence(timeout: 5)); backup.tap()
        let export = app.buttons["exportDiary"]
        XCTAssertTrue(export.waitForExistence(timeout: 5)); export.tap()
        XCTAssertTrue(app.staticTexts["localExportSaved"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Choose private backup folder"].exists)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Local archive export"; evidence.lifetime = .keepAlways; add(evidence)
    }
}
