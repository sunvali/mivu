import XCTest

/// Pip's daily observation, pinned by `--pip-notice-fixture`; the rules that pick it are unit tested.
final class PipNoticeUITests: XCTestCase {
    private let sentence = "Protein came in short on 9 of your last 12 logged days."
    private let ask = "My protein has been short of my target lately. Give me easy ways to add some."

    override func setUp() { continueAfterFailure = false }

    /// Yesterday has a lunch and today is empty, so the morning card shows; the app opens on Coach.
    private func launch(_ id: String, connected: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", id, "--coach-ui-test", "--quick-prompts-fixture",
                               "--quick-prompts-hour", "9", "--pip-notice-fixture", "--proof-english"]
        if connected { app.launchArguments.append("--coach-inference-fixture") }
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        return app
    }
    private func text(_ value: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }
    private func chips(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coachQuickPrompt-"))
    }

    func testPipNoticeInCoachAndMorningCard() {
        let id = UUID().uuidString
        var app = launch(id)
        let strip = app.descendants(matching: .any)["coachCompanionStrip"].firstMatch
        XCTAssertTrue(strip.staticTexts[sentence].waitForExistence(timeout: 10), "Pip says what he noticed in place of his greeting")
        let offer = app.buttons["coachQuickPrompt-pip.notice"]
        XCTAssertTrue(offer.waitForExistence(timeout: 5))
        XCTAssertEqual(offer.label, "Easy ways to add protein")
        XCTAssertEqual(chips(in: app).element(boundBy: 0).identifier, "coachQuickPrompt-pip.notice", "Pip's offer leads the row")
        XCTAssertGreaterThanOrEqual(offer.frame.height, 44)

        app.tabBars.buttons["Today"].tap()
        let line = app.staticTexts["morningPipNotice"]
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        XCTAssertEqual(line.label, sentence)
        let cardOffer = app.buttons["morningPipOffer"]
        XCTAssertTrue(cardOffer.exists)
        XCTAssertEqual(cardOffer.label, "Easy ways to add protein")
        XCTAssertGreaterThanOrEqual(cardOffer.frame.height, 44)

        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(offer.waitForExistence(timeout: 5))
        offer.tap()
        XCTAssertTrue(text(ask, in: app).waitForExistence(timeout: 10), "The offer sends its message to Coach")
        XCTAssertFalse(offer.waitForExistence(timeout: 2), "The offer leaves once it is used")
        XCTAssertFalse(strip.staticTexts[sentence].exists, "So does the sentence")

        app.terminate()
        app = launch(id)
        XCTAssertFalse(app.buttons["coachQuickPrompt-pip.notice"].waitForExistence(timeout: 3), "It does not come back the same day")
        XCTAssertFalse(app.descendants(matching: .any)["coachCompanionStrip"].firstMatch.staticTexts[sentence].exists)
    }

    func testMorningCardOfferOpensCoachWithItsMessage() {
        let app = launch(UUID().uuidString)
        app.tabBars.buttons["Today"].tap()
        let cardOffer = app.buttons["morningPipOffer"]
        XCTAssertTrue(cardOffer.waitForExistence(timeout: 10))
        cardOffer.tap()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 10), "The offer opens Coach")
        XCTAssertTrue(text(ask, in: app).waitForExistence(timeout: 10), "with its message sent")
        XCTAssertFalse(app.buttons["coachQuickPrompt-pip.notice"].exists)
        app.tabBars.buttons["Today"].tap()
        XCTAssertFalse(app.staticTexts["morningPipNotice"].waitForExistence(timeout: 2), "Used once, the notice leaves Today too")
    }

    /// An offer nobody can answer would be a dead end, so without a connection Pip keeps to the observation on Today.
    func testNoOfferWhenCoachCannotAnswer() {
        let app = launch(UUID().uuidString, connected: false)
        XCTAssertFalse(app.buttons["coachQuickPrompt-pip.notice"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Today"].tap()
        let line = app.staticTexts["morningPipNotice"]
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        XCTAssertEqual(line.label, sentence)
        XCTAssertFalse(app.buttons["morningPipOffer"].exists)
    }

    func testSwitchInSettingsTurnsItOff() {
        let id = UUID().uuidString
        var app = launch(id)
        let strip = app.descendants(matching: .any)["coachCompanionStrip"].firstMatch
        XCTAssertTrue(strip.staticTexts[sentence].waitForExistence(timeout: 10))
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["morningPipNotice"].waitForExistence(timeout: 10))
        app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let toggle = app.switches["pipNoticesToggle"]
        for _ in 0..<8 where !(toggle.exists && toggle.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.value as? String, "1", "On by default")
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44)
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertFalse(app.staticTexts["morningPipNotice"].waitForExistence(timeout: 2), "Today drops it at once")
        app.tabBars.buttons["Coach"].tap()
        XCTAssertFalse(app.buttons["coachQuickPrompt-pip.notice"].waitForExistence(timeout: 2))
        XCTAssertFalse(strip.staticTexts[sentence].exists, "Coach drops it at once")

        // Off survives a relaunch, and switching it back on brings today's unused notice back without another launch.
        app.terminate()
        app = launch(id)
        XCTAssertFalse(app.buttons["coachQuickPrompt-pip.notice"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Today"].tap()
        XCTAssertFalse(app.staticTexts["morningPipNotice"].waitForExistence(timeout: 2))
        app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let again = app.switches["pipNoticesToggle"]
        for _ in 0..<8 where !(again.exists && again.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertEqual(again.value as? String, "0")
        again.switches.firstMatch.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["morningPipNotice"].waitForExistence(timeout: 5), "Switched on, Pip's notice shows the same day")
    }
}
