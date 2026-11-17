import XCTest

@MainActor final class TimeZoneTravelUITests: XCTestCase {
    func testZoneChangeShowsToastAndKeepPinsWithHeaderTag() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english", "--time-zone-ui-test"]
        app.launch()
        let toast = app.descendants(matching: .any)["timeZoneToast"].firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Now on New York time"].exists)
        add(XCTAttachment(screenshot: app.screenshot()).named("t6-toast"))
        let keep = app.buttons["timeZoneKeep"]
        XCTAssertGreaterThanOrEqual(keep.frame.height, 44)
        keep.tap()
        // The forward chevron is decorative, so VoiceOver reads the label without a trailing arrow.
        let tag = app.buttons["pinnedZoneTag"]
        XCTAssertTrue(tag.waitForExistence(timeout: 5))
        XCTAssertEqual(tag.label, "Jerusalem time")
        XCTAssertFalse(toast.exists)
        add(XCTAttachment(screenshot: app.screenshot()).named("t6-tag"))
        tag.tap()
        app.buttons["Use New York time"].tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: tag)], timeout: 5) == .completed)
    }
}

private extension XCTAttachment {
    func named(_ name: String) -> XCTAttachment { self.name = name; lifetime = .keepAlways; return self }
}
